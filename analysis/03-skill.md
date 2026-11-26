# 03 · 技能体系（.skl / skill 注册表 / 状态机接口）

> 范围：一个技能在数据里由什么组成、数值怎么随等级长、TP（强化）怎么挂回本体、技能最终怎么变成一个能动的动作。
> 数据源：`export/text/skill/**/*.skl`（4,005 个）、`export/_meta/lst/skill__*skill.lst.tsv`、`export/text/sqr/**`（脚本层）。
> 相邻文档：属性来源 → [02-character.md](02-character.md)；伤害数值 → [04-combat.md](04-combat.md)；`.act` 逐行分析 → [09-script-mechanics.md](09-script-mechanics.md)（本文件不重复）。

---

## 0. 一句话结论

`.skl` 是一张 **纯数值表 + 元信息**，它**不包含任何动作、判定框、帧时序**。

技能从「表」变成「动作」，靠三处拼接：

```
skill id (8)
  → sqr/character/swordman_load_state.nut.txt:93
      pushState(job=0, "character/swordman_jg/tripleslash/tripleslash.nut", "TripleSlash", state=101, skill=8)
  → 该 .nut 的 checkExecutableSkill_TripleSlash(obj) 判定"能不能放"，成功后 setState
  → .nut 里用 CUSTOM_ANI_* 常量（=`swordman_value.nut` 的整数）选动画帧
  → 该整数 = .lay `[etc motion]` 数组下标（258 → `%s/tripleslashbsattackb_body.ani`）
  → `%s` = 装备/转职给的 layer variation 目录
  → ATTACKINFO_* 常量（149）→ character/<job>/attackinfo/*.atk 伤害参数
```

**关键认知：玩家技能没有 `.act` 文件。** 全库 77,511 个 `.act` 里只有 1 个在 `character/` 下（`character/common/action/booster_particle.act`），24,077 个在 `passiveobject/`、52,848 个在 `monster/`——`.act` 是**怪物与召唤物**的触发器容器。玩家技能的时序完全由 `.nut` 状态机 + `.ani` 帧事件表达。复刻时如果你照着 `.act` 去设计玩家技能系统，会走错路。

---

## 1. 注册表与命名

`export/_meta/lst/skill__swordmanskill.lst.tsv`（243 条，全部职业约 3,900+ 条）：

```
id <TAB> 相对路径
1	Swordman/Guard.skl
8	Swordman/TripleSlash.skl
143	Swordman/TripleSlashEx.skl
```

| 事实 | 值 |
|---|---|
| id 空间 | **全局单表**，跨职业不重复（1..约 4000+，有空洞） |
| id 用途 | `.chr [skill] id lv`、`[pre required skill] id lv`、`.apd [string data] (job) skillId …`、`.nut sq_IsUseSkill(id)`、`.equ [skill data up] skillId …` |
| 文件组织 | `skill/<职业小写>/<技能名小写>.skl`，另有 `3rd/` 子目录放三觉技能 |
| 目录与 lst 不一致 | lst 里写 `Swordman/xxx.skl`（大小写混合），磁盘是 `skill/swordman/xxx.skl` → **路径解析必须大小写不敏感** |

`[name2]` 是英文内部名，**与文件名、与 `.nut` 函数名三者同源**（`Triple Slash` ↔ `tripleslash.skl` ↔ `checkExecutableSkill_TripleSlash`）。这是跨层寻找实现的唯一线索。

---

## 2. `.skl` 字段表

证据：`skill/swordman/tripleslash.skl`、`tripleslashex.skl`、`lightswordmastery.skl`、`opendisjointshop.skl`。

### 2.1 元信息

| 字段 | 含义 | 取值 | 必填 |
|---|---|---|---|
| `[name]` | 中文显示名 | 如 `三段斬` | ✅ |
| `[name2]` | 英文内部名 | 如 `Triple Slash` | ✅ |
| `[basic explain]` | 一行简介 | 文本 | ✅ |
| `[explain]` | 详细说明（**含"Lv5 以上解锁 X"这类隐性规则，只写在文本里，代码读不到**） | 多行文本 | ✅ |
| `[purchase cost]` | 学习消耗 **SP** | 整数，`15`；TP 技能用 `[special purchase cost]` | ✅ |
| `[special purchase cost]` | TP（特性点）消耗 | 整数，`2`（仅 TP 技能） | ❌ |
| `[required level]` | 可学等级 | 整数 | ✅ |
| `[required level range]` | **等级间隔**（官方名）。`2` = 每 2 级可用 SP/TP 升 1 级 | 整数 2 / 3 / 5 | ❌ |
| `[pre required skill]` | 前置技能 | `技能id 需求等级`，如 `8 5` | ❌ |
| `[type]` | 主动/被动 | `[active]`(1641) / `[passive]`(1996) —— **只有这两种**，无 `[buff]` | ✅ |
| `[skill class]` | **技能系列分类索引**（官方名）：把类似技能归组（街头系/魔法系/体术系…），用于技能分类显示，以及**装备对特定系列技能的识别** | `0..5`，实测分布 0:680 1:1106 2:547 3:616 4:687 5:2 | ✅ |
| `[maximum level]` | 可购买的最高等级 | 整数（10 / 50 / 70） | ✅ |
| `[growtype maximum level]` | 每个转职可用 SP/TP 学到的**最高等级**，`0` = 该转职学不到；需与 `[skill fitness growtype]` 配合才真正生效 | 本版本实测 **6 个**整数（官方旧样例为 5 个，第 6 位对应后续版本新增的转职） | ✅ |
| `[skill fitness growtype]` | 允许学习的转职下标（0 基） | 整数列表，如 `0 1 2 3 4` | ❌ |
| `[feature skill type]` | 是否为 TP 强化技能 | `1` = 是（仅 TP 技能有此字段） | ❌ |
| `[feature skill index]` | **本体技能 → 它的 TP 强化技能 id** | `143`（TripleSlash → TripleSlashEx） | ❌ |
| `[durability decrease rate]` | 每次使用掉多少耐久 | 整数 | ❌ |
| `[auto cooltime apply]` | 冷却是否自动开始 | `0` / `1` | ❌ |
| `[consume item]` | 消耗材料 | `物品id 数量 数量`，如 `3037 0 0`（无色小晶块） | ❌ |
| `[weapon effect type]` | 技能吃物理还是魔法加成 | `[physical]` / `[magical]` | ✅ |
| `[icon]` | 图标 | `img路径 索引 img路径 索引`（两枚：常态 + 高亮） | ✅ |
| `[command]` | 指令 | DSL：`(RIGHT) & (SKILL)`、`(UP) , (DOWN) , (CREATURE)`，`&`=按住、`,`=顺序 | ❌ |
| `[command key explain]` | 指令的人话说明 | `操作指令: →(按住狀態下)+Z` | ❌ |
| `[command customizing]` | 是否允许改键 | `0`/`1` | ❌ |

### 2.2 分环境数值块（4 个，结构相同）

`[dungeon]`（PVE）、`[pvp]`（决斗场）、`[death tower]`（绝望塔，多数为空）、`[warroom]`（战争大厅，多数为空）。

| 子字段 | 含义 | 取值 | 必填 |
|---|---|---|---|
| `[consume MP]` | MP 消耗 | **两值**：等级 1 值 → 满级值 | PVE 主动技能必填 |
| `[cool time]` | 冷却 | **两值，单位毫秒**（6000 = 6 秒）；两端常相等 | ✅ |
| `[static data]` | **静态数据**（官方名）：不随等级变化的技能参数槽 | 长度 0~12 都有；主动技能常见 `600 -1000`，被动常见 11 值 | ❌ |
| `[level info]` | **等级数值主表**，见 §3 | 首值=列数 C，后接 C×70 个数 | ✅ |
| `[special level up]` | 每级额外百分比成长 | `(类型, 列号, 运算符, 数值)*`，如 `-1 0 % 8` | ❌ |

### 2.3 `[level property]`：给玩家看的公式文本

```
[level property]
    1 99 3連斬的各物理攻擊力 : <int>% + <int>、  <int>% + <int>、  <int>% + <int>
         5連斬的各物理攻擊力 : <int>% + <int>、 … + <int> -1 0 1.0 -2 3 1.0 -1 0 1.0 -2 3 1.0 -1 1 1.0 -2 4 1.0 …
```

| 部分 | 含义 |
|---|---|
| 前两个数 `1 99` | 该文本生效的技能等级区间 |
| 引号内文本 | 带 `<int>` 占位符的模板（**多行，靠缩进续行**） |
| 尾部三元组 | `(来源, 索引, 倍率)`。官方注释：**首值 `-1` 时从 `[level info]` 读取**；非负值可指向 `[static data]`。第二值是列号/槽位，第三值是倍率 |

官方注释（`tagdict.sqlite`，ext=`skl`，tag=`level property`）原文摘要：

> 技能等级区间内的显示说明与参数映射闭合块。块内包含适用等级范围、带 `<整数>/<小数1>/<小数2>` 占位符的说明文本，以及最多多行参数来源/索引/倍率记录；首值为 -1 时从 `[level info]` 读取，非负值可指向 `[static data]`。它主要提供说明和列映射线索，**不能替代真实运行参数**。

三元的第二值在 `-1`（整数百分比）与 `-2`（整数加法）时指列号，`3`（浮点，×0.001 转秒）时指 static data 槽位。

机制：**UI 上的技能说明完全由这张表驱动**——`<int>` 依次被 `(类型,列)×倍率` 从 `[level info]` 的对应列算出。所以「技能描述随等级变化」不是硬编码，是数据。复刻时若要让技能面板自动更新，必须实现这个占位符求值器。

---

## 3. `[level info]` 的编码（最重要的一张表）

格式：`C v[0][0] v[0][1] … v[0][C-1] v[1][0] …`，即 **首值是列数 C，随后按「行=等级、列=属性」行优先铺开**。

已验证：

| 文件 | C | 总长 | 等级行数 | `[maximum level]` |
|---|---|---|---|---|
| `tripleslash.skl` [dungeon] | 6 | 421 | 70 | 70 |
| `tripleslash.skl` [pvp] | 6 | 421 | 70 | 70 |
| `chargecrash.skl` [dungeon] | 2 | 141 | 70 | 70 |
| `tripleslashex.skl` [dungeon] | 6 | 421 | 70 | **10** |

> 官方注释（`level info`）："第 1 横排的内容是会生效的动态数据的数量，不计入该技能的第 1 级，所以可以算作第 0 级"——与实测 `C = v[0]` 一致。
>
> ⚠️ **表永远铺满 70 行**，`[maximum level]` 只是「能买到第几行」。TP 技能只有 10 级，但表里仍有 70 行。复刻时按 `min(maximum_level, growtype_max, 70)` 截断。

`tripleslash` 的 6 列语义（对照 `[level property]` 的 16 个占位符，分成「3 连斩组(0/1/2 列)」与「5 连斩组(3/4/5 列)」，每组又是 `%列 + 加值列`）：

| 列 | 含义（推定） |
|---|---|
| 0 / 3 | 斩击 1 的百分比系数（每下） |
| 1 / 4 | 斩击 1 的固定加值 |
| 2 / 5 | 与列 0/3 成对出现的第二分量（`level property` 里 `%` 与 `+` 交替消费） |

> 精确列语义**待验证**：需要拿 `[level property]` 的 16 个 `<int>` 顺序与 `-1/-2` 三元组逐一对齐（我已确认 tripleslash 只用列 0/1/2 与 3/4/5，且 `%` 配 `-1`、`+` 配 `-2`）。这套「列 = 参数槽、`level property` = 视图」的设计可直接照搬到 Godot：**数据表 + 描述模板** 两件套。

---

## 4. 主动 / 被动 / TP 的差别

### 4.1 主动（`[type] [active]`，1641 个）

有 `[consume MP]`、`[cool time]`、`[command]`；`.nut` 里提供 `checkExecutableSkill_*`（能否放）与 `checkCommandEnable_*`（指令是否响应）。

### 4.2 被动（`[type] [passive]`，1996 个）

没有 `[command]`/`[cool time]`；`[level info]` 的列是「属性加成」。这类技能**不改动作**，只改角色属性或挂 `[appendage]`。例：`lightswordmastery.skl` C=16（11 个 static 参数 + 多组加成）。

### 4.3 TP 强化技能（`[feature skill type] 1`）

以 `tripleslashex.skl`（强化 - 三段斬）为例，与本体成对：

```
[feature skill type]  1
[special purchase cost] 2          ← TP 点
[required level] 50
[pre required skill] 8 5           ← 本体技能 id 8，需本体 Lv5
[type] [passive]                   ← 注意：TP 技能是"被动"
[maximum level] 10
[growtype maximum level] 5 5 5 5 5 5
[basic explain ex]  增加三段斬的攻擊力，并增加2次連斬攻擊。
[explain ex]        增加2次連斬攻擊，但每次斬擊的基本攻擊力將減少15%。…
[special level up]  -1 0 % 8 -1 1 % 8 …   ← 每级 +8%
```

反向指针在本体里：`tripleslash.skl` 的 `[feature skill index] 143` → `TripleSlashEx.skl`。

**这是一个双向链接系统**：本体知道自己的强化（`feature skill index`），强化知道自己的本体与前置等级（`pre required skill`）。复刻 TP 系统只需这两个字段 + 一张 `(id → skl)` 表。

> DNF 的「TP 强化」在效果上是**覆盖本体的数值与行为**（`~ex.skl` 的 `[level info]` 才是生效值），`.nut` 里通常表现为「若学了 ex 则 `sq_GetSkillLevel(obj, 143) > 0` 走另一支」。所以 `~ex` 不是独立技能，是**本体的分支**。

---

## 5. 样例原文 + 解读

### 样例 A：`skill/swordman/tripleslash.skl`（主动技能全貌）

```
[name]
    三段斬
[purchase cost]
    15
[required level]
    15
[required level range]
    2
[type]
    [active]
[skill class]
    1
[maximum level]
    70
[growtype maximum level]
    50 50 50 50 50 50
[skill fitness growtype]
    0 1 2 3 4
[weapon effect type]
    [physical]
[consume item]
    3037 0 0
[command]
    (RIGHT) & (SKILL)
[dungeon]
    [consume MP]
        12 120
    [cool time]
        6000 6000
    [static data]
        600 -1000
    [level info]
        6 158 198 198 47 138 158 177 266 266 53 186 212 …
[pvp]
    [cool time]
        8000 8000
[feature skill index]
    143
```

**解读**
- `[growtype maximum level] 50 50 50 50 50 50` 而 `[maximum level] 70`：**总上限 70，但每个转职只能练到 50**（剩下的 20 级靠装备 `[skill data up]` 或活动加成堆）。这是 DNF 数值膨胀的接口，复刻时可不要。
- `[consume MP] 12 120` → Lv1 花 12，Lv70 花 120（线性插值）。`[cool time] 6000 6000` → 恒定 6 秒；PVP 分支单独给 8 秒。**同一技能在不同环境用不同数值块，这是 `.skl` 最值得抄的设计**。
- `[static data] 600 -1000`：两值，一正一负。可能是「前摇 600ms / 位移 −1000 单位」之类，⚠️ 待验证；但可以确定它是**留给引擎的裸参数槽**，不是通用语义。
- `[feature skill index] 143` 与 `[basic explain]` 里的「若剑魂已学 Lv5 以上的[太刀精通]」互相印证：**跨技能条件只写在说明文本里**，没进数据。复刻时这类联动必须在 `.nut` 里硬写，或者在数据里补一个 `[condition]` 字段（推荐后者）。
- `[command] (RIGHT) & (SKILL)`：`&` 表示「按住方向同时按技能键」。`[command]` 是一套小 DSL，能被 `.key`（APC 输入宏）复用 —— 这就是为什么 APC 能"像人一样"放技能。

### 样例 B：`tripleslashex.skl`（TP 与本体成对）

见 §4.3 摘录。**解读**：`[basic explain ex]`/`[explain ex]` 是**独立字段名**，不是 `[explain]` 的重复键——说明导出/解析层把 `ex` 后缀当**同一个字段名的一部分**，而不是 DNF 的重复键机制。这会影响你写解析器时的字段白名单。

### 样例 C：`lightswordmastery.skl`（被动 + 文本里藏规则）

```
[type]
    [passive]
[growtype maximum level]
    0 1 0 0 0 30
[skill fitness growtype]
    1
[explain]
    若技能達到Lv3以上，使用[連突刺]則可以出現光劍氣; …
    若技能達到Lv5以上，使用[三段斬]則可以進行5次斬擊，且最後一擊還可以浮空敵人。
[static data]
    3 5 9 7 2 500 1500 0 0 1000 5000
[level info]
    16 24 6 110 358 210 …
```

**解读**
- `[growtype maximum level] 0 1 0 0 0 30`：仅 growtype 1（剑魂）可学 1 级，growtype 5 可学 30 级 —— **同一个被动在不同转职下强度不同**，且 `[skill fitness growtype] 1` 只允许 growtype 1 学。这两个字段含义不同：前者是「能练到几级」，后者是「能不能学」。**必须两个都判**，否则会放行不该能学的角色。
- `[static data]` 11 值：被动技能的参数槽又是另一套语义（`3 5 9 7 2` 很像「各级解锁的阈值 Lv3/5/9/7/2」，后面 `500 1500 0 0 1000 5000` 像倍率/概率）。
- `[explain]` 文本里出现「Lv3 以上解锁光剑气」「Lv5 以上三段斩变 5 连斩」——这些是**真实的技能联动逻辑，但只以自然语言存在**。这是 PVF 体系最大的"非数据化"缺陷，也是复刻时你必须自己补数据字段的地方（建议加 `[unlock condition]`）。

---

## 6. 系统联动

```
chr [skill] id lv ──┐
growtype 时授予     ├──▶ 已学技能表 ──▶ .skl 数值（按角色等级/技能等级取 level info 行）
技能书/SP 购买      ┘                      │
                                          ├─▶ [consume MP] / [cool time] → 战斗资源系统（04）
                                          ├─▶ [level info] 列 → 伤害系数 → 合并 .atk（04）
                                          ├─▶ [level property] → 技能面板 UI（09-UI 章）
                                          └─▶ .nut checkExecutableSkill_* → 状态机 → .ani → 帧事件 → 判定框

equ [skill data up] n ──▶ 技能等级 +n（不减 MP/不占 SP，纯加成）
apd [string data] (job)(skillId)[level] % v ──▶ 技能攻击力 % 加成
dgn [no fatigue] / 副本内技能限制（见 07）
```

**SP / TP 双资源**：`[purchase cost]` 花 SP，`[special purchase cost]` 花 TP。本版本 TP 只出现在 `~ex` 技能上。

---

## 7. 复刻时必须实现的最小集

### M1 必须

1. **`SkillDef` 资源**：id、name、name2、图标、`type`(active/passive)、`max_level`、`growtype_max[6]`、`fitness_growtype[]`、`purchase_cost`、`required_level`、`pre_required_skill`、`feature_skill_index`、`command`。
2. **`level_info` 解码器**：`C = v[0]`，`row(level) = v[1 + (level-1)*C .. ]`。一行代码的事，但不实现就取不到数值。
3. **`level_property` 渲染器**：`<int>` 占位符 + `(type, col, mult)` 求值。**不要**手写技能描述。
4. **技能等级 → 数值的取值函数**，含三条截断：`min(max_level, growtype_max[growtype], 70)`。
5. **主动技能的执行链**：指令/按键 → `can_use`（等级、MP、冷却、前置）→ 进入状态 → 播动画 → 帧事件开判定 → 结算 → 进冷却。
6. **冷却与 MP**：`[cool time]`（毫秒）+ `[consume MP]`（两端插值）。PVP 分支可先不做，但**数据结构要预留**。

### M2 应当

7. **TP 双向链接**：`feature_skill_index` ↔ `pre_required_skill`，效果 = 覆盖本体数值 + 解锁额外段数。
8. **`[command]` DSL**：`(方向)&(键)`、`(A),(B),(C)` 两种组合子。**这是格斗游戏手感的核心**，且能直接被 APC 复用（见 06 的 `.key`）。
9. **被动技能 = 属性修饰器**：不要做成"特殊职业分支"，做成 `Modifier { stat, op(add/mul/percent), value_per_level }` 列表。
10. **文本规则外置**：把 `[explain]` 里"Lv5 以上…"转成 `[unlock condition]` 数据字段，别让策划写死在代码里。

### M3 可后做

11. `[static data]` 的完整语义（先把主动技能的 2 值当「前摇 ms / 位移」试）。
12. `[durability decrease rate]`、`[auto cooltime apply]`（耐久系统整体可延后）。
13. `[death tower]` / `[warroom]` 空分支（只留结构）。
14. `[command customizing]`（改键 UI）。

### 明确不要抄的

- `[growtype maximum level]`（50）与 `[maximum level]`（70）的错位——这是道具/活动堆等级的产物。
- 70 行铺满的 `level info`（我方可用「实际最大等级」行数，省内存）。
- `[skill class]` 0..5 的分类（本版本语义已退化，实测分布与玩法无关）。

---

## 8. 待验证清单

| # | 问题 | 怎么验证 |
|---|---|---|
| 1 | `[required level range]` 是升级步长还是浮动范围 | 取一个 20 级技能查 SP 表/技能面板截图对照 |
| 2 | `[static data]` 每类技能的长度与语义 | 按 `[type]`×`[skill class]` 分组统计后与 `.nut` 里 `sq_GetSkillStaticData` 式调用对照 |
| 3 | `[level info]` 6 列在 tripleslash 各是什么 | 用 `[level property]` 的 16 个占位符 + `-1/-2` 顺序反解（已知只用列 0/1/2 与 3/4/5） |
| 4 | `.lay [etc motion]` 下标是否全局唯一 | 已验 swordman 281 项、257→`tripleslashbsattacka_body.ani` ✅；抽 3 个职业再验 |
| 5 | `%s` 展开成 `equipment/character/<job>/growtype/<variation>` 的确切规则 | 用 `weaponmaster.equ [layer variation] 50 weaponmaster` + 实际文件路径对齐 |
| 6 | ATTACKINFO 常量 149 对应哪个 `.atk` | 在 `character/swordman/attackinfo/` 里按注册顺序/`attackinfo.lst` 对齐 |
| 7 | 玩家技能为何完全没有 `.act` | 已确认 8 个 `.act` 里 1 个属 character；需要读 `IRDSQRCharacter.pushState` 的引擎侧语义（不在 PVF 内，属已知断点） |
