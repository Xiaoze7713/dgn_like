## 控制台用的“点一下切下一项”选择器。
class_name UIDebugOption
extends Control

signal option_changed(index: int)

var options := PackedStringArray()
var current := 0

var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(130, 22)
	theme_changed.connect(queue_redraw)
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())


func set_options(list: PackedStringArray, index := 0) -> void:
	options = list
	current = clampi(index, 0, maxi(0, options.size() - 1))
	queue_redraw()


func set_index(index: int) -> void:
	current = clampi(index, 0, maxi(0, options.size() - 1))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if options.is_empty():
			return
		current = (current + 1) % options.size()
		queue_redraw()
		option_changed.emit(current)
		accept_event()


func _draw() -> void:
	var accent := UIKit.col(self, "accent", Color(0.35, 0.8, 1.0))
	var r := Rect2(0, 0, size.x, size.y)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.14, 0.95)
	sb.border_color = accent if _hover else UIKit.col(self, "slot_border", Color(0.3, 0.4, 0.5))
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	draw_style_box(sb, r)
	var text := options[current] if current >= 0 and current < options.size() else "—"
	draw_string(UIKit.font(self), Vector2(8, size.y * 0.5 + 4), text,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 26, 11,
		UIKit.col(self, "text_primary", Color(0.9, 0.95, 1.0)))
	draw_string(UIKit.font(self), Vector2(size.x - 18, size.y * 0.5 + 4), ">",
		HORIZONTAL_ALIGNMENT_CENTER, 12, 11, accent)
