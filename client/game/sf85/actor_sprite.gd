## 一个多图层动画角色（鬼剑士 / 哥布林 通用）
##
## 每个图层一个 Sprite2D，按 .equ 里的 `[layer variation]` z 排层；
## 每帧 = 一张 PNG + 相对脚底原点的偏移（x, y 已经是「动画偏移 + 图集偏移」的和）。
##
## 坐标系：节点 position = 脚底（精灵原点）。x 向右、y 向下（y 同时也是景深）。
class_name Sf85Actor
extends Node2D

signal anim_finished(anim_name: String)
signal frame_changed(anim_name: String, index: int)

@export var anim_speed := 1.0

var def: Dictionary = {}                 ## actors.<id>
var assets: Sf85Assets = null
var anim := ""                           ## 当前动作名
var frame_index := 0
var playing := false
var loop := false
var _timer := 0.0
var visual_offset := Vector2.ZERO   ## 额外的绘制偏移（跳跃抬升等）
var _layers: Array[Sprite2D] = []
var _frames_pos: Array = []
var _layer_defs: Array = []

func setup(actor_def: Dictionary, asset_lib: Sf85Assets) -> void:
	def = actor_def
	assets = asset_lib
	for c in get_children():
		c.queue_free()
	_layers.clear()
	_layer_defs = actor_def.get("layers", [])
	for ld in _layer_defs:
		var s := Sprite2D.new()
		s.centered = false
		s.z_index = int(ld.get("z", 0) / 100.0)
		add_child(s)
		_layers.append(s)
	_frames_pos.clear()
	for i in _layers.size():
		_frames_pos.append(Vector2.ZERO)

## 这个角色的动作表：{name: {frames, loop, total_ms}}
func anims() -> Dictionary:
	# 各层帧数一致，用帧数最多的那层作为时间轴
	var best: Dictionary = {}
	for ld in _layer_defs:
		for name in ld.get("anims", {}):
			var a: Dictionary = ld["anims"][name]
			if not best.has(name) or a["frames"].size() > best[name]["frames"].size():
				best[name] = a
	return best

func has_anim(name: String) -> bool:
	return anims().has(name)

func current_frames() -> Array:
	var best: Array = []
	for ld in _layer_defs:
		var a: Dictionary = ld.get("anims", {}).get(anim, {})
		if a.get("frames", []).size() > best.size():
			best = a["frames"]
	return best

func total_frames() -> int:
	return current_frames().size()

func play(name: String, restart := false) -> void:
	if anim == name and not restart:
		return
	if not has_anim(name):
		return
	anim = name
	frame_index = 0
	_timer = 0.0
	playing = true
	loop = bool(anims()[name].get("loop", false))
	_apply_frame()
	frame_changed.emit(anim, frame_index)

func stop() -> void:
	playing = false

func _process(delta: float) -> void:
	_refresh_offsets()
	if not playing or anim == "":
		return
	var frames := current_frames()
	if frames.is_empty():
		return
	_timer += delta * 1000.0 * anim_speed
	var delay: float = maxf(16.0, float(frames[frame_index].get("delay", 100)))
	while _timer >= delay:
		_timer -= delay
		frame_index += 1
		if frame_index >= frames.size():
			if loop:
				frame_index = 0
			else:
				frame_index = frames.size() - 1
				playing = false
				_apply_frame()
				anim_finished.emit(anim)
				return
		_apply_frame()
		frame_changed.emit(anim, frame_index)
		delay = maxf(16.0, float(frames[frame_index].get("delay", 100)))

## 每帧把「跳跃抬升」等绘制偏移同步到所有层（不依赖动画换帧）
func _refresh_offsets() -> void:
	for i in _layers.size():
		if i < _frames_pos.size():
			_layers[i].position = _frames_pos[i] + visual_offset

func _apply_frame() -> void:
	for i in _layers.size():
		var ld: Dictionary = _layer_defs[i]
		var a: Dictionary = ld.get("anims", {}).get(anim, {})
		var frames: Array = a.get("frames", [])
		var s: Sprite2D = _layers[i]
		if frame_index >= frames.size():
			s.visible = false
			continue
		var f: Dictionary = frames[frame_index]
		# 位置 = .ani 的帧偏移 + 该帧在本 .img 画布里的落位（frame_info 已合成）
		var info := assets.frame_info(f)
		if info.is_empty():
			s.visible = false
			continue
		s.texture = info["tex"]
		var p := Vector2(float(info["x"]), float(info["y"]))
		s.position = p + visual_offset
		_frames_pos[i] = p
		s.visible = true

## 当前帧的判定盒（世界坐标），kind = "attack" / "damage"
##
## **跨层收集**：DNF 把普攻的攻击盒放在**武器层**的 `.ani` 里
## （`character/swordman/animation/weaponcomboshort1.ani` 一帧都没有，
##  `.../weapon/ssword/sswdc/weaponcomboshort1.ani` 的 f2 才有 `[15,-12,44,104,25,59]`），
## 所以判定必须遍历所有图层，不能只看身体那一层。
## 盒子的 6 个整数 = [x, y, ?, w, h, ?]，以脚底原点为基准、面朝右。
func boxes(kind: String) -> Array:
	var out: Array = []
	var flipped := scale.x < 0.0
	for ld in _layer_defs:
		var frames: Array = ld.get("anims", {}).get(anim, {}).get("frames", [])
		if frames.is_empty():
			continue
		var idx := mini(frame_index, frames.size() - 1)
		for b in frames[idx].get("boxes", []):
			if b.get("kind", "") != kind:
				continue
			var box: Array = b.get("box", [])
			if box.size() < 5:
				continue
			var bx: float = float(box[0])
			var by: float = float(box[1])
			var bw: float = float(box[3])
			var bh: float = float(box[4])
			if flipped:
				bx = -bx - bw
			out.append(Rect2(global_position.x + bx, global_position.y + by, bw, bh))
	return out


## 身体碰撞宽度（来自 .chr / .mob 的 `[width]`，第一个数）
func body_width() -> float:
	var stats: Dictionary = def.get("stats", {}) if def.has("stats") else def.get("mob", {})
	return float(stats.get("width", 40.0))


## 受击体积：默认按身体宽高、脚底对齐
func body_rect() -> Rect2:
	var w := body_width()
	var h := maxf(64.0, w * 2.0)
	return Rect2(global_position.x - w * 0.5, global_position.y - h, w, h)
