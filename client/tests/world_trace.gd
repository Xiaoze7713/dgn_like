extends SceneTree
## 城镇装配单步清单：把「一个城镇 area 是怎么拼出来的」按加载顺序逐条打印。
## 用法：--town=hendonmyre --area=0 --out=/path/report.txt
## 这里打印的每个数字都对应 game/world/build/room_builder.gd 里的同一行公式，
## 改公式时记得同步（文件里每个区块都标了行号）。

var _town := "hendonmyre"
var _area := 0
var _out := "user://world_trace.txt"
var _lines: PackedStringArray = []
var _content: PackContent
var _store: NpkStore
var _done := false
var _frame := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--town="):
			_town = a.substr(7)
		elif a.begins_with("--area="):
			_area = int(a.substr(7))
		elif a.begins_with("--out="):
			_out = a.substr(6)
	_content = PackContent.new()
	_content.load_index()
	_store = NpkStore.new(OS.get_environment("DNF_NPK_LATEST"))
	if not _store.open("res://assets/npk-index-latest.bin"):
		push_error("npk index 打不开")


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_trace()
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
	print("[trace] wrote ", _out)
	return true


func _line(s := "") -> void:
	_lines.append(s)
	print(s)


func _rect(img: String, frame: int) -> Rect2i:
	if _store == null or img == "":
		return Rect2i()
	return _store.frame_rect(img, frame)


func _ani_frame(path: String) -> Dictionary:
	var a := _content.ani(path)
	if a == null or a.frames.is_empty():
		return {}
	return a.frames[0]


func _trace() -> void:
	var town_path := _town if _town.contains("/") else "town/%s.twn" % _town
	var town := _content.town(_content.key_of(town_path))
	_line("=== 城镇装配清单 town=%s area=%d ===" % [_town, _area])
	_line("")
	_line("[0] 数据来源链路（每一跳都是一次文件读取）")
	_line("    towns/%s.json  ← tools/pvf_world/build_pack.py 编译自 %s" % [_content.key_of(town_path), town_path])
	_line("      └ areas[%d] → map 路径" % _area)
	_line("")

	var areas: Array = town.areas
	if _area < 0 or _area >= areas.size():
		_line("!! area 越界，共 %d 个" % areas.size())
		return
	var area: Dictionary = areas[_area]
	var map_path := str(area.get("map", ""))
	_line("[1] %s → [area] 第 %d 条" % [town_path, _area])
	_line("    map      : %s" % map_path)
	_line("    type     : %s   args=%s" % [str(area.get("type", "")), str(area.get("args", []))])
	_line("    minimap  : %s   (x0 y0 x1 y1)" % str(area.get("minimap", [])))
	if str(area.get("type", "")) == "dungeon gate":
		var did := int(str(area.get("args", ["-1"])[0]))
		_line("    → 副本入口 id=%d（E 键从这里进 dungeon）" % did)
	_line("")

	var room := _content.map_room(map_path)
	var defs := _content.tiles_for(room)
	_line("[2] %s 解析结果" % map_path)
	_line("    type=%s  dungeon_id=%s  tiles=%d  width=%.0f  sight=%s" % [
		str(room.type), str(room.dungeon_id), room.tile_count(), room.width(), str(room.sight)])
	_line("    background_anims=%d  [animation]=%d  [passive object]=%d  NPC=%d" % [
		room.background_anims.size(), room.anims.size(), room.objects.size(), room.npcs.size()])
	_line("    pathgate(左 右 上 下)=%s" % str(room.pathgate))
	_line("    town_movable=%d 组 (x y w h townIdx areaIdx)" % int(room.town_movable.size() / 6))
	_line("    virtual_movable=%d 组 (x y w h)" % int(room.virtual_movable.size() / 4))
	_line("")

	# ---------------- 通行网格 ----------------
	var grid := PassGrid.new()
	grid.build(room.tiles, defs)
	_line("[3] 通行网格 PassGrid.build()（pass_grid.gd:28）")
	_line("    cols=%d rows=%d  格=%.0fpx  房间=%.0fx%.0f" % [grid.cols, grid.rows, PassGrid.CELL, grid.width, grid.height])
	_line("    可走比例=%.0f%%" % (grid.walkable_ratio() * 100.0))
	_line("    行→屏幕 y：屏幕行 r 的 y 区间 = [r*16, r*16+16)，pass 数组第 n 行落在这里（底边对齐后再翻转）")
	_line("    下面是整个房间的通行表压缩视图（每 16 列取 1 格，# = 可走）：")
	var step := 16
	var head := "        "
	for x in range(0, grid.cols, step):
		head += "%d" % (int(x / grid.cols * 10) % 10)
	_line(head)
	for y in grid.rows:
		var row := "     y=%-4d " % (y * 16)
		for x in range(0, grid.cols, step):
			row += "#" if grid.walkable(x, y) else "."
		_line(row)
	_line("")

	# ---------------- 背景层 ----------------
	_line("[4] 背景层（先画；z=-2000 远景 / -1900 中景，横向平铺）")
	_line("    room_builder.gd:_build_background()")
	var bi := 0
	for b in room.background_anims:
		bi += 1
		var d: Dictionary = b
		var f := _ani_frame(str(d.get("path", "")))
		if f.is_empty():
			continue
		var r := _rect(str(f.get("img", "")), int(f.get("frame", 0)))
		var layers_txt := "distantback→-2000" if str(d.get("layer", "")).contains("distant") else "middleback→-1900"
		_line("    #%d %-26s layer=%-12s → %s" % [bi, str(d.get("ani", "")), str(d.get("layer", "")), layers_txt])
		_line("        img=%-44s frame=%d canvas=(%d,%d) size=%dx%d  dy=%d" % [
			str(f.get("img", "")), int(f.get("frame", 0)), r.position.x, r.position.y, r.size.x, r.size.y, int(f.get("dy", 0))])
		var reps := int(ceil((room.width() + 2304.0) / maxf(float(r.size.x), 1.0))) + 1
		_line("        x 平铺 %d 片（图宽 %d，从 -1152 起）：%s …" % [reps, r.size.x, str(_tile_xs(r.size.x, reps))])
		_line("        y = canvas.y + dy = %d + %d = %d" % [r.position.y, int(f.get("dy", 0)), r.position.y + int(f.get("dy", 0))])
	_line("")

	# ---------------- 地砖 ----------------
	_line("[5] 地砖层 z=-50（从左到右，每块 224 宽）")
	_line("    room_builder.gd:_build_tiles()")
	for i in room.tiles.size():
		var til := str(room.tiles[i])
		var t: TileDef = defs.get(til, null)
		if t == null:
			_line("    #%d %s <缺定义>" % [i, til])
			continue
		var r := _rect(t.img, t.frame)
		var pos_y := int(grid.height) + t.img_pos - r.size.y
		_line("    #%-2d %s" % [i, til])
		_line("        img=%-44s frame=%d  canvas=(%d,%d) size=224x%d  img_pos=%d  rows=%d" % [
			t.img, t.frame, r.position.x, r.position.y, r.size.y, t.img_pos, t.rows])
		_line("        pos = (%d*224 + %d, %d + %d - %d) = (%d, %d)" % [
			i, r.position.x, int(grid.height), t.img_pos, r.size.y, i * 224 + r.position.x, pos_y])
		_line("        pass: 数组第0..N行=%s（行序从底部起算，见 pass_grid.gd:45 的注释）" % _pass_summary(t))
	_line("")

	# ---------------- 装饰 ----------------
	_line("[6] 装饰层 [animation]（按文件顺序；z = clamp(y-480)，y 大的压在上面）")
	_line("    room_builder.gd:_build_deco()   位置 = (x + canvas.x, y + canvas.y + dy)")
	var order := room.anims.duplicate()
	order.sort_custom(func(a, b): return int(a.get("y", 0)) < int(b.get("y", 0)))
	var idx := 0
	for a in order:
		idx += 1
		var d: Dictionary = a
		var f := _ani_frame(str(d.get("path", "")))
		if f.is_empty():
			_line("    #%-2d layer=%-10s x=%-5s y=%-5s <ani 缺帧> %s" % [idx, str(d.get("layer", "")), str(d.get("x", "")), str(d.get("y", "")), str(d.get("path", ""))])
			continue
		var r := _rect(str(f.get("img", "")), int(f.get("frame", 0)))
		var px := int(d.get("x", 0)) + r.position.x
		var py := int(d.get("y", 0)) + r.position.y + int(f.get("dy", 0))
		_line("    #%-2d layer=%-10s (%4d,%4d) + canvas(%d,%d) + dy(%d) → (%4d,%4d)..(%4d,%4d)  z=%d" % [
			idx, str(d.get("layer", "")), int(d.get("x", 0)), int(d.get("y", 0)), r.position.x, r.position.y,
			int(f.get("dy", 0)), px, py, px + r.size.x, py + r.size.y, clampi(int(d.get("y", 0)) - 480, -2000, 2000)])
	_line("")

	# ---------------- 被动对象 ----------------
	_line("[7] 被动对象 [passive object]（.obj → .act → .ani；位置同怪物口径：从画布底往上量）")
	_line("    room_builder.gd:_build_objects() / map_y()")
	idx = 0
	for o in room.objects:
		idx += 1
		var d: Dictionary = o
		var f := _ani_frame(str(d.get("ani", "")))
		var r := _rect(str(f.get("img", "")), int(f.get("frame", 0)))
		var col := int(floor(float(d.get("x", 0)) / 224.0))
		var bottom := int(grid.height)
		if col >= 0 and col < room.tiles.size():
			var t: TileDef = defs.get(room.tiles[col], null)
			if t != null:
				bottom += t.img_pos
		var py := bottom - int(d.get("y", 0))
		_line("    #%-2d id=%-8s (%4d,%4d) obj=%-60s" % [idx, str(d.get("id", "")), int(d.get("x", 0)), int(d.get("y", 0)), str(d.get("obj", ""))])
		_line("        ani=%-56s img=%-40s size=%dx%d" % [str(d.get("ani", "")), str(f.get("img", "")), r.size.x, r.size.y])
		_line("        y = (网格高 %d + 地砖 img_pos %d) - %d = %d" % [int(grid.height), bottom - int(grid.height), int(d.get("y", 0)), py])
	_line("")

	# ---------------- NPC / 门 ----------------
	_line("[8] NPC / 门")
	idx = 0
	for n in room.npcs:
		idx += 1
		var d: Dictionary = n
		_line("    NPC #%-2d id=%-6s dir=%-8s (%4d,%4d)  → 屏幕 y = 画布底 - %d = %d" % [
			idx, str(d.get("id", "")), str(d.get("dir", "")), int(d.get("x", 0)), int(d.get("y", 0)),
			int(d.get("y", 0)), int(grid.height) - int(d.get("y", 0))])
	var g := room.gates()
	if g.is_empty():
		_line("    pathgate 无（这张图没有 [pathgate pos]，换图靠 town_movable / movable area）")
	for k in ["left", "right", "up", "down"]:
		if not g.has(k):
			continue
		var v: Vector2 = g[k]
		_line("    pathgate %-5s = (%.0f, %.0f)" % [k, v.x, v.y])
	_line("")

	_line("[9] 装配顺序（节点树 = 绘制层级；同 z 内按添加顺序）")
	_line("    Background(-2000/-1900) → Tiles(-50) → Deco(z=y-480) → Objects(z=锚点y) → Gates(3000) → Actors(z=脚点y)")
	_line("    换图触发：[town movable area] 每 6 个数一组 (x y w h townIdx areaIdx)，townIdx=-1 = 副本开始")
	for i in range(0, mini(room.town_movable.size(), 36), 6):
		_line("      mov #%d  x=%d y=%d w=%d h=%d → town=%d area=%d" % [
			i / 6, room.town_movable[i], room.town_movable[i + 1], room.town_movable[i + 2],
			room.town_movable[i + 3], room.town_movable[i + 4], room.town_movable[i + 5]])


func _tile_xs(w: int, reps: int) -> String:
	var out: Array[String] = []
	for i in mini(reps, 6):
		out.append(str(-1152 + i * w))
	return ", ".join(out)


func _pass_summary(t: TileDef) -> String:
	var parts: Array[String] = []
	var cur := -1
	var start := 0
	for r in t.rows:
		var v := t.pass_at(0, r)
		if v != cur:
			if cur != -1:
				parts.append("%d..%d=%d" % [start, r - 1, cur])
			cur = v
			start = r
	parts.append("%d..%d=%d" % [start, t.rows - 1, cur])
	return ", ".join(parts)
