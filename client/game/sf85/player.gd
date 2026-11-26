## 鬼剑士（玩家）
##
## 操作：← → ↑ ↓ 移动 / C 跳 / X 普攻（三连）/ Z 上挑
## 动画：move / stay / jump / weaponcomboshort1..3 / attack2（上挑）
##
## **所有数值与判定都来自 PVF 源文件**（不再有 mock 常量）：
##   移速/跳跃  character/swordman/swordman.chr  [move speed]/[jump power]
##   攻击力     同上 [physical attack] + 武器 .equ [equipment physical attack]
##   攻击盒     武器层 .ani 的 [attack box]（见 Sf85Actor.boxes）
##   伤害倍率   character/swordman/attackinfo/attack{1,2,3}.atk  [damage bonus]
##   击退/浮空  同上 [push aside]/[lift up]/[attack direction]
##   上挑       skill/swordman/upperslash.skl 的 [consume mp]/[cool time]/[static data]
class_name Sf85Player
extends Sf85Actor

signal hit_landed(boxes: Array, damage: float, launch: bool, push: float)
signal damaged(amount: float, world_pos: Vector2)

## DNF 单位 → 像素的标定（.chr 里的 speed 是引擎单位，不是像素/秒）
##   [move speed] 850 → 221 px/s：按当前在 1792 宽房间里跑一屏约 8 s 标定
##   [jump power] 430 → 330 px/s：按跳跃最高点约 45 px 标定
const SPEED_SCALE := 0.26
const JUMP_SCALE := 0.767
## DNF 里前后（上下）移动比左右慢，配置里没单独给，按 0.68 处理
const VERTICAL_RATIO := 0.68
## 重力在配置里没有（引擎侧常量），标定自跳跃高度
const GRAVITY := 1100.0
## 面板攻击力 → demo 血量的刻度换算。
## 引擎的完整伤害公式（等级差、防御减伤、抗性、暴击）没有公开，
## 这里把「面板攻击力 × 倍率」线性映射到 demo 的血条刻度：1 点伤害 = 33 点面板。
const DAMAGE_SCALE := 0.03
const COMBO := ["weaponcomboshort1", "weaponcomboshort2", "weaponcomboshort3"]
const COMBO_WINDOW := 0.85
## 上挑现在借用 attack2 的动作（sf85 里没有 upperslash.ani，只有 upperslashafter）
const SKILL_ANIM := "attack2"

var facing := 1
var z_height := 0.0
var z_vel := 0.0
var state := "idle"               ## idle / move / jump / attack / skill / hit
var combo_index := -1
var _combo_timer := 0.0
var _next_combo := 0            ## 收招后窗口内再按 X 时要接的那一段
var _skill_cd := 0.0
var _hit_frames := {}             ## anim -> 已触发判定的帧号集合
var room := Node2D.new()          ## 由房间注入，用来查通行/边界

# ---- 从 PVF 读到的数值（setup 时填）----
var speed_x := 220.0
var speed_y := 150.0
var jump_v := 330.0
var attack_power := 0.0
var attack_chain: Array = []      ## [{damage_bonus, push_aside, lift_up, direction, ...}]
var skill_info: Dictionary = {}
var mp := 0.0
var mp_max := 0.0
var hp := 0.0
var hp_max := 0.0
var _invuln := 0.0

func _ready() -> void:
	anim_finished.connect(_on_anim_finished)

## 覆盖基类 setup：装好动画后把 .chr 里的数值读进来
func setup(actor_def: Dictionary, asset_lib: Sf85Assets) -> void:
	super.setup(actor_def, asset_lib)
	_read_stats()


func _read_stats() -> void:
	var stats: Dictionary = def.get("stats", {})
	speed_x = float(stats.get("move_speed", 850.0)) * SPEED_SCALE
	speed_y = speed_x * VERTICAL_RATIO
	jump_v = float(stats.get("jump_power", 430.0)) * JUMP_SCALE
	hp_max = float(stats.get("hp_max", 180.0))
	hp = hp_max
	mp_max = float(stats.get("mp_max", 140.0))
	mp = mp_max
	attack_power = float(def.get("attack_power", 0.0))
	attack_chain = def.get("attack_chain", [])
	skill_info = def.get("skill", {})


# ---------------------------------------------------------------------------
func can_act() -> bool:
	return state == "idle" or state == "move"

func _physics_process(delta: float) -> void:
	_combo_timer = maxf(0.0, _combo_timer - delta)
	_skill_cd = maxf(0.0, _skill_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)
	# 演示用：MP 缓慢回蓝，让 HUD 的蓝条是活的
	mp = minf(mp_max, mp + 4.0 * delta)

	# 跳跃
	if z_height > 0.0 or z_vel > 0.0:
		z_vel -= GRAVITY * delta
		z_height += z_vel * delta
		if z_height <= 0.0:
			z_height = 0.0
			z_vel = 0.0
			if state == "jump":
				state = "idle"
				play("stay")
	_update_offset()

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1.0

	if input_dir.x != 0.0:
		facing = 1 if input_dir.x > 0.0 else -1
		scale.x = float(facing) * absf(scale.x)

	if can_act() and input_dir != Vector2.ZERO:
		var step := Vector2(input_dir.x * speed_x, input_dir.y * speed_y) * delta
		var want := position + step
		if room != null and room.has_method("is_walkable"):
			if room.is_walkable(Vector2(want.x, position.y)):
				position.x = want.x
			if room.is_walkable(Vector2(position.x, want.y)):
				position.y = want.y
		else:
			position = want
		play("move")
	elif can_act():
		play("stay")

	if Input.is_action_just_pressed("jump") and can_act() and z_height == 0.0:
		state = "jump"
		z_vel = jump_v
		z_height = 0.01
		play("jump", true)
		# 跳跃动画的 delay 里有 20000 这种"定格"值，按空中时间重新配速
		var jd: Dictionary = anims().get("jump", {})
		if not jd.is_empty():
			var airtime_ms := 2.0 * jump_v / GRAVITY * 1000.0
			anim_speed = clampf(float(jd.get("total_ms", airtime_ms)) / maxf(airtime_ms, 1.0), 1.0, 12.0)

	if Input.is_action_just_pressed("attack"):
		_attack()

	if Input.is_action_just_pressed("skill") and _skill_cd <= 0.0 and _can_use_skill() \
			and (can_act() or state == "jump" or state == "attack"):
		_skill()

## 受到怪物伤害：短暂无敌并闪红，HUD 通过 damaged 生成红色伤害数字。
func take_damage(amount: float, _from_x := 0.0) -> void:
	if _invuln > 0.0 or hp <= 0.0:
		return
	_invuln = 0.45
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount, global_position + Vector2(0, -72))
	modulate = Color(1.55, 0.75, 0.75)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.2)


func _update_offset() -> void:
	# 景深就是 position.y；跳起只抬绘制，不动地面坐标
	visual_offset = Vector2(0.0, -z_height)

func _attack() -> void:
	# 连击：挥砍中再按 X 立刻接下一段（DNF 的普攻可打断）
	if state == "attack":
		if combo_index >= 0 and combo_index + 1 < COMBO.size():
			_start_attack(combo_index + 1)
		return
	# 上一段刚收招的窗口内接着按，也继续往后接
	if can_act():
		if _combo_timer > 0.0 and _next_combo > 0 and _next_combo < COMBO.size():
			_start_attack(_next_combo)
		else:
			_start_attack(0)

func _start_attack(i: int) -> void:
	combo_index = i
	state = "attack"
	_hit_frames.clear()
	play(COMBO[i], true)

## 上挑能不能放：MP 够不够（.skl [consume mp]）
func _can_use_skill() -> bool:
	return mp >= float(skill_info.get("consume_mp", 0))

func _skill() -> void:
	state = "skill"
	mp -= float(skill_info.get("consume_mp", 0))
	# 冷却来自 .skl [dungeon][cool time]（毫秒）
	_skill_cd = float(skill_info.get("cool_time", 2000)) / 1000.0
	_hit_frames.clear()
	if has_anim(SKILL_ANIM):
		play(SKILL_ANIM, true)
	else:
		play(COMBO[1], true)

## 技能栏热键入口（HUD 的 12 个技能格都从这里进）。
## 目前只实现了 1 个技能（上挑，占 0 号槽），其它槽位返回 false 让 HUD 提示「未装配」。
func hotbar_skill(index: int) -> bool:
	if index != 0:
		return false
	if _skill_cd > 0.0 or not _can_use_skill():
		return false
	if not (can_act() or state == "jump" or state == "attack"):
		return false
	_skill()
	return true


var target_index := 0
var targets: Array = []


## 手柄十字键切目标：现在还没有敌人目标系统，先按「最近怪物」轮转（由 room 注入 targets）
func cycle_target(dir: int) -> void:
	if targets.is_empty():
		return
	target_index = posmod(target_index + dir, targets.size())
	var t = targets[target_index]
	if t != null and is_instance_valid(t):
		var d: float = t.global_position.x - global_position.x
		if absf(d) > 1.0:
			facing = 1 if d > 0.0 else -1


func set_targets(list: Array) -> void:
	targets = list


func skill_cd_left() -> float:
	return maxf(0.0, _skill_cd)


func _on_anim_finished(name: String) -> void:
	if name in COMBO or name == SKILL_ANIM:
		# 收招后开一个连击窗口：窗口内再按 X，从下一段开始
		_next_combo = combo_index + 1 if combo_index + 1 < COMBO.size() else 0
		_combo_timer = COMBO_WINDOW
		state = "idle"
		combo_index = -1
		anim_speed = 1.0
		play("stay")


# ---------------------------------------------------------------------------
# 伤害：面板攻击力 × .atk 倍率 × 刻度
# ---------------------------------------------------------------------------
## 第 i 段普攻的 .atk（.chr [attack info] 的顺序）
func _atk_of(i: int) -> Dictionary:
	if i >= 0 and i < attack_chain.size():
		return attack_chain[i]
	return {}


## 伤害 = 基础攻击力 × (1 + [damage bonus]/100) × 刻度
## 普攻的 [weapon damage apply] 恒为 1（=100% 武器伤害），所以不再额外乘倍率；
## 上挑改用 .skl [static data][0] 当倍率（100 = 100%）。
func _damage(atk: Dictionary, rate_pct := 100.0) -> float:
	var bonus := float(atk.get("damage_bonus", 0.0))
	var base := attack_power * (rate_pct / 100.0)
	return maxf(1.0, base * (1.0 + bonus / 100.0) * DAMAGE_SCALE)


## 每帧检查判定：改用「判定盒出现的帧」驱动（武器层 .ani 里给的帧），
## 同一动画同一帧只打一次。
func _process(delta: float) -> void:
	super._process(delta)
	if state != "attack" and state != "skill":
		return
	var key := "%s#%d" % [anim, frame_index]
	if _hit_frames.has(key):
		return
	var boxes := boxes("attack")
	if boxes.is_empty():
		return          # 这一帧没有判定盒（武器层 .ani 没给就是没有）
	_hit_frames[key] = true
	var is_skill := state == "skill"
	var atk: Dictionary = skill_info.get("attack", {}) if is_skill else _atk_of(combo_index)
	var rate := 100.0
	if is_skill:
		var sd: Array = skill_info.get("static_data", [])
		if not sd.is_empty():
			rate = float(sd[0])
	var dmg := _damage(atk, rate)
	# [attack direction] 带 "lift up" 才是挑飞（上挑）；"hit down"/reaction=down 是击倒
	var direction := str(atk.get("direction", ""))
	var launch := direction.contains("lift up")
	var push := float(atk.get("push_aside", 0.0))
	hit_landed.emit(boxes, dmg, launch, push)
