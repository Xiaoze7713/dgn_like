extends SceneTree
## 本地调试用：把一个 .twn 及其递归引用的 .map/.til/.ani/.npc 原样 dump 成文本+二进制。
## 不做任何修复，只暴露“哪些引用找不到、哪些标签当前解析器没处理”。
## 跑法：
##   XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=$PWD/client \
##     ./tools/godot.sh --headless --script res://tests/dump_twn.gd -- \
##       --town=town/gent.twn --out=/home/sunmingze/dnf_like/data/debug/gent

var c: LivePvfContent
var outdir := ""
var refs: Array = []
var missing: Array = []
var seen_docs: Dictionary = {}
var unknown_labels: Dictionary = {}

const KNOWN_MAP := ["[player number]", "[pvp start area]", "[pvp practice start area]", "[type]", "[tile]", "[extended tile]", "[far sight scroll]", "[middle sight scroll]", "[background animation]", "[background pos]", "[town movable area]", "[town movable area name]", "[town movable area with animation]", "[virtual movable area]", "[pathgate pos]", "[way point]", "[sound]", "[animation]", "[NPC]", "[map name]", "[wide mode camera vertical correction]", "[limit map camera move]", "[greed]", "[dungeon]", "[import script]", "[teleport area option]", "[monster]", "[passive object]", "[background]"]
const KNOWN_TWN := ["[area]", "[name]", "[sub name]", "[phase]", "[permission]", "[gate]", "[normal]", "[dungeon gate]", "[open party list area]", "[extra dungeon gate]", "[minimap rect]", "[need level]", "[use private store]", "[use goguide]", "[guild gate]"]

func _init() -> void:
	var town_key := "town/gent.twn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--town="):
			town_key = a.substr(7)
		elif a.begins_with("--out="):
			outdir = a.substr(6)
	if outdir == "":
		outdir = "/home/sunmingze/dnf_like/data/debug/gent"
	DirAccess.make_dir_recursive_absolute(outdir)
	c = LivePvfContent.new()
	c.load_index()
	var t := c.town(town_key)
	if t == null:
		printerr("找不到城镇 ", town_key)
		quit(1)
		return
	_dump_doc(town_key, "town")
	refs.append({"kind": "town", "from": "(入口)", "label": "", "raw": town_key, "resolved": town_key, "exists": true})
	for area in t.areas:
		var mp := str(area.get("map", ""))
		var ok := mp != "" and c.archive.has(mp)
		refs.append({"kind": "area map", "from": town_key, "label": "[area]", "raw": mp, "resolved": mp, "exists": ok})
		if ok:
			_dump_map(mp)
		else:
			missing.append({"from": town_key, "label": "[area]", "raw": mp, "reason": "archive.has=false"})
	_write_report(t, town_key)
	print("dump -> ", outdir)
	quit()

func _dump_doc(path: String, kind: String) -> PvfNewDoc.DocNode:
	if seen_docs.has(path):
		return seen_docs[path]
	var raw := c.archive.read(path)
	if raw.is_empty():
		return null
	var node := PvfNewDoc.parse(c.archive, raw)
	seen_docs[path] = node
	var base := _safe(path)
	_write_bin(base + ".bin", raw)
	_write_text(base + ".txt", PvfNewDoc.to_text(node))
	_collect_labels(node, path)
	return node

func _dump_map(path: String) -> void:
	var node := _dump_doc(path, "map")
	if node == null:
		return
	var base_dir := path.get_base_dir() + "/"
	for lbl in ["[tile]", "[extended tile]"]:
		var n: PvfNewDoc.DocNode = node.first(lbl)
		if n == null:
			continue
		for v in n.values:
			if v is String:
				_dump_ref(base_dir, path, lbl, str(v), "tile")
		if n.children.size() > 0:
			for files in n.all("[tile files]"):
				var tv: Array = files.values
				for i in range(tv.size() - 1):
					if (tv[i] is int or tv[i] is float) and tv[i + 1] is String:
						_dump_ref(base_dir, path, lbl, str(tv[i + 1]), "tile")
	for lbl in ["[animation]", "[background animation]"]:
		var n: PvfNewDoc.DocNode = node.first(lbl)
		if n == null:
			continue
		var v: Array = n.values
		if lbl == "[animation]":
			for i in range(0, v.size() - 4, 5):
				_dump_ref(base_dir, path, lbl, str(v[i]), "ani")
		else:
			# [background animation] 的 values 是空的，实际文件在 [ani info]/[filename] 里。
			for info in n.all("[ani info]"):
				var fn: PvfNewDoc.DocNode = info.first("[filename]")
				if fn == null:
					continue
				for s in fn.strings():
					_dump_ref(base_dir, path, "[background animation]/[filename]", str(s), "ani")
			for x in v:
				if x is String:
					_dump_ref(base_dir, path, lbl, str(x), "ani")
	var imp: PvfNewDoc.DocNode = node.first("[import script]")
	if imp != null:
		for s in imp.strings():
			_dump_ref(base_dir, path, "[import script]", str(s), "map")
	var npc_n: PvfNewDoc.DocNode = node.first("[NPC]")
	if npc_n != null:
		var v: Array = npc_n.values
		for i in range(0, v.size() - 4, 5):
			var nid := str(v[i])
			var np := str(c._npc_ids.get(nid, ""))
			if np != "":
				_dump_ref("npc/", path, "[NPC]", np, "npc")
			else:
				missing.append({"from": path, "label": "[NPC]", "raw": nid, "reason": "npc.lst 无此 id"})

func _dump_ref(base_dir: String, from: String, label: String, raw: String, kind: String) -> void:
	var resolved := c._resolve_rel(base_dir, raw)
	if resolved == "":
		var tried := [base_dir + c._norm(raw), c._norm("map/" + raw), c._norm(raw)]
		missing.append({"from": from, "label": label, "raw": raw, "reason": " tried=" + str(tried)})
		refs.append({"kind": kind, "from": from, "label": label, "raw": raw, "resolved": "", "exists": false})
		return
	var ok := c.archive.has(resolved)
	refs.append({"kind": kind, "from": from, "label": label, "raw": raw, "resolved": resolved, "exists": ok})
	if not ok:
		missing.append({"from": from, "label": label, "raw": raw, "reason": "resolved 但 archive.has=false"})
		return
	if kind == "map":
		_dump_map(resolved)
	elif kind == "ani":
		var n := _dump_doc(resolved, "ani")
		if n != null:
			var ip: PvfNewDoc.DocNode = n.first("[IMAGE PATH]")
			if ip != null:
				for s in ip.strings():
					refs.append({"kind": "npk image", "from": resolved, "label": "[IMAGE PATH]", "raw": str(s), "resolved": str(s), "exists": null})
	elif kind == "npc":
		var n := _dump_doc(resolved, "npc")
		if n != null:
			var fa: PvfNewDoc.DocNode = n.first("[field animation]")
			if fa != null:
				for s in fa.strings():
					_dump_ref(resolved.get_base_dir() + "/", resolved, "[field animation]", str(s), "ani")
	elif kind == "tile":
		_dump_doc(resolved, "tile")

func _collect_labels(n: PvfNewDoc.DocNode, path: String) -> void:
	for cnode in n.children:
		if cnode.label != "{":
			var known := false
			if path.ends_with(".twn"):
				known = KNOWN_TWN.has(cnode.label)
			elif path.ends_with(".map"):
				known = KNOWN_MAP.has(cnode.label)
			if not known and not path.ends_with(".til") and not path.ends_with(".ani") and not path.ends_with(".npc"):
				var key: String = path.get_extension() + ":" + cnode.label
				unknown_labels[key] = int(unknown_labels.get(key, 0)) + 1
		_collect_labels(cnode, path)

func _write_text(name: String, text: String) -> void:
	var f := FileAccess.open(outdir.path_join(name), FileAccess.WRITE)
	if f != null:
		f.store_string(text)

func _write_bin(name: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(outdir.path_join(name), FileAccess.WRITE)
	if f != null:
		f.store_buffer(data)

func _write_report(t: TownDef, town_key: String) -> void:
	var lines: Array[String] = []
	lines.append("# dump: " + town_key)
	lines.append("")
	lines.append("- town_id=%d name=%s areas=%d" % [t.town_id, t.display_name(), t.areas.size()])
	lines.append("")
	lines.append("## areas")
	for a in t.areas:
		lines.append("- a%d type=%s map=%s args=%s minimap=%s" % [int(a.get("index", -1)), str(a.get("type", "")), str(a.get("map", "")), str(a.get("args", [])), str(a.get("minimap", null))])
	lines.append("")
	lines.append("## refs")
	for r in refs:
		lines.append("- [%s] %s <- %s %s  => %s (%s)" % [str(r["kind"]), str(r["label"]), str(r["from"]), str(r["raw"]), str(r["resolved"]), ("OK" if r["exists"] == true else ("MISSING" if r["exists"] == false else "UNCHECKED"))])
	lines.append("")
	lines.append("## missing")
	if missing.is_empty():
		lines.append("- (none)")
	for m in missing:
		lines.append("- %s %s %s | %s" % [str(m["from"]), str(m["label"]), str(m["raw"]), str(m["reason"])])
	lines.append("")
	lines.append("## labels not in known list (twn/map)")
	if unknown_labels.is_empty():
		lines.append("- (none)")
	for k in unknown_labels.keys():
		lines.append("- %s x%d" % [k, int(unknown_labels[k])])
	lines.append("")
	lines.append("## files")
	var names := seen_docs.keys()
	names.sort()
	for p in names:
		lines.append("- " + str(p))
	_write_text("report.md", "\n".join(lines) + "\n")

func _safe(path: String) -> String:
	return path.replace("/", "_").replace(":", "_").replace("\\", "_")
