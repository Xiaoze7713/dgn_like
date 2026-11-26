## 底部货币/点数条。
class_name UICurrencyBar
extends Control

## [{label:"金币", value:1246132, color:Color, glyph:"G"}]
@export var entries: Array = []
## 每行几项；物品栏在窄窗口里用 2 行 × 2 列，避免长数字挤在一起。
@export var columns := 2
@export var row_height := 28

var _font: Font
var _font_bold: Font


func _ready() -> void:
	custom_minimum_size.y = row_height * _row_count()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_entries(list: Array) -> void:
	entries = list
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	if entries.is_empty():
		return
	var d := UIKit.data(self)
	if d == null:
		return
	_font = UIKit.font(self, false)
	_font_bold = UIKit.font(self, true)
	var fs := UIKit.fs(self, "fs_s", 12)
	var w := size.x

	# 底：一条很淡的横向托底
	draw_rect(Rect2(0, 0, w, size.y), Color(0, 0, 0, 0.18))
	draw_line(Vector2(0, 0), Vector2(w, 0), UIKit.a(d.frame_color, 0.25), 1.0, true)

	var items := entries
	var n := items.size()
	var cols := maxi(1, columns)
	var cell := w / float(cols)
	var rows := _row_count()
	var rh := size.y / float(rows)
	for i in n:
		var e: Dictionary = items[i]
		var row := i / cols
		var col_i := i % cols
		var cx := cell * col_i
		var cy := rh * row
		var col: Color = e.get("color", d.text_gold)
		var glyph := str(e.get("glyph", "•"))
		var label := str(e.get("label", ""))
		var value := UIKit.fmt_int(int(e.get("value", 0)))

		if col_i > 0:
			draw_line(Vector2(cx, cy + 6), Vector2(cx, cy + rh - 6),
					UIKit.a(d.frame_color, 0.18), 1.0, true)
		if row > 0:
			draw_line(Vector2(0, cy), Vector2(w, cy), UIKit.a(d.frame_color, 0.14), 1.0, true)

		# 小徽记
		var gc := Vector2(cx + 13, cy + rh * 0.5)
		UIKit.diamond(self, gc, 5.0, UIKit.a(col, 0.85))
		UIKit.diamond(self, gc, 2.8, UIKit.a(Color(0, 0, 0, 0.55), 1.0))
		UIKit.text(self, glyph, Rect2(gc.x - 6, gc.y - 7, 12, 14), _font_bold, 8,
				UIKit.a(col, 0.95), UIKit.ALIGN_CENTER)

		UIKit.text(self, label, Rect2(cx + 23, cy, cell * 0.48, rh), _font, fs - 1,
				d.text_muted, UIKit.ALIGN_LEFT)
		UIKit.text(self, value, Rect2(cx + cell * 0.48, cy, cell * 0.46, rh), _font_bold, fs,
				d.text_secondary, UIKit.ALIGN_RIGHT)


func _row_count() -> int:
	return int(ceil(float(maxi(1, entries.size())) / float(maxi(1, columns))))
