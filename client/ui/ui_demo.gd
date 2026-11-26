## UI 演示场景：一块假的游戏画面 + UIRoot。
##
## 快捷键：I 背包 / K 金库 / F3 换肤 / ESC 关最上层。
## 环境变量：
##   UI_PRESET=abyss|ember|jade|violet   起始配色
##   UI_DEMO=inventory|warehouse|both    打开哪个窗口
##   UI_SHOT=/tmp/ui.png                 截一张图然后退出
extends Control

var ui: UIRoot
var _hint_font: SystemFont


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.03, 0.05))
	get_window().size = Vector2i(1600, 1000)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint_font = SystemFont.new()
	_hint_font.font_names = PackedStringArray([
		"Noto Sans CJK SC", "Microsoft YaHei", "WenQuanYi Zen Hei"])
	_hint_font.allow_system_fallback = true

	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)

	ui = UIRoot.new()
	ui.open_inventory_on_start = false
	var preset := OS.get_environment("UI_PRESET")
	if preset in UIThemePresets.PRESETS:
		ui.theme_preset = preset
	canvas.add_child(ui)

	var win_env := OS.get_environment("UI_WINDOW")
	if win_env.contains("x"):
		var parts := win_env.split("x")
		if parts.size() == 2:
			ui.set_window_size(Vector2i(int(parts[0]), int(parts[1])))

	var mode := OS.get_environment("UI_DEMO")
	if mode == "warehouse":
		ui.warehouse.open_window(true)
	elif mode == "both":
		ui.inventory.open_window(true)
		ui.warehouse.open_window(true)
	else:
		ui.inventory.open_window(true)

	# 资产：真实 PVF + NPK，给中间的角色预览用。
	var assets := Sf85Assets.new()
	var pvf := "/mnt/e/dnf-sf/sf85/老牛DNF客户端/Script.pvf"
	if FileAccess.file_exists(pvf) and assets.open(pvf, "res://assets/npk-index.bin"):
		var actor := assets.actor("player")
		ui.bind_assets(assets, actor)

	var drawer := OS.get_environment("UI_DRAWER")
	if drawer == "attrs" and ui.inventory != null:
		ui.inventory.open_attributes()
	elif drawer == "materials" and ui.inventory != null:
		ui.inventory.open_materials()

	if OS.get_environment("UI_CONSOLE") == "1":
		ui.attach_debug(null, null)
		ui.open_console()

	if OS.get_environment("UI_SORT") == "1" and ui.inventory != null:
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if ui.inventory != null:
				ui.inventory._show_sort_menu()
		)

	if OS.get_environment("UI_LOCK") == "1" and ui.inventory != null:
		var s0 := ui.inventory.grid.get_slot(0)
		if s0 != null:
			s0.locked = true
			s0.lock_changed.emit(s0)
		ui.inventory._toggle_page_lock()

	if OS.get_environment("UI_TOOLTIP") == "1" and ui.inventory != null:
		var sample: ItemDef = null
		for it in ItemDB.warehouse_items():
			if it.item_name.contains("东方棍"):
				sample = it
				break
		if sample == null and ui.inventory.grid.get_slot(0) != null:
			sample = ui.inventory.grid.get_slot(0).item
		if sample != null:
			ui.tooltip_layer.show_item_at(sample, Vector2(700, 150))

	var shot := OS.get_environment("UI_SHOT")
	if shot != "":
		Input.warp_mouse(Vector2(4, 4))
		var frames := 24
		var fenv := OS.get_environment("UI_SHOT_FRAMES")
		if fenv != "":
			frames = maxi(1, int(fenv))
		for i in frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot)
		LogUtil.info("SHOT %s %dx%d" % [shot, img.get_width(), img.get_height()])
		get_tree().quit()


func _draw() -> void:
	var vp := size
	# 竖向渐变
	var bands := 36
	for i in bands:
		var t := float(i) / float(bands)
		var col := Color(0.06, 0.09, 0.14).lerp(Color(0.02, 0.035, 0.06), t)
		draw_rect(Rect2(0, vp.y * t, vp.x, vp.y / bands + 1), col)

	# 远处光晕
	for i in 8:
		var t := float(i) / 8.0
		draw_circle(Vector2(vp.x * 0.72, vp.y * 0.35), 90 + t * 220,
				Color(0.18, 0.42, 0.62, 0.018))

	# 地面透视线
	for i in 14:
		var x := vp.x * float(i) / 13.0
		draw_line(Vector2(x, vp.y), Vector2(vp.x * 0.5, vp.y * 0.62),
				Color(0.35, 0.55, 0.7, 0.10), 1.0)
	for i in 9:
		var y := vp.y * 0.62 + pow(float(i) / 9.0, 1.7) * vp.y * 0.4
		draw_line(Vector2(0, y), Vector2(vp.x, y), Color(0.35, 0.55, 0.7, 0.08), 1.0)

	# 一些高对比的方块，让磨砂玻璃看得出模糊
	var blocks := [
		[Rect2(vp.x * 0.06, vp.y * 0.12, 120, 220), Color(0.2, 0.55, 0.8, 0.22)],
		[Rect2(vp.x * 0.78, vp.y * 0.55, 190, 160), Color(0.9, 0.55, 0.2, 0.18)],
		[Rect2(vp.x * 0.12, vp.y * 0.72, 240, 90), Color(0.3, 0.8, 0.55, 0.16)],
		[Rect2(vp.x * 0.62, vp.y * 0.10, 90, 90), Color(0.8, 0.3, 0.6, 0.20)],
	]
	for b in blocks:
		draw_rect(b[0], b[1])
		draw_rect(b[0], Color(1, 1, 1, 0.08), false, 1.0)

	if ui != null and ui.inventory != null and ui.inventory.is_open():
		draw_string(_hint_font, Vector2(18, size.y - 14),
				"I 背包   K 金库   F1 控制台   F3 换肤   ESC 关闭   ·   拖动标题栏移动窗口",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 0.95, 0.55))
