## 主题化按钮：normal / accent / ghost，样式全部来自 UITheme。
class_name UIButton
extends Button

@export_enum("normal", "accent", "ghost") var variant := "normal":
	set(v):
		variant = v
		_apply_variant()

@export var icon_glyph := ""


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_variant()


func _apply_variant() -> void:
	match variant:
		"accent":
			theme_type_variation = &"AccentButton"
		"ghost":
			theme_type_variation = &"GhostButton"
		_:
			theme_type_variation = &""
	if is_inside_tree():
		queue_redraw()
