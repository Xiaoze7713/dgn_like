## 页签栏：物品栏/时装/宠物、装备/消耗品/材料……都用它。
class_name UITabBar
extends Control

signal tab_changed(index: int)

@export var tabs: PackedStringArray = []:
	set(v):
		tabs = v
		current = clampi(current, 0, maxi(0, tabs.size() - 1))
		_recalc()
		queue_redraw()

@export var current := 0:
	set(v):
		var n := clampi(v, 0, maxi(0, tabs.size() - 1))
		if current == n:
			current = n
			return
		current = n
		tab_changed.emit(current)
		queue_redraw()

@export var min_tab_width := 82
## 为 true 时每个页签均分整条宽度，而不是按文字宽度左对齐。
@export var equal_width := false
@export var active_fill := true

var _hover := -1
var _widths: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = 30
	resized.connect(_recalc)
	_recalc()


func _recalc() -> void:
	_widths.clear()
	if not is_inside_tree():
		return
	if tabs.is_empty():
		return
	if equal_width and size.x > 0.0:
		var w := size.x / float(tabs.size())
		for _i in tabs.size():
			_widths.append(w)
		return
	var f := UIKit.font(self, false)
	var fs := UIKit.fs(self, "fs_m", 14)
	for t in tabs:
		var w := maxf(min_tab_width, UIKit.text_width(f, t, fs) + 30.0)
		_widths.append(w)


func select(index: int) -> void:
	current = index


func set_tabs(list: Array, index := 0) -> void:
	tabs = PackedStringArray(list)
	current = clampi(index, 0, maxi(0, tabs.size() - 1))
	queue_redraw()


func _tab_rect(i: int) -> Rect2:
	var x := 0.0
	for j in i:
		var step: float = _widths[j] if j < _widths.size() else float(min_tab_width)
		x += step
	var w: float = _widths[i] if i < _widths.size() else float(min_tab_width)
	return Rect2(x, 0, w, size.y)


func _index_at(p: Vector2) -> int:
	for i in tabs.size():
		if _tab_rect(i).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _index_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var idx := _index_at(event.position)
		if idx >= 0:
			select(idx)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hover != -1:
			_hover = -1
			queue_redraw()
	elif what == NOTIFICATION_THEME_CHANGED:
		_recalc()
		queue_redraw()


func _draw() -> void:
	if tabs.is_empty():
		return
	if _widths.size() != tabs.size():
		_recalc()
	var d := UIKit.data(self)
	if d == null:
		return
	var f := UIKit.font(self, false)
	var fb := UIKit.font(self, true)
	var fs := UIKit.fs(self, "fs_m", 14)

	# 底部一条贯穿的细线，让页签"坐"在上面
	draw_line(Vector2(4, size.y - 1), Vector2(size.x - 4, size.y - 1),
			UIKit.a(d.frame_color, 0.35), 1.0, true)

	for i in tabs.size():
		var r := _tab_rect(i)
		var active := i == current
		var hovered := i == _hover and not active

		if active and active_fill:
			var sb := StyleBoxFlat.new()
			sb.bg_color = UIKit.a(d.accent, 0.10)
			sb.border_color = Color(0, 0, 0, 0)
			sb.border_width_bottom = 2
			sb.border_color = UIKit.a(d.accent, 0.95)
			sb.set_corner_radius_all(0)
			sb.corner_radius_top_left = 5
			sb.corner_radius_top_right = 5
			sb.anti_aliasing = true
			draw_style_box(sb, Rect2(r.position + Vector2(2, 3), Vector2(r.size.x - 4, r.size.y - 3)))
		elif hovered:
			UIKit.round_rect(self, Rect2(r.position + Vector2(2, 3), Vector2(r.size.x - 4, r.size.y - 4)),
					UIKit.a(Color.WHITE, 0.045), 5)

		# 页签之间的分隔
		if i > 0:
			draw_line(Vector2(r.position.x, 9), Vector2(r.position.x, r.size.y - 9),
					UIKit.a(d.frame_color, 0.18), 1.0, true)

		var col := d.text_primary if active else (d.text_secondary if hovered else d.text_muted)
		UIKit.text(self, tabs[i], r, fb if active else f, fs, col, UIKit.ALIGN_CENTER)

		# 激活页签下的小菱形
		if active:
			UIKit.diamond(self, Vector2(r.get_center().x, r.size.y - 1.5), 2.6,
					UIKit.a(d.gold, 0.95))
