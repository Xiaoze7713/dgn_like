## 运行时 NPK 读取自测：索引查询 / IMG 解码 / 像素摘要
##
## 跑法：
##   XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=$PWD/client \
##     ./tools/godot.sh --headless --script res://tests/test_npk_store.gd
##
## 输出每帧的 md5(名字:帧号:宽度:高度:RGBA字节)，用来和 Python 侧
## `tools/npk_parser.py` 解出来的像素逐一比对（见 tools/verify_npk_gd.py）。
extends SceneTree

const CASES := [
	["character/swordman/equipment/avatar/skin/sm_body0001.img", [0, 90, 180, 181, 184]],
	["character/swordman/equipment/avatar/coat/sm_coat0000a.img", [180, 184]],
	["map/02tile03.img", [0]],
	["character/swordman/equipment/weapon/sswd/sswd1200b.img", [0, 1]],
	["character/swordman/atequipment/weapon/sswd/(tn)sg_sswd0912a.img", [0, 1, 2]],
]

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var store := NpkStore.new()
	var idx_path := "res://assets/npk-index.bin"
	if not store.open(idx_path):
		print("FAIL 索引打不开")
		quit(1)
		return
	print("索引 ", store.stats()["index"])
	print("图包目录 ", store.base_dir)
	if not store.is_ready():
		print("FAIL 图包目录不可用")
		quit(1)
		return
	print("打开索引耗时 ", Time.get_ticks_msec() - t0, " ms")

	var total := 0
	var t1 := Time.get_ticks_msec()
	for c in CASES:
		var p: String = c[0]
		var im := store.image(p)
		if im == null:
			print("MISS ", p)
			continue
		print("IMG %s ver=%d frames=%d table=%d dds=%d warn=%d" % [
			p, im.version, im.frame_count, im.table_length,
			im.dds_table.size(), im.warnings.size()])
		for fr in c[1]:
			var got := im.frame(fr)
			var rect: Rect2i = got["rect"]
			var img: Image = got["image"]
			var fmt_name := "RGBA8" if img.get_format() == Image.FORMAT_RGBA8 else "BGRA8"
			print("  F%d rect=(%d,%d,%d,%d) fmt=%s md5=%s" % [
				fr, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
				fmt_name, _md5(img)])
			total += 1
	var dt := Time.get_ticks_msec() - t1
	print("解码 %d 帧，%d ms" % [total, dt])
	print("stats ", store.stats())
	store.close()
	quit(0)


func _md5(img: Image) -> String:
	var data := img.get_data()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(data)
	return ctx.finish().hex_encode()
