## 装备栏 / 物品栏窗口。
##
## 布局：顶部页签 + 左侧「详情」按钮；中上身体装备 / 角色 / 右侧武器+饰品；
## 下方过滤页签与 8×6 物品格。属性与常用材料从左侧同一抽屉展开，顶部页签切换，
## 不占物品格，也不参与背包重量。
class_name InventoryWindow
extends UIWindow

const FILTER_TABS := ["装备", "消耗品", "材料", "副职业", "任务"]
const FILTER_KEYS := ["equipment", "consumable", "material", "profession", "quest"]
const DRAWER_TABS := ["属性", "材料"]
const TOP_GLYPHS := {
	"title": "称", "weapon_main": "武", "weapon_off": "副", "weapon_alt1": "备", "weapon_alt2": "备",
	"head": "头", "shoulder": "肩", "coat": "衣", "pants": "裤",
	"belt": "腰", "shoes": "鞋", "bracer": "腕",
	"necklace": "链", "ring1": "戒", "ring2": "戒", "earring": "耳",
}
const LEFT_SLOTS := ["title", "head", "coat", "shoulder", "pants", "belt", "shoes", "bracer"]
const RIGHT_SLOTS := ["necklace", "earring", "ring1", "ring2"]
const SORT_RULES := [
	{"id": "rarity", "label": "按稀有度"},
	{"id": "level", "label": "按等级"},
	{"id": "slot", "label": "按部位"},
	{"id": "acquired", "label": "按获取时间"},
	{"id": "name", "label": "按名称"},
]

var top_tabs: UITabBar
var filter_tabs: UITabBar
var grid: UIItemGrid
var preview: UICharacterPreview
var weight_bar: UIWeightBar
var currency: UICurrencyBar
var sort_button: UIButton
var organize_button: UIButton
var lock_button: UIButton
var sort_menu: UIPanel
var detail_button: UIButton
var tool_row: HBoxContainer

var weapon_main_slot: UISlot
var weapon_off_slot: UISlot
var weapon_alt1_slot: UISlot
var weapon_alt2_slot: UISlot
var weapon_main_label: Label
var weapon_off_label: Label
var weapon_alt1_label: Label
var weapon_alt2_label: Label

var drawer: UIPanel
var drawer_box: VBoxContainer
var drawer_title: Label
var drawer_tabs: UITabBar
var drawer_mode := ""
var player_job := "鬼剑士"
var sort_rule := "rarity"
var page_locked := false
var _drawer_slide_tween: Tween

var equip_slots := {}
var _items: Array[ItemDef] = []
var _equipped := {}
var _filter_index := 0
var _top_index := 0
var _syncing_drawer_tab := false
var _drawer_width := 268.0


func _ready() -> void:
	window_title = "装备栏"
	super._ready()
	custom_minimum_size = Vector2(440, 760)
	size = custom_minimum_size
	content.add_theme_constant_override("separation", 3)

	_items = ItemDB.inventory_items()
	_equipped = ItemDB.equipment()

	# 顶部：物品栏/时装/宠物
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.custom_minimum_size.y = 26
	content.add_child(header)

	top_tabs = UITabBar.new()
	top_tabs.tabs = ItemDB.INVENTORY_TABS
	top_tabs.min_tab_width = 88
	top_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_tabs.custom_minimum_size.y = 26
	top_tabs.tab_changed.connect(_on_top_tab)
	header.add_child(top_tabs)

	# 中上：左身体 / 中角色 / 右（武器 + 饰品）
	var top := HBoxContainer.new()
	top.name = "Top"
	top.custom_minimum_size.y = 210
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 90
	left.add_theme_constant_override("separation", 4)
	left.add_child(_make_label("身体", 12, UIKit.data(self).text_muted))
	var left_grid := GridContainer.new()
	left_grid.columns = 2
	left_grid.add_theme_constant_override("h_separation", 6)
	left_grid.add_theme_constant_override("v_separation", 4)
	left_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for slot_id in LEFT_SLOTS:
		left_grid.add_child(_make_equip_slot(slot_id))
	left.add_child(left_grid)
	top.add_child(left)

	preview = UICharacterPreview.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_child(preview)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 96
	right.add_theme_constant_override("separation", 3)

	# 右侧上方：四格武器位（2×2，按职业自动禁用）
	right.add_child(_make_label("武器 主/副/备", 9, UIKit.data(self).text_muted))
	var weapon_grid := GridContainer.new()
	weapon_grid.columns = 2
	weapon_grid.add_theme_constant_override("h_separation", 4)
	weapon_grid.add_theme_constant_override("v_separation", 3)
	right.add_child(weapon_grid)

	weapon_main_slot = _make_weapon_slot("weapon_main", "武")
	weapon_main_label = _wrap_weapon_slot(weapon_grid, weapon_main_slot, "主手")
	weapon_off_slot = _make_weapon_slot("weapon_off", "副")
	weapon_off_label = _wrap_weapon_slot(weapon_grid, weapon_off_slot, "副手")
	weapon_alt1_slot = _make_weapon_slot("weapon_alt1", "备")
	weapon_alt1_label = _wrap_weapon_slot(weapon_grid, weapon_alt1_slot, "备 1")
	weapon_alt2_slot = _make_weapon_slot("weapon_alt2", "备")
	weapon_alt2_label = _wrap_weapon_slot(weapon_grid, weapon_alt2_slot, "备 2")

	# 右侧下方：四格饰品
	right.add_child(_make_label("饰品", 11, UIKit.data(self).text_muted))
	var right_grid := GridContainer.new()
	right_grid.columns = 2
	right_grid.add_theme_constant_override("h_separation", 4)
	right_grid.add_theme_constant_override("v_separation", 4)
	for slot_id in RIGHT_SLOTS:
		right_grid.add_child(_make_equip_slot(slot_id))
	right.add_child(right_grid)
	top.add_child(right)

	# 装备栏底部、物品分类页签之上：一排小工具按钮。
	tool_row = HBoxContainer.new()
	tool_row.name = "ToolRow"
	tool_row.custom_minimum_size.y = 22
	tool_row.add_theme_constant_override("separation", 5)
	content.add_child(tool_row)

	detail_button = _make_detail_button("详情")
	detail_button.custom_minimum_size = Vector2(54, 20)
	detail_button.add_theme_font_size_override("font_size", 10)
	detail_button.pressed.connect(_on_detail_pressed)
	tool_row.add_child(detail_button)

	var tool_spacer := Control.new()
	tool_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_row.add_child(tool_spacer)

	var tool_hint := Label.new()
	tool_hint.text = "Ctrl+左键 锁定"
	tool_hint.add_theme_font_size_override("font_size", 9)
	tool_hint.add_theme_color_override("font_color", UIKit.a(UIKit.data(self).text_muted, 0.72))
	tool_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tool_row.add_child(tool_hint)

	# 过滤页签：五个分类均分整条宽度。
	var filter_row := HBoxContainer.new()
	filter_row.custom_minimum_size.y = 24
	filter_row.add_theme_constant_override("separation", 0)
	content.add_child(filter_row)

	filter_tabs = UITabBar.new()
	filter_tabs.tabs = PackedStringArray(FILTER_TABS)
	filter_tabs.min_tab_width = 48
	filter_tabs.equal_width = true
	filter_tabs.custom_minimum_size.y = 24
	filter_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_tabs.tab_changed.connect(_on_filter_tab)
	filter_row.add_child(filter_tabs)

	grid = UIItemGrid.new()
	grid.columns = 8
	grid.rows = 6
	grid.slot_size = 42
	grid.gap_override = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.slot_hovered.connect(_on_grid_hover)
	grid.slot_unhovered.connect(_on_grid_unhover)
	grid.slot_activated.connect(_on_grid_activate)
	grid.slot_lock_changed.connect(_on_slot_lock_changed)
	content.add_child(grid)
	grid.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid.clip_contents = true

	# 底部：短重量条 + 排序 / 锁 / 整理，右侧收口。
	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 20
	footer.add_theme_constant_override("separation", 5)
	content.add_child(footer)

	weight_bar = UIWeightBar.new()
	weight_bar.custom_minimum_size = Vector2(180, 18)
	weight_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(weight_bar)

	sort_button = UIButton.new()
	sort_button.text = "排序"
	sort_button.variant = "ghost"
	sort_button.custom_minimum_size = Vector2(48, 18)
	sort_button.add_theme_font_size_override("font_size", 10)
	sort_button.pressed.connect(_show_sort_menu)
	footer.add_child(sort_button)

	lock_button = UIButton.new()
	lock_button.text = "锁"
	lock_button.variant = "ghost"
	lock_button.custom_minimum_size = Vector2(30, 18)
	lock_button.add_theme_font_size_override("font_size", 10)
	lock_button.pressed.connect(_toggle_page_lock)
	footer.add_child(lock_button)

	organize_button = UIButton.new()
	organize_button.text = "整理"
	organize_button.variant = "accent"
	organize_button.custom_minimum_size = Vector2(52, 18)
	organize_button.add_theme_font_size_override("font_size", 10)
	organize_button.pressed.connect(_on_sort)
	footer.add_child(organize_button)

	currency = UICurrencyBar.new()
	currency.custom_minimum_size.y = 56
	currency.entries = [
		{"label": "金币", "value": 1246132, "color": UIKit.data(self).text_gold, "glyph": "G"},
		{"label": "代币券", "value": 837625, "color": UIKit.data(self).accent, "glyph": "C"},
		{"label": "点券", "value": 12, "color": UIKit.data(self).accent_soft, "glyph": "P"},
		{"label": "复活币", "value": 57, "color": UIKit.data(self).text_success, "glyph": "R"},
	]
	content.add_child(currency)

	_build_sort_menu()

	_build_drawer()
	resized.connect(_layout_drawer)
	item_rect_changed.connect(_layout_drawer)

	_refresh()
	weight_bar.set_values(_total_weight(), 50.0, false)
	_apply_weapon_rules()


func _make_detail_button(text: String) -> UIButton:
	var b := UIButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(58, 24)
	b.add_theme_font_size_override("font_size", 11)
	return b


func _make_label(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


func _make_equip_slot(slot_id: String) -> UISlot:
	var s := UISlot.new()
	s.slot_id = slot_id
	s.add_theme_constant_override("slot", 36)
	s.empty_glyph = TOP_GLYPHS.get(slot_id, "")
	if _equipped.has(slot_id):
		s.item = _equipped[slot_id]
		s.equipped = true
	s.hover_started.connect(func(sl: UISlot): _on_slot_hover(sl))
	s.hover_ended.connect(func(_sl: UISlot): _hide_tooltip())
	s.activated.connect(func(sl: UISlot): _on_slot_activate(sl))
	equip_slots[slot_id] = s
	return s


func _make_weapon_slot(slot_id: String, glyph: String) -> UISlot:
	var s := UISlot.new()
	s.slot_id = slot_id
	s.add_theme_constant_override("slot", 36)
	s.empty_glyph = glyph
	if _equipped.has(slot_id):
		s.item = _equipped[slot_id]
		s.equipped = true
	s.hover_started.connect(func(sl: UISlot): _on_slot_hover(sl))
	s.hover_ended.connect(func(_sl: UISlot): _hide_tooltip())
	s.activated.connect(func(sl: UISlot): _on_slot_activate(sl))
	equip_slots[slot_id] = s
	return s


func _wrap_weapon_slot(parent: Container, slot: UISlot, label_text: String) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(slot)
	# 槽位说明不占额外一行：空槽用 武 / 副 / 备 的占位字，已装备时看图标和浮框。
	var label := _make_label(label_text, 9, UIKit.data(self).text_muted)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(36, 0)
	label.visible = false
	box.add_child(label)
	parent.add_child(box)
	return label


# ---------------------------------------------------------------------------
# 左侧抽屉：角色属性 / 常用材料（同一个入口，顶部页签切换）
# ---------------------------------------------------------------------------

func _build_drawer() -> void:
	drawer = UIPanel.new()
	drawer.name = "SideDrawer"
	drawer.nested = true
	drawer.glass_mul = 1.08
	drawer.visible = false
	drawer.z_index = 30
	var host := get_parent()
	if host != null:
		host.add_child(drawer)
	else:
		add_child(drawer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	drawer.content.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	root.add_child(head)

	drawer_title = _make_label("角色", 13, UIKit.data(self).text_primary)
	drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(drawer_title)

	var close := UIButton.new()
	close.text = "×"
	close.variant = "ghost"
	close.custom_minimum_size = Vector2(24, 24)
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(_close_drawer)
	head.add_child(close)

	drawer_tabs = UITabBar.new()
	drawer_tabs.tabs = PackedStringArray(DRAWER_TABS)
	drawer_tabs.min_tab_width = 64
	drawer_tabs.custom_minimum_size.y = 24
	drawer_tabs.tab_changed.connect(_on_drawer_tab)
	root.add_child(drawer_tabs)

	var line := Control.new()
	line.custom_minimum_size.y = 1
	line.draw.connect(func(): line.draw_line(Vector2(0, 0), Vector2(line.size.x, 0),
		UIKit.a(UIKit.data(self).frame_highlight, 0.22), 1.0))
	root.add_child(line)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.clip_contents = true
	scroll.get_v_scroll_bar().custom_minimum_size.x = 4
	root.add_child(scroll)

	drawer_box = VBoxContainer.new()
	drawer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_box.add_theme_constant_override("separation", 3)
	scroll.add_child(drawer_box)


func _layout_drawer() -> void:
	if drawer == null or not drawer.visible:
		return
	var want_h := maxf(240.0, drawer_box.get_combined_minimum_size().y + 100.0)
	drawer.size = Vector2(_drawer_width, minf(size.y, want_h))
	var tx := position.x - _drawer_width - 8.0
	if tx < 8.0:
		tx = 8.0
	drawer.position = Vector2(tx, position.y)


func _process(_delta: float) -> void:
	if drawer != null and drawer.visible:
		_layout_drawer()


func _clear_drawer() -> void:
	if drawer_box == null:
		return
	for c in drawer_box.get_children():
		drawer_box.remove_child(c)
		c.queue_free()


func _on_detail_pressed() -> void:
	if drawer != null and drawer.visible:
		_close_drawer()
	else:
		_open_drawer("attrs")


func _open_drawer(mode: String) -> void:
	if drawer == null:
		return
	if drawer.visible and drawer_mode == mode:
		_close_drawer()
		return
	_show_drawer(mode)


func _show_drawer(mode: String) -> void:
	drawer_mode = mode
	drawer.visible = true
	drawer.move_to_front()
	_layout_drawer()
	detail_button.variant = "accent"
	_syncing_drawer_tab = true
	drawer_tabs.current = 0 if mode == "attrs" else 1
	_syncing_drawer_tab = false
	if mode == "attrs":
		_build_attributes()
	else:
		_build_materials()


func _on_drawer_tab(index: int) -> void:
	if _syncing_drawer_tab:
		return
	_show_drawer("attrs" if index == 0 else "materials")


func _close_drawer() -> void:
	drawer_mode = ""
	if drawer != null:
		drawer.visible = false
	if detail_button != null:
		detail_button.variant = "normal"


func open_attributes() -> void:
	_open_drawer("attrs")


func open_materials() -> void:
	_open_drawer("materials")


func close_drawer() -> void:
	_close_drawer()


func _build_attributes() -> void:
	_clear_drawer()
	for section in ItemDB.character_attributes():
		var title := _make_label("  " + str(section["section"]), 11, UIKit.data(self).accent_soft)
		title.custom_minimum_size.y = 22
		drawer_box.add_child(title)
		for row in section["rows"]:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 4)
			var key := _make_label(str(row[0]), 10, UIKit.data(self).text_muted)
			key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var value := _make_label(str(row[1]), 10, UIKit.data(self).text_secondary)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(key)
			line.add_child(value)
			var pad := Control.new()
			pad.custom_minimum_size.x = 10
			line.add_child(pad)
			drawer_box.add_child(line)


func _build_materials() -> void:
	_clear_drawer()
	var note := _make_label("不占物品栏 · 获取后数量累加", 9, UIKit.data(self).text_muted)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drawer_box.add_child(note)

	for item in ItemDB.common_materials():
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 28
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_entered.connect(func(): _show_item_at_row(item, row))
		row.mouse_exited.connect(_hide_tooltip)

		var icon := TextureRect.new()
		icon.texture = _item_texture(item)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

		var name := _make_label(item.item_name, 10, UIKit.data(self).text_secondary)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name)

		var count := _make_label(UIKit.fmt_int(item.count), 9, UIKit.data(self).text_gold)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.custom_minimum_size.x = 62
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(count)

		drawer_box.add_child(row)

	var tip := _make_label("小晶块可在副本/分解中获得；数量独立累加，不占物品栏。", 9,
		UIKit.data(self).text_muted)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drawer_box.add_child(tip)


func _item_texture(item: ItemDef) -> Texture2D:
	var root := get_tree().get_first_node_in_group("ui_root")
	if root != null and root.has_method("item_texture"):
		return root.item_texture(item)
	return null


func _show_item_at_row(item: ItemDef, row: Control) -> void:
	if tooltip_layer != null:
		tooltip_layer.show_item(item, row.get_global_rect())


# ---------------------------------------------------------------------------
# 武器体系：按职业自动匹配，不出现手动切换按钮
# ---------------------------------------------------------------------------

func _apply_weapon_rules() -> void:
	var job := player_job
	# 四个武器槽是通用的：主手 / 副手 / 两格备用。
	# 不绑定具体职业物品（箭袋、盾、法球都只是副手位里的物品）。
	# 野蛮人这类“四武器”职业才解锁备用 1/2，其余职业显示为不可用。
	var allow_alt := job.contains("野蛮") or job.contains("狂战") or job.contains("四武器")
	weapon_main_slot.disabled = false
	weapon_off_slot.disabled = false
	weapon_alt1_slot.disabled = not allow_alt
	weapon_alt2_slot.disabled = not allow_alt
	weapon_main_label.text = "主手"
	weapon_off_label.text = "副手"
	weapon_alt1_label.text = "备 1"
	weapon_alt2_label.text = "备 2"


func set_job(job_name: String) -> void:
	player_job = job_name
	_apply_weapon_rules()


# ---------------------------------------------------------------------------
# 数据刷新
# ---------------------------------------------------------------------------

func _on_top_tab(index: int) -> void:
	_top_index = index
	_close_drawer()
	grid.clear_locks()
	page_locked = false
	_update_lock_button()
	if index == 0:
		_apply_filter()
	elif index == 1:
		grid.set_items(_items, _capacity())
		grid.set_filter("avatar")
		_refresh_weight()
	else:
		grid.set_items(_items, _capacity())
		grid.set_filter("pet")
		_refresh_weight()


func _on_filter_tab(index: int) -> void:
	_filter_index = index
	if _top_index != 0:
		_top_index = 0
		top_tabs.current = 0
	_apply_filter()


func _capacity() -> int:
	return grid.columns * grid.rows


func _apply_filter() -> void:
	grid.set_items(_items, _capacity())
	grid.clear_locks()
	page_locked = false
	_update_lock_button()
	grid.set_filter(FILTER_KEYS[clampi(_filter_index, 0, FILTER_KEYS.size() - 1)])
	_refresh_weight()


func _refresh_weight() -> void:
	# 负重是背包整体，不随当前页签/过滤条件变化。
	weight_bar.set_values(_total_weight(), 50.0)


func _refresh() -> void:
	_apply_filter()


func _total_weight(items: Variant = null) -> float:
	var src: Array = _items if items == null else items
	var total := 0.0
	for it in src:
		if it is ItemDef:
			total += it.weight * maxi(1, it.count)
	return total


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

func _on_grid_hover(slot: UISlot) -> void:
	_on_slot_hover(slot)


func _on_grid_unhover(_slot: UISlot) -> void:
	_hide_tooltip()


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


func _on_grid_activate(slot: UISlot) -> void:
	_on_slot_activate(slot)


func _on_sort() -> void:
	if page_locked:
		set_status("当前页已锁定，整理不生效")
		return
	_sort_by(sort_rule)
	set_status("已整理")


func _collect_entries() -> Array:
	var existing := grid.entries()
	if not existing.is_empty():
		return existing
	var items := grid.filtered_items()
	var out := []
	for i in _capacity():
		out.append(items[i] if i < items.size() else null)
	return out


func _sort_by(rule: String) -> void:
	var entries := _collect_entries()
	var locked := grid.locked_indices()
	var locked_map := {}
	var movable: Array = []
	for i in entries.size():
		var it: Variant = entries[i]
		if not (it is ItemDef):
			continue
		if i in locked:
			locked_map[i] = it
		else:
			movable.append(it)
	movable.sort_custom(func(a: ItemDef, b: ItemDef): return _compare_items(a, b, rule))
	var out := []
	var mi := 0
	for i in _capacity():
		if locked_map.has(i):
			out.append(locked_map[i])
		elif mi < movable.size():
			out.append(movable[mi])
			mi += 1
		else:
			out.append(null)
	grid.set_entries(out, _capacity())


func _compare_items(a: ItemDef, b: ItemDef, rule: String) -> bool:
	match rule:
		"level":
			if a.level != b.level:
				return a.level > b.level
		"slot":
			var sa := ItemDB.SLOT_ORDER.find(a.slot)
			var sb := ItemDB.SLOT_ORDER.find(b.slot)
			if sa == -1:
				sa = 99
			if sb == -1:
				sb = 99
			if sa != sb:
				return sa < sb
		"acquired":
			if a.acquired != b.acquired:
				return a.acquired > b.acquired
		"name":
			return a.item_name.naturalnocasecmp_to(b.item_name) < 0
		_:
			if a.rarity != b.rarity:
				return a.rarity > b.rarity
	if a.rarity != b.rarity:
		return a.rarity > b.rarity
	return a.item_name.naturalnocasecmp_to(b.item_name) < 0


func _build_sort_menu() -> void:
	sort_menu = UIPanel.new()
	sort_menu.name = "SortMenu"
	sort_menu.visible = false
	sort_menu.z_index = 60
	sort_menu.size = Vector2(146, SORT_RULES.size() * 25 + 10)
	var host := get_parent()
	if host != null:
		host.add_child(sort_menu)
	else:
		add_child(sort_menu)
	sort_menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sort_menu.size = Vector2(146, SORT_RULES.size() * 25 + 10)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	sort_menu.content.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	margin.add_child(box)
	for i in SORT_RULES.size():
		var rule: Dictionary = SORT_RULES[i]
		var b := UIButton.new()
		b.text = str(rule["label"])
		b.variant = "ghost"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 24)
		b.add_theme_font_size_override("font_size", 11)
		var rid: int = i
		b.pressed.connect(func() -> void: _select_sort_rule(rid))
		box.add_child(b)


func _rebuild_sort_menu() -> void:
	if sort_menu == null:
		return
	var idx := 0
	for c in sort_menu.content.get_child(0).get_child(0).get_children():
		if c is UIButton:
			var rule: Dictionary = SORT_RULES[idx]
			c.text = ("✓ " if rule["id"] == sort_rule else "   ") + str(rule["label"])
			c.variant = "accent" if rule["id"] == sort_rule else "ghost"
			idx += 1


func _show_sort_menu() -> void:
	if sort_menu == null:
		return
	_rebuild_sort_menu()
	sort_menu.visible = not sort_menu.visible
	if not sort_menu.visible:
		return
	var host := sort_menu.get_parent() as Control
	var origin := host.get_global_position() if host != null else Vector2.ZERO
	var gr := sort_button.get_global_rect()
	sort_menu.position = gr.position - origin + Vector2(-10, -sort_menu.size.y - 4)
	sort_menu.move_to_front()


func _select_sort_rule(id: int) -> void:
	if id < 0 or id >= SORT_RULES.size():
		return
	sort_rule = str(SORT_RULES[id]["id"])
	sort_menu.visible = false
	if page_locked:
		set_status("当前页已锁定，排序不生效")
		return
	_sort_by(sort_rule)
	set_status("排序：" + str(SORT_RULES[id]["label"]))


func _toggle_page_lock() -> void:
	page_locked = not page_locked
	_update_lock_button()
	set_status("当前页已锁定" if page_locked else "当前页已解锁")


func _update_lock_button() -> void:
	if lock_button == null:
		return
	lock_button.text = "解锁" if page_locked else "锁"
	lock_button.variant = "accent" if page_locked else "ghost"
	lock_button.tooltip_text = "锁定当前页格子：锁定后整理/排序不生效" if not page_locked else "解锁当前页"
	if organize_button != null:
		organize_button.disabled = page_locked
	if sort_button != null:
		sort_button.disabled = page_locked


func _on_slot_lock_changed(slot: UISlot) -> void:
	set_status(("已锁定：" + slot.item.item_name) if slot.item != null and slot.locked else "已解锁格子")


func close_window(immediate := false) -> void:
	_close_drawer()
	if sort_menu != null:
		sort_menu.visible = false
	super.close_window(immediate)


func set_player_actor(actor: Dictionary, assets: Sf85Assets) -> void:
	if preview == null:
		return
	if actor.is_empty() or assets == null:
		preview.clear_actor()
	else:
		preview.set_actor(actor, assets)
