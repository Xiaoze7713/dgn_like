## 一个物品格：底槽、图标、数量、耐久、悬停/选中描边。
##
## 图标纹理通过场景树里的 UIRoot（group = "ui_root"）解析，
## 这样 UI 组件本身不需要知道 NPK / ItemDB 的存在。
class_name UISlot
extends Control

signal hover_started(slot: UISlot)
signal hover_ended(slot: UISlot)
signal activated(slot: UISlot)
signal right_clicked(slot: UISlot)
signal lock_changed(slot: UISlot)

@export var slot_id := ""
## 空槽时显示的淡色字，比如「武」「衣」「戒」。
@export var empty_glyph := ""
@export var equipped := false:
	set(v):
		equipped = v
		_update_process()
		queue_redraw()
## 禁用槽：仍显示物品，但变暗、不可悬停/点击。
@export var disabled := false:
	set(v):
		disabled = v
		_update_cursor()
		_update_process()
		queue_redraw()
@export var item: ItemDef = null:
	set(v):
		item = v
		_tex = null
		_tex_key = ""
		_update_cursor()
		_update_process()
		queue_redraw()

## 单个物品格锁定：排序时保留位置。
@export var locked := false:
	set(v):
		locked = v
		queue_redraw()

@export var selected := false:
	set(v):
		selected = v
		queue_redraw()

var _hover := false
var _tex: Texture2D = null
var _tex_key := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	custom_minimum_size = Vector2(UIKit.k(self, "slot", 46), UIKit.k(self, "slot", 46))
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_update_cursor()
	queue_redraw()


func _update_process() -> void:
	var want := equipped and item != null and item.rarity >= 5 and not disabled
	set_process(want)


func _process(_delta: float) -> void:
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		var s := UIKit.k(self, "slot", 46)
		if custom_minimum_size.x != s:
			custom_minimum_size = Vector2(s, s)
		queue_redraw()


func clear_item() -> void:
	item = null


func _update_cursor() -> void:
	if disabled:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if item != null else Control.CURSOR_ARROW


func _on_mouse_entered() -> void:
	if disabled:
		return
	_hover = true
	queue_redraw()
	hover_started.emit(self)


func _on_mouse_exited() -> void:
	_hover = false
	queue_redraw()
	hover_ended.emit(self)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.ctrl_pressed:
				locked = not locked
				lock_changed.emit(self)
				accept_event()
				return
			activated.emit(self)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(self)
			accept_event()


func _resolve_icon() -> void:
	if item == null:
		_tex = null
		return
	var key := "%s:%d" % [item.icon_img, item.icon_frame]
	if key == _tex_key:
		return
	_tex_key = key
	_tex = null
	var root := get_tree().get_first_node_in_group("ui_root")
	if root != null and root.has_method("item_texture"):
		_tex = root.item_texture(item)


func _draw() -> void:
	var d := UIKit.data(self)
	if d == null:
		return
	var s := minf(size.x, size.y)
	var r := Rect2(Vector2((size.x - s) * 0.5, (size.y - s) * 0.5), Vector2(s, s))
	var radius := 5

	# 底槽
	UIKit.round_rect(self, r, d.slot_bg, radius,
			UIKit.a(d.slot_border, 0.55), 1)
	# 内阴影 + 顶部微高光，让槽面有一点凹感
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 1)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(r.position + Vector2(2, r.size.y - 3), Vector2(r.size.x - 4, 1)),
			UIKit.a(d.frame_highlight, 0.07))

	if item != null:
		_resolve_icon()
		var rc := d.rarity_color(item.rarity)
		# 稀有度底色：只铺很淡的一层，避免图标被染色
		UIKit.round_rect(self, r.grow(-1), Color(rc.r, rc.g, rc.b, 0.075), radius - 1)
		var icon_side := s * 0.74
		var ir := Rect2(r.get_center() - Vector2(icon_side, icon_side) * 0.5,
				Vector2(icon_side, icon_side))
		if _tex != null:
			draw_texture_rect(_tex, ir, false)
		else:
			# 纹理没加载出来：画个占位菱形，避免整格空着
			UIKit.diamond(self, r.get_center(), icon_side * 0.28, UIKit.a(rc, 0.6))

		# 稀有度描边：普通物品不描，否则太花
		if item.rarity > 0:
			UIKit.round_rect(self, r, Color(0, 0, 0, 0), radius,
					UIKit.a(rc, 0.42), 1)
		if equipped and item.rarity >= 5:
			_draw_rarity_fx(r, rc)

		# 数量
		var cnt := item.display_count()
		if cnt != "":
			var f := UIKit.font(self, true)
			UIKit.text(self, cnt, Rect2(r.position.x + 2, r.end.y - 16, r.size.x - 5, 14),
					f, 10, Color(1, 1, 1, 0.95), UIKit.ALIGN_RIGHT)

		# 耐久
		if item.durability_max > 0 and item.durability < item.durability_max:
			var ratio := clampf(float(item.durability) / float(item.durability_max), 0.0, 1.0)
			var bar_w := r.size.x - 10
			var bx := r.position.x + 5
			var by := r.end.y - 4
			draw_rect(Rect2(Vector2(bx, by), Vector2(bar_w, 2)), Color(0, 0, 0, 0.65))
			var bc := d.text_success.lerp(d.text_danger, 1.0 - ratio)
			draw_rect(Rect2(Vector2(bx, by), Vector2(bar_w * ratio, 2)), bc)

		if equipped:
			UIKit.diamond(self, Vector2(r.position.x + 7, r.position.y + 7), 3.0,
					UIKit.a(d.gold, 0.95))
	else:
		if empty_glyph != "":
			var f := UIKit.font(self, false)
			UIKit.text(self, empty_glyph, r, f, int(s * 0.42),
					UIKit.a(d.text_muted, 0.35), UIKit.ALIGN_CENTER)
		# 空槽四角的小装饰
		UIKit.corner_accents(self, r.grow(-3), UIKit.a(d.slot_border, 0.25), 5.0, 1.0)

	if disabled:
		# 禁用：压暗整格并画一道斜线，像被锁住的装备位。
		UIKit.round_rect(self, r, Color(0.012, 0.022, 0.038, 0.62), radius)
		draw_line(r.position + Vector2(7, r.size.y - 7),
				r.end - Vector2(7, 7), Color(0.72, 0.78, 0.86, 0.55), 1.5)
		UIKit.round_rect(self, r, Color(0, 0, 0, 0), radius,
				Color(0.45, 0.5, 0.58, 0.45), 1)
		return

	# 单个物品锁定：左上角小锁
	if locked:
		_draw_lock_badge(r)

	# 悬停 / 选中
	if selected:
		UIKit.round_rect(self, r.grow(1), Color(0, 0, 0, 0), radius + 1,
				UIKit.a(d.slot_selected, 0.95), 2)
		UIKit.corner_accents(self, r.grow(2), UIKit.a(d.gold, 0.55), 8.0, 1.0)
	elif _hover:
		UIKit.round_rect(self, r.grow(1), Color(0, 0, 0, 0), radius + 1,
				UIKit.a(d.slot_hover, 0.85), 2)
		UIKit.round_rect(self, r.grow(-1), Color(0.5, 0.85, 1.0, 0.04), radius)


# ---------------------------------------------------------------------------
# 稀有度动态效果：5 阶起环绕旋转光点，6 阶再加多色渐变描边
# ---------------------------------------------------------------------------

func _draw_rarity_fx(r: Rect2, rc: Color) -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0
	var center := r.get_center()

	# 只保留边缘闪光：不再画会呼吸的外圈光晕。
	# 环绕旋转的四颗小星
	for i in 4:
		var a := t * 1.35 + TAU * float(i) / 4.0
		var orbit := Vector2(r.size.x * 0.5 + 3.0, r.size.y * 0.5 + 3.0)
		var p := center + Vector2(cos(a) * orbit.x, sin(a) * orbit.y)
		var star := 2.8
		draw_circle(p, star + 2.4, UIKit.a(rc, 0.22))
		draw_circle(p, star, Color(1, 1, 1, 0.95))
		# 十字星芒，静态截图里也能看出“在发光”
		var spike := star + 2.0
		draw_line(p - Vector2(spike, 0), p + Vector2(spike, 0), UIKit.a(rc, 0.45), 1.0, true)
		draw_line(p - Vector2(0, spike), p + Vector2(0, spike), UIKit.a(rc, 0.45), 1.0, true)

	if item.rarity >= 6:
		# 传说：沿圆角框走一圈 HSV 渐变，颜色缓慢流动。
		var pts := _rounded_rect_points(r.grow(2.0), 6.5, 8)
		var cols := PackedColorArray()
		for i in pts.size():
			var h := fmod(t * 0.12 + float(i) / float(maxi(1, pts.size())), 1.0)
			var c := Color.from_hsv(h, 0.72, 1.0)
			c.a = 0.9
			cols.append(c)
		draw_polyline_colors(pts, cols, 2.4, true)


func _rounded_rect_points(r: Rect2, radius: float, segments: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - radius, r.position.y + radius), -PI * 0.5],
		[Vector2(r.end.x - radius, r.end.y - radius), 0.0],
		[Vector2(r.position.x + radius, r.end.y - radius), PI * 0.5],
		[Vector2(r.position.x + radius, r.position.y + radius), PI],
	]
	for ci in corners.size():
		var c: Vector2 = corners[ci][0]
		var a0: float = corners[ci][1]
		for i in segments + 1:
			var a := a0 + (PI * 0.5) * float(i) / float(segments)
			out.append(c + Vector2(cos(a), sin(a)) * radius)
	return out


func _draw_lock_badge(r: Rect2) -> void:
	var d := UIKit.data(self)
	if d == null:
		return
	var p := r.position + Vector2(5, 5)
	var body := Rect2(p + Vector2(0, 3), Vector2(7, 6))
	draw_rect(body, UIKit.a(d.gold, 0.9), true)
	draw_arc(p + Vector2(3.5, 3.5), 3.0, PI, TAU, 8, UIKit.a(d.gold, 0.9), 1.2, true)
	draw_circle(p + Vector2(3.5, 6.0), 1.0, Color(0.02, 0.03, 0.05, 0.9))
