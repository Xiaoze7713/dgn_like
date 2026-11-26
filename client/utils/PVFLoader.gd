class_name PvfLoader
extends RefCounted
## PVF 加载器 —— 门面。对上只暴露「给我一个路径，我告诉你它是什么」。
##
## 分工：
##   [PvfArchive]   容器（头 / 目录树 / 解密 / 读条目）
##   [PvfDocument]  文档型（`.act .atk .chr .equ .mob .lst .lay .skl .map .dgn` …）→ 节点树
##   [PvfAnimation] 动画型（`.ani`）→ 帧表
##   [PvfTypes]     数据结构（Header / Entry / DocNode / AniFrame / AniData）
##
## 最小用法：
##   var pvf := PvfLoader.new()
##   if pvf.open("D:/dnf/Script.pvf") != OK:
##       push_error(pvf.last_error_message)
##   print(pvf.stats())                       # {file_version, num_files, ...}
##   var ani := pvf.get_animation("character/swordman/animation/move.ani")
##   print(ani.frame_count, " 帧；贴图模板 = ", ani.sprites)
##   var chr := pvf.get_document("character/swordman/swordman.chr")
##   print(chr.first("animation").get_str("..."))
##
## 大包注意：sf115 的 Script.pvf 目录树 141 MB，GDScript 单线程解密约 20~60 s。
## 用 `open_threaded()` + `poll_loaded()` 避免卡住主线程。

const TEXT_EXTS: Array = [".str", ".nut", ".lua", ".txt", ".xml", ".json", ".cfg", ".ini"]
const BINARY_EXTS: Array = [".bin", ".wav", ".ogg", ".png", ".img", ".bmp", ".dds"]

var archive: PvfArchive = null
var last_error: Error = OK
var last_error_message: String = ""

var _doc_cache: Dictionary = {}
var _ani_cache: Dictionary = {}
var _thread: Thread = null
var _loading: bool = false
var _load_result: Error = OK


func _init() -> void:
	archive = PvfArchive.new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _thread != null and _thread.is_started():
			_thread.wait_to_finish()
		_thread = null


# =====================================================================
# 打开
# =====================================================================
func open(path: String) -> Error:
	_doc_cache.clear()
	_ani_cache.clear()
	last_error = archive.open(path)
	last_error_message = archive.last_error_message
	return last_error


func close() -> void:
	_doc_cache.clear()
	_ani_cache.clear()
	archive.close()


func is_open() -> bool:
	return archive.is_open()


## 后台打开（目录树解密很慢，别卡主线程）。配合 `poll_loaded()` 用。
func open_threaded(path: String) -> void:
	if _loading:
		LogUtil.warn("[PvfLoader] 上一次 open_threaded 还没结束")
		return
	_loading = true
	_load_result = ERR_BUSY
	_thread = Thread.new()
	_thread.start(func() -> void: _load_result = open(path))


## -1 = 还在加载；否则是 Error 码
func poll_loaded() -> int:
	if not _loading:
		return _load_result
	if _thread != null and _thread.is_alive():
		return -1
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_loading = false
	return _load_result


func is_loading() -> bool:
	return _loading


# =====================================================================
# 取内容
# =====================================================================
func has(path: String) -> bool:
	return archive.has(path)


func get_bytes(path: String) -> PackedByteArray:
	_doc_cache.erase(path)
	return archive.read(path)


func get_text(path: String) -> String:
	return archive.decode_text(archive.read(path))


## 文档型 → 节点树（带缓存）
func get_document(path: String) -> PvfTypes.DocNode:
	if _doc_cache.has(path):
		return _doc_cache[path]
	var e := archive.get_entry(path)
	if e == null:
		last_error = ERR_FILE_NOT_FOUND
		last_error_message = "条目不存在：%s" % path
		return null
	var doc := PvfDocument.parse(archive.read(e), archive)
	_doc_cache[path] = doc
	return doc


## 动画型 → 帧表（带缓存）
func get_animation(path: String) -> PvfTypes.AniData:
	if _ani_cache.has(path):
		return _ani_cache[path]
	var e := archive.get_entry(path)
	if e == null:
		last_error = ERR_FILE_NOT_FOUND
		last_error_message = "条目不存在：%s" % path
		return null
	var ani := PvfAnimation.parse(archive.read(e))
	if ani.frame_count > 0:
		_ani_cache[path] = ani
	return ani


## 按扩展名自动分派，返回 {"kind": "ani"|"document"|"text"|"bytes", "data": Variant}
func read_auto(path: String) -> Dictionary:
	var low := path.to_lower()
	if low.ends_with(".ani"):
		return {"kind": "ani", "data": get_animation(path)}
	if TEXT_EXTS.has(_ext(low)):
		return {"kind": "text", "data": get_text(path)}
	if BINARY_EXTS.has(_ext(low)):
		return {"kind": "bytes", "data": get_bytes(path)}
	return {"kind": "document", "data": get_document(path)}


# =====================================================================
# 查询
# =====================================================================
func list_dir(prefix: String, limit: int = 0) -> PackedStringArray:
	return archive.list_dir(prefix, limit)


func find_suffix(suffix: String, prefix: String = "", limit: int = 0) -> PackedStringArray:
	return archive.find_suffix(suffix, prefix, limit)


func stats() -> Dictionary:
	var s := archive.stats()
	s["loading"] = _loading
	return s


static func _ext(low: String) -> String:
	var p := low.rfind(".")
	return low.substr(p) if p >= 0 else ""
