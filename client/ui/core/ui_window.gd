## 可拖动窗口：玻璃面板 + 标题栏 + 内容区。
##
## 子类在 `_ready()` 里先 `super._ready()`，然后往 `content`（VBoxContainer）里加东西。
class_name UIWindow
extends Control

signal opened
signal closed
signal item_selected(item: ItemDef)

@export var window_title := "窗口"
@export var status_text := ""
@export var closable := true
@export var draggable := true

var panel: UIPanel
var title_bar: UITitleBar
var body: MarginContainer
var content: VBoxContainer
var tooltip_layer: UITooltipLayer = null

var selected_item: ItemDef = null
var _selected_slot: UISlot = null
var _dragging := false
var _drag_offset := Vector2.ZERO
var _anim: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	custom_minimum_size = Vector2(320, 200)

	panel = UIPanel.new()
	panel.name = "Panel"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	title_bar = UITitleBar.new()
	title_bar.name = "TitleBar"
	title_bar.window_title = window_title
	title_bar.status_text = status_text
	title_bar.closable = closable
	add_child(title_bar)
	title_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_bar.offset_left = 1
	title_bar.offset_right = -1
	title_bar.offset_top = 1
	title_bar.offset_bottom = UIKit.k(self, "title_h", 42)

	body = MarginContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", UIKit.k(self, "section_gap", 10))
	body.add_child(content)

	title_bar.close_requested.connect(close_window)
	title_bar.gui_input.connect(_on_title_input)
	theme_changed.connect(_on_theme_changed)
	resized.connect(_layout)
	_layout()

	hide()


func _on_theme_changed() -> void:
	_layout()
	queue_redraw()


func _layout() -> void:
	if body == null or title_bar == null:
		return
	var pad := UIKit.k(self, "pad", 14)
	var th := UIKit.k(self, "title_h", 42)
	title_bar.offset_top = 1
	title_bar.offset_bottom = th
	body.offset_left = pad
	body.offset_top = th + pad
	body.offset_right = -pad
	body.offset_bottom = -pad


func set_title(text: String) -> void:
	window_title = text
	if title_bar != null:
		title_bar.window_title = text


func set_status(text: String) -> void:
	status_text = text
	if title_bar != null:
		title_bar.status_text = text


# ---------------------------------------------------------------------------
# 开关
# ---------------------------------------------------------------------------

func open_window(immediate := false) -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	show()
	bring_to_front()
	if immediate:
		modulate.a = 1.0
		scale = Vector2.ONE
		opened.emit()
		return
	modulate.a = 0.0
	pivot_offset = size * 0.5
	scale = Vector2(0.965, 0.965)
	_anim = create_tween().set_parallel(true)
	_anim.tween_property(self, "modulate:a", 1.0, 0.16)
	_anim.tween_property(self, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	opened.emit()


func close_window(immediate := false) -> void:
	if not visible:
		return
	if _anim != null and _anim.is_valid():
		_anim.kill()
	if immediate:
		hide()
		closed.emit()
		return
	pivot_offset = size * 0.5
	_anim = create_tween().set_parallel(true)
	_anim.tween_property(self, "modulate:a", 0.0, 0.12)
	_anim.tween_property(self, "scale", Vector2(0.97, 0.97), 0.12)
	_anim.finished.connect(func():
		hide()
		modulate.a = 1.0
		scale = Vector2.ONE
		closed.emit()
	)


func is_open() -> bool:
	return visible


func bring_to_front() -> void:
	if get_parent() != null:
		get_parent().move_child(self, get_parent().get_child_count() - 1)


# ---------------------------------------------------------------------------
# 拖动
# ---------------------------------------------------------------------------

func _on_title_input(event: InputEvent) -> void:
	if not draggable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_local_mouse_position() - position
			bring_to_front()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var p := get_local_mouse_position() - _drag_offset
		var parent_ctl := get_parent_control()
		if parent_ctl != null:
			var maxp := parent_ctl.size - size
			p.x = clampf(p.x, 0.0, maxf(0.0, maxp.x))
			p.y = clampf(p.y, 0.0, maxf(0.0, maxp.y))
		position = p


# ---------------------------------------------------------------------------
# 槽位辅助
# ---------------------------------------------------------------------------

func setup(tooltip: UITooltipLayer) -> void:
	tooltip_layer = tooltip


func wire_slot(slot: UISlot) -> void:
	slot.hover_started.connect(_on_slot_hover)
	slot.hover_ended.connect(_on_slot_unhover)
	slot.activated.connect(_on_slot_activated)


func _on_slot_hover(slot: UISlot) -> void:
	if slot.item != null and tooltip_layer != null:
		tooltip_layer.show_item(slot.item, slot.get_global_rect())


func _on_slot_unhover(_slot: UISlot) -> void:
	if tooltip_layer != null:
		tooltip_layer.hide_tooltip()


func _on_slot_activated(slot: UISlot) -> void:
	if _selected_slot != null and is_instance_valid(_selected_slot):
		_selected_slot.selected = false
	_selected_slot = slot
	slot.selected = true
	selected_item = slot.item
	item_selected.emit(slot.item)
