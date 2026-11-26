## 格兰之森（幽暗密林）房间 —— 把 sf85 索引拼成一个可玩的场景
##
## 结构：
##   Room(Node2D, y_sort)
##     ├ Tiles        8 张 224×480 地板分片
##     ├ Actors       y_sort：玩家 + 怪物（按景深 y 排序）
##     └ HUD
extends Node2D

const ROOM_ID := "map/mirkwood/n201.map"

@onready var tiles_root: Node2D = $Tiles
@onready var actors_root: Node2D = $Actors
@onready var hud: Sf85Hud = $HUD/Hud
@onready var camera: Camera2D = $Camera2D

var assets := Sf85Assets.new()
var room_data: Dictionary = {}
var player: Sf85Player = null
var monsters: Array[Sf85Monster] = []
var pass_grid: PackedByteArray = PackedByteArray()
var grid_w := 0
var grid_h := 30
var cell := 16
var room_w := 0
var room_h := 480
var debug_draw := OS.get_environment("SF85_DEBUG") == "1"
var demo_mode := false
var demo_t := 0
var ui: IngameUI = null
var hud_bottom: Sf85HudBottom
var _pad_extra_last := false
var damage_layer: Node2D = null
var zoom_scale := 1.0

## 设计基准分辨率；实际窗口放大时只放大世界（相机 zoom），UI 保持像素尺寸。
const BASE_VIEW := Vector2(1152, 648)
const BASE_ZOOM := 1.4

const START := Vector2(320, 400)

## 地面视觉对齐（实测）：`.til` 的草地内容从 y=245 起，而 `[pass type]` 的可走带从
## y=192（第 12 行）起 —— 地图坐标比地贴图的像素坐标「高」53px。
## 统一把角色（和通行表查询）下移 GROUND_Y，脚才落在草地上。
const GROUND_Y := 53.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.10, 0.07))
	# 键位统一走 DnfKeys（DNF 客户端动作表 + 一版临时默认方案），见 core/input/dnf_keys.gd
	DnfKeys.install()
	GamepadKeys.install()
	# 本工程自己的调试/非 DNF 动作
	_bind_keys("debug_toggle", [KEY_F12])
	_bind_keys("ui_console", [KEY_QUOTELEFT])
	_bind_keys("sf85_warehouse", [KEY_K])

	if not _open_assets():
		hud.set_message("资产加载失败：%s" % _pvf_path())
		return
	_build_tiles()
	_build_background()
	_build_decos()
	_build_pass()
	_spawn_monsters()
	_spawn_player()
	damage_layer = Node2D.new()
	damage_layer.name = "DamageLayer"
	damage_layer.z_index = 200
	add_child(damage_layer)
	hud.setup(player, damage_layer, camera)
	var hud_scale_env := OS.get_environment("SF85_HUD_SCALE")
	if hud_scale_env != "":
		hud.set_hud_scale(float(hud_scale_env))
	_setup_ui()
	_build_bottom_hud()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = room_w
	camera.limit_bottom = room_h
	camera.position_smoothing_enabled = false
	get_viewport().size_changed.connect(_update_camera_zoom)
	_update_camera_zoom()
	demo_mode = OS.get_environment("SF85_DEMO") == "1"
	var scale_env := OS.get_environment("SF85_UI_SCALE")
	if scale_env != "" and ui != null:
		ui.root.set_ui_scale(float(scale_env))
	if OS.get_environment("SF85_UI_DEMO") == "1" and ui != null:
		ui.open_inventory()
	if OS.get_environment("SF85_UI_CONSOLE") == "1" and ui != null:
		ui.open_console()
	if OS.get_environment("SF85_UI_KEYBINDS") == "1" and ui != null:
		ui.open_keybinds()
	if OS.get_environment("SF85_DAMAGE_TEST") == "1":
		_spawn_test_damage()


func _spawn_test_damage() -> void:
	await get_tree().create_timer(0.55).timeout
	if hud == null or player == null:
		return
	hud.spawn_damage(player.global_position + Vector2(0, -92), 1234, "crit")
	hud.spawn_damage(player.global_position + Vector2(34, -70), 88, "hit")
	await get_tree().create_timer(0.25).timeout
	hud.spawn_damage(player.global_position + Vector2(-30, -60), 256, "skill")


## 底部主 HUD：消耗品 / 技能栏 / HP-MP 球 / 功能按钮
func _build_bottom_hud() -> void:
	if OS.get_environment("SF85_HUD_BOTTOM") == "0":
		return
	if hud == null:
		return
	hud_bottom = Sf85HudBottom.new()
	hud_bottom.name = "HudBottom"
	hud.add_child(hud_bottom)
	hud_bottom.setup(player, self)
	# 0 号技能槽 = 现有的「上挑」；其余槽位留空，按键会提示未装配
	if player != null:
		var cd_ms := float(player.skill_info.get("cool_time", 2000))
		hud_bottom.set_skill(0, null, str(player.skill_info.get("name", "上挑")), cd_ms / 1000.0)
	hud_bottom.consumable_used.connect(_on_consumable_used)
	hud_bottom.skill_used.connect(_on_skill_used)
	hud_bottom.button_pressed.connect(_on_hud_button)


## 技能栏热键（A S D F G H / Q W E R T Y，随 DnfKeys 改键）
func _poll_hotbar_keys() -> void:
	if hud_bottom == null:
		return
	for i in Sf85HudBottom.SKILL_IDS.size():
		if DnfKeys.is_just_pressed(str(Sf85HudBottom.SKILL_IDS[i])):
			_on_skill_used(i)
	for i in Sf85HudBottom.CONSUMABLE_IDS.size():
		if DnfKeys.is_just_pressed(str(Sf85HudBottom.CONSUMABLE_IDS[i])):
			_on_consumable_used(i)
	if DnfKeys.is_just_pressed("I61"):
		open_keybinds()
	_poll_gamepad()


## 手柄：技能槽 / 药水 / 切目标 / 菜单（普攻、闪避、跳跃走 InputMap，玩家逻辑不用改）
func _poll_gamepad() -> void:
	if hud_bottom == null:
		return
	var pad_env := OS.get_environment("SF85_HUD_PAD") == "1"
	var want_pad := pad_env or GamepadKeys.is_pad_active()
	if hud_bottom.pad_active != want_pad:
		hud_bottom.pad_active = want_pad
		hud_bottom.queue_redraw()
	if GamepadKeys.extra_row() != _pad_extra_last:
		_pad_extra_last = GamepadKeys.extra_row()
		hud_bottom.refresh_pad_layout()
	var it := GamepadKeys.read()
	if int(it["skill"]) >= 0:
		_on_skill_used(int(it["skill"]))
	if int(it["consumable"]) >= 0:
		_on_consumable_used(int(it["consumable"]))
	if int(it["target"]) != 0 and player != null:
		player.cycle_target(int(it["target"]))
	if bool(it["menu"]) and ui != null:
		ui.root.close_all()
		if hud_bottom != null:
			hud_bottom.toast("菜单（START）")
	if bool(it["close"]) and ui != null:
		ui.root.close_all()


func open_keybinds() -> void:
	if ui != null:
		ui.open_keybinds()


func _on_skill_used(index: int) -> void:
	if player == null or hud_bottom == null:
		return
	if player.hotbar_skill(index):
		return
	hud_bottom.toast("技能槽 %d 还没装配技能" % (index + 1))


func _on_consumable_used(index: int) -> void:
	if hud_bottom != null:
		hud_bottom.toast("消耗品 %d：背包里没有可用道具" % (index + 1))


func _on_hud_button(id: String) -> void:
	match id:
		"inventory":
			if ui != null:
				ui.toggle_inventory()
		"keybinds":
			open_keybinds()
		"map":
			if hud_bottom != null:
				hud_bottom.toast("地图还没接（DNF I17 城镇地图 / 地下城地图）")
		"mall":
			if hud_bottom != null:
				hud_bottom.toast("商城还没接（DNF I16 商城）")
		"menu":
			if ui != null:
				ui.root.close_all()


## 游戏内 UI：独立 CanvasLayer，不自动打开背包；I/K/F3/Esc 由 UIRoot 处理。
func _setup_ui() -> void:
	if OS.get_environment("SF85_UI") == "0":
		return
	ui = IngameUI.new()
	ui.name = "UI"
	add_child(ui)
	if player != null:
		ui.bind(assets, player.def, hud, self)


func _bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

# ---------------------------------------------------------------------------
## PVF 路径解析顺序：环境变量 SF85_PVF > 项目设置 sf85/pvf > 常见位置
func _pvf_path() -> String:
	var env := OS.get_environment("SF85_PVF")
	if env != "" and FileAccess.file_exists(env):
		return env
	var cfg := str(ProjectSettings.get_setting("sf85/pvf", ""))
	if cfg != "" and FileAccess.file_exists(cfg):
		return cfg
	for c in [
		"res://_archive/sf85/Script.utf8.pvf",
		"/home/sunmingze/dnf_like/build/sf85.Script.utf8.pvf",
		"E:/dnf-sf/sf85/老牛DNF客户端/Script.pvf",
		"/mnt/e/dnf-sf/sf85/老牛DNF客户端/Script.pvf",
	]:
		if FileAccess.file_exists(c):
			return c
	return ""

func _open_assets() -> bool:
	var idx := str(ProjectSettings.get_setting("npk/index", "res://assets/npk-index.bin"))
	return assets.open(_pvf_path(), idx)

func _build_tiles() -> void:
	room_data = assets.room(ROOM_ID)
	room_w = int(room_data.get("width", 1792))
	room_h = int(room_data.get("height", 480))
	# [tile] 的 8 条 = 房间从左到右的 8 个竖直切片（每条 224 宽、整幅 480 高，
	# 各自带 14x30 的通行表）。切片用的 .til 不同（forestover / forestunder …），
	# 这是地图作者做纵深变化的方式，不能当成「图层」重复铺。
	var ci := 0
	for li in room_data.get("tiles", []):
		var t: Dictionary = li
		var info := assets.tile_info(t)
		if info.is_empty():
			ci += 1
			continue
		var s := Sprite2D.new()
		s.texture = info["tex"]
		s.centered = false
		s.position = Vector2(float(ci) * 224.0 + float(info["x"]), float(info["y"]))
		s.z_index = -50
		tiles_root.add_child(s)
		ci += 1

## 远景/中景：整幅图按房间宽度横向重复，z 由 [layer] 决定
func _build_background() -> void:
	var zmap := {"distantback": -100, "middleback": -90, "nearback": -80}
	for b in room_data.get("backgrounds", []):
		var fr := _first_frame_of_ani(str(b.get("ani", "")))
		if fr.is_empty():
			continue
		var info := assets.frame_info(fr)
		if info.is_empty():
			continue
		var w: float = info["w"]
		var reps := int(ceil(float(room_w) / maxf(w, 1.0)))
		for i in reps:
			var s := Sprite2D.new()
			s.texture = info["tex"]
			s.centered = false
			s.position = Vector2(float(info["x"]) + w * i, float(info["y"]))
			s.z_index = int(zmap.get(str(b.get("layer", "")), -30))
			# 大气透视：远景提亮 + 降对比，人物才从树里跳出来
			if s.z_index <= -90:
				s.modulate = Color(1.28, 1.30, 1.34)
			else:
				s.modulate = Color(1.10, 1.11, 1.13)
			tiles_root.add_child(s)

## [animation] 装饰物：bottom 在地板层，normal 进 Actors 参与 y 排序
func _build_decos() -> void:
	for d in room_data.get("decos", []):
		var fr := _first_frame_of_ani(str(d.get("ani", "")))
		if fr.is_empty():
			continue
		var info := assets.frame_info(fr)
		if info.is_empty():
			continue
		var s := Sprite2D.new()
		s.texture = info["tex"]
		s.centered = false
		s.position = Vector2(float(info["x"]) + float(d["x"]), float(info["y"]) + float(d["y"]))
		if d.get("layer", "normal") == "bottom":
			s.z_index = -45
			tiles_root.add_child(s)
		else:
			s.z_index = 0
			actors_root.add_child(s)

## 背景/装饰用的动画：直接解 .ani 的第 0 帧
func _first_frame_of_ani(ani_path: String) -> Dictionary:
	if ani_path == "":
		return {}
	var a := assets.animation(ani_path)
	var frs: Array = a.get("frames", [])
	return frs[0] if not frs.is_empty() else {}

func _build_pass() -> void:
	var slices: Array = room_data.get("pass_rows", [])
	grid_w = slices.size() * 14
	grid_h = 30
	pass_grid.resize(grid_w * grid_h)
	for sx in slices.size():
		var cells: Array = slices[sx]
		for i in mini(cells.size(), 420):
			var col: int = i % 14
			var row: int = i / 14
			pass_grid[row * grid_w + (sx * 14 + col)] = int(cells[i])

func pass_at(x: float, y: float) -> int:
	if x < 0.0 or y < 0.0:
		return 0
	var col := int(x / cell)
	var row := int(y / cell)
	if col < 0 or row < 0 or col >= grid_w or row >= grid_h:
		return 0
	return pass_grid[row * grid_w + col]

func is_walkable(pos: Vector2) -> bool:
	if pos.x < 40.0 or pos.x > room_w - 40.0:
		return false
	if pos.y < 150.0 + GROUND_Y or pos.y > room_h - 12.0:
		return false
	return pass_at(pos.x, pos.y - GROUND_Y) == 0    # 0 = 可走，2 = 墙/天空

# ---------------------------------------------------------------------------
func _spawn_player() -> void:
	player = Sf85Player.new()
	player.assets = assets
	player.room = self
	if assets.has_actor("player"):
		player.setup(assets.actor("player"), assets)
	player.position = START + Vector2(0, GROUND_Y)
	# 决斗模式：挪到第一只怪身前，方便截「判定盒命中」的图
	if OS.get_environment("SF85_DUEL") == "1" and not monsters.is_empty():
		var m0 := monsters[0]
		player.position = m0.position + Vector2(-46, 0)
		player.facing = 1
		player.scale.x = absf(player.scale.x)
	player.name = "Player"
	player.hit_landed.connect(_on_player_hit)
	player.damaged.connect(_on_player_damaged)
	actors_root.add_child(player)
	# 怪物是在玩家之前生成的，生成时 player 还是 null；这里补指向。
	for mon in monsters:
		mon.target = player

func _spawn_monsters() -> void:
	for m in room_data.get("monsters", []):
		var id := "mob:%d" % int(m.get("id", 0))
		if not assets.has_actor(id):
			continue
		var mon := Sf85Monster.new()
		mon.assets = assets
		mon.setup(assets.actor(id), assets)
		mon.position = Vector2(float(m["x"]), float(m["y"]) + GROUND_Y)
		mon.target = player
		actors_root.add_child(mon)
		monsters.append(mon)
	# 玩家是在怪物之后创建的，这里补一次指向
	for mon in monsters:
		mon.target = player


## 命中判定：攻击盒（武器层 .ani 的真实判定）∩ 怪物受击体积（.mob [width] 推出的矩形）
func _on_player_hit(boxes: Array, damage: float, launch: bool, push: float) -> void:
	for mon in monsters:
		if mon.is_dead():
			continue
		var body := mon.body_rect()
		for b in boxes:
			if (b as Rect2).intersects(body):
				mon.take_hit(damage, player.global_position.x, launch, push)
				var kind := "skill" if player.state == "skill" else "hit"
				hud.spawn_damage(mon.global_position + Vector2(0, -mon.body_width() * 0.9), damage, kind)
				break


func _on_player_damaged(amount: float, world_pos: Vector2) -> void:
	hud.spawn_damage(world_pos, amount, "player")

# ---------------------------------------------------------------------------
## 身体碰撞：玩家和怪物按各自的 `[width]` 互相挤开（DNF 里角色之间是实体的）
func _physics_process(_delta: float) -> void:
	if player == null:
		return
	for mon in monsters:
		if mon.is_dead():
			continue
		var dx := player.global_position.x - mon.global_position.x
		var min_gap := (player.body_width() + mon.body_width()) * 0.5
		if absf(dx) >= min_gap:
			continue
		# 只沿 x 分开（y 是景深，不参与碰撞）
		var push := (min_gap - absf(dx)) * 0.5
		var dir := 1.0 if dx >= 0.0 else -1.0
		var p := player.global_position
		var m := mon.global_position
		if room_data.get("width", 0) != null:
			var w := float(room_data.get("width", 1792))
			p.x = clampf(p.x + dir * push, 8.0, w - 8.0)
			m.x = clampf(m.x - dir * push, 8.0, w - 8.0)
		player.global_position = p
		mon.global_position = m


func _process(_delta: float) -> void:
	if player == null:
		return
	_poll_hotbar_keys()
	if hud_bottom != null:
		hud_bottom.set_skill_cd(0, player.skill_cd_left(),
			float(player.skill_info.get("cool_time", 2000)) / 1000.0)
	if demo_mode:
		_demo_tick()
	camera.global_position = player.global_position + Vector2(0, -60)
	if Input.is_action_just_pressed("debug_toggle"):
		debug_draw = not debug_draw
	if debug_draw:
		queue_redraw()

## 世界缩放：窗口变大时相机 zoom 同步变大，保持同样的视野范围；
## UI 是独立 CanvasLayer，不乘这个 zoom。
func _update_camera_zoom() -> void:
	if camera == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var s := minf(vp.x / BASE_VIEW.x, vp.y / BASE_VIEW.y)
	s = maxf(0.35, s) * zoom_scale
	camera.zoom = Vector2(BASE_ZOOM * s, BASE_ZOOM * s)


func set_zoom_scale(v: float) -> void:
	zoom_scale = clampf(v, 0.6, 1.8)
	_update_camera_zoom()


## 自检用的自动驾驶：走 → 跳 → 普攻三连 → 上挑，循环
func _demo_tick() -> void:
	demo_t += 1
	var t := demo_t % 420
	Input.action_release("move_right")
	if t < 90:
		Input.action_press("move_right")
	elif t == 100 or t == 112:
		_pulse("attack")
	elif t == 145:
		_pulse("jump")
	elif t == 200 or t == 214 or t == 228:
		_pulse("attack")
	elif t == 300:
		_pulse("skill")
	if OS.get_environment("SF85_DUEL") == "1" and t % 60 == 20:
		_pulse("attack")
	elif t > 350 and t < 390:
		Input.action_press("move_left")

func _pulse(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_press(action)
	Input.action_release(action)

func _draw() -> void:
	if not debug_draw:
		return
	# 判定盒（蓝）/ 受击体积（绿）：来源是武器层 .ani 的 [attack box] 与 .chr/.mob 的 [width]
	if player != null:
		for b in player.boxes("attack"):
			draw_rect(b as Rect2, Color(0.25, 0.6, 1.0, 0.9), false, 2.0)
		draw_rect(player.body_rect(), Color(0.9, 0.9, 0.2, 0.5), false, 1.5)
		for mon in monsters:
			if mon.is_dead():
				continue
			draw_rect(mon.body_rect(), Color(0.3, 1.0, 0.3, 0.45), false, 1.5)
			# 血条：宽度 = .mob 的 [width]，血量来自 .mob 的 [ability category][hp max]
			var r := mon.body_rect()
			var bw := r.size.x
			var bx := r.position.x
			var by := r.position.y - 10.0
			draw_rect(Rect2(bx, by, bw, 4.0), Color(0.1, 0.1, 0.1, 0.8))
			draw_rect(Rect2(bx, by, bw * clampf(mon.hp / maxf(mon.hp_max, 1.0), 0.0, 1.0), 4.0),
				Color(0.9, 0.2, 0.2, 0.9))
	for row in grid_h:
		for col in grid_w:
			var v := pass_grid[row * grid_w + col]
			var r := Rect2(col * cell, row * cell, cell, cell)
			if v == 2:
				# 2 = 墙/天空：整片刷淡红，方便一眼看出可走边界
				draw_rect(r, Color(1, 0.25, 0.25, 0.18))
