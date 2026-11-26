class_name GreedGrid
extends RefCounted
## `[greed]` 网格：每格一个 2 字母 token，表示这间房的四个方向哪边连通。
## 官方 15 个 token（见 analysis/07-map.md §1.2）。

const RIGHT := 1
const LEFT := 2
const UP := 4
const DOWN := 8

const TOKENS := {
	"AA": 0,
	"BB": RIGHT,
	"EE": LEFT,
	"CC": UP,
	"II": DOWN,
	"DD": RIGHT | UP,
	"GG": LEFT | UP,
	"JJ": RIGHT | DOWN,
	"MM": LEFT | DOWN,
	"NN": LEFT | DOWN | RIGHT,
	"HH": LEFT | UP | RIGHT,
	"LL": UP | DOWN | RIGHT,
	"KK": UP | DOWN,
	"FF": LEFT | RIGHT,
	"PP": LEFT | RIGHT | UP | DOWN,
}

var w := 0
var h := 0
var cells: Array[String] = []   ## cells[y][x]


static func from_text(text: String) -> GreedGrid:
	var g := GreedGrid.new()
	for raw in text.split("\n", true):
		var line := raw.strip_edges().replace(" ", "")
		if line.length() < 2:
			continue
		g.cells.append(line.to_upper())
		g.w = maxi(g.w, line.length() / 2)
	g.h = g.cells.size()
	return g


func is_empty() -> bool:
	return w == 0 or h == 0


func row_width(y: int) -> int:
	return cells[y].length() / 2 if y >= 0 and y < cells.size() else 0


func has(x: int, y: int) -> bool:
	return y >= 0 and y < cells.size() and x >= 0 and x < row_width(y)


func token(x: int, y: int) -> String:
	return cells[y].substr(x * 2, 2) if has(x, y) else "AA"


func exits(x: int, y: int) -> int:
	return int(TOKENS.get(token(x, y), 0))


func neighbors(x: int, y: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var bits := exits(x, y)
	if bits & RIGHT and has(x + 1, y):
		out.append(Vector2i(x + 1, y))
	if bits & LEFT and has(x - 1, y):
		out.append(Vector2i(x - 1, y))
	if bits & UP and has(x, y - 1):
		out.append(Vector2i(x, y - 1))
	if bits & DOWN and has(x, y + 1):
		out.append(Vector2i(x, y + 1))
	return out


## 从 (x,y) 朝某方向迈一步；该方向不通返回 null
func step(x: int, y: int, dir: int) -> Variant:
	if not (exits(x, y) & dir):
		return null
	var nx := x + (1 if dir == RIGHT else (-1 if dir == LEFT else 0))
	var ny := y + (1 if dir == DOWN else (-1 if dir == UP else 0))
	if not has(nx, ny):
		return null
	return Vector2i(nx, ny)
