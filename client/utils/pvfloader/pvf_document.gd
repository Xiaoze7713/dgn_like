class_name PvfDocument
extends RefCounted
## PVF 文档型文件（`.act` `.atk` `.chr` `.equ` `.mob` `.lst` `.lay` `.skl` `.map` `.dgn` …）解析器。
##
## 二进制格式（小端）：
##   int16  header（跳过，恒 2 字节）
##   然后是一条条 5 字节记录： uint8 type + int32 index
##
##   type 2  Int             → 本段追加整数 index
##   type 3  IntEx           → 同上
##   type 4  Float           → index 的 32 位按 IEEE754 重解释后追加
##   type 5  Section         → index 是 stringtable 下标，得到 "[xxx]" / "[/xxx]"
##   type 6  Command         → 追加字符串 index
##   type 7  String          → 追加字符串 index
##   type 8  CommandSeparator→ 追加字符串 index
##   type 9  StringLinkIndex → 忽略（参考实现里被注释掉）
##   type 10 StringLink      → index 是**键**，查 n_string.lst 映射表得真实文本
##
## 段是否需要 `[/xxx]` 由「全文件是否出现过该闭标签」决定（两遍扫描）。
##
## 用法：
##   var doc := PvfDocument.parse(archive.read("character/swordman/swordman.chr"), archive)
##   doc.first("animation").get_str("...")

const V_INT: int = 2
const V_INT_EX: int = 3
const V_FLOAT: int = 4
const V_SECTION: int = 5
const V_COMMAND: int = 6
const V_STRING: int = 7
const V_CMD_SEP: int = 8
const V_STRLINK_IDX: int = 9
const V_STRLINK: int = 10


## 解析成节点树。`archive` 可省（省了就拿不到字符串，段名全是空串）。
static func parse(buf: PackedByteArray, archive: PvfArchive = null) -> PvfTypes.DocNode:
	var root := PvfTypes.DocNode.new()
	if buf.size() <= 7:
		return root
	var bin: PackedStringArray = archive.string_bin() if archive != null else PackedStringArray()
	var total := buf.size()

	# ---- 第 1 遍：谁有闭标签 ----
	var with_end: Dictionary = {}
	var off := 2
	while off < total - 4:
		var t := buf[off]
		off += 1
		if t >= V_INT and t <= V_STRLINK:
			if off + 4 > total:
				break
			var idx := buf.decode_s32(off)
			off += 4
			if t == V_SECTION:
				with_end[_lookup(bin, idx)] = true

	# ---- 第 2 遍：建树 ----
	var stack: Array = [root]
	var node: PvfTypes.DocNode = root
	off = 2
	while off < total:
		var t := buf[off]
		off += 1
		if t < V_INT or t > V_STRLINK:
			continue
		if off + 4 > total:
			break
		var idx := buf.decode_s32(off)
		off += 4

		match t:
			V_INT, V_INT_EX:
				node.attrs.append(idx)
			V_FLOAT:
				node.attrs.append(_as_float(idx))
			V_SECTION:
				var name := _lookup(bin, idx)
				if not name.begins_with("[/"):
					var nm := _trim_brackets(name, "[", "]")
					if node != root and not node.has_end:
						node = _pop(stack, node, nm)
					if node != null:
						var child := PvfTypes.DocNode.new()
						child.name = nm
						child.has_end = with_end.has("[/" + nm + "]")
						node.children.append(child)
						stack.append(child)
						node = child
				else:
					node = _pop(stack, node, _trim_brackets(name, "[/", "]"))
			V_STRING, V_COMMAND, V_CMD_SEP:
				node.attrs.append(_lookup(bin, idx))
			V_STRLINK:
				node.attrs.append(_string_link(archive, _lookup(bin, idx)))
	return root


## 把节点树还原成 PVF 原文风格（便于和游戏文件对账）
static func to_text(doc: PvfTypes.DocNode) -> String:
	return doc.to_text(0) if doc != null else ""


# ---------------------------------------------------------------------
static func _lookup(bin: PackedStringArray, index: int) -> String:
	if index >= 0 and index < bin.size():
		return bin[index]
	return ""


static func _string_link(archive: PvfArchive, key: String) -> String:
	if archive == null or key.is_empty():
		return ""
	return str(archive.string_map().get(key, ""))


static func _trim_brackets(s: String, open: String, close: String) -> String:
	var out := s
	if out.begins_with(open):
		out = out.substr(open.length())
	if out.ends_with(close) and not close.is_empty():
		out = out.substr(0, out.length() - close.length())
	return out.strip_edges()


static func _as_float(bits: int) -> float:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, bits & 0xFFFFFFFF)
	return b.decode_float(0)


## 闭标签回退：弹到同名父节点（同名嵌套时继续弹）
static func _pop(stack: Array, node: PvfTypes.DocNode, name: String) -> PvfTypes.DocNode:
	if node != null and node != stack[0]:
		if stack.size() > 1:
			stack.pop_back()
		node = stack[-1] if not stack.is_empty() else null
		if node != null and node != stack[0] and node.name == name:
			return _pop(stack, node, name)
	return node
