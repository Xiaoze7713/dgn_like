## 窗口标题栏：渐变底色、居中标题、左右纹章、状态文字、关闭按钮。
class_name UITitleBar
extends Control

signal close_requested

@export var window_title := "":
	set(v):
		window_title = v
		queue_redraw()
@export var status_text := "":
	set(v):
		status_text = v
		queue_redraw()
@export var closable := true

var close_button: UIButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = UIKit.k(self, "title_h", 42)
	close_button = UIButton.new()
	close_button.name = "Close"
	close_button.text = "×"
	close_button.variant = "ghost"
	close_button.tooltip_text = "关闭"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.custom_minimum_size = Vector2(28, 28)
	close_button.pressed.connect(func(): close_requested.emit())
	add_child(close_button)
	theme_changed.connect(_on_theme_changed)
	resized.connect(_layout)
	_layout()


func _on_theme_changed() -> void:
	custom_minimum_size.y = UIKit.k(self, "title_h", 42)
	_layout()
	queue_redraw()


func _layout() -> void:
	if close_button == null:
		return
	close_button.size = Vector2(28, 28)
	close_button.position = Vector2(size.x - 42, 7)
	close_button.visible = closable


func _draw() -> void:
	var d := UIKit.data(self)
	if d == null:
		return
	var h := size.y
	var w := size.x
	var radius := float(d.corner_radius)

	# 顶栏底色：上亮下暗的竖条（用几层叠出渐变，角落仍保持圆角）
	var base := StyleBoxFlat.new()
	base.bg_color = d.title_top
	base.set_corner_radius_all(0)
	base.corner_radius_top_left = d.corner_radius
	base.corner_radius_top_right = d.corner_radius
	base.border_color = Color(0, 0, 0, 0)
	base.anti_aliasing = true
	draw_style_box(base, Rect2(Vector2(1, 1), Vector2(w - 2, h - 1)))

	# 顶部一层很薄的高光
	draw_rect(Rect2(Vector2(radius, 2), Vector2(maxf(0, w - radius * 2), 1)),
			UIKit.a(d.frame_highlight, 0.16))

	# 底部：由 title_top 过渡到 title_bottom 的窄带
	var bands := 3
	for i in bands:
		var t := float(i) / float(bands)
		var col := d.title_top.lerp(d.title_bottom, 0.35 + t * 0.65)
		col.a = 0.55
		draw_rect(Rect2(Vector2(1, h - 9 + i * 1), Vector2(w - 2, 1)), col)

	# 金色分隔线
	var gold_line := UIKit.a(d.gold, 0.34)
	draw_line(Vector2(12, h - 0.5), Vector2(w - 12, h - 0.5), gold_line, 1.0, true)
	draw_line(Vector2(w * 0.5 - 52, h - 0.5), Vector2(w * 0.5 + 52, h - 0.5),
			UIKit.a(d.gold, 0.65), 1.0, true)

	# 左侧小菱形 + 短装饰线
	var cy := h * 0.5
	UIKit.diamond(self, Vector2(17, cy), 3.5, UIKit.a(d.accent, 0.9))
	draw_line(Vector2(24, cy), Vector2(42, cy), UIKit.a(d.frame_highlight, 0.35), 1.0, true)
	# 右侧对称
	var rx := w - 24
	draw_line(Vector2(rx - 18, cy), Vector2(rx, cy), UIKit.a(d.frame_highlight, 0.25), 1.0, true)

	# 标题：居中到「左侧 48 ~ 右侧给状态/关闭留 112」的区间
	var f := UIKit.font(self, true)
	var fs := UIKit.fs(self, "fs_title", 16)
	var right_pad := 112.0 if (status_text != "" or closable) else 48.0
	var tr := Rect2(48, 0, maxf(10, w - right_pad - 48), h)
	UIKit.text(self, window_title, tr, f, fs, d.title_text, UIKit.ALIGN_CENTER)

	# 标题下方一条很短的强调线
	if window_title != "":
		var tw := minf(UIKit.text_width(f, window_title, fs) + 26, tr.size.x)
		draw_line(Vector2((w - tw) * 0.5, h - 6), Vector2((w + tw) * 0.5, h - 6),
				UIKit.a(d.accent, 0.55), 1.0, true)

	if status_text != "":
		var sf := UIKit.font(self, false)
		UIKit.text(self, status_text, Rect2(w - 220, 0, 150, h), sf,
				UIKit.fs(self, "fs_s", 12), d.text_muted, UIKit.ALIGN_RIGHT)
