extends SceneTree
## 移动/换图的手感自测：按住方向键若干帧，检查真的走了、没走出可走区、能换间房、能回城。
var _w: Node
var _f := 0
var _ok := 0
var _fail := 0
var _start := Vector2.ZERO


func _check(name: String, cond: bool, extra := "") -> void:
	if cond:
		_ok += 1
		print("  ok   ", name, " ", extra)
	else:
		_fail += 1
		print("  FAIL ", name, " ", extra)


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		_w.player._process(1.0 / 60.0)
		_w._process(1.0 / 60.0)
	Input.action_release(action)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		get_root().size = Vector2i(1152, 648)
		_w = load("res://scenes/world.tscn").instantiate()
		get_root().add_child(_w)
		return false
	if _f < 5:
		return false

	print("-- 移动 --")
	_w.enter_town("town_hendonmyre.twn", 0)
	var p0: Vector2 = _w.player.position
	_hold("move_right", 40)
	var p1: Vector2 = _w.player.position
	_check("向右能走", p1.x > p0.x + 40.0, "dx=%.1f" % (p1.x - p0.x))
	_hold("move_up", 20)
	var p2: Vector2 = _w.player.position
	_check("向上能走", p2.y < p1.y, "dy=%.1f" % (p2.y - p1.y))
	_check("仍站在可走格上", _w.grid.walkable_at(_w.player.position), "%s" % _w.player.position)

	print("-- 换图/回城 --")
	_check("城镇内换 area", _w.enter_town_area(1), "area1")
	_check("进副本", _w.enter_dungeon_by_id(101), "kohle")
	var cell_before: Vector2i = _w.cell
	_hold("move_right", 60)
	_check("副本里能走", _w.player.position.x > 8.0, "%s" % _w.player.position)
	# 走到右边缘应该换到右边的房间（greed 连通时）
	var cell_after: Vector2i = _w.cell
	_hold("move_right", 400)
	_check("走到右边能换房间", _w.cell != cell_after,
			"%s -> %s pos=%s grid=%s" % [cell_after, _w.cell, _w.player.position,
					Vector2(_w.grid.width, _w.grid.height)])
	_check("回城", _w.return_to_town(), "回城")
	_check("回到城镇", _w.mode == "town", "%s" % _w.town_key)
	_check("回城后停在原 area", _w.town_area == _w.last_town_area, "area=%d" % _w.town_area)
	print("== %d ok, %d fail ==" % [_ok, _fail])
	quit(0 if _fail == 0 else 1)
	return true
