# 06 · 怪物体系（.mob / 基表 / .ai / .aic / .key / 掉落）

> 范围：一只怪物由哪些数据描述、能力值从哪来、行为怎么表达、掉什么、怎么分类。
> 数据源：`export/text/monster/**/*.mob`（4,042 个，注册表 3,548 条）、`monster/*baseparameter.tbl`、`*.ai`（13,969）、`aicharacter/**/*.aic`（595）、`*.key`（6,461）、`etc/worlddrop.etc`。
> 相邻文档：怪物攻击参数 → [04-combat.md](04-combat.md)；副本里怎么摆怪 → [07-map.md](07-map.md)；怪物 AI 的 `.act` 动作层 → [09-script-mechanics.md](09-script-mechanics.md)。
> 官方标签释义：`export/_meta/tagdict.sqlite`（`ext='mob'` 有 254 个标签被注释）。

---

## 0. 一句话结论

怪物的「肉体」和「大脑」是**两套完全独立的文件**：

| 层 | 文件 | 负责 |
|---|---|---|
| 肉体（面板） | `.mob` | 名字、碰撞、等级区间、抗性、倍率、动作槽、掉落 |
| 能力值（数值） | `monster/*baseparameter.tbl` + `[ability table]` 索引 + `[ability category]` 乘数 | HP/攻防的等级曲线 |
| 大脑（行为） | `.ai`（条件树）+ `.act`（帧触发动作）+ `.key`（输入宏，仅 APC） | 什么时候做什么 |
| 掉落 | `.mob [item]`（独立）+ `etc/worlddrop.etc`（全局） | 掉什么 |

`.mob` 里**没有任何具体数值**（除了抗性和倍率）——HP 多少、攻击多少，全靠「基表行 × 乘数」。这是 DNF 能用 100 行基表覆盖 4,042 只怪物的原因，也是最值得抄的一点。

---

## 1. `.mob` 字段表

完整样本见 §4 样例 A。分组列出（优先级：`必填` 指几乎所有 .mob 都有）。

### 1.1 身份与分类

| 字段 | 官方中文名 | 含义 | 取值 | 必填 |
|---|---|---|---|---|
| `[name]` | 怪物的名称 | 显示名 | 文本，如 `雪魈` | ✅ |
| `[face image]` | 怪物在血条位置的头像 | 血条左侧头像 | `img路径 索引`，如 `Monster/MonsterFace.img 27` | ✅ |
| `[category]` | 怪物类型 | **复合枚举**，可多个 | 护甲类：`[fort armor]`/`[divine armor]`/`[human armor]`/`[fixture]`；种族：`[human]`/`[beast]`/`[plant]`/`[insect]`/`[machine]`/`[hybrid]`/`[undead]`/`[devil]`；战斗风格：`[melee combat]`/`[close-carefully]`/`[close-tough]` 等 | ✅ |
| `[width]` | 碰撞体积 | **X 轴宽、Y 轴高**（像素） | 两整数，如 `40 10` | ✅ |
| `[floating height]` | 浮游高度 | `0` = 地面型；`≥1` = 浮游型（值即高度） | 整数 | ❌ |
| `[level]` | 怪物等级 | **最小等级 最大等级**（同一只怪在副本里按难度/等级缩放） | 两整数，如 `18 33` | ✅ |

### 1.2 能力值来源（关键机制）

| 字段 | 官方中文名 | 含义 | 取值 | 必填 |
|---|---|---|---|---|
| `[ability table]` | 跟随的能力值表索引 | 选哪张基表 | `0`=基本（`monsterbaseparameter.tbl`）/ `1`=召唤物（`summonmonsterbaseparameter.tbl`）/ `2`=竞争地牢；另有 boss/named/common 表 | ✅ |
| `[ability category]` | 能力值分类乘数 | **5 个属性各乘一个系数** | `[HP MAX] * 1720 [EQUIPMENT_PHYSICAL_ATTACK] * 120 [EQUIPMENT_PHYSICAL_DEFENSE] * 130 [EQUIPMENT_MAGICAL_ATTACK] * 130 [EQUIPMENT_MAGICAL_DEFENSE] * 110` | ✅ |

`[HP MAX]` 的官方注释明确了双值结构：

> 参数 1：最小等级能力值 / 参数 2：最大等级能力值

所以每项能力是「该怪最小等级时的值」→「最大等级时的值」之间插值，再乘 `[ability category]` 的系数。

### 1.3 抗性与速度

| 字段 | 官方中文名 | 取值 | 必填 |
|---|---|---|---|
| `[fire resistance]` / `[water resistance]` / `[dark resistance]` / `[light resistance]` | 四属性抗性 | **两值**（最小/最大等级），可为负 | ❌ |
| `[freeze/poison/stun/curse/blind/hold/slow/confuse/sleep/stone/bleeding/burn/lightning/piercing resistance]` | 14 种异常抗性 | 数字或两整数 | ❌ |
| `[move speed]` | 移动速度 | `1000` = 100% | ✅ |
| `[attack speed]` / `[cast speed]` | 攻速 / 施放 | `1000` = 100% | ✅ |
| `[hit recovery]` | 硬直恢复（官方："硬直（数值越高…"） | 整数 | ✅ |
| `[weight]` | 体重（**克**） | 整数，如 `60000` = 60kg（与装备 `[weight] 2800` = 2.8kg 交叉验证；官方注释的「10g 单位」有误） | ✅ |
| `[hp regen speed]` / `[hp regen rate]` / `[mp regen speed]` | HP 每秒恢复率 / 有目标-无目标恢复率 / MP 恢复 | 整数 | ❌ |

### 1.4 感知与 AI 参数

| 字段 | 官方中文名 | 含义 | 取值 | 必填 |
|---|---|---|---|---|
| `[sight]` | 视力 | 越高越不容易丢失目标 | 整数，如 `300` | ✅ |
| `[vision]` | 视野距离 | 索敌范围 | 整数，如 `3000` | ❌ |
| `[targeting nearest]` | — | 是否优先最近目标 | `1`/`0` | ❌ |
| `[warlike]` | 好战性 | `0~100`，越高越好战 | 整数 | ✅ |
| `[intelligence]` | 怪物 AI 智力 | 整数 | ❌ |
| `[think term]` | 思考间隔 | **毫秒**：设定目标/选攻击/选移动的频率 | 如 `100` | ✅ |
| `[destination change term]` | 移动位置变更间隔 | 毫秒 | 如 `200` | ❌ |
| `[keep distance with target]` | 保持距离（X 轴） | 与目标在 X 轴保持多少距离 | 整数 | ❌ |
| `[keep range distance with target]` | 保持距离（范围） | 与目标保持多少距离 | 整数 | ❌ |
| `[attack delay]` | 攻击延迟 | `300` = 0.3 秒 | 整数 | ❌ |
| `[stuckbonus on damage]` | 受击硬直比率 | **4 数 = 2 组**：受**远程**攻击硬直（最小/最大）、受**近战**攻击硬直（最小/最大） | 如 `10 10 0 0` | ✅ |
| `[ai pattern]` | AI 模式设置 | **按难度指定 AI 文件**，见 §3 | 子标签 `[easy]`/`[medium]`/`[hard]`/`[ultimate]`/`[hero]` 或 `[normal]`/`[expert]`/`[master]`/`[king]`；每个难度下**顺序固定为 Event.ai、DestinationSelect.ai、Action.ai、MoveMethod.ai** | ✅ |

### 1.5 动作槽（与 AI 的攻击索引一一对应）

| 字段 | 官方中文名 | 含义 |
|---|---|---|
| `[waiting motion]` / `[waiting action]` | 待机动画 / 待机动作 | `.ani` / `.act` |
| `[move motion]` / `[move action]` | 移动 | 同上 |
| `[attack motion]` / `[attack action]` | **攻击动作列表** | `.ani` 列表，**顺序即攻击槽下标** |
| `[attack info]` | 攻击信息 | `.atk` 列表，**与 `[attack motion]` 平行、下标对齐** |
| `[damage motion 1]` / `[damage motion 2]` | 受击动作 | `.ani` |
| `[down motion]` / `[overturn motion]` | 倒地 / 被浮空 | `.ani` |
| `[sit motion]` / `[sit action]` | 坐下 | |
| `[die effect]` | 死亡特效 | `0 14 0` |
| `[etc action]` | 其他动作列表 | 非攻击用途，如 `action/back_shot.act` |

> `[attack motion]` 与 `[attack info]` 是**平行数组**，AI 的 `[return] n` 返回的就是这个数组的下标。这是怪物「招式表」的全部实现——没有独立技能文件。

### 1.6 掉落与台词

| 字段 | 官方中文名 | 含义 |
|---|---|---|
| `[item]` | **独立掉落** | `物品代码 权重` 成对重复；"击杀后从专门设置的掉落材料里随机掉落 1 个" |
| `[common champion drop item]` | 普通精英怪独立掉落 | 同上，仅精英怪 |
| `[common champion elemental property]` | 精英怪附加属性 | 如 `[water element] [dark element]` |
| `[speech on situation]` | 情境台词 | `[on attack]` / `[on etc]` / `[on die]` 等 + 文本 + 概率 |
| `[die sound]` / `[damage sound]` / `[attack sound]` / `[appear sound]` / `[ambient sound]` | 各类音效 | NPK 内音效名 |
| `[int data]` | **硬编码整数资料** | "各数值含义由硬编码决定" —— 每只怪的私有参数 |

---

## 2. 能力值链（100 行基表 → 4000 只怪）

```
.mob [ability table] N
   → monster/<N 对应的表>.tbl        // monsterbaseparameter / commonmonsterbaseparameter / boss / named / summon
       ↓ 按 [level] 的 min..max 在表中插值
   基值 (5 项) × .mob [ability category] 的乘数
       ↓
   最终 HP / 物攻 / 物防 / 魔攻 / 魔防
```

`monster/monsterbaseparameter.tbl` 实测（标签流 int32，头 `b0 d0`，5504 字节 = 4 + 1100×5）：

```
100 行 × 11 列，列 0 = 等级
[1,   30,   0,    30,   0,    50,    50,    2,   150,  2,   150]
[2,   30,   5,    30,   5,    74,    74,    7,   300,  7,   300]
[3,   30,   11,   30,   11,   101,   101,   12,  450,  12,  450]
 …
[100, 30,   1733, 30,   1733, 38549, 38549, 497, 15000, 497, 15000]
```

**结构判读**：`等级 + 5 组 × 2 列`，与 `[ability category]` 的 5 项属性一一对应，每组的 2 列正是官方说的「最小等级能力值 / 最大等级能力值」。

实测列组（100 级时）：`(30,1733) (30,1733) (38549,38549) (497,15000) (497,15000)`。
- 组 3 两端相等（38549）→ 极可能是 **HP MAX**（HP 不随怪等级浮动）。
- 组 4/5 完全相同且跨度极大（497→15000）→ 极可能是**攻击力**（随等级暴涨）。
- 组 1/2 也相同（30→1733）→ 防御类。

> ⚠️ 列→属性的**确切映射待验证**。验证方法：找一只 `[ability category]` 里只放大 `[HP MAX]` 的怪，把它的实际 HP 与表值比对。
>
> `commonmonsterbaseparameter.tbl` 为 24004 字节 = 4800 单元，行宽不同（行首 id 每 24 值 +1，推测 200 行 × 24 列）。其余 boss/named/summon 同为 24004；`chaosmonsterbaseparameter.tbl` 仅 168、`warroommonsterbaseparameter.tbl` 仅 604。

**这个设计的价值**：改一行基表 = 改一整个等级的全体怪物。复刻时强烈建议照抄「基表 + 每怪乘数」两层结构，而不是给每只怪写死数值。

---

## 3. 行为层：三套文件

### 3.1 `.ai` — 条件树 DSL（不是标签流，是一棵树）

`monster/casillas/ai/action.ai`（38 行）节选：

```
[ai pattern]
    [think]
        [void]
            is target in attack area() 140.0 40.0 40.0 40.0
        [true]
    [think]-1
        [void] check random() 40 100 [true]
    [think]-2
        [void] is the skill in cooltime() 1 [true] [return] -1 [false] [return] 1
    [think]-4
        [void] is target in attack area() 240.0 60.0 50.0 50.0 [true]
    [think]-8
        [void] number of in attack area() 350.0 350.0 200.0 200.0 enemy summon -1
    [think]-9
        [last result] >= 1.0 [true]
    [return]
        -1
```

**语义模型**

| 元素 | 含义 |
|---|---|
| `[think]` | 一个判断节点；块内是**条件表达式** |
| `[void]` | 条件修饰词（无返回/无副作用） |
| `[true]` / `[false]` | 条件成立/不成立时的**分支** |
| `[last result]` | 上一条条件的**数值结果**（可做 `>= 1.0` 比较） |
| `[return] n` | 返回 **`[attack motion]` 的下标 n**；`-1` = 不做任何事 |
| 条件函数 | `is target in attack area() x y w h`、`check random() p 100`、`is the skill in cooltime() n`、`number of in attack area() … enemy summon -1` |

**这是一门极小的脚本语言**：条件返回数值、`[true]/[false]` 按真值分支、`[return]` 是唯一的出口。四个文件分工（官方）

| 文件 | 职责 |
|---|---|
| `Event.ai` | 事件反应（受击/出现/死亡等） |
| `DestinationSelect.ai` | 选去哪 |
| `Action.ai` | 选什么招（本例） |
| `MoveMethod.ai` | 怎么走 |

复刻时**照抄这个设计**：一个 `AIBrain` 资源 = 4 个条件树 + 每帧 tick（`[think term]` 控制频率）。这比行为树（BT）更省，且天然可数据化。

### 3.2 `.aic` — APC（AI 角色）总装

`aicharacter/atfighter/karsh/karsh.aic`：

```
[minimum info]
    音波魔王卡修 7 1 0 0 60 0 0 1 0 0 0 no creature 0 0 0
[character status rate]
    400 1000 1 1 1 1 1.0 6 1.0 6 1 1 1 1 1.2999999523162842 …
[attack damage rate]
    0.1
[skill]
    9 28 7 10 27 1 81 10 86 23 …          ← 技能id 等级 成对
[equipment]
    29125 3 12 10151 0 0 14132 1 0 …      ← 物品id 强化等级 0
[think term] 100
[vision] 3000
[warlike] 0
[ai pattern]
    Event.ai DestinationSelect.ai Action.ai MoveMethod.ai
[key stream]
    atk15 atk15.key atk16 atk16.key atk9 atk9.key reset reset.key
[key cooltime]
    atk16 7000 atk15 3000 reset 500
```

**解读**
- `.aic` 把「角色面板 + 装备 + 技能 + AI + 输入宏」打包成一个 NPC 敌人/队友。
- `[key stream]` 把 **AI 决策映射到 `.key` 输入宏**：AI 想放 15 号招 → 执行 `atk15.key`（一串按键）。
- 所以 **APC ≠ 另一套 AI 系统，而是"会按键的玩家"**。这正是本作「逻辑层留联机接口」的最佳抓手：同一套角色状态机，人类玩家喂真实输入、AI 喂 `.key` 宏。

### 3.3 `.key` — 输入宏

`aicharacter/swordman/siran/key/tripleslash.key`：

```
[input]
    target current direction x 100 time 20
[input]-1
    f 30 time 300
[input]-2
    target current direction x 100 time 20
[input]-3
    f 30 time 300
```

| 元素 | 含义 |
|---|---|
| `target current direction x 100` | 朝目标方向输入 X 轴（组合键语法，而非单键） |
| `f 30 time 300` | 按 `f` 键 300 毫秒 |
| `time n` | 该条输入的持续时长（毫秒） |

`[state check] skill:27 1000 time 1000` 这类条目还能**等待状态条件**再继续执行，等于给宏加了同步点。

---

## 4. 样例原文 + 解读

### 样例 A：`monster/poongjintrainingroom/snowman/snowman.mob`（完整怪物定义）

```
[width] 40 10
[common champion elemental property] [water element] [dark element]
[ability category]
    [HP MAX] * 1720 [EQUIPMENT_PHYSICAL_ATTACK] * 120 [EQUIPMENT_PHYSICAL_DEFENSE] * 130
    [EQUIPMENT_MAGICAL_ATTACK] * 130 [EQUIPMENT_MAGICAL_DEFENSE] * 110
[category] [undead] [melee combat] [close-carefully]
[level] 18 33
[dark resistance] 30 30
[light resistance] -30 -30
[move speed] 300 300
[attack speed] 450 450
[cast speed] 700 790
[hit recovery] 800 800
[weight] 60000 60000
[sight] 300
[targeting nearest] 1
[warlike] 80
[attack delay] 1500
[stuckbonus on damage] 10 10 0 0
[item] 1013 100 1047 100
[attack motion] SnowmanAnimation/Attack1.ani SnowmanAnimation/Throw.ani
[attack info]   SnowmanAttackInfo/Attack1.atk SnowmanAttackInfo/Throw.atk
[int data] 2 5
[name] 雪魈
[speech on situation] [on etc] 喀吱 0 [on etc] 嘎???！ 0
```

**解读**
- `[category] [undead] [melee combat] [close-carefully]`：种族=不死、战斗风格=近战+谨慎接近。**分类是行为提示，不是数值**——AI 与掉落规则用它做筛选。
- `[level] 18 33` + 所有抗性写成 `30 30` / `-30 -30`：**同一个怪在 18~33 级之间被调用**，抗性按两端给。这是副本"怪物等级随难度缩放"的实现基础。
- `[ability category]` 里 `[HP MAX] * 1720` 是唯一的大倍率——说明雪魈是「血厚但攻低」的沙包怪。**一只怪的性格，80% 由这一行决定。**
- `[attack motion]` 两项 ↔ `[attack info]` 两项：**下标 0 = Attack1（近战），下标 1 = Throw（远程投掷）**。AI 的 `[return] 0/1` 就是选这两招。没有"技能池"文件，`[attack motion]` 就是技能池。
- `[int data] 2 5`：两个私货整数（"硬编码决定"）。这是 DNF 留给特殊怪的后门，复刻时可以直接砍掉，改用显式字段。
- `[item] 1013 100 1047 100`：独立掉落两项，权重都是 100。**注意右边是"权重"不是"百分比"**——多个物品的权重之和才是分母。

### 样例 B：`monster/casillas/ai/action.ai`（见 §3.1 摘录）

**解读**
- 整棵树只有 4 种条件函数，却能表达"远距离放 A、近距离放 B、被围住放大招、技能在冷却就不放"的完整战术。
- `[think]-2` 的写法很典型：`is the skill in cooltime() 1` → 真则 `[return] -1`（啥也不做），假则 `[return] 1`（放 1 号招）。**冷却检查被写进 AI 树，而不是技能系统**。这意味着怪物技能没有统一冷却表——每个 AI 文件自己判。
- `[think]-8` + `[think]-9`：先数周围敌人数，再用 `[last result] >= 1.0` 做判断。**`[last result]` 是可复用的临时变量**，这是它能表达复杂逻辑的关键。

### 样例 C：`aicharacter/atfighter/karsh/karsh.aic`（见 §3.2 摘录）

**解读**
- `[attack damage rate] 0.1`：APC 的伤害被压到 10%——**同一份角色数据，用一行倍率就变成"队友"或"敌人"**。
- `[equipment]` 是 `物品id 强化等级 0` 三元组：APC 的装备是**真装备**，走同一套装备系统（见 05-item）。
- `[key stream] atk15 atk15.key …` + `[key cooltime] atk16 7000`：招式名 → 输入宏 → 冷却。**AI 的"技能系统"就是"按键 + 冷却"**，与玩家完全一致。

---

## 5. 掉落体系（三层）

| 层 | 位置 | 规则 |
|---|---|---|
| **独立掉落** | `.mob [item] 物品代码 权重 …` | 击杀该怪后，从这份列表里按权重随机掉 1 个 |
| **精英独立掉落** | `.mob [common champion drop item]` | 同上，仅精英怪（`[common champion elemental property]` 同时给精英附加属性） |
| **全局掉落** | `etc/worlddrop.etc` `[world drop]` | 按**怪物等级**查表：`等级 (物品 权重)* -1`，`-1` 为该等级收尾；与怪物本身的掉落并行 |

`etc/worlddrop.etc` 实测头几行：

```
[world drop]
    1 0 31003915 8000 490000000 8500 10309021 3000 -1
    2 0 31003915 8000 490000000 8500 10309021 3000 -1
    …
```

→ `等级 0 (物品 权重)×3 -1`。第 2 个位置的 `0` 待验证（可能是子分类/难度）。

> **复刻建议**：单机版只做「独立掉落 + 权重」两层即可，全局掉落可以用一张等级→材料表代替。但**权重而非百分比**这点必须照抄：DNF 靠权重让策划随手加物品而不用重新配平概率。

---

## 6. 分类与难度

- `[category]` 的**三重维度**：护甲类型（fort/divine/human armor、fixture）× 种族（human/beast/plant/insect/machine/hybrid/undead/devil）× 战斗风格（melee combat / close-carefully / close-tough …）。
- 护甲类型决定「什么武器打得动」（`[fort damage rate]` 之类字段在 `.atk` 侧）；种族决定任务计数与掉落筛选；战斗风格是给关卡编排用的标签。
- `[ai pattern]` 的**难度分档**：`[easy]/[medium]/[hard]/[ultimate]/[hero]`（新）或 `[normal]/[expert]/[master]/[king]`（旧）。同一只怪在不同难度下用**不同的 4 个 .ai 文件**。
- 怪物还有 boss/named/common/summon 四套基表 + 独立的 `.tbl` 修正表（难度修正、组队平衡、血条比率等，见 `ext='tbl'` 的 51 个标签）。

---

## 7. 系统联动

```
.mob ──[ability table]+[ability category]──▶ 基表 → HP/攻防
  ├──[attack motion]/[attack info]──▶ .ani + .atk（04-combat）
  ├──[ai pattern]──▶ 4×.ai ──[return] n──▶ 攻击槽下标
  ├──[item]/[common champion drop item]──┐
  └──[level]──▶ etc/worlddrop.etc ───────┴─▶ 掉落
.mob 被 .map 引用（房间摆放，见 07）+ .dgn 难度（见 07）
.aic ──[key stream]──▶ .key ──▶ 角色输入状态机
```

- **与地图**：`.map [monster]` 的 10 值组引用怪物 id + 坐标 + AI 覆盖（见 07-map）。
- **与任务**：`.qst [hunt enemy]` 的 `(dungeonId, difficulty, monsterId, 1, count)` 按怪物 id 计数（见 08-quest）。
- **与战斗**：怪物打人走 `.mob [attack info]` 的 `.atk`；被打的硬直由 `[stuckbonus on damage]` 修正。
- **与宠物/召唤**：`.cre`（宠物）与 `.mob`（召唤物）结构相似但不同文件（见 08-quest）。

---

## 8. 复刻时必须实现的最小集

### M1 必须

1. **`MonsterDef`**：name、width(x,y)、category[]、level(min,max)、sight、warlike、think_term、attack_delay、weight、hit_recovery、resistances{}、motion 槽位、`attack_slots[]`（motion + atk 成对）、drop_table[]。
2. **基表 + 乘数两层数值**：一张 `level → (HP, PATK, PDEF, MATK, MDEF)` 表 × 每怪的 5 个乘数，按 `[level]` 两端插值。**这是最小可行且最省事的做法**。
3. **攻击槽**：`attack_slots[n]` 由 AI 返回下标触发；每个槽 = 一个 `.ani` 动作 + 一个 `.atk`。
4. **AI 条件树 VM**：至少 4 个条件函数（目标在范围、随机、技能冷却、周围数量）+ `[true]/[false]` 分支 + `[return] n` 出口 + `[last result]` 变量。
5. **掉落**：权重随机 1 个/次。

### M2 应当

6. **`think_term` 节流**：AI 不是每帧跑，按毫秒 tick。
7. **难度分档 AI**：`easy/normal/hard` 三档，同一只怪三份 AI 树（先做 2 档即可）。
8. **硬直比率双向修正**：`[stuckbonus on damage]` 的远程/近战两组。
9. **受击动作切换**：`damage motion 1/2`、`down`、`overturn`（浮空）四个状态对应四个动画。
10. **情境台词**：`[speech on situation]` = 纯数据驱动的语音/字幕气泡。

### M3 可后做

11. `[int data]`（每怪私货参数）——先全部砍掉。
12. 14 种异常抗性——先做 3 种（眩晕/冰冻/中毒）。
13. `[floating height]`（浮游怪）、`[piercing resistance]`（破甲）。
14. `.aic` 的 APC/NPC 队友系统——**但结构要留**（见 M2 的联机接口考虑）。

### 明确不要抄的

- `[attack kind]` 的 36 个裸数字（12 值 × 3 组，官方只写"怪物的攻击类型"，语义未闭合）——用显式字段替代。
- `[int data]` 这种"含义由硬编码决定"的后门。
- 100 行基表铺满 1..100 级（本作先铺 1..60）。
- 四套基表（boss/named/common/summon）× 100 行 = 冗余，单机版一张表 + 乘数足够。

---

## 9. 待验证清单

| # | 问题 | 怎么验证 |
|---|---|---|
| 1 | `monsterbaseparameter.tbl` 的 11 列与 5 属性的确切映射 | 找 `[ability category]` 只放大单项的怪，用实际 HP 反推 |
| 2 | `commonmonsterbaseparameter.tbl` 的行宽（24 还是别的） | 已确认行首 id 每 24 值 +1（1..200），需再抽样验证其余列 |
| 3 | `[attack kind]` 12 值 × N 组的语义 | 官方无细分；只能靠实机（打不同怪的硬直/受击差异）反推 |
| 4 | `[ai pattern]` 的 4 个文件是否严格按顺序 | 官方注释明说"顺序为 Event/DestinationSelect/Action/MoveMethod"，抽 3 只怪验证文件存在性 |
| 5 | `etc/worlddrop.etc` 每行第 2 个数的含义 | 跨等级段对比，看是否与难度/副本类型相关 |
| 6 | `.ai` 条件函数的完整列表 | 全库扫 `is target in attack area()` 之外的条件关键字（`grep -o '<pattern>()'`） |
| 7 | `[speech on situation]` 末位数字是否为概率 | 对照文本出现频率 |
