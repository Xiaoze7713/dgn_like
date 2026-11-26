## DNF 风格底部主 HUD：消耗品栏 / 技能栏 / HP·MP 球 / 右侧功能按钮
##
## 版式参照客户端实机截图（红框区域）：
##   左：2 列 × 3 行消耗品格（物品快捷键 1–6）
##   中：6 × 2 技能格（上排 技能快捷键 1–6，下排 扩展技能快捷键 1–6）
##   中左 / 中右：圆形 HP / MP 球
##   右：常用功能按钮（背包 / 键位 / 地图 / 商城 / 菜单）
##
## 键帽文字全部来自 DnfKeys（改键后 HUD 立刻跟着变）；键位本身不在本文件里写死。
class_name Sf85HudBottom
extends Control

signal consumable_used(index: int)
signal skill_used(index: int)
signal button_pressed(id: String)

const FONT_FAMILY := "Noto Sans CJK SC, Source Han Sans SC, Microsoft YaHei, WenQuanYi Zen Hei"

const BAR_W := 860.0
const BAR_H := 118.0
const BOTTOM_MARGIN := 6.0
const SLOT := 36.0
const SLOT_GAP := 4.0
const SKILL_SLOT := 40.0
const SKILL_GAP := 3.0
const ORB_R := 30.0
const BTN := 28.0

## 技能格 → DNF 动作 id（上排 6 个技能快捷键，下排 6 个扩展快捷键）
const SKILL_IDS: Array = [
	"I21", "I22", "I23", "I24", "I25", "I26",
	"I27", "I28", "I29", "I30", "I31", "I32",
]
## 消耗品格 → DNF 动作 id（物品快捷键 1–6）
const CONSUMABLE_IDS: Array = ["I33", "I34", "I35", "I36", "I37", "I38"]
## 右侧功能按钮
const BUTTONS: Array = [
	{"id": "inventory", "glyph": "背包", "hint": "背包 (I)"},
	{"id": "keybinds", "glyph": "键位", "hint": "键盘设置 (F9)"},
	{"id": "map", "glyph": "地图", "hint": "地图 (N)"},
	{"id": "mall", "glyph": "商城", "hint": "商城 (P)"},
	{"id": "menu", "glyph": "菜单", "hint": "菜单 (Esc)"},
]

@export var hud_scale := 1.0

var player: Sf85Player = null
var room: Node = null

## 消耗品格内容：{icon: Texture2D, count: int, label: String}
var consumables: Array[Dictionary] = []
## 技能格内容：{icon: Texture2D, name: String, cd_total: float, cd_left: float}
var skills: Array[Dictionary] = []

var _font: SystemFont
var _font_bold: SystemFont
var _panel: StyleBoxFlat
var _slot_bg: StyleBoxFlat
var _slot_hover: StyleBoxFlat
var _btn_bg: StyleBoxFlat
var _toast := ""
var _toast_t := 0.0
var _hover_slot := -1
var _dragging := false

var _bar := Rect2()
var _cons_rects: Array = []
var _skill_rects: Array = []
var _btn_rects: Array = []
var _hp_center := Vector2.ZERO
var _mp_center := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 自己撑出一条贴底的带子：Control 不是容器，PRESET_BOTTOM_WIDE 只改锚点不改高度
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	var band_h := BAR_H + BOTTOM_MARGIN + 26.0
	custom_minimum_size = Vector2(0, band_h)
	offset_top = -band_h
	offset_bottom = 0.0
	offset_left = 0.0
	offset_right = 0.0
	_font = _make_font(false)
	_font_bold = _make_font(true)
	_panel = _box(Color(0.02, 0.035, 0.055, 0.82), Color(0.42, 0.72, 0.95, 0.45), 10)
	_slot_bg = _box(Color(0.06, 0.09, 0.13, 0.86), Color(0.35, 0.52, 0.72, 0.5), 4)
	_slot_hover = _box(Color(0.13, 0.2, 0.28, 0.92), Color(0.95, 0.82, 0.45, 0.85), 4)
	_btn_bg = _box(Color(0.07, 0.11, 0.16, 0.88), Color(0.34, 0.5, 0.7, 0.55), 5)
	DnfKeys.watch(_on_keys_changed)
	_build_consumables()
	_build_skills()
	_relayout()


func _exit_tree() -> void:
	DnfKeys.unwatch(_on_keys_changed)


func _on_keys_changed() -> void:
	queue_redraw()


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


# ------------------------------------------------------------------ 对外

func setup(p: Sf85Player, r: Node = null) -> void:
	player = p
	room = r


func set_hud_scale(v: float) -> void:
	hud_scale = clampf(v, 0.75, 1.6)
	_relayout()


func toast(text: String, seconds := 2.0) -> void:
	_toast = text
	_toast_t = seconds
	queue_redraw()


func set_consumable(index: int, icon: Texture2D, count := 1, label := "") -> void:
	while consumables.size() <= index:
		consumables.append({})
	consumables[index] = {"icon": icon, "count": count, "label": label}
	queue_redraw()


func set_skill(index: int, icon: Texture2D, skill_name := "", cd_total := 0.0) -> void:
	while skills.size() <= index:
		skills.append({})
	skills[index] = {
		"icon": icon, "name": skill_name, "cd_total": cd_total, "cd_left": 0.0,
	}
	queue_redraw()


## 接了手柄就切换成手柄字形与 4 列布局（room 每帧同步）
var pad_active := false:
	set(v):
		if pad_active == v:
			return
		pad_active = v          # 在 setter 内赋值 = 写回背field，不会递归
		_relayout()
		queue_redraw()

## 手柄布局参数变了（第三排开关等）→ 重排
func refresh_pad_layout() -> void:
	_relayout()
	queue_redraw()


func key_hint(id: String) -> String:
	return DnfKeys.key_label(id)


## 技能/物品槽的键帽：优先手柄字形
func slot_label(index: int, is_consumable: bool) -> String:
	if pad_active:
		var pad := GamepadKeys.consumable_label(index) if is_consumable else GamepadKeys.skill_label(index)
		return pad   # 手柄模式下没绑定就空着，不退回键盘键帽
	return DnfKeys.key_label(str(CONSUMABLE_IDS[index] if is_consumable else SKILL_IDS[index]))


## 只更新冷却，不动图标/名字（每帧调，避免重建字典）
func set_skill_cd(index: int, left: float, total := 0.0) -> void:
	while skills.size() <= index:
		skills.append({})
	var d: Dictionary = skills[index]
	d["cd_left"] = maxf(0.0, left)
	if total > 0.0:
		d["cd_total"] = total
	skills[index] = d


## 技能格对应的 DNF 动作 id（HUD 与房间/玩家都用它查键）
func skill_action_id(index: int) -> String:
	return str(SKILL_IDS[index]) if index >= 0 and index < SKILL_IDS.size() else ""


func consumable_action_id(index: int) -> String:
	return str(CONSUMABLE_IDS[index]) if index >= 0 and index < CONSUMABLE_IDS.size() else ""


# ------------------------------------------------------------------ 布局

func _build_consumables() -> void:
	if consumables.size() == 6:
		return
	var out: Array[Dictionary] = []
	for i in 6:
		out.append({})
	consumables = out


func _build_skills() -> void:
	if skills.size() == 12:
		return
	var out: Array[Dictionary] = []
	for i in 12:
		out.append({})
	skills = out


func _relayout() -> void:
	_cons_rects.clear()
	_skill_rects.clear()
	_btn_rects.clear()

	var s := hud_scale
	var bar_w := minf(BAR_W * s, maxf(520.0, size.x - 24.0))
	var bar_h := BAR_H * s
	var x := (size.x - bar_w) * 0.5
	var y := size.y - BOTTOM_MARGIN - bar_h
	_bar = Rect2(Vector2(x, y), Vector2(bar_w, bar_h))

	# 左：2 列 × 3 行消耗品
	var cx := _bar.position.x + 12.0
	var cy := _bar.position.y + (bar_h - (3.0 * SLOT * s + 2.0 * SLOT_GAP * s)) * 0.5
	for i in 6:
		var col := i / 3
		var row := i % 3
		_cons_rects.append(Rect2(
			cx + col * (SLOT * s + SLOT_GAP * s),
			cy + row * (SLOT * s + SLOT_GAP * s),
			SLOT * s, SLOT * s))

	# 中：键盘 6 × 2 / 手柄 4 × 2（面键一排、LB 一排；开第三排才 4 × 3）
	var cols := 4 if pad_active else 6
	var slot_count := 12
	if pad_active and not GamepadKeys.extra_row():
		slot_count = 8
	var rows := int(ceil(float(slot_count) / float(cols)))
	var grid_w := float(cols) * SKILL_SLOT * s + float(cols - 1) * SKILL_GAP * s
	var grid_h := float(rows) * SKILL_SLOT * s + float(rows - 1) * SKILL_GAP * s
	var gx := _bar.position.x + (bar_w - grid_w) * 0.5
	var gy := _bar.position.y + (bar_h - grid_h) * 0.5
	for i in slot_count:
		var col := i % cols
		var row := i / cols
		_skill_rects.append(Rect2(
			gx + col * (SKILL_SLOT * s + SKILL_GAP * s),
			gy + row * (SKILL_SLOT * s + SKILL_GAP * s),
			SKILL_SLOT * s, SKILL_SLOT * s))

	var orb_r := ORB_R * s
	_hp_center = Vector2(gx - orb_r - 14.0 * s, _bar.position.y + bar_h * 0.5)
	_mp_center = Vector2(gx + grid_w + orb_r + 14.0 * s, _bar.position.y + bar_h * 0.5)

	# 右：功能按钮 2 行 × 3
	var bx := _bar.position.x + bar_w - (3.0 * BTN * s + 2.0 * 6.0 * s) - 12.0 * s
	var by := _bar.position.y + (bar_h - (2.0 * BTN * s + 6.0 * s)) * 0.5
	for i in BUTTONS.size():
		var col := i % 3
		var row := i / 3
		_btn_rects.append(Rect2(
			bx + col * (BTN * s + 6.0 * s),
			by + row * (BTN * s + 6.0 * s),
			BTN * s, BTN * s))

	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()


# ------------------------------------------------------------------ 输入

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var m := (event as InputEventMouseMotion).position
		var h := _hit_test(m)
		if h != _hover_slot:
			_hover_slot = h
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var h := _hit_test(mb.position)
			if h >= 0 and h < 12:
				skill_used.emit(h)
				accept_event()
			elif h >= 100 and h < 106:
				consumable_used.emit(h - 100)
				accept_event()
			elif h >= 200:
				button_pressed.emit(str(BUTTONS[h - 200].get("id", "")))
				accept_event()


## 返回：-1 无 / 0–11 技能格 / 100–105 消耗品格 / 200+ 功能按钮
func _hit_test(p: Vector2) -> int:
	for i in _skill_rects.size():
		if (_skill_rects[i] as Rect2).has_point(p):
			return i
	for i in _cons_rects.size():
		if (_cons_rects[i] as Rect2).has_point(p):
			return 100 + i
	for i in _btn_rects.size():
		if (_btn_rects[i] as Rect2).has_point(p):
			return 200 + i
	return -1


# ------------------------------------------------------------------ 绘制

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t = maxf(0.0, _toast_t - delta)
		queue_redraw()
	if visible:
		# 冷却与血蓝每秒都在变，直接重绘（内容很小）
		queue_redraw()


func _draw() -> void:
	# 把控制点放到「底部左右留白」的位置：内容都在 _bar 里
	draw_style_box(_panel, _bar)
	draw_line(
		_bar.position + Vector2(10, 1),
		_bar.position + Vector2(_bar.size.x - 10, 1),
		Color(0.55, 0.8, 1.0, 0.25), 1.0)

	_draw_consumables()
	_draw_skills()
	_draw_orbs()
	_draw_buttons()
	_draw_toast()


func _draw_consumables() -> void:
	for i in _cons_rects.size():
		var r: Rect2 = _cons_rects[i]
		var d: Dictionary = consumables[i] if i < consumables.size() else {}
		var hovered := _hover_slot == 100 + i
		draw_style_box(_slot_hover if hovered else _slot_bg, r)
		var icon: Texture2D = d.get("icon")
		if icon != null and is_instance_valid(icon):
			draw_texture_rect(icon, r.grow(-3), false)
		var count := int(d.get("count", 0))
		if count > 1:
			_draw_text(str(count), r.position + Vector2(r.size.x - 2, r.size.y - 3),
				HORIZONTAL_ALIGNMENT_RIGHT, 0, 10, Color(1, 0.93, 0.72), true)
		var key := slot_label(i, true)
		if key != "":
			_draw_text(key, r.position + Vector2(3, 11), HORIZONTAL_ALIGNMENT_LEFT, 0, 10,
				Color(0.78, 0.88, 1.0, 0.85))
		if not (d.get("label", "") as String).is_empty() and hovered:
			var lbl := str(d.get("label"))
			var w := _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16
			var tip := Rect2(r.position.x - w * 0.5 + r.size.x * 0.5,
				r.position.y - 26.0, w, 22)
			draw_style_box(_slot_bg, tip)
			_draw_text(lbl, tip.position + Vector2(0, 15), HORIZONTAL_ALIGNMENT_CENTER,
				tip.size.x, 12, Color(0.95, 0.97, 1.0))


func _draw_skills() -> void:
	for i in _skill_rects.size():
		var r: Rect2 = _skill_rects[i]
		var d: Dictionary = skills[i] if i < skills.size() else {}
		var hovered := _hover_slot == i
		draw_style_box(_slot_hover if hovered else _slot_bg, r)
		var icon: Texture2D = d.get("icon")
		if icon != null and is_instance_valid(icon):
			draw_texture_rect(icon, r.grow(-3), false)
		else:
			var nm := str(d.get("name", ""))
			if nm.is_empty():
				_draw_text("空", r.position + Vector2(0, r.size.y * 0.5 + 5.0),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Color(0.45, 0.55, 0.66, 0.8))
			else:
				# 没有图标时用技能名前两个字顶一下，避免大片空格子看不出装了什么
				_draw_text(nm.substr(0, 2), r.position + Vector2(0, r.size.y * 0.5 + 5.0),
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color(0.86, 0.92, 1.0))

		var key := slot_label(i, false)
		if key != "":
			var kw := _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 6
			var kr := Rect2(r.position.x + r.size.x - kw - 1, r.position.y + r.size.y - 13,
				kw, 12)
			draw_rect(kr, Color(0.02, 0.03, 0.05, 0.72))
			_draw_text(key, kr.position + Vector2(0, 9.5), HORIZONTAL_ALIGNMENT_CENTER,
				kr.size.x, 10, Color(0.9, 0.96, 1.0))

		var cd := float(d.get("cd_left", 0.0))
		var total := maxf(0.001, float(d.get("cd_total", 0.0)))
		if cd > 0.0:
			var ratio := clampf(cd / total, 0.0, 1.0)
			draw_rect(r.grow(-2), Color(0.02, 0.04, 0.07, 0.62 * ratio + 0.25))
			_draw_text("%.1f" % cd, r.position + Vector2(0, r.size.y * 0.5 + 5.0),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color(1, 0.86, 0.5))


func _draw_orbs() -> void:
	var hp := 1.0
	var mp := 1.0
	var hp_text := "--"
	var mp_text := "--"
	if player != null and is_instance_valid(player):
		var hp_max := maxf(1.0, player.hp_max)
		var mp_max := maxf(1.0, player.mp_max)
		hp = clampf(player.hp / hp_max, 0.0, 1.0)
		mp = clampf(player.mp / mp_max, 0.0, 1.0)
		hp_text = "%d%%" % roundi(hp * 100.0)
		mp_text = "%d%%" % roundi(mp * 100.0)
	_orb(_hp_center, ORB_R * hud_scale, hp,
		Color(0.75, 0.12, 0.16), Color(1.0, 0.42, 0.36), hp_text, "HP")
	_orb(_mp_center, ORB_R * hud_scale, mp,
		Color(0.1, 0.35, 0.8), Color(0.42, 0.72, 1.0), mp_text, "MP")


func _orb(center: Vector2, radius: float, ratio: float,
		deep: Color, bright: Color, text: String, label: String) -> void:
	draw_circle(center, radius, Color(0.02, 0.03, 0.05, 0.92))
	draw_circle(center, radius - 2.0, Color(0.08, 0.1, 0.14, 0.95))
	if ratio > 0.001:
		var r2 := radius - 5.0
		draw_circle(center, r2, Color(deep.r, deep.g, deep.b, 0.32))
		# 用粗弧表示液位（从正上方逆时针）
		var start := -PI * 0.5
		draw_arc(center, r2, start, start + TAU * ratio, 40, bright, 5.0, true)
	draw_arc(center, radius, 0.0, TAU, 40, Color(bright.r, bright.g, bright.b, 0.55), 1.5, true)
	_draw_text(text, center + Vector2(0, 5.0), HORIZONTAL_ALIGNMENT_CENTER,
		radius * 2.0, 13, Color(1, 1, 1, 0.95))
	_draw_text(label, center + Vector2(0, radius + 13.0), HORIZONTAL_ALIGNMENT_CENTER,
		radius * 2.0, 10, Color(bright.r, bright.g, bright.b, 0.85))


func _draw_buttons() -> void:
	for i in _btn_rects.size():
		var r: Rect2 = _btn_rects[i]
		var d: Dictionary = BUTTONS[i]
		var hovered := _hover_slot == 200 + i
		draw_style_box(_slot_hover if hovered else _btn_bg, r)
		var fs := int(maxf(9.0, 11.0 * hud_scale))
		_draw_text(str(d.get("glyph", "")), r.position + Vector2(0, r.size.y * 0.5 + 4.0),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(0.82, 0.9, 1.0))
		if hovered:
			var hint := str(d.get("hint", ""))
			var w := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14
			var tip := Rect2(r.position.x + r.size.x * 0.5 - w * 0.5,
				r.position.y - 24.0, w, 20)
			draw_style_box(_slot_bg, tip)
			_draw_text(hint, tip.position + Vector2(0, 14), HORIZONTAL_ALIGNMENT_CENTER,
				tip.size.x, 11, Color(0.95, 0.97, 1.0))


func _draw_toast() -> void:
	if _toast.is_empty() or _toast_t <= 0.0:
		return
	var fs := 13
	var w := _font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 26
	var r := Rect2(_bar.position.x + (_bar.size.x - w) * 0.5,
		_bar.position.y - 34.0, w, 26)
	draw_style_box(_panel, r)
	_draw_text(_toast, r.position + Vector2(0, 18), HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x, fs, Color(1.0, 0.88, 0.55))


## 统一的小字绘制：draw_string 需要基线下沿，这里把 y 当「底的下一行」处理
func _draw_text(text: String, pos: Vector2, align: int, width: float, fs: int,
		color: Color, right_align := false) -> void:
	if right_align:
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, pos - Vector2(w, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		return
	draw_string(_font, pos, text, align, width, fs, color)
