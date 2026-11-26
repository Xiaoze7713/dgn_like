class_name WorldPlayer
extends Node2D
## 城镇/副本里的角色：位置 = 脚底中心，移动受 PassGrid 约束。
##
## 城镇特例：鬼剑士（Ghostblade）只保留 stay/move 两段走路动画，不接攻击/跑步。
## latest PVF 的 `character/swordman/animation/move.ani` 只给 body 皮肤层；
## 装备层没有可用的 `.lay`，但同编号的 avatar NPK 图都在，且所有层共用 224 画布，
## 所以这里把 body 的 AniDef 复制成 5 层，换帧图后同 index 叠画（skin/pants/shoes/coat/hair）。
## 任何一层缺图就跳过该层；全缺时回退到原来的色块占位，不影响移动/碰撞。

const SPEED_SCALE := 0.26
const BODY_LOOK := 0
const MOVE_ANI := "character/swordman/animation/move.ani"
const STAY_ANI := "character/swordman/animation/stay.ani"
# 同一帧号、同一画布坐标；从里到外：skin → pants → shoes → coat → hair。
const LAYER_IMAGES := [
	"character/swordman/equipment/avatar/skin/sm_body%04d.img",
	"character/swordman/equipment/avatar/pants/sm_pants%04da.img",
	"character/swordman/equipment/avatar/shoes/sm_shoes%04da.img",
	"character/swordman/equipment/avatar/coat/sm_coat%04da.img",
	"character/swordman/equipment/avatar/hair/sm_hair%04da.img",
]

var move_speed := 850.0
var pass_grid: PassGrid
var facing := 1
var moving := false

var _anim_t := 0.0
var _visual_ready := false
var _move_sprites: Array[AniSprite] = []
var _stay_sprites: Array[AniSprite] = []
var _visual: Node2D


func setup_visual(content: LivePvfContent, store: NpkStore) -> void:
	if content == null or store == null:
		return
	var src := content.ani(MOVE_ANI)
	if src == null or src.is_empty():
		LogUtil.warn("[WorldPlayer] 鬼剑士 move 动画不可用，保留占位")
		return
	var stay_src := content.ani(STAY_ANI)
	if stay_src == null or stay_src.is_empty():
		stay_src = src
	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)
	for template in LAYER_IMAGES:
		var move_def := _layer_anim(src, str(template), BODY_LOOK)
		var stay_def := _layer_anim(stay_src, str(template), BODY_LOOK)
		if move_def == null or move_def.is_empty():
			continue
		var ms := AniSprite.new()
		_visual.add_child(ms)
		ms.setup(move_def, store, Vector2.ZERO, true, true)
		ms.visible = false
		_move_sprites.append(ms)
		var ss := AniSprite.new()
		if stay_def == null or stay_def.is_empty():
			ss.free()
			continue
		_visual.add_child(ss)
		ss.setup(stay_def, store, Vector2.ZERO, true, true)
		ss.visible = true
		_stay_sprites.append(ss)
	if _move_sprites.is_empty():
		_visual.queue_free()
		_visual = null
		LogUtil.warn("[WorldPlayer] 鬼剑士层图都不可用，保留占位")
		return
	_visual_ready = true
	queue_redraw()


func _layer_anim(src: AniDef, template: String, look: int) -> AniDef:
	if src == null:
		return null
	var frames: Array = []
	var suffix := "%04d" % look
	for f in src.frames:
		var c: Dictionary = f.duplicate()
		c["img"] = template.replace("%04d", suffix)
		frames.append(c)
	return AniDef.from_dict({"loop": 1 if src.loop else 0, "frames": frames})


func speed_px() -> float:
	return move_speed * SPEED_SCALE


func input_dir() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		v.x -= 1.0
	if Input.is_action_pressed("move_right"):
		v.x += 1.0
	if Input.is_action_pressed("move_up"):
		v.y -= 1.0
	if Input.is_action_pressed("move_down"):
		v.y += 1.0
	return v.normalized()


func _process(delta: float) -> void:
	var v := input_dir()
	moving = v != Vector2.ZERO
	if v.x != 0.0:
		facing = 1 if v.x > 0.0 else -1
	if moving:
		var delta_move := v * speed_px() * delta
		if pass_grid != null:
			position = pass_grid.move(position, delta_move)
		else:
			position += delta_move
		_anim_t += delta * 8.0
	else:
		_anim_t = 0.0
	if _visual_ready:
		_visual.scale.x = float(facing)
		for sp in _move_sprites:
			sp.visible = moving
		for sp in _stay_sprites:
			sp.visible = not moving
		z_index = clampi(int(position.y), -4096, 4096)
	queue_redraw()


func _draw() -> void:
	if _visual_ready:
		return
	var bob := sin(_anim_t) * 2.0 if moving else 0.0
	var body := Rect2(-9, -34 + bob, 18, 30)
	draw_rect(body, Color(0.85, 0.72, 0.55))
	# 头
	draw_circle(Vector2(0, -40 + bob), 8.0, Color(0.95, 0.83, 0.68))
	# 朝向：一条小刘海指示左右
	draw_rect(Rect2(float(facing) * 3.0 - 1.5, -44 + bob, 3, 5), Color(0.15, 0.1, 0.1))
	# 脚底阴影，便于判断脚下格子
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(0, 0), 5.0, Color(0, 0, 0, 0.25))
