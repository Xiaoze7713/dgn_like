class_name PathUtil
extends RefCounted
## 跨平台路径：WSL 的 `/mnt/d/...` 与 Windows 的 `D:/...` 互转。
##
## 为什么需要它：工程在 WSL 里用 `~/dnf_like/client` 打开，但 Windows
## 编辑器 F5 是 Windows 进程，`/mnt/d/dnf_latest` 这种路径在 Godot 里等于不存在。
## 入口统一走这里，按当前进程返回能打开的路径。
##
## 解析顺序（dnf_root）：
##   环境变量 DNF_ROOT > 项目设置 dnf/root > 默认
##   默认：Windows `D:/dnf_latest`，Linux/WSL `/mnt/d/dnf_latest`
## 环境变量/项目设置里写哪种路径都行，会先 native() 一次。

const WSL_DEFAULT_DISTRO := "Ubuntu"


static func is_windows() -> bool:
	return OS.get_name() == "Windows" or OS.has_feature("windows")


## WSL 盘符路径 -> Windows 路径；不是 /mnt/<盘>/... 的原样返回（res://、user:// 也原样）。
static func to_windows(path: String) -> String:
	var p := path.replace("\\", "/")
	if p.is_empty() or p.begins_with("res://") or p.begins_with("user://"):
		return path
	if p == "/mnt":
		return p
	if p.begins_with("/mnt/") and p.length() >= 6:
		var drive := p.substr(5, 1)
		if drive >= "a" and drive <= "z":
			drive = drive.to_upper()
		elif drive < "A" or drive > "Z":
			return path
		var rest := p.substr(6)
		if rest.is_empty():
			rest = "/"
		if not rest.begins_with("/"):
			rest = "/" + rest
		return drive + ":" + rest
	# 其他 WSL 绝对路径（/home、/tmp）走 \\wsl.localhost\<distro>\...
	if p.begins_with("/"):
		var distro := OS.get_environment("WSL_DISTRO_NAME")
		if distro.is_empty():
			distro = WSL_DEFAULT_DISTRO
		return "//wsl.localhost/" + distro + p
	return path


## Windows 盘符路径 -> WSL 路径；已经是 WSL 路径的原样返回。
static func to_linux(path: String) -> String:
	var p := path.replace("\\", "/")
	if p.length() >= 2 and p[1] == ":" and ((p[0] >= "A" and p[0] <= "Z") or (p[0] >= "a" and p[0] <= "z")):
		return "/mnt/" + p[0].to_lower() + p.substr(2)
	return p


## 当前平台能直接交给 FileAccess/DirAccess 的路径。
static func native(path: String) -> String:
	if path.is_empty() or path.begins_with("res://") or path.begins_with("user://"):
		return path
	return to_windows(path) if is_windows() else to_linux(path)


## 原生客户端根目录（含 Script.pvf / ImagePacks2）。
static func dnf_root() -> String:
	var env := OS.get_environment("DNF_ROOT")
	if not env.is_empty():
		return native(env)
	var cfg := str(ProjectSettings.get_setting("dnf/root", ""))
	if not cfg.is_empty():
		return native(cfg)
	var defaults := [
		"D:/dnf_latest",
		"D:/WeGameApps/rail_apps/地下城与勇士：创新世纪(1)",
		"/mnt/d/dnf_latest",
		"/mnt/d/WeGameApps/rail_apps/地下城与勇士：创新世纪(1)",
	]
	for d in defaults:
		var n := native(d)
		if FileAccess.file_exists(n.path_join("Script.pvf")):
			return n
	return native(defaults[0] if is_windows() else defaults[1])


static func dnf_script() -> String:
	return dnf_root().path_join("Script.pvf")


static func dnf_imagepacks() -> String:
	return dnf_root().path_join("ImagePacks2")


static func exists_file(path: String) -> bool:
	return FileAccess.file_exists(native(path))


static func exists_dir(path: String) -> bool:
	return DirAccess.dir_exists_absolute(native(path))


## 给日志/报错用：同时给出两种写法，免得换个平台就看不懂。
static func describe(path: String) -> String:
	var n := native(path)
	if n == path:
		return path
	return "%s（当前平台：%s）" % [path, n]
