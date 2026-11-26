## 角色预览：用真实 sf85 资产（Sf85Assets.actor("player")）画纸娃娃。
##
## 没有资产时退化成剪影，方便单独调 UI。
class_name UICharacterPreview
extends Control

@export var show_stage := true
@export var caption := "角色预览"

var _actor: Dictionary = {}
var _assets: Sf85Assets = null
var _bbox := Rect2()
var _origin := Vector2.ZERO
var _scale := 1.0
var _elapsed_ms := 0.0
var _infos := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_refresh_layout)
	set_process(false)
	queue_redraw()


func set_actor(actor: Dictionary, assets: Sf85Assets) -> void:
	_actor = actor
	_assets = assets
	_infos.clear()
	_elapsed_ms = 0.0
	_refresh_layout()
	set_process(not _actor.is_empty() and _assets != null)
	queue_redraw()


func clear_actor() -> void:
	_actor = {}
	_assets = null
	_infos.clear()
	set_process(false)
	queue_redraw()


func _refresh_layout() -> void:
	if _actor.is_empty() or _assets == null:
		return
	var bbox := Rect2()
	var first := true
	for layer in _actor.get("layers", []):
		var a: Dictionary = layer.get("anims", {}).get("stay", {})
		var frames: Array = a.get("frames", [])
		if frames.is_empty():
			continue
		var info := _assets.frame_info(frames[0])
		if info.is_empty():
			continue
		var r := Rect2(float(info.x), float(info.y), float(info.w), float(info.h))
		bbox = r if first else bbox.merge(r)
		first = false
	if bbox.size.x <= 0.0 or bbox.size.y <= 0.0:
		return
	_bbox = bbox
	var avail := Vector2(maxf(10, size.x - 28), maxf(10, size.y - 64))
	_scale = minf(avail.x / maxf(1.0, bbox.size.x), avail.y / maxf(1.0, bbox.size.y))
	_scale = minf(_scale, 2.2)
	var draw_size := bbox.size * _scale
	var target := Vector2(size.x * 0.5, size.y * 0.5 + 4)
	_origin = target - bbox.get_center() * _scale


func _process(delta: float) -> void:
	if _actor.is_empty():
		return
	_elapsed_ms += delta * 1000.0
	queue_redraw()


func _layer_frame_index(a: Dictionary) -> int:
	var frames: Array = a.get("frames", [])
	if frames.size() <= 1:
		return 0
	var total := 0
	for f in frames:
		total += maxi(1, int(f.get("delay", 120)))
	var t := fmod(_elapsed_ms, float(total))
	var acc := 0
	for i in frames.size():
		acc += maxi(1, int(frames[i].get("delay", 120)))
		if t < float(acc):
			return i
	return frames.size() - 1


func _layer_infos(layer_name: String, frames: Array) -> Array:
	if _infos.has(layer_name):
		return _infos[layer_name]
	var arr := []
	arr.resize(frames.size())
	for i in frames.size():
		arr[i] = _assets.frame_info(frames[i])
	_infos[layer_name] = arr
	return arr


func _draw() -> void:
	var d := UIKit.data(self)
	if d == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	if show_stage:
		_draw_stage(d, r)

	if _actor.is_empty() or _assets == null:
		_draw_silhouette(d, r)
	else:
		var layers: Array = _actor.get("layers", []).duplicate()
		layers.sort_custom(func(a, b): return int(a.get("z", 0)) < int(b.get("z", 0)))
		for layer in layers:
			var a: Dictionary = layer.get("anims", {}).get("stay", {})
			var frames: Array = a.get("frames", [])
			if frames.is_empty():
				continue
			var idx := _layer_frame_index(a)
			var infos := _layer_infos(str(layer.get("name", "")), frames)
			if idx >= infos.size() or infos[idx] == null or infos[idx].is_empty():
				continue
			var info: Dictionary = infos[idx]
			var pos := _origin + Vector2(float(info.x), float(info.y)) * _scale
			var sz := Vector2(float(info.w), float(info.h)) * _scale
			draw_texture_rect(info.tex, Rect2(pos, sz), false)

	if caption != "":
		UIKit.text(self, caption, Rect2(0, size.y - 22, size.x, 16), UIKit.font(self, false),
				11, UIKit.a(d.text_muted, 0.8), UIKit.ALIGN_CENTER)


func _draw_stage(d: UITheme, r: Rect2) -> void:
	UIKit.round_rect(self, r, UIKit.a(d.slot_bg, 0.35), 8,
			UIKit.a(d.frame_color, 0.28), 1)

	var center := Vector2(size.x * 0.5, size.y * 0.54)
	# 背后的柔光（同心圆叠加）
	for i in 9:
		var t := float(i) / 9.0
		draw_circle(center, 42.0 + t * 92.0, UIKit.a(d.accent, 0.008 + (1.0 - t) * 0.012))

	# 光柱
	var beam := PackedVector2Array([
		Vector2(center.x - 34, 0),
		Vector2(center.x + 34, 0),
		Vector2(center.x + 76, size.y - 30),
		Vector2(center.x - 76, size.y - 30),
	])
	draw_polygon(beam, PackedColorArray([
		UIKit.a(d.accent, 0.055), UIKit.a(d.accent, 0.055),
		UIKit.a(d.accent, 0.0), UIKit.a(d.accent, 0.0),
	]))

	# 圆环
	draw_arc(center, 62, PI * 0.15, PI * 0.85, 40, UIKit.a(d.accent, 0.14), 1.0, true)
	draw_arc(center, 84, PI * 1.1, PI * 1.9, 40, UIKit.a(d.gold, 0.10), 1.0, true)

	# 底座
	var py := size.y * 0.86
	draw_set_transform(Vector2(size.x * 0.5, py), 0.0, Vector2(1.0, 0.26))
	draw_circle(Vector2.ZERO, 58, Color(0, 0, 0, 0.45))
	draw_circle(Vector2.ZERO, 48, UIKit.a(d.accent_deep, 0.55))
	draw_arc(Vector2.ZERO, 49, 0, TAU, 48, UIKit.a(d.accent, 0.35), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 左右小符文
	for side in [-1, 1]:
		var bx: float = center.x + float(side) * 96.0
		for i in 3:
			var by: float = size.y * 0.35 + i * 34.0
			UIKit.diamond(self, Vector2(bx, by), 3.0, UIKit.a(d.accent, 0.22 - i * 0.05))
			draw_line(Vector2(bx - float(side) * 8, by), Vector2(bx - float(side) * 22, by),
					UIKit.a(d.frame_color, 0.18), 1.0, true)


func _draw_silhouette(d: UITheme, r: Rect2) -> void:
	var cx := size.x * 0.5
	var base := size.y * 0.84
	var col := UIKit.a(d.text_muted, 0.28)
	# 头
	draw_circle(Vector2(cx, base - 150), 26, col)
	# 躯干
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 26, base - 122), Vector2(cx + 26, base - 122),
		Vector2(cx + 36, base - 42), Vector2(cx - 36, base - 42),
	]), col)
	# 腿
	draw_rect(Rect2(cx - 30, base - 44, 20, 52), col)
	draw_rect(Rect2(cx + 10, base - 44, 20, 52), col)
	# 武器
	draw_line(Vector2(cx + 44, base - 40), Vector2(cx + 92, base - 128),
			UIKit.a(d.gold, 0.45), 4.0, true)
	UIKit.text(self, "未载入角色资产", Rect2(0, size.y * 0.5 + 24, size.x, 18),
			UIKit.font(self, false), 11, UIKit.a(d.text_muted, 0.55), UIKit.ALIGN_CENTER)
