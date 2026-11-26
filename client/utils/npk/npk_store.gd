## NPK 资源库：按路径现场读 .npk → 解 IMG → 出 ImageTexture（带缓存）
##
## 典型用法（每帧都不想碰磁盘）：
##   var store := NpkStore.new()
##   store.open("res://assets/npk-index.bin")     # 或绝对路径
##   var tex := store.texture("character/swordman/animation/move.img", 3)
##
## 找包目录的顺序：显式传 base_dir > 环境变量 DNF_NPK_DIR > 项目设置 npk/base_dir
## > 平台默认（Windows: E:/dnf-sf/... ，Linux/WSL: /mnt/e/dnf-sf/...）。
##
## 说明：索引里的名字是**小写**、且带 `sprite/` 前缀；PVF 里的引用不带前缀也不一定小写，
## 所以查表时两条都试（`NpkIndex.find` 内部已处理前缀）。
class_name NpkStore
extends RefCounted

const DEFAULT_DIRS := [
	"/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2",
	"E:/dnf-sf/sf85/老牛DNF客户端/ImagePacks2",
]

## 同时打开的 .npk 句柄上限（4085 个包不可能全开）
const MAX_OPEN := 12
## 贴图缓存条数上限（一张 500×500 的 RGBA 约 1 MB，600 条约 600 MB 上限太高，
## 这里按「条数」管，实际单帧多在 64×106 量级）
const MAX_TEX := 800
## 贴图总字节上限（按纹理宽高×4 估算；约 64 MB）
const MAX_TEX_BYTES := 64 * 1024 * 1024
## 解析过的 Img 对象缓存（省掉重复解析帧表）
const MAX_IMG := 48

var base_dir := ""
var index: NpkIndex

var _handles := {}          # pack 名 -> FileAccess
var _handle_order: Array[String] = []
var _imgs := {}             # img 路径 -> NpkImage
var _img_order: Array[String] = []
var _tex := {}              # "路径#帧" -> ImageTexture
var _tex_order: Array[String] = []
var _tex_bytes := 0

var hits := 0
var misses := 0


func _init(dir := "") -> void:
	base_dir = PathUtil.native(dir) if dir != "" else _resolve_dir()


## 直接扫 ImagePacks2：不依赖 assets/npk-index-latest.bin
func open_live(dir_path := "") -> bool:
	if dir_path != "":
		base_dir = PathUtil.native(dir_path)
	elif base_dir == "":
		base_dir = _resolve_dir()
	index = NpkLiveIndex.new(base_dir)
	if base_dir == "":
		LogUtil.error("NPK 目录为空")
		return false
	return true


func open(index_path: String) -> bool:
	index = NpkIndex.from_file(index_path)
	if index == null or index.count <= 0:
		LogUtil.error("NPK 索引为空：%s" % index_path)
		return false
	return true


func _resolve_dir() -> String:
	var env := OS.get_environment("DNF_NPK_DIR")
	if env != "" and DirAccess.dir_exists_absolute(PathUtil.native(env)):
		return PathUtil.native(env)
	var cfg := str(ProjectSettings.get_setting("npk/base_dir", ""))
	if cfg != "" and DirAccess.dir_exists_absolute(PathUtil.native(cfg)):
		return PathUtil.native(cfg)
	# 原生 latest 客户端优先：DNF_ROOT / dnf/root / 平台默认
	var native_dir := PathUtil.dnf_imagepacks()
	if DirAccess.dir_exists_absolute(native_dir):
		return native_dir
	for d in DEFAULT_DIRS:
		var n := PathUtil.native(d)
		if DirAccess.dir_exists_absolute(n):
			return n
	return ""


func is_ready() -> bool:
	return index != null and index.count > 0 and base_dir != ""


## 一条 img 的原始字节；找不到返回空
func read_img(img_path: String) -> PackedByteArray:
	var hit := index.find(img_path)
	if hit.is_empty():
		misses += 1
		return PackedByteArray()
	var f := _handle(str(hit["pack"]))
	if f == null:
		return PackedByteArray()
	f.seek(int(hit["offset"]))
	var data := f.get_buffer(int(hit["size"]))
	hits += 1
	return data


func image(img_path: String) -> NpkImage:
	if _imgs.has(img_path):
		_img_order.erase(img_path)
		_img_order.append(img_path)
		return _imgs[img_path]
	var raw := read_img(img_path)
	if raw.is_empty():
		return null
	var im := NpkImage.decode(raw)
	_imgs[img_path] = im
	_img_order.append(img_path)
	while _img_order.size() > MAX_IMG:
		_imgs.erase(_img_order.pop_front())
	return im


func frame_count(img_path: String) -> int:
	var im := image(img_path)
	return im.frame_count if im != null else 0


func frame_rect(img_path: String, frame: int) -> Rect2i:
	var im := image(img_path)
	return im.frame_rect(frame) if im != null else Rect2i(0, 0, 1, 1)


## 最常用：拿一张贴图（同 (路径,帧) 只解码一次）
func texture(img_path: String, frame: int) -> Texture2D:
	var key := "%s#%d" % [img_path, frame]
	if _tex.has(key):
		_tex_order.erase(key)
		_tex_order.append(key)
		return _tex[key]
	var im := image(img_path)
	if im == null:
		return null
	var got := im.frame(frame)
	var tex := ImageTexture.create_from_image(got["image"])
	_tex[key] = tex
	_tex_order.append(key)
	_tex_bytes += int(tex.get_width()) * int(tex.get_height()) * 4
	_trim_tex()
	return tex


func _trim_tex() -> void:
	while _tex_order.size() > MAX_TEX or _tex_bytes > MAX_TEX_BYTES:
		if _tex_order.is_empty():
			break
		var old: String = _tex_order.pop_front()
		var t: Texture2D = _tex.get(old)
		if t != null:
			_tex_bytes -= int(t.get_width()) * int(t.get_height()) * 4
		_tex.erase(old)
	_tex_bytes = maxi(_tex_bytes, 0)


## 只要 Image（导出/对比用，不进贴图缓存）
func frame_image(img_path: String, frame: int) -> Image:
	var im := image(img_path)
	if im == null:
		return null
	return im.frame(frame)["image"]


func _handle(pack: String) -> FileAccess:
	if _handles.has(pack):
		# 提到队尾
		_handle_order.erase(pack)
		_handle_order.append(pack)
		return _handles[pack]
	if base_dir == "":
		LogUtil.error("NPK 目录未设置（DNF_NPK_DIR / npk/base_dir）")
		return null
	var path := PathUtil.native(base_dir).path_join(pack)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		LogUtil.error("打不开 NPK：%s" % path)
		return null
	_handles[pack] = f
	_handle_order.append(pack)
	while _handle_order.size() > MAX_OPEN:
		var old: String = _handle_order.pop_front()
		var h: FileAccess = _handles.get(old)
		if h != null:
			h.close()
		_handles.erase(old)
	return f


## 主动裁剪贴图/图像缓存。切图后旧房间节点已经释放，这里把缓存压回一个小水位，
## 避免玩家逛十几个城镇后 800 张贴图一直占着显存。
func trim_tex(keep := MAX_TEX) -> void:
	while _tex_order.size() > maxi(keep, 0):
		var old: String = _tex_order.pop_front()
		var t: Texture2D = _tex.get(old)
		if t != null:
			_tex_bytes -= int(t.get_width()) * int(t.get_height()) * 4
		_tex.erase(old)
	while _tex_bytes > MAX_TEX_BYTES and not _tex_order.is_empty():
		var old2: String = _tex_order.pop_front()
		var t2: Texture2D = _tex.get(old2)
		if t2 != null:
			_tex_bytes -= int(t2.get_width()) * int(t2.get_height()) * 4
		_tex.erase(old2)
	_tex_bytes = maxi(_tex_bytes, 0)


func trim_img(keep := MAX_IMG) -> void:
	while _img_order.size() > maxi(keep, 0):
		_imgs.erase(_img_order.pop_front())


func trim(keep_tex := MAX_TEX, keep_img := MAX_IMG) -> void:
	trim_tex(keep_tex)
	trim_img(keep_img)


func close() -> void:
	for k in _handles.keys():
		var f: FileAccess = _handles[k]
		if f != null:
			f.close()
	_handles.clear()
	_handle_order.clear()
	_imgs.clear()
	_img_order.clear()
	_tex.clear()
	_tex_order.clear()
	_tex_bytes = 0


func stats() -> Dictionary:
	return {
		"base_dir": base_dir,
		"index": index.stats() if index != null else {},
		"open_packs": _handles.size(),
		"cached_img": _imgs.size(),
		"cached_tex": _tex.size(),
		"tex_bytes": _tex_bytes,
		"hits": hits,
		"misses": misses,
	}
