class_name LogUtil
## 运行时日志适配器：优先走 autoload `Log`，在无 SceneTree / 无 autoload 的
## `--script` 自测里退回引擎输出。这样低层类（PackContent、NPK、PVF）也能
## 统一走 core/log，而不会在脚本编译期解析不到 autoload 名称。

static func _sink() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root := (loop as SceneTree).root
		if root != null:
			return root.get_node_or_null("Log")
	return null

static func _fallback_text(msg: Variant, fields: Variant) -> String:
	var text := str(msg)
	if fields is Dictionary and not (fields as Dictionary).is_empty():
		text += " " + str(fields)
	return text

static func debug(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	var sink := _sink()
	if sink != null:
		sink.debug(msg, fields, tag)
	else:
		print(_fallback_text(msg, fields))

static func info(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	var sink := _sink()
	if sink != null:
		sink.info(msg, fields, tag)
	else:
		print(_fallback_text(msg, fields))

static func warn(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	var sink := _sink()
	if sink != null:
		sink.warn(msg, fields, tag)
	else:
		push_warning(_fallback_text(msg, fields))

static func error(msg: Variant = "", fields: Variant = null, tag: Variant = null) -> void:
	var sink := _sink()
	if sink != null:
		sink.error(msg, fields, tag)
	else:
		push_error(_fallback_text(msg, fields))
