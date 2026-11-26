class_name WorldDirector
extends Node2D
## 全地图加载的总调度：城镇 ⇄ 副本 ⇄ 房间。
## 一切切换都由原生 PVF 数据决定：
##   · 城镇换 area：[town movable area] 命中（x y w h townIdx areaIdx；-1/-1 = 副本开始），
##     area 之间没有 town_movable 时退化为「按 [minimap rect] 找贴边邻居 + 走到边缘」。
##   · 副本换房间：`[greed]` 网格的连通位 + 走到房间边缘。
##   · 进/出副本：城镇里 type = "dungeon gate" 的 area 按 E 进入（id 来自 .twn），Esc 回城。

const VIEW_SIZE := Vector2(1152.0, 648.0)
const WorldDebugUIScript = preload("res://game/world/ui/world_debug_ui.gd")

## 一屏看到的世界高度（像素）。480 = 一个房间高（放大约 1.35 倍）；600 = 原客户端窗口高。
## 用户 2026-11-18：先把地图/人物整体放大到 480 这个比例，不行再试 600。
const VIEW_WORLD_H := 480.0
## 触发换图的边缘阈值：地砖最外一列常常是墙（pass=0），角色只能停在离边 1 格内，
## 所以阈值给到半格以上，不能用 3px。
const EDGE_EPS := 12.0
## 换图后把 NPK / 内容缓存压回的水位。只影响缓存，不卸载当前房间。
const CACHE_TEX_KEEP := 320
const CACHE_IMG_KEEP := 24
const CACHE_CONTENT_KEEP := 40

var content: LivePvfContent
var store: NpkStore
var builder: RoomBuilder

var room_holder: Node2D
var player: WorldPlayer
var camera: Camera2D
var hint: Label
var player_pos: Label
var ui_layer: CanvasLayer
var town_list: TownListUI
var debug_ui
var _ui_open := false
var movable_y_mode := "top"
## 可移动区/触发框/通行网格的 y 偏移，16px 步长；x 不动。地砖块宽固定 224。
var movable_y_offset := 0.0
## 调试：只让 area/virtual 矩形决定可走，忽略地砖 0/2。用来验证“实际移动范围是不是 area 组合”。
var area_walk_only := false
var _ui_hidden := false
var _raised_layer := ""
var _raised_nodes: Array[Node] = []
var _raise_ceiling := 0x7fffffff

var mode := ""                       ## "" / "town" / "dungeon"
var room: MapRoom
var grid: PassGrid
var town: TownDef
var town_key := ""
var town_area := -1
var dungeon: DungeonDef
var dungeon_key := ""
var cell := Vector2i(-1, -1)
var last_town_key := ""
var last_town_area := 0
var last_dungeon_key := ""
var log_lines: PackedStringArray = []

signal room_changed(map_path: String, mode: String)


func _ready() -> void:
	# 先把 HUD 建出来：路径不对时也要能在屏幕上看到原因，而不是只有黑屏。
	_build_hint()
	var pvf_path := PathUtil.dnf_script()
	var npk_dir := PathUtil.dnf_imagepacks()
	LogUtil.info("世界资源", {"pvf": pvf_path, "npk": npk_dir, "platform": OS.get_name()})
	if not PathUtil.exists_file(pvf_path):
		var why := "原生 PVF 不存在：%s\nWindows F5 请设 DNF_ROOT=D:/dnf_latest，或把 dnf_latest 放到 D:/" % pvf_path
		_log(why)
		hint.text = why
		LogUtil.error(why, {"pvf": pvf_path, "expected_windows": PathUtil.to_windows(pvf_path)})
		return
	content = LivePvfContent.new(pvf_path)
	if not content.is_ready():
		var why2 := "原生 PVF 打不开：%s" % pvf_path
		_log(why2)
		hint.text = why2
		return
	content.load_index()

	store = NpkStore.new(npk_dir)
	if not PathUtil.exists_dir(npk_dir):
		var why3 := "NPK 目录不存在：%s\nWindows F5 请设 DNF_ROOT=D:/dnf_latest" % npk_dir
		_log(why3)
		hint.text = why3
		LogUtil.error(why3, {"npk": npk_dir})
		return
	if not store.open_live():
		_log("NPK 目录打不开：%s（地砖会没有贴图）" % npk_dir)
	builder = RoomBuilder.new(store, content)

	room_holder = Node2D.new()
	room_holder.name = "Rooms"
	add_child(room_holder)

	player = WorldPlayer.new()
	player.name = "Player"
	player.z_index = 10
	player.add_to_group("world_player")
	add_child(player)
	player.setup_visual(content, store)

	camera = Camera2D.new()
	camera.name = "Camera"
	camera.enabled = true
	add_child(camera)

	_build_ui()
	_update_player_pos()
	_ready_default_bg()
	_bind_keys()

	var start_town := OS.get_environment("WORLD_TOWN")
	if start_town == "":
		start_town = "town/new_hendonmyre.twn"
	if start_town == "":
		_log("内容包里没有城镇")
		return
	if not enter_town(start_town):
		_log("进不去城镇：%s" % start_town)


# ---------------------------------------------------------------- 对外入口

func enter_town(town_key_in: String, area_index := -1, spawn_edge := "center") -> bool:
	var t := content.town(town_key_in)
	if t == null:
		_log("文城镇缺失：%s" % town_key_in)
		return false
	town = t
	town_key = town_key_in
	mode = "town"
	dungeon = null
	dungeon_key = ""
	cell = Vector2i(-1, -1)
	var idx := area_index
	if idx < 0:
		idx = _default_area(t)
	_log("进城镇 %s area=%d" % [town_key_in, idx])
	if idx < 0:
		_log("城镇没有可用 area：%s" % town_key_in)
		return false
	return enter_town_area(idx, spawn_edge)


func enter_town_area(area_index: int, spawn_edge := "center") -> bool:
	if town == null:
		return false
	var before := player.position if player != null else Vector2.ZERO
	LogUtil.debug("[AreaMove] enter town=%s area=%d spawn=%s player_before=(%.1f,%.1f)" % [
			town_key, area_index, spawn_edge, before.x, before.y])
	var a := town.area(area_index)
	var map_path := str(a.get("map", ""))
	if not _area_usable(area_index):
		# 内容包里没有这张图：退到下一个有图的 area（不硬编码任何地图）
		var fallback := _next_area_with_map(area_index)
		if fallback < 0:
			_log("area %d 的图不在内容包里，且没有可回退的 area" % area_index)
			return false
		_log("area %d 缺图 %s，退到 area %d" % [area_index, map_path, fallback])
		a = town.area(fallback)
		map_path = str(a.get("map", ""))
		area_index = fallback
	town_area = area_index
	last_town_key = town_key
	last_town_area = area_index
	mode = "town"
	return _load_room(map_path, spawn_edge)


func enter_dungeon_by_id(dungeon_id: int) -> bool:
	var key := dungeon_key_for_id(dungeon_id)
	if key == "":
		_log("副本 id %d 不在内容包里" % dungeon_id)
		return false
	return enter_dungeon(key)


func dungeon_key_for_id(dungeon_id: int) -> String:
	for d in content.load_index().get("dungeons", []):
		if int(d.get("registry_id", -1)) == dungeon_id:
			return content.key_of(str(d.get("path", "")))
	return ""


func enter_dungeon(dungeon_key_in: String, maze_index := 0) -> bool:
	var dg := content.dungeon(dungeon_key_in, maze_index)
	if dg == null:
		_log("副本缺失：%s" % dungeon_key_in)
		return false
	dungeon = dg
	dungeon_key = dungeon_key_in
	last_dungeon_key = dungeon_key_in
	mode = "dungeon"
	var start := dungeon.start_cell()
	if not dungeon.has_cell(start.x, start.y):
		var walkable := dungeon.walkable_cells()
		if walkable.is_empty():
			_log("副本没有任何可用格子：%s" % dungeon_key_in)
			return false
		start = walkable[0]
	return _enter_cell(start, "center")


func return_to_town() -> bool:
	if last_town_key == "":
		return false
	_log("回城：%s" % last_town_key)
	return enter_town(last_town_key, last_town_area, "center")


# ---------------------------------------------------------------- 每帧：切换判定

func _process(delta: float) -> void:
	if _ui_open:
		return
	if _switch_cooldown > 0.0:
		_switch_cooldown = maxf(_switch_cooldown - delta, 0.0)
	if room == null or player == null or grid == null:
		return
	if mode == "town":
		_check_town_movable()
		_check_town_edge()
	elif mode == "dungeon":
		_check_dungeon_edge()
	_update_camera()
	_sync_parallax()
	if player != null:
		player.z_index = clampi(int(player.position.y), -2000, 2000)
		_apply_raise_z()
		_update_player_pos()


var _switch_cooldown := 0.0
## 打开城镇列表的 [town movable]：人还站在触发区里时不要每 0.35s 弹一次，
## 必须先走出去再回来才会重新触发。
var _suppress_movable := Rect2()
var _last_cam := Vector2.INF
var _parallax_nodes: Array = []
var room_node: Node2D = null


func _check_town_movable() -> void:
	if _switch_cooldown > 0.0:
		return
	if _suppress_movable.size != Vector2.ZERO:
		if _suppress_movable.has_point(player.position):
			return
		_suppress_movable = Rect2()
	var groups := _rect_groups(room.town_movable, 6)
	for g in groups:
		var r: Rect2 = grid.map_rect(g["rect"])
		if not r.has_point(player.position):
			continue
		var target_town := int(g["values"][4])
		var target_area := int(g["values"][5])
		LogUtil.debug("[AreaMove] movable rect=%s player=(%.1f,%.1f) target=%d/%d" % [
				str(r), player.position.x, player.position.y, target_town, target_area])
		_switch_cooldown = 0.35
		if target_town == -1 and target_area == -1:
			# 官方：-1/-1 = 副本开始而不是 area 移动
			var entrances := _town_dungeon_entrances()
			if not entrances.is_empty():
				_log("[town movable area] 指向副本开始 → %s" % str(entrances[0]))
				enter_dungeon_by_id(int(entrances[0]))
			return
		if target_town == -2 and target_area == -2:
			# 官方：-2/-2 = 世界地图/城门 → 这里直接打开城镇列表
			_log("[town movable area] 打开城镇列表")
			_suppress_movable = r
			_open_town_list()
			return
		# 跨城镇：目标 town 是 PVF 的 town id，不是内容包 key
		if target_town > 0 and town != null and target_town != town.town_id:
			var next_key := content.town_key_by_id(target_town)
			if next_key == "":
				_log("[town movable area] 目标城镇 id=%d 不在内容包" % target_town)
				return
			_log("[town movable area] 跨城 → %s area %d" % [next_key, target_area])
			enter_town(next_key, target_area if target_area >= 0 else -1, "center")
			return
		# 同城镇内的 area 切换
		if target_area >= 0 and target_area != town_area and content.has_map(town.map_of(target_area)):
			_log("[town movable area] → area %d" % target_area)
			enter_town_area(target_area, "center")
			return


func _check_town_edge() -> void:
	var dir := _edge_dir()
	if dir == "":
		return
	var next := town.neighbor_of(town_area, dir) if town != null else -1
	if next < 0 or next == town_area:
		return
	if not content.has_map(town.map_of(next)):
		return
	_log("城镇边缘 %s → area %d" % [dir, next])
	enter_town_area(next, _opposite(dir))


func _check_dungeon_edge() -> void:
	var dir := _edge_dir()
	if dir == "" or dungeon == null:
		return
	var bits := {"right": GreedGrid.RIGHT, "left": GreedGrid.LEFT,
			"up": GreedGrid.UP, "down": GreedGrid.DOWN}
	var bit: int = int(bits[dir])
	var nxt: Variant = dungeon.greed.step(cell.x, cell.y, bit)
	if nxt == null:
		return
	var nc: Vector2i = nxt
	if not dungeon.has_cell(nc.x, nc.y):
		_log("房间 %s 朝向 %s 有连接，但格子 %s 没有地图" % [str(cell), dir, str(nc)])
		return
	_log("副本换房 %s → %s" % [str(cell), str(nc)])
	_enter_cell(nc, _opposite(dir))


func _edge_dir() -> String:
	var p := player.position
	if p.x <= EDGE_EPS:
		return "left"
	if p.x >= grid.width - EDGE_EPS:
		return "right"
	if p.y <= EDGE_EPS:
		return "up"
	if p.y >= grid.height - EDGE_EPS:
		return "down"
	return ""


func _opposite(dir: String) -> String:
	match dir:
		"left":
			return "right"
		"right":
			return "left"
		"up":
			return "down"
		"down":
			return "up"
	return "center"


# ---------------------------------------------------------------- 房间装载/卸载

func _dummy_only(room: MapRoom, defs: Dictionary) -> bool:
	if room.tiles.is_empty():
		return false
	for p in room.tiles:
		if not str(p).get_file().begins_with("dummy"):
			return false
	return true


func _load_room(map_path: String, spawn_edge: String) -> bool:
	var r := content.map_room(map_path)
	if r.tile_count() == 0:
		_log("地图没有地砖：%s" % map_path)
		return false
	var defs := content.tiles_for(r)
	_unload_room()
	room = r
	builder.movable_y_mode = PassGrid.RectYMode.BOTTOM if movable_y_mode == "bottom" else PassGrid.RectYMode.TOP
	builder.block_w = 224.0
	builder.movable_y_offset = movable_y_offset
	builder.area_walk_only = area_walk_only
	var built := builder.build(r, defs)
	var node: Node2D = built["node"]
	room_holder.add_child(node)
	room_node = node
	_collect_parallax(node)
	_last_cam = Vector2.INF
	grid = built["pass"]
	_reapply_raised()
	if grid.walkable_ratio() <= 0.0:
		# 只有「整张图都是 dummy.til」的过渡图才退化为可走；普通城镇/副本的
		# pass 全 2 是数据本身没有可走区，不能整间解锁，否则会穿墙/踩空。
		if _dummy_only(r, defs):
			_log("整张图都是 dummy.til（pass 全 2），退化为整间可走：%s" % map_path)
			grid.make_all_walkable()
		else:
			_log("整张图 [pass type] 全 2，保持全阻挡（不整间解锁）：%s" % map_path)
	player.pass_grid = grid
	player.position = grid.spawn_at(spawn_edge)
	LogUtil.debug("[AreaSpawn] map=%s spawn=%s player=(%.1f,%.1f) grid=%dx%d" % [
			map_path, spawn_edge, player.position.x, player.position.y, grid.cols, grid.rows])
	_update_camera(true)
	_update_player_pos()
	_log("装载 %s（tiles=%d, %dx%d 格, 可走 %.0f%%, 怪物 %d）" % [
			map_path, r.tile_count(), grid.cols, grid.rows, grid.walkable_ratio() * 100.0,
			r.monsters.size()])
	room_changed.emit(map_path, mode)
	_update_hint()
	return true


func _collect_parallax(node: Node) -> void:
	_parallax_nodes.clear()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta("parallax") and n is Node2D:
			_parallax_nodes.append(n)
		for c in n.get_children():
			stack.append(c)


func _unload_room() -> void:
	for c in room_holder.get_children():
		room_holder.remove_child(c)
		# 立即释放而不是 queue_free：旧房间的 Sprite2D/AniSprite 不再引用贴图，
		# 紧接着 trim 缓存才能真正把显存/内存放掉。
		c.free()
	grid = null
	room = null
	room_node = null
	_raised_nodes.clear()
	_parallax_nodes.clear()
	_last_cam = Vector2.INF
	if store != null:
		store.trim(CACHE_TEX_KEEP, CACHE_IMG_KEEP)
	if content != null:
		content.trim_cache(CACHE_CONTENT_KEEP, CACHE_CONTENT_KEEP * 2)


func _enter_cell(c: Vector2i, spawn_edge: String) -> bool:
	if dungeon == null:
		return false
	var map_path := dungeon.map_path(c.x, c.y)
	if map_path == "":
		_log("格子 %s 没有地图" % str(c))
		return false
	var ok := _load_room(map_path, spawn_edge)
	if ok:
		cell = c
		_update_hint()
	return ok


# ---------------------------------------------------------------- 相机/UI/输入

func _update_camera(force := false) -> void:
	if camera == null or grid == null or player == null:
		return
	# 视野：屏幕像素 / zoom = 世界像素。VIEW_WORLD_H 就是"一屏能看到多少世界高度"：
	#   480 → 正好一整个房间高（比原来放大约 1.35 倍，接近原客户端一个房间铺满窗口的感觉）
	#   600 → 原客户端窗口高度（视野更大、人物更小）
	# 环境变量 WORLD_VIEW_H 可临时改，改完直接看效果。
	var view_h := VIEW_WORLD_H
	var env_h := OS.get_environment("WORLD_VIEW_H")
	if env_h != "":
		view_h = env_h.to_float()
	var zoom := VIEW_SIZE.y / view_h
	var vis := VIEW_SIZE / zoom          # 可见世界矩形尺寸
	var half := vis * 0.5

	camera.zoom = Vector2(zoom, zoom)

	# 房间比视野小时：x 居中，**y 贴底**（原客户端画面底部就是房间底边；
	# 按居中放的话整个场景会平白高出 (可见高-房间高)/2）。
	if float(grid.width) <= vis.x and grid.world_height() <= vis.y:
		camera.position = Vector2(float(grid.width) * 0.5, grid.world_height() - half.y)
		return

	var pos := player.position - Vector2(0, 110)
	pos.x = clampf(pos.x, half.x, maxf(float(grid.width) - half.x, half.x))
	if grid.world_height() <= vis.y:
		pos.y = grid.world_height() - half.y
	else:
		pos.y = clampf(pos.y, half.y, maxf(grid.world_height() - half.y, half.y))
	if force:
		camera.position = pos
	else:
		camera.position = camera.position.lerp(pos, 0.2)


## 背景/远景装饰按 [far/middle sight scroll] 的百分比相对镜头缓动（1.0 = 跟着世界走）。
func _sync_parallax() -> void:
	# 只有 [background animation] 的层挂了 "parallax" meta；[animation] 装饰不挂，
	# 所以它们在世界坐标里固定不动，镜头怎么走都不漂移。
	if camera == null or room_node == null:
		return
	var cam := camera.position
	if _last_cam != Vector2.INF:
		var d := cam - _last_cam
		for n in _parallax_nodes:
			var node: Node2D = n
			var f := float(node.get_meta("parallax", 1.0))
			if f < 1.0:
				# 用户 2026-11-26：背景只需要 x 跟随，y 不要跟着人物上下动。
				# 只处理 x；y 由背景构建时的 bg_y 决定，保持固定。
				node.position.x -= d.x * (1.0 - f)
	_last_cam = cam


func _ready_default_bg() -> void:
	# PVF 的 .map 不定义背景色；不铺底的话，装饰图之间的空隙会露出引擎的灰色清屏色，
	# 看起来像「缺图」。用一个深色底把「没有背景图」和「贴图没画出来」区分开。
	RenderingServer.set_default_clear_color(Color(0.05, 0.04, 0.06))


func _bind_keys() -> void:
	_bind_keys_for("move_left", [KEY_A, KEY_LEFT])
	_bind_keys_for("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys_for("move_up", [KEY_W, KEY_UP])
	_bind_keys_for("move_down", [KEY_S, KEY_DOWN])
	_bind_keys_for("world_interact", [KEY_E])
	_bind_keys_for("world_back", [KEY_ESCAPE, KEY_R])
	# 调试键一律用字母/符号键：F 键是 Godot 编辑器的运行/停止/单步快捷键，
	# 游戏从编辑器里跑的时候按 F5/F8 会把项目直接停掉（用户 2026-11-18 踩到）。
	_bind_keys_for("world_reset", [KEY_HOME])
	_bind_keys_for("world_town_list", [KEY_M])
	_bind_keys_for("world_dbg_boxes", [KEY_BRACKETLEFT])
	_bind_keys_for("world_dbg_place", [KEY_BRACKETRIGHT])
	_bind_keys_for("world_dbg_grid", [KEY_BACKSLASH])
	_bind_keys_for("world_deco_raw", [KEY_SEMICOLON])
	_bind_keys_for("world_deco_up", [KEY_COMMA])
	_bind_keys_for("world_deco_down", [KEY_PERIOD])
	_bind_keys_for("world_deco_zero", [KEY_SLASH])
	_bind_keys_for("world_dbg_floor", [KEY_G])
	_bind_keys_for("world_dbg_ui", [KEY_L])
	_bind_keys_for("world_ui_hide", [KEY_U])
	_bind_keys_for("world_layer_off", [KEY_0])
	_bind_keys_for("world_move_y_dec", [KEY_MINUS])
	_bind_keys_for("world_move_y_inc", [KEY_EQUAL])
	for i in 7:
		_bind_keys_for("world_layer_%d" % (i + 1), [KEY_1 + i])


func _bind_keys_for(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


## 就地重建房间节点（保留玩家位置），用来切换 F2/F3/F4 的诊断叠加层。
func _rebuild_room() -> void:
	if room == null:
		return
	var defs := content.tiles_for(room)
	builder.movable_y_mode = PassGrid.RectYMode.BOTTOM if movable_y_mode == "bottom" else PassGrid.RectYMode.TOP
	builder.block_w = 224.0
	builder.movable_y_offset = movable_y_offset
	builder.area_walk_only = area_walk_only
	var built := builder.build(room, defs)
	if room_node != null and is_instance_valid(room_node):
		room_holder.remove_child(room_node)
		room_node.queue_free()
	room_node = built["node"]
	room_holder.add_child(room_node)
	_parallax_nodes.clear()
	_collect_parallax(room_node)
	_last_cam = Vector2.INF
	grid = built["pass"]
	player.pass_grid = grid
	# 调区块宽后玩家位置可能落到新网格外；限制回房间内，落在阻挡格就回出生点。
	player.position.x = clampf(player.position.x, grid.cell_w * 0.5, grid.width - grid.cell_w * 0.5)
	if not grid.walkable_at(player.position):
		player.position = grid.spawn_at("center")
	_update_camera(true)
	_reapply_raised()


func _reapply_raised() -> void:
	if _raised_layer == "":
		return
	_raised_nodes.clear()
	_collect_raised(room_node)
	_raise_ceiling = _actor_ceiling()
	_apply_raise_z()


## [ / ] / \\：切诊断叠加层（区域框 / 每张图的落点 / 通行网格）。游戏里直接按，不用环境变量。
func _toggle_debug(which: String) -> void:
	if builder == null:
		return
	match which:
		"boxes":
			builder.debug_boxes = not builder.debug_boxes
			_log("诊断框 [town movable / virtual / pathgate / 怪物 NPC 物件]：%s" % ("开" if builder.debug_boxes else "关"))
		"place":
			builder.debug_place = not builder.debug_place
			_log("每张图的落点标注：%s" % ("开" if builder.debug_place else "关"))
		"deco":
			builder.deco_raw = not builder.deco_raw
			_log("装饰锚点：%s" % ("地图坐标+[IMAGE POS]（不加画布原点）" if builder.deco_raw else "地图坐标+画布原点+[IMAGE POS]"))
		"grid":
			builder.debug_grid = not builder.debug_grid
			_log("通行网格叠加：%s" % ("开" if builder.debug_grid else "关"))
	_rebuild_room()
	_sync_debug_ui()


## , / . 每按一次把 [animation] 整体上/下移 10px，/ 归零。
## 用来现场对齐「原版里这些装饰到底该落在哪」，对齐后把数字写回 RoomBuilder 默认值即可。
func _nudge_deco_y(delta: float) -> void:
	if builder == null:
		return
	builder.y_shift += delta
	_rebuild_room()
	_log("[animation] y 偏移 = %.0f px（, 上移 / . 下移 / / 归零）" % builder.y_shift)
	_update_hint()


## 按住/按一下刷新键，回到这个房间的初始落点（城镇回 area 中心，副本回当前格中心）。
func reset_to_spawn() -> void:
	if mode == "dungeon" and cell.x >= 0:
		_enter_cell(cell, "center")
		_log("重置到当前副本格的初始位置")
	elif mode == "town" and town != null:
		enter_town_area(town_area, "center")
		_log("重置到城镇 area %d 的初始位置" % town_area)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_town_list"):
		if town_list != null:
			town_list.toggle(town_key)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_ui_hide"):
		_toggle_ui_hidden()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_dbg_ui"):
		if debug_ui != null:
			debug_ui.visible = not debug_ui.visible
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_layer_off"):
		_set_raised_layer("")
		get_viewport().set_input_as_handled()
		return
	for i in 7:
		if event.is_action_pressed("world_layer_%d" % (i + 1)):
			_set_raised_layer(WorldDebugUIScript.LAYERS[i] if debug_ui != null else "")
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("world_move_y_dec") or event.is_action_pressed("world_move_y_inc"):
		var step := 16.0 if event.is_action_pressed("world_move_y_inc") else -16.0
		movable_y_offset = clampf(movable_y_offset + step, -240.0, 240.0)
		_rebuild_room()
		_log("可移动区 Y 偏移 = %+.0f px（16px 步长，x 不变）" % movable_y_offset)
		_update_hint()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_dbg_floor"):
		if builder != null:
			builder.debug_floor = not builder.debug_floor
			_sync_debug_ui()
			_rebuild_room()
		get_viewport().set_input_as_handled()
		return
	if _ui_open:
		return
	if event.is_action_pressed("world_dbg_boxes"):
		_toggle_debug("boxes")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_dbg_place"):
		_toggle_debug("place")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_dbg_grid"):
		_toggle_debug("grid")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_deco_raw"):
		_toggle_debug("deco")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_deco_up"):
		_nudge_deco_y(-10.0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_deco_down"):
		_nudge_deco_y(10.0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_deco_zero"):
		_nudge_deco_y(-builder.y_shift)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("world_reset"):
		reset_to_spawn()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("world_interact"):
		if event.is_action_pressed("world_back") and mode == "dungeon":
			return_to_town()
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if mode == "dungeon":
		return_to_town()
		return
	var entrances := _town_dungeon_entrances()
	if entrances.is_empty():
		_log("这个 area 没有 [dungeon gate]")
		return
	# 优先用当前 area 自己的副本 id
	var here := _town_dungeon_id_of_area(town_area)
	var target := here if here >= 0 else int(entrances[0])
	_log("进入副本 id=%d" % target)
	enter_dungeon_by_id(target)


func _town_dungeon_entrances() -> Array:
	var out := []
	if town == null:
		return out
	for e in town.dungeon_entrances():
		out.append(int(e.get("dungeon_id", -1)))
	return out


func _town_dungeon_id_of_area(area_index: int) -> int:
	if town == null:
		return -1
	var a := town.area(area_index)
	if str(a.get("type", "")) != "dungeon gate":
		return -1
	var args: Array = a.get("args", [])
	return int(args[0]) if not args.is_empty() else -1


## 调试 UI 的动作：面板按钮和快捷键走同一条入口，避免两份状态。
func _on_debug_action(which: String, arg: String) -> void:
	match which:
		"floor":
			if builder != null:
				builder.debug_floor = not builder.debug_floor
				_rebuild_room()
		"boxes", "place", "grid":
			_toggle_debug(which)
		"layer":
			_set_raised_layer(arg)
		"movable_y":
			movable_y_offset = clampf(roundf(float(arg) / 16.0) * 16.0, -240.0, 240.0)
			_rebuild_room()
			_log("可移动区 Y 偏移 = %+.0f px（16px 步长，x 不变）" % movable_y_offset)
			_update_hint()
		"walk_area":
			area_walk_only = not area_walk_only
			if builder != null:
				builder.area_walk_only = area_walk_only
			_rebuild_room()
			_log("移动模式 = %s" % ("只走 area" if area_walk_only else "地砖 0/2 + area"))
			_update_hint()
	_sync_debug_ui()


func _sync_debug_ui() -> void:
	if debug_ui == null:
		return
	debug_ui.set_state("floor", builder != null and builder.debug_floor)
	debug_ui.set_state("boxes", builder != null and builder.debug_boxes)
	debug_ui.set_state("place", builder != null and builder.debug_place)
	debug_ui.set_state("grid", builder != null and builder.debug_grid)
	debug_ui.set_state("walk_area", area_walk_only)
	debug_ui.set_movable_y(movable_y_offset)
	debug_ui.set_layer(_raised_layer)


## 把一个固定图层抬到“角色下面、其它所有层上面”，用来观察遮挡。
## 只改匹配 meta("layer") 的节点；z0 保留原值，取消时恢复。
func _set_raised_layer(layer: String) -> void:
	_restore_raised()
	_raised_layer = layer
	if layer != "":
		_collect_raised(room_node)
		_raise_ceiling = _actor_ceiling()
	else:
		_raise_ceiling = 0x7fffffff
	_apply_raise_z()
	_sync_debug_ui()
	_log("图层提升：%s" % (layer if layer != "" else "关"))


func _collect_raised(n: Node) -> void:
	if n == null:
		return
	if n is Node2D and n.has_meta("layer") and str(n.get_meta("layer")) == _raised_layer:
		_raised_nodes.append(n)
	for c in n.get_children():
		_collect_raised(c)


func _actor_ceiling() -> int:
	var z := 0x7fffffff
	if room_node == null:
		return z
	var stack: Array[Node] = [room_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node2D and n.has_meta("actor"):
			z = mini(z, (n as Node2D).z_index)
		for c in n.get_children():
			stack.append(c)
	return z


func _apply_raise_z() -> void:
	if _raised_nodes.is_empty():
		return
	# 基础层 z 全在 [-100,100]；临时提升也只到 LayerZ.Z_RAISE，且必须低于最近 actor。
	# 不再用 player.z-1 / 4096 这种大范围归一化。
	var z := LayerZ.Z_RAISE
	if _raise_ceiling < 0x7fffffff:
		z = mini(z, _raise_ceiling - 1)
	z = clampi(z, LayerZ.Z_MIN, LayerZ.Z_MAX)
	for n in _raised_nodes:
		if is_instance_valid(n):
			(n as Node2D).z_index = z


func _restore_raised() -> void:
	for n in _raised_nodes:
		if is_instance_valid(n) and n.has_meta("z0"):
			(n as Node2D).z_index = int(n.get_meta("z0"))
	_raised_nodes.clear()
	_raised_layer = ""


func _toggle_ui_hidden() -> void:
	_ui_hidden = not _ui_hidden
	if ui_layer != null:
		ui_layer.visible = not _ui_hidden
	if hint != null:
		hint.visible = not _ui_hidden
	if player_pos != null:
		player_pos.visible = not _ui_hidden


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "WorldUI"
	ui_layer.layer = 20
	add_child(ui_layer)
	town_list = TownListUI.new()
	town_list.name = "TownList"
	town_list.setup(content)
	town_list.town_selected.connect(_on_town_selected)
	town_list.opened.connect(_on_ui_opened)
	town_list.closed.connect(_on_ui_closed)
	ui_layer.add_child(town_list)
	debug_ui = WorldDebugUIScript.new()
	debug_ui.name = "WorldDebug"
	debug_ui.action.connect(_on_debug_action)
	ui_layer.add_child(debug_ui)
	_sync_debug_ui()


func _open_town_list() -> void:
	if town_list == null:
		return
	town_list.open_for(town_key if mode == "town" else last_town_key)


func _on_town_selected(town_key_in: String) -> void:
	if town_key_in == "":
		return
	_log("城镇列表 → %s" % town_key_in)
	if not enter_town(town_key_in):
		_log("传送失败：%s" % town_key_in)


func _on_ui_opened() -> void:
	_ui_open = true
	if player != null:
		player.set_process(false)


func _on_ui_closed() -> void:
	_ui_open = false
	if player != null:
		player.set_process(true)


func _build_hint() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	hint = Label.new()
	hint.position = Vector2(16, 38)
	hint.add_theme_font_override("font", WorldFont.make(400))
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hint.add_theme_constant_override("outline_size", 4)
	layer.add_child(hint)
	player_pos = Label.new()
	player_pos.position = Vector2(16, 12)
	player_pos.add_theme_font_override("font", WorldFont.make(400))
	player_pos.add_theme_font_size_override("font_size", 13)
	player_pos.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	player_pos.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	player_pos.add_theme_constant_override("outline_size", 4)
	layer.add_child(player_pos)


## 左上角实时角色位置：HUD 第二块，独立于房间提示，每帧更新。
func _update_player_pos() -> void:
	if player_pos == null or player == null:
		return
	var cw := grid.cell_w if grid != null else PassGrid.CELL
	var cx := int(floor(player.position.x / cw))
	var cy := int(floor(player.position.y / PassGrid.CELL))
	if grid != null:
		cy = int(floor((player.position.y - grid.origin_y - grid.move_y_offset) / PassGrid.CELL))
	var area_txt := "area %d" % town_area if mode == "town" else "cell %s" % str(cell)
	player_pos.text = "角色 x=%.1f y=%.1f  cell=(%d,%d)  z=%d  %s" % [
			player.position.x, player.position.y, cx, cy, player.z_index, area_txt]
func _update_hint() -> void:
	if hint == null:
		return
	var lines: Array[String] = []
	if mode == "town":
		var a := town.area(town_area) if town != null else {}
		var tname := town.display_name() if town != null else town_key
		lines.append("城镇 %s（%s）  area %d/%d  type=%s" % [tname, town_key, town_area,
				town.area_count() if town != null else 0, str(a.get("type", ""))])
		var did := _town_dungeon_id_of_area(town_area)
		if did >= 0:
			lines.append("E 进入副本 id=%d   M 城镇列表" % did)
		else:
			lines.append("M 城镇列表")
	else:
		lines.append("副本 %s  cell %s  地图 %s" % [dungeon_key, str(cell),
				room.path if room != null else ""])
		lines.append("Esc/R 回城   M 城镇列表")
	lines.append("房间 %dx%d 格  移动范围Y %+.0f  移动=%s   怪物 %d   NPC %d   物件 %d" % [
			grid.cols if grid != null else 0, grid.rows if grid != null else 0,
			movable_y_offset, "只走area" if area_walk_only else "地砖+area",
			room.monsters.size() if room != null else 0,
			room.npcs.size() if room != null else 0,
			room.objects.size() if room != null else 0])
	if store != null:
		lines.append("缓存 tex=%d img=%d   content=%s" % [
				int(store.stats().get("cached_tex", 0)),
				int(store.stats().get("cached_img", 0)),
				str(content.cache_stats()) if content != null else "{}"])
	if builder != null and absf(builder.y_shift) > 0.01:
		lines.append("[animation] y 偏移 %+.0f px（, / . 微调，/ 归零）" % builder.y_shift)
	hint.text = "\n".join(lines)
	_update_player_pos()


# ---------------------------------------------------------------- 工具

## 可装载 = 内容包里有这张图、且图里真有地砖（有些图只写一行 [import script]
## 指向早已删除的旧图，装进去只会得到空房间）
func _area_usable(i: int) -> bool:
	if town == null:
		return false
	var mp := town.map_of(i)
	if mp == "" or not content.has_map(mp):
		return false
	return content.map_room(mp).tile_count() > 0


func _default_area(t: TownDef) -> int:
	for i in t.area_count():
		if _area_usable(i):
			return i
	return -1


func _next_area_with_map(from_index: int) -> int:
	if town == null:
		return -1
	for i in range(from_index + 1, town.area_count()):
		if _area_usable(i):
			return i
	for i in from_index:
		if _area_usable(i):
			return i
	return -1


func _rect_groups(values: Array, step: int) -> Array:
	var out := []
	var i := 0
	while i + step - 1 < values.size():
		var v := []
		for k in step:
			v.append(int(values[i + k]))
		out.append({"values": v, "rect": Rect2(v[0], v[1], v[2], v[3])})
		i += step
	return out


func _log(msg: String) -> void:
	log_lines.append(msg)
	LogUtil.info("[World] " + msg)
