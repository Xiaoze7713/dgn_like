# 02 · 职业体系（.chr / characteretc）

> 范围：职业数据怎么表达、转职怎么表达、成长曲线怎么算、属性从哪来。
> 数据源：`export/text/character/**`、`export/_meta/lst/character__character.lst`。
> 相邻文档：技能怎么接上职业 → `03-skill.md`；属性怎么进伤害公式 → `04-combat.md`；脚本层 → `09-script-mechanics.md`。

---

## 0. 一句话结论

职业在 PVF 里被拆成三层，**没有任何一处代码逻辑**：

1. **`.chr`**（13 个）= 一类角色的「等级 1 基础值 + 每级增量 + 转职分支表」；
2. **`character/characteretc/*.etc`**（13 个）= 该职业的「外围配置」：默认时装槽、脸部绘制偏移、武器子类型→动画索引、转职专属时装文件名；
3. **一份全局等级经验表 `character/exptable.tbl`**（115 级）+ **每个技能自己的等级表**（见 03）。

转职（growtype）不是一种「职业对象」，而是 **`.chr` 里 6 个并列的增量块 + 每个技能自己的 `[growtype maximum level]` 六元组**。这两处合起来才决定「谁能学什么」——这是复刻时最容易漏掉的机制。

---

## 1. 数据地图

```
character/character.lst          # 0..10 → .chr 路径（11 条）
character/swordman/swordman.chr         # 鬼剑士（含 6 个转职名）
character/swordman/atswordman.chr        # 决斗场版鬼剑士（另一套数值）
character/swordman/demonicswordman.chr   # 黑暗武士（与 demiclancer/ 下同名文件并存，待验证哪份生效）
character/fighter|gunner|mage|priest|thief/…
character/demoniclancer/demonicswordman.chr
character/exptable.tbl           # 1..115 级累计经验
character/pvppricetable.tbl      # 决斗场奖励表（本任务不展开）
character/characteretc/*.etc     # 每职业一份外围配置（13 份）
character/common/                # 全职业共用动画（站立/跑步/受伤）
```

`.chr` 之外的职业差异全部在 **技能表**（`skill/<职业>skill.lst` + `.skl`）里，所以「14 个职业树」实际是：

| 类型 | 职业枚举 | `.chr` |
|---|---|---|
| 主线 5 | swordman / fighter / gunner / mage / priest | ✅ |
| 主线 2（后加） | thief / demoniclancer | ✅ |
| 外传 3 | creatormage / demonicswordman / gunblader | ⚠️ 只有 `demonicswordman.chr`（creatormage、gunblader 走 etc + 独立技能表） |
| 决斗场镜像 5 | atswordman / atfighter / atgunner / atmage / atpriest | ✅ |
| 外传职业系统 | — | `character/expertjob.*` |

> 所以严格数是 **13 份 `.chr`**，`character.lst` 只登记了 11 条（不含 demonicswordman、gunblader）。

---

## 2. `.chr` 字段表

证据：`export/text/character/swordman/swordman.chr.txt`（全文 200 行左右）。
语法：`[字段]` 后跟一行数值；重复出现时导出器加后缀 `-1`、`-2`…**后缀顺序 = 出现顺序**，据此还原块归属。

### 2.1 头部（职业身份）

| 字段 | 含义 | 取值 | 必填 |
|---|---|---|---|
| `[job]` | 职业枚举 | 单个嵌套标签 `[swordman]`/`[fighter]`/…（与 `character.lst` 一致） | ✅ |
| `[growtype name]` | 6 个转职/觉醒名的显示串 | 6 个中文名，逗号无分隔连写 | ✅ |
| `[width]` | 碰撞体半宽/半高 | `40 10`（鬼剑士）；`30 x` 之类随职业变 | ✅ |
| `[initial value]` | 初始附加属性 | 空（占位） | ❌ |

### 2.2 基础属性（等级 1 的值）

| 字段 | 含义 | 示例（鬼剑士） | 单位/范围 | 必填 |
|---|---|---|---|---|
| `[HP MAX]` | 1 级最大 HP | `180.0` | 点 | ✅ |
| `[MP MAX]` | 1 级最大 MP | `140.0` | 点 | ✅ |
| `[physical attack]` | 物理攻击力 | `7.5` | 点 | ✅ |
| `[physical defense]` | 物理防御力 | `7.5` | 点 | ✅ |
| `[magical attack]` | 魔法攻击力 | `4.5` | 点 | ✅ |
| `[magical defense]` | 魔法防御力 | `4.5` | 点 | ✅ |
| `[dark resistance]` / `[light resistance]` | 暗/光抗性（另有 fire/water） | `20.0` / `-20.0` | **百分点，可负** | ✅ |
| `[inventory limit]` | 背包容量 | `248000.0` | 单位重量（见 §2.5） | ✅ |
| `[MP regen speed]` | MP 每秒回复 | `50.0` | 点/秒 | ✅ |
| `[move speed]` | 移动速度基准 | `1350.0` | 内部单位/秒（约 1.35 屏宽/s，见 §6） | ✅ |
| `[attack speed]` | 攻速基准 | `1150.0` | 同上 | ✅ |
| `[cast speed]` | 施放速度基准 | `1000.0` | 同上 | ✅ |
| `[hit recovery]` | 硬直恢复基准 | `600.0` | 同上 | ✅ |
| `[jump power]` | 跳跃初速 | `430.0` | 同位移单位 | ✅ |
| `[weight]` | 角色自重（被击退/浮空影响） | `68000.0` | **克(g)**，68000 = 68kg；与装备 `[weight]` 同单位 | ✅ |
| `[jump speed]` | 跳跃帧率系数 | `97` | 百分数 | ✅ |
| `[skill]` | **默认已学技能** | `181 2 182 2 184 1 …` | (技能 id, 等级) 对 | ❌ |

### 2.3 转职块（growtype / awakening）

`[growtype 1]` … `[growtype 6]`、`[awakening 1]`、`[awakening 2]`：每块内部只有**「每级增量」**，字段名与 §2.2 同名（导出时因重名变成 `[HP MAX]-1`、`[HP MAX]-2`…）。

| 字段 | 含义 | 鬼剑士 growtype1 值 | 必填 |
|---|---|---|---|
| `[HP MAX]-n` | 每级 HP 增量 | `45.0` | ✅ |
| `[MP MAX]-n` | 每级 MP 增量 | `25.0` | ✅ |
| `[physical attack]-n` … `[magical defense]-n` | 每级攻防增量 | `4.8 / 4.8 / 4.19 / 4.19` | ✅ |
| `[inventory limit]-n` | 每级容量增量 | `300.0` | ✅ |
| `[MP regen speed]-n` | 每级 MP 回蓝增量 | `2.5` | ✅ |
| `[hit recovery]-n` | 每级硬直增量 | `1.5` | ✅ |
| `[skill]-n` | **转职时自动获得的技能** | `27 1 33 1 37 1 8 1 …` | ❌ |
| `[module damage rate]-n` | **模式伤害倍率序列**（官方注释：旧样例前三列为 PVP／战场／混沌，真实文件可出现第 4 列） | `0.95 1.0 1.0 0.95` | ✅ |
| `[awakening name]` | 觉醒名 | `極詣·劍魂` | ❌ |
| `[awakening skill]` | 觉醒自动技能 | `91 1` | ❌ |

**关键机制 1：成长 = 基础 + 每级增量 × (等级−1)，按「当前 growtype 的块」取增量。**
不同转职的增量不同（鬼剑士 growtype1 每级 +45 HP，growtype2 每级 +50 HP），所以同一个 55 级角色，转职前后 HP 不一样。这是复刻时必须照抄的一点。

**关键机制 2：`[module damage rate]` 是「模式」伤害倍率序列，不是「攻击类型」倍率。**

官方标签注释（`export/_meta/tagdict.sqlite`，ext=`chr`，tag=`module damage rate`）原文：

> 角色或 growtype 在不同玩法模式下使用的伤害倍率序列。旧官方样例说明前三列为 PVP、战场、混沌模式；真实角色文件可出现第四列，因此写回或分析时必须保留目标文件的完整列数，不能按旧三列样例截断。省略或写 0 是否继承上级值，也应按具体版本验证。

所以鬼剑士基础块 `0.95 1.0 1.0 0.95`、growtype2 `0.7 1.0 1.1 0.7` 的含义是：**同一角色进不同玩法模式时乘不同倍率**（PVP 里剑魂比鬼剑士更吃亏：0.7 vs 0.95；混沌里则更强：1.1 vs 1.0）。

这一点与 `.atk [pvp]` 覆盖块、`.skl [pvp]` 分支是同一套「环境分档」设计的不同层：`.chr` 分**模式**、`.skl`/`.atk` 分**PVE/PVP**。复刻单机版可整体忽略，但结构要留。

> 第 4 列的模式名与「省略/写 0 是否继承」均**待验证**。

### 2.4 经验与等级上限

| 数据 | 路径 | 结构 | 值 |
|---|---|---|---|
| 升级经验 | `character/exptable.tbl` | 115 个 int32（标签流，无表头） | `[1..115]` 累计值；Lv1→2 = `1000`，Lv2→3 = `2653`…；尾部 `2000000000` 起为封顶占位 |
| 等级上限 | 由技能 `[maximum level]` 与 exptable 长度共同约束 | — | 本版本 115 |

> 注意 `exptable` 是**累计**还是**单级**：`[1000, 2653, 5543, 10575, …]` 增长平滑且末段 20 亿，判断为**单级所需**（Lv1 需 1000）。⚠️ 待验证。

### 2.5 单位换算（全局口径，复刻必须统一）

PVF 里没有「像素/秒」，用的是一套整数内部单位：

| 概念 | PVF 值示例 | 换算建议 |
|---|---|---|
| 位移 | `[move speed] 1350`、`[jump power] 430`、`.atk [push aside] 30` | 内部单位 ≈ 1/100 像素；`1350` ≈ 13.5 px/帧@60fps 起步值 |
| 时间 | `.skl [cool time] 6000`、`[static data]` | **毫秒** |
| 概率/百分比 | `[skill command advantage] 20 40`、抗性 `20.0` | 百分点 |
| 重量 | `[weight] 68000`（角色）、装备 `[weight] 2800` | **克**：角色 68kg、太刀 2.8kg（官方注释写「10g 单位」，但与装备重量交叉验证可确定为克，注释有误） |
| 坐标 | `.map [monster] … 895 286` | 像素（房间内绝对坐标），Y 向下 |

---

## 3. `characteretc/*.etc` 字段表

证据：`export/text/character/characteretc/swordman.etc.txt`、`default.etc.txt`。

结构：所有键都是 **「key + 一串 (值, 索引) 对」** 或 **「名字 + 10~11 个 id」**，靠 `[key value index]` / `[key value string]` / `[equipment index]` 三类容器区分。

### 3.1 `[equipment index]`：默认时装套装槽

```
[equipment index]
    defaultEquipment -1 39400 -1 40600 41000 41800 -1 -1 42200 -1 27118
[equipment index]-1
    christmas2007  39139 39566 -1 40783 41181 41957 -1 -1 -1 -1 -1
```

| 项 | 含义 | 取值 | 必填 |
|---|---|---|---|
| 套装名 | 时装套装标识（`defaultEquipment`、`christmas2007`、`choosukAvatar1`…） | 字符串，无空格 | ✅ |
| 后 11 个数 | **11 个外观槽的默认装备 id**，`-1` = 空槽 | 装备 id / -1 | ✅ |

11 槽顺序对应：头发 / 帽子 / 脸 / 上衣 / 裤子 / 鞋 / 胸 / 腰 / 皮肤 / …（**顺序待验证**，需要 `.equ` 的 `[equipment type]` 枚举交叉验证）。
自定义套装名（`christmas2007` 等）在 `[key value string]` 里带音效映射：`christmas2007Sound 0 R_CEMETARY_SKELETON_DMG 1 …`。

### 3.2 `[key value index]`：带 key 的数值小表

格式统一为 `名字 v0 i0 v1 i1 …` 或 `名字 值`（单个）。

| key | 含义 | 鬼剑士值 | 用途 |
|---|---|---|---|
| `drawFacePos` | 脸部贴图偏移 | `0 0 -10 1 92` | 渲染层：脸相对身体的坐标 |
| `drawAiFacePos` | APC 脸部偏移 | `0 0 0 1 100` | |
| `drawGhostFacePos` | 鬼手/副手偏移 | `0 0 10 1 10` | |
| `weaponSubTypeIndex` | 武器子类型 → 动画索引 | `27900 0 27000 1 27600 2 27900 3 27300 4 27900 5 28200` | **武器外观/动作映射**：子类型 0..5 对应动画组 id |
| `heaviestWeapon` | 最重武器子类型 | `3` | 影响攻速惩罚 |
| `combatType` | 战斗类型（0..4） | `0 0 0 1 0 2 0 3 0 4` | 全 0 = 近战；远程职业不同 |
| `apcMagicPhysicRate` | APC 魔/物攻折算率 | `100 0 100 1 90` | APC 用 |
| `summerAvatarIndex` | 夏日时装索引表 | 32 对 | 活动用 |
| `wraithBiteOffset` / `starFishBiteOffset` | 特定特效挂点 | `0 0 -34 1 1 2 12` | 渲染偏移 |
| `assaultIntroCut` | 突袭入场镜头开关 | `0` | |

### 3.3 `[key value string]`：字符串表

| key | 含义 | 值 | 关键性 |
|---|---|---|---|
| `growTypeEquipmentFileName` | **转职专属时装文件** | `0 (空) 1 character/swordman/growtype/weaponmaster.equ 2 (空) 3 …/berserker.equ 4 …/asura.equ` | ⭐ 转职后身体外观整包替换 |
| `<套装名>Sound` | 时装套装音效 | `…Sound 0 R_SM_DMG 1 SM_DIE …` | 表现层 |

**`growTypeEquipmentFileName` 的意义**：转职不是换一个 `.chr`，而是**给同一个角色挂上另一份「基础装备」，由那份 `.equ` 决定身体动画**。这解释了 `.chr` 里为什么没有「外观」字段。

---

## 4. 系统联动图

```
character.lst ──id──▶ .chr ─┬─[job]─────────────▶ 职业枚举（= 枚举值，见下）
                            ├─[growtype name]×6─▶ UI 职业名
                            ├─[growtype N] 增量──▶ 属性公式
                            └─[skill]/[skill]-n──▶ skill/<职业>skill.lst ──▶ .skl
characteretc/<职业>.etc ─┬─growTypeEquipmentFileName ──▶ growtype/*.equ（外观整包）
                         ├─weaponSubTypeIndex ──────────▶ 武器动画组
                         └─equipment index ─────────────▶ 默认时装 11 槽
exptable.tbl ──▶ 等级 ──▶ 技能 [required level] / [maximum level]（见 03-skill.md）
              └────────▶ 装备 [minimum level]（见 05-item.md）
```

**职业枚举值**（脚本层大量使用，例如 `sqr/character/swordman_load_state.nut.txt:20` 的 `ENUM_CHARACTERJOB_SWORDMAN`）：

| 枚举 | 值（按 `character.lst` 顺序推定） |
|---|---|
| swordman | 0 |
| fighter | 1 |
| gunner | 2 |
| mage | 3 |
| priest | 4 |
| atgunner | 5 |
| thief | 6 |
| atfighter | 7 |
| atmage | 8 |
| atpriest | 9 |
| atswordman | 10 |

> ⚠️ 待验证：`.lst` 顺序 ≠ 枚举值，需要用 `.nut` 里 `ENUM_CHARACTERJOB_*` 的定义（`sqr/dnf_enum_header.nut`）核对。

---

## 5. 样例原文 + 解读

### 样例 A：鬼剑士基础 + 两个转职块（`character/swordman/swordman.chr`）

```
[job]
    [swordman]
[growtype name]
    極詣·劍影 劍神 黑暗君主 帝血弒天 天帝 鬼劍士
[width]
    40 10
[HP MAX]
    180.0
[move speed]
    1350.0
[jump power]
    430.0
[skill]
    181 2 182 2 184 1 179 7 5 1 46 1 169 1 198 1 199 1 174 1
[growtype 1]

[HP MAX]-1
    45.0
[physical attack]-1
    4.800000190734863
[module damage rate]
    0.949999988079071 1.0 1.0 0.949999988079071
[growtype 2]
...
[skill]-1
    27 1 33 1 37 1 8 1 25 1 65 1 94 1 197 1
[module damage rate]-1
    0.699999988079071 1.0 1.100000023841858 0.699999988079071
[awakening name]
    極詣·劍魂
```

**解读**
- `[growtype name]` 的 6 个名字是**同一行的空格分隔串**而不是 6 个标签，解析时要 split；顺序与 growtype 1..6 对应。
- `[skill] 181 2 182 2 …`：**0 转自带技能**（id + 初始等级）。id 181/182 要去 `skill/swordman/*.skl` 查。
- `[skill]-1 27 1 33 1 37 1 8 1 …`：**转职 2（= growtype 2）时授予**。其中 `8 1` 正是「三段斩」——与 `skill/swordmanskill.lst.txt:8` 的 `8 → Swordman/TripleSlash.skl` 完全对上，闭环验证成功。
- 两个 `[module damage rate]` 不同（`0.95/1/1/0.95` vs `0.7/1/1.1/0.7`），说明**转职改变的是伤害类型系数，不是基础攻击力**。
- `4.800000190734863` 是 float32 精度残留，说明 `.chr` 的浮点字段是 4 字节 float，复刻时不必追精度。

### 样例 B：`character/characteretc/swordman.etc` 的转职时装绑定

```
[key value string]-1
    growTypeEquipmentFileName  0  1 character/swordman/growtype/weaponmaster.equ 2  3 character/swordman/growtype/berserker.equ 4 character/swordman/growtype/asura.equ
[key value index]-3
    weaponSubTypeIndex 27900 0 27000 1 27600 2 27900 3 27300 4 27900 5 28200
```

**解读**
- 格式是 `名字 (值, 索引)*`：`1 → weaponmaster.equ`、`3 → berserker.equ`、`4 → asura.equ`，`0` 与 `2` 是空串（未转职/另一个分支）。
- 因此「转职」= ①换一份 `.chr` 增量块 ②换一份 `growtype/*.equ` 外观 ③技能表用 `[growtype maximum level]` 开口。**三者都在数据里，没有一行代码判断"你是什么职业"**。
- `weaponSubTypeIndex` 的键值对方向要注意：`27900 0` 表示「动画组 27900 对应子类型 0」，不是反过来。

### 样例 C：转职专属装备文件的存在性

`character/swordman/growtype/weaponmaster.equ`（存在，索引里可查）——它不是玩家可掉落的装备，而是「转职后的身体」。这是 `equipment` 表 102,330 条中很大一部分不可掉落的原因（服装/外观资源与可掉落装备混在同一张注册表）。

---

## 6. 复刻时必须实现的最小集

按「不做就跑不起来 / 做了才有 DNF 手感」排序。

### M1 必须（缺一项职业系统就不成立）

1. **`CharacterDef` 资源**：`job_enum`、`growtype_names[6]`、`width`、13 项基础属性、6 组「每级增量」、每组 `module_damage_rate[4]`、默认技能表 `[(skill_id, lv)]`。
2. **属性结算函数** `stat(growtype, level) = base + per_level[growtype] * (level-1)`。
   - 注意 `level` 从 1 开始；转职瞬间要**按新 growtype 的增量重算**（不是加差值）。
3. **经验曲线**：115 级单级经验表（可直接抄 `character/exptable.tbl` 的 115 个整数）。
4. **转职判定表**：`growtype_max_level[6]` 在**技能**里（不是职业里），所以「能转什么职」由技能复算 → 见 [03-skill.md](03-skill.md) §3。
5. **职业枚举**：一份 `enum Job { SWORDMAN=0, … }`，供技能、装备 `[usable job]`、任务 `[target character]` 共用。这一份枚举是三大系统唯一的公共词汇。

### M2 应当（决定手感差异）

6. **速度五件套**：`move/attack/cast speed`、`hit recovery` + 派生公式。DNF 的手感 90% 来自这 5 个数的换算，建议先固定一条公式：
   `动画播放速率 = 1 + (speed - 1000)/1000 * k`（k 取 0.5~0.8，需在 Godot 里对帧）。
7. **`width` 碰撞体**：`40 10` = 半宽 40 / 高度 10？→ 实际用「宽 40、可站立高度 10」做受击盒基准（待验证，需 `.ani` 解码后核对）。
8. **重量 `weight`**：参与击退距离与浮空高度（与 `.atk [push aside]/[lift up]` 相乘，见 04-combat）。
9. **抗性 4 维**（fire/water/dark/light）+ 负值（鬼剑士暗抗 +20、光抗 −20）。负抗必须能被伤害公式放大，否则「属性攻击」没意义。

### M3 可以后做

10. `characteretc` 的 11 槽默认时装（纯外观）。
11. `weaponSubTypeIndex` / `heaviestWeapon`（只有做武器外观与攻速惩罚时才需要）。
12. 决斗场镜像职业（`at*`）：**用同一份数据 + `[pvp]` 分支**即可，不需要单独资源。

### 明确不要抄的

- `.chr` 里 8 位有效数字的浮点尾巴（`4.800000190734863`）——float32 序列化噪音，取 `4.8`。
- `[initial value]`（本版本全空）。
- `pvppricetable.tbl`（决斗场经济，单机无意义）。

---

## 7. 待验证清单

| # | 问题 | 怎么验证 |
|---|---|---|
| 1 | `[module damage rate]` 的 4 个分量各是什么 | 找同时有 4 类攻击的角色（如 gunner 的 physical/魔法/…) 对比 `.atk [separate attack]` |
| 2 | 职业枚举真实值 | 读 `sqr/dnf_enum_header.nut.txt` 的 `ENUM_CHARACTERJOB_*` |
| 3 | `width 40 10` 的两个数含义 | 等 `.ani` 解码后比对受击盒（P0.5） |
| 4 | `exptable` 是累计还是单级 | 用满级配置反推；或找 `[experience increasing point]`（.dgn 里有）交叉 |
| 5 | `characteretc` 11 个外观槽的顺序 | 用 `.equ [equipment type]` 枚举 + 时装槽枚举表核对 |
| 6 | `demonicswordman.chr` 两份（`character/demoniclancer/` 与 `character/swordman/`）谁生效 | 查 `character.lst` 未登记 → 可能由 `expertjob.etc` 指向 |
| 7 | `drawFacePos` 的 `0 0 -10 1 92` 到底几元 | 4 个数 + 1 个孤值，结构不明；可能 `x y rot flip` + 单值 = 索引 |
