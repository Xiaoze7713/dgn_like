class_name PvfAnimation
extends RefCounted
## `.ani` 动画文件解析器。
##
## 二进制格式（小端，全部长度前缀）：
##   u16 frameCount
##   u16 resourceCount;  resourceCount × (i32 len + char[len])   ← 图集模板（`%04d` 占位）
##   u16 paramCount;     paramCount × (u16 type + 载荷)
##   frameCount × 帧：
##       u16 boxCount;   boxCount × (u16 boxType + 6 × i32)      ← 14 伤害盒 / 15 攻击盒
##       u16 imgId                                    （0xFFFF = 无贴图）
##       u16 imgParam                                 （imgId==0xFFFF 时**部分文件省略**）
##       i32 x; i32 y
##       u16 propCount;  propCount × (u16 type + 载荷)
##
## 帧属性 type → 载荷（与 `tools/pvf_unpack.py` 一致）：
##   0 loop(b)      1 shadow(b)     3 coord(u16)      7 rate_x(f32)+rate_y(f32)
##   8 rotate(i32)  9 color(u32)   10 interpolation(b)  11 effect(u16)[+5:3B / +6:2×u16]
##  12 delay(i32)  13 damageType(u16)  16 sound(str)  23 setFlag(i32)
##  24 flip(u16)   25 loopStart(无)    26 loopEnd(i32) 27 clip(4×i16)
##   2,4,5,6,14,15,17,18,19,20,21,22 → 已知无载荷，直接跳过
##
## **变体问题**：imgId==0xFFFF 时 imgParam 有无两种写法；全局 coord 有人写 u16 有人写 i32；
## 极少数文件参数区带未知类型（实测 18）。判定办法 = 「正好把 buffer 消费完」，
## 自证、不需要外部真值。

const ANI_LOOP: int = 0
const ANI_SHADOW: int = 1
const ANI_COORD: int = 3
const ANI_IMAGE_RATE: int = 7
const ANI_IMAGE_ROTATE: int = 8
const ANI_RGBA: int = 9
const ANI_INTERPOLATION: int = 10
const ANI_GRAPHIC_EFFECT: int = 11
const ANI_DELAY: int = 12
const ANI_DAMAGE_TYPE: int = 13
const ANI_DAMAGE_BOX: int = 14
const ANI_ATTACK_BOX: int = 15
const ANI_PLAY_SOUND: int = 16
const ANI_PRELOAD: int = 17
const ANI_SPECTRUM: int = 18
const ANI_SET_FLAG: int = 23
const ANI_FLIP_TYPE: int = 24
const ANI_LOOP_START: int = 25
const ANI_LOOP_END: int = 26
const ANI_CLIP: int = 27

## 已知但无载荷
const _NO_PAYLOAD: Array = [2, 4, 5, 6, 14, 15, 17, 18, 19, 20, 21, 22]

var last_variant: Dictionary = {}


## 解析一个 .ani 的字节。永远返回非 null（全变体失败时返回空 AniData）。
static func parse(buf: PackedByteArray, strict: bool = false) -> PvfTypes.AniData:
	var variants: Array[Dictionary] = [
		{"omit_imgparam_if_ff": true, "coord_size": 4, "strict_types": strict, "unknown": -1},
		{"omit_imgparam_if_ff": true, "coord_size": 2, "strict_types": strict, "unknown": -1},
		{"omit_imgparam_if_ff": false, "coord_size": 4, "strict_types": strict, "unknown": -1},
		{"omit_imgparam_if_ff": false, "coord_size": 2, "strict_types": strict, "unknown": -1},
	]
	if not strict:
		# 未知参数类型：用「精确消费」反推载荷长度（0..32 字节）
		for n in range(0, 33):
			variants.append({"omit_imgparam_if_ff": true, "coord_size": 4,
				"strict_types": false, "unknown": n})
		for n in range(0, 33):
			variants.append({"omit_imgparam_if_ff": false, "coord_size": 4,
				"strict_types": false, "unknown": n})

	var best: PvfTypes.AniData = null
	for v in variants:
		var r := _parse_variant(buf, v)
		if r == null:
			continue
		r.variant = v
		if r.is_exact():
			return r
		if best == null or absi(r.bytes_consumed - r.bytes_total) < absi(best.bytes_consumed - best.bytes_total):
			best = r
	if best != null:
		return best
	var empty := PvfTypes.AniData.new()
	empty.bytes_total = buf.size()
	return empty


# =====================================================================
static func _parse_variant(buf: PackedByteArray, v: Dictionary) -> PvfTypes.AniData:
	var rd := _Reader.new(buf)
	var out := PvfTypes.AniData.new()
	out.bytes_total = buf.size()

	var frame_count := rd.u16()
	if not rd.ok:
		return null
	out.frame_count = frame_count
	var res_count := rd.u16()
	if not rd.ok:
		return null
	var sprites := PackedStringArray()
	sprites.resize(res_count)
	for i in res_count:
		var s := rd.str()
		if not rd.ok:
			return null
		sprites[i] = s.to_lower()
	out.sprites = sprites

	var pcount := rd.u16()
	if not rd.ok:
		return null
	for _i in pcount:
		var t := rd.u16()
		if not rd.ok:
			return null
		match t:
			ANI_LOOP:
				out.params["loop"] = rd.s8()
			ANI_SHADOW:
				out.params["shadow"] = rd.s8()
			ANI_COORD:
				out.params["coord"] = rd.i32() if int(v["coord_size"]) == 4 else rd.u16()
			ANI_SPECTRUM:
				var unk := int(v["unknown"])
				if unk >= 0:
					rd.skip(unk)
				else:
					out.params["spectrum"] = true
			_:
				var unk2 := int(v["unknown"])
				if unk2 >= 0:
					rd.skip(unk2)
				elif bool(v["strict_types"]):
					return null
		if not rd.ok:
			return null

	var omit_ff := bool(v["omit_imgparam_if_ff"])
	for _fi in frame_count:
		var fr := PvfTypes.AniFrame.new()
		var nbox := rd.u16()
		if not rd.ok:
			return null
		for _b in nbox:
			var bt := rd.u16()
			var box: Array = [rd.i32(), rd.i32(), rd.i32(), rd.i32(), rd.i32(), rd.i32()]
			if not rd.ok:
				return null
			if bt == ANI_DAMAGE_BOX:
				fr.damage_boxes.append(box)
			elif bt == ANI_ATTACK_BOX:
				fr.attack_boxes.append(box)
			else:
				fr.props["box_%d" % bt] = box
		fr.img_id = rd.u16()
		if not rd.ok:
			return null
		if omit_ff and fr.img_id == 0xFFFF:
			fr.img_param = -1
		else:
			fr.img_param = rd.u16()
		fr.sprite = out.sprites[fr.img_id] if (fr.img_id >= 0 and fr.img_id < out.sprites.size()) else ""
		fr.x = rd.i32()
		fr.y = rd.i32()
		var np := rd.u16()
		if not rd.ok:
			return null
		for _p in np:
			var t := rd.u16()
			if not rd.ok:
				return null
			match t:
				ANI_LOOP:
					fr.props["loop"] = rd.s8()
				ANI_SHADOW:
					fr.props["shadow"] = rd.s8()
				ANI_INTERPOLATION:
					fr.props["interpolation"] = rd.s8()
				ANI_COORD:
					fr.props["coord"] = rd.u16()
				ANI_IMAGE_RATE:
					fr.props["rate_x"] = rd.f32()
					fr.props["rate_y"] = rd.f32()
				ANI_IMAGE_ROTATE:
					fr.props["rotate"] = rd.i32()
				ANI_RGBA:
					fr.props["color"] = rd.u32()
				ANI_GRAPHIC_EFFECT:
					var it := rd.u16()
					fr.props["effect"] = it
					if it == 5:
						fr.props["effect_color"] = [rd.u8(), rd.u8(), rd.u8()]
					elif it == 6:
						fr.props["effect_pos"] = [rd.u16(), rd.u16()]
				ANI_DELAY:
					fr.delay = rd.i32()
				ANI_DAMAGE_TYPE:
					fr.props["damage_type"] = rd.u16()
				ANI_PLAY_SOUND:
					fr.props["sound"] = rd.str()
				ANI_SET_FLAG:
					fr.props["set_flag"] = rd.i32()
				ANI_FLIP_TYPE:
					fr.props["flip"] = rd.u16()
				ANI_LOOP_START:
					fr.props["loop_start"] = true
				ANI_LOOP_END:
					fr.props["loop_end"] = rd.i32()
				ANI_CLIP:
					fr.props["clip"] = [rd.i16(), rd.i16(), rd.i16(), rd.i16()]
				_:
					if _NO_PAYLOAD.has(t):
						pass
					elif bool(v["strict_types"]):
						return null
			if not rd.ok:
				return null
		out.frames.append(fr)
	out.bytes_consumed = rd.pos
	return out


## 帧号 → 图集路径（look/color 填进模板）
static func sheet_of(ani: PvfTypes.AniData, frame_index: int, look: int = 0, color: int = 0) -> String:
	if ani == null or frame_index < 0 or frame_index >= ani.frames.size():
		return ""
	return ani.sheet_path(ani.frames[frame_index], look, color)


# =====================================================================
## 小端读取器（越界即置 ok=false，不再抛异常）
class _Reader:
	var buf: PackedByteArray
	var pos: int = 0
	var ok: bool = true

	func _init(b: PackedByteArray) -> void:
		buf = b

	func _need(n: int) -> bool:
		if not ok or pos + n > buf.size():
			ok = false
			return false
		return true

	func skip(n: int) -> void:
		if _need(n):
			pos += n

	func u8() -> int:
		if not _need(1):
			return 0
		var v := buf[pos]
		pos += 1
		return v

	func s8() -> int:
		var v := u8()
		return v - 256 if v > 127 else v

	func u16() -> int:
		if not _need(2):
			return 0
		var v := buf.decode_u16(pos)
		pos += 2
		return v

	func i16() -> int:
		if not _need(2):
			return 0
		var v := buf.decode_s16(pos)
		pos += 2
		return v

	func u32() -> int:
		if not _need(4):
			return 0
		var v := buf.decode_u32(pos)
		pos += 4
		return v

	func i32() -> int:
		if not _need(4):
			return 0
		var v := buf.decode_s32(pos)
		pos += 4
		return v

	func f32() -> float:
		if not _need(4):
			return 0.0
		var v := buf.decode_float(pos)
		pos += 4
		return v

	func str() -> String:
		var n := i32()
		if not ok or n < 0 or pos + n > buf.size():
			ok = false
			return ""
		var s := buf.slice(pos, pos + n).get_string_from_ascii()
		pos += n
		return s
