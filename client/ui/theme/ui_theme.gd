## 一套 UI 的“外观参数”。
##
## 这是一个纯数据 Resource：只描述颜色、透明度、圆角、字号、字体。
## 调它不会动任何控件；把 `.tres` 丢进 UIRoot.theme_data，或运行时调用
## `UIRoot.apply_theme_preset("ember")`，整棵 UI 会立刻换肤。
##
## 设计上刻意把「材质」参数（glass_alpha / glass_blur / glass_noise）
## 和「配色」参数（accent / gold / 各层底色）分开，
## 方便做「同一套配色、几档磨砂」的预设。
class_name UITheme
extends Resource

@export_group("标识")
## 预设键：abyss / ember / jade / violet；自定义主题可以留空。
@export var preset_key := "abyss"
## 显示名，给标题栏状态文字用。
@export var preset_name := "深渊蓝"
@export_multiline var description := "深蓝玻璃 + 青蓝高光，偏冷静的地下城夜色。"

@export_group("主色")
## 强调色：激活页签、悬停描边、数值高亮、进度条。
@export var accent := Color(0.32, 0.84, 1.0, 1.0)
## 辅助色：装饰线、次级图标、渐变收尾。
@export var accent_soft := Color(0.55, 0.72, 1.0, 1.0)
## 强调色的深色版本：按下态、底槽、阴影。
@export var accent_deep := Color(0.06, 0.25, 0.4, 1.0)
## 金色：标题纹章、货币、稀有物边框。
@export var gold := Color(0.9, 0.76, 0.44, 1.0)
@export var gold_soft := Color(1.0, 0.9, 0.65, 1.0)

@export_group("玻璃")
## 玻璃染色（RGB 生效，A 不用）。
@export var glass_tint := Color(0.028, 0.06, 0.11, 1.0)
## 玻璃整体不透明度：0 = 全透（只剩模糊），1 = 完全不透。
@export_range(0.0, 1.0, 0.01) var glass_alpha := 0.78
## 磨砂半径（像素，0 = 关闭模糊）。
@export_range(0.0, 16.0, 0.1) var glass_blur := 6.5
## 颗粒噪点强度，给玻璃一点“脏”的质感。
@export_range(0.0, 0.2, 0.001) var glass_noise := 0.028
## 模糊后的亮度/饱和调整。
@export_range(0.4, 1.4, 0.01) var glass_brightness := 0.92
@export_range(0.0, 1.5, 0.01) var glass_saturation := 0.82
## 四角压暗（暗角）。
@export_range(0.0, 1.0, 0.01) var glass_vignette := 0.3

@export_group("边框与阴影")
@export var frame_color := Color(0.42, 0.56, 0.72, 0.55)
@export var frame_highlight := Color(0.75, 0.9, 1.0, 0.32)
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.55)
@export_range(0.0, 8.0, 0.1) var shadow_size := 3.0
@export_range(0, 32, 1) var corner_radius := 10
@export_range(0, 4, 1) var border_width := 1

@export_group("标题栏")
@export var title_top := Color(0.08, 0.17, 0.28, 0.96)
@export var title_bottom := Color(0.03, 0.08, 0.14, 0.88)
@export var title_text := Color(0.9, 0.97, 1.0, 1.0)
@export_range(24, 64, 1) var title_height := 42

@export_group("格子")
@export var slot_bg := Color(0.02, 0.045, 0.08, 0.72)
@export var slot_bg_alt := Color(0.03, 0.06, 0.1, 0.62)
@export var slot_border := Color(0.35, 0.48, 0.62, 0.35)
@export var slot_hover := Color(0.35, 0.84, 1.0, 0.95)
@export var slot_selected := Color(1.0, 0.83, 0.45, 0.95)
@export_range(24, 72, 1) var slot_size := 46
@export_range(0, 16, 1) var slot_gap := 6

@export_group("文字")
@export var text_primary := Color(0.9, 0.95, 1.0, 1.0)
@export var text_secondary := Color(0.68, 0.78, 0.9, 1.0)
@export var text_muted := Color(0.44, 0.54, 0.66, 1.0)
@export var text_gold := Color(0.96, 0.82, 0.5, 1.0)
@export var text_danger := Color(1.0, 0.42, 0.42, 1.0)
@export var text_success := Color(0.45, 0.95, 0.6, 1.0)

@export_group("稀有度")
## 普通 / 高级 / 稀有 / 勇者 / 神器 / 史诗 / 传说
@export var rarity_colors := PackedColorArray([
	Color(0.82, 0.86, 0.92, 1.0),
	Color(0.38, 0.68, 1.0, 1.0),
	Color(0.71, 0.45, 1.0, 1.0),
	Color(1.0, 0.48, 0.82, 1.0),
	Color(1.0, 0.64, 0.25, 1.0),
	Color(1.0, 0.88, 0.35, 1.0),
	Color(1.0, 0.33, 0.3, 1.0),
])

@export_group("字体")
## 逗号分隔的候选字体，交给系统字体回退。
@export var font_family := "Noto Sans CJK SC, Source Han Sans SC, Microsoft YaHei, WenQuanYi Zen Hei"
@export var font_family_bold := "Noto Sans CJK SC, Source Han Sans SC, Microsoft YaHei, WenQuanYi Zen Hei"
@export_range(10, 24, 1) var font_size_base := 14
@export_range(0.8, 1.4, 0.01) var font_scale := 1.0

@export_group("尺寸")
@export_range(0, 40, 1) var window_padding := 14
@export_range(0, 24, 1) var section_gap := 10


func _make_font(bold: bool) -> SystemFont:
	var f := SystemFont.new()
	var family := font_family_bold if bold else font_family
	f.font_names = PackedStringArray(family.split(",", false))
	for i in f.font_names.size():
		f.font_names[i] = f.font_names[i].strip_edges()
	f.font_weight = 700 if bold else 400
	f.allow_system_fallback = true
	return f


## 把参数编译成 Godot 的 Theme。
## 自定义控件统一从 `UI` 类型里读颜色/常量，所以换 Theme 就是换肤。
func build_theme() -> Theme:
	var t := Theme.new()
	t.set_meta("ui_theme", self)

	var f := _make_font(false)
	var fb := _make_font(true)
	t.default_font = f
	t.default_font_size = int(font_size_base * font_scale)

	t.set_font("font", "UI", f)
	t.set_font("font_bold", "UI", fb)
	t.set_font_size("fs_xs", "UI", int(11 * font_scale))
	t.set_font_size("fs_s", "UI", int(12 * font_scale))
	t.set_font_size("fs_m", "UI", int(14 * font_scale))
	t.set_font_size("fs_l", "UI", int(17 * font_scale))
	t.set_font_size("fs_xl", "UI", int(21 * font_scale))
	t.set_font_size("fs_title", "UI", int(16 * font_scale))

	t.set_color("accent", "UI", accent)
	t.set_color("accent_soft", "UI", accent_soft)
	t.set_color("accent_deep", "UI", accent_deep)
	t.set_color("gold", "UI", gold)
	t.set_color("gold_soft", "UI", gold_soft)
	t.set_color("glass_tint", "UI", glass_tint)
	t.set_color("frame", "UI", frame_color)
	t.set_color("frame_highlight", "UI", frame_highlight)
	t.set_color("shadow", "UI", shadow_color)
	t.set_color("title_top", "UI", title_top)
	t.set_color("title_bottom", "UI", title_bottom)
	t.set_color("title_text", "UI", title_text)
	t.set_color("slot_bg", "UI", slot_bg)
	t.set_color("slot_bg_alt", "UI", slot_bg_alt)
	t.set_color("slot_border", "UI", slot_border)
	t.set_color("slot_hover", "UI", slot_hover)
	t.set_color("slot_selected", "UI", slot_selected)
	t.set_color("text_primary", "UI", text_primary)
	t.set_color("text_secondary", "UI", text_secondary)
	t.set_color("text_muted", "UI", text_muted)
	t.set_color("text_gold", "UI", text_gold)
	t.set_color("danger", "UI", text_danger)
	t.set_color("success", "UI", text_success)

	t.set_constant("radius", "UI", corner_radius)
	t.set_constant("border", "UI", border_width)
	t.set_constant("title_h", "UI", title_height)
	t.set_constant("slot", "UI", slot_size)
	t.set_constant("slot_gap", "UI", slot_gap)
	t.set_constant("pad", "UI", window_padding)
	t.set_constant("section_gap", "UI", section_gap)

	# ---- 基础控件 ----
	t.set_color("font_color", "Label", text_primary)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	t.set_color("default_color", "RichTextLabel", text_secondary)
	t.set_font("normal_font", "RichTextLabel", f)
	t.set_font("bold_font", "RichTextLabel", fb)

	# Button 基础样式（普通玻璃按钮）
	t.set_stylebox("normal", "Button", _button_box(Color(0.07, 0.12, 0.19, 0.88), frame_color, 4))
	t.set_stylebox("hover", "Button", _button_box(Color(0.11, 0.2, 0.3, 0.95), accent, 4))
	t.set_stylebox("pressed", "Button", _button_box(accent_deep, accent_soft, 4))
	t.set_stylebox("disabled", "Button", _button_box(Color(0.05, 0.07, 0.1, 0.6), Color(0.25, 0.3, 0.36, 0.4), 4))
	t.set_stylebox("focus", "Button", _button_box(Color(0, 0, 0, 0), Color(accent.r, accent.g, accent.b, 0.65), 4))
	t.set_color("font_color", "Button", text_secondary)
	t.set_color("font_hover_color", "Button", text_primary)
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.45, 0.52, 1))
	t.set_color("font_focus_color", "Button", text_primary)
	t.set_font("font", "Button", f)
	t.set_font_size("font_size", "Button", int(13 * font_scale))
	t.set_constant("h_separation", "Button", 4)

	# 变体：强调按钮
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", _button_box(Color(accent.r, accent.g, accent.b, 0.22), accent, 4))
	t.set_stylebox("hover", "AccentButton", _button_box(Color(accent.r, accent.g, accent.b, 0.36), gold_soft, 4))
	t.set_stylebox("pressed", "AccentButton", _button_box(Color(accent.r, accent.g, accent.b, 0.5), Color(1, 1, 1, 0.9), 4))
	t.set_stylebox("focus", "AccentButton", _button_box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.5), 4))
	t.set_color("font_color", "AccentButton", Color(0.92, 0.98, 1, 1))
	t.set_color("font_hover_color", "AccentButton", Color(1, 1, 1, 1))

	# 变体：幽灵按钮（无底，只有悬停微光）
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", _button_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3, 0))
	t.set_stylebox("hover", "GhostButton", _button_box(Color(0.5, 0.7, 1, 0.1), Color(accent.r, accent.g, accent.b, 0.35), 3, 1))
	t.set_stylebox("pressed", "GhostButton", _button_box(Color(0.5, 0.7, 1, 0.16), accent, 3, 1))
	t.set_stylebox("focus", "GhostButton", _button_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3, 0))
	t.set_color("font_color", "GhostButton", text_muted)
	t.set_color("font_hover_color", "GhostButton", text_primary)

	# 滚条
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(0.02, 0.04, 0.07, 0.5)
	scroll_bg.set_corner_radius_all(3)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(accent.r, accent.g, accent.b, 0.35)
	grab.set_corner_radius_all(3)
	grab.content_margin_left = 2
	grab.content_margin_right = 2
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = Color(accent.r, accent.g, accent.b, 0.6)
	var grab_pr := grab.duplicate() as StyleBoxFlat
	grab_pr.bg_color = Color(accent.r, accent.g, accent.b, 0.8)
	t.set_stylebox("scroll", "VScrollBar", scroll_bg)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_pr)

	# ScrollBar 的上下箭头默认是引擎图标，换成透明 1x1 让滚动条干净。
	var blank := _blank_texture()
	t.set_icon("increment", "VScrollBar", blank)
	t.set_icon("increment_highlight", "VScrollBar", blank)
	t.set_icon("increment_pressed", "VScrollBar", blank)
	t.set_icon("decrement", "VScrollBar", blank)
	t.set_icon("decrement_highlight", "VScrollBar", blank)
	t.set_icon("decrement_pressed", "VScrollBar", blank)
	t.set_constant("scroll_width", "VScrollBar", 8)

	t.set_color("font_color", "TooltipLabel", text_primary)
	t.set_stylebox("panel", "TooltipPanel", _button_box(Color(0.03, 0.07, 0.12, 0.96), frame_color, 6))

	return t


func _button_box(bg: Color, border: Color, radius: int, border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.anti_aliasing = true
	return sb


func _blank_texture() -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func rarity_color(rarity: int) -> Color:
	if rarity_colors.is_empty():
		return Color.WHITE
	return rarity_colors[clampi(rarity, 0, rarity_colors.size() - 1)]


func copy_with(overrides: Dictionary) -> UITheme:
	var t := duplicate() as UITheme
	for k in overrides:
		t.set(k, overrides[k])
	return t


static func from_preset(preset: String) -> UITheme:
	return UIThemePresets.get_theme(preset)
