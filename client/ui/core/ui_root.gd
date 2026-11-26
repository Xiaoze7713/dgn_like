## UI 根节点：主题、磨砂背景、窗口层、浮框层、快捷键。
##
## 用法（挂在 CanvasLayer 下）：
##   var ui := UIRoot.new()
##   ui.theme_preset = "abyss"
##   canvas.add_child(ui)
##   ui.bind_assets(assets, assets.actor("player"))
class_name UIRoot
extends Control

@export_enum("abyss", "ember", "jade", "violet") var theme_preset := "abyss"
@export var theme_data: UITheme = null
@export var open_inventory_on_start := true
@export var dim_background := true
@export var enable_shortcuts := true

var inventory: InventoryWindow
var warehouse: WarehouseWindow
var tooltip_layer: UITooltipLayer
var window_layer: Control
var content_root: Control
var debug_layer: Control
var keybind_window: KeybindWindow = null
var debug_console: UIDebugConsole
var dim: ColorRect
var back_buffer: BackBufferCopy
var ui_scale := 0.9

var _assets: Sf85Assets = null
var _store: NpkStore = null
var _player_actor: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("ui_root")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().min_size = Vector2i(1280, 900)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var data := theme_data
	if data == null:
		data = UIThemePresets.get_theme(theme_preset)
	apply_theme(data)

	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.34)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.hide()
	add_child(dim)

	# 在这之后画的内容会去采样已经画好的画面（含 dim），玻璃才有东西可磨。
	back_buffer = BackBufferCopy.new()
	back_buffer.name = "BackBufferCopy"
	back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(back_buffer)

	# UI 缩放根：窗口/浮框都在这里，缩放它不会连带游戏世界。
	# 尺寸取 viewport / scale，这样子控件仍按“物理像素”定位/居中。
	content_root = Control.new()
	content_root.name = "Content"
	content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.position = Vector2.ZERO
	content_root.size = get_viewport_rect().size
	add_child(content_root)

	window_layer = Control.new()
	window_layer.name = "Windows"
	window_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_root.add_child(window_layer)

	tooltip_layer = UITooltipLayer.new()
	tooltip_layer.name = "Tooltips"
	tooltip_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_root.add_child(tooltip_layer)

	# 控制台不跟 UI 缩放走：调大 UI 时它不会把自己撑出屏幕。
	debug_layer = Control.new()
	debug_layer.name = "DebugLayer"
	debug_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_layer)

	get_viewport().size_changed.connect(_update_content_size)

	inventory = InventoryWindow.new()
	inventory.name = "Inventory"
	window_layer.add_child(inventory)
	inventory.setup(tooltip_layer)
	inventory.opened.connect(_update_dim)
	inventory.closed.connect(_update_dim)

	warehouse = WarehouseWindow.new()
	warehouse.name = "Warehouse"
	window_layer.add_child(warehouse)
	warehouse.setup(tooltip_layer)
	warehouse.opened.connect(_update_dim)
	warehouse.closed.connect(_update_dim)

	if not _player_actor.is_empty():
		inventory.set_player_actor(_player_actor, _assets)
		warehouse.set_player_actor(_player_actor, _assets)

	center_window(inventory)
	center_window(warehouse)

	if open_inventory_on_start:
		inventory.open_window(true)
	_update_dim()
	_update_content_size()


# ---------------------------------------------------------------------------
# 调试控制台
# ---------------------------------------------------------------------------

func attach_debug(hud: Sf85Hud, game_room: Node) -> void:
	if debug_console == null:
		debug_console = UIDebugConsole.new()
		debug_console.name = "DebugConsole"
		debug_layer.add_child(debug_console)
		center_window(debug_console)
	debug_console.bind_context(self, hud, game_room)


## 键盘设置窗口：动作表来自 DNF 客户端（DnfKeys），改键立即生效并写 user://
func open_keybinds() -> void:
	var pad_tab := OS.get_environment("SF85_UI_KEYBINDS_PAD") == "1"
	if keybind_window == null:
		keybind_window = KeybindWindow.new()
		keybind_window.name = "Keybinds"
		window_layer.add_child(keybind_window)
		keybind_window.setup(tooltip_layer)
		keybind_window.opened.connect(_update_dim)
		keybind_window.closed.connect(_update_dim)
		keybind_window.keys_changed.connect(_on_keys_changed_ui)
	center_window(keybind_window)
	keybind_window.open_window()
	if pad_tab and keybind_window.has_method("select_tab"):
		keybind_window.select_tab(4)
	_update_dim()


func _on_keys_changed_ui() -> void:
	set_status_all("键位已更新")


## 取 InputMap 动作当前绑定的物理键（给 _unhandled_input 比对用）
func _action_physical_key(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			return k.physical_keycode if k.physical_keycode != 0 else k.keycode
	return 0


func open_console() -> void:
	if debug_console == null:
		return
	center_window(debug_console)
	debug_console.open_window(true)


func toggle_debug_console() -> void:
	if debug_console == null:
		return
	if debug_console.is_open():
		debug_console.close_window(true)
	else:
		open_console()


func is_console_open() -> bool:
	return debug_console != null and debug_console.is_open()


# ---------------------------------------------------------------------------
# 主题
# ---------------------------------------------------------------------------

func apply_theme(data: UITheme) -> void:
	if data == null:
		return
	theme_data = data
	if data.preset_key != "":
		theme_preset = data.preset_key
	theme = data.build_theme()
	queue_redraw()


func apply_theme_preset(preset: String) -> void:
	var data := UIThemePresets.get_theme(preset)
	theme_preset = preset
	apply_theme(data)


func cycle_theme() -> void:
	var next := UIThemePresets.cycle(theme_preset)
	apply_theme_preset(next)
	set_status_all("配色：" + theme_data.preset_name)


func set_status_all(text: String) -> void:
	if inventory != null:
		inventory.set_status(text)
	if warehouse != null:
		warehouse.set_status(text)


# ---------------------------------------------------------------------------
# 资产
# ---------------------------------------------------------------------------

func bind_assets(assets: Sf85Assets, player_actor := {}) -> void:
	_assets = assets
	_store = assets.store if assets != null else null
	_player_actor = player_actor
	if inventory != null:
		inventory.set_player_actor(_player_actor, _assets)
	if warehouse != null:
		warehouse.set_player_actor(_player_actor, _assets)


func item_texture(item: ItemDef) -> Texture2D:
	if item == null or _store == null:
		return null
	return _store.texture(item.icon_img, item.icon_frame)


# ---------------------------------------------------------------------------
# 窗口
# ---------------------------------------------------------------------------

func open_inventory() -> void:
	if inventory != null:
		center_window(inventory)
		inventory.open_window()
	_update_dim()


func open_warehouse() -> void:
	if warehouse != null:
		center_window(warehouse)
		warehouse.open_window()
	_update_dim()


func toggle_inventory() -> void:
	if inventory == null:
		return
	if inventory.is_open():
		inventory.close_window()
	else:
		center_window(inventory)
		inventory.open_window()


func toggle_warehouse() -> void:
	if warehouse == null:
		return
	if warehouse.is_open():
		warehouse.close_window()
	else:
		center_window(warehouse)
		warehouse.open_window()


func close_all() -> void:
	if keybind_window != null and keybind_window.is_open():
		keybind_window.close_window()
	if inventory != null:
		inventory.close_window()
	if warehouse != null:
		warehouse.close_window()


func center_window(w: Control) -> void:
	if w == null:
		return
	var s := w.custom_minimum_size
	if s == Vector2.ZERO:
		s = w.size
	w.size = s
	var area := size
	if content_root != null:
		area = content_root.size
	w.position = ((area - s) * 0.5).floor()


## 调整游戏窗口尺寸。项目使用 stretch=disabled，窗口尺寸就是逻辑视口尺寸；
## 这里同时走 DisplayServer 和 Window.size，兼容独立运行/调试运行。
func set_window_size(target: Vector2i) -> void:
	target = Vector2i(maxi(1280, target.x), maxi(900, target.y))
	var win := get_window()
	if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		win.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_size(target)
	win.size = target
	win.move_to_center()
	_update_content_size()


## UI 整体缩放：只影响窗口/浮框，不影响世界相机。
func set_ui_scale(v: float) -> void:
	ui_scale = clampf(v, 0.55, 1.5)
	_update_content_size()


func _update_content_size() -> void:
	if content_root == null:
		return
	content_root.scale = Vector2(ui_scale, ui_scale)
	content_root.size = get_viewport_rect().size / ui_scale
	for w in [inventory, warehouse]:
		if w != null and w.is_open():
			center_window(w)


func _update_dim() -> void:
	if dim == null:
		return
	var any := false
	if inventory != null and inventory.is_open():
		any = true
	if warehouse != null and warehouse.is_open():
		any = true
	dim.visible = dim_background and any


func _unhandled_input(event: InputEvent) -> void:
	if not enable_shortcuts:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		# DNF 动作表的键位（随时可改）：I12 装备栏=背包，I11 技能栏，I49 关闭全部菜单
		if code != 0 and code == DnfKeys.keycode_of("I12"):
			toggle_inventory()
			get_viewport().set_input_as_handled()
			return
		if code != 0 and code == _action_physical_key("sf85_warehouse"):
			toggle_warehouse()
			get_viewport().set_input_as_handled()
			return
		if code != 0 and code == DnfKeys.keycode_of("I61"):
			open_keybinds()
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_F1:
				toggle_debug_console()
				get_viewport().set_input_as_handled()
			KEY_F3:
				cycle_theme()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if keybind_window != null and keybind_window.is_open():
					keybind_window.close_window()
					get_viewport().set_input_as_handled()
				elif is_console_open():
					debug_console.close_window(true)
					get_viewport().set_input_as_handled()
				elif warehouse != null and warehouse.is_open():
					warehouse.close_window()
					get_viewport().set_input_as_handled()
				elif inventory != null and inventory.is_open():
					inventory.close_window()
					get_viewport().set_input_as_handled()
