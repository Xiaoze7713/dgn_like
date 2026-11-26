## 游戏内 UI 挂载点：一个 CanvasLayer（layer=10）+ UIRoot。
##
## 用法（room.gd）：
##   var ui := IngameUI.new()
##   add_child(ui)
##   ui.bind(assets, player.def)
##
## 默认不自动打开背包；I 背包 / K 金库 / F3 换肤 / Esc 关闭。
class_name IngameUI
extends CanvasLayer

var root: UIRoot


func _ready() -> void:
	layer = 10
	root = UIRoot.new()
	root.name = "UIRoot"
	root.open_inventory_on_start = false
	add_child(root)

	var shot := OS.get_environment("SF85_UI_SHOT")
	if shot != "":
		_capture.call_deferred(shot)


func bind(assets: Sf85Assets, actor: Dictionary, hud: Sf85Hud = null, room: Node = null) -> void:
	if root == null:
		return
	root.bind_assets(assets, actor)
	if hud != null:
		root.attach_debug(hud, room)


## 调试：启动时直接打开背包。
func open_inventory() -> void:
	if root != null:
		root.open_inventory()


func open_console() -> void:
	if root != null:
		root.open_console()


## 键盘设置窗口（F9 / HUD「键位」按钮）
func open_keybinds() -> void:
	if root != null:
		root.open_keybinds()


func toggle_inventory() -> void:
	if root != null:
		root.toggle_inventory()


## 调试截图：等场景稳定后保存 viewport 并退出。
func _capture(path: String) -> void:
	var frames := 30
	var frames_env := OS.get_environment("SF85_UI_SHOT_FRAMES")
	if frames_env != "":
		frames = maxi(1, int(frames_env))
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	LogUtil.info("UI SHOT %s %dx%d" % [path, img.get_width(), img.get_height()])
	get_tree().quit()
