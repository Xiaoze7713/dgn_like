# 05 · 物品体系（.equ / .stk / 强化 / 合成 / 套装 / 规则引擎）

> 范围：装备与可堆叠道具的字段、稀有度与品质、强化/增幅/锻造、设计图与合成、套装、以及装备自带的 **if/then 规则引擎**。
> 数据源：`export/text/equipment/**/*.equ`（108,645 个，注册表 102,329 条）、`export/text/stackable/**/*.stk`（28,794 个，注册表 32,170 条）、`etc/upgrade.etc`、`etc/amplifyupgrade.etc`、`etc/upgrade_separate.etc`。
> 官方标签释义：`export/_meta/tagdict.sqlite`（`ext='equ'` 有 200+ 标签被注释，`ext='stk'` 有 100+）。**本文的字段释义大量直接来自官方注释原文**，引用处标注「官方」。
> 相邻文档：`.atk`/伤害公式 → [04-combat.md](04-combat.md)；技能数据被装备修改的接口 → [03-skill.md](03-skill.md)；掉落来源 → [06-monster.md](06-monster.md)。

---

## 0. 一句话结论

装备和道具是**同一个「物品基类」的两个子类**：

```
物品基类（.equ 与 .stk 共有的 ~20 个字段）
├── .equ（装备）   + 部位 / 攻防 / 耐久 / 外观 / 强化 / 套装 / if-then 规则
└── .stk（可堆叠） + 堆叠上限 / 使用效果 / 礼包内容 / 设计图配方
```

三个反直觉但极重要的发现：

1. **`[grade]` 不是稀有度，是「装备实际等级」**（官方：「影响增幅强化所加的具体数值」「在装备、道具中为掉落等级」）。真正的稀有度是 `[rarity]`，而玩家看到的**边框颜色是第三个字段 `[icon mark]`**。三套独立编码。
2. **`[equipment physical attack]` ≠ `[physical attack]`**。官方注释：前者是「装备物理攻击力」，后者在 `.equ` 语境下是**「力量」**（`[magical attack]`=智力、`[physical defense]`=体力、`[magical defense]`=精神）。而在 `.chr` 语境下同名字段又变回「角色物理攻击属性」。**同一个标签名在不同文件类型下语义不同**，这是本 PVF 最大的坑之一。
3. **`.equ` 自带一门规则引擎**（`[if]`/`[then]`）。一件史诗武器可以写成「按住上+下+宠物键 20 秒冷却，给自己挂 7139 号 appendage 并生成 48885 号被动对象」。**装备不是纯数值，是可编程的**。

---

## 1. 共通字段（物品基类）

| 字段 | 官方名 | 含义 | 取值 | 必填 |
|---|---|---|---|---|
| `[name]` | 名称 | 显示名 | 文本 | ✅ |
| `[basic explain]` / `[detail explain]` | 装备说明 / 详细说明 | 蓝色说明文本，游戏内 F4 切换简/详 | 文本 | 装备常见 |
| `[flavor text]` | 风味文本 | 底部灰色描述 | 文本 | ❌ |
| `[explain]` | 说明 | 道具说明 | 文本 | `.stk` 常见 |
| `[grade]` | **装备实际等级** | 影响强化/增幅数值；道具里=掉落等级（±5 级区间） | 整数，武器常见 1~100 | ✅ |
| `[rarity]` | 稀有度 | `0` 普通 / `1` 高级 / `2` 稀有 / `3` 神器 / `4` 史诗 / `5` 勇者 / `6` 传说 / `7` 神话 | 整数 | ✅ |
| `[icon mark]` | **图标边框** | `62` 白装 / `63` 蓝装 / `64` 紫装 / `65` 勇者 / `66` 神器 / `67` 传说 / `68` 史诗 | `img路径 帧号` | ✅ |
| `[icon]` | 图标位置 | 主图标 | `img路径 帧号` | ✅ |
| `[field image]` | 掉落图标 | 掉在地上时的图 | `img路径 帧号` | ✅ |
| `[attach type]` | 绑定类型 | `[free]` 自由交易 / `[trade]` 无法交易 / `[sealing]` 封装 / `[trade delete]` 无法删除 | 枚举子标签 | ✅ |
| `[usable job]` | 可使用职业 | `[all]`/`[swordman]`/`[fighter]`/`[at fighter]`/`[gunner]`/`[at gunner]`/`[mage]`/`[at mage]`/`[priest]`/`[demonic swordman]`/`[creator mage]`，可多个 | 枚举子标签列表 | ✅ |
| `[minimum level]` | 等级限制 | 使用所需最低等级 | 整数 | ✅ |
| `[weight]` | 重量 | **克**（官方样例写「g」；与角色 `.chr [weight] 68000`=68kg 交叉验证） | 整数 | ✅ |
| `[price]` | 价格 | 金币购买价 | 整数 | ❌ |
| `[cash]` / `[medal]` | 点券价 / 胜点价 | 商城货币价格 | 整数 | ❌ |
| `[value]` | 出售价格 | 卖给商店的金额，**实际到手 = 标写值 × 1/5**（官方） | 整数 | ✅ |
| `[creation rate]` | 掉落概率 | `0` = 永不掉落（官方） | 整数 | ❌ |
| `[cool time]` | 冷却 | **毫秒**（官方） | 整数 | ❌ |
| `[move wav]` | 拾取音效 | `POTION_TOUCH`/`CLOTH_TOUCH`/`BONE_TOUCH`/`SCRAP_TOUCH`/`RING_TOUCH`/`PAPER_TOUCH` 等 | 音效名 | ✅ |
| `[item group name]` | 具体类型 | 武器细分（`katana` 太刀/`ssword` 短剑/`lswd` 巨剑/`club` 钝器/`knuckle` 手套/`claw` 爪/`tonfa` 东方棍/`gauntlet` 臂铠/`hcannon` 手炮/`axe` 巨斧/`beamswd` 光剑/`automatic` 自动步枪/`totem` 图腾）与防具甲种（`cl*` 布甲/`lt*` 皮甲/`la*` 轻甲/`ha*` 重甲/`mt*` 板甲） | token | 装备常见 |
| `[sub type]` | 子类型 | 武器细分；时装=0 自由/1 强制；称号=0 自由/1 强制（无法脱下） | 整数 | ❌ |

### 1.1 三套「品质」编码的关系

| 概念 | 字段 | 用途 | 例 |
|---|---|---|---|
| 掉落/强化用等级 | `[grade]` | 决定强化加多少数值、从几级怪身上掉 | 太刀 `96` |
| 稀有度档位 | `[rarity]` | 强化成功率/费用的档位键（`etc/upgrade.etc` 用 6 档权重） | 史诗 `4` |
| UI 边框 | `[icon mark]` | 纯显示 | 史诗 `68` |

> 复刻时**三套都要保留**：`[grade]` 是数值曲线，`[rarity]` 是经济曲线，`[icon mark]` 是 UI。合成一套会立刻丢失强化与经济的手感（`etc/upgrade.etc` 的 `[cost weights by rarity] 0.5 1.5 3 5 8 4` 就是按 `[rarity]` 查的）。

---

## 2. `.equ` 独有字段

### 2.1 部位

| 字段 | 含义 | 取值 |
|---|---|---|
| `[equipment type]` | 穿戴部位 | `[weapon]` 武器 / `[coat]` 上装 / `[pants]` 下装 / `[shoulder]` 护肩 / `[waist]` 腰带 / `[shoes]` 鞋子 / `[amulet]` 项链 / `[wrist]` 手镯 / `[ring]` 戒指 / `[support]` 辅助装备 / `[magic stone]` 魔法石 / `[aurora avatar]` 光环 / `[title name]` 称号 / `[creature]` 宠物 / `[artifact red/blue/green]` 宠物装备 / 时装 `[hat avatar]` `[face avatar]` `[coat avatar]` `[pants avatar]` `[skin avatar]` 等 |
| — | 该标签带一个数字参数 | 如 `[weapon] 24`、`[coat avatar] 0`——数字是**部位槽索引**（见 `characteretc/*.etc` 的 `[equipment index]` 11 槽） |

穿戴槽总数 11+（`characteretc/swordman.etc` 实测：`-1 39400 -1 40600 41000 41800 -1 -1 42200 -1 27118`，`-1` = 该时装集在此槽无对应件）。

### 2.2 数值字段

| 字段 | 官方释义 | 单位/例 |
|---|---|---|
| `[equipment physical attack]` | 装备物理攻击力 | `+962 +830` → **地下城值 / 决斗场值**（两列成对） |
| `[equipment magical attack]` | 装备魔法攻击力 | 同上两列 |
| `[physical defense]` / `[magical defense]` | **体力 / 精神**（在 `.equ` 语境） | `+10` |
| `[physical attack]` / `[magical attack]` | **力量 / 智力**（在 `.equ` 语境） | `+100` |
| `[separate attack]` | 独立攻击力 | 一到多列 |
| `[physical critical hit]` / `[magical critical hit]` | 物/魔暴击率 | 单位 1% |
| `[stuck]` | 命中率 | **填负数**：`-1` = 命中 +1% |
| `[attack speed]` / `[cast speed]` / `[move speed]` | 攻速 / 施放 / 移速 | **单位 0.1%**（官方） |
| `[hit recovery]` | 硬直恢复 | 整数 |
| `[jump power]` | 跳跃力 | 整数 |
| `[HP MAX]` / `[MP MAX]` | 生命 / 魔法上限增量 | `+10` |
| `[HP regen speed]` / `[MP regen speed]` | 回复速度 | 实际值 = 输入 ×0.6 / ×3（官方） |
| `[inventory limit]` | 负重上限增量 | 单位 g（官方样例 `[inventory limit] 30`） |
| `[anti evil]` | 抗魔值 | 异界/特殊副本门槛，仅 50 级以上装备 |
| `[durability]` | 耐久度 | `0` = 无限（官方） |
| `[repair price]` | 修理价 | 缺省回退 `[value]` → `[price]`（官方） |

> 官方样例对 `[equipment physical attack]` 的注释是 `物理攻击力(地下城) 物理攻击力(决斗场)`。这解释了**为什么几乎所有数值字段都是成对的**：DNF 的 PVE/PVP 数值是分列的。复刻单机版可以只读第 1 列，但**解析时必须按偶数长度成对切分**。

### 2.3 外观字段（三个字段拼出一个武器贴图）

| 字段 | 官方释义 |
|---|---|
| `[equipment ani script]` | 武器的 **`.lay`** 文件路径（如 `equipment/character/swordman.lay`）。「lay 文件就是根据一定算法，这个算法需要结合 `[layer variation]` 与 `[variation]` 对武器进行贴图匹配」 |
| `[layer variation]` | `数字 英文名`：数字=**图层**（越大越靠前），英文=**调用同文件夹下该名字文件夹内的所有 .ani**。例 `2790 katanac` → 用 `katanac/` 里的动作 |
| `[variation]` | **武器贴图编号**，用来定位 NPK 里的 img。编码规则：`-1-2` → `0102`、`-0-0` → `0000`、`-13-9` → `1309` |
| `[animation job]` | 职业动画归属（`[swordman]`/`[demonic swordman]`/`[fighter]`/`[at fighter]`/`[gunner]`/`[at gunner]`/`[mage]`/`[at mage]`/`[priest]`）；同性别共享脚本时才需要 |

> 这是「装备驱动外观」的完整链路：`equ → .lay（动作总表）+ layer variation（图层+子文件夹）+ variation（贴图编号）`。
> 与 [03-skill.md](03-skill.md) 里的技能链是**同一个 `.lay`**：技能通过 `CUSTOM_ANI_*` 整数取 `.lay [etc motion]` 的下标，装备通过 `layer variation` 把 `%s` 展开成具体子文件夹。**两条链在 `.lay` 汇合。**

### 2.4 时装专属

| 字段 | 官方释义 |
|---|---|
| `[avatar select ability]` | 时装属性选择块：`[能力值KEY] [+/-] 数值`，或 `[SKILL_LEVEL] [职业] 技能ID 等级`；可用 `+` 的项：HP/MP 恢复率、移速、攻速、施放、暴击、MP 恢复 |
| `[avatar type select]` | 时效与价格表：`7 天=1000 点券 / 30 天=2000 / 无期限=4000`，首值 0 表示无期限 |
| `[part set index]` | 套装属性 **套装 ID**（把不同部位的时装串成一套） |
| `[possible kiri protect]` | 是否可用凯莉强化保护券 |

### 2.5 套装

```
[set name]   2013夏日Fate/Zero裝扮 套裝
[set item]   107560202 107570169 107520203 107500212 107510210 107540190 107580124
[set ability]
    [HP MAX] 150
    [MP MAX] 150
    [physical attack] 25
```

| 字段 | 官方释义 |
|---|---|
| `[set name]` | 套装名 |
| `[set item]` | 构成套装的**全部**装备代码（含自身）；首件是父件 |
| `[set item master]` | 子件指向的**父装备代码** |
| `[set ability]` | 集齐后附加的属性块（字段名与 §2.2 同） |

> 实测只有 ~742 处 `[set item]`：套装是少数派功能。**复刻优先级低**，但机制简单（查表 + 计数就够）。

### 2.6 `[skill data up]` —— 装备改技能

官方语法：

```
[skill data up]
  [职业token] [技能索引] [dungeon|pvp|all] [static|level|mp|cooltime|skill consume item|casting time] [数据索引] [+|%] [数值]
```

实测（圣耀救赎太刀）：`[all] 198 [all] [static] 99 + 197`、`[all] 198 [all] [static] 5 + 400`。

**这是装备和技能系统之间唯一的官方接口**：不改 `.skl` 文件，而是在读取技能数据时叠加修正。索引指向 `[static data]`（静态数据）或 `[level info]` 的某一列——与 [03-skill.md](03-skill.md) 的 `[level property]` 三元组 `(来源, 索引, 倍率)` 是同一套索引体系。

---

## 3. `[if]` / `[then]` 规则引擎（`.equ` 最复杂的机制）★

官方注释直接把 `[if]` 叫「如果」、`[then]` 叫「然后」：「`[if]` 作为前置词条，也就是触发条件；`[then]` 作为触发效果」。多条规则在导出里变成 `[if]-1`/`[then]-1`、`[if]-2`/`[then]-2`（后缀序号 = 出现顺序）。

### 3.1 触发条件（`[if]` 内可用的子键）

| 子键 | 含义 | 例 |
|---|---|---|
| `[module]` | 限定生效模式 | `[dungeon]` / `[dead tower]` / `[tournament dungeon]` / `[war room]` / `[blood system]` |
| `[cooltime]` | 此规则的冷却 | `20000`（毫秒） |
| `[use command]` | 需要玩家**手动触发指令** | `1`，配合 `[command]` 键序列 |
| `[command]` | 键序列 | `(UP) , (DOWN) , (CREATURE)` |
| `[time]` | 时间窗口 | `300 1 0` |
| `[change status]` | 状态比较 | `hp > % 0 end`（HP 百分比低于 0 触发） |
| `[is stat]` | 属性比较，**可多条 and 串联** | `myself -1 fire attack > 50` |
| `[attack success]` | 攻击命中时 | `1` |
| 末尾 `[cool time]` | 规则内冷却 | `1000` |

### 3.2 效果（`[then]` 内可用的子键）

| 子键 | 含义 | 例 |
|---|---|---|
| `[target]` | 效果作用于谁 | `myself -1` |
| `[appendage]` | 挂一个 `.apd`（buff/附加体） | `7139` |
| `[passive object]` | 生成一个被动对象 | `48885 0 0 0 0 -1` |
| `[equipment duration]` | 效果持续（毫秒） | `20000` |
| `[elemental weapon]` | 给武器附属性 | `fire` |
| `[consume item]` | 消耗道具 | `索引 数量` |

### 3.3 实测结构（圣耀救赎太刀 `101010864.equ`）

```
[if]-1
    [cooltime] 20000
    [use command] 1
[then]-1
    [target] myself -1
    [equipment duration] 20000
    [appendage] 7139
    [passive object] 48885 0 0 0 0 -1
[command]
    (UP) , (DOWN) , (CREATURE)
```

以及 4 属性 × 5 档阈值的属性武器组：

```
[if]-N
    [is stat] myself -1 fire attack > 50
    [cool time] 1000
[then]-N
    [elemental weapon] fire
```
（阈值 50/100/150/200/250 × 火/冰/暗/光 → 20+ 条规则）

**解读**
- `[if]` 块内多个子键是 **AND** 关系；`[is stat]` 还可自身串联（`… > 50` 再 `… < 100` 形成区间），这就是 5 档阈值的实现方式——**没有 switch，只有区间判断**。
- `[then]` 的 `[equipment duration]` 是**装备级持续时间**，与 `.apd` 自己的 `[duration]` 独立：装备可以在 appendage 到期前先撤掉它。
- `[command] (UP) , (DOWN) , (CREATURE)` 是**装备专属的按键触发器**——等于给装备绑了一个「装备技能」。它不占技能栏、不进 `.skl`、不进 `.lay`，纯由 `[if]/[then]` 驱动。
- 这套引擎让**装备能生成被动对象**（`[passive object]`），而被动对象有自己的 `.act`（24,077 个）与 `.atk`。于是「装备 → 生成物 → 独立攻击判定」这条链完全在数据里闭合，不需要代码里写特殊 case。

> ⚠️ 复刻建议：`[if]/[then]` 是**性价比极高的一个子系统**——只用一个 `Condition[] → Effect[]` 的通用 VM，就能同时表达：属性武器、触发式 buff、按键触发装备技能、血量阈值被动。强烈建议进 M2。

---

## 4. `.stk` 独有字段

### 4.1 `[stackable type]` 全枚举（官方注释原文）

| token | 含义 | token | 含义 |
|---|---|---|---|
| `[waste]` | 消耗品 | `[unlimited waste]` | 重复使用 |
| `[material]` | 材料 | `[recipe]` | **设计图** |
| `[quest]` | 任务物品（放任务栏） | `[quest receive]` | 接受任务的道具 |
| `[booster]` | 礼包：使用后获得（所有/随机）物品 | `[booster random]` | 随机魔盒 |
| `[booster selection]` | 礼包：可选 | `[cera booster]` | 礼包：自动使用 |
| `[package]` | 普通礼包 | `[cera package]` | 点券礼包 |
| `[usable cera package]` | 时装礼包，开启后自选属性 | `[legacy]` | 传承罐子 |
| `[upgradable legacy]` | 罐子类 | `[multi upgradable legacy]` | 幸运礼盒 |
| `[set]` | 套装道具 | `[creature]` | 宠物 |
| `[feed]` | 宠物饲料 | `[dye]` | 染色剂 |
| `[throw]` | 投掷物 | `[global effect]` | 全局效果 |
| `[disguise]` | 伪装道具 | `[unlimited etc]` | 无限次使用 |
| `[etc]` | 其它 | — | — |

实测频次（全库 grep）：`[recipe]` 16,596 / `[usable cera package]` 3,028 / `[cera package]` 2,199 / `[avatar emblem]` 1,717 / `[booster]` 1,688 / `[waste]` 1,088 / `[quest]` 1,084 / `[material]` 981 / `[enchant waste]` 926 / `[upgradable legacy]` 652 / `[booster selection]` 648 / `[package data]` 613 / `[etc]` 529。

> `[avatar emblem]`、`[enchant waste]`、`[material expert job]`、`[expert town potion]`、`[appendage group]` 是官方注释表**没列到**的 token —— 说明枚举表本身不完整，解析时**必须容错未知 token**。

### 4.2 堆叠与使用

| 字段 | 含义 | 取值 |
|---|---|---|
| `[stack limit]` | 堆叠上限 | 整数；`0` = 无限制（官方） |
| `[cool time]` + `[cooltime group]` | 使用冷却 + **冷却组** | 同组的道具共享冷却（药水组 10、食物组 0） |
| `[usable period]` / `[usable time]` / `[usable day of week]` / `[usable hour]` | 限时使用 | 待验证 |
| `[suitable job]` | 允许使用职业 | 同 `[usable job]` |
| `[npc gift disallowance]` | 不可赠送 NPC | 官方：「目前已废弃不用」 |

### 4.3 使用效果（`[waste]` 类）

实测三种：

```
[hp recovery]        + 250 1000 myself      // 恢复 250 HP，持续 1000ms，目标自己
[mp recovery]        % 15  1000 myself      // 按 15% 恢复 MP
[active status recovery] poison 70 myself   // 解除中毒，70 = 概率/强度
[my status]          bless 100 100 1119 0 0 0 0
[except status recovery] …
```

**统一格式**：`(效果类型) [+|%] 数值 持续毫秒 目标`。
`+` = 绝对值、`%` = 百分比、无符号 = 直接给状态。**这一行就是一个极简的效果 DSL**，和 `[if]/[then]` 是同族设计。

### 4.4 礼包与内容物

| 字段 | 官方释义 |
|---|---|
| `[package data]` | 礼包内容：`物品代码-数量-物品代码-数量-…`，`[stackable type]` 为 `[cera package]`/`[package]` 时使用 |
| `[booster info]` → `[etc]` | 随机礼盒：**三元组** `(类别码, 物品ID, 权重)` 重复，如 `2 1108 36764 2 1108 36764 5 1108 36764` |

### 4.5 设计图（`[recipe]`）★

`stackable/recipe/2651416.stk`（84 级设计图）关键字段：

```
[stackable type]
    [recipe] 1
[string data]
    [weaving]
    [monster card id] 0
[int data]
    6  106010043 1  10000204 15  10000327 75  10000224 1  3167 250  3042 100  1  106010044 1  0
[success rate]
    5
[maintain ability]
    1
[broadcast type]
    1
[fail output]
    106010044 1
```

`[int data]` **已解码**：首值 = 材料种类数 N，随后 N 组 `(材料 id, 数量)`，再一组 `(产物个数, 产物 id, 数量)`，末尾 `0` 收尾。上例 = 6 种材料 → 产出 `106010044 ×1`；`[fail output] 106010044 1` 说明失败也给这件。

第二个样本交叉验证（`nrcp_shd_palehorse_jin.stk`）：
`6  3037 97  3146 6  3052 1  3163 2  3166 5  2610030 9  1  14941 1  0` → 6 种材料 → 产出 `14941 ×1`。✅ 格式一致。

| 字段 | 含义 | 取值 |
|---|---|---|
| `[need material]` | 材料表（另一种写法） | 单值或数值序列（官方：「列数、单位不能只凭字段名推断」） |
| `[success rate]` | 成功率 | `100` = 100%（官方） |
| `[maintain ability]` | 制作后保留强化/附魔 | `1` 保留 |
| `[broadcast type]` | 制作广播类型 | `1` |
| `[fail output]` | 失败产物 | `物品id 数量` |
| `[string data]` → `[weaving]` / `[craftmanship]` / `[machinary]` / `[chemistry]` / `[enchant]` | **工艺类型**（织造/精工/机械/化学/附魔），配合 `[monster card id]` 指向宝珠继承的卡片 | 枚举子标签 |

> `[string data]` 在 `.stk` 里是**工艺/宝珠部位表**（`[weapon]`/`[coat]`/`[ring]` 等 + 工艺类型），在 `.apd` 里却是**技能加成规则表**（`[fighter] 5 [all] [level] 1 % 18`）。同名标签在不同文件里是不同东西——**再次印证「标签名只在文件类型语境内有意义」**。

---

## 5. 强化 / 增幅 / 锻造（`etc/*.etc`）

三张表结构相同、参数不同：

| 表 | 文件 | 作用 |
|---|---|---|
| 强化 | `etc/upgrade.etc`（23,660B） | +0…+50，攻击/防御递增 |
| 增幅 | `etc/amplifyupgrade.etc` | 消耗「异次元」材料，额外出「红字」属性（力量/智力/体力/精神） |
| 锻造 | `etc/upgrade_separate.etc`（3,540B） | 独立攻击力 |

关键字段：

| 字段 | 含义 | 实测值 |
|---|---|---|
| `[table]` | 逐级概率表：首列=等级，随后 5 个概率（成功/维持/降级/破坏等），尾列费用上限 | `[0 0.018 0.10 0.033 0.20 0.60 0 1 0 490000000 1]` |
| `[level]` | 各档的等级上限 | `8 8 8 24` |
| `[cost weights by rarity]` | **按稀有度**的费用权重（6 档：普通/高级/稀有/神器/史诗/传说） | `0.5 1.5 3 5 8 4` |
| `[stat weights by rarity]` | 按稀有度的数值权重 | `0.4 0.7 1 1.25 1.4 1.1` |
| `[cost]` | 逐级基础费用 | `0 600 800 1100 1300 …` |
| `[destroy level by rarity]` | 从第几级开始会**碎** | `common 10 uncommon 10` |
| `[max upgrade level by rarity]` | 各稀有度上限 | `common 50 uncommon 50` |
| `[repair cost rate by upgrade level]` | 逐级修理费率 | 50 × `1.0` |
| `[upgrade failed bonus weight by rarity]` | 失败累积的保底权重 | `rare 1.0 unique 1.2 epic 1.5 chronicle 1.0` |
| `[correction grade by rarity]` | 强化等级换算到「等效 grade」的系数 | `common 1 uncommon 1 rare 2 unique 4 epic 5 chronicle 3` |
| `[cost weight by upgrade level]` | 逐级费用权重 | `0 0.5 1 0.5 2 0.5 …` |
| `[upgrade machine frame base time]` / `[upgrade machine frame rate]` | 强化机（凯莉）动画时长 | `20 15 10 20` |
| `[disjoint]` 块 | 分解：`[disjoint bonus item] 3243`（产出物）、`[equip level const] 40`、`[upgrade const for bonus item count] 10` | — |

**解读**：强化系统**一个数字都没写进装备文件**。装备只提供 `[grade]`（数值曲线位置）和 `[rarity]`（费用/概率档位），其余全在 `etc/upgrade.etc`。这是「数据与规则分离」的教科书案例：加一件新装备**不需要动强化表**。

---

## 6. 样例原文 + 解读

### 样例 A：`equipment/character/swordman/weapon/katana/101010864.equ`（圣耀救赎太刀，节选）

```
[name]           圣耀救赎太刀
[grade]          96
[rarity]         4
[icon mark]      Item/IconMark.img 68
[equipment type] [weapon] 24
[item group name] katana
[usable job]     [swordman] [demonic swordman] [creator mage]
[attach type]    [trade]
[minimum level]  90
[physical attack]  68
[magical attack]   102
[equipment physical attack] 962 830
[equipment magical attack]  1063 918
[separate attack]           624 404
[attack speed]  80
[cast speed]    40
[stuck]         1
[durability]    45
[weight]        2800
[value]         138240
[price]         172800
[repair price]  138240
[creation rate] 0
[variation]         56 0
[layer variation]   2790 katanac
[equipment ani script] equipment/character/swordman.lay
[cool time]     10000
[skill data up] [all] 198 [all] [static] 99 + 197
[if]-1 … [then]-1 …（见 §3.3）
```

**解读**
- `[grade] 96` + `[minimum level] 90`：**两个等级**。前者决定强化收益与掉落区间（91~101 级怪），后者是佩戴门槛。
- `[icon mark] 68` = 史诗边框；`[rarity] 4` = 史诗档；二者一致但独立存储。
- `[equipment physical attack] 962 830` 是两列（PVE/PVP）：**PVP 值低 14%**，DNF 的 PVP 平衡就藏在这些第二列里。复刻单机版只需第 1 列。
- `[stuck] 1` = **命中率 -1%**（负数才是加，这里填正数是减）——这类「反直觉编码」在 DNF 里不止一处，解析时要留注释。
- `[layer variation] 2790 katanac`：图层 2790（很靠前）、子文件夹 `katanac`。配 `[variation] 56 0` → 贴图编号 `5600`。
- `[skill data up] [all] 198 [all] [static] 99 + 197`：给 198 号技能的第 99 号静态数据 +197。**一件武器直接改技能参数**，且跨职业（`[all]`）生效。

### 样例 B：`stackable/recipe/2651416.stk`（设计图，见 §4.5）

**解读**
- `[recipe] 1`：枚举 token 后跟一个数字，数字语义未闭合（可能是子类型或可制作次数），复刻时可以先忽略。
- `[int data]` 的一维数组表达「6 种材料 + 1 种产物」——**没有嵌套结构，纯扁平**。这是 PVF 的常见手法：能用数字流表达的绝不用嵌套。
- `[success rate] 5`：注意官方样例说 `100` = 100%，但这里写 `5`。**单位不一致**（可能是 5‰ 或「成功率等级」），标为待验证。

### 样例 C：`stackable/consumption_1240.stk`（暗精灵的解除中毒药剂）

```
[name]            暗精靈的解除中毒藥劑
[grade]           60
[rarity]          1
[icon mark]       Item/IconMark.img 63
[weight]          1
[usable job]      [all]
[minimum level]   60
[stack limit]     1000
[stackable type]  [waste] 1
[item group name] potion
[price]           600
[cool time]       1000
[cooltime group]  10
[move wav]        POTION_TOUCH
[active status recovery] poison 70 myself
```

**解读**
- `[item group name] potion` + `[cooltime group] 10`：**同组共享冷却**。喝任意一瓶 10 号组药水，其他 10 号组药水一起进 CD——这是防止「药水连嗑」的机制，纯数据实现。
- `[grade] 60`：作为道具，`[grade]` = 掉落等级 → 从 55~65 级怪身上掉。
- `[weight] 1`（1 克）+ `[stack limit] 1000`：一瓶药 1 克、可堆 1000 瓶，于是「一背包药水」在重量系统里几乎免费。**负重压力全给装备**。
- `[active status recovery] poison 70 myself`：一行完成「解中毒」。`70` 推测是解除强度/概率。

---

## 7. 系统联动

```
.lst 注册表（equipment.lst 102,329 / stackable.lst 32,170）── id → 路径
   ├── .equ ──[equipment type]+[sub type]──▶ 穿戴槽（characteretc 的 [equipment index] 11 槽）
   │     ├──[equipment physical attack] 等──▶ 面板（02-character 的属性换算）
   │     ├──[skill data up]──▶ 技能数据修正（03-skill 的 static/level 索引）
   │     ├──[equipment ani script]+[layer variation]+[variation]──▶ .lay → 武器 .ani
   │     ├──[if]/[then]──▶ .apd（appendage）+ 被动对象（.act/.atk）
   │     ├──[set item]/[set name]/[set ability]──▶ 套装
   │     └──[grade]+[rarity]──▶ etc/upgrade.etc（强化/增幅/锻造/分解）
   └── .stk ──[stackable type]──▶ 使用效果 / 礼包 / 设计图（.int data 配方）
         └──[int data] 材料 id ──▶ 反查 equipment/stackable 注册表
```

- **与角色**：`[usable job]` × `characteretc/*.etc` 的 `growTypeEquipmentFileName`（转职专属外观整包）。
- **与战斗**：装备提供攻击力/暴击/攻速，进入 [04-combat.md](04-combat.md) 的伤害公式。
- **与怪物**：`.mob [item]` 的掉落 id 落到这两张注册表（见 [06-monster.md](06-monster.md)）。
- **与任务**：`.qst [int data]` 的物品 id 同样落到注册表（见 [08-quest.md](08-quest.md)）。
- **与 NPC**：商店用 `[price]`/`[value]`；`[npc gift disallowance]` 已废弃。

---

## 8. 复刻时必须实现的最小集

### M1 必须

1. **物品基类**：`id, name, desc, grade, rarity, icon, icon_mark, field_image, attach_type, usable_job[], min_level, weight, value, stack_limit`。
2. **两个子类**：`EquipItem`（`equipment_type` + 部位槽 + 数值块）与 `StackItem`（`stackable_type` + 使用效果）。
3. **部件槽与穿戴校验**：11+ 槽位 + `[usable job]` + `[minimum level]` 校验 + 重量上限（`[inventory limit]`）。
4. **数值字段成对切分**：所有 `[equipment physical attack] 962 830` 这类都按「PVE/PVP」两列解析（单机取第 1 列）。
5. **使用效果一行 DSL**：`(类型) [+|%] 数值 毫秒 目标` → 至少支持 HP/MP 恢复、解除异常。
6. **消耗品冷却组**：`(cooltime_group, until_time)` 字典。
7. **强化表驱动**：`etc/upgrade.etc` 的 `[table]` 逐级概率 + `[cost weights by rarity]`，装备侧只出 `[grade]`+`[rarity]`。

### M2 应当

8. **`[if]/[then]` 规则 VM**（性价比最高）：`Condition → Effect` 两个数组，支持 `[module]/[cooltime]/[use command]/[is stat]/[change status]` × `[appendage]/[passive object]/[elemental weapon]/[equipment duration]`。装备技能、属性武器、血量被动全靠它。
9. **设计图配方**：`[int data]` 的 `N + N×(id,cnt) + (cnt,id,cnt) + 0` 解码 + `[success rate]` + `[fail output]`。
10. **礼包三类**：`[package data]`（固定内容）、`[booster info]`（权重随机）、`[booster selection]`（自选）。
11. **套装**：`[set item]` 列表 + `[set ability]` 属性块 + 「集齐 N 件」判定。
12. **装备改技能**：`[skill data up]` 的职业 token + 技能 id + 作用域 + 数据类型 + 索引 + `+ / %`。

### M3 可后做

13. 时装系统（`[avatar select ability]`/`[avatar type select]`/`[part set index]`）——只影响外观与少量属性，可先用「外观 override」占位。
14. 增幅（红字属性）、锻造（独立攻击）。
15. 分解（`[disjoint]`）。
16. 宝珠/附魔（`[enchant]` + `[monster card id]` 继承卡片属性）。
17. `[creation rate]`（掉落概率）与 `±5 级掉落区间`。

### 明确不要抄的

- `[physical attack]`/`[magical attack]` 这种**同名异义**（在 `.chr` 是攻击力、在 `.equ` 是力量/智力）。复刻时直接改名 `strength`/`intelligence`/`physical_attack_power`。
- `[stuck]` 填负数为加、`[value]` 实收 1/5 这类「反直觉编码」。
- `.equ` 里那 20+ 条按属性阈值展开的属性武器规则（`[if]` 区间判断 × 20）——用一个参数化规则替代。
- `[int data]`/`[string data]` 的「语义由硬编码决定」后门。

---

## 9. 待验证清单

| # | 问题 | 怎么验证 |
|---|---|---|
| 1 | `etc/upgrade.etc [table]` 每行 5 个概率的确切语义（成功/维持/降级/破坏/失败？） | 对照实机 +0→+1 的成功率公示值 |
| 2 | `[stackable type] [waste] N` 的数字含义（子类型？使用次数？） | 对比 potion=1、food=4 两类的共同点 |
| 3 | `[success rate] 5` vs 官方「100 = 100%」单位不一致 | 抽 20 个设计图看取值范围分布 |
| 4 | `[stack limit] 0` = 无限制 是否真实现 | 找 `[stack limit] 0` 的样本再实机 |
| 5 | `[my status] bless 100 100 1119 0 0 0 0` 的 6 个数字 | 官方无注释，需实机 |
| 6 | `[active status recovery] poison 70 myself` 的 70 | 同上 |
| 7 | `[if] [time] 300 1 0` 三值 | 全库统计出现形态 |
| 8 | `[rarely used] [part set index]` 套装 ID 与 `[set item]` 两套套装机制的关系 | 找同时有两者的装备 |
| 9 | `[avatar type select]` 的 5 列（时效/价格…）确切列义 | 官方只给了样例表，需逐列对照 |
| 10 | `[int data]` 配方里「产物个数」位是否真的存在（还是只有 产物id+数量） | 找 3 个以上配方交叉验证（已 2 个一致 ✅） |
