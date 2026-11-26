## 背包侧栏：分类计数、容量、当前选中物品。
class_name UIBagSummary
extends Control

const CATS := [
	["equipment", "装备"],
	["consumable", "消耗品"],
	["material", "材料"],
	["profession", "副职业"],
	["quest", "任务"],
]

var _counts := {}
var _used := 0
var _capacity := 48
var _selected: ItemDef = null


func _ready() -> void:
	custom_minimum_size = Vector2(156, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_items(items: Array, capacity := 48) -> void:
	_counts.clear()
	for c in CATS:
		_counts[c[0]] = 0
	_used = 0
	for it in items:
		if it is ItemDef:
			_used += 1
			if _counts.has(it.category):
				_counts[it.category] = int(_counts[it.category]) + 1
	_capacity = capacity
	queue_redraw()


func set_selected(it: ItemDef) -> void:
	_selected = it
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var d := UIKit.data(self)
	if d == null:
		return
	var w := size.x
	var h := size.y
	UIKit.round_rect(self, Rect2(0, 0, w, h), UIKit.a(d.slot_bg, 0.55), 6,
			UIKit.a(d.frame_color, 0.32), 1)

	var x := 12.0
	var y := 10.0
	var fb := UIKit.font(self, true)
	var f := UIKit.font(self, false)

	UIKit.diamond(self, Vector2(x + 3, y + 8), 3.0, UIKit.a(d.accent, 0.9))
	UIKit.text(self, "背包概览", Rect2(x + 12, y, w - 24, 18), fb, 13, d.text_primary)
	y += 28

	var palette := [d.accent, d.gold, d.text_success, d.accent_soft, d.text_muted]
	for i in CATS.size():
		var key: String = CATS[i][0]
		var label: String = CATS[i][1]
		var col: Color = palette[i]
		var count := int(_counts.get(key, 0))
		draw_circle(Vector2(x + 5, y + 9), 2.4, UIKit.a(col, 0.8))
		UIKit.text(self, label, Rect2(x + 14, y, w - 60, 18), f, 12, d.text_secondary)
		UIKit.text(self, str(count), Rect2(w - 44, y, 32, 18), fb, 12,
				d.text_primary if count > 0 else d.text_muted, UIKit.ALIGN_RIGHT)
		y += 21

	y += 4
	draw_line(Vector2(x, y), Vector2(w - 12, y), UIKit.a(d.frame_color, 0.3), 1.0, true)
	y += 9

	UIKit.text(self, "容量", Rect2(x, y, 60, 16), f, 11, d.text_muted)
	UIKit.text(self, "%d / %d" % [_used, _capacity], Rect2(w - 90, y, 78, 16), f, 11,
			d.text_secondary, UIKit.ALIGN_RIGHT)
	y += 18
	var ratio := clampf(float(_used) / float(maxi(1, _capacity)), 0.0, 1.0)
	UIKit.round_rect(self, Rect2(x, y, w - 24, 4), Color(0.02, 0.04, 0.07, 0.8), 2)
	if ratio > 0:
		UIKit.round_rect(self, Rect2(x, y, (w - 24) * ratio, 4),
				d.accent.lerp(d.gold, ratio), 2)
	y += 16

	# 侧栏高度有限时只展示计数和容量；选中详情交给浮框，避免文字被裁掉。
	if _selected != null and h >= y + 52.0:
		draw_line(Vector2(x, y), Vector2(w - 12, y), UIKit.a(d.frame_color, 0.3), 1.0, true)
		y += 9
		UIKit.text(self, "选中", Rect2(x, y, 40, 16), f, 11, d.text_muted)
		y += 18
		var rc := d.rarity_color(_selected.rarity)
		var item_name := _selected.item_name
		while item_name.length() > 1 and UIKit.text_width(fb, item_name, 12) > w - 28:
			item_name = item_name.substr(0, item_name.length() - 1)
		UIKit.text(self, item_name, Rect2(x, y, w - 24, 17), fb, 12, rc)
		y += 17
		UIKit.text(self, _selected.item_type, Rect2(x, y, w - 24, 15), f, 10,
				d.text_muted)
