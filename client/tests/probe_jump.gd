extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/sf85_mirkwood.tscn")
	var node := packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	var room = node
	var p = room.player
	print("start pos=", p.position, " anim=", p.anim)
	Input.action_press("jump")
	await process_frame
	Input.action_release("jump")
	for i in 40:
		await process_frame
		if i % 4 == 0:
			print("f", i, " anim=", p.anim, " fi=", p.frame_index, " pos.y=", snappedf(p.position.y, 0.1),
				" vis=", p.visual_offset)
	quit()
