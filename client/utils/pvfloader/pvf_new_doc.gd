## 新版 PVF 文档解析（nkpi token 流 → 节点树）
##
## 与旧版 `PvfDocument` 不同：新版没有 2 字节头，token 是 5 字节
## （type + int32 值/字符串偏移），段落用 label + `{`/`}`，值串用 type 8。
class_name PvfNewDoc
extends RefCounted

class DocNode:
	var label := ""
	var values: Array = []
	var children: Array = []

	func first(p_label: String) -> DocNode:
		for c in children:
			if c.label == p_label:
				return c
		return null

	func all(p_label: String) -> Array:
		var out: Array = []
		for c in children:
			if c.label == p_label:
				out.append(c)
		return out

	func strings() -> Array:
		var out: Array = []
		for v in values:
			if v is String:
				out.append(v)
		return out

	func ints() -> Array:
		var out: Array = []
		for v in values:
			if v is int or v is float:
				out.append(int(v))
		return out


static func parse(archive: PvfNewArchive, data: PackedByteArray) -> DocNode:
	var root := DocNode.new()
	var tokens: Array = []
	var off := 0
	while off + 5 <= data.size():
		var t := data[off]
		var v := data.decode_s32(off + 1)
		off += 5
		match t:
			0:
				tokens.append({"k": "int", "v": v, "s": ""})
			2:
				tokens.append({"k": "float", "v": v, "s": ""})
			3, 6, 8:
				var s := archive.resolve(v)
				var k := "label" if t == 3 else ("str" if t == 6 else "val")
				tokens.append({"k": k, "v": v, "s": s})
			5:
				tokens.append({"k": "open", "v": 0, "s": "{"})
			7:
				tokens.append({"k": "close", "v": 0, "s": "}"})
			_:
				tokens.append({"k": "t%d" % t, "v": v, "s": ""})
	var block_open := _mark_blocks(tokens)
	var stack: Array = [root]
	for i in tokens.size():
		var tk: Dictionary = tokens[i]
		var k: String = tk["k"]
		if k == "label":
			var s: String = tk["s"]
			if _is_close_label(s):
				var name := _close_name(s)
				for j in range(stack.size() - 1, 0, -1):
					var n: DocNode = stack[j]
					if _strip_bracket(n.label) == name:
						stack.resize(j)
						break
				continue
			var node := DocNode.new()
			node.label = s
			var parent: DocNode = stack[-1]
			parent.children.append(node)
			if block_open.has(i):
				stack.append(node)
		elif k == "open":
			var node := DocNode.new()
			node.label = "{"
			stack[-1].children.append(node)
			stack.append(node)
		elif k == "close":
			if stack.size() > 1:
				stack.pop_back()
		else:
			var container: DocNode = stack[-1]
			var target: DocNode = container.children[-1] if container.children.size() > 0 else container
			if k == "float":
				target.values.append(float(tk["v"]))
			elif k == "int":
				target.values.append(int(tk["v"]))
			else:
				target.values.append(String(tk["s"]))
	return root


static func _mark_blocks(tokens: Array) -> Dictionary:
	var out := {}
	var opens: Array = []
	for i in tokens.size():
		var tk: Dictionary = tokens[i]
		if tk["k"] != "label":
			continue
		var name := _strip_bracket(tk["s"])
		if name.begins_with("/"):
			var target := name.substr(1)
			for j in range(opens.size() - 1, -1, -1):
				if opens[j]["name"] == target:
					out[opens[j]["i"]] = true
					opens.resize(j)
					break
		else:
			opens.append({"i": i, "name": name})
	return out


static func _strip_bracket(s: String) -> String:
	if s.length() >= 2 and s.begins_with("[") and s.ends_with("]"):
		return s.substr(1, s.length() - 2)
	return s


static func _is_close_label(s: String) -> bool:
	return s.length() >= 3 and s.begins_with("[/") and s.ends_with("]")


static func _close_name(s: String) -> String:
	return s.substr(2, s.length() - 3)


static func to_text(n: DocNode, depth := 0) -> String:
	var pad := "    ".repeat(depth)
	var out := ""
	for c in n.children:
		if c.label == "{":
			out += "%s{\n%s%s}\n" % [pad, to_text(c, depth + 1), pad]
			continue
		out += pad + c.label
		for v in c.values:
			out += " " + str(v)
		out += "\n"
		if c.children.size() > 0:
			out += to_text(c, depth + 1)
	return out
