## 键盘设置窗口 —— 按客户端「键盘设置窗口」的四个页签还原：
##   系统 / 角色 / 技能 / 聊天快捷键
##
## 动作清单来自 DNF 客户端（DnfKeys.catalog，123 条），每行「动作名 — 当前键」；
## 点键帽进入录制状态，按任意键改绑（Esc 取消，Delete 清空）。
## 改完立即生效并自动存到 user://keybindings.cfg。
class_name KeybindWindow
extends UIWindow

signal keys_changed

const SCOPES := ["system", "character", "dungeon", "quickchat"]

var _tabs: UITabBar
var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _hint: Label
var _reset_btn: Button
var _capturing := ""
var _capture_btn: Button = null
var _key_buttons: Dictionary = {}   # id -> Button
var _scope := "system"
var _pad_preset: OptionButton
var _pad_mode: OptionButton
var _pad_extra: CheckBox


func _ready() -> void:
	super._ready()
	set_title("键盘设置")
	closable = true
	custom_minimum_size = Vector2(760, 620)
	size = Vector2(780, 640)
	_build_ui()
	DnfKeys.watch(_on_keys_changed)


func _exit_tree() -> void:
	DnfKeys.unwatch(_on_keys_changed)


func _build_ui() -> void:
	var head := Label.new()
	head.text = "按 DNF 客户端的四个分类绑定（数据来自 clientonly/hotkeysystem_ver3.co，共 %d 个动作）" % DnfKeys.count()
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(0.62, 0.74, 0.88))
	content.add_child(head)

	_tabs = UITabBar.new()
	_tabs.custom_minimum_size = Vector2(0, 30)
	var titles: Array = []
	for s in SCOPES:
		titles.append(DnfKeys.scope_label(s))
	titles.append("手柄")
	_tabs.set_tabs(titles, 0)
	_tabs.tab_changed.connect(_on_tab_changed)
	content.add_child(_tabs)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 400)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = true
	content.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 4)
	_scroll.add_child(_rows_box)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	content.add_child(foot)

	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.68, 0.8))
	_hint.text = "点键帽改绑 · Esc 取消本次录制 · Delete 清空 · 改完自动保存"
	foot.add_child(_hint)

	_reset_btn = Button.new()
	_reset_btn.text = "恢复默认"
	_reset_btn.pressed.connect(func() -> void:
		DnfKeys.reset_all()
		DnfKeys.save()
		_rebuild_rows()
		_hint.text = "已恢复临时默认方案")
	foot.add_child(_reset_btn)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func() -> void: close_window())
	foot.add_child(close_btn)

	_rebuild_rows()


## 外部（截图脚本 / 快捷键跳转）指定打开哪一页：0..3 = 键盘四页，4 = 手柄
func select_tab(index: int) -> void:
	if _tabs != null:
		_tabs.select(index)
		_on_tab_changed(index)


func _on_tab_changed(index: int) -> void:
	if index == SCOPES.size():
		_scope = "gamepad"
	else:
		_scope = str(SCOPES[index]) if index >= 0 and index < SCOPES.size() else "system"
	_rebuild_rows()


func _rebuild_rows() -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	_pad_preset = null
	_pad_mode = null
	_pad_extra = null
	_key_buttons.clear()
	if _scope == "gamepad":
		_rebuild_gamepad()
		return
	var ids: Array = DnfKeys.ids(_scope)
	for id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_rows_box.add_child(row)

		var name_label := Label.new()
		name_label.text = DnfKeys.name_of(id)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 13)
		var bound := DnfKeys.key_of(id)
		name_label.add_theme_color_override("font_color",
			Color(0.9, 0.94, 1.0) if not bound.is_empty() else Color(0.62, 0.68, 0.75))
		row.add_child(name_label)

		var id_label := Label.new()
		id_label.text = id
		id_label.add_theme_font_size_override("font_size", 11)
		id_label.add_theme_color_override("font_color", Color(0.42, 0.52, 0.62))
		id_label.custom_minimum_size = Vector2(46, 0)
		row.add_child(id_label)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(112, 24)
		btn.add_theme_font_size_override("font_size", 12)
		var label := DnfKeys.key_label(id)
		btn.text = label if not label.is_empty() else "未绑定"
		btn.pressed.connect(_start_capture.bind(id, btn))
		row.add_child(btn)
		_key_buttons[id] = btn

	_hint.text = "%s：%d 个动作 · 点键帽改绑 · Esc 取消 · Delete 清空" % [
			DnfKeys.scope_label(_scope), ids.size()]


## 手柄页：布局是预设的（改键留给后续），这里只做「看 + 换预设/模式」
func _rebuild_gamepad() -> void:
	var head := Label.new()
	head.text = "手柄与键盘共用同一套技能/角色规则，但独立一份布局（可换预设与模式）"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(0.62, 0.74, 0.88))
	_rows_box.add_child(head)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 8)
	_rows_box.add_child(ctrl)

	var pl := Label.new()
	pl.text = "预设"
	pl.add_theme_font_size_override("font_size", 12)
	ctrl.add_child(pl)
	_pad_preset = OptionButton.new()
	_pad_preset.custom_minimum_size = Vector2(190, 26)
	for key in GamepadKeys.PRESET_LABELS.keys():
		_pad_preset.add_item(str(GamepadKeys.PRESET_LABELS[key]))
	_pad_preset.selected = GamepadKeys.PRESET_LABELS.keys().find(GamepadKeys.get_preset())
	_pad_preset.item_selected.connect(func(i: int) -> void:
		GamepadKeys.set_preset(str(GamepadKeys.PRESET_LABELS.keys()[i]))
		_rebuild_rows())
	ctrl.add_child(_pad_preset)

	var ml := Label.new()
	ml.text = "模式"
	ml.add_theme_font_size_override("font_size", 12)
	ctrl.add_child(ml)
	_pad_mode = OptionButton.new()
	_pad_mode.custom_minimum_size = Vector2(120, 26)
	for key in GamepadKeys.MODE_LABELS.keys():
		_pad_mode.add_item(str(GamepadKeys.MODE_LABELS[key]))
	_pad_mode.selected = GamepadKeys.MODE_LABELS.keys().find(GamepadKeys.get_mode())
	_pad_mode.item_selected.connect(func(i: int) -> void:
		GamepadKeys.set_mode(str(GamepadKeys.MODE_LABELS.keys()[i]))
		_rebuild_rows())
	ctrl.add_child(_pad_mode)

	_pad_extra = CheckBox.new()
	_pad_extra.text = "启用第三排（左扳机修饰）"
	_pad_extra.button_pressed = GamepadKeys.extra_row()
	_pad_extra.toggled.connect(func(on: bool) -> void:
		GamepadKeys.set_extra_row(on)
		_rebuild_rows())
	ctrl.add_child(_pad_extra)

	var dev := Label.new()
	var pads := GamepadKeys.device_names()
	dev.text = "已连接：%s" % ("、".join(pads) if not pads.is_empty() else "未检测到手柄（插上后会立刻生效）")
	dev.add_theme_font_size_override("font_size", 11)
	dev.add_theme_color_override("font_color", Color(0.55, 0.68, 0.8))
	_rows_box.add_child(dev)

	for sec in GamepadKeys.describe():
		var title := Label.new()
		title.text = str(sec["title"])
		title.add_theme_font_size_override("font_size", 12)
		title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.5))
		_rows_box.add_child(title)
		for row in sec["rows"]:
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 10)
			_rows_box.add_child(r)
			var nm := Label.new()
			nm.text = str(row[0])
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.add_theme_font_size_override("font_size", 13)
			r.add_child(nm)
			var kb := Label.new()
			kb.text = str(row[1])
			kb.custom_minimum_size = Vector2(112, 0)
			kb.add_theme_font_size_override("font_size", 12)
			kb.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0))
			r.add_child(kb)

	_hint.text = "手柄布局按预设生效 · 插上手柄后 HUD 会自动换成手柄字形"


func _start_capture(id: String, btn: Button) -> void:
	if _capture_btn != null and is_instance_valid(_capture_btn):
		_refresh_button(_capturing)
	_capturing = id
	_capture_btn = btn
	btn.text = "按新键…"
	btn.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	_hint.text = "正在改绑「%s」——按任意键确认，Esc 取消，Delete 清空" % DnfKeys.name_of(id)


func _refresh_button(id: String) -> void:
	var btn: Button = _key_buttons.get(id)
	if btn == null or not is_instance_valid(btn):
		return
	btn.remove_theme_color_override("font_color")
	var label := DnfKeys.key_label(id)
	btn.text = label if not label.is_empty() else "未绑定"


func _input(event: InputEvent) -> void:
	if _capturing.is_empty():
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.echo or not k.pressed:
		return
	get_viewport().set_input_as_handled()
	var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
	var id := _capturing
	_capturing = ""
	if code == KEY_ESCAPE:
		_refresh_button(id)
		_hint.text = "已取消"
		return
	if code == KEY_DELETE or code == KEY_BACKSPACE:
		DnfKeys.clear_key(id)
		DnfKeys.save()
		_refresh_button(id)
		_rebuild_rows()
		keys_changed.emit()
		return
	DnfKeys.set_key(id, OS.get_keycode_string(code))
	DnfKeys.save()
	_rebuild_rows()
	keys_changed.emit()
	var others := DnfKeys.conflicts_of(id)
	if others.is_empty():
		_hint.text = "「%s」→ %s" % [DnfKeys.name_of(id), DnfKeys.key_label(id)]
	else:
		_hint.text = "「%s」→ %s（已自动解除其它冲突）" % [DnfKeys.name_of(id), DnfKeys.key_label(id)]


func _on_keys_changed() -> void:
	if not _capturing.is_empty():
		return
	if _key_buttons.is_empty():
		return
	_rebuild_rows()
