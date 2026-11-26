extends Node2D
## [town movable area with animation] 的可视门：
## basic 常驻，玩家进入 area 后播放 open → loop，离开后 close → basic。
## area 的 x/y/w/h 与原版 [town movable area] 同一套原始坐标；
## 当前先按“左上角 + 屏幕坐标”放置，位置是否要翻 y 等留给统一步骤验证。

var store: NpkStore
var content: PackContent
var rect := Rect2()
var target_town := -1
var target_area := -1
var defs: Dictionary = {}

var _sprite: AniSprite
var _state := "basic"
var _timer := 0.0
var _inside := false
var _player: Node2D


func setup(p_area: Dictionary, p_store: NpkStore, p_content: PackContent,
		p_world_pos: Vector2 = Vector2.INF) -> void:
	store = p_store
	content = p_content
	rect = Rect2(float(p_area.get("x", 0)), float(p_area.get("y", 0)),
			float(p_area.get("w", 0)), float(p_area.get("h", 0)))
	target_town = int(p_area.get("town", -1))
	target_area = int(p_area.get("area", -1))
	for k in ["basic", "open", "loop", "close"]:
		var path := str(p_area.get(k, ""))
		if path == "":
			continue
		var d: AniDef = content.ani(path) if content != null else null
		if d != null and not d.is_empty():
			defs[k] = d
	# 节点放在 area 左上角；下面 rect 用局部坐标 (0,0,w,h)。
	# p_world_pos 由 RoomBuilder 用 PassGrid.map_rect 算好（y 已翻成世界坐标）。
	position = p_world_pos if p_world_pos != Vector2.INF else rect.position
	rect = Rect2(Vector2.ZERO, rect.size)
	_sprite = AniSprite.new()
	_sprite.name = "GateSprite"
	add_child(_sprite)
	_play("basic")


func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer = maxf(_timer - delta, 0.0)
		if _timer <= 0.0:
			if _state == "open":
				_play("loop")
			elif _state == "close":
				_play("basic")
	if _player == null:
		_player = get_tree().get_first_node_in_group("world_player")
	if _player == null or defs.is_empty():
		return
	var local := to_local(_player.global_position)
	var inside := rect.has_point(local)
	if inside == _inside:
		return
	_inside = inside
	if inside:
		if _state == "basic" or _state == "close":
			_play("open")
	else:
		if _state == "loop" or _state == "open":
			_play("close")


func _play(anim: String) -> void:
	if not defs.has(anim):
		return
	if _sprite == null:
		return
	_state = anim
	_sprite.setup(defs[anim], store, Vector2.ZERO, true, true)
	_sprite.playing = true
	_timer = float(defs[anim].total_ms()) / 1000.0
