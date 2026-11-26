class_name LogCore
extends RefCounted
## 日志内核：级别过滤 → 记录组装（时间/调用点/栈/字段）→ TEXT / JSON 双格式 → 终端 + 文件双 sink。
##
## 不要直接 new 它来用；游戏里用 autoload 单例 `Log`（res://core/log/log.gd）。
## 这里保留实例形态，是为了以后能同时存在多个 logger（比如另开一个审计日志）。
##
## 设计要点（仿服务端）：
## - 每条记录带 ts / level / env / app / msg / tag / file / line / func / stack / fields
## - WARN 及以上采集并打印调用栈（可配阈值与帧数上限）
## - 终端写 stdout，ERROR/FATAL 写 stderr（可关），文件写 JSONL 便于采集
## - 文件按大小轮转，`{app}` `{env}` `{date}` 三个占位符按天/环境分文件

enum Level { TRACE, DEBUG, INFO, WARN, ERROR, FATAL, OFF }
enum Format { TEXT, JSON }

const LEVEL_NAMES := ["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "OFF"]
const LEVEL_ALIASES := {
	"trace": Level.TRACE, "verbose": Level.TRACE,
	"debug": Level.DEBUG,
	"info": Level.INFO, "information": Level.INFO, "notice": Level.INFO,
	"warn": Level.WARN, "warning": Level.WARN,
	"error": Level.ERROR, "err": Level.ERROR,
	"fatal": Level.FATAL, "critical": Level.FATAL, "panic": Level.FATAL,
	"off": Level.OFF, "none": Level.OFF, "silent": Level.OFF,
}

const ANSI_RESET := "\u001b[0m"
const ANSI_BY_LEVEL := {
	Level.TRACE: "\u001b[90m",
	Level.DEBUG: "\u001b[36m",
	Level.INFO: "\u001b[32m",
	Level.WARN: "\u001b[33m",
	Level.ERROR: "\u001b[31m",
	Level.FATAL: "\u001b[1;97;41m",
}

const MAX_FIELD_DEPTH := 6
const MAX_STACK_FRAMES := 32

# ── 可热改的配置 ───────────────────────────────────────────────
var min_level: int = Level.DEBUG
var format: int = Format.TEXT          # 默认格式（两个 sink 的兜底）
var console_format: int = -1           # -1 = 跟随 format
var file_format: int = -1              # -1 = 跟随 format
var use_color: bool = true             # 仅 TEXT 终端输出生效
var show_source: bool = true           # 每条日志尾部追加 (file:line in func)
var show_stack: int = 8                # TEXT 里最多打印几帧栈；0 = 不打
var stack_min_level: int = Level.WARN  # 从哪一级开始打栈
var capture_stack: bool = true         # 是否采集栈（JSON sink / 关掉文本栈时仍需要）
var errors_to_stderr: bool = true      # ERROR/FATAL 走 printerr
var engine_report: bool = false        # 同时 push_warning/push_error（让编辑器断点/调试器可见）
var json_pretty: bool = false          # 多行 JSON（默认严格一行一条，方便 grep/jq）
var startup_log: bool = true           # Log._ready() 打一行启动信息

var env_name: String = "dev"
var app_name: String = ""
var app_version: String = ""

var file_enabled: bool = false
var file_path: String = "user://logs/{app}-{env}-{date}.log"
var file_max_bytes: int = 8 * 1024 * 1024
var file_max_backups: int = 5
var file_flush: bool = true

# ── 内部状态 ───────────────────────────────────────────────────
var _internal_dir := "res://core/log/"
var _mutex := Mutex.new()
var _file: FileAccess = null
var _file_day := ""
var _file_current := ""
var _file_ready := false
var _open_failed := false

var _last_open_error := 0


func _init() -> void:
	var script := get_script() as Script
	if script != null and not script.resource_path.is_empty():
		_internal_dir = script.resource_path.get_base_dir() + "/"


# ── 静态工具 ───────────────────────────────────────────────────
static func level_from(value: Variant, fallback: int = -1) -> int:
	if value is int or value is float:
		var n := int(value)
		if n >= Level.TRACE and n <= Level.OFF:
			return n
		return fallback
	if value is String or value is StringName:
		var key := String(value).to_lower()
		if LEVEL_ALIASES.has(key):
			return int(LEVEL_ALIASES[key])
		# 允许 "warn,native" 之类的前缀写法
		for k in LEVEL_ALIASES:
			if key.begins_with(k):
				return int(LEVEL_ALIASES[k])
	return fallback


static func format_from(value: Variant, fallback: int = -1) -> int:
	if value is int or value is float:
		var n := int(value)
		if n == Format.TEXT or n == Format.JSON:
			return n
		return fallback
	if value is String or value is StringName:
		var key := String(value).to_lower().strip_edges()
		if key == "json" or key == "jsonl" or key == "ndjson":
			return Format.JSON
		if key == "text" or key == "plain" or key == "logfmt" or key == "console":
			return Format.TEXT
	return fallback


static func level_name(level: int) -> String:
	if level >= 0 and level < LEVEL_NAMES.size():
		return LEVEL_NAMES[level]
	return "?"


# ── 配置 ───────────────────────────────────────────────────────
## 合并一份配置（字典里没给的键保持原值），改完文件 sink 相关项会自动重开文件。
func setup(cfg: Dictionary) -> void:
	if cfg.has("level"):
		min_level = level_from(cfg["level"], min_level)
	if cfg.has("format"):
		format = format_from(cfg["format"], format)
	if cfg.has("console_format"):
		console_format = format_from(cfg["console_format"], console_format)
	if cfg.has("file_format"):
		file_format = format_from(cfg["file_format"], file_format)
	if cfg.has("use_color"):
		use_color = bool(cfg["use_color"])
	if cfg.has("show_source"):
		show_source = bool(cfg["show_source"])
	if cfg.has("show_stack"):
		show_stack = maxi(0, int(cfg["show_stack"]))
	if cfg.has("stack_min_level"):
		stack_min_level = level_from(cfg["stack_min_level"], stack_min_level)
	if cfg.has("capture_stack"):
		capture_stack = bool(cfg["capture_stack"])
	if cfg.has("errors_to_stderr"):
		errors_to_stderr = bool(cfg["errors_to_stderr"])
	if cfg.has("engine_report"):
		engine_report = bool(cfg["engine_report"])
	if cfg.has("json_pretty"):
		json_pretty = bool(cfg["json_pretty"])
	if cfg.has("startup_log"):
		startup_log = bool(cfg["startup_log"])
	if cfg.has("env_name"):
		env_name = String(cfg["env_name"])
	if cfg.has("app_name"):
		app_name = String(cfg["app_name"])
	if cfg.has("app_version"):
		app_version = String(cfg["app_version"])
	if cfg.has("file_path"):
		file_path = String(cfg["file_path"])
	if cfg.has("file_max_bytes"):
		file_max_bytes = maxi(0, int(cfg["file_max_bytes"]))
	if cfg.has("file_max_backups"):
		file_max_backups = maxi(0, int(cfg["file_max_backups"]))
	if cfg.has("file_flush"):
		file_flush = bool(cfg["file_flush"])
	if cfg.has("file_enabled"):
		file_enabled = bool(cfg["file_enabled"])

	_reopen_file()


func console_fmt() -> int:
	return console_format if console_format >= 0 else format


func file_fmt() -> int:
	return file_format if file_format >= 0 else format


## 给界面/调试面板用的一份快照。
func config_snapshot() -> Dictionary:
	return {
		"level": level_name(min_level),
		"console_format": "json" if console_fmt() == Format.JSON else "text",
		"file_format": "json" if file_fmt() == Format.JSON else "text",
		"color": use_color,
		"show_stack": show_stack,
		"stack_min_level": level_name(stack_min_level),
		"file_enabled": file_enabled and _file != null,
		"file_path": _file_current if _file != null else "",
		"env": env_name,
		"app": app_name,
		"version": app_version,
	}


func file_status() -> String:
	if not file_enabled:
		return "off"
	if _file == null:
		return "error(%d)" % _last_open_error
	return _file_current


# ── 主入口 ─────────────────────────────────────────────────────
## 真正写一条日志。msg 可以是 String / StringName / 数字 / 字典（字典会被拆成 msg + fields）。
func emit(level: int, msg: Variant = "", fields: Variant = null, tag: StringName = &"", err_code: int = -1) -> void:
	if level > Level.FATAL or level < min_level:
		return
	var rec := _build_record(level, msg, fields, tag, err_code)
	_write(rec)

	if engine_report and level >= Level.ERROR and OS.is_debug_build():
		var text := String(rec.get("msg", ""))
		if rec.has("fields") and rec["fields"] is Dictionary:
			var f: Dictionary = rec["fields"]
			if f.has("err"):
				text += " (%s)" % f["err"]
		push_error("[%s] %s" % [LEVEL_NAMES[level], text])


## 尝试把 `msg % args` 当成 printf 模板。不认识/参数数不匹配就返回 null，
## 让调用方保留原来的结构化日志语义；这里绝不抛运行时错误。
static func _printf(template: String, args: Variant) -> Variant:
	if args == null or args is Dictionary:
		return null
	var arr: Array = args if args is Array else [args]
	var slots := _printf_slots(template)
	if slots <= 0 or slots != arr.size():
		return null
	return template % arr


## 数一数模板里有几个转换符（%% 不算）。返回 -1 表示有%s之类以外的写法。
static func _printf_slots(template: String) -> int:
	var n := 0
	var i := 0
	var length := template.length()
	while i < length:
		if template[i] != "%":
			i += 1
			continue
		i += 1
		if i >= length:
			return -1
		if template[i] == "%":
			i += 1
			continue
		while i < length and template[i] in "-+ 0#":
			i += 1
		while i < length and template[i] >= "0" and template[i] <= "9":
			i += 1
		if i < length and template[i] == ".":
			i += 1
			while i < length and template[i] >= "0" and template[i] <= "9":
				i += 1
		if i < length and (template[i] == "h" or template[i] == "l" or template[i] == "L"):
			i += 1
		if i >= length or not (template[i] in "sdfxXocv"):
			return -1
		n += 1
		i += 1
	return n


func _build_record(level: int, msg: Variant, fields: Variant, tag: StringName, err_code: int) -> Dictionary:
	# printf 兼容：Log.error("打开失败: %s", path) / Log.info("%d/%d", [i, n])。
	# 只有当 msg 里确实有转换符、且参数个数匹配时才格式化；否则保留结构化 fields
	# 语义（dict 仍是字段，字符串仍是 tag，见 Log 门面的 _tag_of）。
	if msg is String and fields != null:
		var formatted: Variant = _printf(String(msg), fields)
		if formatted != null:
			msg = formatted
			fields = null
	var f: Dictionary = {}
	if fields is Dictionary:
		f = (fields as Dictionary).duplicate()
	elif fields != null:
		f = {"data": fields}

	if msg is Dictionary:
		var d: Dictionary = (msg as Dictionary).duplicate()
		msg = ""
		for key in ["msg", "message", "event"]:
			if d.has(key) and d[key] is String:
				msg = d[key]
				d.erase(key)
				break
		d.merge(f, true)
		f = d
	elif msg is StringName:
		msg = String(msg)
	elif not (msg is String):
		msg = str(msg)

	if err_code >= 0:
		f["err"] = error_string(err_code)
		f["err_id"] = err_code

	var want_stack := capture_stack and level >= stack_min_level
	var frames: Array[Dictionary] = []
	if show_source or want_stack:
		frames = _capture_frames()

	var rec := {
		"ts": _timestamp(),
		"level": LEVEL_NAMES[level],
		"level_id": level,
	}
	if not env_name.is_empty():
		rec["env"] = env_name
	if not app_name.is_empty():
		rec["app"] = app_name
	if not app_version.is_empty():
		rec["ver"] = app_version
	if tag != &"":
		rec["tag"] = String(tag)
	rec["msg"] = msg
	if not frames.is_empty():
		var caller: Dictionary = frames[0]
		rec["file"] = caller["file"]
		rec["line"] = caller["line"]
		rec["func"] = caller["fn"]
		if want_stack:
			rec["stack"] = frames
	if not f.is_empty():
		rec["fields"] = _sanitize(f)
	rec["frame"] = Engine.get_process_frames()
	return rec


func _capture_frames() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stack := get_stack()
	for entry in stack:
		var src := String(entry.get("source", ""))
		if src.is_empty() or src.begins_with(_internal_dir):
			continue
		out.append({
			"fn": String(entry.get("function", "")),
			"file": src,
			"line": int(entry.get("line", 0)),
		})
		if out.size() >= MAX_STACK_FRAMES:
			break
	return out


# ── 写 sink ────────────────────────────────────────────────────
func _write(rec: Dictionary) -> void:
	var line := format_record(rec, console_fmt(), use_color)
	if errors_to_stderr and int(rec["level_id"]) >= Level.ERROR:
		printerr(line)
	else:
		print(line)
	if file_enabled:
		_append_file(format_record(rec, file_fmt(), false))


## 把一条记录格式化成一行文本（console 的 color 与文件 sink 的格式都走这里）。
func format_record(rec: Dictionary, fmt: int, with_color: bool) -> String:
	if fmt == Format.JSON:
		return JSON.stringify(rec, "  " if json_pretty else "", false)
	return _format_text(rec, with_color)


func _format_text(rec: Dictionary, with_color: bool) -> String:
	var level := int(rec.get("level_id", Level.INFO))
	var head := String(rec.get("ts", ""))
	head += "[%s]" % String(rec.get("level", "INFO")).rpad(5)
	if rec.has("env"):
		head += "[%s]" % rec["env"]
	if rec.has("tag"):
		head += "[%s]" % rec["tag"]

	var body := String(rec.get("msg", ""))
	var fields: Dictionary = rec.get("fields", {})
	if not fields.is_empty():
		var parts := PackedStringArray()
		for key in fields:
			parts.append("%s=%s" % [key, _fmt_value(fields[key])])
		if not body.is_empty():
			body += " "
		body += " ".join(parts)

	var tail := ""
	if show_source and rec.has("file"):
		tail = "  (%s:%d" % [rec["file"], rec["line"]]
		if rec.has("func") and not String(rec["func"]).is_empty():
			tail += " in %s" % rec["func"]
		tail += ")"

	var color := ""
	var reset := ""
	if with_color and use_color:
		color = String(ANSI_BY_LEVEL.get(level, ""))
		reset = ANSI_RESET

	var lines := PackedStringArray([head + " " + color + body + reset + tail])
	if show_stack > 0 and level >= stack_min_level and rec.has("stack"):
		var stack: Array = rec["stack"]
		var n := mini(stack.size(), show_stack)
		for i in n:
			var fr: Dictionary = stack[i]
			lines.append("    at %s (%s:%d)" % [fr["fn"], fr["file"], fr["line"]])
		if stack.size() > n:
			lines.append("    ... %d more frame(s)" % (stack.size() - n))
	return "\n".join(lines)


func _fmt_value(value: Variant) -> String:
	if value is String:
		var s: String = value
		if s.is_empty() or s.contains(" ") or s.contains("=") or s.contains("\n") or s.contains("\""):
			return JSON.stringify(s, "", false)
		return s
	return JSON.stringify(value, "", false)


func _sanitize(value: Variant, depth: int = 0) -> Variant:
	var t := typeof(value)
	match t:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			var num: float = value
			if is_nan(num):
				return "NaN"
			if is_inf(num):
				return "Infinity" if num > 0.0 else "-Infinity"
			return value
		TYPE_STRING_NAME:
			return String(value)
		TYPE_DICTIONARY:
			if depth >= MAX_FIELD_DEPTH:
				return "{..}"
			var d := {}
			for key in value:
				d[str(key)] = _sanitize(value[key], depth + 1)
			return d
		TYPE_ARRAY:
			if depth >= MAX_FIELD_DEPTH:
				return "[..]"
			var a := []
			for item in value:
				a.append(_sanitize(item, depth + 1))
			return a
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var packed := []
			for item in value:
				packed.append(_sanitize(item, depth + 1))
			return packed
		TYPE_OBJECT:
			var obj := value as Object
			if obj == null:
				return "<freed object>"
			return "<%s#%d>" % [obj.get_class(), obj.get_instance_id()]
		_:
			return str(value)


# ── 时间 ───────────────────────────────────────────────────────
func _timestamp() -> String:
	var d := Time.get_datetime_dict_from_system(false)
	var ms := int(fmod(Time.get_unix_time_from_system(), 1.0) * 1000.0)
	return "%04d-%02d-%02d %02d:%02d:%02d.%03d" % [
		d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"], ms,
	]


func _today() -> String:
	return Time.get_date_string_from_system(false)


# ── 文件 sink ──────────────────────────────────────────────────
func _reopen_file() -> void:
	_close_file()
	_open_failed = false
	if file_enabled:
		_open_file()


func _resolve_path() -> String:
	var p := file_path
	var app := app_name.strip_edges()
	if app.is_empty():
		app = "game"
	p = p.replace("{app}", app.to_lower().replace(" ", "_"))
	p = p.replace("{env}", env_name if not env_name.is_empty() else "dev")
	p = p.replace("{date}", _today())
	return p


func _open_file() -> void:
	_close_file()
	var target := _resolve_path()
	var dir := target.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)

	if FileAccess.file_exists(target):
		_file = FileAccess.open(target, FileAccess.READ_WRITE)
		if _file != null:
			_file.seek_end()
	if _file == null and not FileAccess.file_exists(target):
		_file = FileAccess.open(target, FileAccess.WRITE)
	if _file == null:
		_last_open_error = FileAccess.get_open_error()
		if not _open_failed:
			_open_failed = true
			push_warning("[Log] 打不开日志文件 %s（err=%d %s），文件 sink 停用"
				% [target, _last_open_error, error_string(_last_open_error)])
		return
	_file_current = target
	_file_day = _today()
	_file_ready = true


func _close_file() -> void:
	if _file != null:
		_file.flush()
		_file.close()
	# 不把 _file 置 null 后再判空两次：直接在这里清掉
	_file = null
	_file_ready = false


func _append_file(line: String) -> void:
	_mutex.lock()
	if _file == null:
		if not file_enabled:
			_mutex.unlock()
			return
		_open_file()
	if _file != null:
		# 跨天：{date} 模板换新文件
		if _file_day != _today() and file_path.contains("{date}"):
			_open_file()
		if file_max_bytes > 0 and _file.get_length() >= file_max_bytes:
			_rotate()
		if _file != null:
			_file.store_line(line)
			if file_flush:
				_file.flush()
	_mutex.unlock()


func _rotate() -> void:
	var path := _file_current
	_close_file()
	if file_max_backups <= 0:
		# 不保留历史：直接清空
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		for i in range(file_max_backups, 0, -1):
			var dst := "%s.%d" % [path, i]
			var src := path if i == 1 else "%s.%d" % [path, i - 1]
			if FileAccess.file_exists(dst):
				DirAccess.remove_absolute(dst)
			if FileAccess.file_exists(src):
				DirAccess.rename_absolute(src, dst)
	_open_file()


## 立即把缓冲区刷到磁盘（崩溃前/退出前调用）。
func flush() -> void:
	_mutex.lock()
	if _file != null:
		_file.flush()
	_mutex.unlock()


func shutdown() -> void:
	_mutex.lock()
	_close_file()
	_mutex.unlock()
