extends SceneTree
## DXT 解码回归：颜色块用 4 色插值；DXT1 的 c0<=c1 + index3 必须透明；
## DXT5 alpha 必须按标准 7/5 分母表，不能用 6 分母。
var _ok := 0
var _fail := 0


func _init() -> void:
	var img := NpkImage.new()

	# DXT1：c0<=c1，所有索引 3 -> 透明
	var d1 := PackedByteArray()
	d1.resize(8)
	d1[0] = 0x00; d1[1] = 0x00
	d1[2] = 0xFF; d1[3] = 0xFF
	for i in range(4, 8): d1[i] = 0xFF
	var o1: PackedByteArray = img._dxt(1, d1, 4, 4)
	_check("dxt1 c0<=c1 idx3 alpha", o1[3], 0)

	# DXT1：c0>c1，索引 3 仍是颜色，alpha 255
	var d1b := d1.duplicate()
	d1b[0] = 0xFF; d1b[1] = 0xFF
	d1b[2] = 0x00; d1b[3] = 0x00
	var o1b: PackedByteArray = img._dxt(1, d1b, 4, 4)
	_check("dxt1 c0>c1 idx3 alpha", o1b[3], 255)

	# DXT3：alpha 每像素 4bit，0x7 -> 119
	var d3 := PackedByteArray()
	d3.resize(16)
	for i in range(0, 8): d3[i] = 0x77
	var o3: PackedByteArray = img._dxt(3, d3, 4, 4)
	_check("dxt3 nibble alpha", o3[3], 119)
	_check("dxt3 nibble alpha x1", o3[7], 119)

	# DXT3/DXT5 的颜色端点必须在 p+8（p 是 alpha 块）；否则颜色会从 alpha 块读成黑色
	var dc := PackedByteArray()
	dc.resize(16)
	dc.encode_u16(8, 0xF800)   # c0 = red
	dc.encode_u16(10, 0x001F)  # c1 = blue
	var oc3: PackedByteArray = img._dxt(3, dc, 4, 4)
	_check("dxt3 color base R", oc3[0], 255)
	var oc5: PackedByteArray = img._dxt(5, dc, 4, 4)
	_check("dxt5 color base R", oc5[0], 255)

	# DXT5：a0=255,a1=0，所有索引 2 -> round(6*255/7)=219
	var d5 := PackedByteArray()
	d5.resize(16)
	d5[0] = 255; d5[1] = 0
	var code := 0
	for i in range(16): code |= 2 << (i * 3)
	for i in range(6): d5[2 + i] = (code >> (8 * i)) & 0xFF
	var o5: PackedByteArray = img._dxt(5, d5, 4, 4)
	_check("dxt5 index2 alpha", o5[3], 219)

	# DXT5：a0<=a1，索引 6 -> 0，索引 7 -> 255
	var d5b := PackedByteArray()
	d5b.resize(16)
	d5b[0] = 0; d5b[1] = 255
	var code2 := 0
	for i in range(16): code2 |= 6 << (i * 3)
	for i in range(6): d5b[2 + i] = (code2 >> (8 * i)) & 0xFF
	var o5b: PackedByteArray = img._dxt(5, d5b, 4, 4)
	_check("dxt5 a0<=a1 idx6 alpha", o5b[3], 0)
	var code3 := 0
	for i in range(16): code3 |= 7 << (i * 3)
	for i in range(6): d5b[2 + i] = (code3 >> (8 * i)) & 0xFF
	var o5c: PackedByteArray = img._dxt(5, d5b, 4, 4)
	_check("dxt5 a0<=a1 idx7 alpha", o5c[3], 255)

	# 未压缩 DDS：128B 头 + A8R8G8B8 裸像素，必须跳过 DDS 头再按 mask 解
	var raw := PackedByteArray()
	raw.resize(128 + 8)
	raw[0] = 0x44; raw[1] = 0x44; raw[2] = 0x53; raw[3] = 0x20  # "DDS "
	raw.encode_u32(12, 1)   # height
	raw.encode_u32(16, 2)   # width
	raw.encode_u32(88, 32)  # bits
	raw.encode_u32(92, 0x00FF0000)
	raw.encode_u32(96, 0x0000FF00)
	raw.encode_u32(100, 0x000000FF)
	raw.encode_u32(104, 0xFF000000)
	raw[128] = 0x33; raw[129] = 0x22; raw[130] = 0x11; raw[131] = 0xFF
	raw[132] = 0x66; raw[133] = 0x55; raw[134] = 0x44; raw[135] = 0xFF
	var oraw: PackedByteArray = img._decode_dds(raw, 2, 1, NpkImage.T_ARGB8888)
	_check("dds raw R", oraw[0], 0x11)
	_check("dds raw G", oraw[1], 0x22)
	_check("dds raw B", oraw[2], 0x33)
	_check("dds raw A", oraw[3], 0xFF)
	_check("dds raw px2 R", oraw[4], 0x44)

	print("== %d ok, %d fail ==" % [_ok, _fail])
	quit(0 if _fail == 0 else 1)


func _check(name: String, got: int, want: int) -> void:
	if got == want:
		_ok += 1
		print("ok   %s = %d" % [name, got])
	else:
		_fail += 1
		print("FAIL %s = %d，期望 %d" % [name, got, want])
