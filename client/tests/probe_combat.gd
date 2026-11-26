## 验证「判定与数值来自 PVF 源文件」：
##   1) 打印从 .chr / .atk / .mob / .skl 读到的数值
##   2) 把玩家挪到怪物身前，逐帧扫三连击，看判定盒从哪一帧出现
##   3) 对比每一段的伤害（应等于 面板攻击力 × (1+damage bonus) × DAMAGE_SCALE）
extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/sf85_mirkwood.tscn")
	var node := packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	var room = node
	var p = room.player

	print("=== 玩家数值（.chr + 武器 .equ）")
	var st: Dictionary = p.def.get("stats", {})
	print("  [width] %s x %s   hp %.1f  mp %.1f  物理攻击 %.1f  移速 %.0f  攻速 %.0f  跳跃力 %.0f" % [
		st.get("width"), st.get("depth"), st.get("hp_max"), st.get("mp_max"),
		st.get("physical_attack"), st.get("move_speed"), st.get("attack_speed"), st.get("jump_power")])
	print("  武器 %s  物理攻击 %.0f   面板攻击力 %.1f" % [
		p.def.get("weapon", {}).get("name"), p.def.get("weapon", {}).get("physical_attack"),
		p.attack_power])
	print("  实际移速 %.1f px/s  跳跃初速 %.1f px/s" % [p.speed_x, p.jump_v])
	for i in p.attack_chain.size():
		var a: Dictionary = p.attack_chain[i]
		print("  第%d段 .atk: damage_bonus %.0f  push %.0f  lift %.0f  reaction=%s  direction=%s" % [
			i + 1, a.get("damage_bonus"), a.get("push_aside"), a.get("lift_up"),
			a.get("reaction"), a.get("direction")])
	print("  上挑 .skl: mp %.0f  冷却 %d ms  static_data %s  min dmg %.1f" % [
		p.skill_info.get("consume_mp"), p.skill_info.get("cool_time"),
		p.skill_info.get("static_data"), p._damage(p.skill_info.get("attack", {}),
			float(p.skill_info.get("static_data", [100])[0]))])

	print("=== 怪物数值（.mob）")
	for mon in room.monsters.slice(0, 2):
		print("  %s  width %.0f  hp %.1f/%.1f  移速 %.1f  视野 %.0f  攻速 %.2fs  reach %.1f" % [
			mon.name_text, mon.body_width(), mon.hp, mon.hp_max, mon.speed,
			mon.sight, mon.attack_cd, mon.reach])

	var m = room.monsters[0]
	p.position = m.position + Vector2(-46, 0)
	p.facing = 1
	p.scale.x = absf(p.scale.x)
	print("=== 三连击逐帧扫判定盒（玩家 %s / 怪 %s）" % [p.position, m.position])
	Input.action_press("attack")
	await process_frame
	Input.action_release("attack")
	var last_anim := ""
	for i in 60:
		await process_frame
		var n: int = p.boxes("attack").size()
		if p.anim != last_anim or n > 0:
			print("  f%-2d %-16s 判定盒=%d  %s  hp=%.2f" % [
				p.frame_index, p.anim, n,
				"" if n == 0 else str(p.boxes("attack")), m.hp])
			last_anim = p.anim
	print("=== 上挑")
	var hp_before: float = m.hp
	Input.action_press("skill")
	await process_frame
	Input.action_release("skill")
	for i in 40:
		await process_frame
	print("  上挑 %s -> %s hp %.2f -> %.2f (掉 %.2f)" % [
		p.anim, m.state, hp_before, m.hp, hp_before - m.hp])
	quit()
