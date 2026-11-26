extends SceneTree
## 全量地图审计：twn 引用的所有 map + dgn 目录下的所有 map。
## 只读；输出 data/debug/audit_maps.json / .md。
## 跑法：
##   XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=$PWD/client \
##   ./tools/godot.sh --headless --script res://tests/audit_maps.gd

const OUT_DIR := "res://data/debug"
const KNOWN := [
	"[tile]", "[extended tile]", "[tile files]", "[tile map]",
	"[pathgate pos]", "[way point]", "[background pos]", "[background animation]",
	"[ani info]", "[filename]", "[layer]", "[order]", "[far sight scroll]",
	"[middle sight scroll]", "[town movable area]", "[town movable area name]",
	"[town movable area with animation]", "[movable area]", "[move town]",
	"[basic animation]", "[open animation]", "[loop animation]",
	"[close animation]", "[animation change area]", "[draw layer]",
	"[virtual movable area]", "[teleport area option]", "[passive object]",
	"[animation]", "[NPC]", "[monster]", "[sound]", "[type]", "[greed]",
	"[dungeon]", "[map name]", "[import script]", "[area]",
	"[left]", "[right]", "[up]", "[down]", "[left up]", "[left down]",
	"[right up]", "[right down]",
]

var unknown: Dictionary = {}
var errors := PackedStringArray()
var rows: Array = []


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var c := LivePvfContent.new()
	c.load_index()
	var a: PvfNewArchive = c.archive
	print("INDEX towns=", c.index.get("towns", []).size())

	var town_maps := {}
	for t in c.index.get("towns", []):
		var key := str(t.get("key", "")) if t is Dictionary else ""
		if key == "":
			continue
		var td: TownDef = c.town(key)
		if td == null:
			continue
		for i in td.area_count():
			var mp: String = td.map_of(i)
			if mp != "":
				town_maps[mp] = true

	var dgns := {}
	var dgn_files := 0
	var dgn_list := a.paths_under("dungeon/")
	for p in dgn_list:
		if p.ends_with(".dgn"):
			dgn_files += 1
			dgns[p.get_file().get_basename()] = true

	var targets := {}
	for mp in town_maps.keys():
		targets[mp] = "town"
	var all_maps := a.paths_under("map/")
	for mp in all_maps:
		if not mp.ends_with(".map"):
			continue
		var dir_name := mp.get_base_dir().get_file()
		if dgns.has(dir_name):
			var prev: String = targets.get(mp, "")
			targets[mp] = "both" if prev == "town" else "dgn"
	print("TARGETS town=", town_maps.size(), " dgn_files=", dgn_files,
			" dgn_names=", dgns.size(), " maps=", targets.size(),
			" elapsed_ms=", Time.get_ticks_msec() - t0)

	var n := 0
	for mp in targets.keys():
		_audit(c, a, str(mp), str(targets[mp]))
		n += 1
		if n % 500 == 0:
			print("... ", n, "/", targets.size(), " unknown=", unknown.size(),
					" errors=", errors.size(), " ms=", Time.get_ticks_msec() - t0)

	_dir(OUT_DIR)
	var f := FileAccess.open(OUT_DIR + "/audit_maps.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"town_maps": town_maps.size(), "dgn_files": dgn_files,
		"dgn_basenames": dgns.size(), "maps": targets.size(),
		"rows": rows, "unknown": unknown, "errors": errors,
	}, "\t"))
	f.close()
	_write_md(targets.size(), town_maps.size(), dgn_files, Time.get_ticks_msec() - t0)
	print("DONE maps=", targets.size(), " rows=", rows.size(), " unknown=", unknown.size(),
			" errors=", errors.size(), " ms=", Time.get_ticks_msec() - t0)
	quit()


func _audit(c: LivePvfContent, a: PvfNewArchive, mp: String, source: String) -> void:
	var row := {"path": mp, "source": source}
	var raw := a.read(mp)
	row["bytes"] = raw.size()
	if raw.is_empty():
		row["empty"] = true
		errors.append(mp + ":empty")
		rows.append(row)
		return
	var doc := PvfNewDoc.parse(a, raw)
	if doc != null:
		var labels: Dictionary = {}
		_collect_labels(doc, labels)
		for k in labels.keys():
			if not KNOWN.has(k):
				var key := str(k)
				if not unknown.has(key):
					unknown[key] = {"count": 0, "examples": []}
				unknown[key]["count"] += 1
				if unknown[key]["examples"].size() < 3:
					unknown[key]["examples"].append(mp)
		row["labels"] = labels.size()
		row["root"] = doc.children.map(func(ch): return ch.label)
		row["unknown"] = labels.keys().filter(func(k): return not KNOWN.has(k))
	else:
		row["doc"] = false
	var r: MapRoom = c.map_room(mp)
	if r == null:
		row["room"] = false
		errors.append(mp + ":room")
		rows.append(row)
		return
	row["room"] = true
	row["tiles"] = r.tiles.size()
	row["ext"] = r.extended_tiles.size()
	row["npcs"] = r.npcs.size()
	row["anims"] = r.anims.size()
	row["bganims"] = r.background_anims.size()
	row["mov"] = r.town_movable.size() / 6
	row["movA"] = r.town_movable_anim.size()
	row["virtual"] = r.virtual_movable.size() / 4
	row["objects"] = r.objects.size()
	row["monsters"] = r.monsters.size()
	row["bgpos"] = r.background_pos
	if r.tiles.is_empty():
		row["no_tiles"] = true
	var miss := PackedStringArray()
	for tp in r.tiles:
		if not a.has(tp): miss.append(tp)
	row["missing_tiles"] = miss.size()
	if not miss.is_empty() and miss.size() <= 3:
		row["missing_tile_paths"] = Array(miss)
	rows.append(row)


func _collect_labels(n: PvfNewDoc.DocNode, out: Dictionary) -> void:
	if n == null:
		return
	if n.label != "":
		out[n.label] = int(out.get(n.label, 0)) + 1
	for ch in n.children:
		_collect_labels(ch, out)


func _write_md(total: int, towns: int, dgn_files: int, ms: int) -> void:
	var lines := PackedStringArray()
	lines.append("# 地图全量审计（twn + dgn）\n")
	lines.append("- 时间：%s" % Time.get_datetime_string_from_system())
	lines.append("- twn 引用 map：%d" % towns)
	lines.append("- dgn 文件：%d" % dgn_files)
	lines.append("- 实际加载 map：%d；耗时 %.1f s" % [total, ms / 1000.0])
	lines.append("- 加载失败：%d" % errors.size())
	lines.append("\n## 未解析字段（按出现次数）\n")
	var keys := unknown.keys()
	keys.sort_custom(func(a, b): return unknown[a]["count"] > unknown[b]["count"])
	for k in keys:
		lines.append("- `%s`：%d 次；例：%s" % [k, unknown[k]["count"], ", ".join(unknown[k]["examples"])])
	lines.append("\n## 加载失败\n")
	for e in errors:
		lines.append("- `%s`" % e)
	var f := FileAccess.open(OUT_DIR + "/audit_maps.md", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()


func _dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
