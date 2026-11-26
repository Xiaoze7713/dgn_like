## 一块磨砂玻璃面板：阴影 + 屏幕模糊 + 圆角描边。
##
## 子节点顺序：Shadow（画在外面的投影）→ Glass（Shader 背景）→ content。
## 内容请加到 `content` 下；`content` 本身是 ignore 鼠标的全屏 Control。
class_name UIPanel
extends Control

const SHADER_PATH := "res://ui/shaders/frosted_glass.gdshader"

@export var shadow_enabled := true
## 玻璃浓度倍率：0 = 全透，1 = 主题原值，1.5 = 更浓。
@export_range(0.0, 2.0, 0.01) var glass_mul := 1.0
## 给窗口内的子面板用：不再重复压暗，只保留模糊/描边。
@export var nested := false

var content: Control
var glass: ColorRect
var shadow: Panel

var _mat: ShaderMaterial
var _shadow_box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false

	shadow = Panel.new()
	shadow.name = "Shadow"
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = false
	add_child(shadow)
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	glass = ColorRect.new()
	glass.name = "Glass"
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.color = Color.WHITE
	_mat = ShaderMaterial.new()
	var sh: Shader = load(SHADER_PATH)
	if sh != null:
		_mat.shader = sh
	glass.material = _mat
	add_child(glass)
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	content = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	theme_changed.connect(_sync_theme)
	resized.connect(_update_uniforms)
	_sync_theme()


func _sync_theme() -> void:
	if _mat == null:
		return
	var d := UIKit.data(self)
	if d == null:
		return

	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("corner_radius", float(d.corner_radius))
	_mat.set_shader_parameter("border_width", float(d.border_width))
	_mat.set_shader_parameter("border_color", d.frame_color)
	_mat.set_shader_parameter("border_highlight", d.frame_highlight)
	_mat.set_shader_parameter("tint", d.glass_tint)
	var alpha := d.glass_alpha
	if nested:
		alpha *= 0.55
	_mat.set_shader_parameter("tint_alpha", clampf(alpha * glass_mul, 0.0, 0.96))
	_mat.set_shader_parameter("blur", d.glass_blur)
	_mat.set_shader_parameter("noise_amount", d.glass_noise)
	_mat.set_shader_parameter("brightness", d.glass_brightness)
	_mat.set_shader_parameter("saturation", d.glass_saturation)
	_mat.set_shader_parameter("vignette", d.glass_vignette)
	_mat.set_shader_parameter("shine", 0.10)
	_mat.set_shader_parameter("inner_glow", 0.06)

	_shadow_box = StyleBoxFlat.new()
	_shadow_box.bg_color = Color(0, 0, 0, 0)
	_shadow_box.shadow_color = d.shadow_color
	_shadow_box.shadow_size = int(maxf(2.0, d.shadow_size * 4.0))
	_shadow_box.shadow_offset = Vector2(0, 6)
	_shadow_box.set_corner_radius_all(d.corner_radius)
	_shadow_box.anti_aliasing = true
	shadow.add_theme_stylebox_override("panel", _shadow_box)
	shadow.visible = shadow_enabled
	queue_redraw()


func _update_uniforms() -> void:
	if _mat != null:
		_mat.set_shader_parameter("rect_size", size)
