extends Node2D
## 环境冒烟脚本（仅验证环境，不含游戏逻辑）
## 跑法：godot --path tools/smoke            （有窗口，走 WSLg）
##       godot --headless --path tools/smoke  （无窗口，验证能不能离屏取图）

const LABEL_Y_DEFAULT := 140
const LABEL_Y_MSYH := 200
const LABEL_Y_SYSFONT := 260
const OFFSCREEN_PNG := "user://smoke_offscreen.png"
const WINDOW_PNG := "user://smoke_window.png"

var _frames := 0
var _report: Array[String] = []
var _font_msyh: FontFile
var _font_sys: Font
var _label_default_a: Label
var _label_default_b: Label


func _ready() -> void:
	_log("== engine: ", Engine.get_version_info().string)
	_log("== os: ", OS.get_name(), " | ", OS.get_distribution_name(), " ", OS.get_version())
	_log("== display_server: ", DisplayServer.get_name())
	_log("== window_size: ", DisplayServer.window_get_size())
	_log("== adapter: ", RenderingServer.get_video_adapter_name(),
		" | vendor=", RenderingServer.get_video_adapter_vendor(),
		" | api=", RenderingServer.get_video_adapter_api_version())
	_log("== utf8: 中文测试 DNF 鬼剑士 洛兰 攻击盒")
	_log("== user_dir: ", ProjectSettings.globalize_path("user://"))

	_font_msyh = FontFile.new()
	var err := _font_msyh.load_dynamic_font("/mnt/c/Windows/Fonts/msyh.ttc")
	_log("== font msyh load err=", err, " name=", _font_msyh.get_font_name())
	if err != OK:
		_font_msyh = null

	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "WenQuanYi Zen Hei"])
	sf.allow_system_fallback = true
	_font_sys = sf
	_log("== SystemFont OK, size(中文)=", sf.get_string_size("中文", HORIZONTAL_ALIGNMENT_LEFT, -1, 24))


func _build_labels() -> void:
	_label_default_a = _add_label("中", Vector2(200, LABEL_Y_DEFAULT), null)
	_label_default_b = _add_label("文", Vector2(260, LABEL_Y_DEFAULT), null)
	_add_label("中", Vector2(200, LABEL_Y_MSYH), _font_msyh)
	_add_label("文", Vector2(260, LABEL_Y_MSYH), _font_msyh)
	_add_label("中", Vector2(200, LABEL_Y_SYSFONT), _font_sys)
	_add_label("文", Vector2(260, LABEL_Y_SYSFONT), _font_sys)
	_add_label("默认字体：中文测试 ABC", Vector2(20, 20), null)
	_add_label("msyh：中文测试 ABC", Vector2(20, 60), _font_msyh)
	_add_label("SystemFont：中文测试 ABC", Vector2(20, 100), _font_sys)


func _add_label(text: String, pos: Vector2, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 24)
	if font != null:
		l.add_theme_font_override("font", font)
	add_child(l)
	return l


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 2:
		_build_labels()
	if _frames < 4:
		return
	_report_and_quit()
	set_process(false)


func _report_and_quit() -> void:
	var vp := get_viewport()
	var tex := vp.get_texture()
	_log("== viewport size: ", vp.get_visible_rect().size, " texture=", tex)
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_log("== capture: NULL（拿不到图像）")
	else:
		_log("== capture: size=", img.get_size(), " format=", img.get_format(), " empty=", img.is_empty())
		var nonzero := _count_nonzero(img)
		_log("== capture: nonzero_pixels=", nonzero, "/", img.get_width() * img.get_height())
		var saved := img.save_png(ProjectSettings.globalize_path(OFFSCREEN_PNG))
		_log("== capture: save_png err=", saved, " -> ", ProjectSettings.globalize_path(OFFSCREEN_PNG))
		var a := img.get_region(Rect2i(200, LABEL_Y_DEFAULT, 40, 40)).get_data()
		var b := img.get_region(Rect2i(260, LABEL_Y_DEFAULT, 40, 40)).get_data()
		var ma := img.get_region(Rect2i(200, LABEL_Y_MSYH, 40, 40)).get_data()
		var mb := img.get_region(Rect2i(260, LABEL_Y_MSYH, 40, 40)).get_data()
		_log("== tofu-check default: 中==文 ? ", a == b, " (true 说明两个汉字渲染成同一个方块=无 CJK 字形)")
		_log("== tofu-check msyh   : 中==文 ? ", ma == mb)
	# 屏幕抓图（只有真窗口/真显示才可能成功）
	if DisplayServer.get_name() != "headless":
		var scr := DisplayServer.screen_get_image(0)
		if scr != null and not scr.is_empty():
			scr.save_png(ProjectSettings.globalize_path(WINDOW_PNG))
			_log("== screen_get_image: size=", scr.get_size(), " -> ", ProjectSettings.globalize_path(WINDOW_PNG))
		else:
			_log("== screen_get_image: 拿不到屏幕图像")
	else:
		_log("== screen_get_image: 跳过（headless）")
	_save_report()
	get_tree().quit()


func _log(a = null, b = null, c = null, d = null, e = null, f = null) -> void:
	var parts: Array[String] = []
	for v in [a, b, c, d, e, f]:
		if v != null:
			parts.append(str(v))
	var line := "".join(parts)
	_report.append(line)
	print(line)


func _save_report() -> void:
	var f := FileAccess.open("user://smoke_report.txt", FileAccess.WRITE)
	if f == null:
		return
	for line in _report:
		f.store_line(line)
	f.close()


func _count_nonzero(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.r > 0.02 or c.g > 0.02 or c.b > 0.02:
				n += 1
	return n
