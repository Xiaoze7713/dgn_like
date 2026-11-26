## 游戏内 HUD：左上角角色/HP/MP，右下角操作提示，伤害数字生成。
##
## 不放在 UIRoot 下：HUD 属于游戏层，始终固定屏幕尺寸；分辨率放大时
## 只让世界相机缩放，HUD 和物品栏都不跟着放大。
class_name Sf85Hud
extends Control

const FONT_FAMILY := "Noto Sans CJK SC, Source Han Sans SC, Microsoft YaHei, WenQuanYi Zen Hei"
const PANEL_POS := Vector2(12, 10)
const PANEL_SIZE := Vector2(338, 92)

@export var show_hud := true
@export var show_damage_numbers := true
@export var damage_font_size := 24
@export var damage_float_height := 54.0
@export var damage_duration := 0.9
@export var hud_scale := 1.0

var player: Sf85Player = null
var damage_layer: Node2D = null
var camera: Camera2D = null

var _font: SystemFont
var _font_bold: SystemFont
var _message := ""

var _panel_sb: StyleBoxFlat
var _hp_bg: StyleBoxFlat
var _hp_fill: StyleBoxFlat
var _mp_bg: StyleBoxFlat
var _mp_fill: StyleBoxFlat
var _hint_bg: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = _make_font(false)
	_font_bold = _make_font(true)
	_panel_sb = _box(Color(0.018, 0.035, 0.06, 0.86), Color(0.38, 0.7, 0.95, 0.55), 9)
	_hp_bg = _box(Color(0.05, 0.07, 0.09, 0.9), Color(0.5, 0.2, 0.2, 0.7), 3)
	_hp_fill = _box(Color(0.82, 0.16, 0.18, 1.0), Color(0.95, 0.35, 0.3, 0.9), 3)
	_mp_bg = _box(Color(0.04, 0.06, 0.1, 0.9), Color(0.2, 0.35, 0.6, 0.7), 3)
	_mp_fill = _box(Color(0.18, 0.5, 0.95, 1.0), Color(0.35, 0.75, 1.0, 0.9), 3)
	_hint_bg = _box(Color(0.015, 0.03, 0.05, 0.62), Color(0.3, 0.55, 0.8, 0.25), 5)


func _make_font(bold: bool) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FONT_FAMILY.split(",", false))
	for i in f.font_names.size():
		f.font_names[i] = f.font_names[i].strip_edges()
	f.font_weight = 700 if bold else 400
	f.allow_system_fallback = true
	return f


func _box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	return sb


func setup(p: Sf85Player, layer: Node2D, cam: Camera2D) -> void:
	player = p
	damage_layer = layer
	camera = cam


func set_hud_scale(v: float) -> void:
	hud_scale = clampf(v, 0.75, 1.6)
	queue_redraw()


func set_message(text: String) -> void:
	_message = text
	queue_redraw()


func spawn_damage(world_pos: Vector2, amount: float, kind := "hit") -> void:
	if not show_damage_numbers or damage_layer == null or not is_instance_valid(damage_layer):
		return
	var color := Color(1.0, 0.94, 0.78)
	match kind:
		"skill":
			color = Color(1.0, 0.72, 0.28)
		"player":
			color = Color(1.0, 0.35, 0.32)
		"crit":
			color = Color(1.0, 0.9, 0.35)
	var zoom := 1.0
	if camera != null and is_instance_valid(camera):
		zoom = maxf(0.1, camera.zoom.x)
	var n := Sf85DamageNumber.new()
	n.position = world_pos + Vector2(randf_range(-6.0, 6.0), -4.0)
	n.setup(str(maxi(1, roundi(amount))), color, _font, damage_font_size,
		damage_float_height, damage_duration, 1.0 / zoom)
	damage_layer.add_child(n)


func _process(_delta: float) -> void:
	if visible and show_hud:
		queue_redraw()


func _draw() -> void:
	if not show_hud:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(hud_scale, hud_scale))
	_draw_player_panel()
	_draw_hint()
	if _message != "":
		var w := 460.0
		var r := Rect2((size.x / hud_scale - w) * 0.5, 84, w, 30)
		draw_style_box(_hint_bg, r)
		draw_string(_font, r.position + Vector2(0, 21), _message,
			HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(1, 0.5, 0.45))


func _draw_player_panel() -> void:
	var r := Rect2(PANEL_POS, PANEL_SIZE)
	draw_style_box(_panel_sb, r)

	var name := "鬼剑士"
	var level := 3
	var hp := 0.0
	var hp_max := 1.0
	var mp := 0.0
	var mp_max := 1.0
	var atk := 0.0
	if player != null and is_instance_valid(player):
		name = "鬼剑士"
		level = 3
		hp = player.hp
		hp_max = maxf(1.0, player.hp_max)
		mp = player.mp
		mp_max = maxf(1.0, player.mp_max)
		atk = player.attack_power

	draw_string(_font_bold, r.position + Vector2(14, 22), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.96, 1.0))
	draw_string(_font, r.position + Vector2(14, 22), "Lv.%d" % level,
		HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 28, 11, Color(1.0, 0.84, 0.48))
	draw_string(_font, r.position + Vector2(14, 34), "幽暗密林 · n201",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.64, 0.78))

	var bx := r.position.x + 14.0
	var bw := r.size.x - 28.0
	_bar(Rect2(bx, r.position.y + 40, bw, 14), hp / hp_max, _hp_bg, _hp_fill)
	draw_string(_font, Vector2(bx, r.position.y + 51), "HP  %d / %d" % [roundi(hp), roundi(hp_max)],
		HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color(1, 1, 1, 0.92))
	_bar(Rect2(bx, r.position.y + 58, bw, 12), mp / mp_max, _mp_bg, _mp_fill)
	draw_string(_font, Vector2(bx, r.position.y + 68), "MP  %d / %d" % [roundi(mp), roundi(mp_max)],
		HORIZONTAL_ALIGNMENT_CENTER, bw, 10, Color(1, 1, 1, 0.92))
	draw_string(_font, Vector2(bx, r.position.y + 84),
		"攻击力 %.1f    ·    F1 控制台" % atk,
		HORIZONTAL_ALIGNMENT_LEFT, bw, 10, Color(0.6, 0.75, 0.9))

	draw_string(_font, Vector2(PANEL_POS.x + PANEL_SIZE.x + 10, 22),
		"FPS %d" % Engine.get_frames_per_second(),
		HORIZONTAL_ALIGNMENT_LEFT, 90, 10, Color(0.5, 0.62, 0.72, 0.8))


func _bar(box: Rect2, ratio: float, bg: StyleBoxFlat, fill: StyleBoxFlat) -> void:
	draw_style_box(bg, box)
	var t := clampf(ratio, 0.0, 1.0)
	if t <= 0.0:
		return
	var f := box
	f.size.x = maxf(2.0, box.size.x * t)
	draw_style_box(fill, f)


func _draw_hint() -> void:
	var text := "F1 控制台    %s 背包    %s 金库    %s 跳跃    %s 普攻    %s 技能    %s 键位设置" % [
		DnfKeys.key_label("I12"), DnfKeys.action_key_label("sf85_warehouse"), DnfKeys.key_label("I06"),
		DnfKeys.key_label("I05"), DnfKeys.key_label("I07"), DnfKeys.key_label("I61")]
	var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var r := Rect2(12, size.y / hud_scale - 30, ts.x + 20, 22)
	draw_style_box(_hint_bg, r)
	draw_string(_font, r.position + Vector2(10, 15), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.74, 0.86, 0.9))
