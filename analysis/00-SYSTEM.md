# 00 · DNF 设计体系总纲

> **这份文件是什么**：把 `docs/ANI-FORMAT.md`、`analysis/02`–`09`、`docs/GODOT-EVAL.md` 六份专家产出编成一套能顺着读下去的体系，并把专家之间不一致的地方**回原始数据核对**、写明以哪个为准（§5）。
> **读者**：想搞清「这个游戏的设计是怎么只用文本表达的」的人，以及要照着它写 Godot 4 代码的人。
> **本文不重复专家文档的字段全表**：字段清单在 02–08，格式细节在 ANI-FORMAT / PVF-FORMAT，引擎选型在 GODOT-EVAL。本文只做三件专家不做的事：**画链路、连引用、下判断**。
> 数据源：`export/text/`（1,460,792 个文件，6.2 GB 可读导出）+ `export/_meta/index.sqlite`（路径/大小/后缀）+ `export/_meta/tagdict.sqlite`（官方标签注释）。
> 本篇所有「实测」数字都来自 `export/_meta/index.sqlite` 或本人本轮直接 grep/解析，与专家原文有出入的已单列在 §5。

---

## 0. 先看这张地图（三十秒版）

DNF 的逻辑是**四张网叠在同一个 ID 空间上**：

```
         ┌──────────────── 数据网（谁存在、有多强）───────────────┐
         │ .chr .mob .equ .stk .skl .qst .cre .obj .apd  +  *.lst 注册表 │
         └───────────────┬───────────────────────────────────────┘
                         │ 给出 id 与数值
         ┌───────────────▼──── 编排网（什么时候做什么）───────────┐
         │ 怪物/物件：.act（章 + 编号实例 + 触发器）                 │
         │ 玩家/宠物技能：.nut（Squirrel 回调 + 状态机表）            │
         │ 怪物行为决策：.ai（条件树）                               │
         └───────────────┬───────────────────────────────────────┘
                         │ 只发两类东西：一个动画下标 + 一个攻击信息下标
         ┌───────────────▼──── 帧网（每一帧长什么样、打到哪）───────┐
         │ .ani v6：帧 → (img 引用, x/y, DELAY, ATTACK BOX, DAMAGE BOX) │
         │ .als：叠加层 .ani 列表（纯表现）                          │
         └───────────────┬───────────────────────────────────────┘
                         │ 命中瞬间读出攻击属性
         ┌───────────────▼──── 结算网（打上去什么效果）─────────────┐
         │ .atk：100 个标签（伤害倍率/属性/硬直/位移/异常状态）        │
         │ 伤害公式本身：不在 PVF（客户端/服务端硬编码）               │
         └───────────────────────────────────────────────────────┘
```

四张网之间**没有嵌套结构，只有下标和路径**。这句话是理解 DNF 数据体系的钥匙：它能被 2005 年的 PVF 解析器在 2005 年的机器上读完，代价是语义全靠"约定"承载——约定不写在数据里，写在客户端代码里（§1.3、§4.2）。

**规模感**（`index.sqlite` 实测，2026-10）：

| 层 | 后缀 | 数量 | 备注 |
|---|---|---:|---|
| 帧网 | `.ani` | **1,058,561** | 占全库 72%；其中 `equipment/` 下 547,770（武器/时装外观） |
| 帧网（叠加） | `.als` | 77,490 | 只有一个用途：动画层叠加（§4.2） |
| 编排网（怪物/物件） | `.act` | 77,511 | `monster/` 53,041 + `passiveobject/` 24,107，其余 363 |
| 编排网（玩家） | `.nut` | 2,489 | 角色**没有** `.act`（character/ 下仅 1 个 140B 的 booster_particle） |
| 编排网（怪物决策） | `.ai` | 13,969 | 每只怪 4 个（Event/DestinationSelect/Action/MoveMethod） |
| 结算网 | `.atk` | 18,877 | 无任何几何字段（§5 #1 已核） |
| 数据网（装备/道具） | `.equ` / `.stk` | 108,645 / 28,794 | 注册表 102,329 / 32,170 条 |
| 数据网（怪/图/关卡） | `.mob` / `.map` / `.dgn` | 4,042 / 5,800 / 625 | 怪：基表 100 行覆盖 4,042 只 |
| 数据网（任务/技能/外观） | `.qst` / `.skl` / `.lay` | 3,852 / 4,005 / **13** | `.lay` 只有 13 个——全游戏外观与技能动画的枢纽 |
| 注册表 | `.lst` | 58 | id → 路径的**唯一**权威入口 |
| 二进制 | `.img` | 在 NPK 里，不在 PVF | 33 GB 素材，另行处理 |

> **导出名的两个坑（本轮踩过）**：`export/text/` 里**文本文件被追加 `.txt`、二进制被追加 `.bin`**（`boom.act` → `boom.act.txt`，`boom01.ani` → `boom01.ani.bin`）。`grep -r` 默认把含 NUL 的 `.nut.txt` 当二进制跳过——这会静默漏掉约 3/4 的匹配（§5 #3 的根因）。

---

## 1. 分层架构

### 1.1 五层，不是四层

专家 09 给的是四层（实体声明 → 动作编排 → 判定与属性 → 表现）。那是**从数据文件出发**的分法，对写解析器够用；但要理解"机制如何表达"，必须把**不在 PVF 里的那一层**也画出来，否则会误以为 PVF 是完整的。

```
第 5 层  服务端/运营层   ← 不在 PVF（伤害最终裁决、掉落校验、唯一兽、排行、活动开关、PK 平衡）
   ▲ 只通过"发包"接口接触：客户端算表现，服务端算结果
第 4 层  表现层          ← .ani(帧图) / .als(叠加) / .img(NPK) / 音效名 / [FLASH SCREEN] / [CENTER MSG]
   ▲ 只读
第 3 层  判定层          ← .ani 帧内 0x0f ATTACK BOX / 0x0e DAMAGE BOX（几何）
   │                        + .atk（属性）+ .nut/.act 的开关指令
   ▲ 每帧驱动
第 2 层  编排层          ← .act（怪物/物件）/ .nut（玩家/宠物）/ .ai（决策）
   ▲ 按 id 与下标取
第 1 层  数据层          ← .chr .mob .equ .stk .skl .qst .cre .obj .apd + .lst 注册表 + 各 .etc 总表
   ▲ 由引擎加载
第 0 层  引擎层          ← 不在 PVF：PVF 解析器、状态机执行器、Squirrel/条件树 VM、伤害公式、
                            命中检测、UI 控件句柄、输入映射、.atk 整数索引表（§5 #2）
```

**关键判断：DNF 真正"硬"的逻辑几乎都在第 0 层和第 5 层。** PVF 负责的是"参数"和"时序",不是"规则"。所以复刻时最容易犯的错是：以为照着 PVF 抄完就有手感——其实手感来自第 0 层的 tick 顺序与第 5 层的公式常数，两者都得自己定。

### 1.2 每一层由什么承载（照着实现用这张表）

| 层 | 文件类型 | 决定什么 | 关键字段（只列承重的） | 被谁引用 |
|---|---|---|---|---|
| 1 数据 | `.chr` | 职业 1 级基础值 + 每级增量 + 6 个转职分支 | `[growtype N]`、`[module damage rate]`、`[skill]`、`[weight]` | 客户端建角色、`character.lst`（仅 11/13） |
| 1 数据 | `.mob` | 怪物面板 + 动作槽 + 攻击槽 + AI 槽 | `[attack action]`（列表）、`[attack info]`（列表）、`[cooltime]`（列表）、`[ai pattern]`、`[ability category]` | `monster.lst`、`.map [monster]` |
| 1 数据 | `.equ`/`.stk` | 物品基类 + 两套子类 | `[grade]`/`[rarity]`/`[icon mark]` 三套独立编码、`[if]/[then]`、`[skill data up]` | `equipment.lst` / `stackable.lst` |
| 1 数据 | `.skl` | 技能的等级数据、能否学、怎么放 | `[level info]`（首值=列数）、`[level property]`（来源,索引,倍率）、`[required level range]` | `skill/*.lst`、`pushState`、`.cre [skill info]` |
| 1 数据 | `.qst` | 任务：一个枚举 + 变长参数 + 一条全局经济表 | `[type]`、`[int data]`、`[sub type]`、`[difficulty]`（单字符） | `quest.lst`（仅 339/3,852） |
| 1 数据 | `.twn`/`.dgn`/`.map`/`.til` | 城镇 → 关卡 → 房间 → 地砖 四层引用 | `.dgn [greed]`（2 字符=出口位掩码）、`[map specification]`、`.map [monster]` 10 字段 | `town.lst`/`dungeon.lst`/`map.lst` |
| 2 编排 | `.act` | 怪物/物件：**章 + 编号实例 + 触发器** | `[MOTION][BASE ANI]/[SUB ANI]`、`[TRIGGER][FRAME] a b`、`[DO BEHAVIOR][ME] n`、`[SET ACTION][ATTACK] n [NOW]` | `.mob [attack action]`、`.map [passive object]`、`.obj` |
| 2 编排 | `.nut` | 玩家/宠物：Squirrel 回调 + 状态机注册表 | `pushState(job,nut,name,stateId,skillId)`、`onSetState_*`/`onProc*`/`onKeyFrameFlag_*`/`onEndCurrentAni_*`、`sq_SetCurrentAnimation(idx)`、`sq_SetCurrentAttackInfo(atk)` | `*_load_state.nut`、技能 `.skl` |
| 2 编排 | `.ai` | 怪物决策：条件树 DSL | `[think]`/`[true]`/`[false]`/`[return]`、`[last result]` | `.mob [ai pattern]` |
| 3 判定 | `.ani` | 帧时间轴 + 帧内判定盒 | `0x0c DELAY`(ms)、`0x0f ATTACK BOX`、`0x0e DAMAGE BOX`（6×i32）、`0x0d DAMAGE TYPE`、`0x10 字符串名` | `.act [BASE ANI]`、`.nut`、`.lay [etc motion]`、`.als` |
| 3 判定 | `.atk` | 命中后的效果参数（无几何） | `[damage bonus]`、`[attack type][physic]/[magic]`、`[damage reaction]`、`[push aside]/[lift up]/[knuck back]`、`[hit info]` 四元组、`[active status]` | `.mob [attack info]`、`sq_SetCurrentAttackInfo`、`.cre [attack info]` |
| 4 表现 | `.als` | 叠加层动画列表（**不是**动作别名） | `[use animation]` 7292 / `[none effect add]` 4299 / `[add]` 2751 / `[create draw only object]` 538 | `.act [SUB ANI]`、`.nut` |
| 4 表现 | `.lay` | **只有 13 个**：`[xxx motion] %s/Yyy.ani` + `[etc motion]` 平坦下标表 | `%s`（由 `[layer variation]` 展开）、`[etc motion]` 276 项（剑士） | `.equ [equipment ani script]`、`CUSTOM_ANI_*` |

### 1.3 PVF 里**没有**的东西（边界清单，比有什么更重要）

| 缺失项 | 证据 | 复刻时的后果 |
|---|---|---|
| 伤害公式本身 | 全部 `.atk` 只有倍率与效果，无公式；`etc/` 无 damage*.etc | 必须自己定公式；DNF 的防御/等级差/属强曲线只能实测反推 |
| `.atk` 整数索引 → 文件 的映射 | 全库无 `attackinfo.lst`；`character/swordman/attackinfo/` 有 113 个 `.atk`，但 `sq_SetCurrentAttackInfo(36)` 的 36 无表可查 | 复刻时**必须改成显式路径/id**，否则无法从技能找到属性 |
| UI 控件句柄 | `.ui` 只给摆位；控件 ID 三态并存（`IDC_` 885 / 纯数字 2946 / 符号名 476），句柄在客户端 C++ | UI 只能靠自建控件库重写，不能"导入" |
| 副本结算界面 | `ui/result/` 下 0 个 `.ui`，全库 `IDC_RESULT` 零命中 | 结算界面 100% 自写 |
| 副本内 HUD 布局 | 唯一来源是 `init_character.nut:53-97` 的**常量像素坐标** | 照抄常数即可，但分辨率一变就要重排 |
| 帧标记 flagIndex 的字节字段 | `.ani` 的 `0x17` 值域 0..7（9,260 次）；而脚本 `onKeyFrameFlag` 的实参是 67/100/101 | ⚠️ 阻断项，见 §7 P0-1 |
| 输入映射 | 无键位表；只有 APC 的 `.aic`/`.key` 宏（"会按键的玩家"） | 自建 InputMap |
| 唯一兽 / 排行 / 活动开关 | `.cre` 无 `[unique]` 字段；`tagdict` 无对应标签 | 属运营层，用存档标记即可 |

---

## 2. 机制链路（全文核心）

> 目标：从"玩家按下 X 键"到"怪物头上冒出一个伤害数字"，每一步都能指到**哪个文件、哪个字段、哪个下标**，并且照着能写出来。

### 2.1 全景图

```
【输入】 键盘/手柄
   │  映射不在 PVF（客户端 InputMap；APC 用 .aic/.key 模拟按键流）
   ▼
【意图】 该不该进这个状态？
   │  玩家：.skl [command] 键序列 + [required level range] + 冷却；.nut 的 checkExecutableSkill/onProcCon 里 sq_IsUseSkill/SkillCommandEnable
   │  怪物：.ai 条件树（Event→DestinationSelect→Action→MoveMethod）挑出 attack 槽号 n；.mob [cooltime] 数组按 n 查冷却
   ▼
【状态切换】 ★ 两个"8"不是同一个东西（§5 #6）
   │  玩家：*_load_state.nut 的 pushState(job, nutPath, scriptName, stateId, skillId) → sq_AddSetStatePacket(stateId) → 引擎回调 onSetState_<name>
   │  怪物：.act 的 [SET ACTION] [ATTACK] n [NOW]
   ▼
【动作编排】
   │  怪物/物件 .act：章 [MOTION]/[TRIGGER]/[BEHAVIOR]，[XXX]-N = 第 N+1 个实例，[DO BEHAVIOR] [ME] n = 执行"我"的第 n 个 behavior
   │  玩家 .nut：onSetState 里 sq_SetCurrentAnimation(idx) 选动画；onKeyFrameFlag 里开判定/切子状态/生成物件；onEndCurrentAni 决定下一段
   │  ── 分支：不直接攻击，而是 [CREATE PASSIVEOBJECT][INDEX] <全局id> → .obj（投射物/持续区域）
   │          该对象**从【动画与帧时间轴】开始走同一套流程**，只是宿主换成自己（§2.4 结论 2）
   ▼
【动画与帧时间轴】 .ani v6
   │  header: u16 frame_max | u16 img_count | img_count×(u32 len + 路径)
   │  frame:  u16 n_head | n×(u16 id + payload) | image_slot | i32 x | i32 y | u16 n_tail | n×(id+payload)
   │  每帧 0x0c DELAY(ms, 99.4% 帧都有) → 播放速度就是这个字段
   │  触发点：.act [TRIGGER][FRAME] a b；玩家侧 onKeyFrameFlag(flagIndex)（⚠️ 字段未定，§7 P0-1）
   ▼
【判定盒】 同一帧内 6×i32
   │  0x0f ATTACK BOX = (相对X, 相对Y, 相对Z, 宽, 高, 深)
   │  0x0e DAMAGE BOX = 同格式
   │  开关：.act [SET DAMAGE BOX] [ON]/[OFF]、[ATTACKRECT][RESET]（全库 2,446 次）；
   │        .nut sq_SetAttackBoundingBoxSizeRate（只能缩放，全库 509 次）
   ▼
【攻击属性】 .atk（由 sq_SetCurrentAttackInfo(atk) 或 .mob [attack info][n] 绑定）
   │  [damage bonus] 100   → 倍率百分比
   │  [attack type][physic|magic][weapon damage apply]
   │  [damage reaction][down|blow|stuck…] + [push aside]/[lift up]/[knuck back]
   │  [hit info] 四元组 → 硬直/hit-stop；[active status] burn 100 70 3000 600 20 1 3000 → 异常状态
   ▼
【伤害结算】 不在 PVF
   │  以 .atk 倍率 × 角色面板 × 技能 [level info] 倍率 × 暴击 × 属性抗性 × 等级差修正；PVE/PVP 两列（装备字段成对）
   │  客户端算表现，服务端算结果 → 这就是联机接缝（§3.4）
   ▼
【表现】
      伤害数字/HUD（客户端硬编码）· 受击动画（[damage action 1/2]）· 命中音效（[hit wav]）
      · 屏幕震动/闪光（.act [FLASH SCREEN]）· 气泡文字（[CENTER MSG]）· 叠加层特效（.als / sq_AddStateLayerAnimation）
```

### 2.2 逐段落地表（写代码时对着这张表查）

| # | 步骤 | 承载文件 | 关键字段 / API | 实测样本 |
|---|---|---|---|---|
| 1 | 输入→意图 | `.skl` + `.nut` | `[command]` 键序列；`sq_IsEnterSkill(id)`、`sq_IsUseSkill(id)`、`setCommandEnable(id,true)` | `attack.nut` 的 `onProc` 里 `sq_GetSkill(obj,81)` + `sq_IsUseSkill(81)` 成立就进派生技 |
| 2 | 状态机注册 | `*_load_state.nut` | `pushState(job, path, name, stateId, skillId)`；5 参形式 = (职业, nut 路径, 回调名后缀, 状态 id, 技能 id) | `swordman_load_state.nut:93` `pushState(0,"…tripleslash.nut","TripleSlash",101,8)` |
| 3 | 动作段（怪物） | `.act` | `[MOTION][BASE ANI] <path>`、`[SUB ANI] <path> <x> <aliasIdx>`、`[TRIGGER][FRAME] a b`、`[BEHAVIOR][SET ACTION][ATTACK] n [NOW]` | `rosaura/action/attack_11.act`：帧 39 触发 `[ATTACK] 12` |
| 4 | 动作段（玩家） | `.nut` | `obj.sq_GetAttackAni(k)` / `sq_SetCurrentAnimation(idx)`、`sq_Rewind`、`sq_AddStateLayerAnimation(layer, ani, t, ?)` | `src/character/swordman/attack/attack.nut:115-124`（导出路径 `sqr/…`） |
| 5 | 动画下标解析 | `.lay` | `[etc motion]` 平坦列表，**0 基下标** | 剑士 `sq_SetCurrentAnimation(122)` → `%s/bloodboom.ani`（本轮实测，§5 #7） |
| 6 | 帧驱动 | `.ani` | `0x0c DELAY`（ms）、`0x07 IMAGE RATE`、`0x0a INTERPOLATION`、`0x08 IMAGE ROTATE`、`0x09 RGBA` | `boom01.ani.bin`：11 帧、每帧 DELAY=100 |
| 7 | 判定几何 | `.ani` | `0x0f` / `0x0e` = 6×i32 `(x,y,z,w,h,d)` | 同一 `boom01.ani.bin` f0-f10 攻击盒 `(-118,-19,-91,228,38,199)` |
| 8 | 判定开关 | `.act` / `.nut` | `[SET DAMAGE BOX][ON]`、`[ATTACKRECT][RESET]`、`sq_SetAttackBoundingBoxSizeRate` | 全库 2,446 / 509 次 |
| 9 | 属性绑定 | `.atk` | `[damage bonus]`、`[attack type]`、`[damage reaction]`、`[hit info]`、`[active status]` | `slime/attackinfo/boom.atk`：魔法+火+击倒+燃伤 |
| 10 | 结算 | 客户端/服务端 | 公式不在 PVF | 见 §7 P0-3 |
| 11 | 表现 | `.ani`/`.als`/音效名 | 叠加层、`[hit wav]`、`[FLASH SCREEN]`、`[CENTER MSG]` | `saya/attack_9.act` 的 `[SHAKING] 2 1000`、`rosaura/attack_10.act` 第 78 帧 `[SET DAMAGE BOX][ON]` |

### 2.3 玩家侧完整实例：剑士普攻（state 8）

这是全库最重要的一条链，因为它**同时否证了两个常见误解**（"角色也用 `.act`"、"技能动画是独立文件"）。

```
.skl（技能数据：等级/倍率/冷却/能否学）
   │  command 键位 + cooldown
   ▼
character/swordman_load_state.nut
   :51  //IRDSQRCharacter.pushState(… "swordman_attack", 8, -1);   ← 原版被注释掉
   :99  IRDSQRCharacter.pushState(0, "character/swordman_jg/attack/attack.nut", "swordman_attack", 8, -1);
                                                                   ← 真正生效的是 jg 版（stateId=8, skillId=-1）
   ▼
attack.nut  onAfterSetState_swordman_attack / onKeyFrameFlag_swordman_attack / onProc_swordman_attack
   │  subState（第几段）与 skillIndex 从 datas 取出，存进 obj.getVar()
   ▼
weaponcombo_…_swordman_attack
   │  local animation = obj.sq_GetAttackAni(1);      ← 按武器子类型取普攻动画
   │  obj.setCurrentAnimation(animation);            ← 或 sq_SetCurrentAnimation(37) 数字下标
   │  sq_SetCurrentAttackInfo(36 或 100);              ← 绑定 .atk（按武器子类型）
   │  obj.sq_AddStateLayerAnimation(1, sq_CreateAnimation("", "…/short_new_01.ani"), 0, 0);  ← 叠加特效
   ▼
.ani（该段普攻的帧表）
   │  每帧：图 + DELAY + ATTACK BOX
   │  关键帧 → onKeyFrameFlag_swordman_attack(obj, flagIndex)（实参 67/100/101）
   │           case 67/100/101: obj.resetHitObjectList();  ← 清空"已命中列表"= 允许同一招多段命中
   ▼
.atk（属性）→ 结算 → 表现
```

**三个可直接照抄的设计点**

1. **多段命中不靠"多个攻击盒"，靠 `resetHitObjectList()`**：`onKeyFrameFlag` 的 `case 67/100/101` 里清空命中列表，于是同一目标能被再打一次。复刻时 `hitTargets: Set` + `resetHit()` 就够。
2. **同一套动作按武器子类型分支**：`getWeaponSubType()` 后 `case 2`（巨剑）= `sq_SetCurrentAnimation(37)` + `sq_SetCurrentAttackInfo(36)`，否则 = `170` + `100`。武器种类影响手感，是数据 + 一小段脚本，不是另写一套战斗。
3. **`onProc*` 是"动作播放中也能响应输入"的钩子**：普攻 `onProc` 里若 `sq_IsUseSkill(81)` 成立就 `sq_AddSetStatePacket(45, STATE_PRIORITY_IGNORE_FORCE, true)` 强行切进派生技——**动作取消（cancel）**就是这么实现的，优先级枚举是它的开关。

### 2.4 怪物侧完整实例：沙雅（saya）的冰风 —— 顺带揭示"判定框的另一半"

| 文件 | 内容 | 说明 |
|---|---|---|
| `saya.mob`（结构同全库 4,042 只怪） | `[waiting action]`、`[move action]`、`[damage action 1/2]`、`[attack action]`（44 条 `.act` 的**有序数组**）、`[attack info]`（11 条 `.atk` 数组）、`[ai pattern]`（5 个难度 × 4 个 `.ai`） | 动作槽 / 攻击槽 / AI 槽都是平行数组，由 `[SET ACTION] [ATTACK] n` 的 `n` 统一下标 |
| `monster/championtower/saya/action/attack_9.act`（34 行） | `[BASE ANI] ../Animation/Attack_9_0.ani`；`[SUB ANI] Attack_9_1.ani 0 1 / Attack_9_2.ani 0 2`；`[SOUND] SAYA_BLIZZARD 0 SAYA_ICEMENTLE_ROLL 7 …`；`[TRIGGER]-1 [FRAME] 4 4 [WHICH][CHARACTER] [CHECKUP] [CHECKED NO][=>] 0 [DO BEHAVIOR][CHECKUP OBJECT] 1` | 第 4 帧对"命中的每个角色"执行 BEHAVIOR-1；`[SOUND]` 的第二个数是帧号 |
| 同上 | `[BEHAVIOR]-1 [CREATE PASSIVEOBJECT][INDEX] 74068 [LEVEL]-1 [POS] 545 472 0`；`[TRIGGER]-2/3/4 [FRAME] 7/9/11 → [DO BEHAVIOR][ME] 2`；`[BEHAVIOR]-2 [SHAKING] 2 1000` | **`.act` 不产生伤害**：它只生成被动对象 74068（`ActionObject/Monster/Guild_dungeon/Saya/Ice_Wind/Ice_Wind.obj`）；第 7/9/11 帧各再打一次，靠的是"再生成一次"而不是改判定盒 |
| `monster/poongjintrainingroom/rosaura/action/attack_10.act`（55 行） | 帧 78：`[WHICH][CHARACTER] [CHECKUP][DISTANCE][<] 8000 → [BEHAVIOR]-4 [SET DAMAGE BOX][ON]`；帧 7：十余条 `[CREATE PASSIVEOBJECT][INDEX] 19354 … [POS][RANDOM] 0 560 [RANDOM] 154 317 [USE MAP POS]`；`[TRIGGER] 8 [ON]` 被当作"开关变量"用 | **`.act` 只知道开关时刻（第 78 帧），不知道盒子形状**；`[RANDOM]` 是内置采样器 |

**三条关键结论**

1. 怪物的"技能"= 动作段 + 攻击槽 + 触发器，全在 `.act` 里，**没有一处脚本**；`.ai` 只负责"选哪个槽"，不负责"怎么打"。这是很干净的关注点分离，值得抄。
2. **大量攻击的真正命中体是"被动对象"**（24,107 个 `passiveobject/.act`）：主怪 `.act` 只 `[CREATE PASSIVEOBJECT][INDEX] <全局 id>`，投射物/持续区域是**与怪物同级的独立实体**，有自己的 `.ani` 帧框和 `.atk`。复刻时若把投射物做成"怪物攻击的一部分"，会丢掉"可被打断/可被格挡/可独立存在"这些 DNF 行为。
3. `.act` 是一门"**帧驱动 + 对象查询**"的小语言，不是配置表：条件（`[WHICH]`+`[CHECKUP]` 对象查询、`[COMPARE VAR]` 变量、`[BEGIN IF]/[ELSE]/[END IF]` 内联分支）× 副作用（生成对象 / 位移插值 / 预警框 `[CREATE SIMPLE WARNING]` / 演出 `[FLASH SCREEN]`/`[SHAKING]` / 切动作 `[SET ACTION][CUSTOM] 11`）。`[CUSTOM] 11` 的语义由数据约定，不属引擎——这正是一处"约定代替枚举"的设计债务。

### 2.5 三个必须记住的接线细节（本轮实测）

1. **`[etc motion]` 是 0 基下标表**。剑士 `.lay` 的 `[etc motion]` 有 276 项，`bloodboom.nut` 的 `sq_SetCurrentAnimation(122)` 命中的是 `%s/bloodboom.ani`（第 123 项）→ **0 基**。`%s` 由装备的 `[layer variation]`（如 `2790 katanac`）展开成子文件夹，这就是"换武器换外观"的全部机制：**同一个 .ani 路径配上不同贴图目录**。
2. **`.act` 的章-实例编号是一层扁平化**。`[TRIGGER]-2` 不是嵌套在 `[TRIGGER]` 里，而是"第 3 个触发器实例"；`[DO BEHAVIOR] [ME] n` 指向同一文件里第 n 个 `[BEHAVIOR]` 实例。解析器必须"先扫全章收集实例，再按编号连接"，不能顺序流式解析。
3. **`[SUB ANI]` 的第 3 个数是子动画别名索引（0..9）**，不是"第几帧"。`[PLAY ANIMATION]`/`[SUB ANI FLAG]`/`[DELETE ANIMATION OBJECT]` 都按这个别名操作；语义上相当于叠加层槽位（玩家侧对应 `sq_AddStateLayerAnimation(layer,…)` 的 layer），承担"身体不动、特效动"的表现，相当于内联的 `.als`。

### 2.6 一帧内的时序（自定，但必须固定）

PVF 不定义 tick 顺序，这是第 0 层的自由。要让手感接近 DNF，建议固定 60 Hz 并采用这个顺序（与 `.act` 触发器的语义自洽）：

```
tick(t):
 1. 读输入 → 更新意图缓冲（含 input buffer，DNF 的取消窗口靠它）
 2. 状态机：处理 pending state（sq_AddSetStatePacket 的效果下一 tick 生效）
 3. 动作编排回调：onProc / onProcCon（可改状态、可开判定）
 4. 动画推进：累加 DELAY(ms) → 到帧边界则换帧，并触发该帧事件
 5. 帧事件：.act 的 [FRAME] a b 命中区间 → 执行 behavior；.nut 的 onKeyFrameFlag → 开判定/切子状态
 6. 命中检测：用当前帧 ATTACK BOX（世界坐标变换后）与所有 DAMAGE BOX 求交；
             命中集合去重（未 resetHit 前不重复命中同一目标）
 7. 结算：.atk 效果 + 公式（服务端权威则此处只做预测）
 8. 表现：切受击动画、播 [hit wav]、叠特效、弹伤害数字
 9. 清理：判定框 OFF、销毁本帧生成的临时物件
```

> **Godot 映射**（详见 `docs/GODOT-EVAL.md` §3）：第 4–6 步用**自写 `Rect2` 求交**，不用 `Area2D`——`Area2D` 的物理回调顺序受引擎调度影响，无法保证可回放；事件帧不用 `Call Method Track`，直接用 `frame_index → events[]` 查表。这是"确定性优先"的取舍。

---

## 3. 系统互相引用关系

### 3.1 引用总图（只画跨系统的边，括号内是承载字段）

```
                         ┌──────────── .lst 注册表（id → 路径，唯一权威）────────────┐
                         │ character / skill/* / equipment / stackable / monster /    │
                         │ map / dungeon / town / passiveobject / appendage / npc …   │
                         └───────┬───────────────────────────────────────────────────┘
                                 │ 全体系统都从这里把整数 id 换成文件
   .chr(职业) ──[skill]──▶ .skl(技能) ──[level info] 列──▶ 数值
      │                     │  ▲
      │                     │  └──[skill data up]── .equ（装备改技能，唯一官方接口）
      │                     ▼
      │            pushState(stateId, skillId) ──▶ .nut(脚本) ──[SetCurrentAnimation]──▶ .lay ──▶ .ani
      │                                              │                                   ▲
      │                                              └──[SetCurrentAttackInfo]──▶ .atk    │
      │                                                                                  │
   .equ ──[equipment ani script]+[layer variation]+[variation]───────────────────────────┘
      │
      ├──[if]/[then]──▶ .apd(appendage) / passiveobject(.obj→.act→.ani→.atk)
      └──[grade]+[rarity]──▶ etc/upgrade.etc（强化表；装备侧一个数字都不写）

   .mob ──[attack action]──▶ .act ──[BASE ANI]──▶ .ani ──0x0f──▶ 判定盒
      │  ──[attack info]───▶ .atk
      │  ──[ai pattern]────▶ .ai ×4（Event/DestinationSelect/Action/MoveMethod）
      │  ──[ability category]──▶ 基表 100 行 × 乘数
      └─ ─[item]──▶ .equ/.stk（掉落）

   .dgn ──[greed]+[size]──▶ 迷宫格 ──[map specification]──▶ mapId ──▶ .map
   .map ──[monster]──▶ .mob │ ──[passive object]──▶ .obj │ ──[tile]──▶ .til(通行网格)
        └─[dungeon]──▶ 反向指回 .dgn（房间池复用）
   .dgn ──[quest connection]──▶ .qst ◀──[npc index]/[complete npc index]── .npc
   .qst ──[type]+[int data]──▶ 上述所有（副本/怪/物品/地图/NPC）
        └─[monster reward item]──▶ 临时掉落通道（不改 .mob）
   .cre ──[skill info]──▶ .skl │ ──[attack info]──▶ .atk │ ──[motion]──▶ .ani │ ──[evolution]──▶ .cre + .qst
```

### 3.2 四种接线方式（设计分析的关键，不是实现细节）

| 方式 | 例子 | 优点 | 代价 |
|---|---|---|---|
| **A. `.lst` 注册表** | `equipment.lst` 102,329 条；`map.lst` 4,591 条 | 改 id 不动文件；可热更 | id 与文件不必同名；索引必须常驻内存 |
| **B. 直接路径** | `.act [BASE ANI] ../Animation/Attack.ani`、`.equ [equipment ani script]` | 零查表、人可读 | 大小写/相对根不一致就静默失效（PVF 路径非根相对，须后缀匹配） |
| **C. 平行数组下标** | `.mob [attack action]/[attack info]/[cooltime]`；`.skl [level info]` 列；`[layer variation]` | 解析器只读数值流，最快 | 越界/长度不一致时**没有定义行为**（§7 P1-4） |
| **D. 命名约定** | `%s/Attack_N.act`、`onSetState_<name>`、`CUSTOM_ANI_*`=lay 下标、`job 0` = 剑士 | 省掉一张表 | 改名即断；二进制里看不见，只能靠反推 |

**这张表解释了一个反复出现的现象**：DNF 里"看起来是同一个机制"的东西，往往用不同接线方式实现（`.twn` 用路径引 `.map`，`.dgn` 用 id 引 `.map`）。这不是设计混乱，而是**二十年增量演进 + 不同团队各自最优**的结果。复刻时统一成一种（推荐 A + B），是最大的"可维护性收益"。

### 3.3 四条最容易被忽略的引用边

1. **`.equ → .lay → .ani` 与 `.nut → .lay → .ani` 在 `.lay` 汇合**（05 §2）。技能和外观共用同一个动画下标空间，所以"换武器改普攻外观"不需要改脚本。
2. **任务能临时改写掉落**（`.qst [monster reward item]` 7 值 / `[enemy reward item]` 8 值）。这是"任务道具不污染全局掉落表"的解法，08 明确标为 M2 必做。
3. **`.dgn [champion]` 的 5 个值 = 5 个难度档的精英率**（普通/冒险/勇士/王者/英雄），一行承载一整条难度曲线。
4. **`.dgn [map specification]` 的候选列表 = "随机地图"的真相**：不是程序生成，而是**随机挑一个已做好的房间**。这是全库性价比最高的"伪随机"设计。

### 3.4 联机接缝在哪（单机优先，但要留口）

`.nut` 里所有跨端通信都收敛成一个范式：

```squirrel
if (obj.sq_IsMyControlObject()) {          // 只有"我控制的对象"跑这段
    sq_BinaryStartWrite();
    sq_BinaryWriteDword(...);              // 写参数
    sq_SendCreatePassiveObjectPacket(...); // 发确定性指令包
}
```

实测出现 2,280 次（全量 grep）。**含义**：本地不做"结果同步"，只发"指令"，对端重放同一套确定性逻辑。所以联机接口的正确位置是**指令层**（`SendCreatePassiveObjectPacket` 等价物），不是结果层。单机版只要把这条通路留成"本地立即执行 + 记录指令"，联机时改成"发给 host"即可。这也解释了为什么 §2.6 强调判定必须自算 `Rect2`：**可回放是联机的前提**。

---

## 4. 设计思想点评

### 4.1 为什么这样拆（四条真正好的设计）

**① "何时"与"什么"彻底分离。** `.ai` 只决定"用哪个攻击槽"，`.act` 决定"这段动作在哪些帧做什么"，`.ani` 决定"每帧长什么样、打哪"，`.atk` 决定"打上去什么效果"。四层各自独立可复用：一个 `.atk` 能被 100 个怪物共用，一个 `.ani` 能被 10 个 `.act` 引用（`[SUB ANI]` 还能再拆）。**组合爆炸被压平成四张平表**。这是 DNF 内容量能做起来的根本原因。

**② 枚举 + 变长参数数组 = 零成本的 DSL。** `.qst` 的 `[type]` + `[int data]`（8 种语义、长度随 type 变）、`.atk` 的 100 个标签、`[int data]` 的"首值=个数"，都是同一个套路：**用第一个数说明后面怎么读**。它不需要 schema，不需要嵌套，1980 年代的解析器也能读。代价是"参数含义只能查代码/查注释"——`tagdict.sqlite` 里 200+ 条官方注释就是这个代价的补丁。

**③ 平行数组优先于对象数组。** `.mob` 把 `[attack action]`、`[attack info]`、`[cooltime]` 拆成三条等长列表，而不是一个 `attack[] {action, info, cooltime}` 数组。省一次嵌套解析，代价是"长度必须自己保证"（§5 #4 的 `[ATTACK] 12` 对 4 条 `[attack info]`）。这是**性能优先的年代留下的形状**，复刻时应该改成对象数组。

**④ `%s` 变量 + `[layer variation]` = 用变量展开代替文件复制。** 一把武器的外观 = `layer variation`（图层 + 子目录）+ `variation`（4 位贴图编号）+ 一个共享 `.lay`。于是 108,645 件装备里 547,770 个 `.ani` 只是"同一套动作 × 不同贴图目录"，没有一份是手写的。**这是全库最值得抄的省钱技巧**：动作描述一次，贴图靠变量替换。

### 4.2 五处历史包袱（抄了会后悔）

| 包袱 | 表现 | 建议 |
|---|---|---|
| `.als` 退化 | 77,490 个 `.als` 里**没有一个含 `[TRIGGER]`**，只有 2 个含 `[MOTION]`；实际用途只剩 `[use animation]`(7,292) / `[none effect add]`(4,299) / `[add]`(2,751) / `[create draw only object]`(538) | 直接实现成"叠加层列表"，不要做成状态机 |
| 同名异义 | `[physical attack]` 在 `.chr` = 物攻、在 `.equ` = **力量**；`[string data]` 在 `.stk` = 工艺表、在 `.apd` = 技能加成 | 复刻时改名（`strength`/`int_atk`），别保留原名 |
| 反直觉编码 | `[stuck]` 填**负数**才是加命中；`[value]` 实收 **1/5**；`[greed]` 每格 **2 字符**；`[difficulty]` 是**单字符**且 15 档不成线性（`S 115 / A 90 / B 70 / Z 400`） | 全部换成显式数值/枚举 |
| 索引不在数据里 | `.atk` 整数索引无注册表；`CUSTOM_ANI_*` 常量靠 `.lay` 顺序；`Attack_N.act` 靠文件名 | 一律改显式 id；这是**最高优先级的"不要抄"** |
| 隐式尺寸 | `.til` 无宽高，`[pass type]` 是一长串 0/2；房间边界靠地砖排列 | 显式 `width/height` |

### 4.3 复刻可抄度分级（对"非素材逻辑"的总判断）

这是本文最想给出的一张判断表——**同一份 PVF，"能抄"的程度差别巨大**：

| 级别 | 含义 | 系统 | 工作量 |
|---|---|---|---|
| **A 纯数据，可 1:1 抄** | 只要解析器对，语义就对了 | `.ani` 帧表/判定盒、`.atk` 属性、`.qst` type+data、`.dgn [greed]` 迷宫、`.map [monster]` 10 字段、`.equ/.stk` 字段、`.skl` 等级数据、强化三表 | 解析器 + 内存模型 |
| **B 数据可抄，但需要自写 VM** | 数据结构抄，执行语义自写 | `.act` 触发器/behavior（约 30 种 behavior）、`.ai` 条件树（4 条件函数）、`.nut` 回调（554 个 `sq_*` 里只需 ~40 个）、`.equ [if]/[then]`、`.cre skill node` | 每个 VM 几百行 |
| **C 客户端硬编码，抄不到** | PVF 里根本没有 | 伤害公式、`.atk` 索引表、UI 控件/结算界面、输入映射、命中检测、帧标记字段 | 只能自定（§7） |
| **D 服务端/运营，单机不需要** | 抄了也用不上 | 唯一兽、排行、活动（`.evt`）、掉率校验、PK 平衡列 | 跳过 |

**一句话总结**：DNF 的"逻辑"有 **A 级 60% / B 级 25% / C 级 15%**。A 级是资料，B 级是工作量，C 级是手感。真正决定"像不像 DNF"的是那 15%（第 0 层），而不是 60%。

### 4.4 三个值得抄但不是 DNF 独有的"好习惯"

1. **一张全局经济表统管货币**（`n_quest/questparameter.etc`，2.6 KB 决定 3,852 个任务的产出）。任务只写"难度字符 + 倍率"，数值全查表 → 调经济不用碰任务文件。
2. **强化系统零冗余**：装备只出 `[grade]`（数值曲线位置）+ `[rarity]`（费用/概率档位），其余全在 `etc/upgrade.etc`。加一件新装备**不需要动强化表**。
3. **难度写在关卡而不是怪上**：`.dgn [basis level]` + `[champion]` 5 档 + `.map [monster] 等级自动指定`，同一只怪在 5 个难度下强度不同，而 `.mob` 只有一份。

---

## 5. 交叉印证：专家矛盾与原始数据裁定

> 方法：一律回到 `export/text/` 或 `export/_meta/index.sqlite`，用本轮可复现的命令重新取数。裁定以最后一次实测为准。

| # | 矛盾点 | 甲方说法 | 乙方说法 | 回原始数据核对 | 裁定 |
|---|---|---|---|---|---|
| 1 | `.atk` 里有没有判定盒几何 | `docs/PVF-FORMAT.md` §9、`analysis/00-OVERVIEW.md` 后缀表：`.atk` = "攻击信息/判定盒" | `analysis/04` §0：".atk 不含任何坐标（18,877 个全查过）"；`analysis/09` §1.6 同 | `index.sqlite`：`.atk` = 18,877 个。对全部 `.atk` 做标签频次：`[damage reaction]`18889 / `[attack type]`18667 / `[hit info]`17835 / `[push aside]`16051 … **没有任何 x/y/w/h/box 类标签**；样本 `slime/attackinfo/boom.atk`（26 行）全为属性 | **以 04/09 为准：`.atk` 无几何，几何唯一来源是 `.ani` 的 `0x0f/0x0e`。** PVF-FORMAT 的表述是早期的笼统说法，应视为作废 |
| 2 | `.ani` 头部第一个 u16 是什么 | `analysis/04` §8 待验证 #1："头部 `u16 ver=0x000a, u16=1, u32 pathLen=56`，`0e 00` 后跟 4×int32 疑为矩形" | `docs/ANI-FORMAT.md`：头部是 `u16 frame_max \| u16 img_count \| img_count×(u32 len+路径)`；`0x0e` 是 6×i32 | 直接读 `slime/animation/boom01.ani.bin`：前 8 字节 `0b 00 01 00 3f 00 00 00`，随后 `4d 6f 6e 73 74 65 72 2f…`（"Monster/"）。= frame_max **11**、img_count **1**、路径长 **0x3f=63**。`ani_parser.py` 解析结果 11 帧、clean=True，f0 攻击盒 `(-118,-19,-91,228,38,199)`（6 个值） | **以 ANI-FORMAT 为准。** 04 把 `frame_max=0x0a`(10) 当成了版本号，把 `0x0e` 的 6 个 i32 前 4 个当成了矩形——这正是"前 4 个数像 rect"的陷阱。该文件若不修，会让 ani 解析器一开始就跑错 |
| 3 | `sq_*` 调用频次 | `analysis/04` §4：`sq_SetCurrentAttackInfo` 2,378、`sq_SetCurrentAttackBonusRate` 2,426、`sq_SetAttackBoundingBoxSizeRate` 519 | `analysis/09` §1.7：888 / 726 / 216 | 全量 `grep -a`（绕开 NUL 跳过）于 `sqr/**/*.nut.txt`：**2,608 / 2,386 / 509**；`sq_GetCustomAttackInfo` 1,811、`sq_AddSetStatePacket` 3,244、`sq_SendCreatePassiveObjectPacket` 2,280。另测"不含 NUL 的 .nut 子集"= 733/681/144 | **以全量为准（2,608/2,386/509）。** 09 的数字是"grep 默认跳过含 NUL 文件"的子集口径（660/2,487 个文件）；04 的数量级对，个别值偏差 ~9%。教训：`.nut` 必用 `grep -a` |
| 4 | `.act` 的目录分布 | `analysis/03` §3："24,077 个 passiveobject、52,848 个 monster" | `analysis/09` §1.1："monster 53,041 / passiveobject 24,107 / 合计 77,511" | `index.sqlite` group by 顶层目录：`monster 53041`、`passiveobject 24107`、`aicharacter 178`、`ui 131`、`map 17`、`creature 17`、`worldmap 10`、`npc 9`；总 77,511 | **以 09 为准。** 03 的数字偏小约 190/30，应是早期快照或未含新目录；量级结论（"角色没有 .act"）两边一致，不受影响 |
| 5 | `.ani` 总数 | `analysis/00-OVERVIEW.md`、`PVF-FORMAT`、`GODOT-EVAL` C1：**1,058,561** | `docs/ANI-FORMAT.md`：1,047,702 | `index.sqlite`：`select count(*) from files where ext='ani'` = **1,058,561** | **以 1,058,561 为准。** ANI-FORMAT 的 1,047,702 应是某种过滤子集（差 10,859），引用总量时用 index 口径 |
| 6 | "state 8" 与 "skill 8" 是不是一回事 | `analysis/09` §3："剑士 state 8 = 普攻，原版绑定被注释、实际生效 jg 版" | `analysis/03` §0 样例："`pushState(… "TripleSlash", 101, 8)` → state=101、skill=8" | `swordman_load_state.nut` 原文：`:51` `//IRDSQRCharacter.pushState(… "swordman_attack", 8, -1);`（注释掉）；`:99` `pushState(0, "character/swordman_jg/attack/attack.nut", "swordman_attack", 8, -1);`（生效）；`:93` `pushState(0, "…tripleslash.nut", "TripleSlash", 101, 8)` | **两边都对，但说的是两个命名空间**：`8` 作为**状态 id** = 普攻（jg 版生效），`8` 作为**技能 id** = 三段斩。pushState 的 4 参 = stateId、5 参 = skillId（`-1` = 无技能数据）。**这是全库最危险的"同数字不同义"，必须写进类型区分（`StateId` / `SkillId`）** |
| 7 | `CUSTOM_ANI_*` / `sq_SetCurrentAnimation(n)` 的 `n` 是 0 基还是 1 基 | 03/09 都只说"是 `.lay [etc motion]` 的下标"，未定基准 | —（无人给） | 剑士 `equipment/character/swordman.lay` 的 `[etc motion]` 展开为 276 项（`%s/Stay…` 之外）；`bloodboom.nut:50` `obj.sq_SetCurrentAnimation(122)`；第 123 项（1 基）/第 122 项（0 基）恰为 `%s/bloodboom.ani` | **定为 0 基**（本轮新结论）。这条不定，技能动画会整体错一帧——属于"实现第一天就会撞"的细节 |
| 8 | `.mob` 基表覆盖率 | `analysis/06` §1："基表 100 行 × 11 列覆盖 4,042 只怪" | —（独此一家） | `index.sqlite`：`.mob` 文件数 = **4,042**，与"覆盖 4,042 只怪"完全吻合 | 采信 06。**顺带验证了"每只怪一个 .mob"的假设成立**（不是一份 mob 带多个变体） |
| 9 | 怪物"放技能"怎么写 | 任务书假设用 `[USE SKILL]` | `analysis/09` §1.2：全库 1,460,792 文件里 `[USE SKILL]` **0 次** | 采信 09（0 命中无法被"没搜到"推翻，且 09 给了替代写法） | **真正的写法** = 怪物 `.act` 的 `[SET ACTION] [ATTACK] n [NOW]`；玩家 = `sq_AddSetStatePacket`。任务书该条作废 |

**另有两条"不是矛盾、是版本演进"，不要误读为打架**：
- `analysis/03` 与 `04` 都写过"`.ani` 版本 6 未解析"，`docs/ANI-FORMAT.md` 已解析（95.02% 字节级闭合）。**以 ANI-FORMAT 为准**，03/04 的该条待验证项可关闭。
- `analysis/09` 把 `.mob` 的动作槽列为 6 组、`analysis/06` 列了六组字段表；两者是同一件事的不同切面（09 从"动作编排"看，06 从"怪物面板"看），**不矛盾，引用时注明视角**。

---

## 6. 与路线图的对应（给决策用）

总纲的结论如何落到 `docs/ROADMAP.md` 的阶段：

| 总纲结论 | 影响的阶段 | 动作 |
|---|---|---|
| 判定必须自算 `Rect2`，事件帧用查表不用信号（§2.6） | P0.5/P2.2 | 先写 `AnimPlayer`（帧表+DV 事件队列），不要先摆 `AnimatedSprite2D` |
| `.atk` 整数索引不在 PVF（§1.3） | P0.8 | 资源表里直接存 `.atk` 路径/id，禁止复刻"第 36 号攻击" |
| `.ani` 有 106 万、单帧一文件导入必炸（GODOT-EVAL C1） | P0.6 | NPK→图集**离线**打包，运行时只按 `(img, frame)` 取 region |
| A/B 级系统占 85%（§4.3） | P1–P3 | 先 A 级（解析+内存模型）再 B 级（VM），C 级只做"够手感"的最小版 |
| 联机接缝在指令层（§3.4） | 贯穿 | 所有跨对象效果走"指令包"单一入口，单机时本地执行 |

---

## 7. 待验证清单（汇总六份专家产出 + 本轮新增，按重要性排序）

**P0 = 阻断实现，必须先解决；P1 = 影响正确性；P2 = 影响体验/经济；P3 = 可延后。**
"来源"指提出该问题的文档；"新增"指本轮编纂时发现的缺口。

| # | 优先级 | 问题 | 来源 | 验证方法 | 不解决的后果 |
|---|---|---|---|---|---|
| 1 | **P0** | **帧标记 `flagIndex` 由 `.ani` 哪个字段承载？**（`0x17` 值域 0..7、9,260 次；脚本实参却是 67/100/101） | ANI-FORMAT §10 + 09 §8 待验证1（**两边都没闭合**） | 取一只用 `onKeyFrameFlag` 且 case 值已知的怪/技能（如 `sqr/character/swordman/attack/attack.nut` 的 case 67/100/101），把它对应的 `.ani` 逐帧 dump 全部字段，看哪个字段出现 67/100/101 | 玩家侧"第 N 帧开判定/切子状态"全部无法实现——这是战斗手感的开关 |
| 2 | **P0** | **`.atk` 整数索引 → 文件的映射规则** | **新增**（03/04/09 都默认存在） | 全库搜 `attackinfo*.lst`（已确认 0 命中）；比对 `sq_SetCurrentAttackInfo(n)` 的 n 分布与 `character/swordman/attackinfo/` 113 个文件的构建顺序 | 技能/普攻找不到自己的属性表 → 伤害全错 |
| 3 | **P0** | 伤害公式常数（防御减伤曲线、等级差修正、属性强化、暴击倍率、PVP 第二列系数） | 04 §2（公式结构有，常数无） | 实机取 3 组"面板攻击→实际伤害"，反解；PVE/PVP 列差已知约 14% | 数值平衡无法收敛，"像不像"只能靠猜 |
| 4 | **P1** | `.mob` 三条平行数组长度不一致时 `[ATTACK] n` 如何取值 | **新增**（`rosaura`：1 条 action / 4 条 info / 15 条 cooltime，却出现 `[ATTACK] 12/13`） | 统计 100 只怪的三条数组长度与 `.ai` 里出现的 attack 下标，找越界规则（回绕？回落 0？） | 怪物攻击属性错配 |
| 5 | **P1** | `.til [pass type]` 网格宽高（样本 421 个值，非平方数；值 `3` 语义未知） | 07 §8 #1/#2 | 取同房间的 `[tile]`+`[extended tile]` 数量反推 w×h；统计 `3` 是否只在边界 | 通行层错位 → 走不进去/穿墙 |
| 6 | **P1** | `[SET DAMAGE BOX] [ON/OFF]` 的作用域与持续时间；无敌帧从哪来 | 09 §1.6 + **新增** | 找同时有 `[SET DAMAGE BOX]` 与 `0x0e` 的怪物，逐帧对照受击表现 | 判定时序错，出现"打不到/打到两次" |
| 7 | **P1** | `[greed]` 三向 token（`NN/LL/HH`）是否只出现在边角；`.dgn` 多套 `[maze info]` 是按难度还是阶段 | 07 §8 #4/#10 | 对 625 个 `.dgn` 统计 token 的格位置分布；比对第二套是否带独立 `[quest connection]` | 迷宫连通图偶发不连通 |
| 8 | **P1** | `.nut` 里 554 个 `sq_*` 的最小可用子集（哪些是"引擎语义"、哪些只是工具函数） | 09 §3 | 统计每个 `sq_*` 的调用点与参数模式，按"改状态/改属性/生成物/发包/查询"五类归档 | B 级 VM 做不完，或做了 90% 用不上的 API |
| 9 | **P2** | `.qst [quest point]`（0/4/8/10/14/30）语义 | 08 §10 #1 | 全库交叉表（值与 `[grade]`/`[type]`） | 任务分类/排序有偏差 |
| 10 | **P2** | `exp/gold reward table` 的索引基准（表非严格单调） | 08 §10 #2 | 用 1 级任务实机对照首值 100/72 | 全任务奖励系统性偏移 |
| 11 | **P2** | `[difficulty]` 15 个字符为何不规则（`M 10`/`O 10`/`Z 400`） | 08 §10 #4 | 对照 `[grade]` 分布，判断是否版本追加 | 只能照抄，无法推导 |
| 12 | **P2** | `etc/upgrade.etc [table]` 每行 5 个概率的确切语义 | 05 §9 #1 | 对照实机 +0→+1 公示成功率 | 强化手感不可调 |
| 13 | **P2** | `.equ [success rate] 5` vs 官方"100=100%" 单位不一致 | 05 §9 #3 | 抽 20 个设计图看取值范围 | 设计图成功率错 |
| 14 | **P2** | `.stk [stackable type] [waste] N` 的数字含义；`[stack limit] 0` 是否真无限制 | 05 §9 #2/#4 | 对比 potion=1 / food=4；找 `[stack limit] 0` 样本 | 消耗品行为错 |
| 15 | **P2** | `[active status]` 的参数列义与个数（04 §8 #3 记为 5 个数，而标签样本里出现 7 个；`activestatustable.etc` 有 17 项 duration 表） | 04 §1、§8 #3 | 对照异常状态表现逐帧观察 | 燃伤/冰冻数值不对 |
| 16 | **P2** | `.map [monster]` 的"随机/指定掉落次数"与 `.mob [item]` 的交互 | 07 §8 #5 | 实机刷怪统计 | 掉落次数错 |
| 17 | **P2** | `.npc [dialog]` 每行前 4–6 个数的列义 | 08 §10 #3 | 抽 5 个 NPC 对照对话分支 | 对话树无法还原 |
| 18 | **P3** | `.evt` 自定义块（`[board]`/`[quiz value]`）由谁解释 | 08 §4 | 无客户端代码则放弃 | 单机不做活动 |
| 19 | **P3** | 唯一兽的服务端约束边界 | 08 §6 | 数据层已闭合（无 `[unique]` 标签），无需再验 | 无 |
| 20 | **P3** | `pvp_mission/*.msn`(126) 是否属任务体系 | 08 §10 #10 | 打开一个看结构 | 无 |
| 21 | **P2** | `[CREATE PASSIVEOBJECT] [INDEX] 109084869` 不在 `passiveobject.lst`（该表 17,692 条，最大 id 491,002,230）——是数据缺失还是 `[INDEX]` 另有局部 id 空间 | 09 §1.5 | 抽 100 处 `[INDEX]`，比对 lst 命中率与邻近 id 分布 | 副本怪的攻击投射物可能生成不出来（黑屏式空放） |

### 7.1 未逐条展开的领域内待验证（全量 81 条）

任务书要求"汇总所有待验证项"。跨系统、影响实现的 21 条已在上表；其余属**单领域内、不影响其它系统**，保留在原文的待验证章（总 81 条），按此索引跳读：

| 文档 | 条数 | 本表已吸收 | 原文位置 | 性质 |
|---|---:|---|---|---|
| `02-character.md` | 7 | 0 | §7 | 职业表细节（growtype 列义、单位换算、初始技能） |
| `03-skill.md` | 7 | 0 | §8 | `.skl` 细节（TP 上限、被动叠加、命令串编码） |
| `04-combat.md` | 7 | 2（P0-3、P2-15） | §8 | 公式/异常状态/受击分级 |
| `05-item.md` | 10 | 2（P2-12、P2-13） | §9 | 强化概率、设计图、`[stackable type]` |
| `06-monster.md` | 7 | 0 | §9 | 基表列义、AI 条件函数全表、掉落权重 |
| `07-map.md` | 10 | 2（P1-5、P1-7） | §8 | `.til` 通行网格、`.dgn` 多套 maze |
| `08-quest.md` | 10 | 4（P2-9～11、P2-17） | §10 | 奖励表索引、对话列义、`.evt` |
| `09-script-mechanics.md` | 7 | 3（P0-1、P1-6、P2-21） | §8 | `.nut` API 子集、`.act` 边界语义 |
| `docs/ANI-FORMAT.md` | 16 | 1（P0-1） | §10 | 4.8% 失败样本归类、prologue、trailing、`0x0b/0x17` |

> 另：`analysis/00-OVERVIEW.md` 与 `docs/PVF-FORMAT.md` 无独立待验证章，其遗留表述（"`.atk` 含判定盒"、`.ani` 未解）已在 §5 裁定作废。

> **已可关闭的待验证项**（本轮核对后不必再查）：
> - `.ani` v6 帧结构（原 03/04/09 均标未解析）→ 已由 `docs/ANI-FORMAT.md` 解决，95.02% 字节级闭合。
> - `.atk` 是否有几何（PVF-FORMAT 遗留说法）→ §5 #1 已裁定：无。
> - `.act` 目录分布、`.ani` 总数、`.mob` 覆盖率 → §5 #4/#5/#8 已用 `index.sqlite` 定案。

---

## 8. 如果只记五句话

1. **四张平表（数据/编排/帧/结算）靠下标和路径连接，没有嵌套**——所以能被 20 年前的解析器读完，也所以语义全在客户端代码里。
2. **玩家没有 `.act`，怪物没有 `.nut`**：一侧是 Squirrel 状态机，一侧是触发器-行为章。两侧最终都只做两件事——选一个动画下标、绑一个攻击信息下标。
3. **判定几何只在 `.ani` 帧里（6×i32），`.atk` 只管"打上去什么效果"**。任何说 `.atk` 有判定框的说法都是错的（§5 #1）。
4. **能 1:1 抄的只有 60%**；25% 要自写 VM；决定手感的那 15%（公式、tick、命中检测、帧标记）PVF 里根本没有。
5. **所有跨端交互都收敛成"发指令包"**（`sq_IsMyControlObject` + `SendCreatePassiveObjectPacket`）——这就是联机接缝，也是单机版唯一需要提前留的口子。
