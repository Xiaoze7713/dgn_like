extends SceneTree
## 截图：./tools/godot.sh --script res://tests/world_shot.gd -- --out=/tmp/a.png [--town=KEY] [--area=N] [--map=PATH] [--movable-y=16]
## 非 headless（WSLg）跑，第 N 帧后把主视口存成 PNG。

var _frames := 0
var _world: Node
var _out := "/tmp/world_shot.png"
var _town := ""
var _area := -1
var _dungeon := ""
var _map := ""
var _cell := Vector2i(-1, -1)
var _shot_at := 24
var _ui := false
var _debug := false
var _layer := ""
var _boxes := false
var _grid := false
var _size := Vector2i(1152, 648)
var _movable_y := 0
var _walk_area := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0].trim_prefix("--"):
			"out":
				_out = kv[1]
			"town":
				_town = kv[1]
			"area":
				_area = int(kv[1])
			"dungeon":
				_dungeon = kv[1]
			"map":
				_map = kv[1]
			"cell":
				var xy := kv[1].split(",")
				if xy.size() == 2:
					_cell = Vector2i(int(xy[0]), int(xy[1]))
			"frames":
				_shot_at = int(kv[1])
			"movable-y":
				_movable_y = int(kv[1])
			"walk":
				_walk_area = kv[1] == "area"
			"ui":
				_ui = kv[1] == "1"
			"debug":
				_debug = kv[1] == "1"
			"layer":
				_layer = kv[1]
			"boxes":
				_boxes = kv[1] == "1"
			"grid":
				_grid = kv[1] == "1"
			"size":
				var wh := kv[1].split("x")
				if wh.size() == 2:
					_size = Vector2i(int(wh[0]), int(wh[1]))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		get_root().size = _size
		_world = load("res://scenes/world.tscn").instantiate()
		get_root().add_child(_world)
	if _frames == 4 and _world != null:
		if _map != "":
			# 调试用：直接按 PVF 路径装一张 map（不经过城镇/dgn），用于看怪物/对象层。
			_world.mode = "dungeon"
			_world._load_room(_map, "center")
		if _town != "":
			_world.enter_town(_town, _area)
		if _dungeon != "":
			# 允许直接给 PVF 路径（含 /），内部换成内容包 key
			var dk: String = _dungeon
			if _dungeon.contains("/"):
				dk = _world.content.key_of(_dungeon)
			_world.enter_dungeon(dk)
			if _cell.x >= 0:
				_world._enter_cell(_cell, "center")
		if _ui:
			_world._open_town_list()
		if _movable_y != 0:
			_world.movable_y_offset = float(_movable_y)
			_world._rebuild_room()
			_world._update_hint()
		if _walk_area:
			_world.area_walk_only = true
			_world.builder.area_walk_only = true
			_world._rebuild_room()
			_world._update_hint()
		if _debug or _boxes or _grid:
			_world.builder.debug_floor = _debug
			_world.builder.debug_boxes = _boxes
			_world.builder.debug_grid = _grid
			_world._rebuild_room()
			_world.debug_ui.visible = _debug
			if _layer != "":
				_world._set_raised_layer(_layer)
			_world._sync_debug_ui()
	if _frames >= _shot_at:
		var img := get_root().get_texture().get_image()
		img.save_png(_out)
		print("[shot] ", _out, " ", img.get_width(), "x", img.get_height())
		quit(0)
		return true
	return false
