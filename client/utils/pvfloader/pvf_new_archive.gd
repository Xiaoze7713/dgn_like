class_name PvfNewArchive
extends RefCounted
## 新版国服 Script.pvf（外层 AES 分段 + 内层 nkpi）只读容器。
##
## 这是运行时的原生读取层：不依赖 build_pack.py 产出的 JSON / sqlite，
## 直接打开客户端目录里的 Script.pvf。算法与 tools/pvf_new_unwrap.py、
## tools/pvf_new_extract.py 对齐：
##   - DNF.exe 里取 RSA 私钥 PEM 与其后第一个 64-hex wrapKey
##   - sk.dat 每 128 B 一块 RSA/PKCS#1 v1.5 -> 117 B，拼起来 AES-256-CBC(零 IV)
##     解前 L-L%256 字节，得到 82 把 32 B 的段密钥
##   - Script.pvf 每 10 MiB 段前 0x2800 B 用段密钥 AES-CBC 解；其余字节是明文
##   - 内层 nkpi：iNfO 头、24 B 文件表、HSrm、stAs/stWs 名字池、Gidx 组表、
##     mAIn 分块（zlib），流密码 magic 0x269EC3 / 字符串池 0x269EC9
##
## 性能：内层文件表 6.29M 条；这里先按需线性扫表，第一次查某个路径会慢，
## 命中后进 `_entries` 缓存。后续可换成 hash 索引，不改变对上接口。

const SEG := 0xA00000
const HDR := 0x2800
const HEADER_SIZE := 0x30
const FILE_ITEM_SIZE := 0x18
const GROUP_ITEM_SIZE := 8
const MAGIC_PROTECTED := 0x269EC3
const MAGIC_PSTRING := 0x269EC9
const M32 := 0xFFFFFFFF
const POOL_XOR_A := 0xE7ADF7EA
const POOL_XOR_W := 0xB8DEA7AC

var script_path := ""
var exe_path := ""
var sk_path := ""
var last_error := ""
var is_open := false

var file_count := 0
var body_size := 0
var group_count := 0
var hash_size := 0
var name_size := 0

var _file: FileAccess = null
var _table_off := 0
var _hash_off := 0
var _name_off := 0
var _group_off := 0
var _body_off := 0
var _str_a := PackedByteArray()
var _str_w := PackedByteArray()
var _groups: Array[Vector2i] = []
var _chain := PackedByteArray()
var _entries := {}       # path -> Vector4i(chunk, off, size, dtype)
var _path_cache := {}    # lower path -> resolved path / ""（未找到）
var _dir_index := {}     # dir -> Array[int] global entry index
var _dir_index_built := false
var _chunk_cache := {}   # chunk index -> PackedByteArray（只做小 LRU，后面接内容缓存）
var _chunk_order: Array[int] = []
const MAX_CHUNKS := 24


func open(p_script: String, p_exe := "", p_sk := "") -> Error:
	p_script = PathUtil.native(p_script)
	if not p_exe.is_empty():
		p_exe = PathUtil.native(p_exe)
	if not p_sk.is_empty():
		p_sk = PathUtil.native(p_sk)
	close()
	script_path = p_script
	exe_path = p_exe
	sk_path = p_sk
	if not FileAccess.file_exists(script_path):
		return _fail("找不到 Script.pvf：%s" % script_path)
	if exe_path.is_empty():
		exe_path = script_path.get_base_dir().path_join("DNF.exe")
	if sk_path.is_empty():
		sk_path = script_path.get_base_dir().path_join("sk.dat")
	if not FileAccess.file_exists(exe_path) or not FileAccess.file_exists(sk_path):
		return _fail("缺少 DNF.exe 或 sk.dat：%s / %s" % [exe_path, sk_path])

	var err := _load_chain()
	if err != OK:
		return err
	_file = FileAccess.open(script_path, FileAccess.READ)
	if _file == null:
		return _fail("打不开 Script.pvf：%s" % script_path)
	err = _read_layout()
	if err != OK:
		close()
		return err
	is_open = true
	last_error = ""
	return OK


func index_ready() -> bool:
	return is_open and _file != null and file_count > 0


func close() -> void:
	if _file != null:
		_file.close()
	_file = null
	is_open = false
	_str_a = PackedByteArray()
	_str_w = PackedByteArray()
	_groups.clear()
	_chain = PackedByteArray()
	_entries.clear()
	_path_cache.clear()
	_chunk_cache.clear()
	_chunk_order.clear()


func _fail(msg: String) -> Error:
	last_error = msg
	LogUtil.error("[PvfNewArchive] " + msg)
	return ERR_FILE_CORRUPT


# =====================================================================
# 外层密钥
# =====================================================================
func _load_chain() -> Error:
	var exe := FileAccess.get_file_as_bytes(exe_path)
	if exe.is_empty():
		return _fail("DNF.exe 读取为空")
	var begin := "-----BEGIN".to_ascii_buffer()
	var endm := "-----END".to_ascii_buffer()
	var dash := "-----".to_ascii_buffer()
	var start := _find_sub(exe, begin, 0)
	if start < 0:
		return _fail("DNF.exe 里没有 PRIVATE KEY")
	var e := _find_sub(exe, endm, start)
	if e < 0:
		return _fail("PRIVATE KEY 没有 END")
	e = _find_sub(exe, dash, e + 9)
	if e < 0:
		return _fail("PRIVATE KEY 结束标记不完整")
	var pem := exe.slice(start, e + 5).get_string_from_ascii()
	var win := exe.slice(e + 5, mini(e + 5 + 0x800, exe.size()))
	var wrap_hex := _first_hex64(win)
	if wrap_hex.length() != 64:
		return _fail("没找到 64-hex wrapKey")
	var key := CryptoKey.new()
	if key.load_from_string(pem, false) != OK:
		return _fail("RSA 私钥载入失败")
	var crypto := Crypto.new()
	var sk := FileAccess.get_file_as_bytes(sk_path)
	if sk.size() % 128 != 0:
		_fail("sk.dat 长度不是 128 的倍数：%d" % sk.size())
	var plain := PackedByteArray()
	for i in range(sk.size() / 128):
		var block := sk.slice(i * 128, (i + 1) * 128)
		var dec := crypto.decrypt(key, block)
		if dec.is_empty():
			return _fail("sk.dat 第 %d 块 RSA 解密失败" % i)
		plain.append_array(dec)
	if plain.size() < 256:
		return _fail("sk.dat 解密结果太短：%d" % plain.size())
	var pre := plain.size() - (plain.size() % 256)
	var aes := AESContext.new()
	var iv := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	if aes.start(AESContext.MODE_CBC_DECRYPT, wrap_hex.hex_decode(), iv) != OK:
		return _fail("wrapKey AES 启动失败")
	var mid := aes.update(plain.slice(0, pre))
	aes.finish()
	_chain = mid + plain.slice(pre)
	if _chain.size() < 32:
		return _fail("段密钥链为空")
	return OK


func _find_sub(b: PackedByteArray, needle: PackedByteArray, from: int) -> int:
	if needle.is_empty():
		return -1
	var p := from
	while p < b.size():
		p = b.find(needle[0], p)
		if p < 0 or p + needle.size() > b.size():
			return -1
		if b.slice(p, p + needle.size()) == needle:
			return p
		p += 1
	return -1


func _first_hex64(b: PackedByteArray) -> String:
	var run := 0
	var start := -1
	for i in b.size():
		var c := b[i]
		var is_hex := (c >= 48 and c <= 57) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102)
		if is_hex:
			if run == 0:
				start = i
			run += 1
			if run == 64:
				return b.slice(start, start + 64).get_string_from_ascii()
		else:
			run = 0
	return ""


# =====================================================================
# 段读取：只解每段前 0x2800
# =====================================================================
func _read_seg(seg: int, off_in_seg: int, size: int) -> PackedByteArray:
	var abs_off := seg * SEG + off_in_seg
	_file.seek(abs_off)
	var raw := _file.get_buffer(size)
	if off_in_seg >= HDR:
		return raw
	var enc_len := mini(HDR - off_in_seg, raw.size())
	if enc_len <= 0:
		return raw
	var key_off := seg * 32
	if key_off + 32 > _chain.size():
		return raw
	var aes := AESContext.new()
	var iv := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	if aes.start(AESContext.MODE_CBC_DECRYPT, _chain.slice(key_off, key_off + 32), iv) != OK:
		return raw
	# CBC 要求按 16 B 对齐；段首读取长度可能不是 16 的倍数
	var aligned := enc_len - (enc_len % 16)
	if aligned > 0:
		var dec := aes.update(raw.slice(0, aligned))
		raw = dec + raw.slice(aligned)
	aes.finish()
	return raw


func _read_plain(abs_off: int, size: int) -> PackedByteArray:
	if size <= 0:
		return PackedByteArray()
	var out := PackedByteArray()
	var pos := abs_off
	var left := size
	while left > 0:
		var seg := pos / SEG
		var in_seg := pos % SEG
		var take := mini(left, SEG - in_seg)
		out.append_array(_read_seg(seg, in_seg, take))
		pos += take
		left -= take
	return out


# =====================================================================
# 内层布局
# =====================================================================
func _read_layout() -> Error:
	var head := _read_seg(0, 0, HDR)
	if head.size() < HEADER_SIZE:
		return _fail("Script.pvf 头部太短")
	var plain := _decrypt_protected("iNfO", head.slice(0, HEADER_SIZE), MAGIC_PROTECTED)
	if plain.slice(0, 4).get_string_from_ascii() != "nkpi":
		return _fail("内层 magic 不是 nkpi：%s" % plain.slice(0, 4).hex_encode())
	file_count = plain.decode_s32(24)
	body_size = plain.decode_s32(32)
	group_count = plain.decode_s32(36)
	hash_size = plain.decode_s32(40)
	name_size = plain.decode_s32(44)
	if file_count <= 0 or file_count > 8_000_000:
		return _fail("file_count 不合理：%d" % file_count)
	_table_off = HEADER_SIZE
	_hash_off = _table_off + file_count * FILE_ITEM_SIZE
	_name_off = _hash_off + hash_size
	_group_off = _name_off + name_size
	_body_off = _group_off + group_count * GROUP_ITEM_SIZE
	if _body_off + body_size != _file.get_length():
		return _fail("布局不自洽：%d+%d != %d" % [_body_off, body_size, _file.get_length()])

	var names := _read_plain(_name_off, name_size)
	if names.size() < 8:
		return _fail("名字池太短")
	var pos := 8
	var a := _read_pool(names, pos, "stAs", POOL_XOR_A)
	if a.is_empty():
		return _fail("stAs 池解码失败")
	pos = a[1]
	_str_a = a[0]
	var w := _read_pool(names, pos, "stWs", POOL_XOR_W)
	if w.is_empty():
		return _fail("stWs 池解码失败")
	_str_w = w[0]

	var gid := _read_plain(_group_off, group_count * GROUP_ITEM_SIZE)
	if gid.size() != group_count * GROUP_ITEM_SIZE:
		return _fail("Gidx 组表截断")
	var gplain := _decrypt_protected("Gidx", gid, MAGIC_PROTECTED)
	_groups.clear()
	for i in group_count:
		_groups.append(Vector2i(gplain.decode_s32(i * 8), gplain.decode_s32(i * 8 + 4)))
	return OK


func _read_pool(names: PackedByteArray, pos: int, key: String, xor_const: int) -> Array:
	if pos + 8 > names.size():
		return []
	var enc_raw := names.decode_u32(pos)
	var orig_raw := names.decode_u32(pos + 4)
	pos += 8
	var enc_size := enc_raw ^ xor_const
	if pos + enc_size > names.size():
		return []
	var blob := _decrypt_protected(key, names.slice(pos, pos + enc_size), MAGIC_PSTRING)
	var want := orig_raw ^ enc_size
	var out := _zlib(blob, want)
	if want >= 0 and out.size() != want:
		return []
	return [out, pos + enc_size]


# =====================================================================
# 流密码 / zlib
# =====================================================================
func _keystream(key: String, magic: int, nbytes: int) -> PackedByteArray:
	var kb := key.to_utf16_buffer()
	while kb.size() < 8:
		kb.append(0)
	var w0 := kb.decode_u16(0)
	var w1 := kb.decode_u16(2)
	var w2 := kb.decode_u16(4)
	var w3 := kb.decode_u16(6)
	var seed := (0x339E9711 * w0 + 0x393 * (w3 + 0x393 * (w2 + 0x393 * w1))) & M32
	var out := PackedByteArray()
	out.resize(nbytes)
	var i := 0
	while i + 4 <= nbytes:
		var t1 := (0x343FD * seed + magic) & M32
		seed = (0x343FD * t1 + magic) & M32
		var k := ((t1 & 0xFFFF0000) + (seed >> 16)) & M32
		out.encode_u32(i, k)
		i += 4
	if i < nbytes:
		var t1 := (0x343FD * seed + magic) & M32
		var t2 := (0x343FD * t1 + magic) & M32
		var k := ((t1 & 0xFFFF0000) + ((t2 >> 16) & 0xFFFF)) & M32
		for j in range(i, nbytes):
			out[j] = (k >> (8 * (j - i))) & 0xFF
	return out


func _decrypt_protected(key: String, data: PackedByteArray, magic: int) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()
	var ks := _keystream(key, magic, data.size())
	var out := data.duplicate()
	for i in data.size():
		out[i] = data[i] ^ ks[i]
	return out


func _zlib(data: PackedByteArray, want := -1) -> PackedByteArray:
	if data.is_empty() or want == 0:
		return PackedByteArray()
	if want >= 0:
		return data.decompress(want, FileAccess.COMPRESSION_DEFLATE)
	return data.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)


# =====================================================================
# 字符串 / 条目
# =====================================================================
func resolve(v: int) -> String:
	if v < 0:
		return ""
	if v & 1:
		var start := (v >> 1) * 2
		if start >= _str_w.size():
			return ""
		var end := start
		while end + 1 < _str_w.size() and not (_str_w[end] == 0 and _str_w[end + 1] == 0):
			end += 2
		return _str_w.slice(start, end).get_string_from_utf16()
	var s := v >> 1
	if s >= _str_a.size():
		return ""
	var e := _str_a.find(0, s)
	if e < 0:
		return ""
	return _str_a.slice(s, e).get_string_from_utf8()


func _entry_at(i: int) -> Vector4i:
	_file.seek(_table_off + i * FILE_ITEM_SIZE)
	var b := _file.get_buffer(FILE_ITEM_SIZE)
	return Vector4i(b.decode_s32(8), b.decode_s32(12), b.decode_s32(16), b.decode_s32(20))


func _path_at(i: int) -> String:
	_file.seek(_table_off + i * FILE_ITEM_SIZE)
	var b := _file.get_buffer(FILE_ITEM_SIZE)
	var no := b.decode_s32(0)
	var po := b.decode_s32(4)
	var d := resolve(po)
	var n := resolve(no)
	var p: String = (d + "/" + n) if (d != "" and n != "") else (d if d != "" else n)
	return p.replace("\\", "/").lstrip("./").strip_edges()


func find(path: String) -> Vector4i:
	var low := path.to_lower().lstrip("./")
	if _entries.has(low):
		return _entries[low]
	if _path_cache.has(low):
		return Vector4i(-1, -1, -1, -1)
	if not _dir_index_built:
		_build_dir_index()
	var want_dir := low.get_base_dir()
	var want_name := low.get_file()
	var want_name_b := want_name.to_utf16_buffer()
	var list: Array = _dir_index.get(want_dir, [])
	for gi in list:
		var e := _entry_at(gi)
		if e.x < 0:
			continue
		if _name_equals(_table_name_at(gi), want_name_b):
			_entries[low] = e
			return e
	_path_cache[low] = true
	return Vector4i(-1, -1, -1, -1)


func _build_dir_index() -> void:
	_dir_index_built = true
	var dir_cache := {}
	const BATCH := 65536
	var base := 0
	while base < file_count:
		var n := mini(BATCH, file_count - base)
		_file.seek(_table_off + base * FILE_ITEM_SIZE)
		var buf := _file.get_buffer(n * FILE_ITEM_SIZE)
		for i in n:
			var o := i * FILE_ITEM_SIZE
			var po := buf.decode_s32(o + 4)
			var d: String
			if dir_cache.has(po):
				d = dir_cache[po]
			else:
				d = resolve(po)
				dir_cache[po] = d
			if not _dir_index.has(d):
				_dir_index[d] = []
			_dir_index[d].append(base + i)
		base += n


func _table_name_at(global_i: int) -> int:
	_file.seek(_table_off + global_i * FILE_ITEM_SIZE)
	return _file.get_buffer(4).decode_s32(0)


## 列出某个目录前缀下的全部路径（需要先建目录索引；首次约 4.5 s）。
## 审计/枚举用，不进正常加载路径。
func paths_under(prefix: String) -> PackedStringArray:
	if not _dir_index_built:
		_build_dir_index()
	var out := PackedStringArray()
	var p := prefix.strip_edges().trim_suffix("/")
	for d in _dir_index.keys():
		var ds := str(d)
		if ds != p and not ds.begins_with(p + "/"):
			continue
		for gi in _dir_index[d]:
			var nm := resolve(_table_name_at(int(gi)))
			if nm != "":
				out.append(ds + "/" + nm)
	return out




func _name_equals(v: int, want: PackedByteArray) -> bool:
	if v < 0 or not (v & 1):
		return false
	var p := (v >> 1) * 2
	if p + want.size() + 1 >= _str_w.size():
		return false
	for i in want.size():
		if _str_w[p + i] != want[i]:
			return false
	return _str_w[p + want.size()] == 0 and _str_w[p + want.size() + 1] == 0

func read(path: String) -> PackedByteArray:
	var e := find(path)
	if e.x < 0:
		return PackedByteArray()
	var chunk := chunk_data(e.x)
	var off := e.y
	var size := e.z
	if off < 0 or size < 0 or off + size > chunk.size():
		return PackedByteArray()
	return chunk.slice(off, off + size)


func chunk_data(idx: int) -> PackedByteArray:
	if idx < 0 or idx >= _groups.size():
		return PackedByteArray()
	if _chunk_cache.has(idx):
		return _chunk_cache[idx]
	var prev := 0 if idx == 0 else _groups[idx - 1].x
	var cur := _groups[idx].x
	var blob := _read_plain(_body_off + prev, cur - prev)
	var plain := _decrypt_protected("mAIn", blob, MAGIC_PROTECTED)
	var out := _zlib(plain, _groups[idx].y)
	_chunk_cache[idx] = out
	_chunk_order.append(idx)
	while _chunk_order.size() > MAX_CHUNKS:
		var old: int = _chunk_order.pop_front()
		_chunk_cache.erase(old)
	return out


func has(path: String) -> bool:
	return find(path).x >= 0


func stats() -> Dictionary:
	return {
		"path": script_path,
		"files": file_count,
		"body": body_size,
		"groups": group_count,
		"strings_a": _str_a.size(),
		"strings_w": _str_w.size(),
		"cached_paths": _entries.size(),
		"cached_chunks": _chunk_cache.size(),
	}
