extends SceneTree
func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/sf85_mirkwood.tscn")
	var node := packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	var room = node
	var p = room.player
	var m = room.monsters[0]
	print("开局 mp=%.1f/%.1f 怪 hp=%.1f  上挑 mp 消耗=%s 冷却=%sms" % [
		p.mp, p.mp_max, m.hp, p.skill_info.get("consume_mp"), p.skill_info.get("cool_time")])
	Input.action_press("skill"); await process_frame; Input.action_release("skill")
	var hits := []
	var last := -1
	for i in 200:
		await process_frame
		if m.hp != last:
			last = m.hp
			hits.append("f%d hp=%.2f state=%s" % [p.frame_index, m.hp, m.state])
	print("上挑命中序列：", hits)
	print("玩家 anim=%s mp=%.1f cd=%.2f 怪 state=%s hp=%.2f" % [p.anim, p.mp, p._skill_cd, m.state, m.hp])
	quit()
