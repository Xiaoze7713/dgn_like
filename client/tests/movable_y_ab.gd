extends SceneTree
## 传送区 y 轴 A/B：raw(top) 与 bottom-up 两套假设各跑一次。
## 用法：./tools/godot.sh --headless --script res://tests/movable_y_ab.gd

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	quit(0)
	return false

func _try_mode(d, mode: String, want_town: String) -> Dictionary:
	d.movable_y_mode = mode
	d.town_list.close()
	d._ui_open = false
	d.enter_town("town/centralpark.twn", 1)
	var flat: Array = d.room.town_movable
	var g := {}
	var i := 0
	while i + 5 < flat.size():
		if int(flat[i + 4]) == 35 and int(flat[i + 5]) == 0:
			g = {"x": float(flat[i]), "y": float(flat[i + 1]),
				"w": float(flat[i + 2]), "h": float(flat[i + 3])}
			break
		i += 6
	if g.is_empty():
		return {"error": "no movable target 35/0"}
	var raw := Rect2(g.x, g.y, g.w, g.h)
	var p_raw: Vector2 = raw.get_center()
	var p_bottom: Vector2 = d.grid.rect_with_mode(raw, PassGrid.RectYMode.BOTTOM).get_center()
	var out := {"raw": p_raw, "bottom": p_bottom, "top": d.grid.rect_with_mode(raw, PassGrid.RectYMode.TOP)}
	# raw 点
	d.player.position = p_raw
	d._switch_cooldown = 0.0
	d._check_town_movable()
	out["raw_hit"] = d.town_key != "town/centralpark.twn"
	if out["raw_hit"]:
		d.enter_town("town/centralpark.twn", 1)
	# bottom 点
	d.player.position = p_bottom
	d._switch_cooldown = 0.0
	d._check_town_movable()
	out["bottom_hit"] = d.town_key != "town/centralpark.twn"
	out["town_after"] = d.town_key
	return out

func _run() -> void:
	var d = load("res://game/world/flow/world_director.gd").new()
	d.name = "WorldAB"
	get_root().add_child(d)
	print("== movable y A/B ==")
	for mode in ["top", "bottom"]:
		var r := _try_mode(d, mode, "town/devildom_contact.twn")
		print("mode=", mode, " raw_center=", r.get("raw"), " bottom_center=", r.get("bottom"),
			" raw_hit=", r.get("raw_hit"), " bottom_hit=", r.get("bottom_hit"),
			" town_after=", r.get("town_after"), " err=", r.get("error", ""))
	print("== done ==")
