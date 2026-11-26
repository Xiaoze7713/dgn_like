class_name MapRoom
extends RefCounted
## 一张地图（.map 编译产物）：地砖序列 + 通道 + 怪物/NPC/物件/背景动画。
## 房间坐标：地砖从左到右平铺，每块 224 宽；高度 = 最高地砖的 rows*16。

const BLOCK_W := 224.0

var path := ""
var type := ""
var dungeon_id := 0
var name_key := ""
var greed_text := ""
var greed: GreedGrid
var tiles: Array[String] = []
var extended_tiles: Array[String] = []
var sight: Dictionary = {}          ## far/middle/near sight scroll
var background_pos := 0             ## [background pos]：只作审计数据，不参与物体/通行偏移（当前固定 120）
var extended_map: PackedInt32Array = PackedInt32Array()  ## [tile map]：每列基础地砖用第几块扩展地砖
var pathgate: PackedInt32Array = PackedInt32Array()   ## 左 右 上 下 四组 x,y
var way_point: Array = []
var town_movable: Array = []        ## 每 6 个一组：x y w h town area
var town_movable_anim: Array = []   ## [town movable area with animation]：x y w h town area + basic/open/loop/close
var town_movable_name: Array = []
var virtual_movable: Array = []     ## 每 4 个一组：x y w h
var teleport: Array = []
var monsters: Array = []
var npcs: Array = []
var objects: Array = []
var anims: Array = []
var background_anims: Array = []
var sound: Array = []


static func from_dict(d: Dictionary) -> MapRoom:
	var m := MapRoom.new()
	m.path = str(d.get("path", ""))
	m.type = str(d.get("type", ""))
	var dun: Variant = d.get("dungeon", 0)
	if typeof(dun) == TYPE_ARRAY:
		m.dungeon_id = int(dun[0]) if not dun.is_empty() else 0
	elif dun == null:
		m.dungeon_id = 0
	else:
		m.dungeon_id = int(dun)
	m.name_key = str(d.get("name", ""))
	m.greed_text = str(d.get("greed", ""))
	m.greed = GreedGrid.from_text(m.greed_text)
	m.tiles = _strings(d.get("tiles", []))
	m.extended_tiles = _strings(d.get("extended_tiles", []))
	m.extended_map = _ints(d.get("extended_map", []))
	m.sight = d.get("sight", {})
	m.background_pos = int(d.get("background_pos", 0))
	m.pathgate = _ints(d.get("pathgate", []))
	m.way_point = d.get("way_point", [])
	m.town_movable = d.get("town_movable", [])
	m.town_movable_anim = d.get("town_movable_anim", [])
	# 带动画的传送门也参与 x/y/w/h/town/area 判定；原版把两者分开写在 map 里。
	for a in m.town_movable_anim:
		var ad: Dictionary = a
		m.town_movable.append([ad.get("x", 0), ad.get("y", 0), ad.get("w", 0), ad.get("h", 0), ad.get("town", -1), ad.get("area", -1)])
	m.town_movable_name = d.get("town_movable_name", [])
	m.virtual_movable = d.get("virtual_movable", [])
	m.teleport = d.get("teleport", [])
	m.monsters = d.get("monsters", [])
	m.npcs = d.get("npcs", [])
	m.objects = d.get("objects", [])
	m.anims = d.get("anims", [])
	m.background_anims = d.get("background_anims", [])
	m.sound = d.get("sound", [])
	return m


static func _strings(v: Array) -> Array[String]:
	var out: Array[String] = []
	for x in v:
		out.append(str(x))
	return out


static func _ints(v: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for x in v:
		out.append(int(x))
	return out


func tile_count() -> int:
	return tiles.size()


func width() -> float:
	return float(tile_count()) * BLOCK_W


## 四向通道坐标；返回 {} 表示该方向没有门
func gates() -> Dictionary:
	var out := {}
	var names := ["left", "right", "up", "down"]
	for i in 4:
		if pathgate.size() >= (i + 1) * 2:
			out[names[i]] = Vector2(pathgate[i * 2], pathgate[i * 2 + 1])
	return out


func gate(dir_name: String) -> Variant:
	var g := gates()
	return g.get(dir_name, null)


func all_tile_paths() -> Array[String]:
	var out: Array[String] = []
	for p in tiles:
		out.append(p)
	for p in extended_tiles:
		out.append(p)
	return out
