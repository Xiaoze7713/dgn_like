class_name PassGrid
extends RefCounted
## 把一排地砖的通行表拼成整间房的网格，并提供「带滑动」的移动。
## 世界坐标：x 向右、y 向下；格子 16px；每块地砖宽 224（14 格）。
## 高度不同的地砖按底边对齐（房间底 = 网格底）。

const CELL := 16.0
const BLOCK_COLS := 14
const BLOCK_W := 224.0

var width := 0.0
var height := 0.0
var cols := 0
var rows := 0
var cells := PackedByteArray()
var fallback_all := false
## 每块地砖的宽度（默认 224 = 14×16）。调试 UI 可实时改，用来推测不同地图的区块宽。
var block_w := 224.0
## 水平格子宽 = block_w / 14；垂直格子固定 16。
var cell_w := 16.0
## 区域/传送框在房间里的垂直起点（固定 120）。只用于 [town movable area]、
## 传送门、副本/区域调试框，不随“移动区 Y”调试偏移变化。
var origin_y := 0.0
## 通行网格自己的垂直偏移；调试 UI 只改这个，区域框/传送门不跟。
var move_y_offset := 0.0

## [town movable area] 的 y 解释方式。DNF 地图对象的 y 有“底边为 0、向上”的约定，
## 但传送区数据可能直接是屏幕坐标；两种都保留，默认按用户反馈的 raw（顶部为 0）。
enum RectYMode { TOP, BOTTOM }
var rect_y_mode: int = RectYMode.TOP
## 额外可走矩形（世界坐标）：[town movable area] / [town_movable_anim] / [virtual movable area]。
## 只参与“能不能站/走”，不参与传送触发；触发仍只认 room.town_movable。
var walk_rects: Array[Rect2] = []
## 调试开关：只让 area/virtual 矩形决定可走，完全忽略地砖 [pass type] 0/2。
var walk_rects_only := false


## tiles: Array[String]（按房间从左到右的地砖路径）；defs: 路径 -> TileDef
func build(tiles: Array, defs: Dictionary) -> void:
	cell_w = block_w / float(BLOCK_COLS)
	cols = maxi(tiles.size() * BLOCK_COLS, 1)
	rows = 1
	for p in tiles:
		var t: TileDef = defs.get(p, null)
		if t != null:
			rows = maxi(rows, t.rows)
	width = float(cols) * cell_w
	height = float(rows) * CELL
	cells.resize(cols * rows)
	cells.fill(2)   # 缺 tile 的格子按阻挡，避免“没图的地方也能走”
	fallback_all = false
	for i in tiles.size():
		var t: TileDef = defs.get(tiles[i], null)
		if t == null:
			continue
		var y_off := rows - t.rows          # 底边对齐
		# [pass type] 行序按地砖图像自上而下；0 = 可走、2 = 阻挡。
		# 先前按「0 阻挡 / 2 可走 + 翻转行序」实现，导致地面/墙上下颠倒、出生点跑到半空。
		for r in t.rows:
			var vy := y_off + r
			for c in BLOCK_COLS:
				cells[vy * cols + i * BLOCK_COLS + c] = t.pass_at(c, r)


## 地图原始矩形 -> 世界矩形。
## TOP：raw 的 y 当作屏幕顶部为 0（直接使用）；
## BOTTOM：raw 的 y 当作房间底边为 0（翻成 Rect2 的 y 向下）。
func map_rect(raw: Rect2) -> Rect2:
	return rect_with_mode(raw, rect_y_mode)


func rect_with_mode(raw: Rect2, mode: int) -> Rect2:
	if mode == RectYMode.BOTTOM:
		return Rect2(raw.position.x, height - raw.position.y - raw.size.y + origin_y,
				raw.size.x, raw.size.y)
	return Rect2(raw.position.x, raw.position.y + origin_y, raw.size.x, raw.size.y)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < cols and y >= 0 and y < rows


func walkable(x: int, y: int) -> bool:
	if fallback_all:
		return in_bounds(x, y)
	return in_bounds(x, y) and cells[y * cols + x] == 0


func add_walk_rects(rects: Array) -> void:
	for r in rects:
		if r is Rect2 and r.size.x > 0 and r.size.y > 0:
			walk_rects.append(r)


func walkable_at(p: Vector2) -> bool:
	for r in walk_rects:
		if r.has_point(p):
			return true
	if walk_rects_only:
		return false
	return walkable(int(floor(p.x / cell_w)),
			int(floor((p.y - origin_y - move_y_offset) / CELL)))


## 轴分离 + 子步进：贴墙滑行、不会穿墙
func move(pos: Vector2, delta: Vector2) -> Vector2:
	var p := pos
	var steps := maxi(int(ceil(maxf(absf(delta.x), absf(delta.y)) / (minf(cell_w, CELL) * 0.5))), 1)
	var dx := delta.x / float(steps)
	var dy := delta.y / float(steps)
	for _i in steps:
		if dx != 0.0 and walkable_at(Vector2(p.x + dx, p.y)):
			p.x += dx
		if dy != 0.0 and walkable_at(Vector2(p.x, p.y + dy)):
			p.y += dy
	return p


## 从某侧边缘找一个可站立的点（换图出生用）
func spawn_at(edge: String) -> Vector2:
	var cx := cols / 2
	var cy := rows - 2
	match edge:
		"left":
			cx = 1
		"right":
			cx = cols - 2
		"up":
			cy = 1
		"down":
			cy = rows - 2
	return _nearest_walkable(Vector2i(cx, cy))


func _nearest_walkable(start: Vector2i) -> Vector2:
	var max_r := maxi(cols, rows)
	for r in max_r:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := start.x + dx
				var y := start.y + dy
				if walkable(x, y):
					return Vector2((float(x) + 0.5) * cell_w,
							(float(y) + 0.85) * CELL + origin_y + move_y_offset)
	# 全堵：房间中心
	return Vector2(width * 0.5, height * 0.5 + origin_y + move_y_offset)


func world_height() -> float:
	return height + origin_y + move_y_offset


## 有些过渡图（城镇门口那种）整张 dummy.til 的 pass 全是 0，引擎按 [town movable area]
## 处理，这里退化成「整间可走」，否则角色会卡死在出生点。
func make_all_walkable() -> void:
	fallback_all = true
	cells.fill(0)


func walkable_ratio() -> float:
	if cols * rows == 0:
		return 0.0
	var n := 0
	for i in cols * rows:
		if cells[i] == 0:
			n += 1
	return float(n) / float(cols * rows)
