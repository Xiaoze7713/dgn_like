## 浮框层：负责跟随鼠标、贴边翻转、显示/隐藏。
class_name UITooltipLayer
extends Control

@export var offset := Vector2(20, 18)
@export var margin := 8.0

var tooltip: UITooltip
var _item: ItemDef = null
var _anchor := Rect2()
var _pinned: Variant = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip = UITooltip.new()
	tooltip.name = "Tooltip"
	add_child(tooltip)
	tooltip.visible = false
	set_process(false)


func show_item(it: ItemDef, source_rect := Rect2()) -> void:
	if it == null:
		hide_tooltip()
		return
	if _item != it:
		_item = it
		tooltip.set_item(it)
	_anchor = source_rect
	tooltip.visible = true
	set_process(true)
	_place()


## 固定位置显示（调试/截图/手柄选中时用），位置是相对本层的坐标。
func show_item_at(it: ItemDef, pos: Vector2) -> void:
	_pinned = pos
	show_item(it)
	_place()


func hide_tooltip() -> void:
	_item = null
	_pinned = null
	if tooltip != null:
		tooltip.visible = false
	set_process(false)


func is_showing() -> bool:
	return tooltip != null and tooltip.visible


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	if tooltip == null or not tooltip.visible:
		return
	var m: Vector2 = _pinned if _pinned != null else get_local_mouse_position()
	var vp := size
	var tw := tooltip.size.x
	var th := tooltip.size.y
	var pos := m + offset

	if pos.x + tw > vp.x - margin and m.x - offset.x - tw > margin:
		pos.x = m.x - offset.x - tw
	if pos.y + th > vp.y - margin:
		pos.y = vp.y - th - margin

	pos.x = clampf(pos.x, margin, maxf(margin, vp.x - tw - margin))
	pos.y = clampf(pos.y, margin, maxf(margin, vp.y - th - margin))
	tooltip.position = pos
