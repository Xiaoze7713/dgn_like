## 物品详情浮框：稀有度描边、图标、名称、类型、词条、耐久、说明、重量/价格。
##
## 全部用 `_draw` 画，尺寸随内容自适应；由 UITooltipLayer 负责跟随鼠标和贴边。
class_name UITooltip
extends Control

@export var panel_width := 320
@export var pad := 12

var item: ItemDef = null
var _rows: Array[Dictionary] = []
var _header_h := 54.0
var _tex: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func set_item(it: ItemDef) -> void:
	item = it
	_tex = null
	if it == null:
		visible = false
		return
	_build(it)
	var h := pad * 2 + _header_h
	for row in _rows:
		h += float(row.get("h", 0.0))
	size = Vector2(panel_width, h)
	custom_minimum_size = size
	visible = true
	queue_redraw()


func _resolve_icon() -> void:
	if item == null or _tex != null:
		return
	var root := get_tree().get_first_node_in_group("ui_root")
	if root != null and root.has_method("item_texture"):
		_tex = root.item_texture(item)


# ---------------------------------------------------------------------------
# 内容排版
# ---------------------------------------------------------------------------

func _build(it: ItemDef) -> void:
	_rows.clear()
	var f := UIKit.font(self, false)
	var fb := UIKit.font(self, true)
	var d := UIKit.data(self)
	var fs_m := UIKit.fs(self, "fs_m", 14)
	var fs_s := UIKit.fs(self, "fs_s", 12)
	var fs_xs := UIKit.fs(self, "fs_xs", 11)
	var inner := float(panel_width - pad * 2 - 6)

	for tag in it.tags:
		if tag.strip_edges() == "":
			continue
		_rows.append({"t": "text", "s": tag, "f": f, "fs": fs_s,
				"c": d.text_secondary, "h": 16.0})

	if it.level > 0 or it.required_job != "":
		var req := ""
		if it.level > 0:
			req = "Lv%d以上可以使用" % it.level
		if it.required_job != "":
			req += ("  ·  " if req != "" else "") + it.required_job
		_rows.append({"t": "text", "s": req, "f": f, "fs": fs_s,
				"c": d.text_muted, "h": 18.0})

	if not it.stats.is_empty() or it.durability_max > 0:
		_rows.append({"t": "div", "h": 8.0})

	for st in it.stats:
		var tone := str(st.get("tone", "normal"))
		var col := d.text_primary
		if tone == "good":
			col = d.text_success
		elif tone == "bad":
			col = d.text_danger
		_rows.append({"t": "stat", "l": str(st.get("label", "")),
				"v": str(st.get("value", "")), "c": col, "fs": fs_m, "h": 20.0})

	if it.durability_max > 0:
		var ratio := clampf(float(it.durability) / float(it.durability_max), 0.0, 1.0)
		var col := d.text_success.lerp(d.text_danger, 1.0 - ratio)
		_rows.append({"t": "stat", "l": "耐久度",
				"v": "%d/%d" % [it.durability, it.durability_max],
				"c": col, "fs": fs_s, "h": 19.0})

	if it.description != "":
		_rows.append({"t": "div", "h": 9.0})
		for line in _wrap_text(it.description, inner, f, fs_s):
			_rows.append({"t": "text", "s": line, "f": f, "fs": fs_s,
					"c": d.text_muted, "h": 17.0})

	if it.effect != "":
		for line in _wrap_text(it.effect, inner, f, fs_s):
			_rows.append({"t": "text", "s": line, "f": f, "fs": fs_s,
					"c": d.text_success, "h": 17.0})

	_rows.append({"t": "div", "h": 9.0})
	_rows.append({"t": "footer", "l": it.weight_text(), "v": it.value_text(),
			"fs": fs_xs, "h": 20.0, "bind": it.bind_state})


func _wrap_text(text: String, max_w: float, f: Font, fs: int) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in text.split("\n"):
		var line := ""
		for ch in raw:
			var test := line + ch
			if line != "" and f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
				out.append(line)
				line = ch
			else:
				line = test
		out.append(line)
	return out


func _fit_text(text: String, max_w: float, f: Font, fs: int) -> String:
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return text
	var out := text
	while out.length() > 1 and f.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		out = out.substr(0, out.length() - 1)
	return out + "…"


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

func _draw() -> void:
	if item == null:
		return
	var d := UIKit.data(self)
	if d == null:
		return

	var rc := d.rarity_color(item.rarity)
	var w := panel_width
	var h := size.y
	var r := Rect2(0, 0, w, h)

	# 外层阴影
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.shadow_color = Color(0, 0, 0, 0.55)
	sh.shadow_size = 12
	sh.shadow_offset = Vector2(0, 4)
	sh.set_corner_radius_all(7)
	draw_style_box(sh, r)

	# 底板 + 稀有度描边
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.018, 0.032, 0.055, 0.97)
	bg.border_color = rc
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(7)
	bg.anti_aliasing = true
	draw_style_box(bg, r)

	# 顶部/左侧的高光
	draw_rect(Rect2(Vector2(8, 1), Vector2(w - 16, 1)), UIKit.a(Color.WHITE, 0.10))
	draw_rect(Rect2(Vector2(0, 8), Vector2(2, h - 16)), UIKit.a(rc, 0.85))
	for i in 3:
		var y := 6.0 + i * 3.0
		draw_line(Vector2(7, y), Vector2(7 + 12 - i * 3, y), UIKit.a(rc, 0.18), 1.0, true)

	var x := float(pad)
	var y := float(pad)

	# ---- 头部：图标 + 名称 + 类型 ----
	var ib := Rect2(x, y, 44, 44)
	UIKit.round_rect(self, ib, UIKit.a(d.slot_bg, 0.9), 4, UIKit.a(rc, 0.55), 1)
	_resolve_icon()
	if _tex != null:
		draw_texture_rect(_tex, ib.grow(-4), false)
	else:
		UIKit.diamond(self, ib.get_center(), 9, UIKit.a(rc, 0.55))

	var nx := ib.end.x + 9
	var nw := w - nx - pad - 2
	var name := _fit_text(item.item_name, nw, UIKit.font(self, true), 15)
	UIKit.text(self, name, Rect2(nx, y + 1, nw, 21), UIKit.font(self, true), 15, rc)

	var type_line := item.item_type
	if item.rarity_name() != "":
		type_line += "  ·  " + item.rarity_name()
	UIKit.text(self, type_line, Rect2(nx, y + 23, nw, 16), UIKit.font(self, false),
			UIKit.fs(self, "fs_s", 12), d.text_secondary)
	if item.bind_state != "":
		UIKit.text(self, item.bind_state, Rect2(nx, y + 39, nw, 14), UIKit.font(self, false),
				UIKit.fs(self, "fs_xs", 11), d.text_muted)
	if item.level > 0:
		UIKit.text(self, "Lv.%d" % item.level, Rect2(w - pad - 52, y + 1, 52, 16),
				UIKit.font(self, true), 11, d.text_gold, UIKit.ALIGN_RIGHT)

	y += _header_h

	for row in _rows:
		var kind := str(row.get("t", "text"))
		var rh := float(row.get("h", 0.0))
		if kind == "div":
			var yy := y + rh * 0.5
			UIKit.divider(self, Vector2(x + 4, yy), Vector2(w - pad - 4, yy),
					UIKit.a(d.frame_color, 0.42))
		elif kind == "stat":
			var fs := int(row.get("fs", 14))
			UIKit.text(self, str(row.get("l", "")), Rect2(x + 4, y, w * 0.55, rh),
					UIKit.font(self, false), fs, d.text_secondary)
			UIKit.text(self, str(row.get("v", "")), Rect2(x + w * 0.4, y, w - x - pad - w * 0.4, rh),
					UIKit.font(self, true), fs, row.get("c", d.text_primary), UIKit.ALIGN_RIGHT)
		elif kind == "footer":
			var fs := int(row.get("fs", 11))
			var bind := str(row.get("bind", ""))
			var left := str(row.get("l", ""))
			if bind != "":
				left = bind + "   " + left
			UIKit.text(self, left, Rect2(x + 4, y, w * 0.45, rh), UIKit.font(self, false),
					fs, d.text_muted)
			UIKit.text(self, str(row.get("v", "")), Rect2(w * 0.45, y, w - pad - w * 0.45 - 4, rh),
					UIKit.font(self, false), fs, d.text_gold, UIKit.ALIGN_RIGHT)
		else:
			UIKit.text(self, str(row.get("s", "")), Rect2(x + 4, y, w - x - pad - 4, rh),
					row.get("f", UIKit.font(self, false)), int(row.get("fs", 12)),
					row.get("c", d.text_secondary))
		y += rh
