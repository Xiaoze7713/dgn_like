## 物品网格：固定列数的格子阵列，可滚动；空格也画出来。
class_name UIItemGrid
extends ScrollContainer

signal slot_hovered(slot: UISlot)
signal slot_unhovered(slot: UISlot)
signal slot_activated(slot: UISlot)
signal slot_right_clicked(slot: UISlot)
signal slot_lock_changed(slot: UISlot)

@export var columns := 12
@export var rows := 4
## 不足一页时是否补空格（物品栏/仓库要，纯列表不要）。
@export var fill_empty := true
## 非 0 时覆盖主题的格子尺寸（物品栏可单独缩小）。
@export var slot_size := 0
## >=0 时覆盖主题的格子间距。
@export var gap_override := -1

var grid: GridContainer
var slots: Array[UISlot] = []

var _items: Array[ItemDef] = []
var _entries: Array = []
var _locks := {}
var _filter := ""
var _slot_count := 48


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE

	grid = GridContainer.new()
	grid.name = "Grid"
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(grid)

	theme_changed.connect(_apply_theme)
	_apply_theme()
	_slot_count = columns * rows
	rebuild()


func _apply_theme() -> void:
	if grid == null:
		return
	var gap := gap_override if gap_override >= 0 else UIKit.k(self, "slot_gap", 6)
	grid.add_theme_constant_override("h_separation", gap)
	grid.add_theme_constant_override("v_separation", gap)
	var slot := slot_size if slot_size > 0 else UIKit.k(self, "slot", 46)
	grid.custom_minimum_size.x = columns * slot + maxi(0, columns - 1) * gap


func set_columns(n: int) -> void:
	columns = maxi(1, n)
	if grid != null:
		grid.columns = columns
	_apply_theme()
	rebuild()


func set_items(items: Array, slot_count := -1) -> void:
	_entries.clear()
	_items.clear()
	for it in items:
		if it is ItemDef:
			_items.append(it)
	if slot_count >= 0:
		_slot_count = slot_count
	rebuild()


func set_entries(entries: Array, slot_count := -1) -> void:
	_entries = entries.duplicate()
	if slot_count >= 0:
		_slot_count = slot_count
	rebuild()


func entries() -> Array:
	return _entries.duplicate()


func clear_locks() -> void:
	_locks.clear()


func locked_indices() -> Array:
	var out := []
	for k in _locks.keys():
		if bool(_locks[k]):
			out.append(k)
	return out


func set_filter(category: String) -> void:
	_filter = category
	rebuild()


func get_filter() -> String:
	return _filter


func filtered_items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for it in _items:
		if _filter == "" or it.category == _filter:
			out.append(it)
	return out


func refresh() -> void:
	rebuild()


func get_slot(index: int) -> UISlot:
	return slots[index] if index >= 0 and index < slots.size() else null


func rebuild() -> void:
	if grid == null:
		return
	for s in slots:
		if is_instance_valid(s):
			grid.remove_child(s)
			s.queue_free()
	slots.clear()

	var items: Array = _entries if not _entries.is_empty() else filtered_items()
	var total := _slot_count if fill_empty else items.size()
	total = maxi(total, items.size())
	# 超过一页就按整行扩展
	if total > _slot_count:
		total = int(ceil(float(total) / float(columns))) * columns

	for i in total:
		var slot := UISlot.new()
		slot.name = "Slot%d" % i
		if slot_size > 0:
			slot.add_theme_constant_override("slot", slot_size)
		grid.add_child(slot)
		if i < items.size():
			slot.item = items[i] if items[i] is ItemDef else null
		else:
			slot.empty_glyph = ""
		slot.locked = bool(_locks.get(i, false))
		slot.hover_started.connect(func(s: UISlot): slot_hovered.emit(s))
		slot.hover_ended.connect(func(s: UISlot): slot_unhovered.emit(s))
		slot.activated.connect(func(s: UISlot): slot_activated.emit(s))
		slot.right_clicked.connect(func(s: UISlot): slot_right_clicked.emit(s))
		var idx := i
		slot.lock_changed.connect(func(s: UISlot) -> void:
			_locks[idx] = s.locked
			slot_lock_changed.emit(s)
		)
		slots.append(slot)

	# 让 ScrollContainer 重新计算内容高度
	grid.queue_sort()
