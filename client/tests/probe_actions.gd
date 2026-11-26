extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/sf85_mirkwood.tscn")
	var node := packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	var room = node
	var p = room.player
	print("--- 三连击 ---")
	for k in 3:
		Input.action_press("attack")
		await process_frame
		Input.action_release("attack")
		for i in 6:
			await process_frame
		print("第", k + 1, "段 anim=", p.anim, " fi=", p.frame_index, "/", p.total_frames(),
			" state=", p.state, " 判定盒=", p.boxes("attack").size())
	for i in 20:
		await process_frame
	print("--- 上挑(Z) ---")
	Input.action_press("skill")
	await process_frame
	Input.action_release("skill")
	for i in 8:
		await process_frame
	print("anim=", p.anim, " fi=", p.frame_index, "/", p.total_frames(), " state=", p.state,
		" cd=", snappedf(p._skill_cd, 0.01), " 判定盒=", p.boxes("attack").size())
	for i in 10:
		await process_frame
	print("--- 命中怪物 ---")
	var m = room.monsters[0]
	print("怪物 hp=", m.hp, " 距离=", snappedf(p.position.distance_to(m.position), 1.0))
	m.take_hit(12, p.position.x, false)
	print("受击后 hp=", m.hp, " anim=", m.anim, " state=", m.state)
	quit()
