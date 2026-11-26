class_name PvfArchive
extends RefCounted
## PVF 容器层 —— 只负责字节：56 字节头、目录树解密、条目表、按条目读明文。
##
## 文件布局（小端）：
##   [0x00] Header 56 字节
##   [0x38] 目录树 dirTreeLength 字节（整体加密）
##   [0x38+dirTreeLength] 数据区，条目按 relativeOffset 定位
##
## 目录树 / 文件体的解密是同一个公式（逐 4 字节，密钥不同）：
##   plain = ror32(cipher ^ 0x81A79011 ^ key, 6)
##   key   = 目录树用 dirTreeChecksum，文件体用该条目的 crc 字段
##
## 目录树条目（连续存放，无对齐）：
##   u32 fileNumber; i32 pathLength; char path[pathLength];
##   i32 length; u32 crc; i32 relativeOffset
##
## 已知性能：sf115 的目录树 141 MB → 约 3,530 万次 4 字节解密。
## GDScript 单线程约 20~60 s；建议 `open_async()` 或改用 `PvfIndex`（预生成索引）。
## 条目数 1,460,792。

const HEADER_SIZE: int = 56
const PASSWORD_PVF: int = 0x81A79011
const DEFAULT_ENCODING: String = "ascii"  ## 条目路径只有 10/1460792 条非 ASCII

var header: PvfTypes.Header = null
var entries: Dictionary = {}            ## path(String) -> PvfTypes.Entry
var paths: PackedStringArray = []       ## 保持文件内顺序的 path 列表
var file_path: String = ""

var last_error: Error = OK
var last_error_message: String = ""

var _file: FileAccess = null
var _lower_index: Dictionary = {}       ## path.to_lower() -> path
var _string_bin: PackedStringArray = []
var _string_loaded: bool = false
var _string_map: Dictionary = {}
var _text_decoder: Callable = Callable()


# =====================================================================
# 打开 / 关闭
# =====================================================================
func open(path: String) -> Error:
	close()
	_file = FileAccess.open(path, FileAccess.READ)
	if _file == null:
		LogUtil.error("无法打开文件：%s" % path)
		return _fail(FileAccess.get_open_error(), "打开失败：%s" % path)
	LogUtil.info("已打开文件：%s" % path)
	file_path = path
	var err := _read_header()
	if err != OK:
		LogUtil.error("读取头部失败, %s", err)
		close()
		return err
	err = _read_dir_tree()
	if err != OK:
		LogUtil.error("读取目录树失败, %s", err)
		close()
		return err
	last_error = OK
	last_error_message = ""
	return OK


func is_open() -> bool:
	return _file != null


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
	header = null
	entries.clear()
	paths = PackedStringArray()
	_lower_index.clear()
	_string_bin = PackedStringArray()
	_string_map.clear()
	_string_loaded = false


func _fail(code: Error, msg: String) -> Error:
	last_error = code
	last_error_message = msg
	LogUtil.error("[PvfArchive] " + msg)
	return code


# =====================================================================
# 头部 / 目录树
# =====================================================================
func _read_header() -> Error:
	if _file.get_length() < HEADER_SIZE:
		return _fail(ERR_FILE_CORRUPT, "文件小于 56 字节，不是 PVF")
	var h := PvfTypes.Header.new()
	h.size_guid = _file.get_32()
	h.guid = _file.get_buffer(36).get_string_from_ascii()
	h.file_version = _file.get_32()
	h.dir_tree_length = _file.get_32()
	h.dir_tree_checksum = _file.get_32()
	h.num_files = _file.get_32()
	h.data_start = HEADER_SIZE + h.dir_tree_length
	if h.size_guid != 0x24:
		return _fail(ERR_FILE_UNRECOGNIZED,
			"sizeGUID=%d（应为 36），不是 PVF 或已加密" % h.size_guid)
	if h.num_files <= 0 or h.num_files > 8_000_000:
		return _fail(ERR_FILE_CORRUPT, "numFiles=%d 不合理" % h.num_files)
	if h.data_start > _file.get_length():
		return _fail(ERR_FILE_CORRUPT,
			"目录树长度 %d 超出文件（%d）" % [h.dir_tree_length, _file.get_length()])
	header = h
	return OK


func _read_dir_tree() -> Error:
	_file.seek(HEADER_SIZE)
	var randShow : int = 1000
	var raw := _file.get_buffer(header.dir_tree_length)
	if raw.size() != header.dir_tree_length:
		return _fail(ERR_FILE_CORRUPT, "目录树读取不完整")
	var buf := decrypt_buffer(raw, header.dir_tree_checksum)
	var off := 0
	var total := buf.size()
	entries.clear()
	paths = PackedStringArray()
	paths.resize(header.num_files)
	for i in header.num_files:
		if off + 8 > total:
			return _fail(ERR_FILE_CORRUPT, "目录树在第 %d 条处截断" % i)
		var number := buf.decode_u32(off)
		var path_len := buf.decode_s32(off + 4)
		off += 8
		if path_len < 0 or off + path_len + 12 > total:
			return _fail(ERR_FILE_CORRUPT,
				"第 %d 条 pathLength=%d 越界（剩余 %d）" % [i, path_len, total - off])
		var e := PvfTypes.Entry.new()
		e.number = number
		e.path = decode_path(buf, off, path_len)
		off += path_len
		e.length = buf.decode_s32(off)
		e.crc = buf.decode_u32(off + 4)
		e.rel_offset = buf.decode_s32(off + 8)
		off += 12
		e.abs_offset = header.data_start + e.rel_offset
		entries[e.path] = e
		paths[i] = e.path
		if i % randShow == 0:
			LogUtil.info("目录树读取进度：%d / %d" % [i, header.num_files])
			LogUtil.debug("目录树读取条目：%s " % [e.path])
	return OK


# =====================================================================
# 解密 / 解码
# =====================================================================
## 逐 4 字节解密：plain = ror32(cipher ^ PASSWORD ^ key, 6)。尾部不足 4 字节原样保留。
static func decrypt_buffer(src: PackedByteArray, key: int) -> PackedByteArray:
	var mix: int = (PASSWORD_PVF ^ key) & 0xFFFFFFFF
	var out := src.duplicate()
	var n := out.size() >> 2
	for i in n:
		var o := i << 2
		var v: int = out.decode_u32(o) ^ mix
		v = ((v >> 6) | (v << 26)) & 0xFFFFFFFF
		out.encode_u32(o, v)
	return out


## 路径解码：纯 ASCII 直接用；含高位字节时退化为 latin1（1 字节 1 字符，不丢信息）
static func decode_path(buf: PackedByteArray, offset: int, length: int) -> String:
	var raw := buf.slice(offset, offset + length)
	var ascii := raw.get_string_from_ascii()
	if raw.size() > 0 and ascii.length() != raw.size():
		return _latin1(raw)
	return ascii


static func _latin1(raw: PackedByteArray) -> String:
	var out := ""
	out = out.rstrip(" ")  # 占位，保持类型推导
	var parts: Array = []
	parts.resize(raw.size())
	for i in raw.size():
		parts[i] = String.chr(raw[i])
	return "".join(parts)


## 正文解码（stringtable / 文档字符串）。
## GDScript 只有 UTF-8/ASCII，**没有** big5/gb18030/cp949 支持：
##   - UTF-8 合法 → 直接解；
##   - 否则 → latin1 保底（每个字节映射成一个字符，上层可自行换表）。
## 想显示中文名，给 `set_text_decoder()` 塞一个 Callable（例如转调 C# 的 Encoding）。
func decode_text(raw: PackedByteArray) -> String:
	if _text_decoder.is_valid():
		return String(_text_decoder.call(raw))
	# 纯 ASCII（sf115 的 146 万条路径里 99.99% 是这种）：直接按字节转，最快且无解码告警
	var ascii_only := true
	for i in raw.size():
		if raw[i] > 0x7F:
			ascii_only = false
			break
	if ascii_only:
		return raw.get_string_from_ascii()
	# 非 ASCII：先自己验一遍 UTF-8，通过才交给引擎（否则引擎会往控制台刷
	# "Unicode parsing error ..."，中文名一多就淹掉日志）；不合法就按字节 1:1 映射。
	if _looks_like_utf8(raw):
		return raw.get_string_from_utf8()
	return _latin1(raw)


## 自己验 UTF-8 合法性：只为「不要触发引擎的解码告警」，不做任何转换。
static func _looks_like_utf8(raw: PackedByteArray) -> bool:
	var i := 0
	var n := raw.size()
	while i < n:
		var b := raw[i]
		var extra := 0
		if b < 0x80:
			extra = 0
		elif b >= 0xC2 and b <= 0xDF:
			extra = 1
		elif b >= 0xE0 and b <= 0xEF:
			extra = 2
		elif b >= 0xF0 and b <= 0xF4:
			extra = 3
		else:
			return false
		if i + extra >= n:
			return false
		for k in range(1, extra + 1):
			if (raw[i + k] & 0xC0) != 0x80:
				return false
		i += extra + 1
	return true


## 逐码位找 U+FFFD（不用字符串字面量比较，避免转义在不同版本下不一致）
static func _has_replacement(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) == 0xFFFD:
			return true
	return false


func set_text_decoder(decoder: Callable) -> void:
	_text_decoder = decoder


# =====================================================================
# 条目访问
# =====================================================================
func has(path: String) -> bool:
	return entries.has(path)


## 精确查；找不到时按「小写全路径」再试一次
func get_entry(path: String) -> PvfTypes.Entry:
	if entries.has(path):
		return entries[path]
	if _lower_index.is_empty() and not entries.is_empty():
		for k in entries.keys():
			_lower_index[String(k).to_lower()] = k
	var real: Variant = _lower_index.get(path.to_lower())
	if real != null:
		return entries[real]
	return null


## 读一个条目的明文（已解密、已按 length 截断）。失败返回空数组。
func read(path_or_entry: Variant) -> PackedByteArray:
	var e: PvfTypes.Entry = path_or_entry if path_or_entry is PvfTypes.Entry else get_entry(str(path_or_entry))
	if e == null:
		_fail(ERR_FILE_NOT_FOUND, "条目不存在：%s" % str(path_or_entry))
		return PackedByteArray()
	var need := e.padded_length()
	if e.abs_offset < 0 or e.abs_offset + need > _file.get_length():
		_fail(ERR_FILE_CORRUPT, "条目越界：%s" % e.path)
		return PackedByteArray()
	_file.seek(e.abs_offset)
	var raw := _file.get_buffer(need)
	if raw.size() != need:
		_fail(ERR_FILE_CORRUPT, "条目读取不完整：%s" % e.path)
		return PackedByteArray()
	var plain := decrypt_buffer(raw, e.crc)
	return plain.slice(0, e.length) if plain.size() > e.length else plain


# =====================================================================
# 字符串表（文档里的 [SECTION] 名和字符串值都存成「索引」）
# =====================================================================
func load_strings() -> void:
	if _string_loaded:
		return
	_string_loaded = true
	_string_bin = PackedStringArray()
	_string_map = {}
	var st := get_entry("stringtable.bin")
	if st == null:
		return
	var buf := read(st)
	if buf.size() < 8:
		return
	var count := buf.decode_s32(0)
	if count <= 0 or count > 4_000_000:
		return
	_string_bin.resize(count)
	for i in count:
		var start := buf.decode_s32(i * 4 + 4)
		var end := buf.decode_s32(i * 4 + 8)
		var ln := end - start
		var s := ""
		if ln >= 0 and ln <= 4 * 1024 * 1024 and start >= 0 and start + 4 + ln <= buf.size():
			s = decode_text(buf.slice(start + 4, start + 4 + ln)).strip_edges().to_lower()
		_string_bin[i] = s
	# n_string.lst：把「字符串表下标」映射到语言表文件（形如 key>value 的行）
	var nstr := get_entry("n_string.lst")
	if nstr == null:
		return
	var nb := read(nstr)
	if nb.size() < 12 or nb.decode_u16(0) != 53424:
		return
	var i2 := 2
	while i2 + 10 <= nb.size():
		var key_idx := nb.decode_s32(i2 + 6)
		i2 += 10
		if key_idx < 0 or key_idx >= count:
			continue
		var fname := _string_bin[key_idx]
		if fname.is_empty():
			continue
		var fe := get_entry(fname)
		if fe == null:
			continue
		var txt := decode_text(read(fe))
		for line in txt.split("\r\n"):
			var p := line.find(">")
			if p > 0:
				_string_map[line.substr(0, p).strip_edges()] = line.substr(p + 1).strip_edges()


func string_bin() -> PackedStringArray:
	load_strings()
	return _string_bin


func string_map() -> Dictionary:
	load_strings()
	return _string_map


func lookup_string(index: int) -> String:
	load_strings()
	if index >= 0 and index < _string_bin.size():
		return _string_bin[index]
	return ""


# =====================================================================
# 便利查询
# =====================================================================
## 前缀列举（`list_dir("character/swordman/")`）
func list_dir(prefix: String, limit: int = 0) -> PackedStringArray:
	var out := PackedStringArray()
	var base := prefix.to_lower()
	for p in paths:
		if p.begins_with(base):
			out.append(p)
			if limit > 0 and out.size() >= limit:
				break
	return out


## 后缀过滤（`.ani` / `.equ` / `.img`），可再叠加前缀
func find_suffix(suffix: String, prefix: String = "", limit: int = 0) -> PackedStringArray:
	var out := PackedStringArray()
	var suf := suffix.to_lower()
	var base := prefix.to_lower()
	for p in paths:
		if p.ends_with(suf) and (base.is_empty() or p.begins_with(base)):
			out.append(p)
			if limit > 0 and out.size() >= limit:
				break
	return out


func stats() -> Dictionary:
	return {
		"file": file_path,
		"file_version": header.file_version if header != null else 0,
		"num_files": entries.size(),
		"dir_tree_length": header.dir_tree_length if header != null else 0,
		"data_start": header.data_start if header != null else 0,
	}
