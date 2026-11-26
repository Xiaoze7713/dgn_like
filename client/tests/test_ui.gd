extends SceneTree

var _demo: Control
var _fails := 0


func _initialize() -> void:
	_demo = load("res://ui/ui_demo.tscn").instantiate()
	get_root().add_child(_demo)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		_fails += 1
		printerr("FAIL ", what)


func _run() -> void:
	await process_frame
	await process_frame
	var ui: UIRoot = _demo.ui
	_check(ui != null, "UIRoot exists")
	_check(ui.inventory.is_open(), "inventory opens by default")
	_check(ui.inventory.title_bar.window_title == "装备栏", "inventory title")

	var inv := ui.inventory
	_check(inv.grid.slots.size() == 48, "inventory 8x6 slots")
	_check(inv.grid.columns == 8 and inv.grid.rows == 6, "inventory grid is 8x6")
	_check(inv.equip_slots.has("title") and inv.equip_slots["title"].item != null, "title slot present")
	_check(inv.currency.columns == 2 and inv.currency.custom_minimum_size.y >= 56.0, "two-row currency")
	_check(inv.drawer.get_parent() == inv.get_parent(), "detail drawer is external")
	_check(inv.detail_button != null and inv.detail_button.text == "详情", "single detail button")
	_check(inv.detail_button.get_parent() == inv.tool_row, "detail button lives in toolbar row")
	_check(inv.size.y >= 760.0, "inventory is tall enough after toolbar")
	_check(inv.currency.get_global_rect().end.y <= inv.get_global_rect().end.y + 1.0,
			"currency bottom row is not clipped")
	_check(inv.weapon_main_slot.equipped and inv.weapon_main_slot.item.rarity >= 5,
			"equipped rarity slot has item")
	_check(inv.weapon_main_slot.is_processing(), "equipped rarity slot animates")
	_check(not inv.grid.get_slot(0).is_processing(), "bag rarity slot does not animate")
	_check(not ("全部" in inv.filter_tabs.tabs), "inventory has no all filter")
	_check(inv.weapon_alt1_slot != null and inv.weapon_alt2_slot != null, "four weapon slots")
	_check(not inv.weapon_off_slot.disabled and inv.weapon_alt1_slot.disabled, "swordsman two weapons")
	inv.set_job("弓箭手")
	await process_frame
	_check(not inv.weapon_off_slot.disabled and inv.weapon_alt1_slot.disabled, "archer offhand enabled")
	inv.set_job("魔法师")
	await process_frame
	_check(not inv.weapon_off_slot.disabled and inv.weapon_alt1_slot.disabled, "mage offhand enabled")
	inv.set_job("野蛮人")
	await process_frame
	_check(not inv.weapon_alt1_slot.disabled and not inv.weapon_alt2_slot.disabled, "barbarian four weapons")
	inv.set_job("鬼剑士")
	_check(inv.grid.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "inventory grid has no scrollbar")
	var w0 := inv.filter_tabs._tab_rect(0).size.x
	var w4 := inv.filter_tabs._tab_rect(4).size.x
	_check(absf(w0 - w4) < 1.0 and w0 > 0.0, "filter tabs share equal width")

	inv.filter_tabs.select(0)
	await process_frame
	var eq := inv.grid.filtered_items()
	_check(eq.size() > 0, "equipment filter has items")
	var all_eq := true
	for it in eq:
		if it.category != "equipment":
			all_eq = false
	_check(all_eq, "filter only equipment")
	var w_equip := inv.weight_bar.weight
	inv.filter_tabs.select(1)
	await process_frame
	_check(is_equal_approx(inv.weight_bar.weight, w_equip), "weight is global across filters")
	inv.filter_tabs.select(0)
	await process_frame

	inv.open_attributes()
	await process_frame
	_check(inv.drawer.visible, "attribute drawer opens")
	_check(inv.drawer_tabs.current == 0, "attribute drawer tab")
	_check(inv.drawer.position.x < inv.position.x, "attribute drawer sits left of inventory")
	inv.close_drawer()
	await process_frame
	_check(not inv.drawer.visible, "attribute drawer closes")
	inv.open_materials()
	await process_frame
	_check(inv.drawer.visible and inv.drawer_tabs.current == 1, "material drawer tab")
	_check(inv.drawer_box.get_child_count() >= 13, "material one-row list")
	inv.close_drawer()

	inv._on_sort()
	await process_frame
	var entries := inv.grid.entries()
	var visible := []
	for it in entries:
		if it is ItemDef:
			visible.append(it)
	_check(entries.size() == 48 and visible.size() > 2, "sort keeps 48 entries")
	_check(visible[0].rarity >= visible[visible.size() - 1].rarity, "sort rarity desc")

	# 单格锁：锁住第 0 格后排序，该格物品不动。
	var first_slot := inv.grid.get_slot(0)
	var held: ItemDef = first_slot.item
	first_slot.locked = true
	first_slot.lock_changed.emit(first_slot)
	inv._on_sort()
	await process_frame
	_check(inv.grid.get_slot(0).item == held, "locked slot survives sort")
	first_slot = inv.grid.get_slot(0)
	first_slot.locked = false
	first_slot.lock_changed.emit(first_slot)

	# 整页锁：整理/排序不生效。
	inv._toggle_page_lock()
	var before_first: ItemDef = inv.grid.get_slot(0).item
	inv._on_sort()
	await process_frame
	_check(inv.grid.get_slot(0).item == before_first, "page lock blocks sort")
	_check(inv.organize_button.disabled, "page lock disables organize")
	inv._toggle_page_lock()
	_check(not inv.organize_button.disabled, "page unlock re-enables organize")

	inv.sort_rule = "acquired"
	inv._on_sort()
	await process_frame
	var by_time: Array = []
	for it in inv.grid.entries():
		if it is ItemDef:
			by_time.append(it)
	_check(by_time[0].acquired >= by_time[by_time.size() - 1].acquired, "sort acquired desc")

	var sample: ItemDef = inv.grid.get_slot(0).item
	_check(sample != null, "slot 0 has item")
	ui.tooltip_layer.show_item_at(sample, Vector2(700, 150))
	await process_frame
	_check(ui.tooltip_layer.is_showing(), "tooltip shows")
	ui.tooltip_layer.hide_tooltip()
	_check(not ui.tooltip_layer.is_showing(), "tooltip hides")

	ui.cycle_theme()
	await process_frame
	_check(ui.theme_preset == "ember", "theme cycles to ember")
	_check(ui.theme_data.accent != UIThemePresets.get_theme("abyss").accent, "accent changed")

	ui.warehouse.open_window(true)
	await process_frame
	_check(ui.warehouse.is_open(), "warehouse opens")
	_check(ui.warehouse.grid.slots.size() == 84, "warehouse 14x6 slots")
	ui.warehouse.filter_tabs.select(1)
	await process_frame
	var wh_eq := ui.warehouse.grid.filtered_items()
	_check(wh_eq.size() > 0, "warehouse filter has items")
	var wh_ok := true
	for it in wh_eq:
		if it.category != "equipment":
			wh_ok = false
	_check(wh_ok, "warehouse filter only equipment")
	ui.warehouse.filter_tabs.select(0)
	inv.close_window(true)
	await process_frame
	_check(not inv.is_open(), "inventory closes")

	ui.attach_debug(null, null)
	ui.open_console()
	await process_frame
	_check(ui.is_console_open(), "debug console opens")
	_check(ui.debug_console.size.x >= 438.0 and ui.debug_console.size.y >= 620.0,
		"debug console keeps authored size")
	ui.set_ui_scale(1.2)
	await process_frame
	_check(is_equal_approx(ui.content_root.scale.x, 1.2), "ui scale applies to content root")
	ui.open_inventory()
	await process_frame
	var want := ((ui.content_root.size - inv.size) * 0.5).floor()
	_check(inv.position.distance_to(want) < 2.0, "scaled inventory recenters on open")
	inv.close_window(true)
	ui.debug_console.close_window(true)
	await process_frame
	_check(not ui.is_console_open(), "debug console closes")

	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	ui._unhandled_input(key)
	await process_frame
	_check(ui.is_console_open(), "F1 opens debug console")
	ui._unhandled_input(key)
	await process_frame
	_check(not ui.is_console_open(), "F1 closes debug console")

	print("RESULT fails=", _fails)
	quit(1 if _fails > 0 else 0)
