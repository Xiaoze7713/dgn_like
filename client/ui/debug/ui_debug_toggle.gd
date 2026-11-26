## 控制台用的小开关。
class_name UIDebugToggle
extends Control

signal toggled(on: bool)

var on := true

var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(42, 20)
	theme_changed.connect(queue_redraw)
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())


func set_on(v: bool) -> void:
	on = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		on = not on
		queue_redraw()
		toggled.emit(on)
		accept_event()


func _draw() -> void:
	var accent := UIKit.col(self, "accent", Color(0.35, 0.8, 1.0))
	var bg := Color(0.05, 0.09, 0.14, 0.95) if not on else Color(accent.r, accent.g, accent.b, 0.32)
	var r := Rect2(0, 2, size.x, size.y - 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = accent if _hover or on else UIKit.col(self, "slot_border", Color(0.3, 0.4, 0.5))
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int((size.y - 4) * 0.5))
	draw_style_box(sb, r)
	var kx := size.x - 12.0 if on else 12.0
	draw_circle(Vector2(kx, size.y * 0.5), 6.0, accent if on else Color(0.55, 0.62, 0.7))
