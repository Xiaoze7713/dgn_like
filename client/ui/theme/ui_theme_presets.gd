## 内置配色预设。真正的“可调参数”在 UITheme 上；
## 这里只是几套调好的起点，方便 F3 轮换 / 从代码切。
class_name UIThemePresets
extends RefCounted

const PRESETS := ["abyss", "ember", "jade", "violet"]


static func get_theme(preset: String) -> UITheme:
	match preset:
		"ember":
			return ember()
		"jade":
			return jade()
		"violet":
			return violet()
		_:
			return abyss()


static func cycle(current: String) -> String:
	var i := PRESETS.find(current)
	return PRESETS[(i + 1) % PRESETS.size()]


## 深渊蓝：默认。深蓝玻璃、青蓝高光，接近 DNF 装备栏的夜色。
static func abyss() -> UITheme:
	var t := UITheme.new()
	t.preset_key = "abyss"
	t.preset_name = "深渊蓝"
	t.description = "深蓝玻璃 + 青蓝高光，偏冷静的地下城夜色。"
	t.accent = Color(0.32, 0.84, 1.0)
	t.accent_soft = Color(0.55, 0.72, 1.0)
	t.accent_deep = Color(0.06, 0.25, 0.4)
	t.gold = Color(0.9, 0.76, 0.44)
	t.gold_soft = Color(1.0, 0.9, 0.65)
	t.glass_tint = Color(0.028, 0.06, 0.11)
	t.glass_alpha = 0.78
	t.glass_blur = 6.5
	t.glass_noise = 0.028
	t.glass_brightness = 0.92
	t.glass_saturation = 0.82
	t.glass_vignette = 0.3
	t.frame_color = Color(0.42, 0.56, 0.72, 0.55)
	t.frame_highlight = Color(0.75, 0.9, 1.0, 0.32)
	t.title_top = Color(0.08, 0.17, 0.28, 0.96)
	t.title_bottom = Color(0.03, 0.08, 0.14, 0.88)
	t.slot_bg = Color(0.02, 0.045, 0.08, 0.72)
	t.slot_bg_alt = Color(0.03, 0.06, 0.1, 0.62)
	t.slot_border = Color(0.35, 0.48, 0.62, 0.35)
	t.text_primary = Color(0.9, 0.95, 1.0)
	t.text_secondary = Color(0.68, 0.78, 0.9)
	t.text_muted = Color(0.44, 0.54, 0.66)
	return t


## 余烬：暖橙 + 烟熏黑，像燃烧的炉膛。
static func ember() -> UITheme:
	var t := UITheme.new()
	t.preset_key = "ember"
	t.preset_name = "余烬"
	t.description = "烟熏玻璃 + 熔金橙，暖色高光更贴近火属性地下城。"
	t.accent = Color(1.0, 0.55, 0.22)
	t.accent_soft = Color(1.0, 0.76, 0.4)
	t.accent_deep = Color(0.32, 0.11, 0.04)
	t.gold = Color(1.0, 0.78, 0.38)
	t.gold_soft = Color(1.0, 0.93, 0.7)
	t.glass_tint = Color(0.085, 0.045, 0.025)
	t.glass_alpha = 0.8
	t.glass_blur = 7.5
	t.glass_noise = 0.035
	t.glass_brightness = 0.86
	t.glass_saturation = 0.95
	t.glass_vignette = 0.38
	t.frame_color = Color(0.72, 0.5, 0.32, 0.55)
	t.frame_highlight = Color(1.0, 0.8, 0.5, 0.35)
	t.title_top = Color(0.3, 0.14, 0.06, 0.96)
	t.title_bottom = Color(0.12, 0.05, 0.02, 0.9)
	t.slot_bg = Color(0.09, 0.045, 0.02, 0.7)
	t.slot_bg_alt = Color(0.12, 0.06, 0.03, 0.6)
	t.slot_border = Color(0.66, 0.44, 0.26, 0.35)
	t.text_primary = Color(1.0, 0.94, 0.87)
	t.text_secondary = Color(0.92, 0.78, 0.66)
	t.text_muted = Color(0.66, 0.52, 0.44)
	t.text_gold = Color(1.0, 0.88, 0.56)
	return t


## 翡翠：青玉 + 墨绿，冷绿玻璃，适合精灵/森林场景。
static func jade() -> UITheme:
	var t := UITheme.new()
	t.preset_key = "jade"
	t.preset_name = "翡翠"
	t.description = "墨绿玻璃 + 青玉高光，低饱和、偏自然的配色。"
	t.accent = Color(0.31, 0.95, 0.74)
	t.accent_soft = Color(0.55, 0.98, 0.84)
	t.accent_deep = Color(0.03, 0.27, 0.21)
	t.gold = Color(0.86, 0.8, 0.52)
	t.gold_soft = Color(0.96, 0.94, 0.72)
	t.glass_tint = Color(0.02, 0.075, 0.06)
	t.glass_alpha = 0.79
	t.glass_blur = 6.0
	t.glass_noise = 0.025
	t.glass_brightness = 0.9
	t.glass_saturation = 0.8
	t.glass_vignette = 0.32
	t.frame_color = Color(0.4, 0.66, 0.56, 0.55)
	t.frame_highlight = Color(0.7, 1.0, 0.88, 0.3)
	t.title_top = Color(0.06, 0.24, 0.19, 0.96)
	t.title_bottom = Color(0.02, 0.1, 0.08, 0.9)
	t.slot_bg = Color(0.015, 0.07, 0.055, 0.72)
	t.slot_bg_alt = Color(0.02, 0.09, 0.07, 0.62)
	t.slot_border = Color(0.32, 0.58, 0.48, 0.35)
	t.text_primary = Color(0.9, 1.0, 0.96)
	t.text_secondary = Color(0.68, 0.9, 0.82)
	t.text_muted = Color(0.42, 0.62, 0.56)
	return t


## 紫罗兰：暗紫 + 洋红，偏“异界/次元”气质。
static func violet() -> UITheme:
	var t := UITheme.new()
	t.preset_key = "violet"
	t.preset_name = "紫罗兰"
	t.description = "暗紫玻璃 + 洋红高光，适合异界、次元裂缝类场景。"
	t.accent = Color(0.76, 0.52, 1.0)
	t.accent_soft = Color(0.55, 0.72, 1.0)
	t.accent_deep = Color(0.2, 0.09, 0.36)
	t.gold = Color(0.92, 0.76, 0.98)
	t.gold_soft = Color(1.0, 0.9, 1.0)
	t.glass_tint = Color(0.06, 0.035, 0.11)
	t.glass_alpha = 0.8
	t.glass_blur = 7.0
	t.glass_noise = 0.03
	t.glass_brightness = 0.88
	t.glass_saturation = 0.9
	t.glass_vignette = 0.35
	t.frame_color = Color(0.56, 0.44, 0.72, 0.55)
	t.frame_highlight = Color(0.86, 0.72, 1.0, 0.33)
	t.title_top = Color(0.19, 0.1, 0.32, 0.96)
	t.title_bottom = Color(0.07, 0.035, 0.13, 0.9)
	t.slot_bg = Color(0.055, 0.03, 0.1, 0.72)
	t.slot_bg_alt = Color(0.07, 0.04, 0.12, 0.62)
	t.slot_border = Color(0.5, 0.4, 0.66, 0.35)
	t.text_primary = Color(0.96, 0.92, 1.0)
	t.text_secondary = Color(0.82, 0.74, 0.95)
	t.text_muted = Color(0.58, 0.5, 0.7)
	return t
