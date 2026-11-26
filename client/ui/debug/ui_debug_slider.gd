## 控制台用的细条滑杆：不依赖 Range，绘制/交互都在这里，配色跟 UITheme 走。
class_name UIDebugSlider
extends Control

signal value_changed(value: float)

@export var min_value := 0.0
@export var max_value := 1.0
@export var step := 0.01

var value := 0.0

var _dragging := false
var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(120, 20)
	theme_changed.connect(queue_redraw)
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())


func set_value(v: float) -> void:
	value = clampf(v, min_value, max_value)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_set_from_x(event.position.x)
			accept_event()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x(event.position.x)
		accept_event()


func _set_from_x(x: float) -> void:
	var pad := 9.0
	var t := clampf((x - pad) / maxf(1.0, size.x - pad * 2.0), 0.0, 1.0)
	var raw := lerpf(min_value, max_value, t)
	if step > 0.0:
		raw = snappedf(raw, step)
	var v := clampf(raw, min_value, max_value)
	if is_equal_approx(v, value):
		return
	value = v
	queue_redraw()
	value_changed.emit(value)


func _draw() -> void:
	var data := UIKit.data(self)
	var accent := UIKit.col(self, "accent", Color(0.35, 0.8, 1.0))
	var pad := 9.0
	var cy := size.y * 0.5
	var x0 := pad
	var x1 := size.x - pad
	draw_line(Vector2(x0, cy), Vector2(x1, cy), Color(0.05, 0.08, 0.12, 0.9), 5.0)
	var t := clampf((value - min_value) / maxf(0.0001, max_value - min_value), 0.0, 1.0)
	var x := lerpf(x0, x1, t)
	if x > x0:
		draw_line(Vector2(x0, cy), Vector2(x, cy), accent, 5.0)
	draw_circle(Vector2(x, cy), 6.5 if _hover or _dragging else 5.5,
		Color(1, 1, 1, 0.95) if _hover or _dragging else accent)
	draw_circle(Vector2(x, cy), 2.6, accent.darkened(0.25))
