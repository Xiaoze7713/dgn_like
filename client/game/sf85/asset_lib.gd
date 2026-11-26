## 资产库：PVF 取元数据 + NPK 现场取图（不落地任何中间文件）
##
## 用法：
##   var assets := Sf85Assets.new()
##   assets.open("E:/.../Script.utf8.pvf", "res://assets/npk-index.bin")
##   var room := assets.room("map/mirkwood/n201.map")     # 只读这一间
##   var player := assets.actor("player")                 # 6~7 层
##
## 设计原则：**用到才建**。`room()` 只解该房间的 .map/.til，`actor()` 只建该角色
## 需要的动作帧表，贴图在第一次绘制时才从 NPK 解出来（NpkStore 内部缓存）。
class_name Sf85Assets
extends RefCounted

## 玩家要预热的动作（.ani 名）
const PLAYER_MOTIONS := [
	"stay", "move", "dash", "jump", "jumpattack", "guard",
	"attack1", "attack2", "attack3", "dashattack",
	"weaponcomboshort1", "weaponcomboshort2", "weaponcomboshort3",
	"damage1", "down", "overturn", "sit",
]

## 默认外观（都是 .equ 里的默认物品）
const DEFAULT_SKIN := "equipment/character/swordman/avatar/skin/askin_default.equ"
const DEFAULT_EQU := [
	"equipment/character/swordman/avatar/shoes/ashoes_default.equ",
	"equipment/character/swordman/avatar/pants/apants_default.equ",
	"equipment/character/swordman/avatar/coat/acoat_default.equ",
	"equipment/character/swordman/avatar/hair/ahair_default.equ",
]
const DEFAULT_WEAPON := "equipment/character/swordman/weapon/ssword/sswd_shockwave.equ"
const PLAYER_CHR := "character/swordman/swordman.chr"
const SKILL_UPPERSLASH := "skill/swordman/upperslash.skl"
const MONSTER_LIST := "monster/monster.lst"

var pvf: Sf85Pvf
var store: NpkStore

var _actors := {}
var _rooms := {}
var _mob_paths := {}      # id -> mob 路径（懒加载 monster.lst）
var _mob_paths_loaded := false

var loaded_bytes := 0     # 粗略统计：从 NPK 读出的字节数


func open(pvf_path: String, index_path := "res://assets/npk-index.bin",
		npk_dir := "") -> bool:
	store = NpkStore.new(npk_dir)
	if not store.open(index_path):
		return false
	pvf = Sf85Pvf.new()
	if not pvf.open(pvf_path):
		return false
	return true


func is_ready() -> bool:
	return pvf != null and store != null and store.is_ready()


# ---------------------------------------------------------------------------
# 角色
# ---------------------------------------------------------------------------
## id: "player" 或 "mob:<数字>"
func actor(id: String) -> Dictionary:
	if _actors.has(id):
		return _actors[id]
	var def := {}
	if id == "player":
		def = pvf.build_player(PLAYER_MOTIONS, DEFAULT_EQU, DEFAULT_SKIN, DEFAULT_WEAPON)
		_attach_player_stats(def)
	elif id.begins_with("mob:"):
		var mob_path := mob_path(int(id.substr(4)))
		if mob_path == "":
			LogUtil.warn("monster.lst 里没有 id=%s" % id.substr(4))
		else:
			def = pvf.build_monster(mob_path)
			def["mob"] = pvf.mob_info(mob_path)
	if def.is_empty():
		return {}
	_actors[id] = def
	return def


## 玩家数值全部来自 .chr + 武器 .equ，攻击参数来自 .atk
func _attach_player_stats(def: Dictionary) -> void:
	var chr_stats := pvf.character_info(PLAYER_CHR)
	var weapon_doc := pvf.pvf.get_document(DEFAULT_WEAPON)
	var weapon_atk := 0.0
	var weapon_name := ""
	if weapon_doc != null:
		var wa := weapon_doc.first("equipment physical attack")
		if wa != null:
			weapon_atk = float(wa.value_at(0, 0.0))
		weapon_name = weapon_doc.get_str("name")
	# 面板攻击力 = 角色基础物理攻击 + 武器物理攻击（DNF 的面板口径）
	var power := float(chr_stats.get("physical_attack", 0.0)) + weapon_atk
	def["stats"] = chr_stats
	def["weapon"] = {"name": weapon_name, "physical_attack": weapon_atk}
	def["attack_power"] = power
	# `.chr [attack info]` 里三段普攻的 .atk，按连段顺序对应
	var atks: Array = []
	for p in chr_stats.get("attack_infos", []):
		var a := pvf.attack_info(str(p))
		if not a.is_empty():
			atks.append(a)
	def["attack_chain"] = atks
	def["skill"] = pvf.skill_info(SKILL_UPPERSLASH)
	var upsk := pvf.attack_info("character/swordman/attackinfo/upperslash.atk")
	if not upsk.is_empty():
		def["skill"]["attack"] = upsk


func has_actor(id: String) -> bool:
	if _actors.has(id):
		return true
	if id.begins_with("mob:"):
		return mob_path(int(id.substr(4))) != ""
	return id == "player"


## monster.lst：一行 id、一行 mob 路径交替
func mob_path(id: int) -> String:
	if not _mob_paths_loaded:
		_mob_paths_loaded = true
		var doc := pvf.pvf.get_document(MONSTER_LIST)
		if doc != null:
			var lines := PvfDocument.to_text(doc).split("\n", false)
			var i := 0
			while i + 1 < lines.size():
				var a := lines[i].strip_edges()
				var b := lines[i + 1].strip_edges()
				if a.is_valid_int() and b.ends_with(".mob"):
					# monster.lst 里的路径相对 monster/ 目录
					_mob_paths[int(a)] = b if b.begins_with("monster/") else "monster/" + b
				i += 2
	return str(_mob_paths.get(id, ""))


# ---------------------------------------------------------------------------
# 房间
# ---------------------------------------------------------------------------
func room(map_path: String) -> Dictionary:
	if _rooms.has(map_path):
		return _rooms[map_path]
	var def := pvf.build_room(map_path)
	if not def.is_empty():
		# 通关表：8 片 × 420 格，拼成「全局格」，供 is_walkable 用
		def["grid_w"] = int(def["width"]) / 16
		def["grid_h"] = 480 / 16
		_rooms[map_path] = def
	return def


# ---------------------------------------------------------------------------
# 贴图（懒加载：第一次要才解）
# ---------------------------------------------------------------------------
func frame_texture(f: Dictionary) -> Texture2D:
	var img := str(f.get("img", ""))
	if img == "":
		return null
	return store.texture(img, int(f.get("frame", 0)))


func tile_texture(t: Dictionary) -> Texture2D:
	return store.texture(str(t.get("img", "")), int(t.get("frame", 0)))


## 帧的完整信息：贴图 + 该帧图像在 .img 里的画布偏移(x,y) + 尺寸。
## 坐标公式：精灵左上角 = ani.x + img.x，所以这里把 img.x/img.y 一并带出去。
func frame_info(f: Dictionary) -> Dictionary:
	var img := str(f.get("img", ""))
	if img == "":
		return {}
	var rect := store.frame_rect(img, int(f.get("frame", 0)))
	if rect.size == Vector2i.ZERO:
		return {}
	var tex := store.texture(img, int(f.get("frame", 0)))
	if tex == null:
		return {}
	return {
		"tex": tex, "w": rect.size.x, "h": rect.size.y,
		"x": int(f.get("x", 0)) + rect.position.x,
		"y": int(f.get("y", 0)) + rect.position.y,
	}


func tile_info(t: Dictionary) -> Dictionary:
	return frame_info(t)


## 直接解一个 .ani（房间远景/装饰用，取第 0 帧）
func animation(ani_path: String, look := 0, color := 0) -> Dictionary:
	return pvf.animation(ani_path, look, color)


func stats() -> Dictionary:
	return {
		"actors": _actors.size(),
		"rooms": _rooms.size(),
		"npk": store.stats() if store != null else {},
		"warnings": pvf.warnings.size() if pvf != null else 0,
	}
