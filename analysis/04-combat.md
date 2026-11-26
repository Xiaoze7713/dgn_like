# 04 · 战斗体系（.atk / .ani 判定框 / 命中时序）

> 范围：一次攻击由哪些数据决定、伤害怎么算、命中后敌人怎么动、判定在什么时刻发生。
> 数据源：`export/text/**/*.atk`（18,877 个）、`.ani`（二进制，几何）、`etc/activestatustable.etc`、`monster/**/*.act`、`sqr/**/*.nut`。
> 相邻文档：技能等级→系数 → [03-skill.md](03-skill.md)；怪物属性 → [06-monster.md](06-monster.md)；`.act` 语法逐行 → [09-script-mechanics.md](09-script-mechanics.md)。
> 官方标签释义来源：`analysis/01-TAG-DICT.md` / `export/_meta/tagdict.sqlite`（`ext='atk'` 有 100 个标签被官方注释）。

---

## 0. 一句话结论

DNF 的一次攻击被**三个文件分工**，任何一处缺失都无法成立：

| 层 | 文件 | 负责 |
|---|---|---|
| **数值与语义** | `.atk` | 伤害类型、属性、倍率、命中反应（击倒/击退/浮空）、附加异常状态、命中表现 |
| **几何** | `.ani`（二进制，每帧） | 攻击盒 / 受击盒矩形，随帧变化 |
| **时序** | 玩家：`.nut` 状态机；怪物：`.act` 触发器 | 第几帧开判定、开多久、什么时候关 |

`.atk` **不含任何坐标**——这一点必须记住。查遍 18,877 个 `.atk` 也没有矩形字段；几何只在 `.ani` 里。所以：

- 「这个技能打多远」→ 看 `.ani`（尚未解码，P0.5）；
- 「这个技能打多疼、打飞多远」→ 看 `.atk`；
- 「这个技能什么时候打到人」→ 看 `.nut`/`.act` 的帧号。

---

## 1. `.atk` 字段表

`.atk` 是一张**扁平键值表**，枚举值用「子标签为空块」表达（`[attack type]` 下一行是 `[physic]`）。共 100 个被注释的标签，按用途分 7 组。

### 1.1 伤害类型与属性

| 字段 | 含义 | 取值 | 必填 |
|---|---|---|---|
| `[attack type]` | 伤害类型 | `[physic]` 物理 / `[magic]` 魔法 / `[ignore defense]` 无视防御 | ✅ |
| `[elemental property]` | 属性攻击 | `[no element]`(12,204) / `[fire element]` / `[water element]` / `[dark element]` / `[light element]` / `[ice element]` / `[lightning element]` / `[none element]` / `[no elemental]` | ✅ |
| `[weapon damage apply]` | 是否吃装备攻击力加成 | `1` 开启（16,596 个几乎全是 1）/ `0` 关闭 | ✅ |
| `[attack enemy]` | 敌伤判定 | `1` 开 / `0` 关（关闭后完全不打人） | ✅ |
| `[attack friend]` | 友伤判定 | `1` 开 / `0` 关（349 例） | ❌ |
| `[attack myself]` | 自伤 | `1`/`0` | ❌ |

### 1.2 伤害数值

| 字段 | 含义 | 取值 | 必填 |
|---|---|---|---|
| `[damage bonus]` | **伤害比率** | 整数百分点：`0`=100%、`20`=120%、`-15`=85%（11,039 例） | ❌ |
| `[absolute damage]` | 无视防御的固定伤害 | 整数（5,530 例） | ❌ |
| `[ignore defense]` | 无视防御 | 标记（190 例） | ❌ |
| `[ignore super armor]` | 无视霸体 | 标记（349 例） | ❌ |
| `[ignore weight]` | 无视重量（击退不受体重影响） | 标记（703 例） | ❌ |
| `[ignore diehard]` | 无视不死/濒死保护 | 标记（12 例） | ❌ |
| `[damage increase rate]` | 伤害增加比率 | 整数（93 例） | ❌ |
| `[monster damage rate]` / `[human damage rate]` / `[damage except human]` / `[fort damage rate]` | 对特定对象类别的倍率 | 整数 | ❌ |
| `[max target hit number]` | 单次最多命中目标数 | 整数，如 `1`（68 例） | ❌ |
| `[is hit number increasing]` | 命中数是否累加（多段技） | 标记 | ❌ |
| `[critical hit]` | 是否可暴击 | 标记（20 例） | ❌ |
| `[hp drain]` / `[mp drain]` | 吸血 / 吸蓝 | 整数（19 / 80 例） | ❌ |

### 1.3 命中反应（核心手感）

| 字段 | 含义 | 取值 | 必填 |
|---|---|---|---|
| `[damage reaction]` | 伤害判定类型 | `[none]` 无 / `[damage]` 有伤害 / `[down]` 伤害+击倒（另有 `[blow]` `[stuck]` `[bounce]`） | ✅（18,889 例） |
| `[attack direction]` | 攻击方向 | `[hit lift up]` 浮空(4,485) / `[hit horizon]` 平推(6,150) / `[hit down]` 击倒(3,566) | ✅（14,493 例） |
| `[push aside]` | **平推值** | 整数，`10` = 10%（16,051 例） | ❌ |
| `[lift up]` | **浮空值** | 整数，`10` = 10%（16,222 例） | ❌ |
| `[knuck back]` | 击退开关/力度 | `1` 开、`-1` 禁、>1 加强（官方例："改成 10，敌人会被一巴掌扇到地图边缘"） | ❌ |
| `[stuck]` | 命中率修正 | 正数**减少**命中、负数增加；`-10` = +10%；**`-1000` = 必定命中**（4,003 例） | ❌ |
| `[force hit stun time]` | 强制硬直时间 | 毫秒（374 例） | ❌ |
| `[stuck prob increase]` / `[human active status rate]` | 硬直概率/对人生效加成 | 整数 | ❌ |
| `[pvp]` | PVP 专用覆盖块 | 内含 `[push aside]`/`[lift up]` 等 | ❌ |

### 1.4 附加异常状态

`[active status]` 下挂子标签（3,608 例），取值是 5 个数字：

| 子标签 | 状态 | 出现次数 |
|---|---|---|
| `[burn]` | 灼伤 | 1,065 |
| `[bleeding]` | 出血 | 667 |
| `[lightning]` | 感电 | 573 |
| `[stun]` | 眩晕 | 567 |
| `[freeze]` | 冰冻 | 337 |
| `[poison]` | 中毒 | 318 |
| `[curse]` | 诅咒 | 117 |
| `[blind]` | 失明 | 88 |
| `[confuse]` / `[hold]` / `[sleep]` / `[stone]` / `[slow]` / `[armor break]` / `[weapon break]` / `[weakness]` | 混乱/束缚/睡眠/石化/减速/破甲/破武/虚弱 | 各 29~77 |

全局数值在 `etc/activestatustable.etc`：

```
[active status max level] 150
[active status duration]   20 0 7 0 20 0 15 0 0 7 0 10 20 20 0 0 0     ← 17 种状态的持续帧/秒
[active status power 1]    0.98 0.0 1.0 40.0 5.0 1500.0 …              ← 每级强度（34 个/行）
[active status power 2]    …（第二组强度，另一套口径）
```

### 1.5 表现

| 字段 | 含义 | 取值 |
|---|---|---|
| `[hit info]` | 命中表现 + 卡肉参数 | 4 项：打击类型（`cut`/`blow`/`burn`/`etc`/`mana burn`/`hit`/`slash`）+ 血效（`blood`/`no blood`/`noblood`）+ **命中停顿时间** + **受击延迟倍数**；两项填 `-1` 表示跟随武器子类型 |
| `[hit wav]` | 命中音效 | NPK 内音效名，如 `SUPLEX_CRASH`（14,666 例） |
| `[no blood]` | 无血效 | 数值对，如 `200 1.0` |
| `[hit check by screen pos]` | 按屏幕坐标判命中 | 标记 |

> `[hit info]` 的后两项就是**卡肉（hitstop）**参数。DNF 打击感的物理来源之一，复刻时不要漏。

---

## 2. 伤害计算管线（推定，逐项标注证据强度）

PVF 里**没有公式文件**——公式在引擎里硬编码。以下是能从数据字段反推的最大集合：

```
① 技能系数：skill_level_info 的 (百分比列, 加值列)   ← 03-skill §3
② 面板攻击力： chr 基础 + growtype 增量 + 装备 [physical attack] / [equipment physical attack]
              + 被动技能加成（.apd [string data] 的 % 加成）
③ 原始伤害 = ② × ①% + ①加值
④ × (1 + [damage bonus]/100)                     ← 官方：0=100%, 20=120%, -15=85%
⑤ × 属性克制系数（elemental property vs 目标抗性）
⑥ × 防御减免（除非 [ignore defense] / [absolute damage]）  ← 公式未知
⑦ + [absolute damage]（若存在，最后加）
⑧ × 情境倍率（[monster damage rate]、[human damage rate]、[damage increase rate]、暴击）
⑨ 角色侧再乘 [module damage rate]（模式倍率，PVP/战场/混沌）  ← 02-character §2.3
```

证据强度：

| 步骤 | 强度 | 依据 |
|---|---|---|
| ③④⑤ | **高** | `[damage bonus]` 官方注释明确"0=100%"；技能 `[level property]` 里 `% + 加值` 成对出现 |
| ⑦ | **高** | `[absolute damage]` 官方注释"无视防御的绝对伤害" |
| ⑥ | 低 | 防御减免公式不在 PVF；待实机反推 |
| ⑧⑨ | 中 | 字段存在且名字明确，但倍率组合顺序未知 |

> **复刻建议**：不要试图还原 DNF 的防御公式。用「攻击力 × 系数 − 防御×k」的线性式即可，手感差异远小于「判定框 + 硬直 + 卡肉」三项。

---

## 3. 受击反应：击退 / 浮空 / 击倒

三者是**同一个物理系统**的三个参数，由 `.atk` 决定：

| 玩家的攻击写成 | 敌人的反应 |
|---|---|
| `[attack direction] [hit horizon]` + `[push aside] 30` + `[knuck back] 1` | 沿 X 轴被推开，进入 `damage` 动作 |
| `[attack direction] [hit lift up]` + `[lift up] 75` | Y 轴上升，进入浮空动作（可被连招追打） |
| `[attack direction] [hit down]` + `[damage reaction] [down]` | 直接倒地，起身有无敌帧 |
| `[damage reaction] [none]` | 无硬直（多用于纯特效或持续伤害区域） |

力度换算：`[push aside]`/`[lift up]` 的 `10` = 10%，所以 `270` = 270%（`ashenfork.atk` 的 270/180 是"远距离大击飞"）。

敌人侧的抗性来自 `.mob`：

| 字段 | 含义 |
|---|---|
| `[stuckbonus on damage]` | **4 个数 = 2 组**：受**远程**攻击的硬直比率（最小/最大）、受**近战**攻击的硬直比率（最小/最大） |
| `[weight]` | 体重，影响击退距离与被浮空难度（`.atk [ignore weight]` 可绕过） |
| `[super armor]` | 霸体：受击不进入硬直（`.atk [ignore super armor]` 可绕过） |
| `[hit recovery]` | 硬直恢复速度 |

**这一层是 DNF-like 与普通横版 ACT 的分水岭**：同一个技能因为 `[attack direction]` 一个枚举值不同，就从"推开"变成"挑飞起连段"。复刻时必须把这三项做成**独立参数**而不是硬编码在技能里。

---

## 4. 命中判定时序

### 4.1 怪物侧：`.act` 的 `[FRAME]` 窗口

```
[TRIGGER]-1
    [FRAME] 21 21 [WHICH] [PLAYER] [CHECKUP] [IS OBJECT TYPE] [CHARACTER] [/IS OBJECT TYPE] [/CHECKUP]
    [CHECKED NO] [>] 0 [DO BEHAVIOR] [CHECKUP OBJECT] 1
[BEHAVIOR]-1
    [PULL APPENDAGE] 7 3 4000
[TRIGGER]-4
    [FRAME] 18 18 [DO BEHAVIOR] [ME] 4
[TRIGGER]-3
    [CHECK TIME] 100 [DO BEHAVIOR] [ME] 3
[BEHAVIOR]-3
    [ATTACKRECT] [RESET]
```

（出处：`monster/poongjintrainingroom/sarpoza/action/drain.act`）

**解读**
- `[FRAME] 21 21` = 在第 21 帧（到第 21 帧）触发一次；`[FRAME] a b` 是帧区间，区间内每帧都判。
- `[WHICH] [PLAYER]` 选目标集合，`[CHECKUP] [IS OBJECT TYPE] [CHARACTER]` 再加条件，`[CHECKED NO] [>] 0` 判命中数量。
- `[ATTACKRECT]` 是**判定框开关**（`[ON]`/`[OFF]`/`[RESET]`），配合 `[CHECK TIME] 100` 定时关闭 → 这就是"判定框只在某几帧存在"的实现方式。**矩形本身仍来自 `.ani`**。
- `[ON ATTACKSUCCESS]` 触发器在命中成功后执行（挂特效/吸血/生成被动对象），这是"命中反馈"的挂点。

### 4.2 玩家侧：`.nut` + 帧标记

玩家技能没有 `.act`，时序落在 `.nut`：

```
function onKeyFrameFlag_TripleSlash(obj, flagIndex)
{
    local substate = obj.getSkillSubState();
    if (substate == 1007) { obj.resetHitObjectList(); return true; }
    return false;
}
```

（出处：`sqr/character/swordman_jg/tripleslash/tripleslash.nut`）

- `onKeyFrameFlag_*` = **动画帧标记回调**：`.ani` 某一帧被打上 flag，引擎回调脚本。这是玩家侧"第 N 帧开判定/切子状态"的唯一钩子。
- `obj.resetHitObjectList()` = 清空已命中列表 → 多段攻击每段重新可命中（对应 `.atk [is hit number increasing]`）。
- 与命中相关的脚本 API（按调用次数）：`sq_SetCurrentAttackInfo`(2378)、`sq_SetCurrentAttackBonusRate`(2426)、`sq_GetCustomAttackInfo`(1844)、`sq_SetAttackBoundingBoxSizeRate`(519)、`sq_SetChangeStatusIntoAttackInfo`(224)、`sq_SendHitObjectPacket`(130)。

> **结论**：`.atk` 是"模板"，`.nut` 用 `sq_SetCurrentAttackInfo` 把它挂到当前动作上，再用 `sq_SetCurrentAttackBonusRate` 在运行时改倍率。同一份 `.atk` 可以被多个技能复用并各自调参——这是 DNF 战斗数据量能压到 18,877 份的原因。

---

## 5. 样例原文 + 解读

### 样例 A：`character/swordman/attackinfo/attack1.atk`（普攻第一下）

```
[damage bonus]
    -15
[attack type]
    [physic]
[weapon damage apply]
    1
[attack enemy]
    1
[elemental property]
    [no element]
[damage reaction]
    [damage]
[push aside]
    30
[lift up]
    75
[attack direction]
    [hit down]
```

**解读**
- `[damage bonus] -15` → 85% 伤害。**为什么普攻要打折？** 因为普攻的段数多、可无限循环，靠这个系数控制 DPS。这是"数值平衡靠倍率而不是靠改公式"的典型。
- `[push aside] 30` + `[lift up] 75` + `[hit down]`：既有平推又有浮空，但方向是"击倒"——三者不矛盾，`[attack direction]` 决定**最终进入哪个动作**，另两个决定**位移量**。
- `[weapon damage apply] 1`：吃装备攻击力（所以换武器直接改变普攻伤害）。
- 注意它**没有** `[hit info]`、没有 `[active status]`、没有 `[knuck back]` —— `.atk` 的所有字段除 `[attack type]`/`[damage reaction]` 外基本都可缺省，缺省 = 0/无。

### 样例 B：`character/mage/attackinfo/blackmantlehit.atk`（带异常状态的魔法攻击）

```
[attack type]
    [magic]
[elemental property]
    [dark element]
[damage reaction]
    [none]
[attack direction]
    [hit horizon]
[push aside]
    0
[lift up]
    150
[hit info]
    [blow]
    [no blood] 50 2.0
[hit wav]
    SUPLEX_CRASH
[active status]
    [blind] 0 0 0 0 0
```

**解读**
- `[damage reaction] [none]` + `[push aside] 0` + `[lift up] 150`：**不造成硬直但把人挑起来**——这是"控制型"攻击的写法（配合抓取/浮空连）。
- `[elemental property] [dark element]` 会与目标的 `[dark resistance]` 交互（鬼剑士暗抗 +20、光抗 −20，见 02）。
- `[hit info] [blow] [no blood] 50 2.0`：打击类型 blow、无血效、**命中停顿 50ms、受击延迟 ×2.0**。这两个数直接决定"打上去有多肉"。
- `[active status] [blind] 0 0 0 0 0` 五个 0 = 用默认强度/时长（真实数值查 `etc/activestatustable.etc`，按状态种类序号取行）。**所以 0 不等于"不生效"**，而是"用默认表"——这是最容易读错的一处。

### 样例 C：`character/swordman/attackinfo/ashenfork.atk`（击飞型）

```
[damage reaction]
    [down]
[push aside]
    270
[lift up]
    180
[attack direction]
    [hit down]
```

**解读**
- 270% 平推 + 180% 浮空 + 击倒。对照 `dashattackmultihit.atk` 的 `[push aside] 250 [lift up] 200 [knuck back] 1`（平推 250% + 浮空 200% + **开启击退**）——**差别只在一个 `[knuck back]`**：不写 `[knuck back]` 时位移量仍生效但不触发"击退"状态机（不打断敌人动作）。
- 这解释了 DNF 里"有的技能能把怪推走，有的只是把人打飞但位置不变"的手感差异。复刻时若把 `[push aside]` 直接当速度用，就会丢掉这个区别。

---

## 6. 系统联动

```
.skl [level info] 系数 ─┐
.chr 属性 + .equ 攻击力 ┼─▶ 面板攻击力 ──▶ 伤害公式（§2）
被动 .skl / .apd 加成 ──┘                        │
                                                 ▼
.ani 攻击盒（每帧）──┐                    ┌─ 伤害数字
.act [ATTACKRECT] ───┼─▶ 命中检测 ──▶ 目标 ─┼─ 硬直/击退/浮空（.atk reaction）
.nut 帧标记 ─────────┘         │           ├─ 异常状态（activestatustable）
                               │           └─ 卡肉（hit info 后两项）
                               ▼
                        .mob 抗性/体重/霸体（06-monster）
```

- **与技能**：`.atk` 被 `sq_SetCurrentAttackInfo` 挂载，倍率可运行时改（`sq_SetCurrentAttackBonusRate`）。
- **与装备**：`[weapon damage apply]` 决定是否吃装备攻击力；`[separate attack]` 是独立的攻击力加算。
- **与状态**：`.atk [active status]` 只是"我要挂这个状态"，真实强度在 `etc/activestatustable.etc`，由 `.apd` 承载效果实例。
- **与怪物**：`.mob [attack info]` 指向它自己的 `.atk`；`[stuckbonus on damage]` 反过来修正玩家打它的硬直。

---

## 7. 复刻时必须实现的最小集

### M1 必须

1. **`AttackDef` 资源**：`damage_bonus`、`attack_type`(physic/magic/ignore_defense)、`element`、`weapon_damage_apply`、`reaction`(none/damage/down/blow)、`direction`(hit_down/hit_horizon/hit_lift_up)、`push_aside`、`lift_up`、`knock_back`(bool/强度)、`max_targets`、`hit_stop_ms`、`hit_delay_mult`、`hit_wav`、`status_effects[]`。
2. **判定框时间线**：每个攻击动作有 `[start_frame, end_frame]` 的激活窗口 + 每帧矩形。**Godot 实现**：`Area2D` 只在窗口内 `monitoring = true`，或直接每帧 `intersect_shape` 手动查询（更可控，能实现"每帧不同矩形"）。
3. **三段反应状态机**：`damage`（短硬直）/ `lift`（浮空，可被追打）/ `down`（倒地 + 起身无敌）。三者互斥且有优先级。
4. **命中去重**：一次攻击对同一目标只命中一次，多段技能每段 `resetHitObjectList`。这是"多段技能每段都能打到"的唯一实现方式。
5. **异常状态表**：状态枚举 + 每级强度表 + 持续时间表（可先只做 3 个：burn/stun/freeze）。

### M2 应当

6. **`knuck back` 与 `push aside` 分离**：前者是"打断动作并推走"的状态机，后者只是位移量。**不要合并成一个"击退力"**。
7. **卡肉（hitstop）**：`[hit info]` 后两项，实现为全局/局部 `freeze_frame`。
8. **命中率**：`[stuck]` 的负数加成 + `-1000` 必中。DNF 的命中率公式在引擎侧，本作可用 `命中率 = clamp(基础 + stuck加成)`。
9. **属性克制表**：4（+2）属性 × 6 抗性（含负抗）的乘算。
10. **重量影响击退**：`push_distance ∝ push_aside × (攻击者重量/目标重量)`，重量字段两边都有（`.chr [weight]` / `.mob [weight]`）。

### M3 可后做

11. `[hit info]` 的打击类型分支（cut/blow/burn…）——只需音效与特效分流。
12. `[monster damage rate]` / `[human damage rate]` 等场景倍率。
13. `[absolute damage]`、`[hp drain]`、`[mp drain]`。
14. `[pvp]` 覆盖块（结构先留，数值后填）。

### 明确不要抄的

- `.atk` 里的历史拼写错误变体：`[hit horiozn]`(8)、`[hit horizono]`(4)、`[hit horizoon]`(1)、`[hit horizonal]`、`[damage bouns]`(3)、`[damge]`(2)、`[warter element]`(1)。**解析器要容错，实现时不要跟**。
- `[piercing rate]`、`[hit stun time only attack OverLap dis Rate]`：官方无注释（0 说明），属知识缺口，别猜。

---

## 8. 待验证清单

| # | 问题 | 怎么验证 |
|---|---|---|
| 1 | `.ani` 里的盒子格式与帧结构 | 已验证头部 `u16 ver=0x000a, u16=1, u32 pathLen=56, 路径(含 %04d 图集索引)`，之后是重复的 2 字节 tag 记录；`0e 00` 后跟 4×int32（如 `-30,-5,-6,30`）疑为矩形 `(left,top,right,bottom)`。完整解码属 P0.5 |
| 2 | 防御减免公式 | PVF 内无；需实机数值回归 |
| 3 | `[active status]` 5 个数的位序 | 用 `activestatustable.etc` 的 17 项 duration 表 + 状态种类序号对齐 |
| 4 | `[hit info]` 第三/四项是否真是 ms / 倍数 | 官方注释："命中短暂停顿时间和受击延迟倍数，-1 跟随武器子类型" —— 已确认语义，单位待实测 |
| 5 | `[static data]` 里的攻击相关槽位 | 见 03-skill §8 |
| 6 | `.atk` 复用关系（哪些技能共用同一份） | 用 `export/_meta/refgraph.sqlite` 查入边最多的 `.atk` |
| 7 | `[is hit number increasing]` 与 `resetHitObjectList` 的对应 | 找一个多段技能同时有两者，比对命中次数 |
