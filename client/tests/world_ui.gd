extends SceneTree
## UI / 跨城 / 缓存释放：./tools/godot.sh --headless --script res://tests/world_ui.gd

var _ok := 0
var _fail := 0
var _ran := false


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   ", name)
	else:
		_fail += 1
		print("  FAIL ", name, "  ", detail)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	print("\n== %d ok, %d fail ==" % [_ok, _fail])
	quit(0 if _fail == 0 else 1)
	return false


func _buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_buttons(c, out)


func _run() -> void:
	var d = load("res://game/world/flow/world_director.gd").new()
	d.name = "World"
	get_root().add_child(d)
	_check("启动城镇", d.mode == "town" and d.town != null)
	_check("左上角有实时角色坐标", d.player_pos != null and d.player_pos.text.contains("cell="),
			d.player_pos.text if d.player_pos != null else "null")
	# area/virtual 与地砖 pass 取并集：new_hendon_main 的 virtual 矩形在网格下方仍可走；
	# 但并集只补指定矩形，不会把网格外的所有区域解锁。
	_check("virtual 补充网格外可走", d.grid.walkable_at(Vector2(100, 540)),
			str(d.grid.walk_rects.size()))
	_check("并集外仍保持阻挡", not d.grid.walkable(6, 33), "cell(6,33)")
	# 验证“实际移动范围是不是只由 area/virtual 组成”：只走 area 模式。
	_check("面板有只走area按钮", d.debug_ui._buttons.has("walk_area"))
	d._on_debug_action("walk_area", "")
	_check("只走area开关生效", d.area_walk_only and d.grid.walk_rects_only)
	_check("只走area时网格外不可走", not d.grid.walkable_at(Vector2(100, 50)),
			str(d.grid.walk_rects.size()))
	d._on_debug_action("walk_area", "")
	_check("恢复地砖+area模式", not d.area_walk_only and not d.grid.walk_rects_only)

	# 0) 调试 UI：地板块、图层提升、隐藏 UI
	d._on_debug_action("floor", "")
	_check("地板块开关", d.builder.debug_floor, str(d.builder.debug_floor))
	_check("地板块节点存在", d.room_node.find_child("DebugFloor", true, false) != null)
	d._set_raised_layer("closeback")
	var raised_ok: bool = not d._raised_nodes.is_empty()
	var actor_z: int = d._actor_ceiling()
	var expect_z: int = LayerZ.Z_RAISE
	if actor_z < 0x7fffffff:
		expect_z = mini(expect_z, actor_z - 1)
	expect_z = clampi(expect_z, LayerZ.Z_MIN, LayerZ.Z_MAX)
	for n in d._raised_nodes:
		if int((n as Node2D).z_index) != expect_z:
			raised_ok = false
	_check("图层提升到角色下方且不盖住 NPC", raised_ok, "nodes=%d player_z=%d actor_z=%d expect=%d" % [d._raised_nodes.size(), d.player.z_index, actor_z, expect_z])
	var pg := PassGrid.new()
	pg.cols = 2
	pg.rows = 1
	pg.cells = PackedByteArray([0, 2])
	_check("通行表 0 可走", pg.walkable(0, 0))
	_check("通行表 2 阻挡", not pg.walkable(1, 0))
	d._set_raised_layer("")
	_check("取消图层提升", d._raised_layer == "" and d._raised_nodes.is_empty())
	var ev_layer := InputEventAction.new()
	ev_layer.action = "world_layer_5"
	ev_layer.pressed = true
	d._unhandled_input(ev_layer)
	_check("数字键 5 提升普通层", d._raised_layer == "normal", d._raised_layer)
	d._set_raised_layer("")
	var ev3 := InputEventAction.new()
	ev3.action = "world_layer_3"
	ev3.pressed = true
	d._unhandled_input(ev3)
	_check("数字键 3 对应 closeback（近背景）", d._raised_layer == "closeback", d._raised_layer)
	d._set_raised_layer("")
	var ev_panel := InputEventAction.new()
	ev_panel.action = "world_dbg_ui"
	ev_panel.pressed = true
	d.debug_ui.visible = false
	d._unhandled_input(ev_panel)
	_check("L 打开调试面板", d.debug_ui.visible)
	d._unhandled_input(ev_panel)
	_check("L 关闭调试面板", not d.debug_ui.visible)
	_check("调试面板有移动区 Y 滑块", d.debug_ui._movable_y_slider != null)
	d._toggle_ui_hidden()
	_check("U 隐藏 HUD/UI", not d.hint.visible and not d.ui_layer.visible)
	d._toggle_ui_hidden()
	_check("U 恢复 HUD/UI", d.hint.visible and d.ui_layer.visible)

	# 1) 列表 UI：打开、按地区列出全部城镇、当前城镇有标记
	d._open_town_list()
	_check("M 打开城镇列表", d.town_list != null and d.town_list.visible and d._ui_open)
	_check("打开时玩家暂停", not d.player.is_processing())
	var btns: Array = []
	_buttons(d.town_list, btns)
	_check("列表有全量城镇按钮", btns.size() >= 100, "got %d" % btns.size())
	var texts := ""
	for b in btns:
		texts += b.text + " | "
	_check("当前城镇有 ● 标记", texts.contains("●"), texts)
	_check("列表含中央公园", texts.contains("中央公园"), texts)

	# 2) 点一行 -> 传送并关闭
	var target: Button = null
	for b in btns:
		if b.text.contains("中央公园"):
			target = b
	if target != null:
		target.pressed.emit()
	_check("点中央公园后切城", d.town_key.get_file() == "centralpark.twn", d.town_key)
	_check("传送后 UI 关闭/玩家恢复", not d.town_list.visible and not d._ui_open and d.player.is_processing())
	_check("传送后仍在 town 模式", d.mode == "town" and d.room != null)

	# 3) 跨城 town_movable：中央公园 area1 -> 魔界营地（town id 35）
	d.enter_town("town_centralpark.twn", 1)
	var found := false
	var cross_rect := Rect2()
	for g in d._rect_groups(d.room.town_movable, 6):
		if int(g["values"][4]) == 35:
			cross_rect = d.grid.map_rect(g["rect"])
			found = true
			break
	_check("中央公园有去魔界营地的 movable", found)
	if found:
		d.player.position = cross_rect.get_center()
		d._switch_cooldown = 0.0
		d._check_town_movable()
		_check("跨城到 town_devildom_contact", d.town_key.get_file() == "devildom_contact.twn",
				"town=%s area=%d" % [d.town_key, d.town_area])

	# 3b) 中央公园 area3 -> 魔界集结地（town id 30），验证地区内三城是连通的
	d.enter_town("town_centralpark.twn", 3)
	var metro_found := false
	for g in d._rect_groups(d.room.town_movable, 6):
		if int(g["values"][4]) == 30:
			d.player.position = d.grid.map_rect(g["rect"]).get_center()
			metro_found = true
			break
	_check("中央公园有去魔界集结地的 movable", metro_found)
	if metro_found:
		d._switch_cooldown = 0.0
		d._check_town_movable()
		_check("跨城到 town_metrocenter", d.town_key.get_file() == "metrocenter.twn",
				"town=%s area=%d" % [d.town_key, d.town_area])

	# 4) -2/-2 = 世界地图 -> 打开列表
	d.enter_town("town_hendonmyre.twn", 5)
	var gate_found := false
	var gate_rect := Rect2()
	for g in d._rect_groups(d.room.town_movable, 6):
		if int(g["values"][4]) == -2 and int(g["values"][5]) == -2:
			gate_rect = d.grid.map_rect(g["rect"])
			gate_found = true
			break
	_check("赫顿玛尔 gate 有 -2/-2", gate_found)
	if gate_found:
		d.player.position = gate_rect.get_center()
		d._switch_cooldown = 0.0
		d._check_town_movable()
		_check("-2/-2 打开城镇列表", d.town_list.visible)
		# 站在触发区里不应反复弹窗；走出去再回来才重新触发
		d._switch_cooldown = 0.0
		d._check_town_movable()
		_check("触发区里不重复弹窗", d.town_list.visible)
		d.player.position = gate_rect.position + Vector2(-40, -40)
		d._check_town_movable()
		d.player.position = gate_rect.get_center()
		d._switch_cooldown = 0.0
		d._check_town_movable()
		_check("走出再回来能重新打开", d.town_list.visible)
		d.town_list.close()

	# 5) 缓存上限：连切几次后 transient/tex 不超过配置
	for k in ["town_metrocenter.twn", "town_centralpark.twn", "town_devildom_contact.twn",
			"town_hendonmyre.twn", "town_centralpark.twn"]:
		d.enter_town(k, 1)
	var cs: Dictionary = d.content.cache_stats()
	var st: Dictionary = d.store.stats()
	_check("transient <= 64", int(cs.get("transient", 0)) <= 64, str(cs))
	_check("defs <= 128", int(cs.get("defs", 0)) <= 128, str(cs))
	_check("tex <= 400（含当前房间）", int(st.get("cached_tex", 0)) <= 400, str(st))
	_check("img <= 48（NpkStore 硬上限）", int(st.get("cached_img", 0)) <= 48, str(st))
	_check("tex_bytes <= 64MB", int(st.get("tex_bytes", 0)) <= 64 * 1024 * 1024, str(st))

	# 5b) 只允许移动区 y 偏移：16px 步长、x/宽度/格宽完全不变
	var width0: float = d.grid.width
	var cell0: float = d.grid.cell_w
	var cols_y0: int = d.grid.cols
	var origin0: float = d.grid.origin_y
	var area0: float = d.grid.map_rect(Rect2(0, 100, 10, 10)).position.y
	d._on_debug_action("movable_y", "17")
	_check("移动区 Y 按 16px 步长", absf(d.grid.move_y_offset - 16.0) < 0.001,
			"move_y=%s" % d.grid.move_y_offset)
	_check("移动区 Y 不改变 area 基准", absf(d.grid.origin_y - origin0) < 0.001,
			"origin=%s/%s" % [d.grid.origin_y, origin0])
	_check("移动区 Y 不移动 area/传送框", absf(d.grid.map_rect(Rect2(0, 100, 10, 10)).position.y - area0) < 0.001,
			"area=%s/%s" % [d.grid.map_rect(Rect2(0, 100, 10, 10)).position.y, area0])
	_check("移动区 Y 改变后宽度不变", absf(d.grid.width - width0) < 0.01,
			"width=%s/%s" % [d.grid.width, width0])
	_check("移动区 Y 改变后格宽不变", absf(d.grid.cell_w - cell0) < 0.001,
			"cell_w=%s/%s" % [d.grid.cell_w, cell0])
	_check("移动区 Y 改变后列数不变", d.grid.cols == cols_y0, "%d/%d" % [d.grid.cols, cols_y0])
	d._on_debug_action("movable_y", "0")
	_check("移动区 Y 恢复", absf(d.grid.move_y_offset) < 0.001,
			"move_y=%s" % d.grid.move_y_offset)

	# 5c) 背景只跟 x，不跟 y（取第一层背景，故意只移动镜头 y）
	var bg: Node2D = null
	for n in d._parallax_nodes:
		if n is Node2D:
			bg = n
			break
	if bg != null:
		var by := bg.position.y
		d._last_cam = d.camera.position
		d.camera.position.y += 50.0
		d._sync_parallax()
		_check("背景 y 不随镜头上下移动", absf(bg.position.y - by) < 0.001,
				"y=%s/%s" % [bg.position.y, by])
		d._last_cam = Vector2.INF
	else:
		_check("当前房间有背景层", false, "no parallax node")

	# 6) 显式卸载后缓存确实被裁掉，再进一次城仍能正常渲染
	d._unload_room()
	var cs2: Dictionary = d.content.cache_stats()
	var st2: Dictionary = d.store.stats()
	_check("卸载后 transient 裁到 <= 40", int(cs2.get("transient", 0)) <= 40, str(cs2))
	_check("卸载后 tex 裁到 <= 320", int(st2.get("cached_tex", 0)) <= 320, str(st2))
	d.enter_town("town_hendonmyre.twn", 1)
	_check("最后一次仍装载了房间", d.room != null and d.grid != null and d.room.tile_count() > 0)
