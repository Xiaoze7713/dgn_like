## 泰拉石金库窗口。
##
## 仓库没有负重限制；顶部页签切换个人/账号金库，下方按物品类型过滤。
class_name WarehouseWindow
extends UIWindow

const FILTER_TABS := ItemDB.WAREHOUSE_FILTER_TABS
const FILTER_KEYS := ItemDB.WAREHOUSE_FILTER_KEYS

var tab_bar: UITabBar
var filter_tabs: UITabBar
var capacity_value: Label
var grid: UIItemGrid
var take_button: UIButton
var put_button: UIButton
var transfer_button: UIButton
var sort_button: UIButton

var _items: Array[ItemDef] = []
var _tab_index := 0
var _filter_index := 0


func _ready() -> void:
	window_title = "泰拉石金库"
	super._ready()
	custom_minimum_size = Vector2(760, 560)
	size = custom_minimum_size
	content.add_theme_constant_override("separation", 4)

	_items = ItemDB.warehouse_items()

	var head := HBoxContainer.new()
	head.custom_minimum_size.y = 30
	head.add_theme_constant_override("separation", 10)
	content.add_child(head)

	tab_bar = UITabBar.new()
	tab_bar.tabs = ItemDB.WAREHOUSE_TABS
	tab_bar.min_tab_width = 96
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.custom_minimum_size.y = 30
	tab_bar.tab_changed.connect(_on_tab)
	head.add_child(tab_bar)

	var cap_title := Label.new()
	cap_title.text = "栏位"
	cap_title.add_theme_font_size_override("font_size", 10)
	cap_title.add_theme_color_override("font_color", UIKit.data(self).text_muted)
	cap_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(cap_title)

	capacity_value = Label.new()
	capacity_value.text = "0 / 152 格"
	capacity_value.add_theme_font_size_override("font_size", 11)
	capacity_value.add_theme_color_override("font_color", UIKit.data(self).text_secondary)
	capacity_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	capacity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	capacity_value.custom_minimum_size.x = 92
	head.add_child(capacity_value)

	var filter_row := HBoxContainer.new()
	filter_row.custom_minimum_size.y = 30
	filter_row.add_theme_constant_override("separation", 8)
	content.add_child(filter_row)

	filter_tabs = UITabBar.new()
	filter_tabs.tabs = PackedStringArray(FILTER_TABS)
	filter_tabs.min_tab_width = 64
	filter_tabs.custom_minimum_size.y = 30
	filter_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_tabs.tab_changed.connect(_on_filter)
	filter_row.add_child(filter_tabs)

	grid = UIItemGrid.new()
	grid.columns = 14
	grid.rows = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.slot_hovered.connect(_on_slot_hover)
	grid.slot_unhovered.connect(func(_s: UISlot): _hide_tooltip())
	grid.slot_activated.connect(_on_slot_activate)
	grid.slot_right_clicked.connect(_on_slot_right_click)
	content.add_child(grid)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 30
	footer.add_theme_constant_override("separation", 8)
	content.add_child(footer)

	var note := Label.new()
	note.text = "仓库无重量限制"
	note.add_theme_font_size_override("font_size", 9)
	note.add_theme_color_override("font_color", UIKit.data(self).text_muted)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)

	transfer_button = _footer_button("转移物品")
	transfer_button.pressed.connect(func(): set_status("转移物品：请选择目标"))
	footer.add_child(transfer_button)

	put_button = _footer_button("放入")
	put_button.pressed.connect(func(): set_status("放入：请选择物品"))
	footer.add_child(put_button)

	take_button = _footer_button("取出")
	take_button.variant = "accent"
	take_button.pressed.connect(_on_take)
	footer.add_child(take_button)

	sort_button = _footer_button("整理")
	sort_button.pressed.connect(_on_sort)
	footer.add_child(sort_button)

	_refresh()


func _footer_button(text: String) -> UIButton:
	var b := UIButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(76, 26)
	b.add_theme_font_size_override("font_size", 11)
	return b


func _on_tab(index: int) -> void:
	_tab_index = index
	selected_item = null
	_refresh()


func _on_filter(index: int) -> void:
	_filter_index = index
	selected_item = null
	_refresh()


func _base_items() -> Array[ItemDef]:
	if _tab_index == 1:
		return _items.slice(0, maxi(0, _items.size() - 8))
	return _items


func _visible_items() -> Array[ItemDef]:
	var base := _base_items()
	var key: String = FILTER_KEYS[clampi(_filter_index, 0, FILTER_KEYS.size() - 1)]
	if key == "":
		return base
	var out: Array[ItemDef] = []
	for it in base:
		if it.category == key:
			out.append(it)
	return out


func _refresh() -> void:
	var shown := _visible_items()
	grid.set_items(shown, grid.columns * grid.rows)
	capacity_value.text = "%d / 152 格" % shown.size()


func _on_slot_hover(slot: UISlot) -> void:
	if slot.item != null and tooltip_layer != null:
		tooltip_layer.show_item(slot.item, slot.get_global_rect())


func _hide_tooltip() -> void:
	if tooltip_layer != null:
		tooltip_layer.hide_tooltip()


func _on_slot_activate(slot: UISlot) -> void:
	selected_item = slot.item
	item_selected.emit(slot.item)
	if slot.item != null:
		set_status("选中：" + slot.item.item_name)


func _on_slot_right_click(slot: UISlot) -> void:
	if slot.item != null:
		set_status("取出：" + slot.item.item_name)


func _on_take() -> void:
	if selected_item == null:
		set_status("请先选择物品")
		return
	var name := selected_item.item_name
	var idx := _items.find(selected_item)
	if idx >= 0:
		_items.remove_at(idx)
	selected_item = null
	_refresh()
	set_status("取出：" + name)


func _on_sort() -> void:
	_items.sort_custom(func(a: ItemDef, b: ItemDef):
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		return a.item_name < b.item_name
	)
	_refresh()
	set_status("已整理")


func set_player_actor(_actor: Dictionary, _assets: Sf85Assets) -> void:
	pass
