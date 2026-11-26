extends SceneTree
## 全量通行表体检：列出所有「整张图 pass 全为 2」的 area，以及各种行数/列数。
## 用法：XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
##   ./tools/godot.sh --headless --script res://tests/audit_pass.gd

const PassGridScript := preload("res://game/world/build/pass_grid.gd")

func _init() -> void:
	var content := LivePvfContent.new()
	content.load_index()
	var list: Array = content.index.get("towns", [])
	var all2: Array = []
	var total := 0
	for t in list:
		var d: Dictionary = t
		var key := str(d.get("key", ""))
		var td: TownDef = content.town(key)
		if td == null:
			continue
		for i in td.area_count():
			var mp := td.map_of(i)
			if mp == "" or not content.has_map(mp):
				continue
			total += 1
			var room: MapRoom = content.map_room(mp)
			var defs := content.tiles_for(room)
			var g := PassGridScript.new()
			g.build(room.tiles, defs)
			var zeros := 0
			for v in g.cells:
				if int(v) == 0:
					zeros += 1
			if zeros == 0:
				all2.append({"town": key, "area": i, "map": mp, "cols": g.cols, "rows": g.rows,
						"tiles": room.tiles.size(), "tile_rows": _rows(defs, room.tiles)})
	print("PASS total_areas=%d all_blocked=%d" % [total, all2.size()])
	for e in all2:
		print("ALL2 ", JSON.stringify(e))
	quit()

func _rows(defs: Dictionary, tiles: Array) -> Array:
	var out: Array = []
	for p in tiles:
		var t: TileDef = defs.get(p, null)
		out.append(t.rows if t != null else -1)
	return out
