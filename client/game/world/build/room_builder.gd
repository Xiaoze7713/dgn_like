class_name RoomBuilder
extends RefCounted
## 把 MapRoom 变成一个可玩的 Node2D：
##   Background（背景动画）/ Tiles（地砖）/ Deco（[animation] 装饰层）/ Objects（被动对象）
##   / Gates（四向门标记）/ Actors（怪物、NPC 动画；缺资源回退占位）/ PassGrid。
## 位置、图层、动画全部来自内容包与 NPF 图集，不写死任何房间。

const BLOCK_W := 224.0
const MovableGateScript = preload("res://game/world/build/movable_gate.gd")

var store: NpkStore
var content: PackContent
var warnings: PackedStringArray = []


## 每放置一张图就记一条，供 WORLD_DUMP 输出人可读的坐标清单。
var placements: Array[Dictionary] = []
## 运行时可切换的诊断叠加层（F2/F3/F4），初始值也可由环境变量给。
var debug_boxes := false
var debug_place := false
var debug_grid := OS.get_environment("WORLD_DBG_GRID") == "1"
## 绿色透明地板块叠加。和 debug_boxes / debug_place / debug_grid 一样由世界调试 UI 开关。
var debug_floor := false
## 与 PassGrid.rect_y_mode 同步；区域触发/动画门共用。
var movable_y_mode: int = PassGrid.RectYMode.TOP
var pass_y_offset := 120.0
## 只调“可移动区域/触发框/通行网格”的 y，不影响 NPC/装饰/地砖。
## 调试面板按 16px 步长调整，用来对齐不同地图的可移动区。
var movable_y_offset := 0.0
## 调试开关：可走范围只认 area/virtual 矩形，忽略地砖 0/2。
var area_walk_only := false
## 每块地砖的显示宽度固定 224（14×16）；不再提供实时改宽。
var block_w := 224.0
## 装饰锚点模式：false = 地图坐标 + 画布原点 + [IMAGE POS]（当前默认）
##               true  = 地图坐标 + [IMAGE POS]（不加画布原点）
## 两种都能自洽，用 F6 在游戏里对比，看哪种和原客户端一致。
var deco_raw := false
## 全局 y 位移（实验用：验证「原始画面是不是 800x600 再缩放」这条假设）。
## WORLD_YSHIFT=120 表示所有 [animation] 整体下移 120。
## [animation] 整体垂直偏移（正 = 下移）。用户 2026-11-18 定为固定值 120（和 480 同一套基准）：
## 原客户端可见高度 600、房间高 480，装饰整体是贴着画面底部那 600 的带子摆的。
## 环境变量 WORLD_YSHIFT 可覆盖（截图对比用）。
var y_shift := 120.0

## 扩展地砖与基础地砖之间留的缝（当前 0；曾用 20 表示「逻辑高 160 / 美术高 140」的差）。
const GROUND_GAP := 0


func record(kind: String, src: String, img: String, frame: int, canvas: Vector2,
		dx: float, dy: float, node_pos: Vector2, size: Vector2, z: int, layer := "") -> void:
	var final_pos := node_pos + Vector2(dx, dy)
	var actual := final_pos
	if kind == "npc":
		actual += canvas
	elif kind == "background":
		actual = node_pos
	placements.append({
		"kind": kind, "src": src, "img": img, "frame": frame,
		"canvas": canvas, "dx": dx, "dy": dy,
		"node": node_pos, "final": final_pos, "actual": actual,
		"size": size, "z": z, "layer": layer,
	})


func _init(p_store: NpkStore = null, p_content: PackContent = null) -> void:
	store = p_store
	content = p_content
	deco_raw = OS.get_environment("WORLD_DECO_RAW") == "1"
	var _ys := OS.get_environment("WORLD_YSHIFT")
	if _ys != "":
		y_shift = float(_ys)


func build(room: MapRoom, defs: Dictionary) -> Dictionary:
	placements.clear()
	# 2026-11-25 用户确认：直接 +120 的版本是对的；[background pos]=80 无来源，不参与物体偏移。
	# 哪些对象该用、哪些不该用仍待逐类测试，这里先保留统一常量 120。
	pass_y_offset = 120.0
	y_shift = 120.0
	var grid := PassGrid.new()
	grid.rect_y_mode = movable_y_mode
	# 区域/传送框偏移固定；移动区网格单独偏移，两者不合并。
	grid.origin_y = pass_y_offset
	grid.move_y_offset = movable_y_offset
	grid.block_w = block_w
	grid.build(room.tiles, defs)
	# 必须在 build 之后：BOTTOM 模式要用 grid.height 做翻转。
	grid.add_walk_rects(_collect_walk_rects(room, grid))
	grid.walk_rects_only = area_walk_only

	var root := Node2D.new()
	root.name = "Room"
	root.set_meta("room_path", room.path)

	# 背景（[background animation]，多数地图没有这一段）
	var bg_node := Node2D.new()
	bg_node.name = "Background"
	root.add_child(bg_node)
	_build_background(room, bg_node)

	var tiles_node := Node2D.new()
	tiles_node.name = "Tiles"
	root.add_child(tiles_node)
	_build_tiles(room, defs, grid, tiles_node)
	if debug_floor:
		_build_floor_boxes(room, defs, grid, root)
	if (debug_grid or OS.get_environment("WORLD_DEBUG_GRID") == "1") and store != null \
			and not room.tiles.is_empty():
		_debug_grid(root, grid, room, defs)

	# 装饰层（[animation]：墙、门、铁轨、花草…）
	var deco_node := Node2D.new()
	deco_node.name = "Deco"
	root.add_child(deco_node)
	_build_deco(room, grid, deco_node)

	# 被动对象（[passive object] → .obj → .act → .ani）
	var obj_node := Node2D.new()
	obj_node.name = "Objects"
	root.add_child(obj_node)
	_build_objects(room, grid, defs, obj_node)

	if debug_place or OS.get_environment("WORLD_DEBUG_PLACE") == "1":
		_debug_placements(root)
	if debug_boxes or OS.get_environment("WORLD_DEBUG_BOXES") == "1":
		_debug_boxes(root, room, grid, defs)

	var gates_node := Node2D.new()
	gates_node.name = "Gates"
	root.add_child(gates_node)
	_build_gates(room, grid, gates_node, defs)

	# [town movable area with animation]：可动画的城门/传送门。
	# 放在 Gates 之后、Actors 之前；z 由 [draw layer] 决定，玩家 z 更高。
	_build_movable_gates(room, grid, gates_node, defs)

	var actors_node := Node2D.new()
	actors_node.name = "Actors"
	root.add_child(actors_node)
	_build_actors(room, actors_node, grid, defs)
	_log_placements(room)

	return {"node": root, "pass": grid, "actors": actors_node}


# ---------------------------------------------------------------- 地砖

## area / virtual 是“可走范围”的数据；和地砖 pass 网格取并集。
## 触发仍只用 room.town_movable（见 _build_movable_gates / WorldDirector），
## 这里只补 walkable_at，不改变传送逻辑。
func _collect_walk_rects(room: MapRoom, grid: PassGrid) -> Array:
	var out: Array = []
	for g in _groups(room.town_movable, 6):
		out.append(grid.rect_with_mode(Rect2(float(g[0]), float(g[1]), float(g[2]), float(g[3])),
				grid.rect_y_mode))
	for a in room.town_movable_anim:
		var ad: Dictionary = a
		if float(ad.get("w", 0)) > 0 and float(ad.get("h", 0)) > 0:
			out.append(grid.rect_with_mode(Rect2(float(ad.get("x", 0)), float(ad.get("y", 0)),
					float(ad.get("w", 0)), float(ad.get("h", 0))), grid.rect_y_mode))
	for v in _groups(room.virtual_movable, 4):
		out.append(grid.rect_with_mode(Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3])),
				grid.rect_y_mode))
	return out


func _build_tiles(room: MapRoom, defs: Dictionary, grid: PassGrid, parent: Node2D) -> void:
	for i in room.tiles.size():
		var til_path: String = room.tiles[i]
		var t: TileDef = defs.get(til_path, null)
		if t == null:
			_warn("缺地砖数据：%s" % til_path)
			continue
		if store == null or not store.is_ready():
			continue
		var tex := store.texture(t.img, t.frame)
		if tex == null:
			_warn("NPK 缺图：%s 帧 %d" % [t.img, t.frame])
			continue
		var rect := store.frame_rect(t.img, t.frame)
		var s := Sprite2D.new()
		s.name = "Tile%d" % i
		s.texture = tex
		s.centered = false
		# 地砖落点：**画布底边对齐网格底边**。
		# `.til` 的 [img pos] 是「画布比逻辑网格多出来的顶部空白」：实测
		# hmtile fh=480/img_pos=0、central_tile fh=560/img_pos=80、
		# darkentrance tile.img fh=600/img_pos=120、科勒 point.img fh=600/img_pos=120，
		# 恒有 `画布高 == 行数*16 + img_pos`。所以 art 的屏幕 y = 网格高 − 本帧高度，
		# 多出来的 img_pos 是画布上方的空白，不是往下的偏移（早先按 `网格高 + img_pos - 高`
		# 放，副本图因为 img_pos=120 会整片偏低 120px，表现为「怪浮在半空」）。
		s.position = Vector2(float(i) * block_w + float(rect.position.x),
				grid.height - float(rect.size.y))
		s.z_index = LayerZ.Z_TILE
		s.set_meta("layer", "tile")
		s.set_meta("z0", s.z_index)
		parent.add_child(s)
		record("tile", til_path, t.img, t.frame, rect.position, 0.0, 0.0,
				s.position, rect.size, s.z_index)

	# 扩展地砖（[extended tile]）：每块基础地砖列下面再接一块，用 [tile map] 指定用哪一块。
	# 官方注释：「附加在地砖下方的扩展地砖。横向排列 tile 标签的地砖后，剩余部分排列在下方」。
	for i in room.tiles.size():
		if i >= room.extended_map.size():
			break
		var ei := int(room.extended_map[i])
		if ei < 0 or ei >= room.extended_tiles.size():
			continue
		var ext_path: String = room.extended_tiles[ei]
		var et: TileDef = defs.get(ext_path, null)
		if et == null or store == null or not store.is_ready():
			continue
		var etex := store.texture(et.img, et.frame)
		if etex == null:
			continue
		var erect := store.frame_rect(et.img, et.frame)
		var es := Sprite2D.new()
		es.name = "ExtTile%d" % i
		es.texture = etex
		es.centered = false
		# 扩展地砖的**顶边**贴着基础地砖的下沿（官方注释：剩余部分排列在下方），
		# 所以它的 y 就是网格底边 grid.height —— 不像基础地砖那样按「画布底边对齐」
		# 往上顶（那份公式只管房间内部那一层，扩展层在房间外，必须从底边往下排）。
		es.position = Vector2(float(i) * block_w + float(erect.position.x),
				grid.height + float(GROUND_GAP))
		es.z_index = LayerZ.Z_TILE_EXT
		es.set_meta("layer", "tile")
		es.set_meta("z0", es.z_index)
		parent.add_child(es)
		record("ext_tile", ext_path, et.img, et.frame, erect.position, 0.0, 0.0,
				es.position, erect.size, es.z_index)


# ---------------------------------------------------------------- 背景

## 背景动画是「一层图，横向平铺铺满整个房间」——PVF 只写一次，引擎按图宽重复。
## 不平铺的话，画面里只有 x=0 那一块有背景，镜头一挪就是空的。
var _bg_dy := 0.0

func _build_background(room: MapRoom, parent: Node2D) -> void:
	if OS.get_environment("WORLD_BG_DY") != "":
		_bg_dy = OS.get_environment("WORLD_BG_DY").to_float()
	for b in room.background_anims:
		var d: Dictionary = b
		var def := _ani(str(d.get("path", "")))
		if def == null or store == null or def.is_empty():
			continue
		var f := def.at(0)
		var rect := store.frame_rect(str(f.get("img", "")), int(f.get("frame", 0)))
		var tile_w := maxi(1, rect.size.x)
		var factor := _scroll_factor(str(d.get("layer", "")), room, true)
		# 平铺起点往左多铺一屏，视差滚动时不会露边
		var total := int(ceil((float(room.tile_count()) * block_w + 2.0 * 1152.0) / float(tile_w))) + 1
		var start_x := -1152
		for i in total:
			var sp := AniSprite.new()
			sp.name = "Bg_%s_%d" % [str(d.get("layer", "")), i]
			# 背景必须压在**所有** [animation] 装饰之下：装饰带是 -4100..-3700，
			# 这里给 -6000/-5000，否则装饰会被背景整片盖掉（曾经就是这样「看不见」）。
			# 注意 Godot 的 z_index 合法区间是 [-4096, 4096]，越界会被拒绝（且只报错不生效），
			# 所以这里全部落在合法范围内：远景 -4000、中景 -3900。
			sp.z_index = LayerZ.Z_BG_FAR if str(d.get("layer", "")).contains("distant") else LayerZ.Z_BG_NEAR
			sp.set_meta("layer", str(d.get("layer", "")))
			sp.set_meta("z0", sp.z_index)
			sp.set_meta("parallax", factor)
			parent.add_child(sp)
			# 背景层的画布 y 是它自己的锚点（比如 hmmid01.img 在画布 y=101），
			# 而 [IMAGE POS] 对背景来说不是垂直位置，忽略它才不会把背景推出画面。
			# [background pos]（map 第一行，实测恒 80）是背景层的锚点：
			# 背景从 y = background_pos 起铺，而不是贴着房间顶。
			# [background pos]（map 第一行，实测恒 80）= 背景层整体下移量。
			# 不加它，远景会被顶到房间顶、中景在街道上方空出一条黑带。
			var bg_y := float(rect.position.y) + float(room.background_pos) + _bg_dy
			sp.setup(def, store, Vector2(float(start_x + i * tile_w), bg_y), false)
			record("background", str(d.get("path", "")), str(f.get("img", "")), int(f.get("frame", 0)),
					rect.position, float(f.get("dx", 0)), float(f.get("dy", 0)),
					Vector2(float(start_x + i * tile_w), bg_y), rect.size, sp.z_index,
					str(d.get("layer", "")))


# ---------------------------------------------------------------- 装饰层

## `[animation]` 的 (x, y) 是**屏幕系**（y 向下、0 = 房间顶）：实测按这个解释时
## 「closeback(花草) < normal(墙) < close(铁轨)」的 y 恰好由远及近，
## 换成「距下沿高度」就完全不成立。所以这里不翻 y。
func _build_deco(room: MapRoom, grid: PassGrid, parent: Node2D) -> void:
	if OS.get_environment("WORLD_NO_DECO") == "1":
		return   # 对照实验用：关掉所有 [animation]
	for a in room.anims:
		var d: Dictionary = a
		var def := _ani(str(d.get("path", "")))
		if def == null:
			continue
		# 第三个数字是 z（离地高度）：贴图的 y 要往上抬 z 像素。
		var y := float(d.get("y", 0)) + y_shift - float(d.get("z", 0))
		var sp := AniSprite.new()
		sp.name = "Deco_%d_%d" % [int(d.get("x", 0)), int(y)]
		sp.z_index = _layer_z(str(d.get("layer", "")), y)
		var zov := OS.get_environment("WORLD_DECO_Z")
		if zov != "":
			sp.z_index = int(zov)
		# [animation] 装饰固定在世界坐标里，不随镜头漂移（用户 2026-11-18）。
		var factor := _scroll_factor(str(d.get("layer", "")), room, false)
		if factor < 1.0:
			sp.set_meta("parallax", factor)
		sp.set_meta("layer", str(d.get("layer", "")))
		sp.set_meta("z0", sp.z_index)
		parent.add_child(sp)
		# 落点 = 地图坐标 + 这张图的「画布坐标」。PVF 里的 (x,y) 是 3D 场景里的位置，
		# 每种美术在 NPK 里都带自己的画布原点（比如 hmwall02 的 y=288、hendonpath 的
		# y=341），漏掉画布原点就会整体错位一条，城市场景里表现为「建筑底边和街道之间
		# 空出一条黑带」。见 game/sf85/asset_lib.gd:frame_info() 的同一套算法。
		# 落点 = 地图坐标 + 这张图的画布原点；[IMAGE POS] 由 AniSprite 叠加。
		var f1 := def.at(0)
		var canvas := Vector2.ZERO
		if store != null and not deco_raw:
			var rr := store.frame_rect(str(f1.get("img", "")), int(f1.get("frame", 0)))
			canvas = Vector2(rr.position)
		var anchor := Vector2(float(d.get("x", 0)), y) + canvas
		sp.setup(def, store, anchor)
		record("deco", str(d.get("path", "")), str(f1.get("img", "")), int(f1.get("frame", 0)),
				canvas, float(f1.get("dx", 0)), float(f1.get("dy", 0)),
				anchor, _frame_size(f1), sp.z_index, str(d.get("layer", "")))


## 装饰的 z 按「图层」分带，带内再按 y 排序。
## 基础 z 表统一在 `LayerZ`（[-100,100] 手填常量，不做归一化/按高度换算）。
func _layer_z(layer: String, _y: float) -> int:
	return LayerZ.of(layer)


func _int_or(v: Variant, dflt: int) -> int:
	return dflt if v == null else int(v)


## 视差系数：只有 [background animation] 的远景/中景层用 [far/middle sight scroll]；
## [animation] 装饰一律 1.0（固定在世界坐标，不随镜头漂移）。
## 注：装饰里也有 `[closeback]` 这种含 "back" 的图层名，早先按字符串去猜，
## 结果把贴身的花草也当成远景去做视差 —— 所以这里必须由调用方声明来源，不能靠名字猜。
func _scroll_factor(layer: String, room: MapRoom, is_background: bool) -> float:
	if not is_background:
		return 1.0
	var l := layer.to_lower()
	# JSON 里这些值可能是 null（[far sight scroll] 存在但没写值）——int(null) 会抛
	# "Invalid call. Nonexistent 'int' constructor"，所以先过一道 _int_or。
	var far: int = _int_or(room.sight.get("far"), -1)
	var mid: int = _int_or(room.sight.get("middle"), -1)
	if l.contains("distant") and far >= 0:
		return float(far) / 100.0
	if l.contains("back") and mid >= 0:
		return float(mid) / 100.0
	return 1.0


# ---------------------------------------------------------------- 被动对象

## 地图数据的 y 是「从地砖底边往上量」，画面 y 向下：anchor_y = (网格高 + [img pos]) - raw_y。
## 对象自己的 `.ani` 里 `[IMAGE POS]` 再把左上角往上抬（dy 为负），所以脚点自然落在 anchor 上。
func map_y(room: MapRoom, grid: PassGrid, defs: Dictionary, x: float, raw_y: float) -> float:
	var bottom := grid.height
	var idx := int(floor(x / block_w))
	if idx >= 0 and idx < room.tiles.size():
		var t: TileDef = defs.get(room.tiles[idx], null)
		if t != null:
			bottom += float(t.img_pos)
	return bottom - raw_y


func _build_objects(room: MapRoom, grid: PassGrid, defs: Dictionary, parent: Node2D) -> void:
	for o in room.objects:
		var d: Dictionary = o
		var x := float(d.get("x", 0))
		var ay := map_y(room, grid, defs, x, float(d.get("y", 0)))
		var def := _ani(str(d.get("ani", "")))
		if def == null:
			_marker(parent, Vector2(x, ay), Color(0.55, 0.55, 0.55, 0.45), "")
			continue
		var sp := AniSprite.new()
		sp.name = "Obj%d" % int(d.get("id", 0))
		sp.z_index = clampi(int(ay), -2000, 2000)
		sp.set_meta("layer", str(d.get("layer", "")))
		sp.set_meta("z0", sp.z_index)
		parent.add_child(sp)
		var fo := def.at(0)
		sp.setup(def, store, Vector2(x, ay))
		record("object", str(d.get("ani", "")), str(fo.get("img", "")), int(fo.get("frame", 0)),
				Vector2.ZERO, float(fo.get("dx", 0)), float(fo.get("dy", 0)),
				Vector2(x, ay), _frame_size(fo), sp.z_index, str(d.get("layer", "")))


func _frame_size(f: Dictionary) -> Vector2:
	if store == null:
		return Vector2.ZERO
	return Vector2(store.frame_rect(str(f.get("img", "")), int(f.get("frame", 0))).size)


func _kind_color(kind: String) -> Color:
	match kind:
		"tile": return Color(0.35, 0.65, 1.0)
		"background": return Color(0.75, 0.5, 1.0)
		"deco": return Color(0.4, 1.0, 0.5)
		"object": return Color(1.0, 0.7, 0.2)
	return Color(1, 1, 1)


## WORLD_DEBUG_PLACE=1 时把每张图的实际落点画出来：
## 半透明包围盒 + 两行文字（图路径/帧、画布原点 + [IMAGE POS] → 最终坐标）。
func _debug_placements(root: Node2D) -> void:
	var layer := Node2D.new()
	layer.name = "DebugPlacements"
	layer.z_index = 4000
	root.add_child(layer)
	var font_size := int(OS.get_environment("WORLD_DEBUG_FONT")) if OS.get_environment("WORLD_DEBUG_FONT") != "" else 9
	for pl in placements:
		var p: Vector2 = pl["final"]
		var sz: Vector2 = pl["size"]
		var c := _kind_color(str(pl["kind"]))
		if sz.x > 0.0 and sz.y > 0.0:
			var rect := ColorRect.new()
			rect.color = Color(c.r, c.g, c.b, 0.08)
			rect.position = p
			rect.size = sz
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(rect)
			var line := Line2D.new()
			line.points = PackedVector2Array([p, p + Vector2(sz.x, 0), p + sz,
					p + Vector2(0, sz.y), p])
			line.width = 1.0
			line.default_color = Color(c.r, c.g, c.b, 0.55)
			line.z_index = 1
			layer.add_child(line)
		var lbl := Label.new()
		var cv: Vector2 = pl["canvas"]
		lbl.text = "%s#%d\n画布(%d,%d)+(%d,%d)\n→(%d,%d) %dx%d" % [
			_str_short(str(pl["img"])), int(pl["frame"]),
			int(cv.x), int(cv.y), int(pl["dx"]), int(pl["dy"]),
			int(p.x), int(p.y), int(sz.x), int(sz.y)]
		lbl.position = p + Vector2(2, 2)
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", c)
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(lbl)


## WORLD_DEBUG_BOXES=1：把所有「区域框」画出来——
## [town movable area]（原样 + 上下翻转两种解释都画，方便对着看）、[virtual movable area]、
## [pathgate pos] 的门、NPC / 怪物 / 物件的落点。
func _debug_boxes(root: Node2D, room: MapRoom, grid: PassGrid, defs: Dictionary) -> void:
	var layer := Node2D.new()
	layer.name = "DebugBoxes"
	layer.z_index = 3500
	root.add_child(layer)
	var gx := grid.width
	_line_label(layer, Vector2(4, 4), "boxes: gx=%d gy=%d" % [gx, grid.height], Color(1, 1, 1))

	for g in _groups(room.town_movable, 6):
		var raw := Rect2(float(g[0]), float(g[1]), float(g[2]), float(g[3]))
		var target := _movable_target_text(int(g[4]), int(g[5]))
		# 2026-11-26 用户确认：raw(top) 才是对的；bottom-up 的青色框已删除，只留有效框。
		var r_active := grid.rect_with_mode(raw, grid.rect_y_mode)
		_box(layer, r_active, Color(1, 0.2, 0.85, 1), "mov→" + target)
		_line_label(layer, r_active.position + Vector2(2, 10), "active",
				Color(1, 1, 0.5))

	for a in room.town_movable_anim:
		var ad: Dictionary = a
		var raw_a := Rect2(float(ad.get("x", 0)), float(ad.get("y", 0)),
				float(ad.get("w", 0)), float(ad.get("h", 0)))
		var target_a := _movable_target_text(int(ad.get("town", -1)), int(ad.get("area", -1)))
		var ra_active := grid.rect_with_mode(raw_a, grid.rect_y_mode)
		_box(layer, ra_active, Color(0.3, 1.0, 0.4, 1), "movA→" + target_a)

	for v in _groups(room.virtual_movable, 4):
		var vr := grid.rect_with_mode(Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3])),
				grid.rect_y_mode)
		_box(layer, vr, Color(1.0, 0.75, 0.2, 1), "virtual")

	for k in room.gates():
		var p: Vector2 = room.gates()[k]
		_box(layer, Rect2(p - Vector2(14, 14), Vector2(28, 28)), Color(1, 1, 0, 1), "gate " + str(k))

	for m in room.monsters:
		var d: Dictionary = m
		var x := float(d.get("x", 0))
		var y := map_y(room, grid, defs, x, float(d.get("y", 0)))
		_box(layer, Rect2(x - 12, y - 30, 24, 30), Color(1, 0.35, 0.35, 1), "M" + str(d.get("id", 0)))
	for n in room.npcs:
		var d2: Dictionary = n
		var x2 := float(d2.get("x", 0))
		var y2 := float(d2.get("y", 0)) + pass_y_offset
		_box(layer, Rect2(x2 - 10, y2 - 28, 20, 28), Color(0.4, 0.7, 1, 1), "N" + str(d2.get("id", 0)))
	for o in room.objects:
		var d3: Dictionary = o
		var x3 := float(d3.get("x", 0))
		var y3 := map_y(room, grid, defs, x3, float(d3.get("y", 0)))
		_box(layer, Rect2(x3 - 16, y3 - 40, 32, 40), Color(1, 0.6, 0.2, 1), "O" + str(d3.get("id", 0)))


func _movable_target_text(town_id: int, area_id: int) -> String:
	if town_id == -1 and area_id == -1:
		return "副本开始"
	if town_id == -2 and area_id == -2:
		return "城镇列表"
	var key := content.town_key_by_id(town_id) if content != null else ""
	if key != "":
		return "%s area %d" % [key.get_file(), area_id]
	return "t%d a%d" % [town_id, area_id]


func _groups(values: Array, step: int) -> Array:
	var out := []
	var i := 0
	while i + step - 1 < values.size():
		var v := []
		for k in step:
			v.append(int(values[i + k]))
		out.append(v)
		i += step
	return out


func _box(layer: Node2D, r: Rect2, color: Color, text: String) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y), r.position])
	line.width = 1.0
	line.default_color = color
	layer.add_child(line)
	if text != "":
		_line_label(layer, r.position + Vector2(2, -12), text, color)


func _line_label(layer: Node2D, pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	var fs := int(OS.get_environment("WORLD_DEBUG_FONT")) if OS.get_environment("WORLD_DEBUG_FONT") != "" else 9
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)


func _str_short(path: String) -> String:
	var i := path.rfind("/")
	return path.substr(i + 1) if i >= 0 else path


func _ani(path: String) -> AniDef:
	if path == "" or content == null:
		return null
	return content.ani(path)


# ---------------------------------------------------------------- 带动画的 movable

func _build_movable_gates(room: MapRoom, grid: PassGrid, parent: Node2D, defs: Dictionary) -> void:
	for a in room.town_movable_anim:
		var d: Dictionary = a
		var gate = MovableGateScript.new()
		gate.name = "MovableGate_%d_%d" % [int(d.get("x", 0)), int(d.get("y", 0))]
		gate.z_index = _layer_z(str(d.get("layer", "")), float(d.get("y", 0)))
		gate.set_meta("layer", str(d.get("layer", "")))
		gate.set_meta("z0", gate.z_index)
		parent.add_child(gate)
		var raw := Rect2(float(d.get("x", 0)), float(d.get("y", 0)),
				float(d.get("w", 0)), float(d.get("h", 0)))
		var world_rect := grid.map_rect(raw)
		gate.setup(d, store, content, world_rect.position)
		record("movable", str(d.get("basic", "")), "", 0, Vector2.ZERO,
				0.0, 0.0, world_rect.position,
				world_rect.size, gate.z_index, str(d.get("layer", "")))


# ---------------------------------------------------------------- 门 / 角色占位

func _build_gates(room: MapRoom, grid: PassGrid, parent: Node2D, defs: Dictionary) -> void:
	var colors := {
		"left": Color(0.2, 0.7, 1.0, 0.35),
		"right": Color(1.0, 0.6, 0.2, 0.35),
		"up": Color(0.6, 1.0, 0.3, 0.35),
		"down": Color(1.0, 0.3, 0.6, 0.35),
	}
	for dir_name in room.gates().keys():
		var p: Vector2 = room.gate(dir_name)
		var r := ColorRect.new()
		r.name = "Gate_%s" % dir_name
		r.color = colors.get(dir_name, Color(1, 1, 1, 0.3))
		r.size = Vector2(28, 28)
		p.y = map_y(room, grid, defs, p.x, p.y)
		r.position = p - Vector2(14, 14)
		r.z_index = 3000
		parent.add_child(r)
		record("pathgate", dir_name, "", 0, Vector2.ZERO, 0.0, 0.0,
				r.position, r.size, r.z_index, "gate")


func _build_actors(room: MapRoom, parent: Node2D, grid: PassGrid, defs: Dictionary) -> void:
	for m in room.monsters:
		var d: Dictionary = m
		var x := float(d.get("x", 0))
		var pos := Vector2(x, map_y(room, grid, defs, x, float(d.get("y", 0))))
		var mid := int(d.get("id", 0))
		var mon: MonsterDef = null
		if content is LivePvfContent:
			mon = (content as LivePvfContent).monster(mid)
		if mon != null and mon.stay_ani_path != "":
			var ani := content.ani(mon.stay_ani_path)
			if ani != null and store != null:
				_monster_sprite(parent, pos, mon, ani)
				continue
		_marker(parent, pos, Color(0.9, 0.25, 0.2), "M%d" % mid)
	for n in room.npcs:
		var d: Dictionary = n
		var x := float(d.get("x", 0))
		# NPC 的 y 是屏幕系（顶部为 0），和装饰一样需要加 y_shift；
		# 直接 raw 会站到墙顶，走 map_y 又会压到可走区底部。
		var pos := Vector2(x, float(d.get("y", 0)) + pass_y_offset)
		var nid := int(d.get("id", 0))
		var npc: NpcDef = content.npc(nid) if content != null and content.has_npc(nid) else null
		if npc != null and npc.ani != null and store != null:
			_npc_sprite(parent, pos, npc)
		else:
			var fallback := npc.display_name() if npc != null else "N%d" % int(d.get("id", 0))
			_marker(parent, pos, Color(0.25, 0.55, 0.95), fallback)


## 怪物：`.mob [waiting motion]` 的站立动画；找不到动画时由 _build_actors 退回占位。
func _monster_sprite(parent: Node2D, pos: Vector2, mon: MonsterDef, ani: AniDef) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = clampi(int(pos.y), -4096, 4096)
	holder.set_meta("actor", "monster")
	var sprite := AniSprite.new()
	sprite.setup(ani, store, Vector2.ZERO, true, true)
	holder.add_child(sprite)
	var first: Dictionary = ani.at(0)
	var canvas := store.frame_rect(str(first.get("img", "")), int(first.get("frame", 0))).position
	var art_top := float(first.get("dy", 0)) + float(canvas.y)
	var text := mon.name
	if text == "":
		text = "M%d" % mon.id
	var label := Label.new()
	label.text = text
	label.position = Vector2(-80, art_top - 28.0)
	label.size = Vector2(160, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _cjk_font())
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.65))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	holder.add_child(label)
	parent.add_child(holder)
	record("monster", mon.stay_ani_path, str(first.get("img", "")), int(first.get("frame", 0)),
			canvas, float(first.get("dx", 0)), float(first.get("dy", 0)),
			pos, _frame_size(first), holder.z_index, "monster")


## NPC：站立动画（`.ani` 的帧偏移就是相对脚下锚点的像素）+ 头顶短名。
func _npc_sprite(parent: Node2D, pos: Vector2, npc: NpcDef) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = clampi(int(pos.y), -4096, 4096)
	holder.set_meta("actor", "npc")
	var sprite := AniSprite.new()
	# NPC 没有 RoomBuilder 的 anchor，NPK 帧头的画布原点必须由 AniSprite 自己加；
	# 见 ani_sprite.gd 的 apply_canvas_offset。
	sprite.setup(npc.ani, store, Vector2.ZERO, true, true)
	holder.add_child(sprite)
	var first := npc.ani.at(0)
	var canvas := store.frame_rect(str(first.get("img", "")), int(first.get("frame", 0))).position
	var art_top := float(first.get("dy", 0)) + float(canvas.y)
	var shown := npc.display_name()
	if shown != "":
		var label := Label.new()
		label.text = shown
		label.position = Vector2(-80, art_top - 28.0)
		label.size = Vector2(160, 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", _cjk_font())
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 3)
		holder.add_child(label)
	parent.add_child(holder)
	record("npc", npc.ani_path, str(first.get("img", "")), int(first.get("frame", 0)),
			canvas, float(first.get("dx", 0)), float(first.get("dy", 0)),
			pos, _frame_size(first), holder.z_index, "npc")


var _npc_font: SystemFont


func _cjk_font() -> SystemFont:
	if _npc_font == null:
		_npc_font = WorldFont.make(400)
	return _npc_font


func _marker(parent: Node2D, pos: Vector2, color: Color, label_text: String) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = clampi(int(pos.y), -4096, 4096)
	holder.set_meta("actor", label_text)
	var body := ColorRect.new()
	body.color = color
	body.size = Vector2(16, 28)
	body.position = Vector2(-8, -28)
	holder.add_child(body)
	if label_text != "":
		var l := Label.new()
		l.text = label_text
		l.position = Vector2(-12, -46)
		l.add_theme_font_size_override("font_size", 10)
		holder.add_child(l)
	parent.add_child(holder)
	record("marker", label_text, "", 0, Vector2.ZERO, 0.0, 0.0,
			pos, Vector2(16, 28), holder.z_index, "actor")


## 绿色透明地板块：按实际贴图尺寸画，不是按固定 224 画。
## 这样 218/240/1px 的异常地砖会立刻在画面上露出宽度差；标签同时给出逻辑列和资源名。
func _build_floor_boxes(room: MapRoom, defs: Dictionary, grid: PassGrid, parent: Node2D) -> void:
	var layer := Node2D.new()
	layer.name = "DebugFloor"
	layer.z_index = 2400
	parent.add_child(layer)
	for i in room.tiles.size():
		var til_path: String = room.tiles[i]
		var t: TileDef = defs.get(til_path, null)
		if t == null or store == null:
			continue
		var rect := store.frame_rect(t.img, t.frame)
		var r := Rect2(Vector2(float(i) * block_w + float(rect.position.x),
				grid.height - float(rect.size.y)), rect.size)
		var fill := ColorRect.new()
		fill.color = Color(0.15, 1.0, 0.35, 0.10)
		fill.position = r.position
		fill.size = r.size
		layer.add_child(fill)
		var border := Line2D.new()
		border.width = 2.0
		border.default_color = Color(0.2, 1.0, 0.45, 0.85)
		border.points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
				r.end, Vector2(r.position.x, r.end.y), r.position])
		layer.add_child(border)
		var label := Label.new()
		label.text = "T%d %.0f×%.0f  %s" % [i, r.size.x, r.size.y, til_path.get_file()]
		label.position = r.position + Vector2(4, 4)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 3)
		layer.add_child(label)


## 每张资源图的实际落点/偏移，DEBUG 级逐条打印；每次 build（切图/改诊断层/改偏移）都会重打。
## fields 语义：node=锚点，canvas=NPK 帧画布原点，off=[IMAGE POS]，final=最终左上角。
func _log_placements(room: MapRoom) -> void:
	if OS.get_environment("WORLD_PLACE_LOG") == "0":
		return
	LogUtil.debug("[MapPlace] room=%s count=%d y_shift=%.0f deco_raw=%s" % [
			room.path, placements.size(), y_shift, str(deco_raw)])
	for pl in placements:
		LogUtil.debug("[MapPlace] kind=%s src=%s img=%s frame=%d node=(%.1f,%.1f) canvas=(%.1f,%.1f) off=(%.1f,%.1f) final=(%.1f,%.1f) actual=(%.1f,%.1f) size=(%.1f,%.1f) z=%d layer=%s" % [
				str(pl["kind"]), str(pl["src"]), str(pl["img"]), int(pl["frame"]),
				(pl["node"] as Vector2).x, (pl["node"] as Vector2).y,
				(pl["canvas"] as Vector2).x, (pl["canvas"] as Vector2).y,
				float(pl["dx"]), float(pl["dy"]),
				(pl["final"] as Vector2).x, (pl["final"] as Vector2).y,
				(pl["actual"] as Vector2).x, (pl["actual"] as Vector2).y,
				(pl["size"] as Vector2).x, (pl["size"] as Vector2).y,
				int(pl["z"]), str(pl["layer"])])


func _warn(msg: String) -> void:
	warnings.append(msg)
	LogUtil.warn("[RoomBuilder] " + msg)

## 诊断用：把通行网格画在画面上，检验「深度轴是否被压扁（y 带角度）」。
## WORLD_GRID_K 给 1 就是现在用的 1:1 映射；给 art_h/(rows*16) 就是「地砖美术高度
## 等于整个深度」的假设。两组截图一比，就知道可走区该落在哪。
func _debug_grid(root: Node2D, grid: PassGrid, room: MapRoom, defs: Dictionary) -> void:
	var t: TileDef = defs.get(room.tiles[0], null)
	if t == null:
		return
	var rect := store.frame_rect(t.img, t.frame)
	var art_h := float(rect.size.y)
	var k := float(OS.get_environment("WORLD_GRID_K").to_float())
	if k <= 0.0:
		k = 1.0
	var bottom := grid.height
	var layer := Node2D.new()
	layer.name = "DebugGrid"
	layer.z_index = 4000
	root.add_child(layer)
	for y in grid.rows:
		for x in grid.cols:
			var r := ColorRect.new()
			r.size = Vector2(grid.cell_w - 1.0, PassGrid.CELL - 1.0)
			# 以网格底边为轴做垂直缩放：k<1 时整个可走带被压向地面
			var sy := (bottom - (bottom - float(y) * PassGrid.CELL) * k) + grid.origin_y + grid.move_y_offset
			r.position = Vector2(float(x) * grid.cell_w, sy)
			# 绿 = 可走（pass 0）；红 = 阻挡（pass 2/其它）；灰蓝 = 缺图默认阻挡
			var cell_center := Vector2((float(x) + 0.5) * grid.cell_w, sy + PassGrid.CELL * 0.5)
			var cell_walk := grid.walkable_at(cell_center)
			if not grid.walk_rects_only:
				cell_walk = cell_walk or grid.walkable(x, y)
			if cell_walk:
				r.color = Color(0.1, 1.0, 0.3, 0.28)
			else:
				r.color = Color(1.0, 0.15, 0.1, 0.22)
			layer.add_child(r)
	_line_label(layer, Vector2(4, 22), "grid: 绿=可走 红=阻挡 灰蓝=缺图", Color(1, 1, 1))
	LogUtil.debug("[RoomBuilder] debug grid k=%s art_h=%s rows=%d height=%s" % [str(k), str(art_h), grid.rows, str(bottom)])
