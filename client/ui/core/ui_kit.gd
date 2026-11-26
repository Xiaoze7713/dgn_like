## UI 小工具：从控件树里找 UITheme、画圆角框、画文字、格式化数字。
##
## 约定：所有自定义控件都从 `UI` 这个 Theme 类型里取颜色/常量，
## 这样 UIRoot 换 Theme 时，整棵 UI 自动跟着变，不需要逐个 set。
class_name UIKit
extends RefCounted

const ALIGN_LEFT := HORIZONTAL_ALIGNMENT_LEFT
const ALIGN_CENTER := HORIZONTAL_ALIGNMENT_CENTER
const ALIGN_RIGHT := HORIZONTAL_ALIGNMENT_RIGHT


static func data(c: CanvasItem) -> UITheme:
	var node: Node = c
	while node != null:
		if node is Control:
			var th: Theme = (node as Control).theme
			if th != null and th.has_meta("ui_theme"):
				return th.get_meta("ui_theme") as UITheme
		node = node.get_parent()
	return null


static func col(c: CanvasItem, key: String, fallback := Color.WHITE) -> Color:
	var ctl := c as Control
	if ctl != null and ctl.has_theme_color(key, "UI"):
		return ctl.get_theme_color(key, "UI")
	return fallback


static func k(c: CanvasItem, key: String, fallback := 0) -> int:
	var ctl := c as Control
	if ctl != null and ctl.has_theme_constant(key, "UI"):
		return ctl.get_theme_constant(key, "UI")
	return fallback


static func fs(c: CanvasItem, key: String, fallback := 14) -> int:
	var ctl := c as Control
	if ctl != null and ctl.has_theme_font_size(key, "UI"):
		return ctl.get_theme_font_size(key, "UI")
	return fallback


static func font(c: CanvasItem, bold := false) -> Font:
	var key := "font_bold" if bold else "font"
	var ctl := c as Control
	if ctl != null and ctl.has_theme_font(key, "UI"):
		return ctl.get_theme_font(key, "UI")
	return ThemeDB.fallback_font


static func rarity_color(c: CanvasItem, rarity: int) -> Color:
	var d := data(c)
	if d != null:
		return d.rarity_color(rarity)
	return Color(0.82, 0.86, 0.92)


static func a(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


static func mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, t)


# ---------------------------------------------------------------------------
# 绘制
# ---------------------------------------------------------------------------

static func style(bg: Color, border := Color(0, 0, 0, 0), radius := 6, border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	return sb


static func round_rect(ci: CanvasItem, rect: Rect2, bg: Color, radius := 6,
		border := Color(0, 0, 0, 0), border_w := 1) -> void:
	ci.draw_style_box(style(bg, border, radius, border_w), rect)


## 带「上亮下暗」纵向渐变的圆角框，用于标题栏 / 按钮。
static func gradient_rect(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color, radius := 6) -> void:
	var sb := style(bottom, Color(0, 0, 0, 0), radius, 0)
	sb.bg_color = bottom
	# 用 StyleBoxFlat 的“第二层”没有渐变；这里拆成上下两半叠一个渐变纹理。
	var grad := Gradient.new()
	grad.set_color(0, top)
	grad.set_color(1, bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 8
	ci.draw_texture_rect(tex, rect, false)
	# 顶部/底部 1px 收边
	if radius > 0:
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), top.lightened(0.12))
		ci.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 1), Vector2(rect.size.x, 1)),
				bottom.darkened(0.25))


static func text(ci: CanvasItem, s: String, rect: Rect2, f: Font, size: int, color: Color,
		align := ALIGN_LEFT, valign := VERTICAL_ALIGNMENT_CENTER) -> void:
	if s == "" or f == null:
		return
	var measured := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var x := rect.position.x
	if align == ALIGN_CENTER:
		x += (rect.size.x - measured.x) * 0.5
	elif align == ALIGN_RIGHT:
		x += rect.size.x - measured.x
	var y := rect.position.y + (rect.size.y - measured.y) * 0.5
	if valign == VERTICAL_ALIGNMENT_TOP:
		y = rect.position.y
	elif valign == VERTICAL_ALIGNMENT_BOTTOM:
		y = rect.end.y - measured.y
	y += f.get_ascent(size)
	# 轻微投影，玻璃上的白字更实
	ci.draw_string(f, Vector2(x + 1, y + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			Color(0, 0, 0, color.a * 0.45))
	ci.draw_string(f, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func text_width(f: Font, s: String, size: int) -> float:
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func text_height(f: Font, size: int) -> float:
	return f.get_height(size)


static func diamond(ci: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0),
	]), color)


## 四角的小 L 形装饰；不依赖圆角，画在窗口最上层。
static func corner_accents(ci: CanvasItem, rect: Rect2, color: Color, length := 14.0, width := 1.0) -> void:
	var p := rect.position
	var e := rect.end
	var pts := [
		[Vector2(p.x + 4, p.y + 4 + length), Vector2(p.x + 4, p.y + 4), Vector2(p.x + 4 + length, p.y + 4)],
		[Vector2(e.x - 4 - length, p.y + 4), Vector2(e.x - 4, p.y + 4), Vector2(e.x - 4, p.y + 4 + length)],
		[Vector2(p.x + 4, e.y - 4 - length), Vector2(p.x + 4, e.y - 4), Vector2(p.x + 4 + length, e.y - 4)],
		[Vector2(e.x - 4 - length, e.y - 4), Vector2(e.x - 4, e.y - 4), Vector2(e.x - 4, e.y - 4 - length)],
	]
	for seg in pts:
		ci.draw_polyline(PackedVector2Array(seg), color, width, true)


static func divider(ci: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	ci.draw_line(from, to, color, 1.0, true)
	UIKit.diamond(ci, from.lerp(to, 0.5), 2.5, color)


# ---------------------------------------------------------------------------
# 数字格式
# ---------------------------------------------------------------------------

static func fmt_int(n: int) -> String:
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func fmt_kg(kg: float) -> String:
	return "%.1fkg" % kg
