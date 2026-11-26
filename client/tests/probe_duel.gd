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
	print("玩家=", p.position, " 怪=", m.position, " 怪hp=", m.hp)
	Input.action_press("attack")
	await process_frame
	Input.action_release("attack")
	var seen := {}
	for i in 200:
		await process_frame
		var bs = p.boxes("attack")
		if bs.size() > 0 and not seen.has(p.frame_index):
			seen[p.frame_index] = true
			print("f%d %s boxes=%s 怪hp=%.2f 玩家x=%.1f" % [p.frame_index, p.anim, str(bs), m.hp, p.position.x])
	print("最终 怪hp=", m.hp, " 玩家x=", p.position.x, " 怪x=", m.position.x)
	quit()
