extends SceneTree
## PVF 加载器自测（headless）：
##   ./tools/godot.sh --headless --script res://tests/test_pvf_loader.gd
##
## 夹具由 `tools/make_test_pvf.py` 生成（默认 /tmp/pvf_test/）：
##   mini.pvf       ~1 KB，4 条：小字符串表 + 自造文档 + 真实 move.ani + 真实 acoat_default.equ
##   expected.json  Python 侧真值
##
## 可选：设环境变量 PVF_FULL 指向真实 Script.pvf，会额外跑一次「整包解目录树」计时校验。

const FIXTURE_DIR := "/tmp/pvf_test"
const MINI_PVF := FIXTURE_DIR + "/mini.pvf"
const EXPECTED := FIXTURE_DIR + "/expected.json"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("== PVF 加载器自测 ==")
	if not FileAccess.file_exists(MINI_PVF):
		printerr("找不到夹具 %s，先跑：python3 tools/make_test_pvf.py --out %s" % [MINI_PVF, FIXTURE_DIR])
		quit(2)
		return
	var exp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
	_test_container(exp)
	_test_document(exp)
	_test_animation(exp)
	_test_full_if_requested()

	print("== 结果：%d 通过 / %d 失败 ==" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------
func _test_container(exp: Dictionary) -> void:
	var pvf := PvfLoader.new()
	_eq("open", pvf.open(MINI_PVF), OK)
	var h := pvf.archive.header
	_eq("file_version", h.file_version, int(exp["file_version"]))
	_eq("num_files", h.num_files, int(exp["num_files"]))
	_eq("entries.size", pvf.archive.entries.size(), int(exp["num_files"]))
	_eq("data_start", h.data_start, int(exp["data_start"]))
	_eq("guid", h.guid, "fa08bf71-4395-6a4b-a3e3-2617c9fee116")

	var want: Array = exp["paths"]
	for i in want.size():
		_eq("paths[%d]" % i, pvf.archive.paths[i], str(want[i]))
	for p in want:
		_true("has %s" % p, pvf.has(str(p)))

	# 条目解密：长度对、且不是全 0（说明确实解开了）
	var raw := pvf.get_bytes("stringtable.bin")
	_true("stringtable 非空", raw.size() > 8)
	var st_count := raw.decode_s32(0)
	_eq("stringtable count", st_count, int(exp["string_count"]))

	# 列目录 / 后缀过滤
	var anis := pvf.find_suffix(".ani")
	_eq("find_suffix(.ani).size", anis.size(), 1)
	var docs := pvf.list_dir("test/")
	_eq("list_dir(test/)", docs.size(), 1)


func _test_document(exp: Dictionary) -> void:
	var pvf := PvfLoader.new()
	pvf.open(MINI_PVF)
	var want: Dictionary = exp["documents"]
	for path in want.keys():
		var doc := pvf.get_document(str(path))
		_true("文档可解析 %s" % path, doc != null)
		if doc == null:
			continue
		var got := PvfDocument.to_text(doc)
		var expect_text := str(want[path]["text"])
		if _same_lines(got, expect_text):
			_pass += 1
			print("  ok   to_text(%s)" % path)
		else:
			_fail += 1
			printerr("  FAIL to_text(%s)" % path)
			printerr("  --- 期望 ---\n%s" % expect_text)
			printerr("  --- 实得 ---\n%s" % got)

	# 结构化取值的抽查：自造文档里 [name] 段有 3 个直接值
	var doc2 := pvf.get_document("test/synthetic.act")
	if doc2 != null:
		var nm := doc2.first("name")
		_true("[name] 存在", nm != null)
		if nm != null:
			_eq("[name].attrs.size", nm.attrs.size(), 4)
			_eq("[name].attrs[0]", str(nm.attrs[0]), "synthetic test doc")
			_eq("[name].attrs[1]", str(nm.attrs[1]), "hello")
			_eq("[name].attrs[2]", int(nm.attrs[2]), 42)
			_true("[name].attrs[3] 是 1.5", is_equal_approx(float(nm.attrs[3]), 1.5))
		_eq("顶层段名", _names(doc2.children), "[name, items, tail]")
		_eq("顶层段闭标签", _ends(doc2.children), "[name=true, items=true, tail=false]")
		var items := doc2.first("items")
		_true("[items] 存在", items != null)
		if items != null:
			_true("[items] 为空段", items.attrs.is_empty() and items.children.is_empty())


func _test_animation(exp: Dictionary) -> void:
	var pvf := PvfLoader.new()
	pvf.open(MINI_PVF)
	var wants: Dictionary = exp["animations"]
	for path in wants.keys():
		var w: Dictionary = wants[path]
		var ani := pvf.get_animation(str(path))
		_true("动画可解析 %s" % path, ani != null)
		if ani == null:
			continue
		_eq("frame_count", ani.frame_count, int(w["frame_count"]))
		_eq("sprites.size", ani.sprites.size(), (w["sprites"] as Array).size())
		_eq("sprites[0]", ani.sprites[0], str((w["sprites"] as Array)[0]))
		_eq("params.loop", int(ani.params.get("loop", -1)), int((w["params"] as Dictionary).get("loop", -1)))
		_true("字节精确消费", ani.is_exact())

		var wf: Array = w["frames"]
		_eq("frames.size", ani.frames.size(), wf.size())
		var bad := 0
		for i in mini(ani.frames.size(), wf.size()):
			var f: PvfTypes.AniFrame = ani.frames[i]
			var e: Dictionary = wf[i]
			if f.img_id != int(e["img_id"]) or f.img_param != int(e["img_param"]) \
					or f.x != int(e["x"]) or f.y != int(e["y"]) or f.delay != int(e["delay"]):
				bad += 1
				printerr("    帧 %d 不符：got(id=%d,param=%d,%d,%d,delay=%d) want(%s)" % [
					i, f.img_id, f.img_param, f.x, f.y, f.delay, str(e)])
		_eq("全部帧字段一致", bad, 0)

		# 判定盒
		var f0: PvfTypes.AniFrame = ani.frames[0]
		var wb: Array = wf[0]["damage_box"]
		_eq("帧0 伤害盒数量", f0.damage_boxes.size(), wb.size())
		if f0.damage_boxes.size() > 0 and wb.size() > 0:
			for k in 6:
				_eq("帧0 伤害盒[%d]" % k, int(f0.damage_boxes[0][k]), int(wb[0][k]))

		# 图集模板展开
		_eq("sheet_path(look=1)", ani.sheet_path(ani.frames[0], 1, 0),
			"character/swordman/equipment/avatar/skin/sm_body0001.img")
		_eq("fill_template 双占位", PvfTypes.AniData.fill_template("a/sm_pants%02d%02da.img", 7, 3),
			"a/sm_pants0703a.img")


func _test_full_if_requested() -> void:
	var full := OS.get_environment("PVF_FULL")
	if full.is_empty():
		print("  (跳过整包测试：未设置 PVF_FULL)")
		return
	var t0 := Time.get_ticks_msec()
	var pvf := PvfLoader.new()
	var err := pvf.open(full)
	_eq("整包 open", err, OK)
	if err != OK:
		return
	var dt := Time.get_ticks_msec() - t0
	print("  整包：%d 条，解密+建表 %d ms" % [pvf.archive.entries.size(), dt])
	_true("整包条目数 > 1000000", pvf.archive.entries.size() > 1000000)
	var ani := pvf.get_animation("character/swordman/animation/move.ani")
	if ani != null:
		_eq("整包 move.ani 帧数", ani.frame_count, 8)


# ---------------------------------------------------------------------
func _eq(label: String, got: Variant, want: Variant) -> void:
	if got == want:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL %s：got=%s want=%s" % [label, str(got), str(want)])


func _true(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  FAIL %s（条件不成立）" % label)


func mini(a: int, b: int) -> int:
	return a if a < b else b


## 非 ASCII 连续段折叠成单个 "@"（与 Python 侧 `re.sub(r"[^\x00-\x7f]+", "@", text)` 对齐）。
## GDScript 没有 big5/gb18030 解码器，中文只能比结构、不能比字形。
func _mask_non_ascii(s: String) -> String:
	var out := ""
	var in_run := false
	for i in s.length():
		if s.unicode_at(i) > 127:
			if not in_run:
				out += "@"
				in_run = true
		else:
			out += s[i]
			in_run = false
	return out


func _names(arr: Array) -> String:
	var out: PackedStringArray = []
	for c in arr:
		out.append(c.name)
	return "[" + ", ".join(out) + "]"


func _ends(arr: Array) -> String:
	var out: PackedStringArray = []
	for c in arr:
		out.append("%s=%s" % [c.name, c.has_end])
	return "[" + ", ".join(out) + "]"


## 逐行比较：**两边该行都含非 ASCII** 时视为相同。
## GDScript 没有 big5/gb18030 解码器，中文只能验证「这里有个值」，不能验证字形。
func _same_lines(a: String, b: String) -> bool:
	var la := a.split("\n")
	var lb := b.split("\n")
	if la.size() != lb.size():
		return false
	for i in la.size():
		if la[i] == lb[i]:
			continue
		if _has_non_ascii(la[i]) and _has_non_ascii(lb[i]):
			continue
		if _num_close(la[i], lb[i]):
			continue
		return false
	return true


## 数值行按 1e-6 相对误差比较：Godot 的 str(float) 与 Python 的有效位数策略不同
## （4.800000190734863 vs 4.80000019073486），逐字符比较必然假失败。
func _num_close(a: String, b: String) -> bool:
	var sa := a.strip_edges()
	var sb := b.strip_edges()
	if not (sa.is_valid_float() and sb.is_valid_float()):
		return false
	return is_equal_approx(float(sa), float(sb))


func _has_non_ascii(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) > 127:
			return true
	return false
