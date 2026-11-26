extends SceneTree

var ok := 0
var fail := 0

func _check(name: String, cond: bool, extra := "") -> void:
	if cond:
		ok += 1
		print("ok   ", name)
	else:
		fail += 1
		print("FAIL ", name, "  ", extra)


func _init() -> void:
	_check("\\mnt\\d → D:", PathUtil.to_windows("/mnt/d/dnf_latest") == "D:/dnf_latest",
			PathUtil.to_windows("/mnt/d/dnf_latest"))
	_check("\\mnt\\e → E:", PathUtil.to_windows("/mnt/e/godot_proj/dnf_like") == "E:/godot_proj/dnf_like",
			PathUtil.to_windows("/mnt/e/godot_proj/dnf_like"))
	_check("D: → /mnt/d", PathUtil.to_linux("D:/dnf_latest") == "/mnt/d/dnf_latest",
			PathUtil.to_linux("D:/dnf_latest"))
	_check("res:// 不动", PathUtil.to_windows("res://a.gd") == "res://a.gd")
	var script := PathUtil.dnf_script()
	_check("dnf_root 有 Script.pvf", not script.is_empty() and FileAccess.file_exists(script), script)
	_check("ImagePacks2 目录存在", DirAccess.dir_exists_absolute(PathUtil.dnf_imagepacks()),
			PathUtil.dnf_imagepacks())
	var core := LogCore.new()
	core.emit(LogCore.Level.ERROR, "格式测试 %s / %d", [42, 7])
	core.emit(LogCore.Level.INFO, "百分比 %d%%", 50)
	core.emit(LogCore.Level.WARN, "tag 保留", "Net", &"Net")
	print("== %d ok, %d fail ==" % [ok, fail])
	quit(0 if fail == 0 else 1)
