## 直接从 PVF 组装角色/房间的数据（不依赖任何预导出 JSON/PNG）
##
## 链路（与 docs/PVF-ASSET-REFERENCE.md 一致）：
##   .equ  --[variation]--> look/color     --[layer variation]--> 层目录 + z
##   .ani  --sprites 模板---> 图集路径(%02d%02d / %04d) + 帧号(img_param)
##   图集  --NPK 索引-----> 包内 offset/size -> NpkImage 解码
##
## 输出的字典形状与旧的 index.json 保持**同构**，区别只在每帧带的是
## `img` + `frame`（贴图按需从 NPK 取），不再带 `png` 路径。
class_name Sf85Pvf
extends RefCounted

const SLOT_DIRS := {
	"skin": "skin", "pants": "pants", "shoes": "shoes", "belt": "belt",
	"coat": "coat", "neck": "neck", "face": "face", "hair": "hair", "cap": "cap",
}

var pvf: PvfLoader
var warnings: Array[String] = []


func open(pvf_path: String) -> bool:
	pvf = PvfLoader.new()
	var err := pvf.open(pvf_path)
	if err != OK:
		LogUtil.error("PVF 打开失败 %s (err=%d)" % [pvf_path, err])
		return false
	return true


# ---------------------------------------------------------------------------
# 动画
# ---------------------------------------------------------------------------
## 解一个 .ani，返回 {frames:[{img,frame,x,y,delay,boxes}], loop, total_ms}
##
## look/color 用来展开 sprites 模板里的 %02d / %04d 占位。
func animation(ani_path: String, look := 0, color := 0) -> Dictionary:
	var data := pvf.get_animation(ani_path)
	if data == null or data.frames.is_empty():
		warnings.append("动画为空或不存在：%s" % ani_path)
		return {}
	var out: Array = []
	var total := 0
	for i in data.frames.size():
		var f: PvfTypes.AniFrame = data.frames[i]
		var img := ""
		if f.img_id >= 0 and f.img_id < data.sprites.size():
			img = PvfTypes.AniData.fill_template(data.sprites[f.img_id], look, color)
		var frame_index := f.img_param
		if frame_index < 0:
			frame_index = i
		var boxes: Array = []
		for b in f.damage_boxes:
			boxes.append({"kind": "damage", "box": b})
		for b in f.attack_boxes:
			boxes.append({"kind": "attack", "box": b})
		# .ani 里常用 10000/20000 表示"定格"，这里压到 300ms，避免动画卡死
		var delay: int = clampi(f.delay, 16, 300)
		out.append({
			"img": img, "frame": frame_index,
			"x": f.x, "y": f.y, "delay": delay, "boxes": boxes,
		})
		total += delay
	return {"frames": out, "loop": int(data.params.get("loop", 0)) == 1, "total_ms": total}


# ---------------------------------------------------------------------------
# 时装：.equ -> 层清单
# ---------------------------------------------------------------------------
## 返回 [{part, dir, z, look, color}]，按 z 升序（先画的在前）
func equ_layers(equ_path: String) -> Array:
	var doc := pvf.get_document(equ_path)
	if doc == null:
		warnings.append("equ 不存在：%s" % equ_path)
		return []
	var look := 0
	var color := 0
	var var_node := doc.first("variation")
	if var_node != null:
		look = int(var_node.value_at(0, 0))
		color = int(var_node.value_at(1, 0))
	var layers: Array = []
	var lay := doc.first("layer variation")
	if lay == null:
		return layers
	var vals := lay.attrs
	var i := 0
	while i + 1 < vals.size():
		var z := int(vals[i])
		var dirname := str(vals[i + 1])
		layers.append({
			"part": dirname.split("_")[0],
			"dir": dirname, "z": z, "look": look, "color": color,
		})
		i += 2
	layers.sort_custom(func(a, b): return int(a["z"]) < int(b["z"]))
	return layers


## 一个时装槽位在某个动作下的 .ani 路径
func avatar_ani_path(part: String, dirname: String, motion: String) -> String:
	return "equipment/character/swordman/avatar/%s/%s/%s.ani" % [part, dirname, motion]


# ---------------------------------------------------------------------------
# 玩家
# ---------------------------------------------------------------------------
## 组装玩家：皮肤 + 若干 .equ（时装/武器）
##
## motions 是要预热的动作名（只给这些动作建帧表，其它动作 play 时会报缺失）。
func build_player(motions: Array, equ_paths: Array, skin_equ := "", weapon_equ := "") -> Dictionary:
	var layers: Array = []
	# 皮肤：决定 sm_body%04d 的编号，动作在 character/swordman/animation/<motion>.ani
	var skin_look := 1
	if skin_equ != "":
		var skin_doc := pvf.get_document(skin_equ)
		if skin_doc != null:
			var v := skin_doc.first("variation")
			if v != null:
				skin_look = int(v.value_at(0, skin_look))
	var skin_anims := {}
	for m in motions:
		var a := animation("character/swordman/animation/%s.ani" % m, skin_look, 0)
		if not a.is_empty():
			skin_anims[m] = a
	layers.append({"name": "skin", "z": 0, "anims": skin_anims})

	for equ in equ_paths:
		var eq_layers := equ_layers(equ)
		for ld in eq_layers:
			var anims := {}
			for m in motions:
				var a2 := animation(avatar_ani_path(ld["part"], ld["dir"], m),
					int(ld["look"]), int(ld["color"]))
				if not a2.is_empty():
					anims[m] = a2
			if anims.is_empty():
				continue
			layers.append({
				"name": "%s_%s" % [ld["part"], ld["dir"]], "z": int(ld["z"]),
				"anims": anims,
			})
	if weapon_equ != "":
		for wl in weapon_layers(weapon_equ, motions):
			layers.append(wl)
	layers.sort_custom(func(a, b): return int(a["z"]) < int(b["z"]))
	return {"name": "鬼剑士", "layers": layers}


## 武器层：图集模板来自 .ani 的 sprites，帧号来自 IMP_PARAM
func weapon_layers(equ_path: String, motions: Array) -> Array:
	var doc := pvf.get_document(equ_path)
	if doc == null:
		warnings.append("武器 equ 不存在：%s" % equ_path)
		return []
	var look := 0
	var color := 0
	var v := doc.first("variation")
	if v != null:
		look = int(v.value_at(0, 0))
		color = int(v.value_at(1, 0))
	var out: Array = []
	var lay := doc.first("layer variation")
	if lay == null:
		return out
	var vals := lay.attrs
	var i := 0
	var wtype := _weapon_dir_of(equ_path)
	while i + 1 < vals.size():
		var z := int(vals[i])
		var dirname := str(vals[i + 1])
		var anims := {}
		for m in motions:
			var a := animation(
				"equipment/character/swordman/weapon/%s/%s/%s.ani" % [wtype, dirname, m],
				look, color)
			if not a.is_empty():
				anims[m] = a
		if not anims.is_empty():
			out.append({"name": "weapon_%s" % dirname, "z": z, "anims": anims})
		i += 2
	return out


func _weapon_dir_of(equ_path: String) -> String:
	var parts := equ_path.split("/")
	# equipment/character/swordman/weapon/<wtype>/<file>.equ
	for i in parts.size():
		if parts[i] == "weapon" and i + 1 < parts.size():
			return parts[i + 1]
	return "sswd"


# ---------------------------------------------------------------------------
# 怪物
# ---------------------------------------------------------------------------
## 从 .mob 组装怪物（动作名是 .mob 里的语义名，这里统一映射成动画名）
func build_monster(mob_path: String) -> Dictionary:
	var doc := pvf.get_document(mob_path)
	if doc == null:
		warnings.append("mob 不存在：%s" % mob_path)
		return {}
	var base := mob_path.get_base_dir()
	var pairs := [
		["waiting", "waiting motion"], ["move", "move motion"],
		["attack", "attack motion"], ["damage", "damage motion 1"],
		["down", "down motion"], ["overturn", "overturn motion"],
		["sit", "sit motion"],
	]
	var anims := {}
	for p in pairs:
		var ani_rel := doc.get_str(p[1], "")
		if ani_rel == "":
			continue
		var a := animation(base.path_join(ani_rel))
		if not a.is_empty():
			anims[p[0]] = a
	return {
		"name": doc.get_str("name", mob_path.get_file()),
		"layers": [{"name": "body", "z": 0, "anims": anims}],
	}


# ---------------------------------------------------------------------------
# 地图
# ---------------------------------------------------------------------------
## 解一个 .map -> {tiles, pass_rows, monsters, backgrounds, decos, width, height}
##
## 三个要点：
##  1. `[tile]` 是**一个节点 8 个路径**，每条是一「层」224 宽的地面图，横向重复铺满房间
##  2. `[monster]` 是「8 个数 + [fixed]/[normal] 两个空段名」循环，段名也会作为字符串属性
##  3. `[background animation]` 的每条 `[ani info]` 有 filename / layer / order
## 去掉 PVF 文本里的方括号（"[distantback]" -> "distantback"）
func _bare(text: String) -> String:
	return text.strip_edges().trim_prefix("[").trim_suffix("]")


func build_room(map_path: String) -> Dictionary:
	var doc := pvf.get_document(map_path)
	if doc == null:
		warnings.append("map 不存在：%s" % map_path)
		return {}
	var base := map_path.get_base_dir()
	var tiles: Array = []
	var pass_rows: Array = []
	var width := 0
	var tn := doc.first("tile")
	if tn != null:
		var order := 0
		for v in tn.attrs:
			var til_rel := str(v)
			if not til_rel.ends_with(".til"):
				continue
			var til := pvf.get_document(base.path_join(til_rel))
			if til == null:
				warnings.append("til 不存在：%s" % til_rel)
				continue
			var img_rel := ""
			var img_frame := 0
			var img_node := til.first("image")
			if img_node != null:
				img_rel = str(img_node.value_at(0, ""))
				img_frame = int(img_node.value_at(1, 0))
			var cells: Array = []
			var pass_node := til.first("pass type")
			if pass_node != null:
				for pv in pass_node.attrs:
					cells.append(int(pv))
			pass_rows.append(cells)
			tiles.append({"img": img_rel, "frame": img_frame, "order": order})
			width += 14 * 16
			order += 1

	# 怪物：先把字符串属性（[fixed]/[normal] 这类空段名）滤掉，再按 8 个数字一组
	var monsters: Array = []
	var mn := doc.first("monster")
	if mn != null:
		var nums: Array = []
		for v in mn.attrs:
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				nums.append(int(v))
		var i := 0
		while i + 7 < nums.size():
			monsters.append({"id": nums[i], "count": nums[i + 1],
				"x": nums[i + 3], "y": nums[i + 4]})
			i += 8

	var backgrounds: Array = []
	var bn := doc.first("background animation")
	if bn != null:
		for info in bn.child_nodes("ani info"):
			backgrounds.append({
				"ani": base.path_join(info.get_str("filename", "")),
				# PVF 里的值带方括号（"[distantback]"），去掉才好按层查 z
				"layer": _bare(info.get_str("layer", "middleback")),
				"order": _bare(info.get_str("order", "below")),
			})

	# 装饰物：[animation] 是「路径 + 段名 + x + y + 序号」循环
	var decos: Array = []
	var an := doc.first("animation")
	if an != null:
		var cur := ""
		var layer := "normal"
		var triple: Array = []
		for v in an.attrs:
			if typeof(v) == TYPE_STRING:
				var sv := str(v)
				if sv.ends_with(".ani"):
					cur = sv
					triple.clear()
				else:
					layer = sv.strip_edges().trim_prefix("[").trim_suffix("]")
			else:
				triple.append(int(v))
				if triple.size() == 3 and cur != "":
					decos.append({"ani": base.path_join(cur), "layer": layer,
						"x": triple[0], "y": triple[1]})
					cur = ""
					triple.clear()
	return {
		"id": map_path, "tiles": tiles, "pass_rows": pass_rows,
		"monsters": monsters, "backgrounds": backgrounds, "decos": decos,
		"width": width, "height": 480,
	}


# ---------------------------------------------------------------------------
# 战斗数值：直接读 .chr / .atk / .mob / .skl（不做任何预导出）
# ---------------------------------------------------------------------------
## 取同名子节点的第 idx 个数值（找不到返回 def）
func _num(doc: PvfTypes.DocNode, name: String, idx := 0, def := 0.0) -> float:
	if doc == null:
		return def
	var c := doc.first(name)
	if c == null or c.attrs.size() <= idx:
		return def
	var v = c.attrs[idx]
	if typeof(v) == TYPE_STRING:
		return def
	return float(v)


## 取同名子节点最后一个数值（`[hp max]` + `*` + `70` 这种写法）
func _num_last(doc: PvfTypes.DocNode, name: String, def := 0.0) -> float:
	if doc == null:
		return def
	var c := doc.first(name)
	if c == null:
		return def
	for i in range(c.attrs.size() - 1, -1, -1):
		if typeof(c.attrs[i]) != TYPE_STRING:
			return float(c.attrs[i])
	return def


## 取同名子节点的第 idx 个字符串
func _str_at(doc: PvfTypes.DocNode, name: String, idx := 0, def := "") -> String:
	if doc == null:
		return def
	var c := doc.first(name)
	if c == null or c.attrs.size() <= idx:
		return def
	return str(c.attrs[idx])


## 取「空段名 + 下一个节点」这种写法里的值。
##
## `.atk` 里的枚举是这么写的（`[physic]` 是 `[attack type]` 的**兄弟**节点，不是子节点）：
##   [attack type]
##   [physic]
##   [damage reaction]
##   [damage]
## 所以不能只看 children，要看它在 children 数组里的下一个。
func _tag(doc: PvfTypes.DocNode, name: String) -> String:
	if doc == null:
		return ""
	for i in doc.children.size():
		var c: PvfTypes.DocNode = doc.children[i]
		if str(c.name) != name:
			continue
		if not c.attrs.is_empty():
			return str(c.attrs[0])
		if not c.children.is_empty():
			return str(c.children[0].name)
		if i + 1 < doc.children.size():
			return str(doc.children[i + 1].name)
		return ""
	return ""


## 角色基础数据（.chr）
##
## 注意：.chr 里 `[hp max]`/`[physical attack]` 这类节点会按 growtype 重复出现很多次，
## 第一次出现的那组才是基础值（后面是各转职/觉醒的成长表），所以一律取 `first()`。
func character_info(chr_path: String) -> Dictionary:
	var doc := pvf.get_document(chr_path)
	if doc == null:
		warnings.append("chr 不存在：%s" % chr_path)
		return {}
	var attack_infos: Array = []
	var ai := doc.first("attack info")
	if ai != null:
		for v in ai.attrs:
			if typeof(v) == TYPE_STRING and str(v) != "":
				attack_infos.append(chr_path.get_base_dir().path_join(str(v)))
	return {
		"path": chr_path,
		"width": _num(doc, "width", 0, 40.0),
		"depth": _num(doc, "width", 1, 10.0),
		"hp_max": _num(doc, "hp max", 0, 100.0),
		"mp_max": _num(doc, "mp max", 0, 100.0),
		"physical_attack": _num(doc, "physical attack", 0, 0.0),
		"physical_defense": _num(doc, "physical defense", 0, 0.0),
		"move_speed": _num(doc, "move speed", 0, 850.0),
		"attack_speed": _num(doc, "attack speed", 0, 850.0),
		"jump_power": _num(doc, "jump power", 0, 430.0),
		"jump_speed": _num(doc, "jump speed", 0, 95.0),
		"attack_infos": attack_infos,
		"dashattack_info": _str_at(doc, "dashattack info"),
		"jumpattack_info": _str_at(doc, "jumpattack info"),
	}


## 一次攻击的判定参数（.atk）
func attack_info(atk_path: String) -> Dictionary:
	var doc := pvf.get_document(atk_path)
	if doc == null:
		warnings.append("atk 不存在：%s" % atk_path)
		return {}
	return {
		"path": atk_path,
		"type": _tag(doc, "attack type"),
		"damage_bonus": _num(doc, "damage bonus", 0, 0.0),
		"weapon_apply": _num(doc, "weapon damage apply", 0, 0.0),
		"attack_enemy": _num(doc, "attack enemy", 0, 1.0),
		"element": _tag(doc, "elemental property"),
		"reaction": _tag(doc, "damage reaction"),
		"direction": _tag(doc, "attack direction"),
		"push_aside": _num(doc, "push aside", 0, 0.0),
		"lift_up": _num(doc, "lift up", 0, 0.0),
	}


## 怪物数据（.mob）
func mob_info(mob_path: String) -> Dictionary:
	var doc := pvf.get_document(mob_path)
	if doc == null:
		warnings.append("mob 不存在：%s" % mob_path)
		return {}
	var category := doc.first("ability category")
	var hp_mult := 100.0
	if category != null:
		hp_mult = _num_last(category, "hp max", 100.0)
	var atk_rel := _str_at(doc, "attack info")
	var base := mob_path.get_base_dir()
	return {
		"path": mob_path,
		"name": _str_at(doc, "name", 0, mob_path.get_file()),
		"width": _num(doc, "width", 0, 40.0),
		"depth": _num(doc, "width", 1, 10.0),
		"hp_mult": hp_mult,
		"move_speed": _num(doc, "move speed", 0, 300.0),
		"attack_speed": _num(doc, "attack speed", 0, 400.0),
		"sight": _num(doc, "sight", 0, 300.0),
		"attack_delay": _num(doc, "attack delay", 0, 1500.0),
		"level_min": _num(doc, "level", 0, 1.0),
		"level_max": _num(doc, "level", 1, 1.0),
		"attack_info": base.path_join(atk_rel) if atk_rel != "" else "",
	}


## 技能数据（.skl 的 dungeon 段）
func skill_info(skl_path: String) -> Dictionary:
	var doc := pvf.get_document(skl_path)
	if doc == null:
		warnings.append("skl 不存在：%s" % skl_path)
		return {}
	var out := {
		"path": skl_path,
		"name": _str_at(doc, "name"),
		"cool_time": 0,
		"consume_mp": 0,
		"static_data": [],
		"level_rows": [],
	}
	var dun := doc.first("dungeon")
	if dun == null:
		return out
	out["cool_time"] = int(_num(dun, "cool time", 0, 0.0))
	out["consume_mp"] = int(_num(dun, "consume mp", 0, 0.0))
	var sd := dun.first("static data")
	if sd != null:
		var arr: Array = []
		for v in sd.attrs:
			if typeof(v) != TYPE_STRING:
				arr.append(int(v))
		out["static_data"] = arr
	var li := dun.first("level info")
	if li != null and not li.attrs.is_empty():
		var cols := int(li.attrs[0])
		if cols > 0:
			var rows: Array = []
			var i := 1
			while i + cols <= li.attrs.size():
				var row: Array = []
				for k in cols:
					row.append(int(li.attrs[i + k]))
				rows.append(row)
				i += cols
			out["level_rows"] = rows
	return out
