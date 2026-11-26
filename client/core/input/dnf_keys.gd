## DNF 键位系统（临时方案）—— 全部键盘输入的唯一入口
##
## 动作表来自客户端数据 `clientonly/hotkeysystem_ver3.co`（见 tools/extract_dnf_hotkeys.py
## → data/dnf_hotkeys.json），分类与客户端「键盘设置窗口」一致：
##   system 系统 / character 角色 / dungeon 技能 / quickchat 聊天快捷键
##
## 客户端数据的键位字段是空的（默认键在 exe 里），所以这里给了一版**临时默认方案**，
## 尽量贴着 DNF 的肌肉记忆：方向键移动、X 普攻、C 跳跃、Z 技能、空格技能2、
## A S D F G H 技能 1–6、Q W E R T Y 扩展技能 1–6、1–6 物品快捷键。
## 没写进 DEFAULT_KEYS 的动作默认**不绑定**，在设置窗口里可以自己录。
##
## 用法（一次就够）：
##   DnfKeys.install()          # 建 InputMap 动作 + 套键位
##   DnfKeys.is_pressed("I05")  # 按 DNF 动作 id 查询
##   DnfKeys.set_key("I05", "G"); DnfKeys.save()   # 改键并落盘
##
## 所有改动会广播给 DnfKeys.watch(callable) 注册的界面（HUD / 设置窗口用它刷新）。
class_name DnfKeys
extends RefCounted

const CATALOG_PATH := "res://data/dnf_hotkeys.json"
const SAVE_PATH := "user://keybindings.cfg"
const SECTION := "keys"

## 游戏已实现的动作 → DNF 动作 id（player.gd / room.gd 直接读这些语义动作名）
const SEMANTIC := {
	"move_left": "I02",
	"move_right": "I04",
	"move_up": "I01",
	"move_down": "I03",
	"attack": "I05",
	"jump": "I06",
	"skill": "I07",
	"skill2": "I08",
}

## 临时默认方案（只给有意义的动作，其余留空等玩家自己录）
const DEFAULT_KEYS := {
	# 移动 + 战斗
	"I01": "Up", "I02": "Left", "I03": "Down", "I04": "Right",
	"I05": "X", "I06": "C", "I07": "Z", "I08": "Space", "I09": "V",
	# 技能栏 1–6 / 扩展 1–6
	"I21": "A", "I22": "S", "I23": "D", "I24": "F", "I25": "G", "I26": "H",
	"I27": "Q", "I28": "W", "I29": "E", "I30": "R", "I31": "T", "I32": "Y",
	# 物品快捷键 1–6（消耗品栏）
	"I33": "1", "I34": "2", "I35": "3", "I36": "4", "I37": "5", "I38": "6",
	# 角色 / 面板（I11 技能栏留给玩家自配：本工程把 K 留给了金库窗口）
	"I10": "M", "I11": "", "I12": "I", "IA4": "L", "I18": "O",
	"I20": "F1", "I19": "F4", "I65": "F5", "I80": "F6", "I69": "F7",
	"K14": "F8", "K27": "F10", "C03": "Comma", "C04": "Period",
	# 系统
	"I13": "F11", "I61": "F9", "I49": "Escape", "IA1": "Tab",
	"I15": "U", "I16": "P", "I17": "N", "I41": "F2", "I99": "B",
	# 地下城特殊键
	"K02": "J", "K12": "Num0",
}

## 显示用中文名（其余走 OS.get_keycode_string）
const KEY_LABELS := {
	"Up": "↑", "Down": "↓", "Left": "←", "Right": "→",
	"Space": "空格", "Escape": "Esc", "Tab": "Tab", "Enter": "回车",
	"Comma": ",", "Period": ".", "Semicolon": ";", "Apostrophe": "'",
	"BracketLeft": "[", "BracketRight": "]", "Backslash": "\\",
	"Slash": "/", "Minus": "-", "Equal": "=", "Backspace": "退格",
	"Num0": "小键盘0", "Num1": "小键盘1", "Num2": "小键盘2",
	"Shift": "Shift", "Ctrl": "Ctrl", "Alt": "Alt",
}

const SCOPE_LABELS := {
	"system": "系统",
	"character": "角色",
	"dungeon": "技能",
	"quickchat": "聊天快捷键",
}

const SCOPE_ORDER := ["system", "character", "dungeon", "quickchat"]

static var _catalog: Dictionary = {}          # id -> {id,name,scope,side,type}
static var _order: Array = []                  # 按 scope 排序的 id
static var _keys: Dictionary = {}              # id -> String（键名，空 = 未绑定）
static var _loaded := false
static var _installed := false
static var _watchers: Array = []               # Array[Callable]


# ---------------------------------------------------------------- 目录 / 查询

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	if text.is_empty():
		LogUtil.warn("DnfKeys: 读不到 %s" % CATALOG_PATH)
		return
	var doc: Variant = JSON.parse_string(text)
	if typeof(doc) != TYPE_DICTIONARY:
		LogUtil.warn("DnfKeys: %s 不是合法 JSON" % CATALOG_PATH)
		return
	for e in (doc as Dictionary).get("entries", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id := str(e.get("id", ""))
		if id.is_empty():
			continue
		_catalog[id] = e
		_order.append(id)
	# 默认键位 → 运行时表
	for id in _catalog.keys():
		_keys[id] = str(DEFAULT_KEYS.get(id, ""))
	load_user()


static func count() -> int:
	ensure_loaded()
	return _catalog.size()


static func ids(scope := "") -> Array:
	ensure_loaded()
	if scope.is_empty():
		return _order.duplicate()
	var out: Array = []
	for id in _order:
		if str(_catalog[id].get("scope", "")) == scope:
			out.append(id)
	return out


static func has(id: String) -> bool:
	ensure_loaded()
	return _catalog.has(id)


static func name_of(id: String) -> String:
	ensure_loaded()
	return str(_catalog.get(id, {}).get("name", id))


static func scope_of(id: String) -> String:
	ensure_loaded()
	return str(_catalog.get(id, {}).get("scope", ""))


static func scope_label(scope: String) -> String:
	return str(SCOPE_LABELS.get(scope, scope))


static func key_of(id: String) -> String:
	ensure_loaded()
	return str(_keys.get(id, ""))


static func keycode_of(id: String) -> int:
	var k := key_of(id)
	return 0 if k.is_empty() else OS.find_keycode_from_string(k)


## 界面上显示的键帽文字（↑ / 空格 / Esc / A …）；未绑定返回 ""
static func key_label(id: String) -> String:
	var k := key_of(id)
	if k.is_empty():
		return ""
	return str(KEY_LABELS.get(k, OS.get_keycode_string(OS.find_keycode_from_string(k))))


## 任意 InputMap 动作的键帽文字（本工程自己的动作，如 sf85_warehouse）
static func action_key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
			if code != 0:
				var n := OS.get_keycode_string(code)
				return str(KEY_LABELS.get(n, n))
	return ""


## 和 id 抢同一个键的所有动作 id（不含自己）
static func conflicts_of(id: String) -> Array:
	ensure_loaded()
	var k := key_of(id)
	var out: Array = []
	if k.is_empty():
		return out
	for other in _keys.keys():
		if other != id and str(_keys[other]) == k:
			out.append(other)
	return out


# ---------------------------------------------------------------- 动作名 / 输入

## DNF 动作 id → InputMap 动作名
static func action_name(id: String) -> String:
	return "dnf_" + id.to_lower()


## 语义动作名（move_left…）→ InputMap 动作名（就是语义名本身）
static func semantic_action(id: String) -> String:
	for k in SEMANTIC.keys():
		if str(SEMANTIC[k]) == id:
			return str(k)
	return ""


static func is_pressed(id: String) -> bool:
	var a := action_name(id)
	return InputMap.has_action(a) and Input.is_action_pressed(a)


static func is_just_pressed(id: String) -> bool:
	var a := action_name(id)
	return InputMap.has_action(a) and Input.is_action_just_pressed(a)


## 语义动作名查询（player.gd 用）：DnfKeys.pressed("move_left")
static func pressed(semantic: String) -> bool:
	return InputMap.has_action(semantic) and Input.is_action_pressed(semantic)


static func just_pressed(semantic: String) -> bool:
	return InputMap.has_action(semantic) and Input.is_action_just_pressed(semantic)


# ---------------------------------------------------------------- 安装 / 应用

## 建 InputMap 动作（幂等），然后套上当前键位
static func install() -> void:
	ensure_loaded()
	_installed = true
	for id in _catalog.keys():
		_ensure_action(action_name(id))
		var sem := semantic_action(id)
		if not sem.is_empty():
			_ensure_action(sem)
	_ensure_action("debug_toggle")
	_ensure_action("ui_console")
	apply()


static func apply() -> void:
	ensure_loaded()
	for id in _catalog.keys():
		var names: Array = [action_name(id)]
		var sem := semantic_action(id)
		if not sem.is_empty():
			names.append(sem)
		var code := keycode_of(id)
		for n in names:
			var act := str(n)
			if not InputMap.has_action(act):
				InputMap.add_action(act)
			InputMap.action_erase_events(act)
			if code != 0:
				var ev := InputEventKey.new()
				ev.physical_keycode = code
				InputMap.action_add_event(act, ev)
	_notify()


# ---------------------------------------------------------------- 改键 / 存盘

static func set_key(id: String, key_name: String) -> void:
	ensure_loaded()
	if not _catalog.has(id):
		return
	# 一键只绑一个动作：先清掉抢同一个键的
	for other in _keys.keys():
		if other != id and str(_keys[other]) == key_name:
			_keys[other] = ""
	_keys[id] = key_name
	if _installed:
		apply()
	else:
		_notify()


static func clear_key(id: String) -> void:
	set_key(id, "")


static func reset_all() -> void:
	ensure_loaded()
	for id in _catalog.keys():
		_keys[id] = str(DEFAULT_KEYS.get(id, ""))
	if _installed:
		apply()
	else:
		_notify()


static func save() -> void:
	ensure_loaded()
	var cfg := ConfigFile.new()
	for id in _keys.keys():
		cfg.set_value(SECTION, id, str(_keys[id]))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		LogUtil.warn("DnfKeys: 保存失败 %s (%d)" % [SAVE_PATH, err])


static func load_user() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id in cfg.get_section_keys(SECTION):
		if _catalog.has(id):
			_keys[id] = str(cfg.get_value(SECTION, id, ""))


# ---------------------------------------------------------------- 观察者

static func watch(cb: Callable) -> void:
	if not _watchers.has(cb):
		_watchers.append(cb)


static func unwatch(cb: Callable) -> void:
	_watchers.erase(cb)


static func _notify() -> void:
	for cb in _watchers.duplicate():
		if cb.is_valid():
			cb.call()


static func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
