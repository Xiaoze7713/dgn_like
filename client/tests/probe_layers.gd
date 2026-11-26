extends SceneTree
func _initialize() -> void:
	var room = load("res://scenes/sf85_mirkwood.tscn").instantiate()
	root.add_child(room)
	await process_frame
	var p = room.player
	p.play("move", true)
	for i in 6:
		await process_frame
	print("facing=", p.facing, " scale.x=", p.scale.x, " anim=", p.anim, " frame=", p.frame_index)
	var ls = p.get_children()
	for s in ls:
		print("  layer z=", s.z_index, " vis=", s.visible, " pos=", s.position, " tex=", (s.texture.get_size() if s.texture else "null"))
	quit()
