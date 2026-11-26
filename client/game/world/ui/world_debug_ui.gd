extends Control
## 世界调试面板：地板块、落点/框/网格、图层临时提升。
## 由 world_director.gd 用 L 打开/关闭；本身不直接改场景，只发 action 信号。

signal action(name: String, arg: String)

const FONT_FAMILY := "Noto Sans CJK SC, Source Han Sans SC, Microsoft YaHei, WenQuanYi Zen Hei"

var _panel: PanelContainer
var _status: Label
var _buttons := {}
var _layer_buttons := {}
var _selected_layer := ""
var _movable_y_slider: HSlider
var _movable_y_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.position = Vector2(812, 14)
	_panel.custom_minimum_size = Vector2(326, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.045, 0.06, 0.94)
	sb.border_color = Color(0.35, 0.55, 0.7, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "世界调试  (L 关)"
	title.add_theme_font_override("font", _font(700))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	box.add_child(title)

	var help := Label.new()
	help.text = "G 地板块  [ 区域框  ] 落点  \\ 网格  只走area  -/= 移动区Y  U 隐藏UI"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_override("font", _font(400))
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	box.add_child(help)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	box.add_child(hb)
	_add_toggle(hb, "floor", "地板块 G")
	_add_toggle(hb, "boxes", "区域框 [")
	_add_toggle(hb, "place", "落点 ]")
	_add_toggle(hb, "grid", "网格 \\")
	_add_toggle(hb, "walk_area", "只走area")

	var bw := HBoxContainer.new()
	bw.add_theme_constant_override("separation", 5)
	box.add_child(bw)
	var bl := Label.new()
	bl.text = "移动范围 Y"
	bl.add_theme_font_override("font", _font(400))
	bl.add_theme_font_size_override("font_size", 11)
	bl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	bw.add_child(bl)
	_movable_y_slider = HSlider.new()
	_movable_y_slider.min_value = -240
	_movable_y_slider.max_value = 240
	_movable_y_slider.step = 16
	_movable_y_slider.value = 0
	_movable_y_slider.custom_minimum_size = Vector2(150, 16)
	_movable_y_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_movable_y_slider.value_changed.connect(func(v: float) -> void:
		if _movable_y_label != null:
			_movable_y_label.text = "%+d" % int(v))
	_movable_y_slider.drag_ended.connect(func(_changed: bool) -> void:
		action.emit("movable_y", str(int(_movable_y_slider.value))))
	bw.add_child(_movable_y_slider)
	_movable_y_label = Label.new()
	_movable_y_label.text = "0"
	_movable_y_label.add_theme_font_override("font", _font(400))
	_movable_y_label.add_theme_font_size_override("font_size", 11)
	_movable_y_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	bw.add_child(_movable_y_label)

	_status = Label.new()
	_status.text = "图层提升：关"
	_status.add_theme_font_override("font", _font(400))
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	box.add_child(_status)

	var sep := HSeparator.new()
	box.add_child(sep)
	var hint := Label.new()
	hint.text = "临时把某一层抬到角色下面（0 关，1-7 选）"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_override("font", _font(400))
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.72, 0.8, 0.86))
	box.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for i in LAYERS.size():
		var key: String = LAYERS[i]
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, LAYER_LABELS.get(key, key)]
		b.toggle_mode = true
		b.add_theme_font_override("font", _font(400))
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_pick_layer.bind(key))
		grid.add_child(b)
		_layer_buttons[key] = b


## 顺序与 z 表统一由 `LayerZ` 提供；这里只做显示名。
const LAYERS: PackedStringArray = LayerZ.NAMES
const LAYER_LABELS := {
	"distantback": "远背景", "middleback": "中背景", "closeback": "近背景",
	"bottom": "底部", "normal": "普通", "close": "贴近", "front": "前景",
}


func _add_toggle(parent: HBoxContainer, key: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.add_theme_font_override("font", _font(400))
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(func() -> void: action.emit(key, ""))
	parent.add_child(b)
	_buttons[key] = b


func _pick_layer(key: String) -> void:
	action.emit("layer", key)


func set_state(key: String, on: bool) -> void:
	if _buttons.has(key):
		(_buttons[key] as Button).set_pressed_no_signal(on)


func set_movable_y(value: float) -> void:
	if _movable_y_slider != null:
		_movable_y_slider.set_value_no_signal(round(value / 16.0) * 16.0)
	if _movable_y_label != null:
		_movable_y_label.text = "%+d" % int(round(value))


func set_layer(key: String) -> void:
	_selected_layer = key
	for k in _layer_buttons:
		var b := _layer_buttons[k] as Button
		b.set_pressed_no_signal(k == key)
		b.modulate = Color(0.55, 1.0, 0.65) if k == key else Color.WHITE
	if _status != null:
		_status.text = "图层提升：%s" % (LAYER_LABELS.get(key, key) if key != "" else "关")


func _font(weight: int) -> SystemFont:
	return WorldFont.make(weight)
