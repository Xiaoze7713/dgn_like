extends SceneTree
## DDS 帧回归：PVF 里 v5 共享贴图是 DXT1/DXT5，DDS 头的 fourCC 在偏移 84，
## 读错会把整帧退化成 1×1 占位图（背景/中景整层黑掉）。这里直接读原图验证尺寸。

const NPK_DIR := "/mnt/d/dnf_latest/ImagePacks2"
var _ok := 0
var _fail := 0


func _init() -> void:
	var store := NpkStore.new(NPK_DIR)
	if not store.open_live():
		_fail += 1
		print("FAIL 打开 ImagePacks2")
		return
	_check(store, "Map/Act8/background/far.img", Vector2i(556, 489))
	_check(store, "Map/LuftHafen/middle.img", Vector2i(895, 297))
	# wahrheit 的大 DDS：以前逐像素 DXT 解码，一帧 100–560ms，主线程直接卡死。
	_check(store, "CommonMap/Town/Warheit/Effect/Cloud.img", Vector2i(1000, 477))
	_check(store, "CommonMap/Town/Warheit/Effect/Gear_Big.img", Vector2i(818, 845))
	_check(store, "CommonMap/Town/Warheit/Effect/Barrier.img", Vector2i(639, 563))
	_check(store, "CommonMap/Town/Warheit/Bottom_Close.img", Vector2i(2016, 230))
	print("== %d ok, %d fail ==" % [_ok, _fail])
	store.close()
	quit(0 if _fail == 0 else 1)


func _check(store: NpkStore, img_path: String, want: Vector2i) -> void:
	var tex := store.texture(img_path, 0)
	if tex == null:
		_fail += 1
		print("FAIL 读不到 %s" % img_path)
		return
	if tex.get_size() == Vector2(want):
		_ok += 1
		print("ok   %s %s" % [img_path, tex.get_size()])
	else:
		_fail += 1
		print("FAIL %s 尺寸 %s，期望 %s（DDS 头 fourCC 偏移错会退化成 1×1）" % [img_path, tex.get_size(), want])
