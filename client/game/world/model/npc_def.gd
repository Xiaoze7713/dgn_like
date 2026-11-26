class_name NpcDef
extends RefCounted
## 一个城镇 NPC（`.npc` 编译产物）：名字 + 站立动画 + 脸图。
## 地图里的 [NPC] 只给 id/x/y；真正的模型按 id 从内容包 npcs/<id>.json 取。

var id := 0
var path := ""
var name := ""
var field_name := ""
var role := ""
var ani_path := ""
var ani: AniDef
var face_img := ""
var face_frame := 0


static func from_dict(d: Dictionary, p_ani: AniDef = null) -> NpcDef:
	var n := NpcDef.new()
	n.id = int(d.get("id", 0))
	n.path = str(d.get("path", ""))
	var names: Array = d.get("name", [])
	n.name = str(names[0]) if not names.is_empty() else ""
	var fields: Array = d.get("field_name", [])
	n.field_name = str(fields[0]) if not fields.is_empty() else ""
	n.role = str(d.get("role", ""))
	n.ani_path = str(d.get("ani", ""))
	n.ani = p_ani
	var face: Dictionary = d.get("face", {})
	n.face_img = str(face.get("img", ""))
	n.face_frame = int(face.get("frame", 0))
	return n


## 场景头顶显示短名；没有短名时退回全名。
## 少数 .npc（如 Storage）把 [field name] 写成了动画路径 / 角色标签，不能当名字显示。
func display_name() -> String:
	for s in [field_name, name]:
		if _readable(s):
			return s
	return ""


static func _readable(s: String) -> bool:
	if s == "":
		return false
	if s.begins_with("[") or s.contains("/") or s.to_lower().ends_with(".ani"):
		return false
	return true
