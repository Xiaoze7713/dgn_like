extends Node
## 全局日志入口（autoload：`Log`）—— 插到任意脚本里直接写 `Log.info("...")`，不用传引用。
##
## 依赖：[LogCore]（内核，class_name）、[LogTag]（子 logger）。环境常量来自 autoload `Env`（可选）。
## 失败降级：没有 Env 也能用，默认 dev 档；打不开日志文件只警告一次，不影响终端输出。
##
## 常用：
##   Log.debug("热更包大小", {"bytes": 1024})
##   Log.info("玩家登录", {"uid": 10001, "name": "鲸鲸"})
##   Log.warn("连接超时", "Net")                       # 第 2 个参数给字符串 = 当 tag
##   Log.error("存档写入失败", {"slot": 3})
##   Log.exc("读图集失败", ERR_FILE_NOT_FOUND, {"atlas": "x"})   # 附带 Error 码
##   var net := Log.tag("Net"); net.warn("断开")       # 固定 tag 的子 logger
##   Log.fatal("配置缺失")                             # 只记录，不退出；要不要 quit 由游戏决定

const Level := LogCore.Level
const Format := LogCore.Format

var _core: LogCore = null


func _ready() -> void:
	_ensure_core()
	configure_from_env()
	if _core.startup_log:
		var env_node := get_node_or_null("/root/Env")
		var snap := _core.config_snapshot()
		var file_state: String = String(snap["file_path"])
		if file_state.is_empty():
			file_state = "off"
		var fields := {
			"level": snap["level"],
			"console": snap["console_format"],
			"file": file_state,
			"godot": Engine.get_version_info().string,
		}
		if env_node != null:
			fields["env"] = env_node.env_name
			fields["app"] = env_node.app_name
			fields["ver"] = env_node.version
			fields["build"] = env_node.build
		_core.emit(LogCore.Level.INFO, "logger ready", fields, &"boot")


func _exit_tree() -> void:
	if _core != null:
		_core.shutdown()


## 内核实例（想直接改配置时用：`Log.core().setup({...})`）。一般不碰。
func core() -> LogCore:
	_ensure_core()
	return _core


func _ensure_core() -> void:
	if _core != null:
		return
	_core = LogCore.new()


## 从 autoload `Env` 拉环境相关配置（env 名/级别/文件开关/命令行覆盖）。
## Env 自己会在 _ready 里调一次；手动调也安全（幂等）。
func configure_from_env() -> void:
	_ensure_core()
	var env_node := get_node_or_null("/root/Env")
	if env_node == null or not env_node.has_method("log_config"):
		return
	_core.setup(env_node.log_config())


## 手动覆盖配置，键同 [LogCore] 的字段：
## level / format / console_format / file_format / use_color / show_source / show_stack /
## stack_min_level / capture_stack / errors_to_stderr / engine_report / json_pretty /
## file_enabled / file_path / file_max_bytes / file_max_backups / env_name / app_name / app_version
func setup(cfg: Dictionary) -> void:
	_ensure_core()
	_core.setup(cfg)


# ── 级别 ───────────────────────────────────────────────────────
func trace(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	_emit(Level.TRACE, msg, fields, tag)


func debug(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	_emit(Level.DEBUG, msg, fields, tag)


func info(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	_emit(Level.INFO, msg, fields, tag)


func warn(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	_emit(Level.WARN, msg, fields, tag)


func warning(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	_emit(Level.WARN, msg, fields, tag)


func error(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	_emit(Level.ERROR, msg, fields, tag)


func fatal(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	_emit(Level.FATAL, msg, fields, tag)


## 带 Godot Error 码的 error：会多打 `err=ERR_XXX err_id=N` 两个字段。
func exc(msg: Variant = "", err_code: int = -1, fields: Variant = null, tag: Variant = null) -> void:
	_ensure_core()
	var t := _tag_of(fields, tag)
	_core.emit(Level.ERROR, msg, _fields_of(fields, tag), t, err_code)


## 便宜的前置判断：热循环里要拼字符串前先用它挡一下。
func is_enabled(level: int) -> bool:
	_ensure_core()
	return level >= _core.min_level and level <= Level.FATAL


## 固定 tag 的子 logger，之后每条都自动带 `[tag]`。
func Tag(name: StringName) -> LogTag:
	_ensure_core()
	return LogTag.new(_core, name)


## 运行时调级别：Log.set_level("warn")
func set_level(level: Variant) -> void:
	_ensure_core()
	_core.min_level = LogCore.level_from(level, _core.min_level)


## 运行时切格式：Log.set_format("json")
func set_format(fmt: Variant) -> void:
	_ensure_core()
	var f := LogCore.format_from(fmt, _core.format)
	_core.format = f


func flush() -> void:
	if _core != null:
		_core.flush()


func shutdown() -> void:
	if _core != null:
		_core.shutdown()


# ── 内部 ───────────────────────────────────────────────────────
func _emit(level: int, msg: Variant, fields: Variant, tag: Variant) -> void:
	_ensure_core()
	_core.emit(level, msg, _fields_of(fields, tag), _tag_of(fields, tag))


## 位置参数兼容：`Log.warn("x", "Net")` 里的 "Net" 当 tag 用；`Log.warn("x", {"a":1}, "Net")` 正常。
func _tag_of(fields: Variant, tag: Variant) -> StringName:
	if tag != null:
		return StringName(tag)
	if fields is String or fields is StringName:
		return StringName(fields)
	return &""


func _fields_of(fields: Variant, tag: Variant) -> Variant:
	if tag != null:
		return fields
	if fields is String or fields is StringName:
		return null
	return fields
