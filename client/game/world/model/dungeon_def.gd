class_name DungeonDef
extends RefCounted
## 一个副本（.dgn 编译产物）：maze 网格 + 每格对应的 .map。
## cells["x,y"] = {path, role, ids, kind, approx}；kind: spec=由 [map specification] 直接给出，
## dir=按「同名目录 + 坐标」兜底推导（approx=true，说明是猜的）。

var path := ""
var name_key := ""
var explain_key := ""
var cells: Dictionary = {}
var size := Vector2i.ZERO
var greed_text := ""
var greed: GreedGrid
var start_cells: Array = []
var boss_cells: Array = []
var maze_index := 0
var maze_count := 1
var min_level := 0
var basis_level := 0
var exp_point := 0.0


static func from_dict(d: Dictionary) -> DungeonDef:
	var x := DungeonDef.new()
	x.path = str(d.get("path", ""))
	x.name_key = str(d.get("name", ""))
	x.explain_key = str(d.get("explain", ""))
	# cells 在 JSON 里是数组：[{kind,x,y,ids,map,approx}, …]
	for c in d.get("cells", []):
		var cd: Dictionary = c
		x.cells[cell_key(int(cd.get("x", 0)), int(cd.get("y", 0)))] = cd
	var sz: Array = d.get("size", [])
	if sz.size() >= 2:
		x.size = Vector2i(int(sz[0]), int(sz[1]))
	x.maze_index = int(d.get("maze_index", 0))
	x.maze_count = int(d.get("maze_count", 1))
	x.greed_text = str(d.get("greed", ""))
	x.greed = GreedGrid.from_text(x.greed_text)
	x.start_cells = d.get("start", [])
	x.boss_cells = d.get("boss", [])
	x.min_level = int(d.get("min_level", 0))
	x.basis_level = int(d.get("basis_level", 0))
	x.exp_point = float(d.get("exp_point", 0.0))
	return x


static func cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func has_cell(x: int, y: int) -> bool:
	return cells.has(cell_key(x, y))


func cell(x: int, y: int) -> Dictionary:
	return cells.get(cell_key(x, y), {})


func map_path(x: int, y: int) -> String:
	var c := cell(x, y)
	return str(c.get("map", c.get("path", "")))


func start_cell() -> Vector2i:
	if not start_cells.is_empty():
		var c: Array = start_cells[0]
		if c.size() >= 2:
			return Vector2i(int(c[0]), int(c[1]))
	return Vector2i.ZERO


## 网格里真实存在格子的数量（没有 greed 也没有 size 时用 cells 自己推）
func cell_extent() -> Vector2i:
	if not greed.is_empty():
		return Vector2i(greed.w, greed.h)
	if size.x > 0 and size.y > 0:
		return size
	var mx := 0
	var my := 0
	for k in cells.keys():
		var parts := str(k).split(",")
		if parts.size() == 2:
			mx = maxi(mx, int(parts[0]))
			my = maxi(my, int(parts[1]))
	return Vector2i(mx + 1, my + 1)


func walkable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ext := cell_extent()
	for y in ext.y:
		for x in ext.x:
			if has_cell(x, y):
				out.append(Vector2i(x, y))
	return out
