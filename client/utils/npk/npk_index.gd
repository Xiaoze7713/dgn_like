## NPK 索引：把「img 路径 → 在哪个 .npk、从第几字节开始、多长」装进内存
##
## 索引由 `tools/mk_npk_index.py` 生成（扫 ImagePacks2 下所有 NPK 的索引表，
## 只读 16 B magic + u32 条目数 + 每项 264 B，不解图）。
##
## 文件布局（小端，见 mk_npk_index.py 头部注释）：
##   "NPKIDX02"        8 B
##   u32 count         条目数
##   u32 reserved
##   record[count]     20 B：u64 hash, u16 pack_id, u16 pad, u32 offset, u32 size
##   u16 pack_count
##   pack[...]         u16 len + utf-8 字节
##
## record 按 hash 升序 → 二分查找。hash = FNV-1a 64（对小写路径的 UTF-8 字节）。
class_name NpkIndex
extends RefCounted

const MAGIC := "NPKIDX02"
const REC_SIZE := 20
static var XOR_TABLE := PackedByteArray([112, 117, 99, 104, 105, 107, 111, 110, 64, 110, 101, 111, 112, 108, 101, 32, 100, 117, 110, 103, 101, 111, 110, 32, 97, 110, 100, 32, 102, 105, 103, 104, 116, 101, 114, 32, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 68, 78, 70, 0])

var count := 0
var packs: PackedStringArray = []

var _buf: PackedByteArray
var _rec_start := 16


static func from_file(path: String) -> NpkIndex:
	var idx := NpkIndex.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		LogUtil.error("打不开 NPK 索引：%s" % path)
		return idx
	idx.load_bytes(f.get_buffer(f.get_length()))
	f.close()
	return idx


func load_bytes(bytes: PackedByteArray) -> void:
	_buf = bytes
	if bytes.size() < 16 or bytes.slice(0, 8).get_string_from_ascii() != MAGIC:
		LogUtil.error("NPK 索引 magic 不对（期望 %s）" % MAGIC)
		return
	count = bytes.decode_u32(8)
	_rec_start = 16
	var p := _rec_start + count * REC_SIZE
	if p + 2 > bytes.size():
		LogUtil.error("NPK 索引截断：期望 %d 条" % count)
		count = 0
		return
	var pack_count := bytes.decode_u16(p)
	p += 2
	for i in pack_count:
		if p + 2 > bytes.size():
			break
		var n := bytes.decode_u16(p)
		p += 2
		if p + n > bytes.size():
			break
		packs.append(bytes.slice(p, p + n).get_string_from_utf8())
		p += n


## FNV-1a 64（64 位回绕，与 Python 侧一致）
static func hash_path(path: String) -> int:
	var h := -3750763034362895579  # 0xCBF29CE484222325 的 int64 补码
	var low := path.to_lower()
	for b in low.to_utf8_buffer():
		h = (h ^ b) * 0x100000001B3
	return h




## 直接扫描 ImagePacks2 目录，运行时建索引（不依赖预生成的 .bin）
static func from_dir(dir: String) -> NpkIndex:
	var idx := NpkIndex.new()
	var dh := DirAccess.open(dir)
	if dh == null:
		LogUtil.error("打不开 NPK 目录：%s" % dir)
		return idx
	var names := PackedStringArray()
	var rows: Array = []
	for fn in dh.get_files():
		if not fn.to_lower().ends_with(".npk"):
			continue
		var path := dir.path_join(fn)
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var magic := f.get_buffer(16).get_string_from_ascii()
		if magic != "NeoplePack_Bill":
			continue
		var cnt := f.get_32()
		if cnt <= 0 or cnt > 200000:
			continue
		var tab := f.get_buffer(cnt * 264)
		f.close()
		if tab.size() < cnt * 264:
			continue
		var pid := names.size()
		names.append(fn)
		for i in cnt:
			var o := i * 264
			var off := tab.decode_s32(o)
			var size := tab.decode_s32(o + 4)
			var h := -3750763034362895579
			var ended := false
			for j in 255:
				var c := tab[o + 8 + j] ^ XOR_TABLE[j]
				if c == 0:
					ended = true
					break
				if c >= 65 and c <= 90:
					c += 32
				h = (h ^ c) * 0x100000001B3
			if not ended or h == -3750763034362895579:
				continue
			rows.append({"h": h, "p": pid, "o": off, "s": size})
	rows.sort_custom(func(a, b):
		var ah := (int(a["h"]) >> 32) & 0xFFFFFFFF
		var bh := (int(b["h"]) >> 32) & 0xFFFFFFFF
		if ah != bh:
			return ah < bh
		return (int(a["h"]) & 0xFFFFFFFF) < (int(b["h"]) & 0xFFFFFFFF))
	var out := "NPKIDX02".to_ascii_buffer()
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, rows.size())
	head.encode_u32(4, 0)
	out.append_array(head)
	var rec := PackedByteArray()
	rec.resize(rows.size() * REC_SIZE)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var h := int(r["h"])
		rec.encode_u32(i * REC_SIZE, h & 0xFFFFFFFF)
		rec.encode_u32(i * REC_SIZE + 4, (h >> 32) & 0xFFFFFFFF)
		rec.encode_u16(i * REC_SIZE + 8, int(r["p"]))
		rec.encode_u16(i * REC_SIZE + 10, 0)
		rec.encode_u32(i * REC_SIZE + 12, int(r["o"]))
		rec.encode_u32(i * REC_SIZE + 16, int(r["s"]))
	out.append_array(rec)
	var pc := PackedByteArray()
	pc.resize(2)
	pc.encode_u16(0, names.size())
	out.append_array(pc)
	for nm in names:
		var b := nm.to_utf8_buffer()
		var ln := PackedByteArray()
		ln.resize(2)
		ln.encode_u16(0, b.size())
		out.append_array(ln)
		out.append_array(b)
	idx.load_bytes(out)
	return idx


## 查一条：{"pack": 包文件名, "pack_id": int, "offset": int, "size": int}；找不到返回空字典
func find(path: String) -> Dictionary:
	if count <= 0:
		return {}
	var key := path
	var hit := _search(hash_path(key))
	if hit.is_empty() and not key.begins_with("sprite/"):
		# NPK 里的名字带 sprite/ 前缀，PVF 里的引用不带
		hit = _search(hash_path("sprite/" + key))
	return hit


## 二分查找。注意：GDScript 的 int 是 int64，而表里的 hash 是 u64，
## 高位为 1 的值读回来可能是负数 —— 所以统一拆成 hi/lo 两个 u32 做**无符号**比较。
func _search(h: int) -> Dictionary:
	var hi := (h >> 32) & 0xFFFFFFFF
	var lo := h & 0xFFFFFFFF
	var a := 0
	var b := count - 1
	while a <= b:
		var mid := (a + b) >> 1
		var off := _rec_start + mid * REC_SIZE
		var mhi := _buf.decode_u32(off + 4)
		var mlo := _buf.decode_u32(off)
		var c := 0
		if mhi < hi:
			c = -1
		elif mhi > hi:
			c = 1
		elif mlo < lo:
			c = -1
		elif mlo > lo:
			c = 1
		if c == 0:
			var pid := _buf.decode_u16(off + 8)
			return {
				"pack": packs[pid] if pid < packs.size() else "",
				"pack_id": pid,
				"offset": _buf.decode_u32(off + 12),
				"size": _buf.decode_u32(off + 16),
			}
		if c < 0:
			a = mid + 1
		else:
			b = mid - 1
	return {}


func stats() -> Dictionary:
	return {"count": count, "packs": packs.size(), "bytes": _buf.size()}
