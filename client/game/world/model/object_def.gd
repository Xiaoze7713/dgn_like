class_name ObjectDef
extends RefCounted
## 被动对象（`.obj` → 可选 `.act` → base/sub `.ani`）的只读模型。
##
## 只保存渲染和调试需要的字段；不保存 PVF token。`ani_path` 是主动画，
## 找不到时为空，RoomBuilder 会退回灰色占位。

var id := 0
var path := ""
var name := ""
var width: Array = []
var layer := "normal"
var pass_type := ""
var basic_action := ""
var ani_path := ""
var sub_anis: Array = []


static func from_dict(d: Dictionary) -> ObjectDef:
	var o := ObjectDef.new()
	o.id = int(d.get("id", 0))
	o.path = str(d.get("path", ""))
	o.name = str(d.get("name", ""))
	o.width = d.get("width", [])
	o.layer = str(d.get("layer", "normal"))
	o.pass_type = str(d.get("pass_type", ""))
	o.basic_action = str(d.get("basic_action", ""))
	o.ani_path = str(d.get("ani", ""))
	o.sub_anis = d.get("sub_anis", [])
	return o
