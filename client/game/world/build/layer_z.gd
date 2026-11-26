class_name LayerZ
extends RefCounted
## 世界装饰 [animation] 的固定图层 z 表。
##
## 约束（用户 2026-11-26 明确）：
## - 基础图层只用 [-100, 100] 内的小整数；100 个档位足够手工分配多层动画。
## - 不做归一化、不按房间高度/相机/角色位置算基础 z；每层一个手填常量。
## - 只有“临时图层提升”允许动态设到 actor-1，不参与基础层。
##
## 顺序（远 → 近）：
##   distantback < middleback < bottom < normal < closeback < close < front
## 2026-11-26 用户截图：closeback 的建筑要盖住 normal 的城门墙，所以把 closeback 提到
## normal 之上、close/front 之下（-35），仍在地砖 ±100 的小范围里。
## 字符串匹配必须精确，不能用 contains() 猜；未知层回退 normal。

const Z_MIN := -100
const Z_MAX := 100

const NAMES: PackedStringArray = [
	"distantback",
	"middleback",
	"closeback",
	"bottom",
	"normal",
	"close",
	"front",
]

const Z_BY_NAME := {
	"distantback": -70,
	"middleback": -65,
	"closeback": -35,
	"bottom": -50,
	"normal": -40,
	"close": -30,
	"front": 20,
}

const Z_DEFAULT := -40
## 临时图层提升的目标 z：手填的“最高基础层之上、actor 之下”档位，仍限制在 ±100 内。
const Z_RAISE := 95

## 非动画的基础层，也压在 [-100,100] 内；不要改成按房间高度缩放。
const Z_TILE := -50
const Z_TILE_EXT := -79
const Z_BG_FAR := -95
const Z_BG_NEAR := -90


static func of(layer: String) -> int:
	var key := layer.strip_edges().to_lower()
	if key.begins_with("[") and key.ends_with("]"):
		key = key.substr(1, key.length() - 2)
	if Z_BY_NAME.has(key):
		return int(Z_BY_NAME[key])
	return Z_DEFAULT


static func index_of(layer: String) -> int:
	var key := layer.strip_edges().to_lower()
	if key.begins_with("[") and key.ends_with("]"):
		key = key.substr(1, key.length() - 2)
	return NAMES.find(key)


static func name_at(index: int) -> String:
	if index < 0 or index >= NAMES.size():
		return ""
	return NAMES[index]
