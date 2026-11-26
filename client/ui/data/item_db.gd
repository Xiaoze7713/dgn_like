## Mock 道具表。
##
## 图标帧全部来自 sf85 客户端真实图集（28x28）：
##   iconweapon / iconarmor / iconacc / iconstackable / iconmaterial / iconavatar
## 名字、数值、描述是编的，先把 UI 的排版和交互跑通。
## 将来接真实道具表时，把这里换成“从 PVF / 服务端读 ItemDef”即可。
class_name ItemDB
extends RefCounted

const SLOT_LABELS := {
	"title": "称号",
	"weapon_main": "主手",
	"weapon_off": "副手",
	"weapon_alt1": "备用武器 1",
	"weapon_alt2": "备用武器 2",
	"head": "头部",
	"shoulder": "护肩",
	"coat": "上衣",
	"pants": "下装",
	"belt": "腰带",
	"shoes": "鞋子",
	"bracer": "护腕",
	"necklace": "项链",
	"ring1": "戒指",
	"ring2": "戒指",
	"earring": "耳环",
}

const SLOT_ORDER := [
	"title",
	"weapon_main", "weapon_off", "weapon_alt1", "weapon_alt2",
	"head", "coat", "shoulder", "pants", "belt", "shoes", "bracer",
	"necklace", "ring1", "ring2", "earring",
]

const WAREHOUSE_FILTER_TABS := ["全部", "装备", "消耗品", "材料", "副职业", "任务"]
const WAREHOUSE_FILTER_KEYS := ["", "equipment", "consumable", "material", "profession", "quest"]

const TAB_CATEGORIES := {
	"装备": ["equipment"],
	"消耗品": ["consumable"],
	"材料": ["material"],
	"副职业": ["profession"],
	"任务": ["quest"],
}

const INVENTORY_TABS := ["物品栏", "时装", "宠物"]
const WAREHOUSE_TABS := ["个人金库", "账号金库"]


static func slot_label(slot: String) -> String:
	return str(SLOT_LABELS.get(slot, "装备"))


static func icon_weapon(frame: int) -> Array:
	return ["sprite/item/iconweapon.img", frame]


static func icon_armor(frame: int) -> Array:
	return ["sprite/item/iconarmor.img", frame]


static func icon_acc(frame: int) -> Array:
	return ["sprite/item/iconacc.img", frame]


static func icon_stack(frame: int) -> Array:
	return ["sprite/item/iconstackable.img", frame]


static func icon_mat(frame: int) -> Array:
	return ["sprite/item/iconmaterial.img", frame]


static func icon_avatar(frame: int) -> Array:
	return ["sprite/item/iconavatar.img", frame]


# ---------------------------------------------------------------------------
# 构造器
# ---------------------------------------------------------------------------

static var _acquired_seq := 0

static func _base(id: String, name: String, category: String, icon: Array) -> ItemDef:
	_acquired_seq += 1
	var it := ItemDef.new()
	it.acquired = _acquired_seq
	it.item_id = id
	it.item_name = name
	it.category = category
	it.icon_img = str(icon[0])
	it.icon_frame = int(icon[1])
	it.max_stack = 1 if category == "equipment" or category == "avatar" else 999
	return it


static func _equip(id: String, name: String, slot: String, icon: Array, rarity: int,
		level: int, item_type: String, tags: Array, stats: Array, opts := {}) -> ItemDef:
	var it := _base(id, name, "equipment", icon)
	it.slot = slot
	it.rarity = rarity
	it.level = level
	it.item_type = item_type
	it.tags = PackedStringArray(tags)
	it.bind_state = str(opts.get("bind", "封装"))
	it.weight = float(opts.get("weight", 2.0))
	it.value = int(opts.get("value", 3200))
	it.durability_max = int(opts.get("durability", 40))
	it.durability = int(opts.get("durability_now", it.durability_max))
	it.required_job = str(opts.get("job", "鬼剑士"))
	it.description = str(opts.get("desc", ""))
	for s in stats:
		it.add_stat(str(s[0]), str(s[1]), str(s[2]) if s.size() > 2 else "normal")
	return it


static func _stack(id: String, name: String, icon: Array, rarity: int, count: int,
		opts := {}) -> ItemDef:
	var it := _base(id, name, str(opts.get("category", "consumable")), icon)
	it.rarity = rarity
	it.count = count
	it.max_stack = int(opts.get("max_stack", 999))
	it.weight = float(opts.get("weight", 0.01))
	it.value = int(opts.get("value", 12))
	it.item_type = str(opts.get("type", "消耗品"))
	it.tags = PackedStringArray(opts.get("tags", []))
	it.description = str(opts.get("desc", ""))
	it.effect = str(opts.get("effect", ""))
	it.level = int(opts.get("level", 0))
	it.bind_state = str(opts.get("bind", "不可交易"))
	return it


static func _mat(id: String, name: String, icon: Array, rarity: int, count: int,
		opts := {}) -> ItemDef:
	var o := opts.duplicate()
	o["category"] = "material"
	o["type"] = str(o.get("type", "材料"))
	var it := _stack(id, name, icon, rarity, count, o)
	it.category = "material"
	return it


# ---------------------------------------------------------------------------
# 装备（穿在身上的那一套）
# ---------------------------------------------------------------------------

static func equipment() -> Dictionary:
	var d := {}
	d["title"] = _equip("eq_title_01", "阿拉德探险家", "title", icon_acc(90), 4, 1, "称号",
		["所有属性强化 +2", "冒险团等级 +1"],
		[["力量", "+10"], ["智力", "+10"], ["体力", "+10"], ["精神", "+10"],
		 ["所有属性强化", "+2"]],
		{"weight": 0.0, "value": 0, "bind": "账号绑定",
		 "desc": "走遍阿拉德的人，名字会被记在酒馆的墙上。"})
	d["weapon_main"] = _equip("eq_weapon_01", "月影太刀", "weapon_main", icon_weapon(38), 5, 55, "太刀",
		["快速攻击速度", "武器物理技能：MP-5%", "武器魔法技能：MP+5%"],
		[["物理攻击力", "+412"], ["魔法攻击力", "+380"], ["独立攻击力", "+96"],
		 ["力量", "+45"], ["智力", "+32"], ["攻击速度", "+8.0%"], ["命中率", "+2.0%"]],
		{"weight": 3.2, "value": 128000, "durability_now": 45, "durability": 45,
		 "desc": "刀身映出月光时，持刀人会短暂忘记自己的名字。"})
	d["weapon_off"] = _equip("eq_weapon_off_01", "影袭短匕", "weapon_off", icon_weapon(35), 3, 50, "匕首",
		["快速攻击速度", "背击时伤害 +8%"],
		[["物理攻击力", "+266"], ["魔法攻击力", "+210"], ["独立攻击力", "+72"],
		 ["力量", "+18"], ["攻击速度", "+3.0%"]],
		{"weight": 1.1, "value": 42000, "durability_now": 31, "durability": 34,
		 "desc": "刃口很短，适合贴到别人呼吸范围里再拔出来。"})
	d["head"] = _equip("eq_head_01", "苍狼头盔", "head", icon_armor(43), 4, 52, "轻甲",
		["物理防御力 +186", "被击时 2% 概率减少冷却"],
		[["物理防御力", "+186"], ["魔法防御力", "+104"], ["力量", "+20"], ["体力", "+26"],
		 ["HP 最大值", "+260"]],
		{"weight": 1.4, "value": 54000, "durability_now": 34, "durability": 36,
		 "desc": "盔沿有一道旧裂痕，像被什么东西从侧面咬过。"})
	d["shoulder"] = _equip("eq_shoulder_01", "星辉护肩", "shoulder", icon_armor(91), 4, 50, "轻甲",
		["物理防御力 +142", "硬直恢复 +40"],
		[["物理防御力", "+142"], ["魔法防御力", "+86"], ["力量", "+18"], ["体力", "+22"],
		 ["回避率", "+1.0%"]],
		{"weight": 1.6, "value": 46000, "durability_now": 32, "durability": 32,
		 "desc": "缝在肩甲内侧的星砂，会在夜里发很淡的光。"})
	d["coat"] = _equip("eq_coat_01", "苍龙战衣", "coat", icon_armor(55), 4, 52, "轻甲",
		["物理防御力 +318", "被击时 3% 概率生成护盾"],
		[["物理防御力", "+318"], ["魔法防御力", "+196"], ["力量", "+26"], ["体力", "+34"],
		 ["HP 最大值", "+420"], ["施放速度", "+2.0%"]],
		{"weight": 4.8, "value": 86000, "durability_now": 39, "durability": 40,
		 "desc": "甲片上的龙纹不是装饰，是龙在睡觉。"})
	d["pants"] = _equip("eq_pants_01", "影舞长裤", "pants", icon_armor(78), 3, 48, "皮甲",
		["物理防御力 +206", "移动速度 +1.5%"],
		[["物理防御力", "+206"], ["魔法防御力", "+124"], ["力量", "+16"], ["体力", "+18"],
		 ["移动速度", "+1.5%"]],
		{"weight": 3.1, "value": 32000, "durability_now": 28, "durability": 36,
		 "desc": "裤脚裁得很短，为了在屋顶上跑的时候不绊脚。"})
	d["belt"] = _equip("eq_belt_01", "玄铁腰带", "belt", icon_armor(67), 3, 45, "重甲",
		["物理防御力 +118", "物品栏重量 +3kg"],
		[["物理防御力", "+118"], ["魔法防御力", "+62"], ["力量", "+14"], ["体力", "+20"],
		 ["物品栏重量", "+3kg"]],
		{"weight": 1.2, "value": 21000, "durability_now": 30, "durability": 30,
		 "desc": "扣环是旧的，带身换过三次。"})
	d["shoes"] = _equip("eq_shoes_01", "疾风战靴", "shoes", icon_armor(25), 4, 50, "皮甲",
		["移动速度 +4.5%", "跳跃力 +18"],
		[["物理防御力", "+96"], ["魔法防御力", "+58"], ["力量", "+10"], ["体力", "+12"],
		 ["移动速度", "+4.5%"], ["跳跃力", "+18"]],
		{"weight": 1.9, "value": 38000, "durability_now": 26, "durability": 30,
		 "desc": "鞋底刻着一道风纹，走起来有很轻的哨声。"})
	d["necklace"] = _equip("eq_neck_01", "龙牙项链", "necklace", icon_acc(34), 4, 50, "项链",
		["魔法防御力 +86", "所有属性强化 +2"],
		[["魔法防御力", "+86"], ["智力", "+22"], ["精神", "+18"], ["所有属性强化", "+2"],
		 ["暗属性抗性", "+6"]],
		{"weight": 0.3, "value": 52000, "durability_now": 18, "durability": 18,
		 "desc": "牙根还带着一点体温，像刚从谁嘴里拔下来。"})
	d["bracer"] = _equip("eq_bracer_01", "赤铜护腕", "bracer", icon_armor(110), 3, 48, "轻甲",
		["物理防御力 +88", "攻击速度 +1.5%"],
		[["物理防御力", "+88"], ["魔法防御力", "+44"], ["力量", "+12"], ["体力", "+10"],
		 ["攻击速度", "+1.5%"]],
		{"weight": 0.7, "value": 24000, "durability_now": 22, "durability": 24,
		 "desc": "护腕内侧刻着前任主人的名字，被磨得只剩一半。"})
	d["ring1"] = _equip("eq_ring_01", "暗影之戒", "ring1", icon_acc(12), 4, 50, "戒指",
		["魔法防御力 +52", "暗属性强化 +4"],
		[["魔法防御力", "+52"], ["智力", "+18"], ["暗属性强化", "+4"], ["暗属性抗性", "+10"]],
		{"weight": 0.1, "value": 44000, "durability_now": 20, "durability": 20,
		 "desc": "戒面像一小块被按住的黑夜。"})
	d["ring2"] = _equip("eq_ring_02", "元素之戒", "ring2", icon_acc(78), 4, 52, "戒指",
		["魔法防御力 +58", "所有属性强化 +3"],
		[["魔法防御力", "+58"], ["力量", "+14"], ["智力", "+14"], ["所有属性强化", "+3"]],
		{"weight": 0.1, "value": 48000, "durability_now": 20, "durability": 20,
		 "desc": "四种元素在同一个环里轮流值夜。"})
	d["earring"] = _equip("eq_earring_01", "星辰耳坠", "earring", icon_acc(90), 5, 55, "耳环",
		["魔法防御力 +96", "技能攻击力 +3%"],
		[["魔法防御力", "+96"], ["智力", "+20"], ["精神", "+18"], ["所有属性强化", "+4"],
		 ["技能攻击力", "+3.0%"]],
		{"weight": 0.1, "value": 128000, "durability_now": 18, "durability": 18,
		 "desc": "耳坠里封着一小片夜空，靠近时能听见很远的回声。"})
	return d


# ---------------------------------------------------------------------------
# 角色属性（左侧「属性」抽屉）
# ---------------------------------------------------------------------------

static func character_attributes() -> Array:
	return [
		{"section": "基础", "rows": [
			["力量", "76"], ["智力", "62"], ["体力", "88"], ["精神", "54"], ["敏捷", "75"],
		]},
		{"section": "战斗", "rows": [
			["物理攻击", "1,246"], ["魔法攻击", "980"], ["独立攻击", "412"],
			["物理防御", "3,820"], ["魔法防御", "2,940"],
			["暴击率", "12.5%"], ["暴击伤害", "61.5%"],
			["攻击速度", "2.5%"], ["移动速度", "4.5%"], ["施放速度", "2.0%"],
			["命中率", "12.5%"], ["回避率", "3.0%"],
		]},
		{"section": "属性强化", "rows": [
			["火属性", "12"], ["冰属性", "8"], ["光属性", "4"], ["暗属性", "18"],
			["所有属性", "3"],
		]},
		{"section": "其他", "rows": [
			["抗魔值", "92"], ["冒险团等级", "Lv.7"], ["金币获取", "+5.0%"],
			["物品栏重量", "27.7 / 50.0 kg"],
		]},
	]


# ---------------------------------------------------------------------------
# 常用材料（不占物品栏，数量独立累加）
# ---------------------------------------------------------------------------

static func common_materials() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	out.append(_mat("cm_colorless", "无色小晶块", icon_mat(11), 4, 12800,
		{"desc": "最常用的技能材料。获得后直接累加，不占物品栏。", "value": 18}))
	out.append(_mat("cm_red", "红色小晶块", icon_mat(12), 3, 4200,
		{"desc": "火属性技能与部分装备制作材料。", "value": 22}))
	out.append(_mat("cm_blue", "蓝色小晶块", icon_mat(14), 3, 3860,
		{"desc": "冰属性技能与部分装备制作材料。", "value": 22}))
	out.append(_mat("cm_black", "黑色小晶块", icon_mat(20), 3, 2740,
		{"desc": "暗属性技能与部分装备制作材料。", "value": 26}))
	out.append(_mat("cm_white", "白色小晶块", icon_mat(24), 3, 1980,
		{"desc": "光属性技能与部分装备制作材料。", "value": 26}))
	out.append(_mat("cm_furnace", "炉岩炭", icon_mat(28), 2, 960,
		{"desc": "强化与锻造的基础材料。", "value": 34}))
	out.append(_mat("cm_contradiction", "矛盾的结晶体", icon_mat(30), 4, 312,
		{"desc": "高阶装备制作材料，掉落时会有特殊光效。", "value": 860}))
	out.append(_mat("cm_epic_soul", "史诗灵魂", icon_mat(4), 5, 46,
		{"desc": "分解史诗装备获得，用于跨界与制作。", "value": 2400}))
	out.append(_mat("cm_legend_soul", "传说灵魂", icon_mat(6), 4, 18,
		{"desc": "分解传说装备获得。", "value": 1800}))
	out.append(_mat("cm_golden", "金绿柱石", icon_mat(8), 3, 720,
		{"desc": "版本常用兑换材料。", "value": 120}))
	out.append(_mat("cm_crystal", "次元水晶", icon_mat(7), 4, 88,
		{"desc": "次元裂缝相关材料。", "value": 520}))
	out.append(_mat("cm_seal", "耀眼的记忆碎片", icon_mat(10), 3, 156,
		{"desc": "用于兑换部分固有史诗。", "value": 300}))
	return out


# ---------------------------------------------------------------------------
# 背包（物品栏）
# ---------------------------------------------------------------------------

static func inventory_items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	var eq := equipment()
	# 备用武器：让格子看起来像真的在玩
	out.append(_equip("eq_weapon_02", "裂空巨剑", "weapon", icon_weapon(33), 4, 55, "巨剑",
		["缓慢攻击速度", "武器物理技能：MP+10%"],
		[["物理攻击力", "+536"], ["魔法攻击力", "+402"], ["独立攻击力", "+110"],
		 ["力量", "+52"], ["命中率", "-1.0%"]],
		{"weight": 7.4, "value": 96000, "durability_now": 41, "durability": 45,
		 "desc": "挥动时空气会先裂开，声音后到。"}))
	out.append(_equip("eq_weapon_03", "霜寒短剑", "weapon", icon_weapon(35), 3, 50, "短剑",
		["快速攻击速度", "冰属性攻击"],
		[["物理攻击力", "+318"], ["魔法攻击力", "+402"], ["独立攻击力", "+88"],
		 ["智力", "+38"], ["冰属性强化", "+5"]],
		{"weight": 2.4, "value": 72000, "durability_now": 33, "durability": 38,
		 "desc": "剑鞘内侧结着永远化不掉的霜。"}))
	out.append(_equip("eq_weapon_04", "赤焰光剑", "weapon", icon_weapon(34), 5, 60, "光剑",
		["快速攻击速度", "火属性攻击", "光剑精通"],
		[["物理攻击力", "+468"], ["魔法攻击力", "+446"], ["独立攻击力", "+128"],
		 ["力量", "+48"], ["火属性强化", "+7"], ["攻击速度", "+6.0%"]],
		{"weight": 2.8, "value": 188000, "durability_now": 50, "durability": 50,
		 "desc": "剑刃没有实体，只有一段被烧红的空气。"}))
	out.append(_equip("eq_weapon_07", "星陨·终焉", "weapon_main", icon_weapon(128), 6, 65, "巨剑",
		["缓慢攻击速度", "技能攻击力 +8%", "攻击时 5% 概率召唤星落"],
		[["物理攻击力", "+812"], ["魔法攻击力", "+688"], ["独立攻击力", "+220"],
		 ["力量", "+88"], ["所有属性强化", "+12"], ["技能攻击力", "+8.0%"]],
		{"weight": 8.6, "value": 999000, "durability_now": 60, "durability": 60,
		 "desc": "剑落下的地方，夜空会短暂地缺一块。"}))
	out.append(_equip("eq_coat_02", "苍龙战衣（封装）", "coat", icon_armor(55), 4, 52, "轻甲",
		["物理防御力 +318"], [["物理防御力", "+318"], ["力量", "+26"], ["体力", "+34"]],
		{"weight": 4.8, "value": 86000, "durability_now": 40, "durability": 40,
		 "desc": "同一件衣服的第二件，准备拿去强化。"}))
	out.append(_equip("eq_shoulder_02", "旧皮护肩", "shoulder", icon_armor(12), 1, 20, "皮甲",
		["物理防御力 +32"], [["物理防御力", "+32"], ["体力", "+6"]],
		{"weight": 0.9, "value": 1200, "durability_now": 12, "durability": 20,
		 "desc": "边缘磨得发亮，还能再用一阵。"}))

	out.append(_equip("eq_weapon_05", "训练用长弓", "weapon_main", icon_weapon(46), 3, 45, "长弓",
		["普通攻击速度", "需要弓精通"],
		[["物理攻击力", "+302"], ["魔法攻击力", "+188"], ["独立攻击力", "+64"],
		 ["敏捷", "+28"], ["命中率", "+1.5%"]],
		{"weight": 2.0, "value": 28000, "durability_now": 28, "durability": 32,
		 "desc": "弓臂上还留着训练场的编号。"}))
	out.append(_equip("eq_weapon_06", "学徒法杖", "weapon_main", icon_weapon(60), 3, 45, "法杖",
		["缓慢攻击速度", "魔法技能：MP+5%"],
		[["魔法攻击力", "+336"], ["独立攻击力", "+82"], ["智力", "+32"],
		 ["施放速度", "+4.0%"], ["所有属性强化", "+2"]],
		{"weight": 2.6, "value": 31000, "durability_now": 30, "durability": 34,
		 "desc": "杖头的水晶是后来配的，颜色不太对。"}))
	out.append(_equip("eq_head_02", "旧皮帽", "head", icon_armor(12), 2, 30, "皮甲",
		["物理防御力 +42"], [["物理防御力", "+42"], ["体力", "+8"]],
		{"weight": 0.6, "value": 3200, "durability_now": 18, "durability": 24,
		 "desc": "帽檐被雨泡得发软，但还能挡一挡树枝。"}))
	out.append(_equip("eq_shoes_02", "旅人短靴", "shoes", icon_armor(25), 2, 28, "皮甲",
		["移动速度 +2.0%"], [["物理防御力", "+28"], ["移动速度", "+2.0%"]],
		{"weight": 0.8, "value": 2600, "durability_now": 15, "durability": 22,
		 "desc": "鞋底钉着防滑的铁片，走石板路会响。"}))
	out.append(_equip("eq_bracer_02", "青铜护腕", "bracer", icon_armor(110), 2, 26, "重甲",
		["物理防御力 +36"], [["物理防御力", "+36"], ["力量", "+6"]],
		{"weight": 1.0, "value": 1800, "durability_now": 20, "durability": 22,
		 "desc": "铜绿从铆钉缝里渗出来。"}))
	out.append(_equip("eq_neck_02", "褪色护符", "necklace", icon_acc(34), 2, 25, "项链",
		["魔法防御力 +24"], [["魔法防御力", "+24"], ["精神", "+6"]],
		{"weight": 0.2, "value": 2200, "durability_now": 12, "durability": 18,
		 "desc": "绳子换过很多次，坠子一直没换。"}))
	out.append(_equip("eq_ring_03", "铜制指环", "ring1", icon_acc(12), 1, 20, "戒指",
		["命中率 +0.5%"], [["命中率", "+0.5%"], ["力量", "+3"]],
		{"weight": 0.1, "value": 800, "durability_now": 10, "durability": 16,
		 "desc": "内圈刻着一个已经磨平的字母。"}))
	out.append(_equip("eq_ear_02", "兽牙耳饰", "earring", icon_acc(90), 2, 24, "耳环",
		["物理攻击力 +18"], [["物理攻击力", "+18"], ["敏捷", "+5"]],
		{"weight": 0.1, "value": 1600, "durability_now": 9, "durability": 14,
		 "desc": "兽牙尖端还带着一点暗色。"}))
	out.append(_stack("use_hp_01", "新手 HP 药剂", icon_stack(6), 0, 12,
		{"effect": "恢复 120 点 HP。冷却 1 秒。", "value": 20, "weight": 0.02,
		 "tags": ["立即恢复"], "desc": "味道像稀释过的草莓糖浆。"}))
	out.append(_stack("use_mp_01", "新手 MP 药剂", icon_stack(8), 0, 8,
		{"effect": "恢复 90 点 MP。冷却 1 秒。", "value": 24, "weight": 0.02,
		 "tags": ["立即恢复"], "desc": "喝下去喉咙会凉一下。"}))
	out.append(_stack("use_hp_02", "高级生命药剂", icon_stack(10), 1, 5,
		{"effect": "恢复 30% 最大 HP。冷却 8 秒。", "value": 180, "weight": 0.03,
		 "tags": ["百分比恢复"], "desc": "瓶口封着红色的蜡，像一小管备用血。"}))
	out.append(_stack("use_mp_02", "精神刺激灵药", icon_stack(9), 2, 3,
		{"effect": "30 秒内施放速度 +15%，MP 消耗 +10%。", "value": 420, "weight": 0.04,
		 "tags": ["增益", "持续 30 秒"], "desc": "副作用是耳朵会听见自己的心跳。"}))
	out.append(_stack("use_fatigue", "抗疲劳秘药", icon_stack(11), 2, 2,
		{"effect": "恢复 30 点疲劳值。每日最多使用 3 次。", "value": 900, "weight": 0.05,
		 "tags": ["每日限用"], "desc": "喝起来像 melted 的薄荷糖。"}))
	out.append(_stack("use_growth", "成长胶囊", icon_stack(12), 2, 4,
		{"effect": "50 级以下角色获得少量经验。", "value": 300, "weight": 0.01,
		 "tags": ["经验值"], "desc": "胶囊里那点液体永远在慢慢旋。"}))
	out.append(_stack("use_revive", "复活币", icon_stack(5), 4, 3,
		{"effect": "在副本中死亡后原地复活，恢复 30% HP/MP。", "value": 0, "weight": 0.0,
		 "tags": ["账号绑定"], "bind": "账号绑定", "desc": "硬币正面刻着「再来一次」。"}))
	out.append(_stack("use_charm", "装备强化保护券", icon_mat(21), 4, 1,
		{"effect": "强化失败时装备不破碎，但强化等级 -1。",
		 "value": 12000, "weight": 0.0, "tags": ["强化"], "desc": "一叠薄薄的符纸，摸起来有点潮。"}))
	out.append(_stack("use_amp", "纯净的增幅书", icon_mat(20), 5, 1,
		{"effect": "为装备附加异次元属性。", "value": 88000, "weight": 0.1,
		 "tags": ["增幅"], "desc": "书页是空白的，但翻动时能听见字。"}))

	out.append(_mat("mat_cube_white", "无色小晶块", icon_mat(10), 1, 1246,
		{"weight": 0.001, "value": 8, "desc": "最基础的晶块，所有技能都会吃掉一点。"}))
	out.append(_mat("mat_cube_red", "红色小晶块", icon_mat(11), 2, 837,
		{"weight": 0.001, "value": 18, "desc": "火属性技能的燃料，握在手里是温的。"}))
	out.append(_mat("mat_cube_blue", "蓝色小晶块", icon_mat(12), 2, 592,
		{"weight": 0.001, "value": 18, "desc": "冰属性技能的燃料，表面永远有一层水雾。"}))
	out.append(_mat("mat_cube_purple", "紫色小晶块", icon_mat(14), 3, 210,
		{"weight": 0.001, "value": 46, "desc": "暗属性技能的燃料，看久了会觉得它在呼吸。"}))
	out.append(_mat("mat_tera", "泰拉石", icon_mat(0), 3, 37,
		{"weight": 0.05, "value": 320, "desc": "泰拉石金库的钥匙材料，硬得离谱。"}))
	out.append(_mat("mat_furnace", "炉岩炭", icon_mat(4), 1, 64,
		{"weight": 0.02, "value": 60, "desc": "烧起来没有烟，只有一层蓝火。"}))
	out.append(_mat("mat_pearl", "耀眼的珍珠", icon_mat(6), 3, 9,
		{"weight": 0.01, "value": 1400, "desc": "从深海贝里取出来的，光很软。"}))
	out.append(_mat("mat_hide", "哥布林手骨", icon_mat(7), 0, 23,
		{"weight": 0.03, "value": 22, "desc": "哥布林身上最硬的一块，也是最好卖的一块。"}))
	out.append(_mat("mat_crystal", "下级元素结晶", icon_mat(8), 2, 48,
		{"weight": 0.01, "value": 90, "desc": "元素在结晶里睡成一圈一圈的纹。"}))
	out.append(_mat("mat_crystal_hi", "上级元素结晶", icon_mat(30), 3, 12,
		{"weight": 0.01, "value": 420, "desc": "纯度更高，靠近时头发会立起来。"}))
	out.append(_mat("mat_orb", "混沌魔石碎片", icon_mat(28), 4, 6,
		{"weight": 0.1, "value": 2600, "desc": "从混沌魔石上崩下来的一角，还在轻微震动。"}))
	out.append(_mat("mat_soul", "史诗灵魂", icon_mat(30), 5, 2,
		{"weight": 0.0, "value": 0, "tags": ["账号绑定"], "bind": "账号绑定",
		 "desc": "一件史诗装备被分解后，留下的那一点“不甘心”。"}))

	out.append(_mat("quest_note", "冒险家笔记", icon_mat(20), 0, 1,
		{"type": "任务物品", "weight": 0.0, "value": 0, "bind": "不可交易",
		 "desc": "封面写着你的名字，但笔迹不是你的。"}))
	out.append(_mat("quest_letter", "神秘信件", icon_mat(23), 2, 1,
		{"type": "任务物品", "weight": 0.0, "value": 0, "bind": "不可交易",
		 "desc": "封口处压着一枚没有图案的火漆。"}))
	out.append(_mat("quest_map", "破损的地图", icon_mat(21), 1, 1,
		{"type": "任务物品", "weight": 0.0, "value": 0, "bind": "不可交易",
		 "desc": "只剩半张，边缘被烧过。"}))
	out.append(_mat("quest_kazan", "卡赞的诅咒", icon_mat(24), 5, 1,
		{"type": "任务物品", "weight": 0.2, "value": 0, "bind": "不可交易",
		 "desc": "别打开。真的。"}))
	out.append(_mat("prof_alchemy", "炼金术士的笔记", icon_mat(20), 2, 1,
		{"type": "副职业", "weight": 0.3, "value": 1200, "bind": "不可交易",
		 "desc": "记着十七种把失败品变成另一种失败品的方法。"}))
	out.append(_mat("prof_enchant", "附魔宝珠", icon_mat(32), 3, 4,
		{"type": "副职业", "weight": 0.0, "value": 2600,
		 "desc": "珠子里封着一小段咒文，贴到装备上就会醒。"}))

	return out


# ---------------------------------------------------------------------------
# 金库
# ---------------------------------------------------------------------------

static func warehouse_items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	# 一排备用装备
	out.append(_equip("wh_weapon_01", "古旧的木制东方棍", "weapon", icon_weapon(60), 0, 3, "东方棍",
		["快速攻击速度", "武器物理技能：MP-5%"],
		[["物理攻击力", "+29"], ["魔法攻击力", "+30"], ["独立攻击力", "+28"],
		 ["物理防御力", "+32"], ["回避率", "+3.0%"], ["命中率", "+2.0%"]],
		{"weight": 2.3, "value": 302, "durability_now": 39, "durability": 39, "job": "格斗家",
		 "desc": "木头上有一层被手汗磨出来的包浆。"}))
	out.append(_equip("wh_weapon_02", "破裂的木制东方棍", "weapon", icon_weapon(60), 0, 3, "东方棍",
		["快速攻击速度", "武器物理技能：MP-5%"],
		[["物理攻击力", "+11"], ["魔法攻击力", "+15"], ["独立攻击力", "+20"],
		 ["物理防御力", "+10"], ["回避率", "+3.0%"], ["命中率", "+2.0%"]],
		{"weight": 2.3, "value": 92, "durability_now": 36, "durability": 39, "job": "格斗家",
		 "desc": "再挨一下就要从中间断开了。"}))
	out.append(_equip("wh_weapon_03", "暗影之触", "weapon", icon_weapon(88), 4, 55, "爪",
		["快速攻击速度", "暗属性攻击"],
		[["物理攻击力", "+388"], ["魔法攻击力", "+352"], ["独立攻击力", "+104"],
		 ["力量", "+36"], ["暗属性强化", "+5"]],
		{"weight": 2.6, "value": 74000, "durability_now": 42, "durability": 42, "job": "格斗家",
		 "desc": "指套内侧有细密的倒刺。"}))
	out.append(_equip("wh_weapon_04", "星界法杖", "weapon", icon_weapon(120), 4, 58, "法杖",
		["缓慢攻击速度", "所有属性强化 +4"],
		[["魔法攻击力", "+502"], ["独立攻击力", "+118"], ["智力", "+64"], ["精神", "+42"],
		 ["施放速度", "+4.0%"]],
		{"weight": 3.6, "value": 92000, "durability_now": 45, "durability": 45, "job": "魔法师",
		 "desc": "杖头那颗星是后来装上去的，原装的那颗掉进了海里。"}))
	out.append(_equip("wh_weapon_05", "海妖之歌", "weapon", icon_weapon(128), 5, 60, "魔杖",
		["快速攻击速度", "水属性攻击"],
		[["魔法攻击力", "+548"], ["独立攻击力", "+132"], ["智力", "+72"],
		 ["水属性强化", "+7"], ["施放速度", "+6.0%"]],
		{"weight": 2.9, "value": 204000, "durability_now": 50, "durability": 50, "job": "魔法师",
		 "desc": "靠近耳边能听见潮声。别听太久。"}))
	out.append(_equip("wh_coat_01", "旅人的旧外套", "coat", icon_armor(43), 1, 25, "布甲",
		["物理防御力 +86"], [["物理防御力", "+86"], ["魔法防御力", "+54"], ["体力", "+8"]],
		{"weight": 1.8, "value": 2400, "durability_now": 18, "durability": 25,
		 "desc": "内衬缝着三个补丁，每个补丁都来自不同的地方。"}))
	out.append(_equip("wh_pants_01", "旅人的旧长裤", "pants", icon_armor(78), 1, 25, "布甲",
		["物理防御力 +62"], [["物理防御力", "+62"], ["魔法防御力", "+40"], ["体力", "+6"]],
		{"weight": 1.5, "value": 1800, "durability_now": 15, "durability": 25,
		 "desc": "膝盖处磨得发白。"}))
	out.append(_equip("wh_belt_01", "粗制皮带", "belt", icon_armor(67), 0, 10, "皮甲",
		["物理防御力 +18"], [["物理防御力", "+18"], ["体力", "+3"]],
		{"weight": 0.6, "value": 320, "durability_now": 16, "durability": 20,
		 "desc": "孔位是自己拿锥子扎的。"}))
	out.append(_equip("wh_shoes_01", "旅人的旧靴", "shoes", icon_armor(25), 1, 25, "皮甲",
		["移动速度 +2.0%"], [["物理防御力", "+42"], ["移动速度", "+2.0%"]],
		{"weight": 1.1, "value": 1600, "durability_now": 14, "durability": 25,
		 "desc": "鞋底钉过两次，钉子是从另一双鞋上拆的。"}))
	out.append(_equip("wh_neck_01", "褪色的护符", "necklace", icon_acc(34), 2, 30, "项链",
		["魔法防御力 +32"], [["魔法防御力", "+32"], ["精神", "+10"]],
		{"weight": 0.2, "value": 3400, "durability_now": 12, "durability": 18,
		 "desc": "符纸上的字已经看不清了，但还留着一点暖意。"}))
	out.append(_equip("wh_brace_01", "铜制手环", "bracelet", icon_acc(56), 1, 20, "手镯",
		["魔法防御力 +18"], [["魔法防御力", "+18"], ["力量", "+4"]],
		{"weight": 0.3, "value": 900, "durability_now": 15, "durability": 18,
		 "desc": "内侧刻着一个已经停产的工坊标记。"}))
	out.append(_equip("wh_ring_01", "生锈的指环", "ring1", icon_acc(12), 0, 12, "戒指",
		["魔法防御力 +8"], [["魔法防御力", "+8"]],
		{"weight": 0.1, "value": 120, "durability_now": 10, "durability": 12,
		 "desc": "镀层掉光了，露出底下的铁。"}))

	# 堆叠材料：把背包里没有的也补进来
	out.append(_mat("wh_mat_gold", "金锭", icon_mat(5), 2, 18,
		{"weight": 0.1, "value": 600, "desc": "沉甸甸的，边缘还留着模具的毛刺。"}))
	out.append(_mat("wh_mat_plate", "上级强化钢板", icon_mat(4), 2, 26,
		{"weight": 0.4, "value": 240, "desc": "强化装备时垫在底下，能听见很闷的一声。"}))
	out.append(_mat("wh_mat_pearl2", "深海珍珠", icon_mat(6), 3, 14,
		{"weight": 0.01, "value": 1600, "desc": "在暗处会自己亮一小会儿。"}))
	out.append(_mat("wh_mat_blue", "蓝色小晶块", icon_mat(12), 2, 780,
		{"weight": 0.001, "value": 18, "desc": "冰属性技能的燃料，表面永远有一层水雾。"}))
	out.append(_mat("wh_mat_red", "红色小晶块", icon_mat(11), 2, 650,
		{"weight": 0.001, "value": 18, "desc": "火属性技能的燃料，握在手里是温的。"}))
	out.append(_mat("wh_mat_purple", "紫色小晶块", icon_mat(14), 3, 320,
		{"weight": 0.001, "value": 46, "desc": "暗属性技能的燃料，看久了会觉得它在呼吸。"}))
	out.append(_mat("wh_mat_white", "无色小晶块", icon_mat(10), 1, 2400,
		{"weight": 0.001, "value": 8, "desc": "最基础的晶块，所有技能都会吃掉一点。"}))
	out.append(_mat("wh_mat_tera", "泰拉石", icon_mat(0), 3, 88,
		{"weight": 0.05, "value": 320, "desc": "泰拉石金库的钥匙材料，硬得离谱。"}))
	out.append(_mat("wh_mat_furnace", "炉岩炭", icon_mat(4), 1, 120,
		{"weight": 0.02, "value": 60, "desc": "烧起来没有烟，只有一层蓝火。"}))
	out.append(_mat("wh_mat_hide", "哥布林手骨", icon_mat(7), 0, 56,
		{"weight": 0.03, "value": 22, "desc": "哥布林身上最硬的一块，也是最好卖的一块。"}))
	out.append(_mat("wh_mat_crystal", "下级元素结晶", icon_mat(8), 2, 96,
		{"weight": 0.01, "value": 90, "desc": "元素在结晶里睡成一圈一圈的纹。"}))
	out.append(_mat("wh_mat_crystal_hi", "上级元素结晶", icon_mat(30), 3, 31,
		{"weight": 0.01, "value": 420, "desc": "纯度更高，靠近时头发会立起来。"}))
	out.append(_mat("wh_mat_orb", "混沌魔石碎片", icon_mat(28), 4, 11,
		{"weight": 0.1, "value": 2600, "desc": "从混沌魔石上崩下来的一角，还在轻微震动。"}))
	out.append(_mat("wh_mat_soul", "史诗灵魂", icon_mat(30), 5, 5,
		{"weight": 0.0, "value": 0, "tags": ["账号绑定"], "bind": "账号绑定",
		 "desc": "一件史诗装备被分解后，留下的那一点“不甘心”。"}))
	out.append(_mat("wh_mat_scroll", "附魔卷轴", icon_mat(21), 3, 7,
		{"type": "附魔", "weight": 0.0, "value": 1800, "desc": "卷轴边缘有裁切不齐的毛边。"}))
	out.append(_mat("wh_mat_scroll2", "远古记忆卷轴", icon_mat(23), 4, 3,
		{"type": "附魔", "weight": 0.0, "value": 8600, "desc": "打开时会有很淡的墨味。"}))
	out.append(_mat("wh_prof_doll", "人偶师的线", icon_mat(31), 2, 9,
		{"type": "副职业", "weight": 0.0, "value": 700, "desc": "线头会自己找地方缠上。"}))
	out.append(_mat("wh_prof_doll2", "人偶师的针", icon_mat(2), 3, 4,
		{"type": "副职业", "weight": 0.0, "value": 2200, "desc": "针尖有一点永远擦不掉的暗色。"}))
	out.append(_mat("wh_quest_1", "罗特斯的触须", icon_mat(34), 4, 1,
		{"type": "任务物品", "weight": 0.2, "value": 0, "bind": "不可交易",
		 "desc": "还在动。放进金库之后也还在动。"}))
	out.append(_mat("wh_quest_2", "天界通行证", icon_mat(20), 3, 1,
		{"type": "任务物品", "weight": 0.0, "value": 0, "bind": "不可交易",
		 "desc": "照片那一栏是空白的。"}))
	out.append(_mat("wh_quest_3", "被污染的水晶", icon_mat(9), 2, 1,
		{"type": "任务物品", "weight": 0.1, "value": 0, "bind": "不可交易",
		 "desc": "水晶内部有一团不规则的黑色。"}))

	# 消耗品
	out.append(_stack("wh_use_hp", "新手 HP 药剂", icon_stack(6), 0, 46,
		{"effect": "恢复 120 点 HP。冷却 1 秒。", "value": 20, "weight": 0.02,
		 "tags": ["立即恢复"], "desc": "味道像稀释过的草莓糖浆。"}))
	out.append(_stack("wh_use_mp", "新手 MP 药剂", icon_stack(8), 0, 38,
		{"effect": "恢复 90 点 MP。冷却 1 秒。", "value": 24, "weight": 0.02,
		 "tags": ["立即恢复"], "desc": "喝下去喉咙会凉一下。"}))
	out.append(_stack("wh_use_hp2", "高级生命药剂", icon_stack(10), 1, 12,
		{"effect": "恢复 30% 最大 HP。冷却 8 秒。", "value": 180, "weight": 0.03,
		 "tags": ["百分比恢复"], "desc": "瓶口封着红色的蜡，像一小管备用血。"}))
	out.append(_stack("wh_use_growth", "成长胶囊", icon_stack(12), 2, 8,
		{"effect": "50 级以下角色获得少量经验。", "value": 300, "weight": 0.01,
		 "tags": ["经验值"], "desc": "胶囊里那点液体永远在慢慢旋。"}))
	out.append(_stack("wh_use_charm", "装备强化保护券", icon_mat(21), 4, 3,
		{"effect": "强化失败时装备不破碎，但强化等级 -1。", "value": 12000, "weight": 0.0,
		 "tags": ["强化"], "desc": "一叠薄薄的符纸，摸起来有点潮。"}))
	out.append(_stack("wh_use_amp", "纯净的增幅书", icon_mat(20), 5, 1,
		{"effect": "为装备附加异次元属性。", "value": 88000, "weight": 0.1,
		 "tags": ["增幅"], "desc": "书页是空白的，但翻动时能听见字。"}))

	# 时装
	out.append(_avatar("av_hair", "天空套·头发", icon_avatar(3), 5,
		{"desc": "发梢会随着风慢慢散开，像被水拖着。"}))
	out.append(_avatar("av_coat", "天空套·上衣", icon_avatar(5), 5,
		{"desc": "布料上绣着一整片夜空，星星的位置每天都在变。"}))
	out.append(_avatar("av_pants", "天空套·下装", icon_avatar(7), 4,
		{"desc": "裤脚有很淡的云纹。"}))
	out.append(_stack("av_coupon", "稀有装扮兑换券", icon_stack(20), 4, 2,
		{"category": "avatar", "type": "兑换券", "value": 0, "weight": 0.0,
		 "tags": ["账号绑定"], "bind": "账号绑定", "desc": "能在 NPC 那里换一件稀有装扮。"}))
	return out


static func _avatar(id: String, name: String, icon: Array, rarity: int, opts := {}) -> ItemDef:
	var it := _base(id, name, "avatar", icon)
	it.rarity = rarity
	it.item_type = "时装"
	it.bind_state = "已绑定"
	it.tags = PackedStringArray(["高级装扮", "不可交易"])
	it.description = str(opts.get("desc", ""))
	return it
