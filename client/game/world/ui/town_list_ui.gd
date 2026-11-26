class_name TownListUI
extends Control
## 城镇列表：按地区分组，点一行就传送。数据只读 LivePvfContent 的 index
## （只在进游戏时解析一次 town.lst，不会为了列名单去读地图），所以打开是瞬时的。
##
## 开关由 WorldDirector 绑定 M；打开时玩家移动暂停，关闭后恢复。

signal town_selected(town_key: String)
signal opened
signal closed

const PANEL_SIZE := Vector2(560, 620)
const ROW_H := 38

var content: PackContent
var _panel: PanelContainer
var _list: VBoxContainer
var _sub: Label
var _current_key := ""
var _font: SystemFont
var _font_bold: SystemFont


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = WorldFont.make(400)
	_font_bold = WorldFont.make(700)
	_build()


func setup(p_content: PackContent) -> void:
	content = p_content


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.11, 0.97)
	sb.border_color = Color(0.35, 0.55, 0.85, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "城镇列表"
	title.add_theme_font_override("font", _font_bold)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	box.add_child(title)

	_sub = Label.new()
	_sub.text = "点一行传送 · M / Esc 关闭"
	_sub.add_theme_font_override("font", _font)
	_sub.add_theme_font_size_override("font_size", 14)
	_sub.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	box.add_child(_sub)

	var sep := HSeparator.new()
	box.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)


func is_open() -> bool:
	return visible


func open_for(current_key: String) -> void:
	_current_key = current_key
	_rebuild()
	if _sub != null:
		var shown := current_key
		for t in content.load_index().get("towns", []) if content != null else []:
			var tk := str(t.get("key", ""))
			if tk == current_key or tk.get_file() == current_key.get_file() \
					or tk.get_file().trim_prefix("town_") == current_key.get_file().trim_prefix("town_"):
				var names: Array = t.get("name_text", [])
				if not names.is_empty():
					shown = str(names[0])
				break
		_sub.text = "当前：%s · 点一行传送 · M / Esc 关闭" % shown
	visible = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle(current_key: String) -> void:
	if visible:
		close()
	else:
		open_for(current_key)


func _rebuild() -> void:
	if content == null:
		return
	for c in _list.get_children():
		c.queue_free()

	var groups: Dictionary = {}
	var order: Array[String] = []
	for t in content.load_index().get("towns", []):
		var d: Dictionary = t
		var group := str(d.get("region_name", ""))
		if group == "":
			group = "其他地区"
		if not groups.has(group):
			groups[group] = []
			order.append(group)
		groups[group].append(d)

	for group_name in order:
		var head := Label.new()
		head.text = "— %s —" % group_name
		head.add_theme_font_override("font", _font)
		head.add_theme_font_size_override("font_size", 15)
		head.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
		head.custom_minimum_size = Vector2(0, 30)
		_list.add_child(head)
		var rows: Array = groups[group_name]
		rows.sort_custom(func(a, b): return int(a.get("town_id", -1)) < int(b.get("town_id", -1)))
		for raw in rows:
			var t: Dictionary = raw
			var key := str(t.get("key", ""))
			var names: Array = t.get("name_text", [])
			var label := str(names[0]) if not names.is_empty() else key
			var current := key == _current_key or key.get_file().get_basename() == _current_key
			var ac: Variant = t.get("areas", 0)
			var area_n: int = ac.size() if ac is Array else int(ac)
			var b := Button.new()
			b.text = "%s %s    %d 个区域" % [
					"●" if current else "○", label, area_n]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, ROW_H)
			b.add_theme_font_override("font", _font_bold if current else _font)
			b.add_theme_font_size_override("font_size", 17)
			if current:
				b.modulate = Color(1.0, 0.92, 0.55)
			b.tooltip_text = key
			b.pressed.connect(_on_row.bind(key))
			_list.add_child(b)


func _on_row(key: String) -> void:
	if key == "":
		return
	town_selected.emit(key)
	close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE or k == KEY_M:
			close()
			get_viewport().set_input_as_handled()
