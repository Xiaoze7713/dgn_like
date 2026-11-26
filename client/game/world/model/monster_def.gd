class_name MonsterDef
extends RefCounted
## `.mob` 的最小模型：身份 + 站立/移动动画。
##
## 战斗属性（HP/攻击/掉落）不在这里；当前只服务地图渲染和调试。

var id := 0
var path := ""
var name := ""
var width: Array = []
var stay_ani_path := ""
var move_ani_path := ""


static func from_dict(d: Dictionary) -> MonsterDef:
	var m := MonsterDef.new()
	m.id = int(d.get("id", 0))
	m.path = str(d.get("path", ""))
	m.name = str(d.get("name", ""))
	m.width = d.get("width", [])
	m.stay_ani_path = str(d.get("stay_ani", ""))
	m.move_ani_path = str(d.get("move_ani", ""))
	return m
