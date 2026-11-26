extends SceneTree
## 冒烟：./tools/godot.sh --headless --script res://tests/world_smoke.gd
## 覆盖：内容包读取 / 每个城镇的每个 area 能装载 / 每个副本的每个格子能装载 /
##       PassGrid 有可走区域 / town_movable 与 greed 的邻接能算出来。

var _ok := 0
var _fail := 0
var _ran := false
## 这几张图原始 pass 全为 2，且不是 dummy.til；保留全阻挡（见 world_director._load_room）。
const KNOWN_BLOCKED := [
	"map/cataclysm/town/stormpass/stormpass.map",
	"map/cataclysm/town/stormpass/d_stormpass_storm.map",
	"contents/2022/stolenlandispins/map/town/stolenlandispins_1.map",
	"contents/2022/stolenlandispins/map/town/stolenlandispins_2.map",
]


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   ", name)
	else:
		_fail += 1
		print("  FAIL ", name, "  ", detail)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	print("\n== %d ok, %d fail ==" % [_ok, _fail])
	quit(0 if _fail == 0 else 1)
	return false


func _run() -> void:
	var Dir = load("res://game/world/flow/world_director.gd")
	var d = Dir.new()
	d.name = "World"
	get_root().add_child(d)

	var c: PackContent = d.content
	_check("内容包索引已读", not c.load_index().is_empty())
	_check("NPK 索引可用", d.store != null and d.store.is_ready(),
			"npk ready=%s" % str(d.store.is_ready() if d.store else false))
	_check("启动进了城镇", d.mode == "town" and d.room != null, "mode=%s" % d.mode)

	print("\n-- 城镇 --")
	for t in c.load_index().get("towns", []):
		var key := c.key_of(str(t.get("path", "")))
		var ok: bool = d.enter_town(key)
		_check("进入城镇 %s" % key, ok)
		if not ok:
			continue
		var town: TownDef = d.town
		for i in town.area_count():
			var mp := town.map_of(i)
			var a := town.area(i)
			var ok2: bool = d.enter_town_area(i)
			var tiles: int = d.room.tile_count() if d.room != null else 0
			var walk: float = d.grid.walkable_ratio() if d.grid != null else 0.0
			var walk_ok := walk > 0.0 or KNOWN_BLOCKED.has(mp)
			_check("  area %d %s tiles=%d walk=%.2f" % [i, str(a.get("type", "")), tiles, walk],
					ok2 and tiles > 0 and walk_ok, "ok=%s map=%s" % [str(ok2), mp])
			# 邻居关系（能算出来就行，不要求每个方向都有）
			var n := town.neighbor_of(i, "right")
			if n >= 0:
				_check("  area %d 右侧邻居 %d 有图" % [i, n], c.has_map(town.map_of(n)))
			var mv: int = d.room.town_movable.size() if d.room != null else 0
			var gates: Array = d.room.gates().keys() if d.room != null else []
			print("       movable_values=%d gates=%s monsters=%d" % [
					mv, str(gates), d.room.monsters.size() if d.room != null else 0])

	print("\n-- 副本 --")
	for item in c.load_index().get("dungeons", []):
		var did := int(item.get("registry_id", -1))
		var key := c.key_of(str(item.get("path", "")))
		var ok: bool = d.enter_dungeon(key)
		_check("进入副本 %s (id=%d)" % [key, did], ok)
		if not ok:
			continue
		var cells: Array = d.dungeon.walkable_cells()
		print("       cells=%d size=%s greed=%dx%d start=%s" % [cells.size(),
				str(d.dungeon.cell_extent()), d.dungeon.greed.w, d.dungeon.greed.h,
				str(d.dungeon.start_cell())])
		var loaded := 0
		for cc in cells:
			var map_path: String = d.dungeon.map_path(cc.x, cc.y)
			if map_path == "":
				continue
			var okc: bool = d._enter_cell(cc, "center")
			if not okc:
				_check("  格子 %s 装载" % str(cc), false, map_path)
				continue
			loaded += 1
			if d.room.tile_count() <= 0 or d.grid.walkable_ratio() <= 0.0:
				_check("  格子 %s 有地砖/可走" % str(cc), false, map_path)
		_check("  副本 %s 装载 %d 间房" % [key, loaded], loaded > 0)
		# greed 邻接
		var sc: Vector2i = d.dungeon.start_cell()
		var nb: Array = d.dungeon.greed.neighbors(sc.x, sc.y)
		print("      start %s 邻居 %s" % [str(sc), str(nb)])
		# 回城
		_check("  回城", d.return_to_town() and d.mode == "town")
