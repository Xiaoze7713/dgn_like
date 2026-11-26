extends SceneTree
## 地砖“拼接宽度”体检：RoomBuilder 目前按固定 224 像素铺一块地砖，
## 但 NPK 帧宽不全是 224。这里列出所有非 224 的贴图，供位置后处理前核对。
## 用法：
##   XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
##     ./tools/godot.sh --headless --script res://tests/tile_width_audit.gd

func _init() -> void:
	var c := LivePvfContent.new()
	c.load_index()
	var store := NpkStore.new("/mnt/d/dnf_latest/ImagePacks2")
	store.open_live()
	var seen: Dictionary = {}
	var bad: Array = []
	for t in c.index.get("towns", []):
		var td: TownDef = c.town(str(t.get("key", "")))
		if td == null:
			continue
		for i in td.area_count():
			var mp := str(td.area(i).get("map", ""))
			if mp == "" or not c.has_map(mp):
				continue
			var room: MapRoom = c.map_room(mp)
			for tp in room.tiles:
				var def: TileDef = c.tile(tp)
				if def == null or def.img == "":
					continue
				var key := def.img + "#" + str(def.frame)
				if seen.has(key):
					continue
				seen[key] = true
				var rect := store.frame_rect(def.img, def.frame)
				if rect.size.x != 224:
					bad.append({"town": str(t.get("key", "")), "area": i, "map": mp,
						"tile": tp, "img": def.img, "w": rect.size.x, "h": rect.size.y})
	print("TILE_WIDTH non224=", bad.size(), " unique_images=", seen.size())
	print("TILE_WIDTH_JSON ", JSON.stringify(bad))
	quit()
