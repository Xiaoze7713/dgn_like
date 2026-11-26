extends SceneTree
func _process(_d: float) -> bool:
	var store := NpkStore.new("/mnt/d/WeGameApps/rail_apps/地下城与勇士：创新世纪(1)/ImagePacks2")
	store.open("res://assets/npk-index-latest.bin")
	for q in [["Map/HendonMyre/hmtile.img", 0], ["Map/Town/Evildom/CentralPark/Central_tile.img", 0], ["Map/powerstation/KohlePowerStation/Tile/point.img", 3]]:
		var img := store.image(str(q[0]))
		if img == null:
			print("MISS ", q[0]); continue
		var f: Dictionary = img.frame(int(q[1]))
		print("%s f%d rect=%s frame_keys=%s" % [q[0], int(q[1]), store.frame_rect(str(q[0]), int(q[1])), f.keys()])
	quit(0)
	return true
