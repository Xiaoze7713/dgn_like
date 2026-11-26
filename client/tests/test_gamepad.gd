## GamepadKeys 自测：动作注册、按键/轴绑定、布局表、键帽、两种模式 × 两套预设
##
##   XDG_DATA_HOME=.tmp_udata GODOT_PROJECT=$PWD/client \
##     ./tools/godot.sh --headless --script res://tests/test_gamepad.gd
extends SceneTree

var _fails := 0
var _checks := 0


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", what)
	else:
		_fails += 1
		print("  FAIL ", what)


func _has_button(action: String, button: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button:
			return true
	return false


func _has_axis(action: String, axis: int, positive: bool) -> bool:
	if not InputMap.has_action(action):
		return false
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion:
			var m := e as InputEventJoypadMotion
			if m.axis == axis and ((m.axis_value > 0.0) == positive) and m.axis_value != 0.0:
				return true
	return false


func _init() -> void:
	print("== GamepadKeys 自测 ==")
	var cfg := ProjectSettings.globalize_path(DnfKeys.SAVE_PATH)
	if FileAccess.file_exists(cfg):
		DirAccess.remove_absolute(cfg)
	DnfKeys.install()
	GamepadKeys.install()

	# --- 按钮动作
	_ok(_has_button("pad_a", JOY_BUTTON_A), "pad_a = JOY_BUTTON_A")
	_ok(_has_button("pad_b", JOY_BUTTON_B), "pad_b = JOY_BUTTON_B")
	_ok(_has_button("pad_x", JOY_BUTTON_X), "pad_x = JOY_BUTTON_X")
	_ok(_has_button("pad_y", JOY_BUTTON_Y), "pad_y = JOY_BUTTON_Y")
	_ok(_has_button("pad_lb", JOY_BUTTON_LEFT_SHOULDER), "pad_lb = 左肩键")
	_ok(_has_button("pad_rb", JOY_BUTTON_RIGHT_SHOULDER), "pad_rb = 右肩键")
	_ok(_has_button("pad_dpad_up", JOY_BUTTON_DPAD_UP), "pad_dpad_up = 十字上")
	_ok(_has_button("pad_start", JOY_BUTTON_START), "pad_start = START")
	_ok(_has_button("pad_back", JOY_BUTTON_BACK), "pad_back = BACK")

	# --- 扳机是轴
	_ok(_has_axis("pad_rt", JOY_AXIS_TRIGGER_RIGHT, true), "pad_rt = 右扳机轴")
	_ok(_has_axis("pad_lt", JOY_AXIS_TRIGGER_LEFT, true), "pad_lt = 左扳机轴")

	# --- 左摇杆挂到语义移动动作上（player.gd 不用改）
	_ok(_has_axis("move_left", JOY_AXIS_LEFT_X, false), "move_left += 左摇杆 X-")
	_ok(_has_axis("move_right", JOY_AXIS_LEFT_X, true), "move_right += 左摇杆 X+")
	_ok(_has_axis("move_up", JOY_AXIS_LEFT_Y, false), "move_up += 左摇杆 Y-")
	_ok(_has_axis("move_down", JOY_AXIS_LEFT_Y, true), "move_down += 左摇杆 Y+")

	# --- 右摇杆 = 瞄准/选目标
	_ok(_has_axis("pad_look_left", JOY_AXIS_RIGHT_X, false), "pad_look_left = 右摇杆 X-")
	_ok(_has_axis("pad_look_right", JOY_AXIS_RIGHT_X, true), "pad_look_right = 右摇杆 X+")

	# --- 设计稿预设：右扳机=普攻、右肩键=闪避
	GamepadKeys.set_preset(GamepadKeys.PRESET_DESIGN)
	_ok(_has_axis("attack", JOY_AXIS_TRIGGER_RIGHT, true), "设计稿：attack = RT")
	_ok(_has_button("dodge", JOY_BUTTON_RIGHT_SHOULDER), "设计稿：dodge = RB")

	# --- 客户端原生预设：A=普攻、B=跳跃、X=技能、Y=技能2
	GamepadKeys.set_preset(GamepadKeys.PRESET_DNF)
	_ok(_has_button("attack", JOY_BUTTON_A), "原生：attack = A")
	_ok(_has_button("jump", JOY_BUTTON_B), "原生：jump = B")
	_ok(_has_button("skill", JOY_BUTTON_X), "原生：skill = X")
	_ok(_has_button("skill2", JOY_BUTTON_Y), "原生：skill2 = Y")

	# --- 2.5D 设计稿：第一排面键、第二排 LB+面键、第三排默认关闭
	GamepadKeys.set_preset(GamepadKeys.PRESET_DESIGN)
	GamepadKeys.set_mode(GamepadKeys.MODE_2_5D)
	GamepadKeys.set_extra_row(false)
	_ok(GamepadKeys.skill_label(0) == "Ⓐ", "2.5D 槽1 = Ⓐ（实际 %s）" % GamepadKeys.skill_label(0))
	_ok(GamepadKeys.skill_label(3) == "Ⓨ", "2.5D 槽4 = Ⓨ")
	_ok(GamepadKeys.skill_label(4) == "LB+Ⓐ", "2.5D 槽5 = LB+Ⓐ（实际 %s）" % GamepadKeys.skill_label(4))
	_ok(GamepadKeys.skill_label(7) == "LB+Ⓨ", "2.5D 槽8 = LB+Ⓨ")
	_ok(GamepadKeys.skill_label(8) == "", "第三排默认关闭时槽9 无键帽")
	GamepadKeys.set_extra_row(true)
	_ok(GamepadKeys.skill_label(8) == "LT+Ⓐ", "开第三排后槽9 = LT+Ⓐ（实际 %s）" % GamepadKeys.skill_label(8))
	GamepadKeys.set_extra_row(false)

	# --- 俯视 45°：第二排改成十字键直按（不用修饰键）
	GamepadKeys.set_mode(GamepadKeys.MODE_TOPDOWN)
	_ok(GamepadKeys.skill_label(4) == "▲", "俯视槽5 = ▲（实际 %s）" % GamepadKeys.skill_label(4))
	_ok(GamepadKeys.skill_label(7) == "▶", "俯视槽8 = ▶")
	_ok(GamepadKeys.consumable_label(0) == "LB+▲", "俯视药水1 = LB+▲（实际 %s）" % GamepadKeys.consumable_label(0))

	# --- 2.5D 药水/目标：十字键直按
	GamepadKeys.set_mode(GamepadKeys.MODE_2_5D)
	_ok(GamepadKeys.consumable_label(0) == "▲", "2.5D 药水1 = ▲")
	_ok(GamepadKeys.consumable_label(1) == "▼", "2.5D 药水2 = ▼")

	# --- 客户端原生预设：十字键 = 物品 1–4
	GamepadKeys.set_preset(GamepadKeys.PRESET_DNF)
	_ok(GamepadKeys.consumable_label(0) == "▲", "原生物品1 = ▲")
	_ok(GamepadKeys.consumable_label(3) == "◀", "原生物品4 = ◀（实际 %s）" % GamepadKeys.consumable_label(3))

	# --- describe() 四段
	GamepadKeys.set_preset(GamepadKeys.PRESET_DESIGN)
	var desc := GamepadKeys.describe()
	_ok(desc.size() == 4, "describe 四段（实际 %d）" % desc.size())
	_ok(str(desc[0]["title"]) == "高频动作", "第一段是高频动作")
	_ok(str(desc[1]["title"]).begins_with("技能"), "第二段是技能")

	# --- read() 结构
	var it := GamepadKeys.read()
	for key in ["attack", "dodge", "jump", "skill", "consumable", "target", "menu", "close", "look"]:
		_ok(it.has(key), "read() 含 %s" % key)
	_ok(int(it["skill"]) == -1, "没按键时技能槽 = -1")
	_ok(int(it["consumable"]) == -1, "没按键时药水槽 = -1")

	print("== %d 项检查，%d 失败 ==" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
