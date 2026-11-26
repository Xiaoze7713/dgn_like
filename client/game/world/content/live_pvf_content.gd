class_name LivePvfContent
extends PackContent
## 直接从原生 Script.pvf 读内容的内存实现。
##
## 不再读 assets/pvf/world 里的 JSON；城镇/地区/NPC/地图/地砖/动画都在
## 第一次用到时从 PVF token 流解析，解析结果按房间级缓存，切图时裁剪。
##
## 目前覆盖：
##   城镇列表 / 城镇 area / 地图 / 地砖 / NPC / 怪物 / 被动对象 /
##   地图装饰动画 / 背景动画 / 地区
## 副本（.dgn）仍是空实现。

const STRING_LIST := "list/n_string.lst"

var archive: PvfNewArchive
var pvf_path := ""
var _open_error := OK
var _npc_ids: Dictionary = {}
var _monster_ids: Dictionary = {}
var _object_ids: Dictionary = {}
var _town_ids: Dictionary = {}
var _str_files: Dictionary = {}
var _str_tables: Dictionary = {}
var _town_region: Dictionary = {}
var _region_names: Dictionary = {}
var _npc_cache: Dictionary = {}
var _object_cache: Dictionary = {}
var _monster_cache: Dictionary = {}
var _map_cache: Dictionary = {}
var _map_order: Array[String] = []
var _ani_cache: Dictionary = {}
var _ani_order: Array[String] = []
var _town_cache: Dictionary = {}
var _region_cache: Dictionary = {}
var _warned: Dictionary = {}


func _init(p_pvf := "") -> void:
	super("")
	pvf_path = PathUtil.native(p_pvf if not p_pvf.is_empty() else PathUtil.dnf_script())
	archive = PvfNewArchive.new()
	_open_error = archive.open(pvf_path)
	if _open_error != OK:
		_warn("PVF 打不开：%s err=%d" % [pvf_path, _open_error])


func is_ready() -> bool:
	return _open_error == OK and archive != null and archive.index_ready()


func load_index() -> Dictionary:
	if not index.is_empty():
		return index
	if not is_ready():
		return index
	_load_id_lists()
	_load_string_list()
	var regions := _compile_regions()
	var towns: Array = []
	for rec in _town_id_records():
		var key: String = rec["key"]
		var t := _compile_town(key, int(rec["id"]))
		if t.is_empty():
			continue
		var usable := false
		for a in t.get("areas", []):
			if str(a.get("map", "")) != "" and not archive.read(str(a["map"])).is_empty():
				usable = true
				break
		if not usable:
			continue
		towns.append(t)
		_town_cache[key] = t
		if int(t.get("town_id", -1)) >= 0:
			_town_ids[str(t["town_id"])] = key
	var town_by_id := {}
	for k in _town_ids.keys():
		if not str(k).begins_with("path:"):
			town_by_id[str(k)] = _town_ids[k]
	index = {
		"version": 1,
		"source": pvf_path,
		"towns": towns,
		"towns_by_id": town_by_id,
		"regions": regions,
		"dungeons": [],
		"npcs": _npc_ids.size(),
		"monsters": _monster_ids.size(),
		"objects": _object_ids.size(),
	}
	return index


func has_town(town_key: String) -> bool:
	return _town_key_ok(town_key) != ""


func has_map(map_path: String) -> bool:
	return archive.has(_norm(map_path))


func has_npc(npc_id: int) -> bool:
	return _npc_ids.has(str(npc_id))


func has_monster(monster_id: int) -> bool:
	return _monster_ids.has(str(monster_id))


func town_key_by_id(town_id: int) -> String:
	return str(load_index().get("towns_by_id", {}).get(str(town_id), ""))


func region(region_key: String) -> RegionDef:
	if region_key == "":
		return null
	if _region_cache.has(region_key):
		return _region_cache[region_key]
	for r in load_index().get("regions", []):
		if str(r.get("key", "")) == region_key:
			var def := RegionDef.from_dict(r, region_key)
			_region_cache[region_key] = def
			return def
	return null


func regions() -> Array:
	return load_index().get("regions", [])


func town(town_key: String) -> TownDef:
	var key := _town_key_ok(town_key)
	if key == "":
		return null
	var d: Dictionary
	if _town_cache.has(key):
		d = _town_cache[key]
	else:
		var id := int(load_index().get("towns_by_id", {}).get(key, -1))
		d = _compile_town(key, id)
		if d.is_empty():
			return null
		_town_cache[key] = d
	return TownDef.from_dict(d)


func map_room(map_path: String) -> MapRoom:
	var key := _norm(map_path)
	if _map_cache.has(key):
		_map_order.erase(key)
		_map_order.append(key)
		return _map_cache[key]
	var d := _compile_map(key, 0)
	var room := MapRoom.from_dict(d if not d.is_empty() else {"path": map_path})
	_map_cache[key] = room
	_map_order.append(key)
	while _map_order.size() > 16:
		_map_cache.erase(_map_order.pop_front())
	return room


func tile(til_path: String) -> TileDef:
	var key := _norm(til_path)
	var id := "tile:" + key
	if _defs.has(id):
		return _defs[id]
	var raw := archive.read(key)
	if raw.is_empty():
		return null
	var d := _compile_tile(key, raw)
	var def := TileDef.from_dict(d)
	_defs[id] = def
	_def_order.append(id)
	_trim_defs()
	return def


func ani(ani_path: String) -> AniDef:
	var key := _norm(ani_path)
	if key == "":
		return null
	var id := "ani:" + key
	if _defs.has(id):
		return _defs[id]
	if _ani_cache.has(key):
		var cached: AniDef = _ani_cache[key]
		_defs[id] = cached
		_def_order.append(id)
		_trim_defs()
		return cached
	var raw := archive.read(key)
	if raw.is_empty():
		return null
	var d := _compile_ani(key, raw)
	var def := AniDef.from_dict(d)
	_ani_cache[key] = def
	_ani_order.append(key)
	while _ani_order.size() > 256:
		_ani_cache.erase(_ani_order.pop_front())
	_defs[id] = def
	_def_order.append(id)
	_trim_defs()
	return def


func npc(npc_id: int) -> NpcDef:
	if npc_id <= 0:
		return null
	var id := "npc:%d" % npc_id
	if _defs.has(id):
		return _defs[id]
	if _npc_cache.has(npc_id):
		var cached: NpcDef = _npc_cache[npc_id]
		_defs[id] = cached
		_def_order.append(id)
		_trim_defs()
		return cached
	var path := str(_npc_ids.get(str(npc_id), ""))
	if path == "":
		if not _warned.has(id):
			_warned[id] = true
			_warn("缺 NPC：%d" % npc_id)
		return null
	var raw := archive.read(path)
	if raw.is_empty():
		return null
	var d := _compile_npc(npc_id, path, raw)
	var def := NpcDef.from_dict(d, ani(str(d.get("ani", ""))))
	_npc_cache[npc_id] = def
	_defs[id] = def
	_def_order.append(id)
	_trim_defs()
	return def


func object(obj_path: String) -> ObjectDef:
	var key := _norm(obj_path)
	if key == "":
		return null
	if _object_cache.has(key):
		return _object_cache[key]
	var raw := archive.read(key)
	if raw.is_empty():
		return null
	var d := _compile_object(key, raw)
	if d.is_empty():
		return null
	var def := ObjectDef.from_dict(d)
	_object_cache[key] = def
	return def


func object_def(obj_path: String) -> Dictionary:
	var def := object(obj_path)
	if def == null:
		return {}
	return {"id": def.id, "path": def.path, "name": def.name, "layer": def.layer,
			"pass_type": def.pass_type, "basic_action": def.basic_action,
			"ani": def.ani_path, "sub_anis": def.sub_anis}


func monster(monster_id: int) -> MonsterDef:
	if monster_id <= 0:
		return null
	if _monster_cache.has(monster_id):
		return _monster_cache[monster_id]
	var path := str(_monster_ids.get(str(monster_id), ""))
	if path == "":
		return null
	var raw := archive.read(path)
	if raw.is_empty():
		return null
	var d := _compile_monster(monster_id, path, raw)
	if d.is_empty():
		return null
	var def := MonsterDef.from_dict(d)
	_monster_cache[monster_id] = def
	return def


func anis_for(paths: Array) -> Dictionary:
	var out: Dictionary = {}
	for raw in paths:
		var p := str(raw)
		if p == "" or out.has(p):
			continue
		var a := ani(p)
		if a != null:
			out[p] = a
	return out


func tiles_for(room: MapRoom) -> Dictionary:
	var out: Dictionary = {}
	for p in room.all_tile_paths():
		if out.has(p):
			continue
		var t := tile(p)
		if t != null:
			out[p] = t
	return out


func cache_stats() -> Dictionary:
	return {"permanent": _town_cache.size() + _region_cache.size(), "transient": _map_cache.size(),
			"defs": _defs.size(), "npcs": _npc_cache.size(),
			"monsters": _monster_cache.size(), "objects": _object_cache.size()}


func trim_cache(max_transient := MAX_TRANSIENT, max_defs := MAX_DEFS) -> void:
	while _transient_order.size() > max_transient:
		_transient.erase(_transient_order.pop_front())
	while _def_order.size() > max_defs:
		_defs.erase(_def_order.pop_front())
	while _map_order.size() > max_transient:
		_map_cache.erase(_map_order.pop_front())
	while _ani_order.size() > 256:
		_ani_cache.erase(_ani_order.pop_front())


# ---------------------------------------------------------------- 基础

func _norm(p: String) -> String:
	var parts := PackedStringArray()
	for seg in p.replace("\\", "/").to_lower().split("/", true):
		if seg == "" or seg == ".":
			continue
		if seg == "..":
			if not parts.is_empty():
				parts.remove_at(parts.size() - 1)
			continue
		parts.append(seg)
	return "/".join(parts)


func _read(path: String) -> PackedByteArray:
	return archive.read(_norm(path))


func _doc(path: String) -> PvfNewDoc.DocNode:
	var raw := _read(path)
	if raw.is_empty():
		return null
	return PvfNewDoc.parse(archive, raw)


func _read_lst(path: String) -> Array:
	var raw := _read(path)
	if raw.is_empty():
		return []
	var root := PvfNewDoc.parse(archive, raw)
	var vals: Array = root.values
	var out: Array = []
	var i := 0
	while i + 1 < vals.size():
		if vals[i] is int or vals[i] is float:
			out.append({"id": int(vals[i]), "path": str(vals[i + 1])})
			i += 2
		else:
			i += 1
	return out


func _load_id_lists() -> void:
	for rec in _read_lst("list/town.lst"):
		var p := _norm(str(rec["path"]))
		_town_ids[str(rec["id"])] = p
		_town_ids["path:" + p] = str(rec["id"])
	for rec in _read_lst("list/npc.lst"):
		_npc_ids[str(rec["id"])] = _norm(str(rec["path"]))
	for rec in _read_lst("list/monster.lst"):
		_monster_ids[str(rec["id"])] = _norm(str(rec["path"]))
	for rec in _read_lst("list/passiveobject.lst"):
		_object_ids[str(rec["id"])] = _norm(str(rec["path"]))


func _load_string_list() -> void:
	for rec in _read_lst(STRING_LIST):
		_str_files[str(rec["id"])] = _norm(str(rec["path"]))
	for n in 20:
		_str_tables[str(n)] = {}


func _string_table(index: String) -> Dictionary:
	if _str_tables.has(index) and not (_str_tables[index] as Dictionary).is_empty():
		return _str_tables[index]
	var rel := str(_str_files.get(index, ""))
	if rel == "":
		return {}
	var raw := _read(rel)
	var out: Dictionary = {}
	if raw.is_empty():
		_str_tables[index] = out
		return out
	var text := raw.get_string_from_utf16()
	for line in text.split("\n"):
		line = line.strip_edges()
		if line == "" or line.begins_with("//") or not line.contains(">"):
			continue
		var kv := line.split(">", true, 1)
		if kv.size() == 2:
			out[kv[0].strip_edges()] = kv[1].strip_edges()
	_str_tables[index] = out
	return out


func _resolve_string(v: String) -> String:
	var re := RegEx.new()
	re.compile("<(\\d+)::([^>]+)>")
	var m := re.search(v)
	if m == null:
		return v
	return str(_string_table(m.get_string(1)).get(m.get_string(2), v))


func _resolve_rel(base_dir: String, rel: String) -> String:
	# 先拼接、后折叠 ..；不能先 _norm(rel)，否则开头的 .. 会被当成根路径丢掉。
	var raw := rel.replace("\\", "/").to_lower().lstrip("/")
	for base in [base_dir, "map/", ""]:
		var f := _norm(base + raw)
		if archive.has(f):
			return f
	return ""


# ---------------------------------------------------------------- 城镇/地区

func _town_id_records() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for k in _town_ids.keys():
		if not str(k).begins_with("path:"):
			continue
		var p := str(k).substr(5)
		var id := int(_town_ids[k])
		seen[p] = true
		out.append({"id": id, "key": p})
	# hendonmyre 这类旧 town 不在 town.lst 里，仍然列出来
	for p in ["town/hendonmyre.twn", "town/centralpark.twn", "town/metrocenter.twn", "town/devildom_contact.twn"]:
		if not seen.has(p) and archive.has(p):
			out.append({"id": -1, "key": p})
	return out


func _town_key_ok(town_key: String) -> String:
	var k := _norm(town_key)
	if k == "":
		return ""
	if not k.contains("/") and k.begins_with("town_"):
		k = "town/" + k.substr(5)
	if not k.begins_with("town/"):
		k = "town/" + k
	if archive.has(k):
		return k
	return ""


func _compile_town(key: String, town_id: int) -> Dictionary:
	var root := _doc(key)
	if root == null:
		return {}
	var areas := _parse_areas(root)
	var names: Array = root.first("[name]").strings() if root.first("[name]") != null else []
	var subs: Array = root.first("[sub name]").strings() if root.first("[sub name]") != null else []
	var region_key := str(_town_region.get(str(town_id), ""))
	var rec := {
		"path": key,
		"key": key,
		"id": town_id,
		"region": region_key,
		"region_name": str(_region_name(region_key)),
		"name": names,
		"sub_name": subs,
		"name_text": [_resolve_string(str(names[0]))] if names.size() > 0 else [],
		"sub_name_text": [_resolve_string(str(subs[0]))] if subs.size() > 0 else [],
		"areas": areas,
		"town_id": town_id,
		"dungeon_gate_ids": [],
	}
	for a in areas:
		if str(a.get("type", "")) == "dungeon gate" and not a.get("args", []).is_empty():
			rec["dungeon_gate_ids"].append(str(a["args"][0]))
	if town_id < 0:
		var inferred := _infer_town_id(key, areas)
		if inferred >= 0:
			rec["id"] = inferred
			rec["town_id"] = inferred
			_town_ids[str(inferred)] = key
	return rec


func _infer_town_id(key: String, areas: Array) -> int:
	if areas.is_empty():
		return -1
	var map_path := str(areas[0].get("map", ""))
	if map_path == "":
		return -1
	var root := _doc(map_path)
	if root == null:
		return -1
	var vals: Array = root.first("[town movable area]").ints() if root.first("[town movable area]") != null else []
	var counts: Dictionary = {}
	for i in range(0, vals.size() - 5, 6):
		var target := int(vals[i + 4])
		if target > 0:
			counts[target] = int(counts.get(target, 0)) + 1
	var best := -1
	var best_n := 0
	for k in counts.keys():
		if int(counts[k]) > best_n:
			best_n = int(counts[k])
			best = int(k)
	return best


func _parse_areas(root: PvfNewDoc.DocNode) -> Array:
	var out: Array = []
	var ranks := {"dungeon gate": 5, "gate": 4, "normal": 3, "safe zone": 2, "housing": 1, "open party list area": 0}
	for node in root.all("[area]"):
		var vals: Array = node.values
		var area := {"index": -1, "map": "", "type": "normal", "args": [], "minimap": null, "phase": []}
		if vals.size() >= 1:
			area["index"] = int(vals[0]) if (vals[0] is int or vals[0] is float) else -1
		if vals.size() >= 2 and not (vals[1] is int or vals[1] is float):
			area["map"] = _resolve_town_map(str(vals[1]))
		var best := -1
		for seq in _walk_values(node):
			var i := 0
			while i < seq.size():
				var s := str(seq[i]) if not (seq[i] is int or seq[i] is float) else ""
				if s == "[minimap rect]" and i + 4 < seq.size():
					area["minimap"] = [int(seq[i + 1]), int(seq[i + 2]), int(seq[i + 3]), int(seq[i + 4])]
					i += 5
					continue
				var bare := s.substr(1, s.length() - 2) if s.begins_with("[") and s.ends_with("]") else ""
				if ranks.has(bare):
					var args: Array = []
					i += 1
					while i < seq.size() and not (not (seq[i] is int or seq[i] is float) and str(seq[i]).begins_with("[")):
						args.append(seq[i])
						i += 1
					if int(ranks[bare]) > best:
						best = int(ranks[bare])
						area["type"] = bare
						area["args"] = args
					continue
				i += 1
		out.append(area)
	return out


func _resolve_town_map(rel: String) -> String:
	var v := _norm(rel)
	var bare := v.trim_prefix("map/")
	for full in ["map/" + bare, bare, v]:
		if archive.has(full):
			return full
	return "map/" + v


func _walk_values(n: PvfNewDoc.DocNode) -> Array:
	var out: Array = [n.values]
	for c in n.children:
		out.append_array(_walk_values(c))
	return out


func _compile_regions() -> Array:
	var out: Array = []
	_town_region.clear()
	for rec in _read_lst("list/region.lst"):
		var path := _norm(str(rec["path"]))
		var root := _doc(path)
		if root == null:
			continue
		var rkey := path.get_file().get_basename()
		var names: Array = root.first("[name]").strings() if root.first("[name]") != null else []
		var towns: Array = root.first("[towns]").ints() if root.first("[towns]") != null else []
		var mm: Array = root.first("[minimap]").strings() if root.first("[minimap]") != null else []
		var entry := {
			"path": path, "key": rkey, "name": names,
			"name_text": [_resolve_string(str(names[0]))] if names.size() > 0 else [],
			"towns": towns, "town_keys": [], "minimap": mm,
		}
		_region_names[rkey] = str(entry["name_text"][0]) if not entry["name_text"].is_empty() else rkey
		for t in towns:
			_town_region[str(int(t))] = rkey
		out.append(entry)
	# 填 town_keys
	for r in out:
		for t in r["towns"]:
			var k := str(_town_ids.get(str(int(t)), ""))
			if k != "":
				r["town_keys"].append(k)
	return out


func _region_name(region_key: String) -> String:
	if region_key == "":
		return ""
	return str(_region_names.get(region_key, region_key))


# ---------------------------------------------------------------- 地图/地砖/动画

func _compile_map(path: String, depth := 0) -> Dictionary:
	var root := _doc(path)
	if root == null:
		return {}
	var base_dir := path.get_base_dir() + "/"
	var data := {
		"path": path, "type": "", "greed": "", "dungeon": 0, "name": [],
		"tiles": [], "extended_tiles": [], "extended_map": [], "sight": {},
		"pathgate": [], "way_point": [], "background_pos": 0,
		"town_movable": [], "town_movable_name": [], "town_movable_anim": [], "virtual_movable": [],
		"teleport": [], "monsters": [], "npcs": [], "objects": [], "anims": [],
		"background_anims": [], "sound": [],
	}
	var tn := root.first("[tile]")
	if tn != null:
		for v in tn.strings():
			var got := _resolve_rel(base_dir, str(v))
			data["tiles"].append(got if got != "" else "")
	var ext := root.first("[extended tile]")
	if ext != null:
		if ext.children.size() > 0:
			var by_idx := {}
			for files in ext.all("[tile files]"):
				var tv: Array = files.values
				for i in range(tv.size() - 1):
					if (tv[i] is int or tv[i] is float) and tv[i + 1] is String:
						var got := _resolve_rel(base_dir, str(tv[i + 1]))
						if got != "":
							by_idx[int(tv[i])] = got
			var keys := by_idx.keys()
			keys.sort()
			for k in keys:
				data["extended_tiles"].append(by_idx[k])
			for tm in ext.all("[tile map]"):
				data["extended_map"] = tm.ints()
		else:
			for v in ext.strings():
				var got := _resolve_rel(base_dir, str(v))
				if got != "":
					data["extended_tiles"].append(got)
	var type_n := root.first("[type]")
	if type_n != null:
		var ss := type_n.strings()
		if ss.size() > 0:
			data["type"] = str(ss[0]).strip_edges().trim_prefix("[").trim_suffix("]")
	var greed_n := root.first("[greed]")
	if greed_n != null:
		var ss := greed_n.strings()
		if ss.size() > 0:
			data["greed"] = str(ss[0])
	var dun_n := root.first("[dungeon]")
	if dun_n != null:
		var ii := dun_n.ints()
		if ii.size() > 0:
			data["dungeon"] = ii[0]
	var name_n := root.first("[map name]")
	if name_n != null:
		data["name"] = name_n.strings()
	var bg_n := root.first("[background pos]")
	if bg_n != null:
		var ii := bg_n.ints()
		if ii.size() > 0:
			data["background_pos"] = ii[0]
	# 背景动画：一层一个 [ani info]，不是 [background animation] 的直接 values。
	# 原实现只找 [background pos]，所以 gent 的 GentFar/GentMid 永远不进 background_anims。
	var bga_n := root.first("[background animation]")
	if bga_n != null:
		for info in bga_n.all("[ani info]"):
			var raw_path := ""
			var fn_n: PvfNewDoc.DocNode = info.first("[filename]")
			if fn_n != null:
				var fs: Array = fn_n.strings()
				if fs.size() > 0:
					raw_path = str(fs[0])
			if raw_path == "":
				continue
			var layer := ""
			var layer_n: PvfNewDoc.DocNode = info.first("[layer]")
			if layer_n != null:
				var ls: Array = layer_n.strings()
				if ls.size() > 0:
					layer = str(ls[0]).trim_prefix("[").trim_suffix("]")
			var order := ""
			var order_n: PvfNewDoc.DocNode = info.first("[order]")
			if order_n != null:
				var os: Array = order_n.strings()
				if os.size() > 0:
					order = str(os[0]).trim_prefix("[").trim_suffix("]")
			var bpath := _resolve_rel(base_dir, raw_path)
			data["background_anims"].append({"ani": raw_path, "path": bpath, "layer": layer, "order": order})
	# 视差滚动量（[far sight scroll] / [middle sight scroll]，单位 %），Builder 已经读 room.sight。
	for pair in [["far", "[far sight scroll]"], ["middle", "[middle sight scroll]"]]:
		var sight_n := root.first(str(pair[1]))
		if sight_n != null:
			var si := sight_n.ints()
			if si.size() > 0:
				data["sight"][str(pair[0])] = si[0]
	var tm_n := root.first("[town movable area]")
	if tm_n != null:
		data["town_movable"] = tm_n.ints()
	var tmn_n := root.first("[town movable area name]")
	if tmn_n != null:
		data["town_movable_name"] = tmn_n.strings()
	# [town movable area with animation]：传送门本体在 [movable area] 子节点里，
	# 每个子节点有 [area] x y w h + [move town] town area + 4 个 ani。
	# 不能只读 [town movable area]：gent 的 Seria 门就是这种结构。
	var tma_n := root.first("[town movable area with animation]")
	if tma_n != null:
		var ma_nodes: Array = tma_n.all("[movable area]")
		if ma_nodes.is_empty():
			ma_nodes = [tma_n]
		for ma in ma_nodes:
			var area_n: PvfNewDoc.DocNode = ma.first("[area]")
			if area_n == null:
				continue
			var av: Array = area_n.ints()
			if av.size() < 4:
				continue
			var mt_n: PvfNewDoc.DocNode = ma.first("[move town]")
			var mt: Array = mt_n.ints() if mt_n != null else []
			var entry := {
				"x": int(av[0]), "y": int(av[1]), "w": int(av[2]), "h": int(av[3]),
				"town": int(mt[0]) if mt.size() > 0 else -1,
				"area": int(mt[1]) if mt.size() > 1 else -1,
			}
			for pair in [["basic", "[basic animation]"], ["open", "[open animation]"],
					["loop", "[loop animation]"], ["close", "[close animation]"]]:
				var an_n: PvfNewDoc.DocNode = ma.first(str(pair[1]))
				var ap := ""
				if an_n != null:
					var ss: Array = an_n.strings()
					if ss.size() > 0:
						ap = _resolve_rel(base_dir, str(ss[0]))
				entry[str(pair[0])] = ap
			var ca_n: PvfNewDoc.DocNode = ma.first("[animation change area]")
			entry["change_area"] = ca_n.ints() if ca_n != null else []
			var dl_n: PvfNewDoc.DocNode = ma.first("[draw layer]")
			entry["layer"] = str(dl_n.strings()[0]).trim_prefix("[").trim_suffix("]") if dl_n != null and not dl_n.strings().is_empty() else ""
			data["town_movable_anim"].append(entry)
	var vm_n := root.first("[virtual movable area]")
	if vm_n != null:
		data["virtual_movable"] = vm_n.ints()
	var pg_n := root.first("[pathgate pos]")
	if pg_n != null:
		data["pathgate"] = pg_n.ints()
	var wp_n := root.first("[way point]")
	if wp_n != null:
		data["way_point"] = wp_n.ints()
	var sound_n := root.first("[sound]")
	if sound_n != null:
		data["sound"] = sound_n.strings()
	# NPC
	# 一条记录不一定是 5 个值：部分地图会在方向前插一个条件标签，
	# 例如 100001775 [visible on dungeon if quest clear] [left] 633 136 0。
	# 按“id → 任意个 [..] 标签 → dir → x y z”扫描，不能按固定 5 个分组。
	var npc_n := root.first("[NPC]")
	if npc_n != null:
		var v: Array = npc_n.values
		var i := 0
		while i < v.size():
			var nid := int(v[i])
			i += 1
			var cond: Array = []
			var ndir := ""
			while i < v.size() and v[i] is String and str(v[i]).begins_with("["):
				var lab := str(v[i])
				i += 1
				if lab in ["[left]", "[right]", "[up]", "[down]", "[left up]", "[right up]", "[left down]", "[right down]"]:
					ndir = lab
					break
				cond.append(lab)
			if i + 2 >= v.size():
				break
			var nx := int(v[i])
			var ny := int(v[i + 1])
			var nz := int(v[i + 2])
			i += 3
			var rec := {"id": str(nid), "dir": ndir, "x": nx, "y": ny, "z": nz}
			if not cond.is_empty():
				rec["condition"] = cond
			var np := str(_npc_ids.get(str(rec["id"]), ""))
			if np != "":
				rec["path"] = np
			data["npcs"].append(rec)
	# 被动对象：可直接读 `.obj [basic motion]`，也可经 `.act [BASE ANI]`。
	var po_n := root.first("[passive object]")
	if po_n != null:
		for rec in _compile_passive_objects(po_n, base_dir):
			data["objects"].append(rec)
	# 怪物：一条 [monster] 可含多条 8-int 记录，见 _parse_monsters()。
	var mon_n := root.first("[monster]")
	if mon_n != null:
		data["monsters"] = _parse_monsters(mon_n)
	# 装饰动画
	var an := root.first("[animation]")
	if an != null:
		var v: Array = an.values
		for i in range(0, v.size() - 4, 5):
			var ap := _resolve_rel(base_dir, str(v[i]))
			data["anims"].append({"ani": v[i], "path": ap, "layer": str(v[i + 1]).trim_prefix("[").trim_suffix("]"),
				"x": int(v[i + 2]), "y": int(v[i + 3]), "z": int(v[i + 4])})
	var imp := root.first("[import script]")
	if imp != null and depth < 4:
		var ss := imp.strings()
		if ss.size() > 0:
			var ref := _norm(str(ss[0]))
			var pp := _resolve_import(base_dir, ref)
			if pp != "":
				var parent := _compile_map(pp, depth + 1)
				for k in parent.keys():
					if k in ["path", "import"]:
						continue
					if not data.get(k):
						data[k] = parent[k]
			else:
				data["import_missing"] = true
	return data


## [import script] 的父图不一定是字面路径：客户端里常见 (f)/(r) 两个变体，
## 例如 Common/Gate_Seria.map 实际是 map/common/(f)gate_seria.map。
## 这里先按普通相对路径找，再补 (f)/(r) 变体；仍找不到才记 import_missing。
func _resolve_import(base_dir: String, ref: String) -> String:
	var dir := ref.get_base_dir()
	var file := ref.get_file()
	var cands: Array[String] = []
	for c in [base_dir + ref, "map/" + ref, ref]:
		cands.append(_norm(c))
	for tag in ["(f)", "(r)"]:
		for c in [base_dir + dir + "/" + tag + file, "map/" + dir + "/" + tag + file, dir + "/" + tag + file]:
			cands.append(_norm(c))
	for c in cands:
		if archive.has(c):
			return c
	return ""


func _compile_tile(path: String, raw: PackedByteArray) -> Dictionary:
	var root := PvfNewDoc.parse(archive, raw)
	var img_n := root.first("[IMAGE]")
	# `[IMAGE]` 的值是“路径 + 帧号”，混着字符串和 int；用 strings() 会把帧号丢掉，
	# 结果所有地砖都落在 frame 0（gent 的 Imperial_Palace_Tile 5 张图就全用 00）。
	var img: Array = img_n.values if img_n != null else []
	var pass_n := root.first("[pass type]")
	var vals: Array = pass_n.ints() if pass_n != null else []
	var pos_n := root.first("[img pos]")
	var ip: Array = pos_n.ints() if pos_n != null else []
	var tt_n := root.first("[tile type]")
	var tt: Array = tt_n.strings() if tt_n != null else []
	return {"path": path, "img": str(img[0]) if img.size() > 0 else "", "frame": int(img[1]) if img.size() > 1 else 0,
		"img_pos": ip[0] if ip.size() > 0 else 0, "tile_type": str(tt[0]).trim_prefix("[").trim_suffix("]") if tt.size() > 0 else "",
		"cols": 14, "rows": vals.size() / 14, "pass": vals}


# ---------------------------------------------------------------- 怪物/被动对象

## `[monster]` 一个 label 里可以塞 N 条记录：8 个 int + `[fixed|half|ratio]`
## + 类型 token（`[normal|champion|super champion|boss]`）。类型前还可能插
## `[NPC]` + 5 个值（击杀后出现的 NPC），所以按 token 流扫描，不能按固定宽度切。
func _parse_monsters(node: PvfNewDoc.DocNode) -> Array:
	var vals: Array = node.values
	var out: Array = []
	var i := 0
	while i < vals.size():
		while i < vals.size() and not (vals[i] is int or vals[i] is float):
			i += 1
		if i + 7 >= vals.size():
			break
		var ints: Array[int] = []
		while i < vals.size() and ints.size() < 8 and (vals[i] is int or vals[i] is float):
			ints.append(int(vals[i]))
			i += 1
		if ints.size() < 8:
			break
		var rec := {
			"id": ints[0], "auto": ints[1], "level": ints[2],
			"x": ints[3], "y": ints[4], "z": ints[5],
			"rdrop": ints[6], "sdrop": ints[7],
			"copy": "fixed", "kind": "normal", "npc": null, "extra": [],
		}
		while i < vals.size():
			var tok := str(vals[i])
			if tok == "[fixed]" or tok == "[half]" or tok == "[ratio]":
				rec["copy"] = tok.trim_prefix("[").trim_suffix("]")
				i += 1
			elif tok == "[normal]" or tok == "[champion]" or tok == "[super champion]" or tok == "[boss]":
				rec["kind"] = tok.trim_prefix("[").trim_suffix("]")
				i += 1
				break
			elif tok == "[NPC]":
				i += 1
				# 官方写法固定 5 个值：id、朝向 token、x、y、z。朝向本身以 `[` 开头，
				# 不能拿“是否以 [ 开头”当终止条件，否则会把朝向吐回去。
				var npc: Array = []
				for _k in 5:
					if i < vals.size():
						npc.append(vals[i])
						i += 1
				rec["npc"] = npc
			else:
				rec["extra"].append(tok)
				i += 1
				if rec["extra"].size() > 8:
					break
		out.append(rec)
	return out


## `[passive object]` 固定 4 个 int：id x y z；id 查 list/passiveobject.lst，
## 再读 `.obj` 的 `[basic action]`/`[basic motion]`。对象本身不参与通行，
## 只负责渲染；`pass_type` 先存下来，等对象碰撞逻辑再消费。
func _compile_passive_objects(node: PvfNewDoc.DocNode, base_dir: String) -> Array:
	var vals: Array = node.values
	var out: Array = []
	var i := 0
	while i + 3 < vals.size():
		if not (vals[i] is int or vals[i] is float):
			i += 1
			continue
		var oid := int(vals[i])
		var ox := int(vals[i + 1])
		var oy := int(vals[i + 2])
		var oz := int(vals[i + 3])
		i += 4
		var rec := {"id": oid, "x": ox, "y": oy, "z": oz, "obj": "", "ani": "",
			"layer": "normal", "pass_type": ""}
		var obj_path := str(_object_ids.get(str(oid), ""))
		if obj_path != "":
			rec["obj"] = obj_path
			var def := object(obj_path)
			if def != null:
				rec["ani"] = def.ani_path
				rec["layer"] = def.layer
				rec["pass_type"] = def.pass_type
		out.append(rec)
	return out


func _compile_object(path: String, raw: PackedByteArray) -> Dictionary:
	var root := PvfNewDoc.parse(archive, raw)
	if root == null:
		return {}
	var base := path.get_base_dir() + "/"
	var name := _first_string(root, "[name]")
	var width := _node_ints(root, "[width]")
	var layer := _token(_first_string(root, "[layer]"))
	var pass_type := _token(_first_string(root, "[pass type]"))
	var act_rel := _first_string(root, "[basic action]")
	var motion := _first_string(root, "[basic motion]")
	var act_path := ""
	var ani_path := ""
	var sub_anis: Array = []
	if act_rel != "":
		act_path = _resolve_rel(base, act_rel)
		if act_path != "":
			var act := _doc(act_path)
			if act != null:
				var abase := act_path.get_base_dir() + "/"
				var bnode := _find_deep(act, "[BASE ANI]")
				if bnode != null:
					ani_path = _resolve_rel(abase, _first_string(bnode, ""))
				for snode in _find_deep_all(act, "[SUB ANI]"):
					var sv: Array = snode.values
					if sv.is_empty():
						continue
					var sp := _resolve_rel(abase, str(sv[0]))
					if sp != "":
						sub_anis.append({"ani": sp, "start": int(sv[1]) if sv.size() > 1 else 0,
							"count": int(sv[2]) if sv.size() > 2 else 1})
	elif motion != "":
		ani_path = _resolve_rel(base, motion)
	return {"path": path, "name": _resolve_string(name), "width": width,
		"layer": layer if layer != "" else "normal", "pass_type": pass_type,
		"basic_action": act_path, "ani": ani_path, "sub_anis": sub_anis}


func _compile_monster(monster_id: int, path: String, raw: PackedByteArray) -> Dictionary:
	var root := PvfNewDoc.parse(archive, raw)
	if root == null:
		return {}
	var base := path.get_base_dir() + "/"
	var stay := _first_string(root, "[waiting motion]")
	var move := _first_string(root, "[move motion]")
	return {"id": monster_id, "path": path, "name": _resolve_string(_first_string(root, "[name]")),
		"width": _node_ints(root, "[width]"),
		"stay_ani": _resolve_rel(base, stay) if stay != "" else "",
		"move_ani": _resolve_rel(base, move) if move != "" else ""}


func _first_string(node: PvfNewDoc.DocNode, label: String) -> String:
	if node == null:
		return ""
	if label == "":
		var ss := node.strings()
		return str(ss[0]) if ss.size() > 0 else ""
	var n := node.first(label)
	if n == null:
		return ""
	var ss := n.strings()
	return str(ss[0]) if ss.size() > 0 else ""


func _node_ints(node: PvfNewDoc.DocNode, label: String) -> Array:
	if node == null:
		return []
	var n := node.first(label)
	if n == null:
		return []
	return n.ints()


func _token(s: String) -> String:
	return s.trim_prefix("[").trim_suffix("]")


func _find_deep(node: PvfNewDoc.DocNode, label: String) -> PvfNewDoc.DocNode:
	if node == null:
		return null
	for c in node.children:
		if c.label == label:
			return c
		var got := _find_deep(c, label)
		if got != null:
			return got
	return null


func _find_deep_all(node: PvfNewDoc.DocNode, label: String, out: Array = []) -> Array:
	if node == null:
		return out
	for c in node.children:
		if c.label == label:
			out.append(c)
		_find_deep_all(c, label, out)
	return out


func _compile_ani(path: String, raw: PackedByteArray) -> Dictionary:
	var root := PvfNewDoc.parse(archive, raw)
	var img := ""
	var loop := 0
	var shadow := 0
	var frames: Array = []
	var cur: Dictionary = {}
	for node in root.children:
		var lab: String = node.label
		match lab:
			"[IMAGE PATH]":
				var ss: Array = node.strings()
				if ss.size() > 0:
					img = str(ss[0])
			"[FRAME MAX]":
				var ii: Array = node.ints()
				if ii.size() > 0:
					pass
			"[LOOP]":
				var ii: Array = node.ints()
				if ii.size() > 0:
					loop = ii[0]
			"[SHADOW]":
				var ii: Array = node.ints()
				if ii.size() > 0:
					shadow = ii[0]
			_:
				if lab.begins_with("[FRAME") and lab != "[FRAME MAX]":
					cur = {"img": img, "frame": 0, "dx": 0, "dy": 0, "delay": 100, "effect": "", "rgba": []}
					frames.append(cur)
				elif not cur.is_empty():
					if lab == "[IMAGE EX]":
						var ii: Array = node.ints()
						if ii.size() >= 2:
							cur["frame"] = ii[1]
						cur["img"] = img
					elif lab == "[IMAGE POS]":
						var ii: Array = node.ints()
						if ii.size() >= 2:
							cur["dx"] = ii[0]
							cur["dy"] = ii[1]
					elif lab == "[DELAY]":
						var ii: Array = node.ints()
						if ii.size() > 0:
							cur["delay"] = ii[0]
					elif lab == "[GRAPHIC EFFECT]":
						var ss: Array = node.strings()
						if ss.size() > 0:
							cur["effect"] = str(ss[0])
					elif lab == "[RGBA]":
						cur["rgba"] = node.ints()
	return {"path": path, "loop": loop, "shadow": shadow, "frame_max": frames.size(), "frames": frames}


func _compile_npc(npc_id: int, path: String, raw: PackedByteArray) -> Dictionary:
	var root := PvfNewDoc.parse(archive, raw)
	var base := path.get_base_dir() + "/"
	var ani_rel := ""
	var fa := root.first("[field animation]")
	if fa != null and fa.strings().size() > 0:
		ani_rel = str(fa.strings()[0])
	var ani_path := ""
	if ani_rel != "":
		ani_path = _resolve_rel(base, ani_rel)
		if ani_path == "":
			ani_path = _resolve_rel("npc/", ani_rel)
	var names: Array = _resolve_values(root.first("[name]"))
	var fields: Array = _resolve_values(root.first("[field name]"))
	var role := ""
	var rn := root.first("[role]")
	if rn != null and rn.strings().size() > 0:
		role = str(rn.strings()[0]).trim_prefix("[").trim_suffix("]")
	var face_img := ""
	var face_frame := 0
	var fn := root.first("[small face]")
	if fn != null:
		var fs := fn.strings()
		if fs.size() > 0:
			face_img = str(fs[0])
		if fs.size() > 1:
			face_frame = int(fs[1])
	return {"id": npc_id, "path": path, "name": names, "field_name": fields, "role": role,
		"ani": ani_path, "face": {"img": face_img, "frame": face_frame}}


func _resolve_values(n: PvfNewDoc.DocNode) -> Array:
	var out: Array = []
	if n == null:
		return out
	for s in n.strings():
		out.append(_resolve_string(str(s)))
	return out


func _warn(msg: String) -> void:
	warnings.append(msg)
	LogUtil.warn("[LivePvfContent] " + msg)
