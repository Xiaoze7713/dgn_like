## 手柄键位系统 —— 与键盘共用同一套技能/角色规则，但独立一套操作布局。
##
## 设计依据（2026-11-15 讨论稿）：
##   2.5D    ：面键 4 个 + 按住左肩键再按面键 4 个 = 8 个常用技能；左扳机修饰的第三排默认关闭；
##             右扳机=普攻、右肩键=闪避；十字键=药水/道具/切目标；左摇杆移动；右摇杆=瞄准/选目标。
##   俯视 45°：左摇杆移动、朝向跟随最后移动方向；扳机负责普攻；技能优先直按，十字键也用上；
##             尽量减少需要同时按修饰键的组合；右摇杆不作必需瞄准。
##
## 另附 `PRESET_DNF`：客户端原生手柄方案（从 PVF `clientonly/gamepad/gamepadhotkeyinfo.co` 解出），
## 用于对照验证 —— A=普攻 B=跳跃 X=技能 Y=技能2、十字键=物品1-4、RB/RT=技能5/6、LB/LT=组合键修饰。
##
## 用法：
##   GamepadKeys.install()                 # 开局一次（内部会挂到 DnfKeys.watch 上，改键盘不会冲掉手柄事件）
##   var intent := GamepadKeys.read()      # 每帧读一次：attack/dodge/skill/consumable/target/menu/close
##   GamepadKeys.set_mode(GamepadKeys.MODE_TOPDOWN)
##   GamepadKeys.set_preset(GamepadKeys.PRESET_DNF)
class_name GamepadKeys
extends RefCounted

const MODE_2_5D := "2_5d"
const MODE_TOPDOWN := "topdown"
const MODE_LABELS := {
	MODE_2_5D: "2.5D",
	MODE_TOPDOWN: "俯视 45°",
}

const PRESET_DESIGN := "design"
const PRESET_DNF := "dnf"
const PRESET_LABELS := {
	PRESET_DESIGN: "设计稿（面键+组合键）",
	PRESET_DNF: "客户端原生",
}

## 按钮名 → Godot 常量
const BUTTONS := {
	"a": JOY_BUTTON_A,
	"b": JOY_BUTTON_B,
	"x": JOY_BUTTON_X,
	"y": JOY_BUTTON_Y,
	"lb": JOY_BUTTON_LEFT_SHOULDER,
	"rb": JOY_BUTTON_RIGHT_SHOULDER,
	"back": JOY_BUTTON_BACK,
	"start": JOY_BUTTON_START,
	"ls": JOY_BUTTON_LEFT_STICK,
	"rs": JOY_BUTTON_RIGHT_STICK,
	"dpad_up": JOY_BUTTON_DPAD_UP,
	"dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT,
	"dpad_right": JOY_BUTTON_DPAD_RIGHT,
}

## 扳机是轴，不是按钮：用 JoypadMotion + 0.5 阈值当按钮用
const TRIGGERS := {
	"lt": JOY_AXIS_TRIGGER_LEFT,
	"rt": JOY_AXIS_TRIGGER_RIGHT,
}

## 键帽文字（手柄玩家看得懂的字形）
const GLYPHS := {
	"a": "Ⓐ", "b": "Ⓑ", "x": "Ⓧ", "y": "Ⓨ",
	"lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT",
	"back": "BACK", "start": "START", "ls": "LS", "rs": "RS",
	"dpad_up": "▲", "dpad_down": "▼", "dpad_left": "◀", "dpad_right": "▶",
}

## 右摇杆（瞄准/选目标/镜头）—— 4 个方向动作
const LOOK_ACTIONS := {
	"pad_look_left": 2, "pad_look_right": 2,
	"pad_look_up": 3, "pad_look_down": 3,
}

var mode := MODE_2_5D
var preset := PRESET_DESIGN
var extra_row_enabled := false

static var _installed := false
static var _s_mode := MODE_2_5D
static var _s_preset := PRESET_DESIGN
static var _s_extra := false
static var _s_watching := false


# ---------------------------------------------------------------- 布局表
## 每一行 = 4 个技能槽。modifier 为空表示直按，否则要先按住该修饰键。
const LAYOUT := {
	PRESET_DESIGN: {
		MODE_2_5D: [
			{"buttons": ["a", "b", "x", "y"], "modifier": ""},
			{"buttons": ["a", "b", "x", "y"], "modifier": "lb"},
			{"buttons": ["a", "b", "x", "y"], "modifier": "lt", "optional": true},
		],
		MODE_TOPDOWN: [
			{"buttons": ["a", "b", "x", "y"], "modifier": ""},
			{"buttons": ["dpad_up", "dpad_down", "dpad_left", "dpad_right"], "modifier": ""},
			{"buttons": ["a", "b", "x", "y"], "modifier": "lt", "optional": true},
		],
	},
	PRESET_DNF: {
		MODE_2_5D: [
			{"buttons": ["a", "b", "x", "y"], "modifier": ""},
		],
		MODE_TOPDOWN: [
			{"buttons": ["a", "b", "x", "y"], "modifier": ""},
		],
	},
}

## 高频动作（走 InputMap，player.gd 不用改）
const HIGH_FREQ := {
	PRESET_DESIGN: {"attack": "rt", "dodge": "rb", "jump": "", "skill": "", "skill2": ""},
	PRESET_DNF: {"attack": "a", "dodge": "", "jump": "b", "skill": "x", "skill2": "y"},
}

## 药水 / 道具 / 切换目标
const ITEM_LAYOUT := {
	PRESET_DESIGN: {
		MODE_2_5D: {"items": ["dpad_up", "dpad_down"], "modifier": "", "target_prev": "dpad_left", "target_next": "dpad_right", "target_modifier": ""},
		MODE_TOPDOWN: {"items": ["dpad_up", "dpad_down"], "modifier": "lb", "target_prev": "dpad_left", "target_next": "dpad_right", "target_modifier": "lb"},
	},
	PRESET_DNF: {
		MODE_2_5D: {"items": ["dpad_up", "dpad_right", "dpad_down", "dpad_left"], "modifier": "", "target_prev": "", "target_next": "", "target_modifier": ""},
		MODE_TOPDOWN: {"items": ["dpad_up", "dpad_right", "dpad_down", "dpad_left"], "modifier": "", "target_prev": "", "target_next": "", "target_modifier": ""},
	},
}


# ---------------------------------------------------------------- 安装

static func install() -> void:
	_installed = true
	for name in BUTTONS.keys():
		_ensure_action("pad_" + str(name))
	for name in TRIGGERS.keys():
		_ensure_action("pad_" + str(name))
	for act in LOOK_ACTIONS.keys():
		_ensure_action(str(act))
	_ensure_action("dodge")
	apply()
	if not _s_watching:
		_s_watching = true
		# 键盘改键会 erase_events → 手柄事件必须在它之后重新挂上
		DnfKeys.watch(_on_keys_changed)


static func set_mode(m: String) -> void:
	if not MODE_LABELS.has(m):
		return
	_s_mode = m
	if _installed:
		apply()


static func set_preset(p: String) -> void:
	if not PRESET_LABELS.has(p):
		return
	_s_preset = p
	if _installed:
		apply()


static func set_extra_row(enabled: bool) -> void:
	_s_extra = enabled
	if _installed:
		apply()


static func get_mode() -> String:
	return _s_mode


static func get_preset() -> String:
	return _s_preset


static func extra_row() -> bool:
	return _s_extra


## 把按钮/轴事件挂到 InputMap 上（按钮类动作一次写清楚；语义动作只补手柄事件，不动键盘事件）
static func apply() -> void:
	for name in BUTTONS.keys():
		var act := "pad_" + str(name)
		_ensure_action(act)
		InputMap.action_erase_events(act)
		var ev := InputEventJoypadButton.new()
		ev.button_index = int(BUTTONS[name])
		InputMap.action_add_event(act, ev)
	for name in TRIGGERS.keys():
		var act := "pad_" + str(name)
		_ensure_action(act)
		InputMap.action_erase_events(act)
		var ev := InputEventJoypadMotion.new()
		ev.axis = int(TRIGGERS[name])
		ev.axis_value = 0.5
		InputMap.action_add_event(act, ev)
	for act in LOOK_ACTIONS.keys():
		_ensure_action(str(act))
		InputMap.action_erase_events(str(act))
		var axis := int(LOOK_ACTIONS[act])
		var sign := -1.0 if str(act).ends_with("left") or str(act).ends_with("up") else 1.0
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = 0.4 * sign
		InputMap.action_add_event(str(act), ev)

	_apply_semantic()


## 高频动作 + 左摇杆移动：在 DnfKeys 之后补手柄事件
static func _apply_semantic() -> void:
	var stick_axes := {
		"move_left": [JOY_AXIS_LEFT_X, -0.35],
		"move_right": [JOY_AXIS_LEFT_X, 0.35],
		"move_up": [JOY_AXIS_LEFT_Y, -0.35],
		"move_down": [JOY_AXIS_LEFT_Y, 0.35],
	}
	for act in stick_axes.keys():
		if not InputMap.has_action(str(act)):
			InputMap.add_action(str(act))
		_strip_pad_events(str(act))
		var ev := InputEventJoypadMotion.new()
		ev.axis = int(stick_axes[act][0])
		ev.axis_value = float(stick_axes[act][1])
		InputMap.action_add_event(str(act), ev)

	var hf: Dictionary = HIGH_FREQ.get(_s_preset, {})
	for act in hf.keys():
		var btn := str(hf[act])
		_ensure_action(str(act))
		_strip_pad_events(str(act))
		if btn.is_empty():
			continue
		InputMap.action_add_event(str(act), _event_for(btn))


static func _event_for(btn: String) -> InputEvent:
	if TRIGGERS.has(btn):
		var m := InputEventJoypadMotion.new()
		m.axis = int(TRIGGERS[btn])
		m.axis_value = 0.5
		return m
	if BUTTONS.has(btn):
		var b := InputEventJoypadButton.new()
		b.button_index = int(BUTTONS[btn])
		return b
	return null


static func _strip_pad_events(action: String) -> void:
	var keep: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			continue
		keep.append(e)
	InputMap.action_erase_events(action)
	for e in keep:
		InputMap.action_add_event(action, e)


static func _on_keys_changed() -> void:
	if _installed:
		_apply_semantic()


static func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


# ---------------------------------------------------------------- 读取

## 每帧读一次：{ attack, dodge, skill:-1, consumable:-1, target:0, menu, close, jump, look:Vector2 }
static func read() -> Dictionary:
	var out := {
		"attack": InputMap.has_action("attack") and Input.is_action_pressed("attack"),
		"dodge": InputMap.has_action("dodge") and Input.is_action_just_pressed("dodge"),
		"jump": InputMap.has_action("jump") and Input.is_action_just_pressed("jump"),
		"skill": skill_slot_just_pressed(),
		"consumable": consumable_just_pressed(),
		"target": 0,
		"menu": _just("pad_start"),
		"close": _just("pad_back"),
	}
	var lay: Dictionary = ITEM_LAYOUT.get(_s_preset, {}).get(_s_mode, {})
	if not lay.is_empty():
		var mod := str(lay.get("target_modifier", ""))
		if _mod_ok(mod):
			if _just(str(lay.get("target_prev", ""))):
				out["target"] = -1
			elif _just(str(lay.get("target_next", ""))):
				out["target"] = 1
	var look := Vector2(
		Input.get_action_strength("pad_look_right") - Input.get_action_strength("pad_look_left"),
		Input.get_action_strength("pad_look_down") - Input.get_action_strength("pad_look_up"))
	out["look"] = look
	return out


## 当前按下的技能槽（0 起），没有就 -1
static func skill_slot_just_pressed() -> int:
	var rows: Array = LAYOUT.get(_s_preset, {}).get(_s_mode, [])
	var slot := 0
	for row in rows:
		var mod := str(row.get("modifier", ""))
		var optional := bool(row.get("optional", false))
		var enabled := (not optional) or _s_extra
		if enabled and _mod_ok(mod):
			var btns: Array = row.get("buttons", [])
			for i in btns.size():
				if _just("pad_" + str(btns[i])):
					return slot + i
		slot += 4
	return -1


## 当前按下的药水/道具槽（0 起），没有就 -1
static func consumable_just_pressed() -> int:
	var lay: Dictionary = ITEM_LAYOUT.get(_s_preset, {}).get(_s_mode, {})
	if lay.is_empty():
		return -1
	if not _mod_ok(str(lay.get("modifier", ""))):
		return -1
	var items: Array = lay.get("items", [])
	for i in items.size():
		if _just("pad_" + str(items[i])):
			return i
	return -1


static func _just(action: String) -> bool:
	if action.is_empty() or not InputMap.has_action(action):
		return false
	return Input.is_action_just_pressed(action)


static func _mod_ok(mod: String) -> bool:
	if mod.is_empty():
		return true
	if not InputMap.has_action("pad_" + mod):
		return false
	return Input.is_action_pressed("pad_" + mod)


# ---------------------------------------------------------------- 显示

static func skill_label(slot: int) -> String:
	var rows: Array = LAYOUT.get(_s_preset, {}).get(_s_mode, [])
	var idx := 0
	for row in rows:
		var optional := bool(row.get("optional", false))
		if optional and not _s_extra:
			idx += 4
			continue
		var btns: Array = row.get("buttons", [])
		if slot >= idx and slot < idx + btns.size():
			var mod := str(row.get("modifier", ""))
			var glyph := glyph(str(btns[slot - idx]))
			return (glyph_prefix(mod) + glyph) if not mod.is_empty() else glyph
		idx += 4
	return ""


static func consumable_label(slot: int) -> String:
	var lay: Dictionary = ITEM_LAYOUT.get(_s_preset, {}).get(_s_mode, {})
	var items: Array = lay.get("items", [])
	if slot < 0 or slot >= items.size():
		return ""
	var mod := str(lay.get("modifier", ""))
	var glyph := glyph(str(items[slot]))
	return (glyph_prefix(mod) + glyph) if not mod.is_empty() else glyph


static func glyph(btn: String) -> String:
	return str(GLYPHS.get(btn, btn.to_upper()))


static func glyph_prefix(mod: String) -> String:
	if mod.is_empty():
		return ""
	return glyph(mod) + "+"


## 设置窗口用：返回 [{title, rows:[[名字, 键帽], ...]}]
static func describe() -> Array:
	var out: Array = []
	var hf: Dictionary = HIGH_FREQ.get(_s_preset, {})
	var freq: Array = []
	if not str(hf.get("attack", "")).is_empty():
		freq.append(["普通攻击", glyph(str(hf["attack"]))])
	if not str(hf.get("dodge", "")).is_empty():
		freq.append(["闪避", glyph(str(hf["dodge"]))])
	if not str(hf.get("jump", "")).is_empty():
		freq.append(["跳跃", glyph(str(hf["jump"]))])
	if not str(hf.get("skill", "")).is_empty():
		freq.append(["技能", glyph(str(hf["skill"]))])
	if not str(hf.get("skill2", "")).is_empty():
		freq.append(["技能2", glyph(str(hf["skill2"]))])
	freq.append(["菜单", glyph("start")])
	freq.append(["关闭/返回", glyph("back")])
	out.append({"title": "高频动作", "rows": freq})

	var skills: Array = []
	for slot in 12:
		var lb := skill_label(slot)
		if lb.is_empty():
			continue
		skills.append(["技能槽 %d" % (slot + 1), lb])
	out.append({"title": "技能（%s）" % str(MODE_LABELS.get(_s_mode, _s_mode)), "rows": skills})

	var items: Array = []
	var lay: Dictionary = ITEM_LAYOUT.get(_s_preset, {}).get(_s_mode, {})
	var names := ["药水/道具 1", "药水/道具 2", "药水/道具 3", "药水/道具 4"]
	var lst: Array = lay.get("items", [])
	for i in lst.size():
		items.append([names[min(i, names.size() - 1)], consumable_label(i)])
	if not str(lay.get("target_prev", "")).is_empty():
		items.append(["切换目标 ←", glyph_prefix(str(lay.get("target_modifier", ""))) + glyph(str(lay["target_prev"]))])
		items.append(["切换目标 →", glyph_prefix(str(lay.get("target_modifier", ""))) + glyph(str(lay["target_next"]))])
	out.append({"title": "药水 / 道具 / 目标", "rows": items})

	out.append({"title": "摇杆", "rows": [
		["左摇杆", "移动"],
		["右摇杆", "瞄准 / 选目标 / 镜头"],
		["左摇杆按下", "未绑定"],
	]})
	return out


# ---------------------------------------------------------------- 设备状态

static func is_pad_active() -> bool:
	if not Input.get_connected_joypads().is_empty():
		return true
	# 没有设备时也允许上游强制显示（截图/演示用）
	return false


static func pad_count() -> int:
	return Input.get_connected_joypads().size()


static func device_names() -> Array:
	var out: Array = []
	for id in Input.get_connected_joypads():
		out.append("%s / %s" % [id, Input.get_joy_name(int(id))])
	return out
