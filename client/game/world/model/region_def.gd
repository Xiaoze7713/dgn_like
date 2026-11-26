class_name RegionDef
extends RefCounted
## 地区（`.rgn` 编译产物）：只用于城镇列表 UI 的分组，不参与房间装载。
## towns 是 PVF 的 town id；town_keys 是内容包里已经编译的城镇 key。

var path := ""
var key := ""
var name := ""
var towns: Array = []
var town_keys: Array = []
var minimap := ""


static func from_dict(d: Dictionary, p_key := "") -> RegionDef:
	var r := RegionDef.new()
	r.path = str(d.get("path", ""))
	r.key = p_key
	var names: Array = d.get("name_text", d.get("name", []))
	r.name = str(names[0]) if not names.is_empty() else ""
	r.towns = d.get("towns", [])
	r.town_keys = d.get("town_keys", [])
	var mm: Array = d.get("minimap", [])
	r.minimap = str(mm[0]) if not mm.is_empty() else ""
	return r
