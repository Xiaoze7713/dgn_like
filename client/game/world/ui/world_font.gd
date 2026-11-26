class_name WorldFont
extends RefCounted
## 世界层 UI 的字体：PVF 名字是中文，Godot 默认字体没有 CJK 字形。
## 用 SystemFont 走系统字体回退，Windows / WSLg 都能显示。

const FAMILY := "Noto Sans CJK SC, Source Han Sans SC, Microsoft YaHei, WenQuanYi Zen Hei"


static func make(weight := 400) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FAMILY.split(","))
	for i in f.font_names.size():
		f.font_names[i] = f.font_names[i].strip_edges()
	f.allow_system_fallback = true
	f.font_weight = weight
	return f
