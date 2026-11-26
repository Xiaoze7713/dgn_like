## 哥布林（怪物）
##
## .mob 里给的动作名不是 DNF 标准名：waiting / move / sit / damage / down / overturn / attack
## 行为：待机 → 玩家进了视野就追 → 贴身就砍 → 挨打有硬直 → 血空倒地
##
## **数值全部来自 `.mob`**（不再有 mock 常量）：
##   血量    [ability category][hp max] 的分类倍率（70 → ×0.6 刻度 = 42）
##   移速    [move speed] 300 → 78 px/s（与玩家同一套 SPEED_SCALE）
##   视野    [sight] 300
##   攻速    [attack delay] 1500ms
##   宽度    [width] 40 → 受击体积与贴身距离
##   击退    .atk 的 [push aside]
class_name Sf85Monster
extends Sf85Actor

## 与 Sf85Player 共用同一套「DNF 单位 → 像素」标定
const SPEED_SCALE := 0.26
const VERTICAL_RATIO := 0.68
## `.mob` 的分类倍率 → demo 血量刻度（70 × 0.6 = 42，约三刀）
const HP_SCALE := 0.6
## `.atk [push aside]` → 像素位移；玩家普攻 30 → 12 px
const PUSH_SCALE := 0.4
## `.mob` 里没有「攻击力」字段（引擎按等级表算），这里保留一个 demo 占位值
const ATTACK_DAMAGE := 6.0

var hp := 40.0
var hp_max := 40.0
var speed := 110.0
var sight := 300.0
var reach := 56.0
var attack_cd := 1.6
var attack_damage := ATTACK_DAMAGE
var push_force := 0.0
var mob_info: Dictionary = {}

var target: Node2D = null
var state := "idle"            ## idle / chase / attack / hit / down / dead
var _cd := 0.0
var _hit_timer := 0.0
var _dead := false
var _dying := false           ## 这次倒地是不是死亡（挑飞只是倒地，hp>0 会爬起来）
var name_text := ""

func _ready() -> void:
	anim_finished.connect(_on_anim_finished)
	if has_anim("waiting"):
		play("waiting")
	elif has_anim("stay"):
		play("stay")

## 用 .mob 的数据初始化（def 里带 mob 段，见 Sf85Assets.actor）
func setup(actor_def: Dictionary, asset_lib: Sf85Assets) -> void:
	super.setup(actor_def, asset_lib)
	mob_info = actor_def.get("mob", {})
	speed = float(mob_info.get("move_speed", 300.0)) * SPEED_SCALE
	sight = float(mob_info.get("sight", 300.0))
	attack_cd = float(mob_info.get("attack_delay", 1500.0)) / 1000.0
	hp_max = maxf(1.0, float(mob_info.get("hp_mult", 70.0)) * HP_SCALE)
	hp = hp_max
	reach = body_width() * 0.9 + 20.0
	name_text = str(mob_info.get("name", actor_def.get("name", "")))

func _physics_process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_hit_timer = maxf(0.0, _hit_timer - delta)
	if _dead or target == null:
		return
	var dx := target.global_position.x - global_position.x
	var dy := target.global_position.y - global_position.y

	match state:
		"idle":
			if absf(dx) < sight and absf(dy) < 120.0:
				state = "chase"
		"chase":
			if absf(dx) > reach:
				var dir := signf(dx)
				global_position.x += dir * speed * delta
				global_position.y = move_toward(global_position.y, target.global_position.y,
					speed * VERTICAL_RATIO * delta)
				scale.x = -dir * absf(scale.x)
				if has_anim("move"):
					play("move")
			elif _cd <= 0.0:
				state = "attack"
				_cd = attack_cd
				if has_anim("attack"):
					play("attack", true)
				else:
					state = "idle"

## 受击：伤害、击退（push_aside）、是否挑飞（attack direction = lift up）
func take_hit(damage: float, from_x: float, launch := false, push := 0.0) -> void:
	if _dead:
		return
	hp -= damage
	var dir := signf(global_position.x - from_x)
	if dir == 0.0:
		dir = 1.0
	global_position.x += dir * maxf(push, 8.0) * PUSH_SCALE
	if hp <= 0.0:
		_dead = true
		_dying = true
		state = "down"
		if has_anim("down"):
			play("down", true)
		elif has_anim("overturn"):
			play("overturn", true)
		return
	if launch:
		# 挑飞/浮空（`.atk [attack direction] hit lift up`）：走 down 动作，
		# hp 还活着的话播完会爬起来（见 _on_anim_finished）
		state = "down"
		_hit_timer = 1.2
		if has_anim("down"):
			play("down", true)
		elif has_anim("damage"):
			play("damage", true)
	else:
		state = "hit"
		_hit_timer = 0.35
		if has_anim("damage"):
			play("damage", true)
	modulate = Color(1.6, 0.9, 0.9)

func _on_anim_finished(anim_name: String) -> void:
	if state == "attack":
		_try_hit_target()
		state = "idle"
		if has_anim("waiting"):
			play("waiting")
	elif state == "hit":
		state = "chase"
		modulate = Color(1, 1, 1)
	elif state == "down":
		if _dying:
			state = "dead"
		else:
			state = "chase"
			modulate = Color(1, 1, 1)
			if has_anim("waiting"):
				play("waiting")

func is_dead() -> bool:
	return _dead and state == "dead"


## 攻击动作播完、且目标还在身前时，对玩家造成一次伤害。
func _try_hit_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	var dx := absf(target.global_position.x - global_position.x)
	var dy := absf(target.global_position.y - global_position.y)
	if dx > reach + target.body_width() * 0.5 + 10.0 or dy > 90.0:
		return
	if target.has_method("take_damage"):
		target.take_damage(attack_damage, global_position.x)
