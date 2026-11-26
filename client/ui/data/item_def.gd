## 一件物品的纯数据描述。
##
## 现阶段是 mock：图标用 sf85 客户端里真实存在的 `sprite/item/icon*.img` 帧，
## 名字/数值/描述是编的。等真实道具表接进来，只要把 ItemDB 换成读表，
## UI（UISlot / UITooltip / UIItemGrid）不用改。
class_name ItemDef
extends Resource

const RARITY_NAMES := ["普通", "高级", "稀有", "勇者", "神器", "史诗", "传说"]

@export_group("身份")
@export var item_id := ""
@export var item_name := ""
## equipment / consumable / material / profession / quest / avatar / pet
@export var category := "material"
## 装备槽位：weapon / title / coat / pants / shoes / belt / shoulder /
## necklace / bracelet / ring / support / magic_stone
@export var slot := ""
@export var item_type := "材料"
@export var rarity := 0
@export var level := 0
@export var required_job := ""
## 获取顺序（mock 用；真实数据可换成时间戳）
@export var acquired := 0

@export_group("图标")
@export var icon_img := "sprite/item/iconmaterial.img"
@export var icon_frame := 0

@export_group("堆叠与重量")
@export var count := 1
@export var max_stack := 1
@export var weight := 0.0
@export var value := 0

@export_group("耐久")
@export var durability := 0
@export var durability_max := 0

@export_group("说明")
## [{label: "物理攻击力", value: "+412", tone: "normal"}]
@export var stats: Array = []
## 类型行下面的补充，比如「快速攻击速度」「武器物理技能：MP-5%」
@export var tags: PackedStringArray = []
@export var description := ""
@export var effect := ""
@export var bind_state := "封装"


func is_equipment() -> bool:
	return category == "equipment"


func is_stackable() -> bool:
	return max_stack > 1


func rarity_name() -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]


func display_count() -> String:
	return str(count) if count > 1 else ""


func weight_text() -> String:
	return "%.1fkg" % weight if weight > 0.0 else ""


func value_text() -> String:
	return UIKit.fmt_int(value) + " 金币"


func add_stat(label: String, value: String, tone := "normal") -> ItemDef:
	stats.append({"label": label, "value": value, "tone": tone})
	return self


func with_count(n: int) -> ItemDef:
	var d := duplicate() as ItemDef
	d.count = n
	return d
