## 重量条：左「重量」、右「12.4 / 50.0 kg」、中间细进度条。
class_name UIWeightBar
extends Control

@export var label := "重量"
@export var weight := 0.0
@export var max_weight := 50.0
@export var show_numbers := true

var _display := 0.0
var _tween: Tween


func _ready() -> void:
	custom_minimum_size.y = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display = weight
	queue_redraw()


func set_values(now: float, cap: float, animate := true) -> void:
	weight = now
	max_weight = maxf(0.01, cap)
	if not animate or not is_inside_tree():
		_display = weight
		queue_redraw()
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float):
		_display = v
		queue_redraw()
	, _display, weight, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var d := UIKit.data(self)
	if d == null:
		return
	var f := UIKit.font(self, false)
	var fb := UIKit.font(self, true)
	var fs := UIKit.fs(self, "fs_xs", 11)
	var w := size.x
	var cy := size.y * 0.5

	UIKit.text(self, label, Rect2(0, 0, 50, size.y), f, fs, d.text_muted)
	if show_numbers:
		var txt := "%.1f / %.1f kg" % [_display, max_weight]
		UIKit.text(self, txt, Rect2(w - 130, 0, 130, size.y), f, fs, d.text_secondary,
				UIKit.ALIGN_RIGHT)

	var bx := 44.0
	var bw := maxf(10.0, w - 44.0 - (138.0 if show_numbers else 0.0))
	var bh := 6.0
	var track := Rect2(bx, cy - bh * 0.5, bw, bh)
	UIKit.round_rect(self, track, Color(0.02, 0.04, 0.07, 0.75), 3,
			UIKit.a(d.frame_color, 0.35), 1)

	var ratio := clampf(_display / max_weight, 0.0, 1.0)
	if ratio > 0.001:
		var fill_w := maxf(2.0, (bw - 2) * ratio)
		var col := d.accent
		if ratio > 0.85:
			col = d.text_danger
		elif ratio > 0.65:
			col = d.gold
		var fr := Rect2(bx + 1, cy - bh * 0.5 + 1, fill_w, bh - 2)
		UIKit.round_rect(self, fr, col, 2)
		# 高光
		draw_rect(Rect2(fr.position + Vector2(1, 0), Vector2(maxf(0, fr.size.x - 2), 1)),
				UIKit.a(Color.WHITE, 0.35))
		# 当前值的细刻度
		if fill_w < bw - 3:
			draw_rect(Rect2(Vector2(bx + 1 + fill_w, cy - bh * 0.5), Vector2(1, bh)),
					UIKit.a(Color.WHITE, 0.55))


