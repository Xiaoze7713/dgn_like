class_name PvfTypes
extends RefCounted
## PVF 的数据结构定义 —— 只有字段和取值帮助函数，不含任何解析/IO。
##
## 三层结构（详见 `docs/PVF-FORMAT-BYTES.md`）：
##
##   [Header] 56 字节头
##   └─ [Entry] × num_files        目录树里的一条（path + 偏移 + 长度 + 解密密钥）
##        └─ 文件体
##           ├─ [DocNode] 文档型（.act/.atk/.chr/.equ/.mob/.lst/…）
##           ├─ [AniData] 动画型（.ani）
##           └─ PackedByteArray 原样（.nut/.lua/.str/.txt/…）
##
## 字段命名与 Python 参考实现 `tools/pvf_unpack.py` 一一对应，便于对账。

## 容器头（56 = 0x38 字节，全部小端）
class Header:
	var size_guid: int = 0          ## 恒 0x24（36）
	var guid: String = ""           ## 36 字节 ASCII，各档常量相同
	var file_version: int = 0       ## 作者版号（如 53579），不是格式版本
	var dir_tree_length: int = 0    ## 目录树字节数（含 2 字节尾部对齐）
	var dir_tree_checksum: int = 0  ## CRC32，同时是目录树的解密密钥
	var num_files: int = 0          ## 条目总数
	var data_start: int = 0         ## = 56 + dir_tree_length

	func to_dict() -> Dictionary:
		return {
			"size_guid": size_guid, "guid": guid, "file_version": file_version,
			"dir_tree_length": dir_tree_length, "dir_tree_checksum": dir_tree_checksum,
			"num_files": num_files, "data_start": data_start,
		}

	func _to_string() -> String:
		return "PvfHeader(ver=%d, files=%d, dirTree=%d, dataStart=%d)" % [
			file_version, num_files, dir_tree_length, data_start]


## 目录树里的一条
class Entry:
	var number: int = 0        ## fileNumber（无全局语义，不要拿来当 id）
	var path: String = ""      ## 包内路径（小写目录、正斜杠）
	var length: int = 0        ## 明文长度
	var crc: int = 0           ## 同时是该文件体的解密密钥（**不是**校验和）
	var rel_offset: int = 0    ## 相对数据区的偏移
	var abs_offset: int = 0    ## = header.data_start + rel_offset

	## 磁盘上实际占用的字节数（4 字节对齐）
	func padded_length() -> int:
		return (length + 3) & ~3

	func _to_string() -> String:
		return "%s (%d B @%d)" % [path, length, abs_offset]


## 文档节点（PvfDocument 解析结果，一棵树）
class DocNode:
	var name: String = ""          ## 段名，不含方括号；根节点为空
	var attrs: Array = []          ## 本段直接挂的值：int / float / String，按出现顺序
	var children: Array = []       ## Array[DocNode]，保留文档真实顺序
	var has_end: bool = false      ## 原文是否有对应的 [/name]

	# ---- 取子节点 ----
	func child_nodes(child_name: String) -> Array:
		var out: Array = []
		for c in children:
			if c.name == child_name:
				out.append(c)
		return out

	func first(child_name: String) -> DocNode:
		for c in children:
			if c.name == child_name:
				return c
		return null

	func has(child_name: String) -> bool:
		return first(child_name) != null

	# ---- 取值（找不到返回 default）----
	func value_at(i: int, default: Variant = null) -> Variant:
		if i >= 0 and i < attrs.size():
			return attrs[i]
		return default

	func get_int(child_name: String, default: int = 0) -> int:
		var c := first(child_name)
		if c == null or c.attrs.is_empty():
			return default
		return int(c.attrs[0])

	func get_float(child_name: String, default: float = 0.0) -> float:
		var c := first(child_name)
		if c == null or c.attrs.is_empty():
			return default
		return float(c.attrs[0])

	func get_str(child_name: String, default: String = "") -> String:
		var c := first(child_name)
		if c == null or c.attrs.is_empty():
			return default
		return str(c.attrs[0])

	func get_int_array(child_name: String) -> Array:
		var c := first(child_name)
		if c == null:
			return []
		var out: Array = []
		for v in c.attrs:
			out.append(int(v))
		return out

	# ---- 转文本（与 Python 的 to_text 输出一致，便于对账）----
	func to_text(indent: int = 0) -> String:
		var pad := "\t".repeat(indent)
		var lines: PackedStringArray = []
		if not name.is_empty():
			lines.append("%s[%s]" % [pad, name])
		for v in attrs:
			lines.append("%s\t%s" % [pad, _fmt(v)])
		var child_indent := indent + (1 if not name.is_empty() else 0)
		for c in children:
			lines.append(c.to_text(child_indent))
		if not name.is_empty() and has_end:
			lines.append("%s[/%s]" % [pad, name])
		return "\n".join(lines)

	func to_dict() -> Dictionary:
		var d: Dictionary = {}
		if not name.is_empty():
			d["_name"] = name
		if not attrs.is_empty():
			d["_attrs"] = attrs.duplicate()
		for c in children:
			var bucket: Array = d.get(c.name, [])
			bucket.append(c.to_dict())
			d[c.name] = bucket
		return d

	static func _fmt(v: Variant) -> String:
		if typeof(v) == TYPE_FLOAT:
			var f: float = v
			if f == floor(f) and absf(f) < 1e15:
				return "%d.0" % int(f)
			return str(f)
		return str(v)


## .ani 的一帧
class AniFrame:
	var img_id: int = -1           ## 贴图模板下标（sprites 的下标），0xFFFF = 无贴图
	var img_param: int = -1        ## **图集内的帧号**（-1 = 该变体省略了这个字段）
	var sprite: String = ""        ## 展开后的图集模板（未替换 %02d/%04d）
	var x: int = 0                 ## 画布左上角（角色坐标系）
	var y: int = 0
	var delay: int = 0             ## 毫秒
	var damage_boxes: Array = []   ## Array[Array[int]]，每个 6 个数 [x,y,z,w,h,d]
	var attack_boxes: Array = []
	var props: Dictionary = {}     ## 其它帧属性原样保留（rotate / flip / sound / …）


## 一个 .ani 文件
class AniData:
	var frame_count: int = 0
	var sprites: PackedStringArray = []   ## 图集模板，如 ".../sm_body%04d.img"
	var params: Dictionary = {}           ## 全局参数（loop / shadow / …）
	var frames: Array = []                ## Array[AniFrame]
	var bytes_consumed: int = 0
	var bytes_total: int = 0
	var variant: Dictionary = {}          ## 命中的解析变体（调试用）

	func is_exact() -> bool:
		return bytes_consumed == bytes_total

	## 第 i 帧用的图集路径：把模板里的 %04d / %02d%02d 换成 (look, color)
	##   sm_body%04d.img      + look=1            -> sm_body0001.img
	##   sm_pants%02d%02da.img+ look=0, color=0   -> sm_pants0000a.img
	func sheet_path(frame: AniFrame, look: int = 0, color: int = 0) -> String:
		if frame.sprite.is_empty():
			return ""
		return AniData.fill_template(frame.sprite, look, color)

	## 模板替换：第一个 %0Nd 用 look，第二个用 color
	static func fill_template(tpl: String, look: int, color: int) -> String:
		var out := tpl
		var pos := out.find("%")
		if pos >= 0:
			var first := _take_one_placeholder(out, pos, look)
			out = first[0]
			var next_pos: int = first[1]
			pos = out.find("%", next_pos)
			if pos >= 0:
				out = _take_one_placeholder(out, pos, color)[0]
		return out

	## 把 out[pos] 处的 %0Nd 换成 value，返回 [新串, 后续搜索位置]
	static func _take_one_placeholder(s: String, pos: int, value: int) -> Array:
		var j := pos + 1
		var width := 0
		while j < s.length() and s[j] >= "0" and s[j] <= "9":
			width = width * 10 + (s.unicode_at(j) - 48)
			j += 1
		if j < s.length() and s[j] == "d":
			var num := str(value)
			if width > 0:
				while num.length() < width:
					num = "0" + num
			return [s.substr(0, pos) + num + s.substr(j + 1), pos + num.length()]
		return [s, pos + 1]
