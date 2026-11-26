extends SceneTree
## 逐个城镇/area 做“数据层”体检：只记录明确缺失/异常，不改代码。
## 用法：
##   XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
##     ./tools/godot.sh --headless --script res://tests/audit_towns.gd
## 产物：data/debug/audit_towns.json + 终端摘要。

func _init() -> void:
	var c := LivePvfContent.new()
	c.load_index()
	var rows: Array = []
	for t in c.index.get("towns", []):
		var key := str(t.get("key", ""))
		var td: TownDef = c.town(key)
		if td == null:
			rows.append({"town": key, "area": -1, "error": "town_null"})
			continue
		for i in td.area_count():
			var area: Dictionary = td.area(i)
			var map_path := str(area.get("map", ""))
			var row := {
				"town": key, "town_id": td.town_id, "town_name": td.display_name(),
				"area": i, "type": str(area.get("type", "")), "map": map_path,
				"minimap": area.get("minimap") != null, "phase": area.get("phase", []).size(),
				"tiles": 0, "missing_tiles": [], "anims": 0, "missing_anims": [],
				"bg": 0, "missing_bg": [], "npcs": 0, "missing_npcs": [],
				"movable": 0, "movable_anim": 0,
			}
			if map_path == "" or not c.has_map(map_path):
				row["error"] = "map_missing"
				rows.append(row)
				continue
			var room: MapRoom = c.map_room(map_path)
			row["tiles"] = room.tiles.size()
			if room.tiles.is_empty():
				row["error"] = "no_tiles"
			for tp in room.tiles:
				if c.tile(tp) == null:
					row["missing_tiles"].append(tp)
			for a in room.anims:
				var ap := str(a.get("path", ""))
				if ap == "" or c.ani(ap) == null:
					row["missing_anims"].append(ap)
			row["anims"] = room.anims.size()
			for b in room.background_anims:
				var bp := str(b.get("path", ""))
				if bp == "" or c.ani(bp) == null:
					row["missing_bg"].append(bp)
			row["bg"] = room.background_anims.size()
			for n in room.npcs:
				var nid := int(n.get("id", 0))
				if not c.has_npc(nid):
					row["missing_npcs"].append(nid)
			row["npcs"] = room.npcs.size()
			row["movable"] = room.town_movable.size()
			row["movable_anim"] = room.town_movable_anim.size()
			rows.append(row)
	var out := {"generated": Time.get_datetime_string_from_system(), "rows": rows}
	var dir := "/home/sunmingze/dnf_like/data/debug"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/audit_towns.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
	var problems: Array = []
	for r in rows:
		if r.has("error") or not r.get("missing_tiles", []).is_empty() \
				or not r.get("missing_anims", []).is_empty() \
				or not r.get("missing_bg", []).is_empty() \
				or not r.get("missing_npcs", []).is_empty():
			problems.append(r)
	print("AUDIT towns=", c.index.get("towns", []).size(), " areas=", rows.size(), " problems=", problems.size())
	var kinds: Dictionary = {}
	for r in problems:
		if r.has("error"):
			kinds[str(r["error"])] = int(kinds.get(str(r["error"]), 0)) + 1
		if not r.get("missing_tiles", []).is_empty():
			kinds["missing_tiles"] = int(kinds.get("missing_tiles", 0)) + 1
		if not r.get("missing_anims", []).is_empty():
			kinds["missing_anims"] = int(kinds.get("missing_anims", 0)) + 1
		if not r.get("missing_bg", []).is_empty():
			kinds["missing_bg"] = int(kinds.get("missing_bg", 0)) + 1
		if not r.get("missing_npcs", []).is_empty():
			kinds["missing_npcs"] = int(kinds.get("missing_npcs", 0)) + 1
	print("KINDS ", JSON.stringify(kinds))
	for r in problems.slice(0, 40):
		print("P ", JSON.stringify(r))
	quit()
