extends SceneTree
## 端到端探针：用 PvfLoader 打开 pvf_to_utf8.py 产出的 UTF-8 包，
## 打印中文，确认 GDScript 侧不需要任何 GBK 解码器也能正确显示。
##
## 跑法：
##   XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
##     ./tools/godot.sh --headless --script res://tests/probe_utf8_pvf.gd


func _initialize() -> void:
	var path: String = OS.get_environment("PVF_UTF8")
	if path.is_empty():
		path = "/home/sunmingze/dnf_like/build/Script.utf8.pvf"
	print("== 打开 ", path)
	var t0: int = Time.get_ticks_msec()
	var pvf := PvfLoader.new()
	if pvf.open(path) != OK:
		print("!! 打开失败")
		quit(1)
		return
	print("   条目 %d，耗时 %d ms" % [pvf.archive.entries.size(), Time.get_ticks_msec() - t0])

	# 1) 文档里的中文：默认上衣的 [name]
	var equ_path := "equipment/character/swordman/avatar/coat/acoat_default.equ"
	var doc := pvf.get_document(equ_path)
	if doc != null:
		var name_node := doc.first("name")
		if name_node != null:
			print("   [name] = ", name_node.attrs[0] if name_node.attrs.size() > 0 else "(空)")
		print("   层数 = ", doc.child_nodes("layer variation").size())

	# 2) 字符串表里挑几条中文，验证是合法 UTF-8
	var ar: PvfArchive = pvf.archive
	ar.load_strings()
	var all: PackedStringArray = ar.string_bin()
	var shown := 0
	for i in all.size():
		var s: String = all[i]
		if s.length() < 2:
			continue
		for j in s.length():
			var c: int = s.unicode_at(j)
			if c > 0x7F:
				shown += 1
				print("   串[%d] = %s" % [i, s.substr(0, 40)])
				break
		if shown >= 5:
			break

	pvf.close()
	print("== 完成")
	quit(0)
