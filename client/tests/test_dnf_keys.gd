## DnfKeys 自测：默认键位 → 改键 → 存盘 → 读回 → 恢复默认
##
##   XDG_DATA_HOME=.tmp_udata GODOT_PROJECT=$PWD/client \
##     ./tools/godot.sh --headless --script res://tests/test_dnf_keys.gd
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


func _action_keys(action: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append((e as InputEventKey).physical_keycode)
	return out


func _init() -> void:
	print("== DnfKeys 自测 ==")
	# 清掉上一次的存盘，保证从默认方案开始（测试本身会验证存盘/读回）
	var cfg_path := ProjectSettings.globalize_path(DnfKeys.SAVE_PATH)
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)
	DnfKeys.install()

	_ok(DnfKeys.count() == 123, "动作表 123 条（实际 %d）" % DnfKeys.count())
	_ok(DnfKeys.ids("system").size() == 59, "系统 59 条（实际 %d）" % DnfKeys.ids("system").size())
	_ok(DnfKeys.ids("character").size() == 27, "角色 27 条")
	_ok(DnfKeys.ids("dungeon").size() == 27, "技能 27 条")
	_ok(DnfKeys.ids("quickchat").size() == 10, "聊天 10 条")

	# 默认方案：移动、普攻、跳跃、技能、技能2、技能栏 1–6、扩展 1–6、物品 1–6
	_ok(_action_keys("move_up") == [KEY_UP], "I01 移动↑ = Up")
	_ok(_action_keys("move_left") == [KEY_LEFT], "I02 移动← = Left")
	_ok(_action_keys("attack") == [KEY_X], "I05 普攻 = X")
	_ok(_action_keys("jump") == [KEY_C], "I06 跳跃 = C")
	_ok(_action_keys("skill") == [KEY_Z], "I07 技能 = Z")
	_ok(_action_keys("dnf_i08") == [KEY_SPACE], "I08 技能2 = 空格")
	_ok(_action_keys("dnf_i21") == [KEY_A], "I21 技能1 = A")
	_ok(_action_keys("dnf_i32") == [KEY_Y], "I32 扩展6 = Y")
	_ok(_action_keys("dnf_i33") == [KEY_1], "I33 物品1 = 1")
	_ok(_action_keys("dnf_i12") == [KEY_I], "I12 装备栏 = I")
	_ok(_action_keys("dnf_i49") == [KEY_ESCAPE], "I49 关闭菜单 = Esc")

	# 改键：普攻 X → G，语义动作 attack 必须跟着变
	DnfKeys.set_key("I05", "G")
	_ok(_action_keys("attack") == [KEY_G], "改 I05 后 attack = G")
	_ok(DnfKeys.key_label("I05") == "G", "键帽显示 G")
	DnfKeys.save()

	# 读回
	DnfKeys.install()
	_ok(DnfKeys.key_of("I05") == "G", "存盘后读回 I05 = G")

	# 冲突：把 I07 也设成 G，I05 应被清空
	DnfKeys.set_key("I07", "G")
	_ok(DnfKeys.key_of("I05").is_empty(), "冲突时旧绑定被解除")
	_ok(DnfKeys.key_of("I07") == "G", "新绑定生效")

	# 恢复默认
	DnfKeys.reset_all()
	_ok(DnfKeys.key_of("I05") == "X", "reset 后 I05 = X")
	_ok(DnfKeys.key_of("I07") == "Z", "reset 后 I07 = Z")

	# 清空 / 未绑定动作
	DnfKeys.clear_key("I11")
	_ok(DnfKeys.key_label("I11") == "", "未绑定动作键帽为空")
	_ok(DnfKeys.ids("dungeon").has("I82"), "I82 再次挑战在技能页里")

	print("== %d 项检查，%d 失败 ==" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
