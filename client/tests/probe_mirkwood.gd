extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/sf85_mirkwood.tscn")
	if packed == null:
		print("场景加载失败")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var node := packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	print("启动耗时: ", Time.get_ticks_msec() - t0, " ms")
	var room = node
	print("资产: ", room.assets.stats())
	print("房间: ", room.room_w, "x", room.room_h, " 格子 ", room.grid_w, "x", room.grid_h)
	print("地板分片: ", room.tiles_root.get_child_count())
	var p = room.player
	print("玩家: pos=", p.position, " anim=", p.anim, " 帧数=", p.total_frames(), " 图层=", p.get_child_count())
	print("可走(320,400)? ", room.is_walkable(Vector2(320, 400)), "  (100,60)? ", room.is_walkable(Vector2(100, 60)))
	print("怪物: ", room.monsters.size())
	for m in room.monsters:
		print("   ", m.name_text, " pos=", m.position, " anim=", m.anim, " 帧数=", m.total_frames())
	# 走两帧动画看有没有崩
	for i in 12:
		await process_frame
	print("12 帧后: player anim=", p.anim, " frame=", p.frame_index, " 贴图=", room.assets.stats()["npk"].get("cached_tex", 0))
	# 假装按 X 打一下
	Input.action_press("attack")
	await process_frame
	Input.action_release("attack")
	for i in 10:
		await process_frame
	print("按 X 后: anim=", p.anim, " state=", p.state)
	quit(0)
