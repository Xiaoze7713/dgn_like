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
	p.position = m.position + Vector2(-46, 0)
	print("贴脸：玩家=", p.position, " 怪=", m.position, " hp=", m.hp)
	Input.action_press("attack")
	await process_frame
	Input.action_release("attack")
	for i in 40:
		await process_frame
	print("普攻后 hp=", m.hp, " 怪物 anim=", m.anim, " state=", m.state)
	await process_frame
	print("--- 上挑 ---")
	Input.action_press("skill")
	await process_frame
	Input.action_release("skill")
	for i in 40:
		await process_frame
	print("上挑后 hp=", m.hp, " 怪物 state=", m.state, " 玩家 anim=", p.anim, " cd=", snappedf(p._skill_cd, 0.01))
	quit()
