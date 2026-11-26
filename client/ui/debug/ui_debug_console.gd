## 可扩展的 UI 调试控制台。
##
## 左列是参数名，右列是控件；后续要加“物品栏尺寸 / 槽位大小 / 动画速度”
## 之类的开关，只要在 `_build()` 里追加一行 `_slider(...)` / `_toggle(...)`
## 即可。所有改动都直接落到 UIRoot / HUD / Room 上，不需要重启。
class_name UIDebugConsole
extends UIWindow

const PRESET_KEYS := ["abyss", "ember", "jade", "violet"]
const PRESET_NAMES := ["深渊蓝", "余烬", "翡翠", "紫罗兰"]
const WINDOW_SIZES := ["1280 x 900", "1600 x 900", "1600 x 1000", "1920 x 1080"]
const WINDOW_VALUES := [Vector2i(1280, 900), Vector2i(1600, 900), Vector2i(1600, 1000), Vector2i(1920, 1080)]

var ui_root: UIRoot = null
var hud: Sf85Hud = null
var room: Node = null

var _box: VBoxContainer
var _syncing := false


func _ready() -> void:
	window_title = "UI 调试控制台"
	closable = true
	draggable = true
	super._ready()
	custom_minimum_size = Vector2(438, 640)
	size = custom_minimum_size
	set_status("F1 关闭 · 拖动标题栏")
	_build()


func bind_context(root: UIRoot, game_hud: Sf85Hud, game_room: Node) -> void:
	ui_root = root
	hud = game_hud
	room = game_room
	if is_inside_tree():
		_build()


func _build() -> void:
	if content == null:
		return
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.clip_contents = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	_box = VBoxContainer.new()
	_box.name = "Rows"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_box)
	var sb := scroll.get_v_scroll_bar()
	sb.custom_minimum_size.x = 8
	sb.modulate = Color(1, 1, 1, 0.9)

	if ui_root == null:
		_note("UI 根节点未绑定；只显示说明。")
		_button("关闭", close_window)
		return

	_section("主题")
	var preset_idx := maxi(0, PRESET_KEYS.find(ui_root.theme_preset))
	_option("预设", PRESET_NAMES, preset_idx, func(i: int) -> void:
		ui_root.apply_theme_preset(PRESET_KEYS[i])
		call_deferred("_rebuild")
	)
	_color("主色", ui_root.theme_data.accent, func(c: Color) -> void:
		ui_root.theme_data.accent = c
		_apply_theme()
	)
	_color("金色", ui_root.theme_data.gold, func(c: Color) -> void:
		ui_root.theme_data.gold = c
		_apply_theme()
	)
	_slider("玻璃不透明度", 0.0, 1.0, 0.01, ui_root.theme_data.glass_alpha, func(v: float) -> void:
		ui_root.theme_data.glass_alpha = v
		_apply_theme()
	)
	_slider("磨砂半径", 0.0, 16.0, 0.1, ui_root.theme_data.glass_blur, func(v: float) -> void:
		ui_root.theme_data.glass_blur = v
		_apply_theme()
	)
	_slider("噪点", 0.0, 0.1, 0.001, ui_root.theme_data.glass_noise, func(v: float) -> void:
		ui_root.theme_data.glass_noise = v
		_apply_theme()
	)
	_slider("圆角", 0.0, 24.0, 1.0, ui_root.theme_data.corner_radius, func(v: float) -> void:
		ui_root.theme_data.corner_radius = int(v)
		_apply_theme()
	)
	_slider("字号缩放", 0.85, 1.25, 0.01, ui_root.theme_data.font_scale, func(v: float) -> void:
		ui_root.theme_data.font_scale = v
		_apply_theme()
	)

	_section("界面 / 分辨率")
	_slider("UI 缩放", 0.7, 1.4, 0.01, ui_root.ui_scale, func(v: float) -> void:
		ui_root.set_ui_scale(v)
	)
	_note("窗口放大只放大世界；UI 固定像素，用上面的 UI 缩放单独调。")
	var wsize := maxi(0, WINDOW_VALUES.find(get_window().size))
	_option("窗口尺寸", WINDOW_SIZES, wsize, func(i: int) -> void:
		ui_root.set_window_size(WINDOW_VALUES[i])
	)
	_button("全屏 / 窗口", func() -> void:
		if get_window().mode == Window.MODE_FULLSCREEN:
			get_window().mode = Window.MODE_WINDOWED
		else:
			get_window().mode = Window.MODE_FULLSCREEN
	)
	if room != null and room.has_method("set_zoom_scale"):
		_slider("世界缩放", 0.6, 1.8, 0.01, float(room.get("zoom_scale")), func(v: float) -> void:
			room.call("set_zoom_scale", v)
		)

	if hud != null:
		_section("HUD / 伤害数字")
		_slider("HUD 缩放", 0.75, 1.6, 0.05, hud.hud_scale, func(v: float) -> void:
			hud.set_hud_scale(v)
		)
		_toggle("显示 HUD", hud.show_hud, func(on: bool) -> void:
			hud.show_hud = on
			hud.queue_redraw()
		)
		_toggle("显示伤害数字", hud.show_damage_numbers, func(on: bool) -> void:
			hud.show_damage_numbers = on
		)
		_slider("数字字号", 14.0, 44.0, 1.0, float(hud.damage_font_size), func(v: float) -> void:
			hud.damage_font_size = int(v)
		)
		_slider("上浮高度", 20.0, 120.0, 1.0, hud.damage_float_height, func(v: float) -> void:
			hud.damage_float_height = v
		)
		_slider("持续时间", 0.4, 1.8, 0.05, hud.damage_duration, func(v: float) -> void:
			hud.damage_duration = v
		)
		_button("测试伤害数字", _test_damage)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 34
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)
	_make_button(footer, "重置全部", _reset, false)
	_make_button(footer, "关闭控制台", close_window, true)


func _apply_theme() -> void:
	if ui_root != null:
		ui_root.apply_theme(ui_root.theme_data)


func _test_damage() -> void:
	if hud == null or room == null:
		return
	var p = room.get("player")
	if p == null:
		return
	var pos: Vector2 = p.global_position + Vector2(0, -90)
	hud.spawn_damage(pos, 1234.0, "crit")
	hud.spawn_damage(pos + Vector2(28, 0), 88.0, "hit")


func _reset() -> void:
	if ui_root == null:
		return
	ui_root.apply_theme_preset("abyss")
	ui_root.set_ui_scale(0.9)
	if hud != null:
		hud.show_hud = true
		hud.set_hud_scale(1.0)
		hud.show_damage_numbers = true
		hud.damage_font_size = 24
		hud.damage_float_height = 54.0
		hud.damage_duration = 0.9
		hud.queue_redraw()
	if room != null and room.has_method("set_zoom_scale"):
		room.call("set_zoom_scale", 1.0)
	_rebuild()


func _rebuild() -> void:
	_build()


# ---------------------------------------------------------------------------
# 行构建
# ---------------------------------------------------------------------------

func _section(text: String) -> void:
	var l := Label.new()
	l.text = "  " + text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_constant_override("outline_size", 0)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_box.add_child(gap)
	_box.add_child(l)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 10)
	l.modulate = Color(1, 1, 1, 0.65)
	_box.add_child(l)


func _row(label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(104, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("font_size", 11)
	row.add_child(l)
	_box.add_child(row)
	return row


func _slider(label: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> void:
	var row := _row(label)
	var s := UIDebugSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.set_value(value)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new()
	v.custom_minimum_size = Vector2(42, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 10)
	v.text = _fmt(value, step)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(nv: float) -> void:
		v.text = _fmt(nv, step)
		if not _syncing:
			cb.call(nv)
	)
	row.add_child(s)
	row.add_child(v)
	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(12, 0)
	row.add_child(right_pad)


func _toggle(label: String, value: bool, cb: Callable) -> void:
	var row := _row(label)
	var t := UIDebugToggle.new()
	t.set_on(value)
	t.size_flags_horizontal = Control.SIZE_SHRINK_END
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			cb.call(on)
	)
	row.add_child(t)


func _option(label: String, options: Array, index: int, cb: Callable) -> void:
	var row := _row(label)
	var o := UIDebugOption.new()
	o.set_options(PackedStringArray(options), index)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	o.option_changed.connect(func(i: int) -> void:
		if not _syncing:
			cb.call(i)
	)
	row.add_child(o)


func _color(label: String, color: Color, cb: Callable) -> void:
	var row := _row(label)
	var c := ColorPickerButton.new()
	c.color = color
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(0, 24)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_theme_font_size_override("font_size", 10)
	c.color_changed.connect(func(nc: Color) -> void:
		if not _syncing:
			cb.call(nc)
	)
	row.add_child(c)


func _button(label: String, cb: Callable) -> void:
	_make_button(_box, label, cb, label == "关闭控制台")


## 给自动化/调试脚本用：按 WINDOW_VALUES 下标切窗口尺寸。
func apply_window_size(index: int) -> void:
	if index >= 0 and index < WINDOW_VALUES.size():
		ui_root.set_window_size(WINDOW_VALUES[index])


func _make_button(parent: Control, label: String, cb: Callable, accent: bool) -> void:
	var b := UIButton.new()
	b.text = label
	b.variant = "accent" if accent else "normal"
	b.custom_minimum_size = Vector2(0, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % roundi(v)
	if step >= 0.1:
		return "%.1f" % v
	if step >= 0.01:
		return "%.2f" % v
	return "%.3f" % v
