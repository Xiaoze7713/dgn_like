class_name TileDef
extends RefCounted
## 一块地砖（.til 编译产物）：一张 NPK 图 + 一帧 + 14×rows 通行表。
## 通行值：0 = 可走，2 = 阻挡（与 game/sf85/room.gd 的 is_walkable 一致）；
## 其余值（1/3…）按“可走”保守处理。

const COLS := 14
const CELL := 16

var path := ""
var img := ""
var frame := 0
var img_pos := 0            ## 地贴图像素相对通行网格的纵向偏移
var tile_type := ""         ## "" = 普通地砖，"extended" = 扩展（下方那一层）
var rows := 0
var pass_cells := PackedByteArray()


static func from_dict(d: Dictionary) -> TileDef:
	var t := TileDef.new()
	t.path = str(d.get("path", ""))
	t.img = str(d.get("img", ""))
	t.frame = int(d.get("frame", 0))
	t.img_pos = int(d.get("img_pos", 0))
	t.tile_type = str(d.get("tile_type", ""))
	var pass_raw: Array = d.get("pass", [])
	t.pass_cells.resize(pass_raw.size())
	for i in pass_raw.size():
		t.pass_cells[i] = int(pass_raw[i])
	t.rows = int(d.get("rows", t.pass_cells.size() / COLS))
	return t


func pass_at(col: int, row: int) -> int:
	if col < 0 or col >= COLS or row < 0 or row >= rows:
		return 0
	return pass_cells[row * COLS + col]


func logic_height() -> float:
	return float(rows * CELL)
