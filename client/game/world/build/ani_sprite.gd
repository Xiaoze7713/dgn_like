class_name AniSprite
extends Node2D
## 把一个 AniDef 轮播出来：内部一个 Sprite2D，每帧换 texture 并按 IMAGE POS 摆位。
##
## `[IMAGE POS]` 是「相对锚点的左上角偏移」：锚点对地板系物件是脚下（世界 y 更大在上），
## 对地图装饰层是屏幕坐标原点。所以这里只做 `sprite.position = (dx, dy)`，
## 锚点本身由调用方（RoomBuilder）决定。

var def: AniDef
var store: NpkStore
var sprite: Sprite2D
var playing := true
## true = 帧里的 [IMAGE POS] 当偏移用（装饰/物件）；false = 当它不存在（背景层，
## 那些值在 PVF 里更像滚动量，照做会把背景推离画面）
var apply_frame_pos := true
## true = 把 NPK 帧自带的画布原点 (rect.position) 加进 sprite 偏移。
## 装饰层已经在 RoomBuilder 的 anchor 里加过一次，必须保持 false；NPC 没有 anchor，用 true。
var apply_canvas_offset := false

var _elapsed := 0.0
var _index := 0
var _warned := {}
var _mat_add: CanvasItemMaterial


func setup(p_def: AniDef, p_store: NpkStore, offset := Vector2.ZERO, p_apply_pos := true, p_canvas := false) -> void:
	def = p_def
	store = p_store
	apply_frame_pos = p_apply_pos
	apply_canvas_offset = p_canvas
	position = offset
	if def == null or def.is_empty():
		return
	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)
	set_process(true)
	_apply()


func _process(delta: float) -> void:
	if not playing or def == null or def.frames.size() <= 1:
		return
	_elapsed += delta * 1000.0
	var guard := 0
	while _elapsed >= float(def.at(_index).get("delay", 100)) and guard < 64:
		_elapsed -= float(def.at(_index).get("delay", 100))
		guard += 1
		if _index + 1 >= def.frames.size():
			if def.loop:
				_index = 0
			else:
				_elapsed = 0.0
				return
		else:
			_index += 1
		_apply()


func _apply() -> void:
	if sprite == null or def == null or store == null:
		return
	var f := def.at(_index)
	var img := str(f.get("img", ""))
	if img == "":
		return
	var tex := store.texture(img, int(f.get("frame", 0)))
	if tex == null:
		var key := "%s#%d" % [img, int(f.get("frame", 0))]
		if not _warned.has(key):
			_warned[key] = true
			LogUtil.warn("[AniSprite] NPK 缺图 %s" % key)
		return
	sprite.texture = tex
	var fpos := Vector2(float(f.get("dx", 0)), float(f.get("dy", 0)))
	if apply_canvas_offset:
		# NPK 帧头里的 (x,y) 是这张图在 NPC 画布里的原点；漏掉它，每个 NPC 的偏移
		# 就只剩作者写的 [IMAGE POS]，表现是有的贴底、有的整体浮空/偏左一块。
		fpos += Vector2(store.frame_rect(img, int(f.get("frame", 0))).position)
	sprite.position = fpos
	# [GRAPHIC EFFECT] LINEARDODGE = 线性加色（火光/蒸汽一类），不处理会变成一块不透明色板
	var effect := str(f.get("effect", "")).to_upper()
	if effect.contains("LINEARDODGE"):
		if _mat_add == null:
			_mat_add = CanvasItemMaterial.new()
			_mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = _mat_add
	else:
		sprite.material = null
	# [RGBA] 的第 4 位是 alpha（0..1 或 0..255 两种写法都见过）
	var rgba: Array = f.get("rgba", [])
	if rgba.size() >= 4:
		var a := float(rgba[3])
		if a > 1.0:
			a /= 255.0
		sprite.modulate = Color(1, 1, 1, clampf(a, 0.0, 1.0))
	else:
		sprite.modulate = Color.WHITE
