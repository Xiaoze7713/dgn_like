## 批量语法检查：把 res://sqr_gd 下所有 .gd 都 load 一遍，统计编译失败的文件。
## 用法：godot --headless --script res://tests/check_sqr.gd
extends SceneTree

var total := 0
var failed := 0
var failed_paths: Array[String] = []


func _initialize() -> void:
	_walk("res://sqr_gd")
	print("\n=== 共 %d 个脚本，失败 %d 个 ===" % [total, failed])
	for p in failed_paths:
		print("  FAIL ", p)
	quit(1 if failed > 0 else 0)


func _walk(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		print("打不开目录: ", dir_path)
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			_walk(full)
		elif name.ends_with(".gd"):
			_check(full)
		name = d.get_next()
	d.list_dir_end()


func _check(path: String) -> void:
	total += 1
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		failed += 1
		failed_paths.append(path)
