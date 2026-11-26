extends SceneTree
## 自测：./tools/godot.sh --headless --script res://tests/test_logger.gd
## 覆盖：级别过滤 / 两种格式 / 调用点 file:line / 栈 / 字段清洗 / tag / 错误码 / 文件轮转 / Env 常量。
## 注意：`--script` 模式编译早于 autoload 实例化，脚本里不能直接写 `Log.xxx`，所以这里用 get_node 取单例。

var _ok := 0
var _fail := 0
var _ran := false
var _log: Node
var _env: Node


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_log = get_root().get_node_or_null("Log")
	_env = get_root().get_node_or_null("Env")
	_run()
	quit(0 if _fail == 0 else 1)
	return false


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_ok += 1
		print("  ok   ", name)
	else:
		_fail += 1
		print("  FAIL ", name, "  ", detail)


func _read_lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	return FileAccess.get_file_as_string(path).split("\n", false)


func _clean(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _run() -> void:
	_check("Log autoload", _log != null)
	_check("Env autoload", _env != null)
	if _log == null or _env == null:
		print("\n==== %d ok, %d fail ====" % [_ok, _fail])
		return

	print("  env = ", _env.summary())
	_check("Env 环境名合法", _env.env_name in ["dev", "test", "staging", "prod"], _env.env_name)
	_check("Env 版本非空", not String(_env.version).is_empty())
	_check("Env 有 server_url", String(_env.cfg("server_url", "")) != "")

	var base := ProjectSettings.globalize_path("user://test_logs")
	DirAccess.make_dir_recursive_absolute(base)
	var json_path := base.path_join("run-json.log")
	var text_path := base.path_join("run-text.log")
	for p in [json_path, text_path, json_path + ".1", text_path + ".1"]:
		_clean(p)

	# ── 1. 配置：终端 TEXT / 文件 JSON
	_log.setup({
		"level": "debug", "format": "text",
		"console_format": "text", "file_format": "json",
		"file_enabled": true, "file_path": json_path,
		"use_color": false, "file_max_bytes": 0, "file_max_backups": 3,
		"env_name": "test", "app_name": "unit", "app_version": "1.2.3",
	})
	var core = _log.core()
	_check("level=debug", core.min_level == LogCore.Level.DEBUG, str(core.min_level))
	_check("console=text", core.console_fmt() == LogCore.Format.TEXT)
	_check("file=json", core.file_fmt() == LogCore.Format.JSON)

	_log.trace("trace 应被过滤")
	_log.debug("debug 可见", {"n": 1})
	_log.info("info 可见")
	_log.warn("warn 可见", {"retry": 3})
	_log.error("error 可见", {"code": "E42"})
	_log.fatal("fatal 可见")
	_log.flush()

	var lines := _read_lines(json_path)
	_check("文件 5 行", lines.size() == 5, str(lines.size()))
	var lvls := []
	for l in lines:
		var parsed = JSON.parse_string(l)
		if parsed is Dictionary:
			lvls.append(parsed.get("level"))
	_check("级别序列", lvls == ["DEBUG", "INFO", "WARN", "ERROR", "FATAL"], str(lvls))

	# ── 2. JSON 结构 / 调用点 / 栈
	var warn_rec: Dictionary = JSON.parse_string(lines[2])
	_check("msg", warn_rec.get("msg") == "warn 可见", str(warn_rec))
	_check("fields.retry=3", warn_rec.get("fields", {}).get("retry") == 3)
	_check("env=test", warn_rec.get("env") == "test")
	_check("app=unit", warn_rec.get("app") == "unit")
	_check("ver=1.2.3", warn_rec.get("ver") == "1.2.3")
	_check("file 指向本测试", String(warn_rec.get("file", "")).ends_with("tests/test_logger.gd"), str(warn_rec.get("file")))
	_check("line > 0", int(warn_rec.get("line", 0)) > 0, str(warn_rec.get("line")))
	_check("func=_run", warn_rec.get("func") == "_run", str(warn_rec.get("func")))
	_check("warn 带 stack", warn_rec.has("stack") and warn_rec["stack"].size() >= 1, str(warn_rec.get("stack")))
	if warn_rec.has("stack"):
		_check("stack[0].fn=_run", warn_rec["stack"][0].get("fn") == "_run")
	_check("无 tag 时没有 tag 键", not warn_rec.has("tag"))

	var info_rec: Dictionary = JSON.parse_string(lines[1])
	_check("info 不带 stack", not info_rec.has("stack"), str(info_rec.keys()))

	# ── 3. tag / 错误码 / 字典当 msg
	_log.tag("Net").warn("tag 子 logger", {"host": "a.b"})
	_log.exc("读文件失败", ERR_FILE_NOT_FOUND, {"path": "/nope"})
	_log.info({"uid": 7, "msg": "字典当消息"})
	_log.flush()

	lines = _read_lines(json_path)
	_check("追加到 8 行", lines.size() == 8, str(lines.size()))
	var tag_rec: Dictionary = JSON.parse_string(lines[5])
	_check("tag=Net", tag_rec.get("tag") == "Net")
	var exc_rec: Dictionary = JSON.parse_string(lines[6])
	_check("err_id=7", exc_rec.get("fields", {}).get("err_id") == 7, str(exc_rec.get("fields")))
	_check("err 文本非空", not String(exc_rec.get("fields", {}).get("err", "")).is_empty())
	var dict_rec: Dictionary = JSON.parse_string(lines[7])
	_check("字典 msg 提取", dict_rec.get("msg") == "字典当消息", str(dict_rec.get("msg")))
	_check("字典剩余进 fields", dict_rec.get("fields", {}).get("uid") == 7)

	# ── 4. 字段清洗：Vector2 / Object / 嵌套 packed / NaN
	var node := Node.new()
	_log.warn("脏字段", {
		"pos": Vector2(1, 2),
		"node": node,
		"deep": {"a": [1, {"b": PackedInt32Array([3, 4])}]},
		"nan": NAN,
	})
	node.free()
	_log.flush()
	lines = _read_lines(json_path)
	var dirty: Dictionary = JSON.parse_string(lines[-1])
	_check("Vector2 变可序列化", String(dirty.get("fields", {}).get("pos", "")) != "", str(dirty.get("fields", {})))
	_check("Object 变占位", String(dirty.get("fields", {}).get("node", "")).begins_with("<"))
	var deep: Dictionary = dirty.get("fields", {}).get("deep", {})
	var seq: Array = deep.get("a", [])
	var packed_out: Array = seq[1].get("b", []) if seq.size() == 2 else []
	_check("packed 变数组", packed_out.size() == 2 and int(packed_out[0]) == 3 and int(packed_out[1]) == 4, str(deep))

	# ── 5. 级别过滤 + 文本 sink（含栈上限）
	_log.setup({
		"level": "warn", "console_format": "text", "file_format": "text",
		"file_path": text_path, "file_enabled": true, "use_color": false,
		"show_stack": 2, "stack_min_level": "warn", "file_max_bytes": 0,
	})
	_log.debug("应过滤")
	_log.info("应过滤")
	_log.warn("文本警告", {"k": "带空格 的值"})
	_log.debug("也应过滤")
	_log.flush()

	var raw := FileAccess.get_file_as_string(text_path)
	var heads := 0
	for ln in raw.split("\n", false):
		if ln.contains("[WARN ]"):
			heads += 1
	_check("只落 1 条记录", heads == 1, str(heads))
	_check("含 [WARN ]", raw.contains("[WARN ]"), raw)
	_check("含 msg", raw.contains("文本警告"))
	_check("fields 会加引号", raw.contains("k=带空格 的值") or raw.contains("k=\"带空格 的值\""), raw)
	_check("含 src:line", raw.contains("test_logger.gd:"), raw)
	_check("含 at 栈行", raw.contains("\n    at "), raw)
	_check("栈帧限制在 2", raw.count("    at ") <= 2, str(raw.count("    at ")))

	# ── 6. 文件轮转
	var rot_path := base.path_join("rot.log")
	for p in [rot_path, rot_path + ".1", rot_path + ".2", rot_path + ".3"]:
		_clean(p)
	_log.setup({
		"level": "debug", "console_format": "json", "file_format": "json",
		"file_path": rot_path, "file_enabled": true, "file_max_bytes": 400,
		"file_max_backups": 2, "use_color": false, "show_source": false,
	})
	for i in 20:
		_log.info("rotation line %d .............................." % i)
	_log.flush()
	_check("轮转出 .1", FileAccess.file_exists(rot_path + ".1"))
	_check("最多留 2 个备份", not FileAccess.file_exists(rot_path + ".3"))

	# ── 7. 关文件 sink 不影响终端
	_log.setup({"file_enabled": false, "console_format": "json", "format": "json", "level": "info"})
	_check("file_status=off", _log.core().file_status() == "off", _log.core().file_status())
	_log.info("no file", {"a": 1})

	# ── 8. LogTag
	var t = _log.tag("Boot")
	t.debug("tag debug")
	_check("LogTag.get_tag()", t.get_tag() == &"Boot")

	print("")
	print("==== %d ok, %d fail ====" % [_ok, _fail])
	if _fail > 0:
		printerr("SOME CHECKS FAILED")
