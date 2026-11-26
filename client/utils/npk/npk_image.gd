## DNF 的 IMG 解码（纯 GDScript，不依赖任何导出产物）
##
## 一个 .img 的组成（全部实测，见 docs/NPK-IMG-BYTES.md）：
##   文件头 32 B：magic "Neople Img File\0"(16) + u32 tableLength + u32 0
##                + u32 version + u32 frameCount
##   版本扩展：v2 无 / v4 调色板 / v5 DDS 表 + 调色板 / v6 多调色板
##   帧记录：指向帧 8 B(type=0x11, linkTo) / 普通帧 36 B / v5 共享贴图帧 64 B
##   帧体：全部帧记录之后，按帧顺序紧密排列；v5 的 DDS 裸数据排在帧体之前
##
## 用法：
##   var img := NpkImage.decode(bytes)
##   var f := img.frame(3)            # {rect:Rect2i, image:Image}
class_name NpkImage
extends RefCounted

const MAGIC := "Neople Img File"

## 帧类型（像素格式）
const T_INDEXED := 0x0E   # v4/v6 调色板索引
const T_ARGB1555 := 0x0E  # v2/v5 ARGB1555（同一个码，按版本区分）
const T_ARGB4444 := 0x0F
const T_ARGB8888 := 0x10
const T_REFERENCE := 0x11
const T_DXT1 := 0x12
const T_DXT3 := 0x13
const T_DXT5 := 0x14

## 压缩方式
const C_RAW := 0x05
const C_ZLIB := 0x06
const C_DDS := 0x07

var version := 2
var frame_count := 0
var table_length := 0
var palettes: Array[PackedByteArray] = []
var dds_table: Array = []
var warnings: Array[String] = []

var _buf: PackedByteArray
var _frames: Array = []     # 每条一个 Dictionary
var _resolved: Array[int] = []
var _body_start := 0


static func decode(buf: PackedByteArray) -> NpkImage:
	var img := NpkImage.new()
	img._parse(buf)
	return img


func _parse(buf: PackedByteArray) -> void:
	_buf = buf
	if buf.size() < 32:
		LogUtil.error("IMG 太短：%d 字节" % buf.size())
		return
	if buf.slice(0, 15).get_string_from_ascii() != MAGIC:
		LogUtil.error("IMG magic 不对")
		return
	table_length = buf.decode_u32(16)
	version = buf.decode_u32(24)
	frame_count = buf.decode_u32(28)

	var pos := 32
	match version:
		4:
			var cn := buf.decode_s32(pos)
			pos += 4
			palettes.append(_read_palette(pos, cn))
			pos += cn * 4
		5:
			var dds_n := buf.decode_s32(pos)
			var img_len := buf.decode_s32(pos + 4)
			var cn2 := buf.decode_s32(pos + 8)
			pos += 12
			if cn2 > 0:
				palettes.append(_read_palette(pos, cn2))
				pos += cn2 * 4
			if dds_n > 0:
				for i in dds_n:
					var rec := {
						"title": buf.decode_s32(pos),
						"pixel_format": buf.decode_s32(pos + 4),
						"index": buf.decode_s32(pos + 8),
						"full_length": buf.decode_s32(pos + 12),
						"length": buf.decode_s32(pos + 16),
						"width": buf.decode_s32(pos + 20),
						"height": buf.decode_s32(pos + 24),
					}
					dds_table.append(rec)
					pos += 28
			if dds_n < 0 or img_len < 0:
				LogUtil.warn("v5 头字段异常 dds=%d len=%d" % [dds_n, img_len])
		6:
			var pn := buf.decode_s32(pos)
			pos += 4
			for i in pn:
				var cn3 := buf.decode_s32(pos)
				pos += 4
				palettes.append(_read_palette(pos, cn3))
				pos += cn3 * 4

	# 帧记录
	for i in frame_count:
		if pos + 4 > buf.size():
			LogUtil.warn("帧记录越界，截断于第 %d 帧" % i)
			frame_count = i
			break
		var t := buf.decode_s32(pos)
		if t == T_REFERENCE:
			if pos + 8 > buf.size():
				break
			_frames.append({"type": t, "ref": buf.decode_s32(pos + 4),
				"w": 0, "h": 0, "x": 0, "y": 0, "length": 0,
				"compressed": 0, "dds": -1, "raw": PackedByteArray()})
			pos += 8
			continue
		if pos + 36 > buf.size():
			LogUtil.warn("帧记录不完整，截断于第 %d 帧" % i)
			frame_count = i
			break
		var f := {
			"type": t,
			"compressed": buf.decode_s32(pos + 4),
			"w": buf.decode_s32(pos + 8),
			"h": buf.decode_s32(pos + 12),
			"length": buf.decode_s32(pos + 16),
			"x": buf.decode_s32(pos + 20),
			"y": buf.decode_s32(pos + 24),
			"fw": buf.decode_s32(pos + 28),
			"fh": buf.decode_s32(pos + 32),
			"dds": -1, "left": 0, "up": 0, "right": 0, "down": 0,
			"raw": PackedByteArray(),
		}
		pos += 36
		if version == 5 and (f["compressed"] == C_DDS or t in [T_DXT1, T_DXT3, T_DXT5]):
			if pos + 28 <= buf.size():
				f["dds"] = buf.decode_s32(pos + 4)
				f["left"] = buf.decode_s32(pos + 8)
				f["up"] = buf.decode_s32(pos + 12)
				f["right"] = buf.decode_s32(pos + 16)
				f["down"] = buf.decode_s32(pos + 20)
				pos += 28
			else:
				pos = buf.size()
		_frames.append(f)

	_resolve_refs()
	_read_bodies(pos)


func _read_palette(pos: int, n: int) -> PackedByteArray:
	if n <= 0 or pos + n * 4 > _buf.size():
		return PackedByteArray()
	return _buf.slice(pos, pos + n * 4)


## 指向帧解析成真实帧号；越界/成环 -> -1（画 1×1 透明）
func _resolve_refs() -> void:
	_resolved.clear()
	for i in _frames.size():
		var f: Dictionary = _frames[i]
		if f["type"] != T_REFERENCE:
			_resolved.append(i)
			continue
		var cur: int = f["ref"]
		var seen := {}
		var real := -1
		while true:
			if cur < 0 or cur >= _frames.size() or seen.has(cur):
				break
			seen[cur] = true
			if _frames[cur]["type"] != T_REFERENCE:
				real = cur
				break
			cur = _frames[cur]["ref"]
		_resolved.append(real)


func _read_bodies(pos: int) -> void:
	# v5：先铺满 DDS 裸数据
	if version == 5:
		for rec in dds_table:
			var n: int = rec["full_length"]
			if n < 0 or pos + n > _buf.size():
				rec["raw"] = _buf.slice(pos, mini(pos + maxi(n, 0), _buf.size()))
				pos = mini(pos + maxi(n, 0), _buf.size())
				continue
			rec["raw"] = _buf.slice(pos, pos + n)
			pos += n
	_body_start = pos
	for f in _frames:
		if f["type"] == T_REFERENCE:
			continue
		if version == 5 and f["compressed"] == C_DDS:
			continue
		var n: int = f["length"]
		if f["compressed"] == C_RAW:
			# 未压缩帧的 length 在真实语料里有写错的，以几何尺寸为准
			var bpp := _bpp(int(f["type"]))
			var exp: int = int(f["w"]) * int(f["h"]) * bpp
			if exp > 0:
				n = exp
		if n <= 0:
			continue
		var end := pos + n
		if end > _buf.size():
			end = _buf.size()
			warnings.append("帧 %d 截断" % f.get("index", -1))
		f["raw"] = _buf.slice(pos, end)
		pos = end


func _bpp(t: int) -> int:
	match t:
		T_ARGB8888:
			return 4
		T_ARGB4444:
			return 2
		T_INDEXED:
			return 1 if version in [4, 6] else 2
		_:
			return 1


func frame_rect(i: int) -> Rect2i:
	if i < 0 or i >= _resolved.size() or _resolved[i] < 0:
		return Rect2i(0, 0, 1, 1)
	var f: Dictionary = _frames[_resolved[i]]
	if version == 5 and f["compressed"] == C_DDS and f["dds"] >= 0:
		var cw: int = int(f["right"]) - int(f["left"])
		var ch: int = int(f["down"]) - int(f["up"])
		return Rect2i(int(f["x"]), int(f["y"]), maxi(cw, 1), maxi(ch, 1))
	return Rect2i(int(f["x"]), int(f["y"]), maxi(int(f["w"]), 1), maxi(int(f["h"]), 1))


## 解一帧 -> {"rect": Rect2i, "image": Image(FORMAT_RGBA8)}
func frame(i: int) -> Dictionary:
	if i < 0 or i >= _resolved.size() or _resolved[i] < 0:
		return _placeholder()
	var fi: int = _resolved[i]
	var f: Dictionary = _frames[fi]
	if version == 5 and f["compressed"] == C_DDS:
		return _dds_frame(f)
	var w: int = maxi(int(f["w"]), 1)
	var h: int = maxi(int(f["h"]), 1)
	var data := _inflate(f)
	var t: int = f["type"]
	var rgba := PackedByteArray()
	match t:
		T_ARGB8888:
			return _bgra_frame(data, w, h, int(f["x"]), int(f["y"]))
		T_ARGB4444:
			rgba = _from_4444(data, w, h)
		T_ARGB1555:
			if version in [4, 6]:
				rgba = _from_indexed(data, w, h)
			else:
				rgba = _from_1555(data, w, h)
		T_INDEXED:
			rgba = _from_indexed(data, w, h)
		_:
			warnings.append("帧 %d 类型 0x%02X 不支持" % [fi, t])
			return _placeholder()
	if rgba.size() < w * h * 4:
		rgba.resize(w * h * 4)
	var im := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
	return {"rect": Rect2i(int(f["x"]), int(f["y"]), w, h), "image": im}


func _placeholder() -> Dictionary:
	var im := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	return {"rect": Rect2i(0, 0, 1, 1), "image": im}


func _inflate(f: Dictionary) -> PackedByteArray:
	var raw: PackedByteArray = f["raw"]
	var c: int = f["compressed"]
	if c == C_RAW:
		return raw
	if c == C_ZLIB or c == C_DDS:
		var need: int = int(f["w"]) * int(f["h"]) * _bpp(int(f["type"]))
		if need <= 0:
			need = 1 << 20
		var out := raw.decompress(need, FileAccess.COMPRESSION_DEFLATE)
		if out.is_empty():
			# 有些包是裸 deflate（无 zlib 头），Godot 不支持，只能放弃这一帧
			warnings.append("zlib 解压失败：帧体 %d B" % raw.size())
		return out
	warnings.append("未知压缩 0x%02X" % c)
	return PackedByteArray()


## ARGB8888 在内存里是 B,G,R,A（D3D9 A8R8G8B8）；Godot 4 没有 BGRA8，手工换 B/R
func _bgra_frame(data: PackedByteArray, w: int, h: int, x: int, y: int) -> Dictionary:
	var need := w * h * 4
	if data.size() < need:
		data.resize(need)   # resize 补零
	elif data.size() > need:
		data = data.slice(0, need)
	var i := 0
	while i < need:
		var b := data[i]
		data[i] = data[i + 2]
		data[i + 2] = b
		i += 4
	var im := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	return {"rect": Rect2i(x, y, w, h), "image": im}


func _from_1555(data: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var n := w * h
	var out := PackedByteArray()
	out.resize(n * 4)
	for i in n:
		var o := i * 2
		if o + 1 >= data.size():
			break
		var v: int = data[o] | (data[o + 1] << 8)
		var r := (v >> 10) & 0x1F
		var g := (v >> 5) & 0x1F
		var b := v & 0x1F
		var q := i * 4
		out[q] = (r << 3) | (r >> 2)
		out[q + 1] = (g << 3) | (g >> 2)
		out[q + 2] = (b << 3) | (b >> 2)
		out[q + 3] = 255 if (v & 0x8000) != 0 else 0
	return out


func _from_4444(data: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var n := w * h
	var out := PackedByteArray()
	out.resize(n * 4)
	for i in n:
		var o := i * 2
		if o + 1 >= data.size():
			break
		var v: int = data[o] | (data[o + 1] << 8)
		var q := i * 4
		out[q] = ((v >> 8) & 0xF) * 17
		out[q + 1] = ((v >> 4) & 0xF) * 17
		out[q + 2] = (v & 0xF) * 17
		out[q + 3] = ((v >> 12) & 0xF) * 17
	return out


func _from_indexed(data: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var pal: PackedByteArray = palettes[0] if palettes.size() > 0 else PackedByteArray()
	var n := w * h
	var out := PackedByteArray()
	out.resize(n * 4)
	var colors := pal.size() / 4
	for i in n:
		if i >= data.size():
			break
		var idx: int = data[i]
		if idx >= colors:
			idx = 0   # 与 Python 参考实现一致：越界索引按 0 号色
		var s := idx * 4
		var q := i * 4
		out[q] = pal[s]
		out[q + 1] = pal[s + 1]
		out[q + 2] = pal[s + 2]
		out[q + 3] = pal[s + 3]
	return out


# ---------------------------------------------------------------------------
# v5 共享贴图：DDS（128 B 头 + DXT 负载）或裸像素
# ---------------------------------------------------------------------------
func _dds_frame(f: Dictionary) -> Dictionary:
	var di: int = f["dds"]
	if di < 0 or di >= dds_table.size():
		return _placeholder()
	var rec: Dictionary = dds_table[di]
	var blob: PackedByteArray = rec["raw"]
	if blob.is_empty():
		return _placeholder()
	if blob.size() > 2 and blob[0] == 0x78:
		# v5 的 DDS 记录里 full_length 是**压缩后**字节数（也是 _read_bodies 的切片长度），
		# length 才是解压后的 DDS 字节数；之前用 full_length*4 当输出缓冲，遇到大图会
		# 报 “decompress err != 1”，整帧退化成占位图（表现为城镇背景一部分变黑）。
		var want := int(rec.get("length", 0))
		if want <= 0:
			want = int(rec["full_length"]) * 4 + 64
		var got := blob.decompress(want, FileAccess.COMPRESSION_DEFLATE)
		if not got.is_empty():
			blob = got
	var dw: int = maxi(int(rec["width"]), 1)
	var dh: int = maxi(int(rec["height"]), 1)
	var left: int = f["left"]
	var up: int = f["up"]
	var cw: int = maxi(int(f["right"]) - left, 1)
	var ch: int = maxi(int(f["down"]) - up, 1)
	# DDS 已经是标准文件时交给引擎原生解码（C++），比 GDScript 逐像素 DXT 快两个数量级。
	# 运行时大图（warheit 的 Cloud/Gear_Big）之前每帧 300–560ms，就是逐像素解码卡主线程。
	if blob.size() >= 128 and blob.slice(0, 4).get_string_from_ascii() == "DDS ":
		var native := Image.new()
		if native.load_dds_from_buffer(blob) == OK and native.get_width() > 0:
			if native.is_compressed():
				native.decompress()
			native.convert(Image.FORMAT_RGBA8)
			var cw2: int = mini(cw, native.get_width() - left)
			var ch2: int = mini(ch, native.get_height() - up)
			if cw2 > 0 and ch2 > 0:
				var crop2 := native.get_region(Rect2i(left, up, cw2, ch2))
				return {"rect": Rect2i(int(f["x"]), int(f["y"]), cw2, ch2), "image": crop2}
	var full := _decode_dds(blob, dw, dh, int(rec["pixel_format"]))
	if full.is_empty():
		return _placeholder()
	var im := Image.create_from_data(dw, dh, false, Image.FORMAT_RGBA8, full)
	var crop := im.get_region(Rect2i(left, up, cw, ch))
	return {"rect": Rect2i(int(f["x"]), int(f["y"]), cw, ch), "image": crop}


func _decode_dds(blob: PackedByteArray, w: int, h: int, pf: int) -> PackedByteArray:
	if blob.size() >= 128 and blob.slice(0, 4).get_string_from_ascii() == "DDS ":
		# DDS 头布局：magic 0, dwSize 4, flags 8, height 12, width 16, pitch 20,
		# mip 28, ddspf 76, dwFlags 80, fourCC 84, bits 88, masks 92/96/100/104。
		# fourCC 必须在 84，不是 20——以前读成 pitch，DXT 全部退化成 1×1。
		var fourcc := blob.slice(84, 88).get_string_from_ascii()
		var off := 128
		if fourcc == "DX10":
			off += 20
		match fourcc:
			"DXT1":
				return _dxt(1, blob.slice(off), w, h)
			"DXT2", "DXT3":
				return _dxt(3, blob.slice(off), w, h)
			"DXT4", "DXT5":
				return _dxt(5, blob.slice(off), w, h)
			"DX10":
				# DX10 扩展头里的 DXGI format 暂不展开；先按 32 位裸像素兜底。
				return _dds_uncompressed(blob.slice(off), w, h, 32,
					blob.decode_u32(92), blob.decode_u32(96), blob.decode_u32(100), blob.decode_u32(104))
		var bits := blob.decode_u32(88)
		if bits in [16, 24, 32]:
			return _dds_uncompressed(blob.slice(off), w, h, bits,
				blob.decode_u32(92), blob.decode_u32(96), blob.decode_u32(100), blob.decode_u32(104))
	# 裸像素：按 pixel_format 当普通帧解
	var need := w * h * 4
	if blob.size() < need:
		blob.resize(need)
	match pf:
		T_ARGB8888:
			var d := _bgra_frame(blob, w, h, 0, 0)
			return (d["image"] as Image).get_data()
		T_ARGB4444:
			return _from_4444(blob, w, h)
		T_ARGB1555:
			return _from_1555(blob, w, h)
	return PackedByteArray()


## DDS 里没有 DXT fourCC 的裸像素（ARGB8888/1555/4444 等）：按头里的 bit mask 解，
## 不能把 128 B 头当像素。JS NPK Inspector 的 decodeUncompressedDds 同逻辑。
func _dds_uncompressed(src: PackedByteArray, w: int, h: int, bits: int, rm: int, gm: int, bm: int, am: int) -> PackedByteArray:
	var bpp := bits / 8
	var need := w * h * bpp
	if src.size() < need:
		return PackedByteArray()
	var rs := _mask_shift(rm)
	var gs := _mask_shift(gm)
	var bs := _mask_shift(bm)
	var ash := _mask_shift(am)
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var p := 0
	for i in w * h:
		var v := 0
		for k in bpp:
			v |= int(src[p + k]) << (8 * k)
		p += bpp
		var q := i * 4
		out[q] = _mask_channel(v, rm, rs)
		out[q + 1] = _mask_channel(v, gm, gs)
		out[q + 2] = _mask_channel(v, bm, bs)
		out[q + 3] = 255 if am == 0 else _mask_channel(v, am, ash)
	return out


func _mask_shift(mask: int) -> Array[int]:
	if mask == 0:
		return [0, 0]
	var s := 0
	while ((mask >> s) & 1) == 0:
		s += 1
	return [s, mask >> s]


func _mask_channel(v: int, mask: int, sh: Array[int]) -> int:
	if mask == 0:
		return 0
	var m := sh[1]
	return 0 if m <= 0 else (((v & mask) >> sh[0]) * 255) / m


## DXT1/3/5 -> RGBA8
func _dxt(mode: int, src: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var block := 8 if mode == 1 else 16
	var bw := (w + 3) / 4
	var bh := (h + 3) / 4
	var p := 0
	for by in bh:
		for bx in bw:
			if p + block > src.size():
				return out
			var cbase := p if mode == 1 else p + 8
			var c0: int = src[cbase] | (src[cbase + 1] << 8)
			var c1: int = src[cbase + 2] | (src[cbase + 3] << 8)
			var col := _dxt_colors(c0, c1)
			var c0_le_c1 := c0 <= c1
			for yy in 4:
				for xx in 4:
					var idx := 0
					if mode == 1:
						var bits: int = src[cbase + 4 + yy]
						idx = (bits >> (xx * 2)) & 3
					else:
						var bits2: int = src[cbase + 4 + yy]
						idx = (bits2 >> (xx * 2)) & 3
					var px: int = bx * 4 + xx
					var py: int = by * 4 + yy
					if px >= w or py >= h:
						continue
					var q := (py * w + px) * 4
					var c: PackedInt32Array = col[idx]
					var a := 255
					if mode == 1:
						# DXT1 的 c0<=c1 表里 index 3 是透明色（1-bit alpha）
						if c0_le_c1 and idx == 3:
							a = 0
					if mode == 3:
						# 4 bit alpha
						var byte_i: int = p + (yy * 2) + (xx >> 1)
						var nib: int = (src[byte_i] >> ((xx & 1) * 4)) & 0xF
						a = nib * 17
					elif mode == 5:
						# alpha0/alpha1 + 3 bit index，row-major 48 bit；按 DXT5 标准表查
						var a0: int = src[p]
						var a1: int = src[p + 1]
						var atab: Array[int] = [a0, a1]
						if a0 > a1:
							for i in range(1, 7):
								atab.append(int(round(((7 - i) * a0 + i * a1) / 7.0)))
						else:
							for i in range(1, 5):
								atab.append(int(round(((5 - i) * a0 + i * a1) / 5.0)))
							atab.append(0)
							atab.append(255)
						var bits3 := 0
						var base: int = p + 2
						var bitpos: int = (yy * 4 + xx) * 3
						var byte0 := base + (bitpos / 8)
						if byte0 + 1 < src.size():
							var v: int = src[byte0] | (src[byte0 + 1] << 8)
							bits3 = (v >> (bitpos % 8)) & 7
						a = atab[bits3]
					out[q] = c[0]
					out[q + 1] = c[1]
					out[q + 2] = c[2]
					out[q + 3] = a
			p += block
	return out


func _dxt_colors(c0: int, c1: int) -> Array:
	var r0 := (c0 >> 11) & 0x1F
	var g0 := (c0 >> 5) & 0x3F
	var b0 := c0 & 0x1F
	var r1 := (c1 >> 11) & 0x1F
	var g1 := (c1 >> 5) & 0x3F
	var b1 := c1 & 0x1F
	var p0 := [((r0 << 3) | (r0 >> 2)), ((g0 << 2) | (g0 >> 4)), ((b0 << 3) | (b0 >> 2))]
	var p1 := [((r1 << 3) | (r1 >> 2)), ((g1 << 2) | (g1 >> 4)), ((b1 << 3) | (b1 >> 2))]
	# DXT1/3/5 的颜色块统一用 4 色插值；DXT1 的透明只由 alpha/index 3 表达。
	return [p0, p1,
		[int(round((2.0 * p0[0] + p1[0]) / 3.0)), int(round((2.0 * p0[1] + p1[1]) / 3.0)), int(round((2.0 * p0[2] + p1[2]) / 3.0))],
		[int(round((p0[0] + 2.0 * p1[0]) / 3.0)), int(round((p0[1] + 2.0 * p1[1]) / 3.0)), int(round((p0[2] + 2.0 * p1[2]) / 3.0))]]
