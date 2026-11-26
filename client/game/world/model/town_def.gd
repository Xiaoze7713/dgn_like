class_name TownDef
extends RefCounted
## 一个城镇（.twn 编译产物）：若干 area，每个 area 是一张 .map + 一条通行规则。
## area.type ∈ normal / gate / dungeon gate / safe zone / housing / open party list area
## area.args：[gate] 是 x y；[dungeon gate] 是副本 id。

var path := ""
var town_id := -1
var region := ""
var region_name := ""
var name_key := ""
var sub_name_key := ""
var name_text := ""
var sub_name_text := ""
var areas: Array = []
var dungeon_gate_ids: Array = []


static func from_dict(d: Dictionary) -> TownDef:
	var t := TownDef.new()
	t.path = str(d.get("path", ""))
	t.town_id = int(d.get("id", -1))
	t.region = str(d.get("region", ""))
	t.region_name = str(d.get("region_name", ""))
	t.name_key = str(d.get("name", ""))
	t.sub_name_key = str(d.get("sub_name", ""))
	var names: Array = d.get("name_text", [])
	t.name_text = str(names[0]) if not names.is_empty() else ""
	var subs: Array = d.get("sub_name_text", [])
	t.sub_name_text = str(subs[0]) if not subs.is_empty() else ""
	t.areas = d.get("areas", [])
	t.dungeon_gate_ids = d.get("dungeon_gate_ids", [])
	return t


func display_name() -> String:
	return name_text if name_text != "" else name_key


func area_count() -> int:
	return areas.size()


func area(i: int) -> Dictionary:
	return areas[i] if i >= 0 and i < areas.size() else {}


func map_of(i: int) -> String:
	return str(area(i).get("map", ""))


## 城镇里所有 [dungeon gate] area 的 (area 索引, 副本 id)
func dungeon_entrances() -> Array:
	var out := []
	for a in areas:
		if str(a.get("type", "")) != "dungeon gate":
			continue
		var args: Array = a.get("args", [])
		if args.is_empty():
			continue
		out.append({"area": int(a.get("index", -1)), "dungeon_id": int(args[0])})
	return out


## 找与 rect 相邻（某方向上贴边）的 area：城镇切换就靠这个
func neighbor_of(area_index: int, dir_name: String) -> int:
	var cur: Dictionary = area(area_index)
	var rect := _rect(cur)
	if rect.size == Vector2.ZERO:
		return -1
	for i in areas.size():
		if i == area_index:
			continue
		var r := _rect(area(i))
		if r.size == Vector2.ZERO:
			continue
		match dir_name:
			"right":
				if is_equal_approx(r.position.x, rect.end.x) and _overlap(r.position.y, r.end.y, rect.position.y, rect.end.y):
					return i
			"left":
				if is_equal_approx(r.end.x, rect.position.x) and _overlap(r.position.y, r.end.y, rect.position.y, rect.end.y):
					return i
			"down":
				if is_equal_approx(r.position.y, rect.end.y) and _overlap(r.position.x, r.end.x, rect.position.x, rect.end.x):
					return i
			"up":
				if is_equal_approx(r.end.y, rect.position.y) and _overlap(r.position.x, r.end.x, rect.position.x, rect.end.x):
					return i
	return -1


## [minimap rect] 的语义按官方注释是「各 step 的起点/终点 X/Y」= x0 y0 x1 y1（不是 w/h）。
static func _rect(a: Dictionary) -> Rect2:
	var mm: Variant = a.get("minimap", null)
	if mm == null:
		return Rect2()
	if typeof(mm) == TYPE_ARRAY:
		var v: Array = mm
		if v.size() < 4:
			return Rect2()
		return Rect2(float(v[0]), float(v[1]), float(v[2]) - float(v[0]), float(v[3]) - float(v[1]))
	if typeof(mm) == TYPE_DICTIONARY:
		var d: Dictionary = mm
		if d.has("x1"):
			return Rect2(float(d["x0"]), float(d["y0"]), float(d["x1"]) - float(d["x0"]), float(d["y1"]) - float(d["y0"]))
		return Rect2(float(d.get("x", 0)), float(d.get("y", 0)), float(d.get("w", 0)), float(d.get("h", 0)))
	return Rect2()


static func _overlap(a0: float, a1: float, b0: float, b1: float) -> bool:
	return minf(a1, b1) > maxf(a0, b0)
