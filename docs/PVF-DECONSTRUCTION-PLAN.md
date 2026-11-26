# PVF 架构拆解与复刻路线图

> 目标：把 DNF 的角色 / 怪物 / AI / 技能 / 道具 / 碰撞 / 伤害 / 手感，拆成**可执行的规格**，
> 然后在 Godot 里按「垂直切片」逐块复刻。数值后续可调，但**原有结构与相互关系要摸清**。
>
> 配套文档：[NPK-FRAME-BYTES.md](NPK-FRAME-BYTES.md)（图像层，已完成）、
> [NPK-FORMAT.md](NPK-FORMAT.md)、[GODOT-MIGRATION.md](GODOT-MIGRATION.md)（资产层迁移）。
>
> 本文只写「做什么、什么顺序、怎么验收」，不写具体字段含义（那些在字段词典里，见 §9）。

---

## 0. 先给结论：PVF 到底是什么，能拿到什么

**PVF 是一个「文本文件的归档包」，不是二进制数据表。**

`Script.pvf`（sf115 = 923 MB）解包后是几万到十几万个**纯文本**文件，形如：

```text
[ATTACK BOX] -12 -7 -12 28 14 28        // 攻击盒大小
[DAMAGE BOX] -21 -10 -5 76 10 70        // 受击/伤害盒
[DELAY] 70                              // 帧持续时间(ms)
[IMAGE] `Monster/Golem/PassiveObject/GolemBullet.img` 0   // 图像路径, 帧号
```

所以「拆 PVF」在技术上不难，难的是**量**和**语义**：37 种扩展名、6610 个 `.atk`、
上百个 `.lst` registry、以及一套只有官方注释文档才讲得清的**触发器/行为系统**。

### 能静态拿到的（数据层，100% 可拿）

| 类别 | 载体 | 例子 |
| --- | --- | --- |
| 角色基础属性 | `.chr` | `[HP MAX] [physical attack] [move speed] [jump power]` |
| 成长/转职 | `.chr` 的 `[growtype 1..3]` | 每级成长值 |
| 动作与帧 | `.ani` | `[IMAGE] [IMAGE POS] [IMAGE RATE] [IMAGE ROTATE] [RGBA] [DELAY]` |
| **碰撞盒** | `.ani` 每帧 | `[ATTACK BOX] x y z w h d`（**3D 盒，6 个数**） |
| **受击盒** | `.ani` 每帧 | `[DAMAGE BOX] x y z w h d` |
| **攻击载荷** | `.atk` | `[damage] [damage bonus] [absolute damage] [weapon damage apply] [ignore defense]` |
| 元素/异常 | `.atk` | `[elemental property]` + `[fire/water/dark/light element]`；`[active status]` + `[burn] [bleed] [stun] [slow] [curse] [hold]` |
| 行为状态机 | `.act` | `[MOTION] [TRIGGER] [LIMIT] [WHICH] [IF] [ON DAMAGE] [BEHAVIOR]` |
| 怪物 | `.mob` | 属性、AI 引用、掉落、召唤 |
| AI | `.ai` / `.aic` / `.key` | 目标选择、优先级、动作表 |
| 技能 | `.skl` | `[level info]` 逐级数值、`[static data]`、冷却、命令 |
| 脚本 | `.nut` | Squirrel 源码（真正的「程序逻辑」） |
| 道具/装备 | `.equ` / `.stk` | 属性、强化、套装、使用效果 |
| 地图/副本 | `.map` / `.dgn` | 出生点、刷怪表、通关条件、掉落 |

### 静态拿不到的（必须另找来源）

- **伤害公式本体**（攻击力 × 技能倍率 × 防御减免 × 元素 × 暴击 …）——不在 PVF 里。
- **命中判定顺序与优先级**（多盒重叠、无敌帧、抓取、浮空重置）——在 `DNF.exe` 里。
- **状态机推进的时间基准**（`[DELAY]` 与实际帧率、硬直、取消窗口）——引擎行为。
- **网络同步与 PVP 修正**——服务端。

> 一句话：**PVF 给你「输入」，引擎给你「规则」。** 复刻的准确度上限由「规则」的重建程度决定。

---

## 0.5 本轮实测更新（2026-11-05，P0 已完成）

**自研 PVF 解包器已跑通**，不需要 pvfUtility / Windows：`tools/pvf_unpack.py`（纯 Python）。
格式细节与真实字节见 [PVF-FORMAT-BYTES.md](PVF-FORMAT-BYTES.md)，这里只记对路线图有影响的结论。

| 事项 | 结果 |
| --- | --- |
| 容器解密 | ✅ 56B 头 + 加密目录树 + 逐文件解密，全链路自洽（dirTree 能耗到尾部 2B 填充） |
| 文档节点树 | ✅ 抽样 3000/3000 解析成功，输出与官方注释样例同构（`[TAG]` 缩进文本） |
| `.ani` 二进制 | ✅ sf85 209,635 个里 209,309 个精确走完（99.84%）；sf115 1,058,561 个里 1,058,417 个（99.986%） |
| `.nut`（Squirrel） | ✅ **是纯文本源码**，可直接读，不需要反编译 ← 复刻游戏逻辑的最大利好 |
| `.als` | ✅ 是 Document（`[use animation]` 列表），新发现的第 3 类编码 |
| 中文字符串 | ✅ **直接可用**：三档语料的文档正文串（`stringtable.bin`）都是 big5 繁体，sf115 也能读出`極詣·劍影/劍神/黑暗君主`；⚠️ 只有独立 `.str` 语言表（ID→显示名）在 sf115 被写成 U+FFFD |

**三份语料的分工（重要）**

| 语料 | 大小 | 条目 | 特征 | 用途 |
| --- | --- | --- | --- | --- |
| `sf110.08/客户端/客户端神话8.0/Script.pvf` | 692 MB | 1,092,561 | 繁体中文(big5)完整、768,567 `.ani` | 老版对照 / `.str` 语言表备用 |
| `sf115/Script.pvf` | 923 MB | 1,460,792 | 内容最新、正文串 big5 完好、`.str` 语言表已损坏 | **唯一主语料**（内容+名称都能取） |
| `sf85/老牛DNF客户端/Script.pvf` | 206 MB | 370,666 | 韩文(cp949)完整、老版本 | 对照/回溯 |

> 推论（已实测纠正）：**不再需要跨包分工** —— sf115 一份就够，正文串（名字/技能名/怪物名）和内容都在里面。
> 早先"中文名从 sf110.08 取"的说法基于一个观察误差：当时只看了 `.chn.str` 语言表，没看 `stringtable.bin`。
> 编码判据也修正为：用 `stringtable.bin` 采样 + `errors="ignore"` + 重罚私用区字符（`-20×`），
> 否则 gb18030 会把 big5 字节解成"看着像汉字"的私用区垃圾并胜出。

## 1. 六层架构模型（拆解顺序就是自下而上）

```text
 L6 表现层    NPK 图像 + .ani 帧参数 + 音效/语音          ← 已解决(NPK-FRAME-BYTES.md)
 L5 脚本层    .nut (Squirrel) + 原生 API (IRDSQRCharacter…)  ← 逻辑的真正载体
 L4 行为层    .act 触发器/行为状态机                        ← 官方 1112 行注释文档
 L3 数据层    .chr .mob .skl .atk .equ .stk .map .dgn …     ← 37 种扩展名
 L2 索引层    .lst registry：ID → 路径；名称/文本表          ← 依赖关系的骨架
 L1 文本层    `[TAG] args // comment` 的 token 语法          ← 一切解析的地基
 L0 容器层    Script.pvf（二进制归档）                       ← 用现成工具，别自研
```

**关键判断：L0 不值得自己啃，L1/L2 必须自己写，L3 靠词典，L4/L5 是复刻的主战场。**

理由：L0 是纯粹的工程问题，已经有 pvfUtility（本机就有）、godof 等实现；而 L1/L2 的解析器决定了
你后面所有工具（依赖图、查询、导出、对比、热重载）的上限，必须自己掌握。

---

## 2. L4/L5 的分工：三套逻辑，别混为一谈

这是整个项目最容易走错的地方。DNF 的一个动作由**三套东西**共同决定：

| 层 | 载体 | 谁执行 | 复刻策略 |
| --- | --- | --- | --- |
| **行为层**（有没有这个动作、什么时候触发、打到谁） | `.act` 的 `[TRIGGER]`/`[BEHAVIOR]` | 引擎内置解释器 | **写一个 `.act` 解释器**（数据驱动，工作量可控） |
| **脚本层**（特殊技能的花式逻辑） | `.nut`（Squirrel） | 引擎内嵌 Squirrel VM | 二选一：嵌入 Squirrel VM 实现 `sq_*` 原生 API；或逐个转写 |
| **数值/物理层**（伤害数字、击退、硬直） | 无（引擎 C++） | DNF.exe | 只能「重建公式 + 实测校准」 |

实测证据（来自官方注释样例，见 §9 资料）：`.act` 里已经有一套相当完整的**条件-行为 DSL**：

```text
[TRIGGER]
  [LIMIT] 1              // 执行次数，0=无限
  [CHECK TIME] 1000      // 每 1000ms 检测
  [FRAME] 2 2            // 帧范围
  [ON DAMAGE]            // 事件：受击
  [CHECK STUCK] 1        // 是否硬直
  [IS MEET PROB] 60      // 概率
  [WHICH] [TARGET]       // 目标选择器（12 种）
  [IF] `变量` [=] `变量` [+] 数字 [/IF]
  [BEHAVIOR] … [/BEHAVIOR]
[/TRIGGER]
```

**推论：把 `.act` 的 DSL 实现出来，就能不写一行代码复刻大量怪物/道具/机关行为。**
这是投入产出比最高的一块，也是「怪物 AI 不用逐个手写」的前提。

`.nut` 则不同：它是**真代码**，一个技能一个脚本，调用几百个 `sq_*` 原生函数
（`sq_AddSetStatePacket` / `sq_CreateCNRDAnimation` / `CNSquirrelAppendage.sq_AppendAppendage` / …）。
逐个人工转写 Skill 不现实，**建议单独做一个「NUT 兼容层」子项目**（见 P5）。

---

## 3. 依赖关系怎么建（这是「摸清关系」的答案）

PVF 的引用有两种，必须分开建模：

### 3.1 `ID → 路径`：`.lst` registry

| registry 类型 | 例子 | 语义 |
| --- | --- | --- |
| 文件路径表 | `equipment/equipment.lst`、`monster/monster.lst`、`map/map.lst` | 数字 ID → PVF 内部路径 |
| 职业技能表 | `skill/swordmanskill.lst` | 按职业分桶的技能 ID |
| 名称表 | `itemname.lst`、`monstername.lst`、`skillname*.lst` | ID → 显示名（**不是路径**） |
| 数值表 | `aicharacter/operatingvalue.lst` | 分组/参数 |

**三条硬规则**（来自字段词典，会反复踩）：

1. 数字 ID **没有全局唯一语义**，必须先知道父块用的是哪张 `.lst`。
2. 同一个 ID 可以同时存在于多张表；同一路径可以被多个 ID 指向。
3. 名称表不能当路径表用；「未注册」不等于「孤儿」（可能被直接路径/动作链/脚本链引用）。

### 3.2 路径直接引用：字段级边

```text
.act  --[BASE ANI]/[SUB ANI]/[SUB ANI WITH XY]-->  .ani
.act  --[DEFAULT ATTACKINFO]------------------->  .atk
.ani  --[IMAGE] path frame-------------------->  NPK img 帧
.act  --[SOUND]/[SPEECH]---------------------->  音效标签 / .str
.skl  --state 注册 / skillIndex--------------->  .nut (sqr/…)
.mob  --ai 引用 / 掉落表---------------------->  .ai / .stk / .equ
.map  --spawn 表------------------------------>  .mob
.dgn  --地图列表------------------------------>  .map
.npc  --shop role----------------------------->  itemshop/*.shp → .equ/.stk
```

### 3.3 最终产出

一张**有向图数据库**（SQLite 或 JSONL），边带类型与字段来源，支持查询：

- 「这个技能用到哪些 `.ani`/`.atk`/图/音效？」（导出资产用）
- 「改这个 `.atk` 会影响谁？」（回归测试用）
- 「哪些文件是死数据？」（减量用）
- 「复刻一个技能需要哪些文件？」（垂直切片用）

**这张图是整个项目的神经系统**，P1 必须先做，后面所有工具都挂在它上面。

---

## 4. 数值与碰撞：怎么把「关系」摸清

### 4.1 静态可得（回答「原来是什么」）

| 问题 | 在哪 |
| --- | --- |
| 攻击盒多大 | `.ani` 每帧 `[ATTACK BOX] x y z w h d` |
| 受击盒多大 | `.ani` 每帧 `[DAMAGE BOX]` |
| 这个动作何时产生伤害 | `.act` 的 `[FRAME]` + `.ani` 的 `[DELAY]` 累积时间 |
| 打多少 | `.atk` 的 `[damage]`/`[damage bonus]`/`[absolute damage]` + `.skl` 的 `[level info]` |
| 是否吃武器 | `.atk [weapon damage apply] 0/1` |
| 元素/异常 | `.atk [elemental property]` / `[active status]` |
| 击退/浮空/硬直 | `.atk [damage reaction]` → `[damage]/[down]/[push aside]/[lift up]/[knuck back]` |

### 4.2 静态不可得 → 三条求公式路线（按可靠性排序）

| 路线 | 做法 | 成本 | 可靠性 |
| --- | --- | --- | --- |
| **A. 跑私服抓包** | 本机有服务端（`/mnt/e/dnf-sf/new-sf`，docker + MySQL）；起服→登录→打怪→抓包，把「输入属性 + 输出伤害」做成数据集，回归拟合公式 | 中 | **最高**：输出是引擎真实结果 |
| **B. 反编译客户端** | `DNF.exe` 66 MB，找伤害结算函数；配合 `TypeSquirrel` 的 API 名交叉定位 | 高 | 中高 |
| **C. 社区公式 + 实测校准** | 先用流传的公式搭骨架，再用路线 A 的数据集校准系数 | 低 | 中（系数会错） |

**建议：以 A 为主线**（它是唯一能给出「真实数字」的），B 只在 A 解释不通时定点使用，C 只做初值。

> 这一条决定了项目的可行性判断：**「完全摸清伤害关系」不是读 PVF 能得到的**，
> 必须建立「可复现的实验台」。所以 P3 的核心交付物不是公式，而是**实验台 + 数据集**。

---

## 5. TODO 总表（按优先级）

### P0 — 地基（阻断一切，1–2 周）

| # | 任务 | 产出 | 验收 |
| --- | --- | --- | --- |
| P0.1 | ~~拿到 PVF 导出~~ **✅ 已完成**：自研 `tools/pvf_unpack.py`（容器+Document+ANI+文本） | 可任意 `cat`/`extract` | 三档 PVF 全解，ANI 精确消费 ≥99.8% |
| P0.2 | **文本/文档双向序列化**（读已通，缺写回） | `parse_document` → 树/JSON；`write_document` 回二进制 | 1000 个随机条目 读出→写回→再读出 与原条目字节一致 |
| P0.3 | **语料清点** ✅ 已完成 | 各扩展名/版本/编码/异常报告 | `analysis/pvf/census.md`（三档 PVF：92/90/73 种后缀） |
| P0.4 | **编码与字符串表** ✅ 基本完成 | 自动判编码（big5/cp949/gb18030 打分） | sf110.08 显示「鬼劍士/劍魂/鬼泣」等正确繁体名 |

### P1 — 神经系统（1–2 周）

| # | 任务 | 产出 | 验收 |
| --- | --- | --- | --- |
| P1.1 | `.lst` registry 全量解析 ✅ 已完成 | `graph.sqlite: reg` 表，58 张表 / 171,325 条 | 解析规则 `dirname(lst)+'/'+value` 命中 100% |
| P1.2 | 字段级引用抽取 ✅ 已完成 | `graph.sqlite: edge` 表，2,589,988 条（path 119 万 / img 136 万 / id 3.5 万） | 覆盖 39.9 万 Document + 105.8 万 `.ani`；`.nut/.lua` 未建边 |
| P1.3 | 图分析工具 ✅ 已完成 | `tools/pvf_graph.py`（build/ani/idedges/idmap/report/query）+ `docs/PVF-DEPENDENCY-GRAPH.md` | 可回答「这个技能/怪物依赖哪些文件」；23 条人工核过的字段→注册表映射 |

### P2 — 垂直切片 1：一个人、一只怪、一次命中（2–3 周，**第一个能看的 demo**）

| # | 任务 | 产出 | 验收 |
| --- | --- | --- | --- |
| P2.1 | 演员装配：`.chr` + `.ani` + `[IMAGE]` → Godot 动画 | 站/走/跳/普攻可播 | 帧时序与 `[DELAY]` 一致 |
| P2.2 | `.act` 解释器（子集） | `[MOTION]` + `[TRIGGER]` 基础触发 | 官方样例可跑通 |
| P2.3 | **盒调试器** | 实时绘制 `[ATTACK BOX]`/`[DAMAGE BOX]`/坐标轴 | 与 PVF 数字逐帧一致 |
| P2.4 | 怪物装配 | `.mob` + `.act` + 基础 `.ai` | 怪能追、能打、能被打 |
| P2.5 | 命中判定 | 盒相交 + `.atk` 载荷 → 伤害占位数字 | 帧窗口与官方文档一致 |

> P2.3 这个调试器别省。**没有盒可视化，后面所有碰撞问题都会变成玄学。**

### P3 — 战斗数值（2–4 周，交付「实验台」不是「公式」）

| # | 任务 | 产出 |
| --- | --- | --- |
| P3.1 | 私服实验台：起服 + 抓包 + 数据集 | `analysis/pvf/combat-dataset/` |
| P3.2 | 公式假设 → 拟合 → 残差报告 | `docs/COMBAT-FORMULA.md`（标注置信度） |
| P3.3 | 元素/异常/防御/暴击/独立攻击/额外伤害 | 同上 |
| P3.4 | PVP 修正块 `[pvp]` | 同上 |

### P4 — AI（2–3 周）

| # | 任务 | 产出 |
| --- | --- | --- |
| P4.1 | `.ai`/`.aic`/`.key` 结构解析（目标选择、优先级、动作表） | 结构文档 + 解析器 |
| P4.2 | 把 AI 图翻译成 Godot 行为树 | 一种怪的完整 AI |
| P4.3 | APC / 守卫 / 召唤物 | 同 P4.2 |

### P5 — 技能与 NUT 兼容层（3–6 周，最重的一块）

| # | 任务 | 产出 |
| --- | --- | --- |
| P5.1 | `.skl` 结构（`[level info]` 列、`[static data]`、冷却、命令） | 技能数值表 |
| P5.2 | **决策点：NUT 兼容层**（嵌入 Squirrel VM + 实现 `sq_*` API）vs 逐技能手写 | 决策文档 + PoC |
| P5.3 | `sq_*` 原生 API 面清单（从 TypeSquirrel 定义反推） | API 清单 + 优先级 |
| P5.4 | 3–5 个技能垂直切片（普攻、位移、范围、抓取、buff） | 可玩 demo |

### P6 — 系统层（按需，4 周+）

地图/副本进出、刷怪表、掉落、背包、商店、任务、经济（金币/疲劳）、UI 布局（`.ui`/`.lay`/`.pos`）。

### P7 — 工具链（持续）

PVF 查询 CLI、依赖图可视化、热重载、**与官方数据的回归对比**（同一动作在两边导出的帧/盒/时序 diff）。

---

## 6. 第一个垂直切片的具体范围（建议从这里开始）

```text
剑士 .chr(基础属性 + growtype)
  └─ 站/走 .act → .ani → .img 帧
  └─ 普攻 .act(3 段) → .ani([ATTACK BOX]) + .atk([damage])
        └─ 命中 → 哥布林 .mob → .ani([DAMAGE BOX]) → 掉血/受击 .act
```

判据（做完就算成功）：

1. 能在 Godot 里操作剑士走动、普攻，**帧时序与 `[DELAY]` 一致**；
2. 攻击盒/受击盒在屏幕上可见且与 PVF 数值一致；
3. 打中哥布林能出伤害数字（公式可以是占位），能被击退/硬直；
4. 全链路数据**全部来自 PVF 解析**，没有硬编码常量。

这个切片打通后，横向扩展（更多职业/怪物/技能）就变成「填数据 + 补引擎规则」。

---

## 7. 里程碑

| 里程碑 | 内容 | 预估 |
| --- | --- | --- |
| M0 | PVF 导出 + 文本解析器 + 语料清点 | 1–2 周 |
| M1 | 依赖图（能回答「这个技能需要哪些文件」） | +1–2 周 |
| M2 | 垂直切片 1 可玩（P2） | +2–3 周 |
| M3 | 战斗实验台 + 公式初版（P3） | +2–4 周 |
| M4 | 一种怪完整 AI（P4） | +2–3 周 |
| M5 | 3–5 个技能（P5） | +3–6 周 |
| M6 | 一个小副本闭环（地图+怪+掉落+结算） | +3–4 周 |

> 全量复刻（全职业全技能全副本）不是「几个月」的量级，是「年」的量级。
> 所以策略必须是**先打通一条最窄的竖线，再横向摊开**，并且每一步都能独立验收。

---

## 8. 风险与「不要做」

| 风险 | 说明 | 对策 |
| --- | --- | --- |
| 规模误判 | 6610 个 `.atk`、上百 `.lst`、几万 `.nut` | 只做「垂直切片用到的那部分」，其余按需 |
| 公式不可静态获得 | 反复强调：PVF 只有输入 | 先建实验台，别在数据里找公式 |
| NUT 工作量黑洞 | 原生 API 几百个 | 先做 API 面清单与 PoC，再决策 |
| 版本差异 | sf85(2017) / sf115 结构不同（如 v1 IMG、PVF 头加密） | 固定一个语料为主，另一个做对照 |
| 工具链缺失 | 没有盒可视化、没有 diff、没有查询 | P2.3/P7 优先做工具 |

**明确不要做**：

1. 不要自己解 PVF 容器（pvfUtility 已经能用，把时间花在语义上）。
2. 不要试图「一次性解析全部 37 种类型」——按垂直切片需要的那几种逐个啃。
3. 不要在没建依赖图之前手工翻文件（会疯）。
4. 不要把「社区流传的公式」当事实写进文档，必须标注置信度与来源。
5. 不要 commit 任何游戏原始资产/脚本到仓库（只在本地私有环境使用）。

---

## 9. 现成的资料在哪（本机已确认）

这些是**这次调研最大的意外收获**，直接把「PVF 每个字段什么意思」的问题解决了大半：

### 9.1 字段注释字典（37 个，按扩展名）

`/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Options/PvfComments/*.json`
（`{"SchemaVersion","FileType","Comments"}` 结构；`act.json` 742 KB、`etc.json` 529 KB、
`equ.json` 301 KB、`stk.json` 286 KB、`mob.json` 210 KB、`ani.json` 150 KB、`skl.json` 80 KB …）

### 9.2 官方注释样例（真实 PVF 文本 + 中文逐行注释）

`/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Resources/OfficialAnnotationTranslation/`

| 文件 | 内容 | 价值 |
| --- | --- | --- |
| `actionsample.act.txt`（1112 行） | `.act` 触发器/行为系统**完整文档** | ★★★ 复刻行为层的圣经 |
| `animation.ani.txt` / `animationsamplebytool.ani.txt` | `.ani` 帧字段与盒 | ★★★ 碰撞层 |
| `attackinfosample.atk.txt` | `.atk` 伤害载荷 | ★★★ |
| `charactersample.chr.txt`（353 行） | `.chr` 全字段 + 成长 | ★★★ |
| `monstersample.mob.txt` / `newmonstersample.mob.txt` | `.mob` | ★★★ |
| `actionlibrary/*.act.txt`（jump/shake/throw/chocking/appendage…） | 现成动作库 | ★★ |
| `ai_doc/how to edit ai.txt` / `aic.txt` / `key.txt` | AI 编写方法 | ★★★ |
| `dungeonsample.dgn.txt` / `mapsample.map.txt` | 副本/地图 | ★★ |

### 9.3 领域知识库（pvfUtility 自带，面向 Agent 写成）

`/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Resources/AgentKnowledge/`

- `dictionaries/` 41 个（`monster-fields` 313 行、`dungeon-map-spawn…` 339 行、
  `stackable-fields` 239 行、`nut-runtime-api-boundary` 223 行、
  `attackinfo-payload-damage-element-activestatus-fields` 91 行 …）
- `encyclopedia/pvf-file-types/` 23 个（每类文件的百科，含 `lst-registry-topology`）
- `indexes/` 147 个（路由/边界账本，含大量「命中数」实测统计）
- `task-cards/` 45 个、`workflows/` 12 个

> 注意它的**边界声明**：这些词典明确写「不证明伤害公式/不证明实机行为」，
> 与我们 §4 的判断一致——它们给字段语义，不给规则。

### 9.4 其他

- `Options/ItemCodeHoverConfig.xml`：道具码悬浮说明配置
- `sf115/DNFGM包/PVF工具和读取代码教学/`：`如何查看单机地下城全代码以及如何替换PVF教学.mp4`（140 MB）
- `new-sf/`：服务端 docker + MySQL（P3 实验台的底座）

---

## 10. 复现与下一步

```bash
# 1) 看字段字典（任一扩展名）
python3 -c "import json;d=json.load(open('/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Options/PvfComments/chr.json',encoding='utf-8-sig'));print(d['FileType']);print(list(d['Comments'])[:20])"

# 2) 读行为系统文档
less '/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Resources/OfficialAnnotationTranslation/actionsample.act.txt'

# 3) 读知识库入口
less '/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Resources/AgentKnowledge/README.zh-CN.md'
```

**下一个动作（等确认）**：把 `Script.pvf` 导出成目录（P0.1），之后我就能写文本解析器、
建依赖图、并开始垂直切片。
