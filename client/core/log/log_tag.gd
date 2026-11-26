class_name LogTag
extends RefCounted
## 带固定 tag 的子 logger：`var net := Log.tag("Net")`，之后 `net.warn("超时")` 都会自动带 `[Net]`。
## 由 `Log.tag()` 创建，不直接 new。

var _core: LogCore
var _tag: StringName


func _init(core: LogCore, tag: StringName) -> void:
	_core = core
	_tag = tag


func get_tag() -> StringName:
	return _tag


func trace(msg: Variant = "", fields: Variant = null) -> void:
	_core.emit(LogCore.Level.TRACE, msg, fields, _tag)


func debug(msg: Variant = "", fields: Variant = null) -> void:
	_core.emit(LogCore.Level.DEBUG, msg, fields, _tag)


func info(msg: Variant = "", fields: Variant = null) -> void:
	_core.emit(LogCore.Level.INFO, msg, fields, _tag)


func warn(msg: Variant = "", fields: Variant = null) -> void:
	_core.emit(LogCore.Level.WARN, msg, fields, _tag)


func warning(msg: Variant = "", fields: Variant = null) -> void:
	_core.emit(LogCore.Level.WARN, msg, fields, _tag)


func error(msg: Variant = "", fields: Variant = null) -> void:
	_core.emit(LogCore.Level.ERROR, msg, fields, _tag)


func fatal(msg: Variant = "", fields: Variant = null) -> void:
	_core.emit(LogCore.Level.FATAL, msg, fields, _tag)


func exc(msg: Variant = "", err_code: int = -1, fields: Variant = null) -> void:
	_core.emit(LogCore.Level.ERROR, msg, fields, _tag, err_code)
