extends SceneTree
## 怪物 / 被动对象解析：./tools/godot.sh --headless --script res://tests/world_entities.gd
##
## 用一张固定 map 覆盖：`[monster]` 的 token 流、`[passive object]` 的 id→.obj
## →base ani、对象字段、怪物站立动画路径。只验证解析，不改坐标/渲染。

var _ok := 0
var _fail := 0
var _ran := false


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
	var c := LivePvfContent.new()
	c.load_index()
	_check("PVF 内容就绪", c.is_ready())
	var mp := "map/astraythief/17655(2,1)normal.map"
	var room := c.map_room(mp)
	_check("map 可解析", room != null and not room.tiles.is_empty())
	_check("怪物数=13", room.monsters.size() == 13, str(room.monsters.size()))
	_check("对象数=17", room.objects.size() == 17, str(room.objects.size()))
	if not room.monsters.is_empty():
		var m: Dictionary = room.monsters[0]
		_check("怪物 id/坐标", int(m.get("id", 0)) == 1082 and int(m.get("x", -1)) == 99,
				"%d @ %d,%d" % [int(m.get("id", 0)), int(m.get("x", -1)), int(m.get("y", -1))])
		var md := c.monster(int(m.get("id", 0)))
		_check("怪物 .mob 站立动画", md != null and md.stay_ani_path != "", md.stay_ani_path if md != null else "null")
		_check("怪物中文名", md != null and md.name == "妖变的石像", md.name if md != null else "null")
	if not room.objects.is_empty():
		var o: Dictionary = room.objects[0]
		_check("对象 id/坐标", int(o.get("id", 0)) == 909 and int(o.get("x", -1)) == 17,
				"%d @ %d,%d" % [int(o.get("id", 0)), int(o.get("x", -1)), int(o.get("y", -1))])
		_check("对象 base ani", str(o.get("ani", "")).ends_with("trashbox.ani"), str(o.get("ani", "")))
		_check("对象 layer/pass", str(o.get("layer", "")) == "normal" and str(o.get("pass_type", "")) == "do not pass",
				"%s / %s" % [str(o.get("layer", "")), str(o.get("pass_type", ""))])
		var od := c.object(str(o.get("obj", "")))
		_check("对象 .obj 名字", od != null and od.name == "诺斯玛尔的垃圾桶", od.name if od != null else "null")
	var stats := c.cache_stats()
	_check("对象/怪物缓存有记录", int(stats.get("objects", 0)) > 0 and int(stats.get("monsters", 0)) > 0, str(stats))
