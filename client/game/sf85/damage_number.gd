## 世界坐标伤害数字：生成在命中点，向上漂浮并淡出。
##
## 挂在房间的 DamageLayer(Node2D) 下，因此会跟着相机/世界移动；
## `screen_scale` 用 1/相机 zoom 抵消缩放，让数字在高分辨率下也保持屏幕字号。
class_name Sf85DamageNumber
extends Node2D

var label: Label
var _font: Font
var _duration := 0.9
var _rise := 54.0
var _screen_scale := 1.0


func setup(text: String, color: Color, font: Font, font_size: int,
		rise: float, duration: float, screen_scale: float) -> void:
	_font = font
	_duration = maxf(0.2, duration)
	_rise = rise
	_screen_scale = maxf(0.2, screen_scale)
	z_index = 200
	scale = Vector2(_screen_scale, _screen_scale)

	label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(150, 44)
	label.size = Vector2(150, 44)
	label.position = Vector2(-75, -44)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)

	var start := position
	var drift := Vector2(randf_range(-9.0, 9.0), -_rise)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position", start + drift, _duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, _duration * 0.55) \
			.set_delay(_duration * 0.45)
	t.tween_property(self, "scale", Vector2(_screen_scale * 1.12, _screen_scale * 1.12), 0.10) \
			.from(Vector2(_screen_scale * 0.58, _screen_scale * 0.58)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.finished.connect(queue_free)
