extends Node
## 运行时常量 / 环境组件（autoload：`Env`）。
##
## 一次初始化，之后全项目只读：当前跑在 dev / test / staging / prod 哪一档、
## 版本号、构建号、平台、启动时间、日志配置，以及**你自己按环境分档的常量**（服务器地址、开关……）。
##
## 环境怎么判定（优先级从高到低）：
##   1. 命令行：`--env=test` / `--env test` / `--test` / `--staging` / `--prod`
##   2. project.godot 里 `app/env="test"`
##   3. 导出的自定义 feature tag：`test` / `staging` / `prod`
##   4. 自动：编辑器里跑 → dev；debug 导出 → test；release 导出 → prod
##
## 你在下面 PROFILES 里加自己的常量，用 `Env.cfg("server_url")` 取；
## 同名 ProjectSettings（`app/server_url`）会盖掉 PROFILES 的值，方便打包时覆盖。

enum Mode { DEV, TEST, STAGING, PROD }

const MODE_NAMES := {
	Mode.DEV: "dev",
	Mode.TEST: "test",
	Mode.STAGING: "staging",
	Mode.PROD: "prod",
}

const NAME_TO_MODE := {
	"dev": Mode.DEV, "development": Mode.DEV, "local": Mode.DEV,
	"test": Mode.TEST, "testing": Mode.TEST, "qa": Mode.TEST,
	"staging": Mode.STAGING, "stage": Mode.STAGING,
	"prod": Mode.PROD, "production": Mode.PROD, "release": Mode.PROD, "live": Mode.PROD,
}

const LOG_FILE_DEFAULT := "user://logs/{app}-{env}-{date}.log"

## 每个环境的常量表。日志项以 `log/` 开头，其余是你自己的业务常量。
## 常用日志键：
##   log/level            过滤级别 trace/debug/info/warn/error/fatal/off
##   log/console_format   text / json
##   log/file_format      text / json
##   log/file_enabled     是否写文件
##   log/file_path        路径模板，支持 {app} {env} {date}
##   log/color            终端是否上色（headless 自动关）
##   log/stack            文本日志里最多打几帧栈
##   log/stack_min_level  从哪级开始打栈
##   log/engine_report    是否同时 push_error（编辑器调试器可见）
const PROFILES: Dictionary = {
	"dev": {
		"log/level": "debug",
		"log/console_format": "text",
		"log/file_format": "json",
		"log/file_enabled": false,
		"log/color": true,
		"log/stack": 8,
		"log/stack_min_level": "warn",
		"log/engine_report": false,
		# ↓ 业务常量示例，按需改
		"server_url": "http://127.0.0.1:9000",
		"allow_cheat": true,
		"submit_analytics": false,
	},
	"test": {
		"log/level": "debug",
		"log/console_format": "text",
		"log/file_format": "json",
		"log/file_enabled": true,
		"log/color": true,
		"log/stack": 16,
		"log/stack_min_level": "warn",
		"log/engine_report": false,
		"server_url": "http://10.0.0.21:9000",
		"allow_cheat": true,
		"submit_analytics": true,
	},
	"staging": {
		"log/level": "info",
		"log/console_format": "text",
		"log/file_format": "json",
		"log/file_enabled": true,
		"log/color": true,
		"log/stack": 16,
		"log/stack_min_level": "error",
		"log/engine_report": false,
		"server_url": "https://staging.example.com",
		"allow_cheat": false,
		"submit_analytics": true,
	},
	"prod": {
		"log/level": "info",
		"log/console_format": "text",
		"log/file_format": "json",
		"log/file_enabled": true,
		"log/color": false,
		"log/stack": 16,
		"log/stack_min_level": "error",
		"log/engine_report": false,
		"server_url": "https://game.example.com",
		"allow_cheat": false,
		"submit_analytics": true,
	},
}

# ── 初始化后的常量（只读约定） ─────────────────────────────────
var initialized := false
var mode: int = Mode.DEV
var env_name: String = "dev"
var app_name: String = ""
var version: String = "0.0.0"
var build: String = "local"
var engine_version: String = ""
var platform: String = ""
var arch: String = ""
var is_editor := false
var is_debug := false
var data_dir: String = ""
var log_dir: String = "user://logs"
var started_at: String = ""
var pid: int = 0
var cmdline := PackedStringArray()


func _init() -> void:
	# 放在 _init 而不是 _ready：别的 autoload 在自己的 _init 里就可能用到 Env。
	ensure()


func _ready() -> void:
	ensure()
	var log_node := get_node_or_null("/root/Log")
	if log_node != null and log_node.has_method("configure_from_env"):
		log_node.configure_from_env()


## 幂等初始化；所有取值方法都会先调它，所以不用关心调用顺序。
func ensure() -> void:
	if initialized:
		return
	initialized = true

	cmdline = OS.get_cmdline_args()
	for a in OS.get_cmdline_user_args():
		if not cmdline.has(a):
			cmdline.append(a)

	is_editor = OS.has_feature("editor")
	is_debug = OS.is_debug_build()
	platform = OS.get_name()
	arch = Engine.get_architecture_name()
	engine_version = Engine.get_version_info().string
	pid = OS.get_process_id()
	started_at = Time.get_datetime_string_from_system(false, true)
	data_dir = ProjectSettings.globalize_path("user://")

	app_name = String(ProjectSettings.get_setting("application/config/name", "godot_game"))
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	version = v if not v.is_empty() else "0.0.0"
	var b := String(ProjectSettings.get_setting("app/build", ""))
	if b.is_empty():
		b = OS.get_environment("BUILD_NUMBER")
	build = b if not b.is_empty() else "local"

	env_name = _detect_env()
	mode = int(NAME_TO_MODE.get(env_name, Mode.DEV))


# ── 环境判断 ───────────────────────────────────────────────────
func _detect_env() -> String:
	for i in cmdline.size():
		var a := cmdline[i]
		if a.begins_with("--env="):
			return _normalize_env(a.substr("--env=".length()))
		if a == "--env" and i + 1 < cmdline.size():
			return _normalize_env(cmdline[i + 1])
		if a == "--dev" or a == "--test" or a == "--staging" or a == "--prod" or a == "--production":
			return _normalize_env(a.substr(2))

	var from_settings := String(ProjectSettings.get_setting("app/env", "")).strip_edges()
	if not from_settings.is_empty():
		return _normalize_env(from_settings)

	for name in ["test", "staging", "prod"]:
		if OS.has_feature(name):
			return name

	if OS.has_feature("editor"):
		return "dev"
	if OS.is_debug_build():
		return "test"
	return "prod"


func _normalize_env(raw: String) -> String:
	var key := raw.strip_edges().to_lower()
	if NAME_TO_MODE.has(key):
		return MODE_NAMES[int(NAME_TO_MODE[key])]
	LogUtil.warn("[Env] 未知环境名 '%s'，按 dev 处理" % raw)
	return "dev"


func is_dev() -> bool:
	ensure()
	return mode == Mode.DEV


func is_test() -> bool:
	ensure()
	return mode == Mode.TEST


func is_staging() -> bool:
	ensure()
	return mode == Mode.STAGING


func is_prod() -> bool:
	ensure()
	return mode == Mode.PROD


## 非本地：test / staging / prod 都算，适合挂“别在本地跑的东西”。
func is_remote() -> bool:
	ensure()
	return mode != Mode.DEV


# ── 常量读取 ───────────────────────────────────────────────────
## 取当前环境的常量：PROFILES[env] → ProjectSettings["app/<key>"] → default。
func cfg(key: String, default: Variant = null) -> Variant:
	ensure()
	var profile: Dictionary = PROFILES.get(env_name, {})
	var value: Variant = profile.get(key, default)
	var setting := "app/" + key
	if ProjectSettings.has_setting(setting):
		value = ProjectSettings.get_setting(setting)
	return value


## 只读当前环境的日志配置，交给 LogCore.setup() 用。
func log_config() -> Dictionary:
	ensure()
	var cfg_dict := {
		"env_name": env_name,
		"app_name": app_name,
		"app_version": version,
		"level": cfg("log/level", "debug"),
		"console_format": cfg("log/console_format", "text"),
		"file_format": cfg("log/file_format", "json"),
		"file_enabled": bool(cfg("log/file_enabled", false)),
		"file_path": String(cfg("log/file_path", LOG_FILE_DEFAULT)),
		"use_color": bool(cfg("log/color", true)),
		"show_stack": int(cfg("log/stack", 8)),
		"stack_min_level": cfg("log/stack_min_level", "warn"),
		"engine_report": bool(cfg("log/engine_report", false)),
		"capture_stack": bool(cfg("log/capture_stack", true)),
	}

	# 命令行覆盖（给 CI / 现场排查用，不改代码）
	for a in cmdline:
		if a.begins_with("--log-level="):
			cfg_dict["level"] = a.substr("--log-level=".length())
		elif a.begins_with("--log-file="):
			cfg_dict["file_path"] = a.substr("--log-file=".length())
			cfg_dict["file_enabled"] = true
		elif a.begins_with("--log-stack="):
			cfg_dict["show_stack"] = int(a.substr("--log-stack=".length()))
		elif a == "--log-json":
			cfg_dict["console_format"] = "json"
		elif a == "--log-text":
			cfg_dict["console_format"] = "text"
		elif a == "--log-no-color":
			cfg_dict["use_color"] = false
		elif a == "--log-color":
			cfg_dict["use_color"] = true
		elif a == "--log-file-off":
			cfg_dict["file_enabled"] = false

	# headless（CI、专用服务器、--script 测试）默认不上色，避免管道里一堆转义码
	if DisplayServer.get_name() == "headless" and not _has_arg("--log-color"):
		cfg_dict["use_color"] = false

	return cfg_dict


func _has_arg(needle: String) -> bool:
	for a in cmdline:
		if a == needle:
			return true
	return false


# ── 展示 ───────────────────────────────────────────────────────
func summary() -> String:
	ensure()
	return "%s %s (build=%s) | env=%s | debug=%s | editor=%s | godot %s | %s.%s | pid=%d | %s" % [
		app_name, version, build, env_name, is_debug, is_editor,
		engine_version, platform, arch, pid, started_at,
	]


func _to_string() -> String:
	return "Env(%s)" % env_name
