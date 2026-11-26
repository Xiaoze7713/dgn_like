class_name PackContent
extends RefCounted
## 内容源：读 build_pack.py 编译出来的 JSON 内容包（已移到 _archive/pvf/world，仅作旧实现对照）。
## 运行时只认这个接口，不再碰 PVF token 流；想换回 live PVF 只需再写一个同接口的实现。

const DEFAULT_ROOT := "res://_archive/pvf/world"
const KEY_PATTERN := "[^a-z0-9._-]+"
## 房间级 JSON（map/tile/ani/object）的缓存上限；切图时主动裁剪。
## 这些对象都只在当前房间用，卸图后释放引用即可让 Godot 回收。
const MAX_TRANSIENT := 64
const MAX_DEFS := 128

var root := DEFAULT_ROOT
var index: Dictionary = {}
var warnings: PackedStringArray = []

var _cache: Dictionary = {}          ## 永久：index / towns / dungeons / regions / npcs
var _transient: Dictionary = {}      ## 房间级：maps / tiles / anis / objects
var _transient_order: Array[String] = []
var _defs: Dictionary = {}           ## 解析后的 AniDef / NpcDef 缓存
var _def_order: Array[String] = []
var _key_re: RegEx


func _init(p_root := DEFAULT_ROOT) -> void:
	root = p_root
	_key_re = RegEx.new()
	_key_re.compile(KEY_PATTERN)


## 与 build_pack.py 的 key_of() 必须逐字节一致
func key_of(path: String) -> String:
	return _key_re.sub(path.to_lower(), "_", true)


func load_index() -> Dictionary:
	if not index.is_empty():
		return index
	index = _read_json("index.json")
	if index.is_empty():
		_warn("内容包索引缺失：%s/index.json" % root)
	return index


func has_town(town_key: String) -> bool:
	return _exists("towns/%s.json" % town_key)


func has_dungeon(dungeon_key: String) -> bool:
	return _exists("dungeons/%s.json" % dungeon_key)


func has_map(map_path: String) -> bool:
	return _exists("maps/%s.json" % key_of(map_path))


func has_npc(npc_id: int) -> bool:
	return _exists("npcs/%d.json" % npc_id)


## 跨城镇目标用 PVF 的 town id 找内容包里的城镇 key；找不到返回空串。
func town_key_by_id(town_id: int) -> String:
	var table: Dictionary = load_index().get("towns_by_id", {})
	return str(table.get(str(town_id), ""))


func region(region_key: String) -> RegionDef:
	if region_key == "":
		return null
	var d := _read_json("regions/%s.json" % region_key)
	return RegionDef.from_dict(d, region_key) if not d.is_empty() else null


## 按 UI 需要取所有地区（index 里已经带 town_keys，不读 region JSON）。
func regions() -> Array:
	return load_index().get("regions", [])


func npc(npc_id: int) -> NpcDef:
	if npc_id <= 0:
		return null
	var key := "npc:%d" % npc_id
	if _defs.has(key):
		return _defs[key]
	var d := _read_json("npcs/%d.json" % npc_id)
	if d.is_empty():
		_warn("缺 NPC：%d" % npc_id)
		return null
	var a := ani(str(d.get("ani", "")))
	var def := NpcDef.from_dict(d, a)
	_defs[key] = def
	_def_order.append(key)
	_trim_defs()
	return def


func town(town_key: String) -> TownDef:
	var d := _read_json("towns/%s.json" % town_key)
	return TownDef.from_dict(d) if not d.is_empty() else null


## 一个 .dgn 可能有多个 maze（不同难度/阶段）；默认取第 0 个，用世界地图选难度时再扩展。
func dungeon(dungeon_key: String, maze_index := 0) -> DungeonDef:
	var d := _read_json("dungeons/%s.json" % dungeon_key)
	if d.is_empty():
		return null
	var mazes: Array = d.get("mazes", [])
	var flat := d.duplicate()
	if maze_index >= 0 and maze_index < mazes.size():
		var m: Dictionary = mazes[maze_index]
		for k in m.keys():
			flat[k] = m[k]
	flat["maze_index"] = maze_index
	flat["maze_count"] = mazes.size()
	return DungeonDef.from_dict(flat)


func map_room(map_path: String) -> MapRoom:
	var d := _read_json("maps/%s.json" % key_of(map_path), true)
	return MapRoom.from_dict(d if not d.is_empty() else {"path": map_path})


func tile(til_path: String) -> TileDef:
	var d := _read_json("tiles/%s.json" % key_of(til_path), true)
	return TileDef.from_dict(d) if not d.is_empty() else null


## `.ani`（地图装饰 / 被动对象的帧动画）
func ani(ani_path: String) -> AniDef:
	if ani_path == "":
		return null
	var key := "ani:" + ani_path
	if _defs.has(key):
		return _defs[key]
	var d := _read_json("anis/%s.json" % key_of(ani_path), true)
	var def := AniDef.from_dict(d) if not d.is_empty() else null
	_defs[key] = def
	_def_order.append(key)
	_trim_defs()
	return def


## 被动对象定义（`.obj` → `.act` → base ani 路径）
func object_def(obj_path: String) -> Dictionary:
	if obj_path == "":
		return {}
	var key := "obj:" + obj_path
	if _defs.has(key):
		return _defs[key]
	var d := _read_json("objects/%s.json" % key_of(obj_path), true)
	_defs[key] = d
	_def_order.append(key)
	_trim_defs()
	return d


## 把一组 ani 路径批量读进来（跳过缺失的），key = ani 路径
func anis_for(paths: Array) -> Dictionary:
	var out: Dictionary = {}
	for raw in paths:
		var p := str(raw)
		if p == "" or out.has(p):
			continue
		var a := ani(p)
		if a == null:
			_warn("缺动画：%s" % p)
			continue
		out[p] = a
	return out


## 一次性把房间用到的所有 .til 读出来（TileDef），key = til 路径
func tiles_for(room: MapRoom) -> Dictionary:
	var out: Dictionary = {}
	for p in room.all_tile_paths():
		if out.has(p):
			continue
		var t := tile(p)
		if t == null:
			_warn("缺地砖：%s" % p)
			continue
		out[p] = t
	return out


# ---------------------------------------------------------------- 内部

func _exists(rel: String) -> bool:
	return FileAccess.file_exists(root.path_join(rel))


func _read_json(rel: String, transient := false) -> Dictionary:
	if _cache.has(rel):
		return _cache[rel]
	if _transient.has(rel):
		return _transient[rel]
	var p := root.path_join(rel)
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_warn("JSON 解析失败：%s" % p)
		return {}
	var d: Dictionary = parsed
	if transient:
		_transient[rel] = d
		_transient_order.append(rel)
		_trim_transient()
	else:
		_cache[rel] = d
	return d


func _trim_transient() -> void:
	while _transient_order.size() > MAX_TRANSIENT:
		_transient.erase(_transient_order.pop_front())


func _trim_defs() -> void:
	while _def_order.size() > MAX_DEFS:
		_defs.erase(_def_order.pop_front())


## 切图后主动放掉上一张图的 JSON / 解析结果；正在用的房间节点已 queue_free，
## 这里只减少缓存引用，Godot 会在下一帧回收贴图和 Object。
func trim_cache(max_transient := MAX_TRANSIENT, max_defs := MAX_DEFS) -> void:
	while _transient_order.size() > max_transient:
		_transient.erase(_transient_order.pop_front())
	while _def_order.size() > max_defs:
		_defs.erase(_def_order.pop_front())


func cache_stats() -> Dictionary:
	return {"permanent": _cache.size(), "transient": _transient.size(),
			"defs": _defs.size()}


func _warn(msg: String) -> void:
	warnings.append(msg)
	LogUtil.warn("[PackContent] " + msg)
