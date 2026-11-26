# DNF Squirrel 脚本层 · 宿主 API 手册

> 面向对象：要把 `sqr_gd/` 这套翻译脚本真正跑起来的人。
> 数据来源：`sqr_gd/sqr_script.gd`（478 个 `sq_*` 桩 + 5 个无前缀内建）、`sqr_gd/**/*.gd`（189 个翻译文件、5368 个调用点）、`sqr_gd/sqr_globals.gd`（1537 个公共函数）、`sqr_gd/INDEX.md`（文件→功能）、回查语料 `sqr_src_utf8/sqr/**/*.nut`（193 个原始脚本）。
> 文中所有 `文件:行号` 相对 `sqr_gd/`；`推断` 标记的是「没有直接调用证据、按命名与参数形态推出来」的结论。

**证据约定**：每条语义都给出调用现场。判定依据优先看三件事——
① 实参形态（第 1 参是不是对象 / 是不是技能 ID）；② 返回值被谁接走（赋给什么、喂给谁）；③ 上下文文件（`INDEX.md` 里这个脚本是技能状态机还是被动对象）。
三者齐了才写「是」；只凭命名的写「推断」。

**调用形态**：原名机把同一批函数注入成两套——对象上的方法 `obj.sq_GetLevelData(SKILL_X, col, lv)`，和取对象为第一参的全局函数 `sq_GetLevelData(obj, SKILL_X, col, lv)`。两种形态在**原始 `.nut` 里就并存**（`sqr_src_utf8/sqr/character/atmage/firepillar/firepillar.nut:89` 是方法式，同目录 `atmage_common.nut:429` 是全局式），不是翻译引入的。下文签名统一写成 `sq_<名字>(obj, …)`，方法式即「去掉 obj 那一位」。

---

## 1 总览

### 1.1 规模

| 口径 | 数量 | 说明 |
|---|---|---|
| `sq_*` 桩 | 478 | `sqr_gd/sqr_script.gd` 里 `func sq_*` 的总数，统一 16 个可选参数、`_stub()` 返回 `null` |
| 无前缀宿主内建 | 5 | `printc` / `isDebugMode` / `isSameObject` / `checkModuleType` / `setCurrentAnimationFromCutomIndex` |
| 宿主全局对象 | 5 | `IRDSQRCharacter` / `IMouse` / `CNSquirrelAppendage` / `CNAvenger` / `IRDSUltimateSkill`（`sqr_gd/sqr_consts.gd:12-16` 已按 `var X = null` 逐个预置好这 5 个名字） |
| 被实际调用的 | 386 | 381 个 `sq_*` + 5 个内建；共 **5368 个调用点** |
| 只在桩表里、语料中零调用 | 97 | 多为 UI / 城镇 / 商城 / 决斗场相关，见 §3.4 |
| 原始语料里的 `sq_*` | 291 | 193 个 `.nut` 的去重名字数 |
| 只出现在未翻译 `.nut` 里的 | 52 | 主要是 creator_mage 的弹窗/光标 UI 与 `*_common.nut` 的杂项，见 §3.3 |
| 有调用证据的总覆盖 | **433** | 381 + 52 |

> 97 个零调用桩里，比较典型的是 `sq_GetPopupWindows`、`sq_SetClipCursor`、`sq_GetStateCashShop`、`sq_OpenPopupWindow`——整套「创造者法师鼠标 UI」在翻译版里只被 `creatormage_common` 用到，而那份文件没有翻译。

### 1.2 调用频次分层

| 层 | 名字数 | 代表 |
|---|---|---|
| > 150 次 | 5 | `sq_IntVectPush`(199)、`sq_LoadSkillEffectAni`(195)、`sq_BinaryWriteDword`(167)、`sq_GetLevelData`(157)、`sq_AddSetStatePacket`(157) |
| 50 ~ 150 次 | 23 | `sq_GetIntData`(150)、`sq_GetSkillLevel`(133)、`sq_GetCurrentAttackInfo`(127)、`sq_PlaySound`(126)、`sq_IntVectClear`(121)、`sq_SetCurrentAnimation`(100)、`sq_SendDestroyPacketPassiveObject`(98)、`sq_GetGlobalIntVector`(90) |
| 10 ~ 50 次 | 80 | `sq_IntVectorPush`(89)、`sq_SetCurrentAttackBonusRate`(84)、`sq_GetCurrentAnimation`(73)、`sq_SendCreatePassiveObjectPacket`(71)、`sq_IntVectorClear`(69)、`sq_GetDistancePos`(66)、`sq_CreateCNRDAnimation`(62)、`sq_AddStateLayerAnimation`(62) |
| < 10 次 | 278 | 长尾，含 5 个内建（`printc` 18、`setCurrentAnimationFromCutomIndex` 13、`isSameObject` 7、`checkModuleType` 3、`isDebugMode` 1） |

频次分布本身就是结论：**前 30 个 API 覆盖了一半以上的调用点**，它们集中在四个机制上——IntVect 传参、状态包、二进制打包、动画取帧。先把这四个机制做实，脚本层就能跑起来；长尾 278 个基本是各技能的个性化查询/表现。

调用点分布（按目录）：

| 目录 | 调用点 | 文件数 |
|---|---|---|
| `character/atmage/**`（男法师 11 技能 + 公共） | 3805 | 107 |
| `character/priest/**` + `character/creatormage/**` | 约 1200 | 55 |
| `appendage/**`、`passiveobject/**` | 约 300 | 20 |

### 1.3 「要跑通一个技能」最少需要什么

以火柱（`character/atmage/firepillar/`）+ 链电（`character/atmage/chainlightning/`）这 5 个文件为最小样本，实测只用到 **68 个 `sq_*`**（228 个调用点）。这 68 个可归成 8 组：

1. **状态机**：`sq_IsUseSkill` / `sq_IsCommandEnable` / `sq_AddSetStatePacket` / `sq_addSetStatePacket` / `sq_GetState` / `sq_GetStateTimer` / `sq_GetVectorData`
2. **IntVect**：`sq_IntVectClear` / `sq_IntVectPush` / `sq_GetGlobalIntVector` / `sq_IntVectorClear` / `sq_IntVectorPush`
3. **二进制打包**：`sq_BinaryStartWrite` / `sq_BinaryWriteDword` / `sq_BinaryWriteWord`
4. **动画**：`sq_SetCurrentAnimation` / `sq_GetCurrentAnimation` / `sq_GetCurrentAni` / `sq_GetCurrentFrameIndex` / `sq_GetCurrentTime` / `sq_CreateAnimation` / `sq_CreatePooledObject` / `sq_AddObject` / `sq_setCurrentAnimation`(方法式)
5. **坐标/运动**：`sq_GetXPos` / `sq_GetYPos` / `sq_GetZPos` / `sq_SetCurrentPos` / `sq_setCurrentAxisPos` / `sq_GetDistancePos` / `sq_GetUniformVelocity` / `sq_StopMove` / `sq_GetDirection` / `sq_GetOppositeDirection`
6. **攻击信息**：`sq_GetCurrentAttackInfo` / `sq_SetCurrentAttackBonusRate` / `sq_SetCurrentAttackeDamageAct` / `sq_SetAttackInfoHitDelayRateDamager`
7. **被动对象**：`sq_SendCreatePassiveObjectPacket` / `sq_SendCreatePassiveObjectPacketFromPassivePos` / `sq_SendDestroyPacketPassiveObject` / `sq_GetPassiveObject` / `sq_GetObjectByObjectId` / `sq_GetObjectId`
8. **表现**：`sq_PlaySound` / `sq_SetShake` / `sq_SetStaticSpeedInfo` / `sq_GetCastTime` / `sq_GetFrameStartTime` / `sq_StartDrawCastGauge` / `sq_EndDrawCastGauge`

**但 68 个 `sq_*` 不是全部成本**：这 5 个文件还调了 24 个**不带 `sq_` 前缀的对象方法**，它们是 `CNRDObject` / `CNRDCharacter` 的宿主方法，同样得实现——

`getVar`(150 次，变量系统，见 §4.6) / `isMyControlObject`(30) / `getSkillSubState`(17) / `addSetStatePacket`(15) / `readDword`(10) / `readWord`(9) / `getVector`(9) / `getXPos|getYPos|getZPos`(各 6) / `get_obj_vector_size`(6) / `setCurrentAnimation`(5) / `getCurrentAnimation`(5) / `setCurrentDirection`(5) / `getState`(4) / `getDirection`(4) / `setValid`(3) / `get_obj_vector`(3) / `setSkillSubState`(2) / `resize`(2) / `push_vector`(2) / `setCurrentPos`(2) / `isOnEvent`(2) / plus 被动对象的 `getTopCharacter` / `isMeleeAttack` / `isMissileObject` / `resetHitObjectList` / `setImageRate`。

> 结论：**跑通一个技能 ≈ 68 个 `sq_*` + 24 个对象宿主方法 + 一个 IntVect/二进制包模型**。这构成 M0（§5.1）。

### 1.4 这套绑定在 GDScript 上的整体可行性

**主体可以照搬**：478 个桩已经统一签名（16 个可选参），参数语义清楚，返回值只有四种——`null` / `int` / `float` / 宿主对象引用。绝大多数 `sq_*` 是「查询数据」或「往全局缓冲里塞值」，在 Godot 里都是几行代码。

**真正没有对应物的是 6 个机制**（详见 §5.4）：

| 机制 | 为什么难 | 折中 |
|---|---|---|
| `sq_BinaryStartWrite` / `sq_BinaryWrite*` + 接收端 `readDword` | 宿主用一条**全局写缓冲**，写完由引擎塞进包体；脚本侧看不到 buffer 对象 | 用单例 `PacketBuffer`（`PackedByteArray` + 读指针），`BinaryStartWrite` 清空、`Write*` 追加、`BinaryGetReadSize` 返回写指针 |
| `sq_BinaryParameterStartWrite` | 第二条**并行**全局缓冲（参数缓冲），与主缓冲独立 | 第二个 `PackedByteArray` 实例 |
| `sq_GetGlobalIntVector` | 全局共享的 IntVect，跨调用复用 | 单例 `Array[int]`，`IntVectorClear` 原地清空 |
| `sq_SetStaticSpeedInfo` / `sq_setAnimationSpeedRate` / `sq_SetFrameDelayTime` | 直接改引擎动画时间轴（帧停留毫秒） | Godot `AnimationPlayer` 的 `speed_scale` + 自维护 `frame_delays` 表（按下标查 ms），`SetFrameDelayTime` 改表 |
| `sq_AddStateLayerAnimation` | 往角色身上叠「第二/第三层动画」（图层 1/2），与主 Ani 同步 | 子 `AnimationPlayer` + 每层一个 `Sprite2D`，父子节点同步 `frame` |
| `IMouse.GetXPos` | 取鼠标世界坐标，脚本用来让技能落在鼠标位置 | `get_global_mouse_position()` + 相机反变换 |

其余都是「照搬参数签名 + 引擎适配层」的活。

---

## 2 核心 API 详解（79 个）

分组不是按字母，而是按「脚本跑起来时按什么顺序用到」：状态机 → 技能数据 → 传参（IntVect/二进制）→ 动画 → 坐标运动 → 攻击信息 → 被动对象与附加体 → 表现 → 杂项。

### 2.A 状态机与技能入口（9）

#### `sq_IsUseSkill(SKILL_X) -> bool`
语义：判断这个技能此刻能否起手（冷却、前置、技能键是否按下都由引擎判定）。实参恒为 `SKILL_*` 常量，返回值直接进 `if`，判断成立后紧跟 `sq_IntVectClear` + `sq_AddSetStatePacket`。
参数：技能 ID。落地：技能表 `can_use(id) -> bool`；M0 阶段可先恒 `true`，让链路先跑通。
位置：`character/atmage/elementalchange/elemental_change.gd:18`、`character/atmage/darknessmantle/darknessmantle.gd:29`、`character/atmage/resonance/resonance.gd:20`

#### `sq_IsCommandEnable(SKILL_X) -> bool`
语义：判断技能是否处于「命令可取消硬直」状态——用在 `checkCommandEnable_*` 回调里，只有返回 `true` 时当前动作（普攻/施法中）才允许被这个技能打断。`character/atmage/elementalchange/elemental_change.gd:86` 先取 `sq_GetState()`，只在 `STATE_ATTACK` 时才问这个问题，其余状态直接 `return true`。
参数：技能 ID。落地：`state_allow_cancel(skill_id) -> bool`，默认 `true`。
位置：`character/atmage/elementalchange/elemental_change.gd:86`、`character/atmage/darknessmantle/darknessmantle.gd:51`

#### `sq_AddSetStatePacket(state, priority, bool) -> void`
语义：请求切状态（真正生效在下一 tick，见 `analysis/00-SYSTEM.md:247`）。第 2 参是优先级枚举 `STATE_PRIORITY_*`，决定能否被更高优先级的状态抢占；第 3 参**推断**为「是否重置该状态的计时/是否立刻生效」（`analysis/09-script-mechanics.md:385` 记作 `resetTimer`），调用现场里 `true`/`false` 两种都有（`sqr_src_utf8/sqr` 统计：`true` 96 次、`false` 75 次），没有一处注释说明差别。
参数：`state` 状态 ID、`priority` 优先级、`bool` 见上（推断）。落地：`set_state(state, priority, reset_timer)`；配套的 `sq_IntVectPush` 队列须在切换时整体交给新状态。
位置：`character/atmage/elementalchange/elemental_change.gd:66`、`character/atmage/darknessmantle/darknessmantle.gd:35`、`character/atmage/firepillar/firepillar.gd:26`

#### `sq_addSetStatePacket(state, intVec, priority, bool, prefix) -> void`
语义：带**显式 IntVect** 的切状态版本，额外还能指定回调前缀（第 5 参空串 = 用默认前缀）。与 `sq_AddSetStatePacket` 的区别只在「向量从哪来」：那个用对象身上的隐式向量，这个由调用方传。
参数：`state`、`IntVect`（`sq_GetGlobalIntVector()` 产物）、`priority`、`bool`、`prefix: String`。落地：`set_state_with_args(state, args: Array[int], priority, reset, prefix)`。
位置：`character/priest/awakenningturnoff.gd:124`、`character/priest/spincutter.gd:28`

#### `sq_GetState() -> int`
语义：取当前状态 ID（`STATE_*`）。用于「现在是不是普攻/站立」这类判断，**不**用于判断技能内部子阶段（那用 `obj.getSkillSubState()`）。
参数：无（方法式 `obj.sq_GetState()`）。落地：`current_state: int` 字段。
位置：`character/atmage/elementalchange/elemental_change.gd:81`、`character/atmage/darknessmantle/darknessmantle.gd:46`

#### `sq_GetStateTimer() -> int`
语义：当前状态已经持续了多少毫秒，用于「按住超过 N ms 才进入下一段」。`character/atmage/firepillar/firepillar.gd:193` 取它和「抓住旋风的最大时间」比较，判定是否超时松手。
参数：无。落地：`state_elapsed_ms`，由状态机每帧累加。
位置：`character/atmage/firepillar/firepillar.gd:193`、`character/atmage/elementalbuster/elementalbuster.gd:436`

#### `sq_GetVectorData(vec, i) -> int`
语义：从状态向量里按**下标**取值——`onSetState` / `onProc` 收到的 `datas` 参数就是这个向量，配合 `sq_IntVectPush` 的压入顺序读回。压 6 个就读 0..5。
参数：`vec`（回调传入的向量）、`i`（下标，0 起）。落地：`func on_set_state(datas: Array[int])`，直接下标访问。
位置：`character/atmage/darknessmantle/darknessmantle.gd:62`、`character/atmage/icechakram/icechakram.gd:57`

#### `sq_IsMyControlObject() -> bool`
语义：是否为本地主控端对象。**所有「创建被动对象 / 发包 / 改攻击信息」的写操作都必须包在它里面**，否则联机会双发；只影响表现（音效、闪屏）的调用一般也包。
参数：无。落地：Godot 单机版恒 `true`；联机时需要 `is_multiplayer_authority()`。
位置：`character/atmage/resonance/resonance.gd:135`、`character/atmage/elementalrain/elementalrain.gd:77`、`character/atmage/elementalrain/elementalrain.gd:154`

#### `sq_SetSkillSubState(n) -> void`
语义：设置技能内部子阶段号，后续 `onProc_*` 用 `obj.getSkillSubState()` 读它分派。整个语料只用了 1 次，但对应的读侧 `getSkillSubState` 有 17 次——子阶段主要靠**读**驱动。
参数：子阶段整数。落地：`skill_sub_state: int` 字段 + `set_skill_sub_state()`。
位置：`character/atmage/fireroad/fire_road.gd:66`

### 2.B 技能数据（7）

#### `sq_GetSkillLevel(obj, SKILL_X) -> int`
语义：取该角色这个技能当前等级，0 表示没学。绝大多数调用点直接把它当第 3/4 参喂给 `sq_GetLevelData` / `sq_GetIntData`，是「读技能数值」的标准前戏。
参数：对象、技能 ID。落地：角色技能表 `skill_levels: Dictionary[String, int]`。
位置：`character/atmage/atmage_throw.gd:26`、`character/atmage/firepillar/firepillar.gd:85`、`character/atmage/darknessmantle/darknessmantle.gd:82`

#### `sq_GetLevelData(obj, SKILL_X, column, level) -> number`
语义：查**技能等级表**的某一列。列语义随技能而变，只能从调用点反推：`character/atmage/firepillar/firepillar.gd:91` 第 1 列 = 飞出距离；同文件第 0 列 = 毫秒数（直接喂 `sq_SetFrameDelayTime` 见 §2.D）；`character/atmage/passive_skill_atmage.gd:21` 第 1 列 = 被动技能加的魔法攻击力。返回值可能是 int 也可能是 float。
参数：对象、技能 ID、列号（0 起）、技能等级。落地：`Dictionary[skill_id][level][column]`，从 PVF `.skl` 导出。
位置：`character/atmage/passive_skill_atmage.gd:21`、`character/atmage/atmage_throw.gd:28`、`character/atmage/firepillar/firepillar.gd:91`

#### `sq_GetIntData(obj, SKILL_X, idx[, level]) -> int`
语义：查技能的**整数参数槽**（`[int data]` 段），与 `GetLevelData` 的区别是不跟等级走（第 4 参缺省）。已证实的槽位语义：火柱 `idx 0` = 飞出到达时间（1/1000 秒）、`idx 1` = 抓住旋风的最大时间 ms（`character/atmage/firepillar/firepillar.gd:195` 行内【译注】写明）、`idx 2` = 多段间隔；链电围墙 `idx 3` = 电流僵直时间 ms。
参数：对象、技能 ID、槽号、可选等级。落地：`skill_int_data[skill_id][idx]`。
位置：`character/atmage/atmage_throw.gd:51`、`character/atmage/firepillar/firepillar.gd:87`、`character/atmage/darknessmantle/darknessmantle.gd:200`

#### `sq_GetBonusRateWithPassive(SKILL_X, state, idx, base) -> float`
语义：把「被动技能的加成率」叠进一个基础倍率，返回最终倍率（1.0 = 100%）。第 3 参是加成条目的下标，第 4 参是基础值（多数传 1.0）。结果直接喂给 `sq_SetCurrentAttackBonusRate`。
参数：技能 ID、状态 ID、被动索引、基础倍率。落地：`bonus = base * (1 + sum(passive_rate(state, idx)))`。
位置：`character/atmage/darknessmantle/darknessmantle.gd:205`、`character/atmage/icechakram/icechakram.gd:93`、`character/atmage/firepillar/firepillar.gd:89`

#### `sq_GetPowerWithPassive(SKILL_X, state, idx, base, rate) -> float`
语义：与上一条同族，算的是**攻击力数值**而不是倍率：`character/atmage/bluedragonwill/bluedragonwill.gd:142` 用它算被动加成后的总攻击力。第 4 参在语料里恒为 `-1`（表示「用技能自己的基础值」）。
参数：技能 ID、状态 ID、索引、基础值（-1 = 自动）、倍率。落地：与 `GetBonusRateWithPassive` 共用一套被动表，最后乘攻击力基数。
位置：`character/atmage/bluedragonwill/bluedragonwill.gd:142`、`character/atmage/iceman/iceman.gd:215`

#### `sq_GetCastTime(obj, SKILL_X, level) -> int`
语义：取该技能在该等级的**施法时长（毫秒）**。`character/atmage/darknessmantle/darknessmantle.gd:87` 拿它和动画第 16 帧的起始时间做比值，算出播放倍速再喂 `sq_SetStaticSpeedInfo`——这是「动画时长对齐施法时间」的标准做法。
参数：对象、技能 ID、等级。落地：`cast_time_ms = skill_cast_time[id][level]`。
位置：`character/atmage/darknessmantle/darknessmantle.gd:87`、`character/atmage/resonance/resonance.gd:96`

#### `sq_GetSkill(obj, SKILL_X) -> skill | null`
语义：取技能对象本体（可判空），用来问技能自身状态，例如「是否已经学会/是否处于封印」。`character/atmage/passive_skill_atmage.gd:47` 判空后才继续挂被动。
参数：对象、技能 ID。落地：`Dictionary[skill_id] -> SkillData`，未学返回 `null`。
位置：`character/atmage/passive_skill_atmage.gd:47`、`character/atmage/elementalrain/po_elementalrainbigball.gd:66`

### 2.C IntVect 与二进制打包（11）

#### `sq_GetGlobalIntVector() -> IntVect`
语义：取**全局共享**的整数向量实例（不是新建）。惯例是「取来 → `sq_IntVectorClear` → 逐个 `push` → 交给 `addSetStatePacket` / `SendCreatePassiveObjectPacket`」。因为是共享实例，取到后必须先清空。
参数：无。落地：单例 `Array[int] g_int_vector`，`IntVectorClear` 原地 `clear()`。
位置：`character/atmage/darknessmantle/po_atdarknessmantle.gd:342`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:609`

#### `sq_IntVectorClear(vec) -> void`
语义：清空**传入的**向量（对比 `sq_IntVectClear` 清的是对象身上的隐式向量）。与 `GetGlobalIntVector` 成对出现，见上。
参数：向量。落地：`vec.clear()`。
位置：`character/atmage/darknessmantle/po_atdarknessmantle.gd:343`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:610`

#### `sq_IntVectorPush(vec, v) -> void`
语义：往传入的向量尾部压一个整数。压入顺序 = 接收端（被动对象的 `setCustomData` 或 `onSetState`）的读取顺序。
参数：向量、整数值。落地：`vec.append(v)`。
位置：`character/atmage/darknessmantle/po_atdarknessmantle.gd:344`、`character/atmage/chainlightning/po_atchainlightning.gd:151`

#### `sq_IntVectClear() -> void`
语义：清空**对象身上**的隐式状态向量。`sq_AddSetStatePacket` 的状态参数就是从这个向量里读的，所以模式恒为「先 Clear 再连续 Push 再 AddSetStatePacket」。
参数：无（方法式）。落地：`self._state_vector.clear()`。
位置：`character/atmage/elementalchange/elemental_change.gd:54`、`character/atmage/darknessmantle/darknessmantle.gd:32`、`character/atmage/firepillar/firepillar.gd:23`

#### `sq_IntVectPush(v) -> void`
语义：往对象隐式状态向量压一个参数。**全库最高频（199 次）**，因为所有带参数的切状态都靠它。`character/atmage/elementalchange/elemental_change.gd:55` 是最好的一份样本：连压 6 个，每个都带行内注释说明位置含义（`throwAnimationIndex` / `chargeSpeedType` / `throwShootSpeedType` / `chargeSpeedValue` / `throwShootSpeedValue` / `personalCastRange`）。
参数：一个整数（也见过传 `-1` 表「不启用」）。落地：`self._state_vector.append(v)`。
位置：`character/atmage/elementalchange/elemental_change.gd:55`、`character/atmage/firepillar/firepillar.gd:24`、`character/atmage/darknessmantle/darknessmantle.gd:33`

#### `sq_BinaryStartWrite() -> void`
语义：开始一次**新的**二进制写包（等价于清空全局写缓冲并把写指针归零）。之后连续的 `sq_BinaryWrite*` 依次追加，直到把包交给 `sq_SendCreatePassiveObjectPacket` 之类的发送函数。
参数：无。落地：单例 `PacketBuffer.reset()`（`PackedByteArray` + 写指针）。
位置：`character/atmage/atmage_throw.gd:125`、`character/atmage/darknessmantle/darknessmantle.gd:218`、`character/atmage/firepillar/firepillar.gd:96`

#### `sq_BinaryWriteDword(v) -> void`
语义：往写缓冲追加一个 32 位整数（167 次，写包主力）。发过去的包由被动对象的 `receiveData.readDword()` 逐个读回，**顺序必须严格对齐**：`character/atmage/firepillar/firepillar.gd:97-103` 写 4 个 dword（攻击力率/距离/到达时间/间隔），`po_atfirepillar.gd` 就按同样顺序读 4 个。
参数：整数值（负数按补码写）。落地：`buf.encode_s32(pos, v)` 或 `buf.append_array(PackedByteArray)`；读侧 `decode_s32`。
位置：`character/atmage/darknessmantle/darknessmantle.gd:219`、`character/atmage/darknessmantle/darknessmantle.gd:220`、`character/atmage/firepillar/firepillar.gd:97`

#### `sq_BinaryWriteWord(v) -> void`
语义：追加一个 16 位整数，用于「小范围的枚举/下标」（技能状态 ID、动画下标）。与 `readWord()` 配对。
参数：0..65535。落地：`buf.encode_u16`。
位置：`character/atmage/elementalrain/po_elementalrainbigball.gd:82`、`character/atmage/chainlightning/chainlightning.gd:131`

#### `sq_BinaryWriteFloat(v) -> void`
语义：追加一个 32 位浮点，用于角度、比例这类连续量；接收端 `receiveData.readFloat()`。`character/atmage/icechakram/icechakram.gd:386` 写两个浮点（水平角/垂直角）。
参数：浮点。落地：`buf.encode_float`。
位置：`character/atmage/icechakram/icechakram.gd:386`、`character/atmage/elementalrain/po_elementalraincreator.gd:118`

#### `sq_BinaryGetReadSize() -> int`
语义：返回**当前读缓冲已消费的字节数**。`character/atmage/multishot/po_magic_ball.gd:47` 用它和 `receiveData.getSize()` 比较，做「包里还有没有下一段」的循环读取——说明它是读侧的游标而不是写侧长度。
参数：无。落地：读包对象 `read_pos`。
位置：`character/atmage/jumpattack/po_magic_ball.gd:45`、`character/atmage/jumpattack/po_magic_ball.gd:56`

#### `sq_BinaryParameterWriteDword(v) -> void`
语义：往**第二条并行缓冲**（参数缓冲）写一个 dword。`character/creatormage/firemeteo/firemeteo.gd:54` 连续写两个再发包，接收端用另一套读取接口取——它承载的是「给引擎看的参数」而不是「给脚本看的自定义数据」。
参数：整数值。落地：第二个 `PackedByteArray`（`param_buf`），与主缓冲独立。
位置：`character/creatormage/firemeteo/firemeteo.gd:54`、`character/creatormage/firemeteo/firemeteo.gd:55`

### 2.D 动画（14）

#### `sq_SetCurrentAnimation(CUSTOM_ANI_X) -> void`
语义：按**自定义动画索引**切换角色当前动画。实参恒为脚本自己定义的 `CUSTOM_ANI_*` 常量（这些常量最终映射到角色 `.ani` 里的帧段），是 `onSetState` 里「这个状态放哪段动作」的唯一入口。
参数：自定义动画索引（int）。落地：`ani_map: Dictionary[String, Animation]`，索引 → `.ani` 资源。
位置：`character/atmage/darknessmantle/darknessmantle.gd:80`、`character/atmage/firepillar/firepillar.gd:75`、`character/atmage/icechakram/icechakram.gd:118`

#### `sq_GetCurrentAni() -> animation | null`
语义：取对象当前的动画实例（无参方法式）。与 `sq_GetCurrentAnimation(obj)` 是同一件事的两种写法，语料里 36 次；拿到后一般立刻交给 `sq_GetCurrentFrameIndex` / `sq_GetCurrentTime` 查询播放进度。
参数：无。落地：`current_ani: Animation`。
位置：`character/atmage/darknessmantle/darknessmantle.gd:156`、`character/atmage/darknessmantle/darknessmantle.gd:190`

#### `sq_GetCurrentAnimation(obj) -> animation | null`
语义：取**指定对象**的当前动画（73 次，最常用的动画句柄来源）。可对角色也可对被动对象/绘制对象调用：`character/atmage/darknessmantle/po_atdarknessmantle.gd:619` 取的是另一个绘制对象的动画，用它判断那段特效有没有播完。
参数：对象。落地：`obj.current_ani`。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:58`、`character/atmage/darknessmantle/darknessmantle.gd:88`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:619`

#### `sq_GetCurrentFrameIndex(ani) -> int`
语义：当前播放到第几帧（0 起）。用于「播到第 N 帧就生成判定/停下」这类分帧逻辑，与 `onKeyFrameFlag` 里的 `flagIndex` 互补。
参数：动画。落地：`ani.current_frame`。
位置：`character/atmage/darknessmantle/darknessmantle.gd:157`、`character/atmage/darknessmantle/darknessmantle.gd:191`

#### `sq_GetCurrentTime(ani) -> int`
语义：当前动画已播放的**毫秒数**（不是帧号）。用于和「某帧起始时间」比较，判断是否越过关键帧。
参数：动画。落地：`ani_elapsed_ms`。
位置：`character/atmage/darknessmantle/darknessmantle.gd:158`、`character/atmage/darknessmantle/darknessmantle.gd:192`

#### `sq_GetFrameStartTime(ani, frame) -> int`
语义：第 `frame` 帧的起始时间（毫秒）。`character/atmage/darknessmantle/darknessmantle.gd:89` 取第 16 帧起点 `startTime`，再用 `startTime / castTime` 得到倍速——「让蓄力动作正好铺满施法时间」的标准做法。
参数：动画、帧下标。落地：由 `frame_delays` 表前缀和算出（`sum(delays[0..frame-1])`）。
位置：`character/atmage/darknessmantle/darknessmantle.gd:89`、`character/atmage/resonance/resonance.gd:99`

#### `sq_SetFrameDelayTime(ani, frame, ms) -> void`
语义：改某一帧的停留时间。`character/atmage/fireroad/fire_road.gd:80` 把第 0 帧延迟直接设成整段施法时间（`sq_Rewind` 之后调），实现「一帧铺满蓄力」——这是脚本层唯一直接改时间轴的手段，**在 Godot 里没有等价物**（须自维护帧延迟表）。
参数：动画、帧下标、毫秒。落地：`ani.frame_delays[frame] = ms`，动画播放器每帧按表推进。
位置：`character/atmage/fireroad/fire_road.gd:80`

#### `sq_IsEnd(ani) -> bool`
语义：动画是否播完（到达末帧并结束）。被动对象自毁、循环特效收尾都靠它。
参数：动画。落地：`ani.is_finished()`（Godot `AnimationPlayer.animation_finished`）。
位置：`character/atmage/darknessmantle/po_atdarknessmantle.gd:621`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:687`

#### `sq_CreateAnimation(name, aniPath) -> animation`
语义：从 `.ani` 路径创建一个独立动画实例（不进对象池）。第 1 参是名称前缀，语料里恒为空串 `""`，说明它只是历史遗留形参。
参数：名称（`""`）、`.ani` 相对路径。落地：`preload/load(ani_path)` + `AnimationPlayer` 实例化。
位置：`common.gd:143`、`common.gd:157`、`character/atmage/icechakram/po_aticechakramsmallmgr.gd:29`

#### `sq_CreateCNRDAnimation(aniPath) -> animation`
语义：同上的**便捷版**（省掉名称参数，62 次，比 `sq_CreateAnimation` 常用一倍）。产物通常立刻进 `sq_AddStateLayerAnimation` 或 `sq_AddObject`。
参数：`.ani` 路径。落地：同 `sq_CreateAnimation`。
位置：`character/atmage/resonance/resonance.gd:82`、`character/atmage/resonance/resonance.gd:83`

#### `sq_CreatePooledObject(ani, bool) -> object`
语义：把动画包成一个「可池化对象」，返回的对象有 `setCurrentPos` / `setCurrentDirection` / `setValid` 等宿主方法。`common.gd:112` 用的是小写别名 `sq_createCNRDPooledObject(ani, true)`，第 2 参**推断**为「是否入池复用」（同族 `sq_CreateDrawOnlyObject` 的第 4 参是「是否跟随父对象」，语义不同）。
参数：动画、bool（推断：池化开关）。落地：`PooledAni` 节点 + 对象池（`Array[PooledAni]`）。
位置：`character/atmage/icechakram/po_aticechakramsmallmgr.gd:31`、`common.gd:112`

#### `sq_AddObject(obj, pooled[, type, follow]) -> void`
语义：把生成的对象挂到 `obj` 名下，随 `obj` 一起销毁。两种形态：1 参式 `obj.sq_AddObject(pooledObj)`（`common.gd:117`，纯悬挂）；4 参式 `sq_AddObject(obj, pooledObj, OBJECTTYPE_DRAWONLY, false)`（`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:43`，带对象类型与是否跟随）。第 3 参 `OBJECTTYPE_*` 决定它是否参与碰撞/绘制层。
参数：宿主对象、被挂对象、`OBJECTTYPE_*`、是否跟随。落地：`add_child(pooled)` + `type` 分流到「纯绘制层 / 判定层」。
位置：`common.gd:117`、`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:43`

#### `sq_AddStateLayerAnimation(layer, ani, keyFrame, yOffset) -> void`
语义：往角色身上叠**附加动画层**。`character/atmage/resonance/resonance.gd:82` 的【译注】把四个参数全写明了：层 1 = 身体描边、层 2 = 水波；`6` = 叠加动画从第 6 帧起播（与主动画对齐）；`-68` = 相对角色原点的 Y 偏移像素。同一层可以连续叠多条。
参数：层号 1|2、动画、对齐帧号、Y 偏移。落地：每层一个 `Sprite2D` + 子 `AnimationPlayer`，`frame` 跟随主动画、`offset.y = yOffset`。
位置：`character/atmage/resonance/resonance.gd:82`、`character/atmage/resonance/resonance.gd:84`

#### `setCurrentAnimationFromCutomIndex(obj, idx) -> void`
语义：**无前缀内建**（原文拼写 `Cutom` 不是笔误，桩里就这么写），按自定义动画索引切动画。与 `sq_SetCurrentAnimation` 的区别在于它是「对指定对象」且带 `FromCustomIndex` 语义——`character/atmage/icechakram/po_aticechakramlarge.gd:169` 用它给**被动对象自己**播泛白动画。
参数：对象、自定义动画索引。落地：`obj.play_custom_ani(idx)`。
位置：`character/atmage/icechakram/po_aticechakramlarge.gd:169`、`character/atmage/icechakram/po_aticechakramlarge.gd:176`

### 2.E 坐标与运动（12）

#### `sq_GetXPos(obj) -> int`
语义：取对象世界坐标 X（像素）。与 `sq_GetYPos` / `sq_GetZPos` 三件套恒一起出现，用来把对象的当前位置抄到新生成的对象上，或算距离。
参数：对象。落地：`obj.global_position.x`（脚本坐标系 Y 向下、Z 为高度，见 §5.3 坐标约定）。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:29`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:192`

#### `sq_SetCurrentPos(obj, x, y[, z]) -> void`
语义：直接设置对象坐标（瞬时传送，不产生移动）。被动对象每帧更新位置、技能把角色拉回原位都用它；第 3 参 z 省略时只看平面。
参数：对象、x、y、可选 z。落地：`obj.global_position = Vector3(x, y, z)`。
位置：`character/atmage/icechakram/po_aticechakramlarge.gd:220`、`character/atmage/elementalrain/elementalrain.gd:75`

#### `sq_setCurrentAxisPos(obj, axis, v) -> void`
语义：只改**单个轴**（小写开头 = 引擎侧的另一个重载族）。`character/atmage/darknessmantle/po_atdarknessmantle.gd:176` 用它逐帧改高度轴做悬浮，避免整坐标重设。
参数：对象、轴号（`0|1|2` 对应 X/Y/Z）、新值。落地：`obj.position[axis] = v`。
位置：`character/atmage/darknessmantle/po_atdarknessmantle.gd:176`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:260`

#### `sq_GetDistancePos(start, direction, distance) -> int`
语义：从 `start` 沿 `direction` 走 `distance` 像素后的坐标——**返回新坐标，不改任何东西**。66 次，是「朝面向方向生成东西」的唯一正确写法。三轴通用：语料里既有 `sq_GetDistancePos(obj.getXPos(), sq_GetDirection(obj), d)`，也有 `sq_GetDistancePos(obj.getYPos(), ENUM_DIRECTION_DOWN, d)`（`character/atmage/icechakram/icechakram.gd:367`），说明方向枚举同时编码了轴和正负。
参数：起始坐标、方向枚举、距离。落地：`ENUM_DIRECTION_LEFT=0 / RIGHT=1 / UP=2 / DOWN=3 / NEUTRAL=4`（`sqr_consts.gd:88-92`），**推断**映射为「偶数减、奇数加、4 不动」：`start + (dir==4 ? 0 : (dir % 2 == 0 ? -d : d))`。依据：`DOWN` 取「+」、`UP` 取「−」才符合屏幕坐标（Y 向下为大），而 `LEFT/RIGHT` 又分别落在 0/1，两者共同满足该奇偶规律。
位置：`character/atmage/icechakram/icechakram.gd:367`、`character/atmage/icechakram/po_aticechakramlarge.gd:220`、`character/atmage/icechakram/po_aticechakramsmallicering.gd:435`

#### `sq_GetUniformVelocity(a, b, curT, totalT) -> float`
语义：匀速插值——`curT/totalT` 从 0 走到 1 时，返回值从 `a` 线性变到 `b`（ms 计时的位移/缩放都用它）。
参数：起点值、终点值、已过时间、总时间。落地：`lerp(a, b, float(cur_t)/total_t)`。
位置：`character/atmage/icechakram/po_aticechakramsmallmgr.gd:86`、`character/atmage/icechakram/po_aticechakramsmallicering.gd:107`

#### `sq_GetAccel(a, b, curT, totalT, bool) -> float`
语义：加速/减速插值。第 5 参**推断**为「是否减速」（`true` = 由快变慢，`false` = 由慢变快）——同一组参数在 5 处出现，两种取值都有，没有直接注释。
参数：起点、终点、已过时间、总时间、bool。落地：`a + (b-a) * t*t`（缓入）或 `a + (b-a) * (1-(1-t)*(1-t))`（缓出）。
位置：`character/atmage/icechakram/po_aticechakramsmallicering.gd:121`、`character/atmage/icechakram/po_aticechakramsmallicering.gd:123`

#### `sq_GetShuttleValue(min, max, time, period) -> int`
语义：三角波往复值——在 `[min, max]` 之间以 `period` 毫秒为一趟来回。`character/atmage/elementalrain/po_elementalraincreator.gd:73` 的【译注】写明「400ms 一个来回的三角波」，用来做上下浮动；`character/atmage/lightningwall/ap_lightningwall.gd:45` 用 40ms 周期做上下抖动。
参数：下限、上限、已过毫秒（常配 `sq_GetObjectTime`）、周期 ms。落地：`min + (max-min) * triangle(t/period)`。
位置：`character/atmage/elementalrain/po_elementalraincreator.gd:73`、`character/atmage/lightningwall/ap_lightningwall.gd:45`

#### `sq_GetObjectTime(obj) -> int`
语义：对象已存活的毫秒数（自创建起的时钟），是 `sq_GetShuttleValue` 的时间源。与 `sq_GetStateTimer`（状态计时）不同：它跨状态存活。
参数：对象。落地：`obj.age_ms`（每帧 `+= delta*1000`）。
位置：`character/atmage/elementalrain/po_elementalraincreator.gd:73`、`character/atmage/lightningwall/ap_lightningwall.gd:45`

#### `sq_StopMove() -> void`
语义：立即停下当前位移（清掉引擎给的移动速度），用于「到位就定住」。`character/atmage/elementalchange/elemental_change.gd:96` 在蓄力开始前调它防止惯性滑走。
参数：无。落地：`velocity = Vector3.ZERO`。
位置：`character/atmage/elementalchange/elemental_change.gd:96`、`character/atmage/darknessmantle/darknessmantle.gd:65`

#### `sq_SetStaticMoveInfo(direction, v1, v2, bool[, accel, bool]) -> void`
语义：设置对象的**恒定移动参数**（方向 + 两个速度值 + 开关）。4 参与 6 参两种形态：4 参是「方向、速度、速度、是否移动」，6 参多出加速度与减速标志。设置后由引擎每帧推动，脚本不用自己积分。
参数：方向、速度、速度、bool、可选加速度、可选 bool。落地：`move_info` 结构 + 物理帧里 `position += dir * speed * delta`。
位置：`character/atmage/elementalrain/elementalrain.gd:94`、`character/atmage/elementalrain/elementalrain.gd:95`

#### `sq_SetStaticSpeedInfo(t1, t2, v1, v2, rate1[, rate2]) -> void`
语义：设置**动画播放速度**的静态参数：两个速度类型（`SPEED_TYPE_*`）、两个速度值、以及两个倍率。`character/atmage/darknessmantle/darknessmantle.gd:91` 传入算好的 `speedRate` = 第 16 帧起点 / 施法时长，让蓄力段正好铺满 `castTime`；`character/atmage/fireroad/fire_road.gd:81` 则用 `1.0, 1.0` 表示「不改速」。
参数：`SPEED_TYPE_CAST_SPEED` 等枚举 ×2、`SPEED_VALUE_DEFAULT` 等值 ×2、倍率 ×2。落地：`AnimationPlayer.speed_scale = rate`（类型/值先忽略，只取倍率）。
位置：`character/atmage/darknessmantle/darknessmantle.gd:91`、`character/atmage/fireroad/fire_road.gd:81`、`character/atmage/atmage_throw.gd:15`

#### `sq_GetDirection(obj) -> int`
语义：取对象当前朝向，返回 `ENUM_DIRECTION_*` 枚举（0..4）。既用于比较（`== ENUM_DIRECTION_LEFT`），也直接喂给 `sq_GetDistancePos` 第 2 参。
参数：对象。落地：`facing: int`，取值就是 `ENUM_DIRECTION_*`（0..4）——对象方法 `obj.getDirection()`（`character/atmage/jumpattack/jump_attack.gd:85` 的 `if obj.getDirection() == ENUM_DIRECTION_LEFT`、`character/atmage/atmage_common.gd:80` 的 `== ENUM_DIRECTION_RIGHT`）也是同一套枚举，说明它不是 ±1。
位置：`character/atmage/icechakram/icechakram.gd:367`、`character/atmage/elementalrain/po_elementalraincreator.gd:95`

### 2.F 攻击信息（5）

#### `sq_GetCurrentAttackInfo(obj) -> attackInfo | null`
语义：取对象当前的攻击信息对象（127 次）。返回的是**可改的引用**：拿到后调 `sq_SetCurrentAttackBonusRate` / `sq_SetChangeStatusIntoAttackInfo` 就是直接改这次攻击，不需要再 set 回去（`character/atmage/darknessmantle/po_atdarknessmantle.gd:532` 就是取来、改完、走人）。可判空。
参数：对象。落地：`attack_info: AttackInfo`（伤害率、属性、状态附加、命中框）。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:33`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:532`、`character/atmage/firepillar/po_atfirepillar.gd:69`

#### `sq_SetCurrentAttackInfo(obj, x) -> void`
语义：切换攻击信息。两种实参：**自定义索引** `obj.sq_SetCurrentAttackInfo(CUSTOM_ATTACK_INFO_RESONANCE)`（`character/atmage/resonance/resonance.gd:77`，从角色 `.atk` 里按索引换一套）；**攻击信息对象** `sq_SetCurrentAttackInfo(obj, sq_GetCurrentAttackInfo(obj))`（`po_magic_ball.gd`，设置完加成率后「刷新」一次提交）。
参数：对象、`CUSTOM_ATTACK_INFO_*` 索引或 attackInfo 对象。落地：前者查 `atk_table[index]`，后者 `attack_info = atk; apply()`。
位置：`character/atmage/resonance/resonance.gd:77`、`character/atmage/elementalrain/po_elementalrainbigball.gd:26`

#### `sq_SetCurrentAttackBonusRate(atk, rate) -> void`
语义：设置本次攻击的**攻击力加成率**（倍率，1.0 = 100%）。84 次，几乎所有被动对象生成时都调一次；值通常来自 `sq_GetBonusRateWithPassive` 或二进制包里读到的浮点。
参数：攻击信息对象、倍率。落地：`attack_info.bonus_rate = rate`，结算时 `damage * bonus_rate`。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:34`、`character/atmage/icechakram/icechakram.gd:132`、`character/atmage/firepillar/po_atfirepillar.gd:70`

#### `sq_SetChangeStatusIntoAttackInfo(atk, slot, status, prob, level, ms) -> void`
语义：给这次攻击附加一个**状态效果**（减速/冰冻/眩晕…）。`po_atdarknessmantle.gd:530-538` 的【译注】写明位序：`0` = 攻击信息里第 0 组状态槽，`100` = 触发概率(%)，`level` = 状态等级、`ms` = 持续时间。同文件状态值来自 `obj.getVar("attack")` 的向量。
参数：攻击信息、槽位、`ACTIVESTATUS_*`、概率%、等级、持续 ms。落地：`attack_info.status_list[slot] = {type, prob, level, ms}`。
位置：`character/atmage/darknessmantle/po_atdarknessmantle.gd:538`、`character/atmage/icefieldex/po_aticefieldex.gd:39`

#### `sq_SendHitObjectPacket(obj, target, 0, 0, heightOffset) -> void`
语义：直接对单个对象结算一次命中（不走碰撞盒）。`character/atmage/chainlightning/po_atchainlightningtarget.gd:77` 的【译注】说明末参是**命中点高度**：取目标身高的一半，让判定落在身体中部。只在 `isMyControlObject()` 里发。
参数：攻击者、目标、两个恒为 0 的保留位（**推断**：帧号/子攻击下标）、命中高度偏移。落地：`deal_damage(target, attack_info, hit_offset_y)`。
位置：`character/atmage/chainlightning/po_atchainlightningtarget.gd:77`、`character/atmage/chainlightning/po_atchainlightningtarget.gd:202`

### 2.G 被动对象与附加体（12）

#### `sq_SendCreatePassiveObjectPacket(poId, layer, x, y, z) -> void`
语义：请求创建一个**被动对象**（特效实体）。5 参式是最常见形态：`obj.sq_SendCreatePassiveObjectPacket(24252, 0, 200, 1, 0)`（`character/atmage/darknessmantle/darknessmantle.gd:231`，poId = 24252 暗影斗篷黑洞），坐标是相对施法者的偏移；7 参式多一个显式对象与方向 `(obj, poId, layer, x, y, z, dir)`。紧邻它之前的 `sq_BinaryWrite*` 序列会成为新对象的 `receiveData`。
参数：poId（`IRDSQRCharacter.pushPassiveObj` 注册的那个整数）、绘制层、x/y/z 偏移。落地：`spawn_passive_obj(po_id, offset)`，把当前 `PacketBuffer` 交给新节点的 `setCustomData`。
位置：`character/atmage/darknessmantle/darknessmantle.gd:231`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:739`、`character/atmage/firepillar/firepillar.gd:106`

#### `sq_SendDestroyPacketPassiveObject(obj) -> void`
语义：销毁一个被动对象（98 次，被动对象生命周期里的 `allDestroy` 都靠它）。传的是**对象引用**而不是 poId；只应主控端调用，且通常伴随一次 `getVar()` 清理。
参数：要销毁的被动对象。落地：`obj.queue_free()`。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:104`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:553`

#### `sq_GetPassiveObject(poId) -> object | null`
语义：按 poId 取**当前已存在**的被动对象实例，可判空；拿到后能读它的状态 `getState()`。用于「我已经生成过一个了，这是同一个吗」这类判断。
参数：poId。落地：`Dictionary[po_id] -> Array[nodes]`（同 ID 可能有多个，语料里只取第一个）。
位置：`character/atmage/icechakram/icechakram.gd:260`、`character/atmage/chainlightning/chainlightning.gd:183`

#### `sq_GetObject(obj, group, uid) -> object | null`
语义：按「对象组 + 唯一 ID」找回一个对象引用——二进制包里只传 32 位整数，接收端靠它换回真实对象。`po_aticechakramlarge.gd:75-83` 先 `readDword()` 读 group、再读 uid，然后 `sq_GetObject(obj, group, uid)` 取回目标，并 `obj.getVar().setObject(0, target)` 缓存。
参数：查询者（用于确定对象表范围）、组号、uid。落地：`groups[group].get(uid)`。
位置：`character/atmage/icechakram/po_aticechakramlarge.gd:83`、`character/atmage/bluedragonwill/bluedragonwill.gd:93`

#### `sq_AppendAppendage(obj, src, SKILL_X, bool, apPath, bool) -> appendage | null`
语义：给 `obj` 挂一个附加体（脚本级 buff/状态机），返回已挂上的附加体对象，失败（已有同名且不允许叠加）返回 `null`。`character/atmage/passive_skill_atmage.gd:16` 的【译注】给出位序：「主人、来源、技能 ID、是否强制、附加体脚本路径、是否唯一/替换」。这是整个附加体系统的主入口。
参数：主人、来源对象、技能 ID、bool、`ap_*.nut` 路径、bool。落地：`appendages[path] = APNode.new(obj, src)`；返回既有实例或 `null`。
位置：`character/atmage/passive_skill_atmage.gd:16`、`character/atmage/lightningwall/po_lightningwall.gd:245`

#### `sq_Append(appendage, obj, obj[, isBuff]) -> void`
语义：把**已经创建好的**附加体挂到对象上（与 `sq_AppendAppendage` 的区别：那个一步到位，这个先有对象再 Append，便于复用一个池里的附加体）。4 参式第 4 参是「打开 buff」标志（`character/atmage/atmage_throw.gd:104` 行内注释「打开 buff」）；另有 5 参式 `ap.sq_Append(obj, obj, APID_x, 0, null)`（`character/atmage/atmage_throw.gd:58`，带 `APID_*` change-status ID，**推断**后两参是条目索引与回调）。
参数：附加体、主人、目标、可选 isBuff。落地：`target.appendages.add(appendage)`。
位置：`character/atmage/atmage_throw.gd:58`、`character/atmage/atmage_throw.gd:104`

#### `sq_GetAppendage(obj, apPath) -> appendage | null`
语义：按脚本路径取对象身上已挂的附加体，取不到返回 `null`。`character/atmage/elementalchange/ap_atmage_elemental_change.gd:54` 用它跨文件拿「魔法护盾」附加体再去改它的属性。
参数：对象、`ap_*.nut` 路径。落地：`obj.appendages.get(path)`。
位置：`character/atmage/elementalchange/ap_atmage_elemental_change.gd:54`、`character/atmage/tundrasoul/ap_atmage_tundrasoul.gd:137`

#### `sq_RemoveAppendage(obj, apPath) -> void`
语义：按路径摘掉附加体（被动对象结束时清理自己挂上去的东西）。16 次，几乎都出现在 `allDestroy` 一类的收尾函数里。
参数：对象、`ap_*.nut` 路径。落地：`obj.appendages.erase(path)` + 该节点 `queue_free()`。
位置：`character/atmage/darknessmantle/po_atdarknessmantle.gd:550`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:562`

#### `sq_IsAppendAppendage(obj, apPath) -> bool`
语义：查询对象身上有没有某个附加体。`character/atmage/tundrasoul/ap_atmage_tundrasoul.gd:21` 用它在挂之前先去重，避免重复叠同一个光环。
参数：对象、`ap_*.nut` 路径。落地：`obj.appendages.has(path)`。
位置：`character/atmage/tundrasoul/ap_atmage_tundrasoul.gd:21`、`character/atmage/tundrasoul/ap_atmage_tundrasoul.gd:79`

#### `sq_AddChangeStatus(tag, parent, target, slot, type, isAbs, value) -> changeStatus`
语义：给附加体添加一条**属性变更项**（attackChangeStatus 的成员）。`character/atmage/passive_skill_atmage.gd:27` 的【译注】给出位序：「标签、主人、目标、槽位 0、变更类型、是否绝对值（false = 百分比）、初值」。返回值可继续 `clearParameter()` / `addParameter()` 做分级加成。
参数：字符串标签、主人、目标、槽位、`CHANGE_STATUS_TYPE_*`、bool、数值。落地：`ChangeStatus{tag, type, is_abs, value, params: Array}`。
位置：`character/atmage/passive_skill_atmage.gd:27`、`character/atmage/holonglight/po_atholonglight.gd:154`

#### `sq_IsValidActiveStatus(obj, ACTIVESTATUS_X) -> bool`
语义：查询对象当前是否处于某种特殊状态（抓取、僵直、浮空…）。`character/atmage/teleport/teleport.gd:210` 用 `ACTIVESTATUS_HOLD` 判断「是否正被抓住」，是则不做落点修正。
参数：对象、`ACTIVESTATUS_*`。落地：`active_status: int` 位标记。
位置：`character/atmage/teleport/teleport.gd:210`、`character/atmage/iceman/ap_aticemanmagiccircle.gd:90`

#### `sq_HoldAndDelayDie(obj, src, b1, b2, b3, ms1, ms2, dir, appendage) -> void`
语义：让目标「被抓住并延迟死亡」：挂住、给一段僵直、到点再死。`character/atmage/lightningwall/po_lightningwall.gd:247` 传 `(damager, obj, true, true, true, 200, 200, ENUM_DIRECTION_NEUTRAL, masterAppendage)`，三个 bool 与两个 ms 的具体分工没有注释，**推断**为「是否抓取 / 是否禁止行动 / 是否禁止攻击」+「抓取时长 / 死亡延迟」。
参数：目标、来源、3×bool、ms、ms、方向、附加体。落地：`target.hold(src, ms1, dir)` + 延迟 `die()`。
位置：`character/atmage/lightningwall/po_lightningwall.gd:247`、`character/atmage/icecrash/icecrash.gd:197`

### 2.H 表现（7）

#### `sq_PlaySound(soundTag) -> void`
语义：按**音效标签字符串**播音效（126 次）。标签形如 `"MW_FPILLAR"` / `"MW_DMANTLE"` / `"MW_ANCIENT"`，全部是脚本里硬编码的常量串，说明音效资源由 exe 侧按标签查表。个别调用点带第 2 参（音效实例 ID，用于 `stopSound` 精确停止）。
参数：标签字符串、可选实例 ID。落地：`AudioStreamPlayer` + `Dictionary[String, AudioStream]`。
位置：`character/atmage/atmage_buff.gd:16`、`character/atmage/darknessmantle/darknessmantle.gd:99`、`character/atmage/firepillar/firepillar.gd:82`

#### `sq_flashScreen(obj, f1, f2, f3, f4, rgb, effect, layer) -> fScreen`
语义：创建一个闪屏效果，**返回句柄**，句柄可直接交给 `sq_addFlashScreen` 追加第二段。实际调用 `sq_flashScreen(obj, 0, 80, 0, 80, sq_RGB(255,255,255), GRAPHICEFFECT_NONE, ENUM_DRAWLAYER_BOTTOM)`；`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:48` 的【译注】给出的位序是（对象、起始、结束、起始、结束、颜色、图形效果、绘制层），即 `f1..f4` 是两组「起止帧」——**推断**为「淡入起止 + 淡出起止」，不是毫秒也不是 alpha。
参数：见上。落地：全屏 `ColorRect` + `Tween`（按帧换算时间），`effect` 对应后处理（`GRAPHICEFFECT_*`）。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:48`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:712`

#### `sq_addFlashScreen(fScreen, f1, f2, f3, f4, rgb, effect, layer) -> void`
语义：往已有闪屏句柄上**追加**一段，位序与 `sq_flashScreen` 相同但第 1 参换成句柄：`sq_addFlashScreen(fScreen, 0, 240, 240, 150, sq_RGB(0,0,0), GRAPHICEFFECT_NONE, ENUM_DRAWLAYER_BOTTOM)`（白色闪完接黑色）。
参数：闪屏句柄 + 其余同 `sq_flashScreen`。落地：句柄对象持有 `segments: Array[FlashSegment]`，按序播放。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:49`、`character/atmage/icechakram/po_aticechakramlarge.gd:194`

#### `sq_RGB(r, g, b) -> color`
语义：用 0~255 整数构造颜色（54 次，几乎只作 `sq_flashScreen` / `sq_SetMyShake` 一类函数的实参）。同族还有 `sq_RGBA(r,g,b,a)` 与 `sq_ALPHA(a)`（见 §3）。
参数：r、g、b（0~255）。落地：`Color8(r, g, b)`。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:48`、`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:48`

#### `sq_SetMyShake(obj, strength, ms) -> void`
语义：震屏，且**只震本地玩家**（`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:52` 的【译注】：「只让自己（控制端）震屏，参数 (对象, 强度, 毫秒)」）。同义 API 还有 `sq_SetShake` / `sq_setShake`（大小写变体，语义相同，见 §3）。
参数：对象、强度、毫秒。落地：`Camera2D.offset` 随机抖动，`Timer` 结束。
位置：`character/atmage/darknessmantle/po_atdarknessmantleexp.gd:52`、`character/atmage/darknessmantle/po_atdarknessmantle.gd:215`、`character/atmage/icechakram/icechakram.gd:354`

#### `sq_CreateParticle(ptlPath, obj, x, y, z, follow, life, ?, ?) -> void`
语义：在对象身上挂一个粒子特效（`.ptl`）。实参形态：`sq_CreateParticle("Character/Mage/Effect/Particle/ATIceChakramDust.ptl", obj, 60, -60, 0, true, 350, 1000, 100)`——路径、宿主、x/y/z 偏移、是否跟随、寿命 ms，后两参**推断**为速度与数量（各调用点取值 1 / 100 不等，无注释）。
参数：`.ptl` 路径、宿主对象、x、y、z、bool、寿命、?、?。落地：`GPUParticles2D` + `.ptl` 转换出的配置。
位置：`character/atmage/icechakram/icechakram.gd:356`、`character/atmage/icechakram/icechakram.gd:356`

#### `sq_AddEffectFront(aniPath) -> void`
语义：给附加体叠一条**常驻前层特效动画**（如冰霜之魂的被动光环），与 `appendage.sq_DeleteEffectFront()` 成对使用——先删再加是标准写法（`character/atmage/tundrasoul/ap_atmage_tundrasoulcs.gd:189`）。
参数：`.ani` 路径（挂在附加体上，所以调用者是 `appendage`）。落地：附加体节点下一个 `AnimatedSprite2D`，循环播放。
位置：`character/atmage/tundrasoul/ap_atmage_tundrasoulcs.gd:189`、`character/atmage/diehard/ap_atmage_diehardslowheal.gd:34`

### 2.I 杂项（2）

#### `sq_RunScript(path) -> void`
语义：加载并执行另一个脚本文件——脚本层的「require」。`loadstate.gd:13-14` 是全局装载入口：先 `sq_RunScript("dnf_enum_header.nut")` 再 `common.nut`，之后各职业的 `*_load_state`。只出现在装载期，5 次。
参数：脚本相对路径。落地：`load(path)` 后实例化（翻译版已经把这些静态展开成 `SqrGlobals`，M0 里可以只留空实现）。
位置：`loadstate.gd:13`、`loadstate.gd:14`

#### `sq_GetCNRDObjectToSQRCharacter(obj) -> character | null`
语义：把引擎对象（`CNRDObject`）转成脚本侧的**角色**对象，转换失败返回 `null`。26 次，全在附加体里——因为附加体拿到的是 `parentObj`（引擎对象），要调角色专有方法前必须转一次（`character/atmage/tundrasoul/ap_atmage_tundrasoul.gd:125` 转完立刻判空，空就 `appendage.setValid(false)` 自杀）。
参数：引擎对象。落地：`obj as CharacterNode`（Godot 里两者本就是同一节点，转换可退化成一次 `is CharacterNode` 判断）。
位置：`character/atmage/tundrasoul/ap_atmage_tundrasoul.gd:125`、`character/atmage/tundrasoul/ap_atmage_tundrasoul.gd:217`

---

## 3 其余 API 速查表

### 3.1 频次 ≥2 的 202 个（按频次降序，大表）

§2 已详解的 79 个不重复列出。语义列由调用现场反推；标「推断」的表示只有命名与参数形态支撑。频次 1 的 105 个证据太薄，按 §3.2 的族归纳列出。本章与 §2 合计给出 **438 个名字**的语义（79 详解 + 202 表 + 105 族 + 52 族）。

| API | 反推语义 | 频次 |
|---|---|---|
| `sq_LoadSkillEffectAni` | 给技能登记一张特效动画表，登记顺序即下标 | 195 |
| `sq_GetYPos` | 取对象世界 Y 坐标 | 54 |
| `sq_GetZPos` | 取对象世界 Z 坐标 | 49 |
| `sq_getIntData` | 读技能 int 表第 idx 项（方法式写法） | 43 |
| `sq_setCurrentAnimation` | 按 CUSTOM_ANI 索引切当前动画（方法式写法） | 32 |
| `sq_WriteDword` | 写 dword 到全局写缓冲（同 sq_BinaryWriteDword） | 30 |
| `sq_getCurrentAni` | 取当前播放的动画对象（方法式写法） | 29 |
| `sq_AddObjectParticleCreater` | 按 .ptl 路径给对象加粒子创建器 | 27 |
| `sq_getRandom` | 取 [min, max) 随机整数（方法式写法） | 27 |
| `sq_setCurrentAttackInfo` | 换当前攻击信息（方法式写法） | 25 |
| `sq_Abs` | 绝对值 | 24 |
| `sq_SetMoveParticle` | 设置移动拖尾粒子（路径, 水平角, 垂直角） | 24 |
| `sq_AddDrawOnlyAniFromParent` | 以父对象为基准挂一个纯绘制动画 | 19 |
| `sq_EndDrawCastGauge` | 结束施法条（obj） | 19 |
| `sq_GetCNRDObjectToActiveObject` | CNRDObject* → CActiveObject* | 19 |
| `sq_SetAttackBoundingBoxSizeRate` | 按倍率缩放攻击盒 | 19 |
| `sq_StartWrite` | 开始写全局缓冲（同 sq_BinaryStartWrite） | 19 |
| `sq_WriteWord` | 写 word 到全局写缓冲 | 19 |
| `sq_stopMove` | 停住角色移动（方法式写法） | 19 |
| `printc` | 向控制台打印一行（调试用，1 参） | 18 |
| `sq_GetAnimationFrameIndex` | 取动画当前帧下标（同 GetCurrentFrameIndex） | 18 |
| `sq_StartDrawCastGauge` | 开始画施法条（obj, 起始 ms, 是否跟随） | 18 |
| `sq_ani_GetCurrentFrameIndex` | 取动画当前帧下标（方法式别名） | 18 |
| `sq_getJob` | 取角色职业（ENUM_CHARACTERJOB_*） | 17 |
| `sq_AddParticleObject` | 把粒子创建器挂到对象上 | 16 |
| `sq_getVectorData` | 读状态包 IntVect 第 i 个 dword（方法式写法） | 15 |
| `sq_setShake` | 屏幕震动（方法式别名） | 15 |
| `sq_GetObjectHeight` | 取对象高度（常用于取半高做命中点） | 14 |
| `sq_GetSTATE` | 同 sq_GetState，取当前状态 ID | 14 |
| `sq_SendChangeSkillEffectPacket` | 广播「技能特效已换」包 | 14 |
| `sq_setAttackPowerWithPassive` | 把被动加成后的攻击力写回当前攻击信息 | 14 |
| `sq_ObjectToSQRCharacter` | CNRDObject* → 脚本角色对象（父类写法） | 13 |
| `sq_GetOppositeDirection` | 取相反朝向 | 12 |
| `sq_GetUniqueId` | 取对象的唯一 ID（组内寻址用） | 12 |
| `sq_IsGrabable` | 查询目标是否可被抓 | 12 |
| `sq_IsHoldable` | 查询目标是否可被举/抓 | 12 |
| `sq_GetGroup` | 取对象所属组 ID | 11 |
| `sq_SendCreatePassiveObjectPacketPos` | 在指定坐标创建被动对象（6 参） | 11 |
| `sq_SetValidTime` | 设置被动对象存活毫秒（到期自毁） | 11 |
| `sq_WriteFloat` | 写 float 到全局写缓冲 | 11 |
| `sq_getBonusRateWithPassive` | 取被动加成后的倍率（方法式写法） | 11 |
| `sq_IsKeyDown` | 查询某热键是否按下 | 10 |
| `sq_SetShake` | 屏幕震动（强度, 毫秒） | 10 |
| `sq_getChangeStatus` | 取附加体上的属性变更对象 | 10 |
| `sq_CreateDrawOnlyObject` | 创建纯绘制对象（不参与碰撞） | 9 |
| `sq_ToRadian` | 角度转弧度 | 9 |
| `sq_ani_IsEnd` | 动画是否播完（方法式别名） | 9 |
| `sq_getLevelData` | 读技能等级表第 col 列（方法式写法） | 9 |
| `sq_GetAniRealImageSize` | 取动画某方向的实际像素尺寸 | 8 |
| `sq_GetCurrentModuleType` | 取当前模块类型（副本/城镇/决斗） | 8 |
| `sq_GetDelaySum` | 取动画各帧停留时间之和（总时长 ms） | 8 |
| `sq_RemoveParticle` | 移除指定路径的粒子 | 8 |
| `sq_binaryData_writeDword` | 写 dword（旧别名） | 8 |
| `sq_createCNRDAnimation` | 创建动画对象（小写别名） | 8 |
| `isSameObject` | 判断两个对象引用是否同一对象 | 7 |
| `sq_ALPHA` | 构造颜色：1 参=alpha，4 参=RGBA | 7 |
| `sq_GetCustomAttackInfo` | 取自定义攻击信息模板（按索引） | 7 |
| `sq_GetSkillIndex` | 取当前正在执行的技能 ID | 7 |
| `sq_IsFixture` | 判断是否为固定物（不可抓） | 7 |
| `sq_RGBA` | 用 (r,g,b,a) 构造颜色值 | 7 |
| `sq_RemoveMoveParticle` | 移除移动拖尾粒子 | 7 |
| `sq_SetCurrentAttackPower` | 直接改当前攻击信息的基础攻击力 | 7 |
| `sq_binaryData_startWrite` | 开始写二进制缓冲（旧别名） | 7 |
| `sq_createCNRDPooledObject` | 创建可池化动画对象（小写别名） | 7 |
| `sq_Cos` | 余弦（弧度） | 6 |
| `sq_GetObjectId` | 取对象模板 ID（poId） | 6 |
| `sq_GetObjectManagerStage` | 取当前关卡的对象管理器 | 6 |
| `sq_GetParentState` | 取被动对象主人的状态 ID | 6 |
| `sq_SetApplyConversionSkill` | 应用「技能转换」被动 | 6 |
| `sq_SetCurrentAttackeHitStunTime` | 设当前攻击的命中硬直毫秒 | 6 |
| `sq_SetCustomRotate` | 设置对象自定义旋转（弧度） | 6 |
| `sq_SetZVelocity` | 设 Z 速度与重力 | 6 |
| `sq_Sin` | 正弦（弧度） | 6 |
| `sq_binaryData_writeWord` | 写 word（旧别名） | 6 |
| `sq_isMyControlObject` | 是否本地控制对象（方法式写法） | 6 |
| `sq_moveWithParent` | 让对象跟随父对象移动 | 6 |
| `sq_setXScrollStop` | 停止背景横向滚动 | 6 |
| `sq_AddSetStatePacketActiveObject` | 给活动对象发状态包（4 参） | 5 |
| `sq_AnimationProc` | 推进动画一帧（按时间更新） | 5 |
| `sq_AppendAppendageID` | 用 APID_* 给附加体打 ID 并挂上 | 5 |
| `sq_BinaryWriteByte` | 写 1 字节到全局写缓冲 | 5 |
| `sq_CosTable` | 查余弦表（按角度整数） | 5 |
| `sq_DeleteEffectFront` | 删除对象前层特效 | 5 |
| `sq_GetCNRDObjectToCollisionObject` | CNRDObject* → CCollisionObject* | 5 |
| `sq_GetCenterZPos` | 取包围盒中心 Z | 5 |
| `sq_GetCurrentAttackBonusRate` | 取当前攻击加成率 | 5 |
| `sq_IsEnterSkill` | 查询是否处于某技能状态 | 5 |
| `sq_SetMoveDirection` | 设置移动方向（不直接位移） | 5 |
| `sq_SetObjectParticlePos` | 设置对象粒子的相对位置 | 5 |
| `sq_SimpleMoveToNearMovablePos` | 简化版移动寻位（obj, 距离） | 5 |
| `sq_SinTable` | 查正弦表（按角度整数） | 5 |
| `sq_setStaticMoveInfo` | 设置静态移动参数（方法式写法） | 5 |
| `sq_AddChangeStatusAppendageID` | 按 APID 挂「属性变更」附加体 | 4 |
| `sq_AniLayerListSize` | 取动画叠加层数量（别名） | 4 |
| `sq_Atan2` | atan2(y, x) → 弧度 | 4 |
| `sq_ChangeDrawLayer` | 改对象绘制层级 | 4 |
| `sq_CreateParticleByGlobal` | 用全局粒子枚举创建粒子（9/16 参） | 4 |
| `sq_DeleteAni` | 释放动画对象 | 4 |
| `sq_EffectLayerAppendage` | 给附加体挂一层整屏色层 | 4 |
| `sq_FindShootingTarget` | 扇形/直线搜敌（13 参，返回目标） | 4 |
| `sq_GetAttackBonusRate` | 取技能攻击加成率（按列与倍率） | 4 |
| `sq_GetCNRDObjectToAICharacter` | CNRDObject* → CAICharacter* | 4 |
| `sq_GetCenterXPos` | 取包围盒中心 X | 4 |
| `sq_GetDistance` | 两点距离（5 参，可只算 X） | 4 |
| `sq_GetObjectByObjectId` | 按对象 ID 取对象 | 4 |
| `sq_GetParentSkillSubState` | 取被动对象主人的技能子状态 | 4 |
| `sq_GetShootingHorizonAngle` | 求射击的水平角度 | 4 |
| `sq_GetShootingVerticalAngle` | 求射击的垂直角度 | 4 |
| `sq_GetTeam` | 取对象所属队伍 | 4 |
| `sq_ReleaseActiveStatus` | 解除主动状态（中毒/束缚等） | 4 |
| `sq_SendMessage` | 给对象发消息（4 参） | 4 |
| `sq_SetCurrentAttackInfoFromCustomIndex` | 按 CUSTOM_ATTACK_INFO_* 换当前攻击信息 | 4 |
| `sq_SetTargetObjectAICharacter` | 设置目标 AI 角色（或清除） | 4 |
| `sq_SetVelocity` | 设水平速度 (x, y) | 4 |
| `sq_SetfRotateAngle` | 设置动画旋转角（弧度） | 4 |
| `sq_drawCurrentFrame` | 在指定屏幕坐标画当前帧 | 4 |
| `sq_isPVPMode` | 判断是否 PVP 模式 | 4 |
| `sq_p00_sendCreatePassiveObjectPacket` | 创建被动对象的旧式入口（5 参） | 4 |
| `sq_setAnimationSpeedRate` | 设置动画播放倍速（方法式写法） | 4 |
| `checkModuleType` | 查询当前模块类型是否匹配 | 3 |
| `sq_AddAttackCancelStartFrame` | 加「可取消攻击」的起始帧 | 3 |
| `sq_AddAuraMaster` | 创建光环对象（名字, 父, 对象, 半径, ...） | 3 |
| `sq_AddHitObject` | 登记一个已命中对象（防重复命中） | 3 |
| `sq_AddMessage` | 弹一条系统消息（消息 ID） | 3 |
| `sq_AddSetStatePacketCollisionObject` | 给碰撞对象发状态包（5 参） | 3 |
| `sq_BinaryWriteBool` | 写 1 字节布尔到全局写缓冲 | 3 |
| `sq_GetInputDirection` | 取当前输入方向（ENUM_DIRECTION_*） | 3 |
| `sq_GetMap` | 取角色所在地图对象 | 3 |
| `sq_GetMyControlObjectSize` | 取本地控制对象数量 | 3 |
| `sq_GetOcularSpectrum` | 取「视觉频谱」附加体对象 | 3 |
| `sq_GetSkillSubState` | 取角色当前技能子状态号 | 3 |
| `sq_IsEnterCommand` | 查询是否输入了某指令 | 3 |
| `sq_SendCreatePassiveObjectPacketFromPassivePos` | 由被动对象按位置创建被动对象（6 参） | 3 |
| `sq_SetAnimationCurrentTimeByFrame` | 把动画时间设到某帧（可含区间） | 3 |
| `sq_SetAnimationFrameIndex` | 强制跳动画到某帧 | 3 |
| `sq_SetCameraScrollPosition` | 设置摄像机滚动位置 | 3 |
| `sq_SetCurrentAttackeDamageAct` | 设当前攻击的伤害表现（DAMAGEACT_*） | 3 |
| `sq_SetCustomDamageType` | 设置自定义伤害类型 | 3 |
| `sq_SetKeyxEnable` | 开关指定的 keyx 输入项 | 3 |
| `sq_SetSpeedToMoveParticle` | 设置移动粒子的速度 | 3 |
| `sq_WriteByte` | 写 byte 到全局写缓冲 | 3 |
| `sq_findNearLinearMovableXPos` | 沿直线求最近可站立 X | 3 |
| `sq_getAniLayerListObject` | 取动画叠加层对象（方法式写法） | 3 |
| `sq_getAuraMaster` | 取光环对象（按名字） | 3 |
| `sq_getNewAttackInfoPacket` | 取一份新的攻击信息包 | 3 |
| `sq_getStateTimer` | 取当前状态已持续毫秒 | 3 |
| `sq_removeAttractAimPointMark` | 移除瞄准点标记 | 3 |
| `sq_setCurrentAttackBonusRate` | 设置攻击加成率（方法式写法） | 3 |
| `sq_setMoveDirection` | 设置移动方向（不动位置） | 3 |
| `sq_BinaryParameterStartWrite` | 开始写「参数」缓冲（第二套全局缓冲） | 2 |
| `sq_CreateCNRDPooledObject` | 创建可池化动画对象（小写别名） | 2 |
| `sq_CreateChangeStatus` | 创建一个状态变更对象 | 2 |
| `sq_CreatePassiveObjectAfterWarning` | 延迟预警后再创建被动对象 | 2 |
| `sq_DeleteAppendages` | 清空对象身上所有附加体 | 2 |
| `sq_EffectLayerAppendageOnlyBody` | 只给身体挂色层 | 2 |
| `sq_GetAimPosX` | 按时间取瞄准点 X | 2 |
| `sq_GetCNRDObjectToCharacter` | CNRDObject* → CCharacter* | 2 |
| `sq_GetCNRDObjectToFlashScreen` | CNRDObject* → CFlashScreen* | 2 |
| `sq_GetCustomIntDataSize` | 取技能自定义 int 表长度 | 2 |
| `sq_GetMyControlObject` | 取本地控制的对象（可带对象参数） | 2 |
| `sq_GetMyMasterCharacter` | 取本被动对象的主人角色 | 2 |
| `sq_GetPassiveObjectByState` | 按状态取被动对象（3 参） | 2 |
| `sq_GetSkillLoad` | 查询技能「充能/装载」层数 | 2 |
| `sq_GetSourceChrTarget` | 取施法源角色当前目标 | 2 |
| `sq_IsDownKey` | 查询某方向键是否按住 | 2 |
| `sq_IsInBattle` | 判断是否处于战斗中 | 2 |
| `sq_IsSameAni` | 判断两个动画对象是否同一个 | 2 |
| `sq_MoveToAppendageForce` | 带外力地把对象吸向附加体主人 | 2 |
| `sq_MoveToNearMovablePos` | 移动到最近可站立点（10 参，走路径） | 2 |
| `sq_PostDelayedMessage` | 延迟投递消息（5 参） | 2 |
| `sq_RemovePassiveSkillAttackBonusRate` | 移除被动技能攻击力加成 | 2 |
| `sq_SendHitObjectPacketByAttackInfo` | 按指定攻击信息发命中包 | 2 |
| `sq_SetAimPointMarkPosition` | 设置瞄准点标记位置 | 2 |
| `sq_SetAttackInfoForceHitStunTime` | 强制设置命中硬直毫秒 | 2 |
| `sq_SetAttackInfoHitDelayRateDamager` | 设攻击命中延迟倍率（蓄力用） | 2 |
| `sq_SetChangeStatusIntoAttackInfoWithEtc` | 把属性变更写进攻击信息（8 参，带附加参数） | 2 |
| `sq_SetExSkillSlotVisible` | 显示/隐藏 EX 技能槽 | 2 |
| `sq_SetGrabable` | 设置是否可被抓住 | 2 |
| `sq_SetMaxHitCounterPerObject` | 设同一目标最大命中次数 | 2 |
| `sq_SetParameterOcularSpectrum` | 设置视觉频谱参数（9 参） | 2 |
| `sq_SetPause` | 暂停/恢复对象（3 参） | 2 |
| `sq_SetSkillSlotEnable` | 启用/禁用某技能槽 | 2 |
| `sq_SetSkillSlotPos` | 设置技能槽位置 | 2 |
| `sq_SetSkillSlotVisible` | 显示/隐藏某技能槽 | 2 |
| `sq_SetSoundTagBackStepStart` | 设置后跳音效 | 2 |
| `sq_SetSoundTagCoolTime` | 设置冷却中音效 | 2 |
| `sq_SetSoundTagCreatureCommand` | 设置召唤兽指令音效 | 2 |
| `sq_SetSoundTagDie` | 设置死亡音效 | 2 |
| `sq_SetSoundTagLackMp` | 设置 MP 不足音效 | 2 |
| `sq_SetSoundTagThrowItem` | 设置投掷道具音效 | 2 |
| `sq_WriteBool` | 写 bool 到全局写缓冲 | 2 |
| `sq_ZStop` | 清零 Z 方向速度 | 2 |
| `sq_addPassiveSkillAttackBonusRate` | 叠加被动攻击力加成（方法式写法） | 2 |
| `sq_getAttractAimPosX` | 取吸引瞄准点 X | 2 |
| `sq_getAttractAimPosY` | 取吸引瞄准点 Y | 2 |
| `sq_getHpMaxUp` | 取「最大 HP 提升」静态变量 | 2 |
| `sq_getRandomUnique` | 取不重复随机数（3 参） | 2 |
| `sq_getSkillLevel` | 取技能等级（方法式写法） | 2 |
| `sq_sendSetActiveStatusPacket` | 广播设置主动状态（7 参） | 2 |
| `sq_setFullScreenEffect` | 设置全屏特效（2 参） | 2 |
| `sq_setXScroll` | 设置背景横向滚动（4 参，带速度） | 2 |
| `sq_setXScrollStart` | 启动背景横向滚动 | 2 |

### 3.2 频次 1 的 105 个（按族合并，仍逐个给语义）

每个只有一次调用现场，语义只能给到「大概做什么 + 参数个数」，属于**推断**。实现顺序上一律排在 3.1 之后。

| 族 | 名字 → 反推语义（每个都是 1 次调用，证据最薄；括号内为参数量） |
|---|---|
| 身份判定 | `sq_IsMyCharacter` 是否本人角色；`sq_IsAiCharacter` 是否 AI 角色（怪物）；`sq_IsBoss` 是否 BOSS；`sq_IsNamed` 是否精英/命名怪；`sq_IsHellMonster` 是否地狱怪；`sq_IsExistObject` 对象是否仍存在；`sq_IsInCategory(obj, 类别)` 是否属于某类别；`sq_IsInScreenCollisionObject` 是否在屏幕内 |
| 副本判定 | `sq_IsAncientDungeon` 远古副本；`sq_IsDimensionDungeon` 次元副本；`sq_IsTowerDungeon` 塔类副本；`sq_IsDespairTower` 绝望之塔 |
| 状态判定 | `sq_IsMovablePosCollisionObject` 该坐标对碰撞体是否可站立；`sq_IsSetActiveStatus` 主动状态是否已设置；`sq_IsIntersectRect(8)` 两个屏幕矩形是否相交；`sq_IsEnterSkillLastKeyUnits` 是否处于技能「最后按键单元」内；`sq_isSendTimeOutPacket` 是否已发网络超时包 |
| 距离与几何 | `sq_GetDistanceObject` 两对象间距（可选只算 X）；`sq_GetHeightObject` / `sq_GetWidthObject` / `sq_GetBoundingBoxXSize` 碰撞高/宽；`sq_GetAttackBoundRect` 动画的攻击判定矩形；`sq_SetObjectBounding` 设包围盒；`sq_GetVelocity` 当前速度分量 |
| 坐标换算 | `sq_GetScreenXPos` / `sq_GetScreenYPos` 世界坐标→屏幕坐标；`sq_ToDegree` 弧度→角度；`sq_SetfindNearLinearMovablePos` 线性方向上的最近可站立点；`sq_setfindNearMovablePos` 求最近可站立点并写回坐标 |
| 动画与帧 | `sq_Rewind` 动画回到第 0 帧；`sq_CurrentAnimationProc` 推进当前动画一帧；`sq_GetAniFrameNumber` 按时间取帧号；`sq_SetCurrentTimeByFrame` 把动画时间跳到某帧起点；`sq_SetAnimationSpeedRate` 播放倍速；`sq_GetCustomAni` 按索引取技能自定义动画；`sq_GetBuffAni` 取 buff 图标动画；`sq_GetFrontAnimation` 取前层动画对象；`sq_AddEffectBack` 在对象背后挂特效；`sq_InitFrameIndices` 初始化帧索引表（`init_character.gd` 装载期一次） |
| 动作帧配置 | `sq_JumpUpStartFrame` / `sq_JumpDownStartFrame` / `sq_JumpLandStartFrame` 跳跃三阶段起始帧；`sq_SetDownUpFrame` / `sq_SetDownDownFrame` / `sq_SetDownLieFrame` 倒地弹起/落下/躺地帧；`sq_SetDownBounceUpFrame` / `sq_SetDownBounceDownFrame` 倒地反弹上下帧 —— 都是「把某个动作的起始帧号告诉引擎」，落地=`state_frames[动作] = 帧号` |
| 攻击信息 | `sq_AddAttackBox` / `sq_ClearAttackBox` 给动画加/清攻击盒；`sq_GetAttackType` / `sq_setAttackInfoType` 攻/受击类型读写；`sq_ChangeAttackTypeToOpposite` 物理↔魔法翻转；`sq_GetDefaultAttackInfo` 默认攻击信息模板；`sq_GetSkillPower` 技能基础攻击力；`sq_GetAbilityConvertRate` 属性转换率（力/智） |
| 命中与打击感 | `sq_GetAttackInfoHitDelayRateDamager` / `sq_GetCurrentAttackeDamageAct` 命中延迟倍率/伤害表现；`sq_SetCurrentAttacknBackForce` / `sq_SetCurrentAttacknUpForce` 击退/上挑力；`sq_SetAddWeaponDamage` 武器伤害附加；`sq_SendHitObjectPacketWithNoStuck` 发命中包但不产生卡肉；`sq_setCustomHitEffectFileName` 自定义命中特效路径 |
| 造攻击对象 | `sq_createAttackObjectWithPath(9)` 按路径创建攻击对象；`sq_createCommonElementalAttack(6)` 创建通用属性攻击；`sq_SendCreatePassiveObjectPacketFromPassive(7)` 由被动对象再创建被动对象 |
| 被动与属性 | `sq_AddPassiveSkillAttackBonusRate` 叠加被动攻击力加成；`sq_getPassiveAttackRate` / `sq_getPowerWithPassive` 同样的被动加成，但用方法式写法（`obj.sq_getPowerWithPassive(...)`）；`sq_AddHpMaxUp` 提升最大 HP 并挂附加体；`sq_RemoveChangeStatus` 移除属性变更 |
| 瞄准与吸引 | `sq_AddAimPointMark` / `sq_RemoveAimPointMark` / `sq_addAttractAimPointMark` 瞄准点标记增删；`sq_setAttractAimInfo` 瞄准吸引参数；`sq_AttractToMe` 把目标吸向自己；`sq_AtrractionForce` 施加吸引力（原文拼写 Atrraction）；`sq_AccelMoveToAppendageForce` 带加速度吸向附加体主人 |
| 光环与霸体 | `sq_AddOcularSpectrum` 视觉频谱附加体；`sq_getSquirrelAuraMaster` 取脚本侧光环对象；`sq_setSuperArmor` / `sq_removeSuperArmor` 霸体开/关 |
| 输入与控制权 | `sq_SetEnableKeyInputType` 允许的输入类型位掩码；`sq_SetMyControlCharacter` 指定本地控制的角色；`sq_getInputDirection` 取当前输入方向（方法式别名） |
| 索敌 | `sq_FindTarget(5)` / `sq_FindFirstTarget` / `sq_FindNextTarget` 搜索目标三连（首/次/按条件） |
| 技能装载 | `sq_AddSkillLoad` / `sq_RemoveSkillLoad` 技能装载层数与时间；`sq_GetCastSpeed` 施法速度数值；`sq_SetStartCoolTime` 技能冷却起点；`sq_requestBuySkill` 请求学习/购买技能 |
| 场景查询 | `sq_GetDungeonByStage` 按关卡取副本信息；`sq_GetGlobaludpModuleStage` 全局 UDP 模块的关卡；`sq_GetMoveParent` 跟随的父对象；`sq_GetGrowAvatarViewControl` 转职展示控件；`sq_getGrowType` 转职/成长类型；`sq_GetParticleInfo` 按索引取粒子信息 |
| 表现与层 | `sq_SetBodyEffect(8)` 身体特效；`sq_bottomcreateFlash(5)` 底层闪光；`sq_SetEnumDrawLayer` 按 `ENUM_DRAWLAYER_*` 改层级；`sq_SetDirection` / `sq_SetCurrentDirection` 设朝向（后者是 `ENUM_DIRECTION_*` 枚举值）；`sq_binaryData_writeFloat` 写 float 的旧别名；`sq_SendSetHpPacket` 广播 HP 变更包；`isDebugMode` 是否调试模式 |

### 3.3 只出现在未翻译 `.nut` 里的 52 个（按族合并）

这些名字在 `sqr_gd/**` 里一次调用都没有，只在原始脚本里出现，因此没有 `文件:行号` 式的 Godot 侧调用证据，语义只能靠命名 + 所在文件（大多是创造者法师的弹窗/光标 UI）**推断**。其中 `sq_addSetStatePacketColObj`、`sq_drawCurrentFrameEffectColor` 在原脚本里也只以注释形式出现（`sqr_src_utf8/sqr/passiveobject/character/priest/po_spincutter.nut:142`、`sqr_src_utf8/sqr/character/atmage/iceorbex/po_aticeorbexprickle.nut:47`）。

| 族 | 名字 → 反推语义 |
|---|---|
| 脚本级入口（不是宿主绑定） | `sq_AddFunctionName` 向引擎注册本脚本提供的回调名；`sq_AddEffect` 附加体加载时注册常驻特效 —— 两者只出现在 `ap_*.nut` 顶层，翻译时被故意排除在桩表外（`sqr_gd/sqr_script.gd:15`） |
| 弹窗/控件（UI 层，几乎全在 `creatormage_common`） | `sq_GetGlobalMainControl` 主控件根节点；`sq_GetGlobalChatControl` 聊天控件；`sq_GetUISystemChatControl` 系统聊天控件；`sq_GetStrikerSkillUi` 连击/技能 UI；`sq_GetPopupWindows` 弹窗集合；`sq_GetPopupWindowMainCotrol` 弹窗主控件（原文拼写 Cotrol）；`sq_OpenPopupWindow` 打开弹窗；`sq_GetStateCashShop` 商城界面状态；`sq_GetResultState` 结算界面状态；`sq_GetRewardState` 奖励界面状态；`sq_IsESCClosableWindow` 窗口能否 ESC 关闭；`sq_IsOpenCreatorControlPopupWindows` 创造者控制弹窗是否已开；`sq_IsIgnoreOpenPopupCreator` 是否忽略创造者弹窗；`sq_IsPauseTypeWorld` 世界是否处于暂停型状态；`sq_drawToolTip` 画 tooltip |
| 鼠标与光标 | `sq_GetMouseXPos` / `sq_GetMouseYPos` 鼠标坐标（等价 `IMouse.GetXPos()/GetYPos()`，`avenger_common.nut` 里并存）；`sq_SetClipCursor` / `sq_IsClipCursor` 把鼠标裁剪在窗口内/查询；`sq_IsVisibleCursor` / `sq_SetVisibleCursor` 光标显隐；`sq_IsMousePtInWindowRect` 鼠标点是否落在窗口矩形内；`sq_IsDownHotKeyCreatorCursor` 创造者光标热键是否按下 |
| 场景与坐标查询 | `sq_GetDuegonIndex` 地下城索引（原文拼写 Duegon）；`sq_GetMapIndex` 地图索引；`sq_IsinMapArea` 坐标是否在某地图区域；`sq_GetObjectWeight` 对象重量；`sq_AddObjectTarget` 把目标加入对象的索敌/命中列表；`sq_IsRidingObject` 是否骑乘中；`sq_IsItemRecover` 物品是否处于找回态；`sq_GetShadowTypeByAnimation` 按动画查该用的阴影类型 |
| 绘制（需要直接操作渲染，最不适合搬） | `sq_DrawSpecificFrame` 画指定帧；`sq_DrawCurrentFrameEffect_SIMPLE` / `sq_DrawSpecificFrameEffect_SIMPLE` / `sq_drawCurrentFrameEffect_SIMPLE` 简化参数画当前帧/指定帧特效；`sq_drawCurrentFrameEffectColor` 带颜色后处理地画（仅注释出现）；`sq_DrawSkillIcon` 画技能图标 |
| 二进制读侧 | `sq_BinaryStartRead` 开始读缓冲；`sq_BinaryGetDWord` 读一个 dword —— 与 `.gd` 里常见的 `receiveData.readDword()` 是同一件事的两套写法 |
| 消息与技能 | `sq_AddMessagePrintf` 弹格式化系统消息；`sq_getMyBuffInfoCount` 自身 buff 数；`sq_getMyCharacter` 取自身角色（等价 `IRDSQRCharacter`）；`sq_GetobjectParticleCreaters` 对象已挂的粒子生成器表 |
| 其它 | `sq_LoadSkillEffect_Swordman` / `sq_LoadSkillEffect_DemonicSwordman` 按职业注册技能特效动画表（顺序即下标，对应 `common.nut`）；`sq_SetAllCommandEnable` 副本级批量开关命令可用性；`sq_SetCurrentAttackDirection` 设当前攻击朝向；`sq_GetKeyxEnable` 扩展按键是否可用；`sq_addSetStatePacketColObj` 给碰撞对象发状态包（仅注释）；`sq_InitFrameIndices` 初始化帧索引表（见上文频次 1 组） |

### 3.4 零调用的 97 个桩

这 97 个 `sq_*` 在 `sqr_gd/**` 里零调用，但要分成两拨看：

- **50 个**是「只在未翻译 `.nut` 里出现」的（完整清单与语义见 §3.3）——它们是真 API，只是用到它们的脚本没被翻译。
- **47 个**连原始语料里都一次没出现，是桩表的余量。它们有明显的族特征，可整族当成一类实现：

| 族 | 成员 | 推断语义 |
|---|---|---|
| `sq_get*Ani`（17 个） | `sq_getAttackAni`、`sq_getBuffAni`、`sq_getCustomAni`、`sq_getDamageAni`、`sq_getDashAni`、`sq_getDashAttackAni`、`sq_getDownAni`、`sq_getGetItemAni`、`sq_getJumpAni`、`sq_getJumpAttackAni`、`sq_getMoveAni`、`sq_getOverturnAni`、`sq_getRestAni`、`sq_getSitAni`、`sq_getStayAni`、`sq_getThrowChargeAni`、`sq_getThrowShootAni` | 按「动作类型」取该角色的动画名/索引（大写 `Get` 变体 `sq_GetAttackAni` / `sq_GetDashAttackAni` / `sq_GetJumpAttackAni` 同义） |
| 帧号查询（7 个） | `sq_getAttackCancelStartFrame`、`sq_getAttackCancelStartFrameSize`、`sq_getAttackCancelStartFrameSize`(大写变体)、`sq_getJumpUpStartFrame`、`sq_getJumpDownStartFrame`、`sq_getJumpLandStartFrame`、`sq_getDashAttackSlideStopFrame` | 取某段动作的关键帧下标（取消窗口起止、跳跃三段起止） |
| 攻击信息查询（5 个） | `sq_GetDashAttackInfo`、`sq_GetJumpAttackInfo`、`sq_getJumpAttackInfo`、`sq_getSkillPower`、`sq_getSkillAttackBonusRate`、`sq_GetSkillPowerWithAttackBonusRate` | 取冲刺/跳跃攻击的 `.atk` 与技能攻击力/加成率 |
| 其余零散（其余） | `sq_AddCNChangeHp`、`sq_GetCNChangeHp`、`sq_AddSquirrelAuraMaster`、`sq_ClearKeyFrameFlag`、`sq_IsKeyFrameFlag`、`sq_GetObjectWorldTime`、`sq_PlayMoveSound`、`sq_getDelaySum`、`sq_getAutoLayerWorkAnimation`、`sq_getSendState`、`sq_getRGB`、`sq_isEnableBackStepState`、`sq_isMyCharacter`、`sq_setStaticSpeedInfo` | 血量变更、aura master、关键帧标记、世界时钟、移动音效、动作总时长等；`sq_setStaticSpeedInfo` / `sq_getRGB` 是小写重载变体（对应大写版 §2.D / §2.H） |

> 落地建议：这 47 个可以统一 `return null` 先跑，符号名保留在桩表里即可——没有任何脚本会因此走错分支（已验证零调用）。

---

## 4 宿主全局对象

原版 exe 除了注入 478 个函数，还注入了 5 个**全局单例对象**。翻译版在 `sqr_gd/sqr_consts.gd:12-16` 里把它们声明成 `var X = null`（`class_name SqrConsts` 上的字段），任何 `extends SqrConsts` 的脚本都能直接引用名字——所以移植时要做的不是「传对象」，而是**在 JavaScript/Godot 侧给这 5 个名字各提供一个真实实例**（autoload 最合适）。

### 4.1 `IRDSQRCharacter` —— 角色脚本注册器（不是角色实例）

| 成员 | 频次 | 语义 | 落地 |
|---|---|---|---|
| `pushScriptFiles(path)` | 18 | 把一份脚本排进加载队列（**只是排队，不是立即执行**，`sqr_gd/character/creatormage_load_state.gd:15` 的译注写明） | autoload 里的 `script_queue: Array[String]`，装载期统一 `load()` |
| `pushPassiveObj(path, poId)` | 95 | 登记「poId → 被动对象脚本路径」，之后 `sq_SendCreatePassiveObjectPacket(poId, …)` 才找得到模板 | `Dictionary[int, String] passive_obj_table` |
| `pushState(job, path, prefix, STATE_x, SKILL_x)` | 52 | 登记「状态 ID → 回调前缀」，引擎调 `onSetState_<prefix>` 时按它分派 | `Dictionary[String, Callable] state_table`（key = prefix） |

三者的调用现场都在职业装载表：`sqr_gd/character/creatormage_load_state.gd:16`（pushScriptFiles，`:15` 是它被注释掉的原行）、`:39`（pushPassiveObj 24353）、`:49`（pushState）。**注意它注册的是「脚本提供的入口」，与「角色实例」无关**——名字里的 Character 指的是「角色脚本宿主」。

### 4.2 `CNSquirrelAppendage` —— 附加体工厂

| 成员 | 频次 | 语义 | 落地 |
|---|---|---|---|
| `sq_AppendAppendage(obj, src, SKILL, bool, apPath, bool)` | 49 | 建并挂一个附加体，返回实例或 `null`（详见 §2.G） | `AppendageManager.attach()` |
| `sq_RemoveAppendage(obj, apPath)` | 21 | 按路径摘掉 | `erase(path)` |
| `sq_IsAppendAppendage(obj, apPath)` | 13 | 是否已挂 | `has(path)` |
| `sq_Append(appendage, obj, obj[, isBuff])` | 11 | 挂已建好的附加体 | `add(appendage)` |
| `sq_GetAppendage(obj, apPath)` | 7 | 按路径取实例 | `get(path)` |
| `sq_AppendAppendageID(appendage, obj, obj, APID_x[, bool])` | 5 | 按 `APID_*`（change-status ID）挂条目，用于「同一附加体上的多种加成」 | `appendages[path].change_status[APID]` |

调用现场：`sqr_gd/character/atmage/passive_skill_atmage.gd:16`（主入口）、`sqr_gd/character/atmage/darknessmantle/po_atdarknessmantle.gd:550`（摘除）、`sqr_gd/character/atmage/atmage_throw.gd:104`（`sq_Append(appendage, obj, obj, true)` 打开 buff）。落地形态：`AppendageManager` autoload + 每个附加体一个 `Node`（脚本即 `ap_*.gd`），生命周期挂在目标对象上。

### 4.3 `CNAvenger` —— 复仇者专用注册器

与 `IRDSQRCharacter` 同构，但 `pushState` 只有 **4 参**（没有 `job`）：`pushState(path, prefix, STATE_x, SKILL_x)`，见 `sqr_gd/character/avenger_load_state.gd:30`；另有 `pushPassiveObj` 11 次（`:65`）、`pushScriptFiles` 4 次、`getStaticVar()` 2 次（`sqr_gd/common.gd:76`，返回一份跨职业共享的静态变量表，里面能 `GetAnimationMap(name, path)` 取转职特效动画，再配 `sq_AnimationProc` + `sq_drawCurrentFrame` 画出来）。**落地**：`AvengerRegistry`（可复用 IRDSQRCharacter 的表，只是多一层职业归属）；`getStaticVar()` → `StaticVarStore` autoload。

### 4.4 `IMouse` —— 鼠标

只有两个成员：`GetXPos()` / `GetYPos()`（各 7 次，无参），取鼠标的**世界坐标**，用于让创造者法师的技能落在鼠标位置。调用现场：`sqr_gd/character/creatormage/creatormage_common.gd:777`、`:1011-1012`、`:1435`（`objectManager.getFieldXPos(IMouse.GetXPos(), ENUM_DRAWLAYER_NORMAL)`）。**落地**：`IMouse = autoload`，`GetXPos() -> int: return camera.get_screen_to_world(get_viewport().get_mouse_position()).x`。

### 4.5 `IRDSUltimateSkill` —— 无调用证据

`.gd` 与 `.nut` 里**一次引用都没有**：`sqr_src_utf8` 全库 grep 只命中 0 处，翻译版只在 `sqr_gd/sqr_consts.gd:13` 声明了 `var IRDSUltimateSkill = null`（`avenger_load_state.gd:11` 的注释把它和另外两个并列成「同类单例」）。**推断**它是觉醒/终极技能接口，成员未知。落地：先给一个空 autoload（`extends Node`），不要为它设计接口——没有脚本会调。

### 4.6 变量系统：`obj.getVar()`（最高的单点成本）

`getVar` 在 `.gd` 里出现 **1686 次**，是被调用最多的宿主方法（比 `sq_IntVectPush` 多 8 倍）。它返回一个「变量槽对象」，槽位有两套寻址：无参 `obj.getVar()` = 默认槽；带字符串 `obj.getVar("attack")` = 命名槽（`po_atdarknessmantle.gd:534`、`darknessmantle.gd:231`）。

| 方法 | 频次 | 语义 | 落地 |
|---|---|---|---|
| `get_vector(i)` / `set_vector(i, v)` / `push_vector(v)` / `clear_vector()` | 232 / 194 / 205 / 55 | 整数向量，按下标读写或追加 | `Array[int]` |
| `getInt(i)` / `setInt(i, v)` | 71 / 63 | 标量整数槽 | `Dictionary[int, int]` |
| `get_obj_vector(i)` / `push_obj_vector(o)` / `get_obj_vector_size()` / `clear_obj_vector()` | 49 / 37 / 34 / 17 | 对象引用列表（追踪子对象/目标） | `Array[Node]` |
| `get_timer_vector(i)` / `push_timer_vector(t)` / `clear_timer_vector()` | 39 / 26 / 16 | 定时器组（多次触发用） | `Array[TimerSpec]` |
| `get_ct_vector(i)` / `push_ct_vector(c)` / `clear_ct_vector()` | 35 / 14 / 10 | 冷却计时器组（cooldown-time） | `Array[CooldownSpec]` |
| `getObject(i)` / `setObject(i, o)` | 23 / 14 | 单对象槽（存目标引用） | `Dictionary[int, Node]` |
| `GetAnimationMap(name, path)` | 21 | 动画缓存表（静态共享，见 §4.3） | `Dictionary[String, Animation]` |
| `GetparticleCreaterMap` | 41 | 粒子生成器表 | `Dictionary[String, PackedScene]` |
| `getBool/setBool`、`getFloat/setFloat` | 18/32、11/13 | 布尔/浮点槽 | 同 int 槽 |

> 这套变量系统是**脚本自己的内存**，与引擎状态无关。落地时给每个对象一个 `SqrVar` 子对象（`Dictionary` 装多个命名槽），一次性实现上面 12 组方法即可，**不需要 478 个桩里的任何一个**。

---

## 5 落地路线

### 5.1 M0 —— 跑通电链火柱的最小集合

**目标**：火柱（firepillar）与链电（chainlightning）两个技能从按键到命中到销毁全链路跑通，含被动对象。规模实测：**5 个文件、68 个 `sq_*`、228 个调用点**。

必须实现（按机制分组，括号内为 M0 内的调用次数）：

1. **状态机**：`sq_IsUseSkill`(2)、`sq_IsCommandEnable`(2)、`sq_GetState`(2)、`sq_GetStateTimer`(1)、`sq_GetVectorData`(6)、`sq_AddSetStatePacket`(9)、`sq_addSetStatePacket`、`sq_SetSkillSubState`、`getSkillSubState`（对象方法，17）
2. **IntVect**：`sq_IntVectClear`(7)、`sq_IntVectPush`(7)、`sq_GetGlobalIntVector`(12)、`sq_IntVectorClear`(12)、`sq_IntVectorPush`(18)
3. **二进制**：`sq_BinaryStartWrite`(3)、`sq_BinaryWriteDword`(9)、`sq_BinaryWriteWord`(8) + 读侧 `readDword`(10) / `readWord`(9) / `getSize()`
4. **动画**：`sq_SetCurrentAnimation`(6)、`sq_GetCurrentAnimation`(2)、`sq_GetCurrentAni`(3)、`sq_GetCurrentFrameIndex`(2)、`sq_GetCurrentTime`(3)、`sq_GetFrameStartTime`(1)、`sq_CreateAnimation`(4)、`sq_CreatePooledObject`(2)、`sq_AddObject`(2)、`sq_GetAnimationFrameIndex`(1)
5. **坐标**：`sq_GetXPos`(4)、`sq_GetYPos`(4)、`sq_GetZPos`(3)、`sq_SetCurrentPos`(3)、`sq_setCurrentAxisPos`(1)、`sq_GetDistancePos`(1)、`sq_GetUniformVelocity`(1)、`sq_StopMove`(2)、`sq_GetDirection`(2)、`sq_GetOppositeDirection`(1)、`sq_GetDistance`(1)、`sq_Atan2`(1)、`sq_Cos`/`sq_Sin`(2)
6. **攻击**：`sq_GetCurrentAttackInfo`(4)、`sq_SetCurrentAttackBonusRate`(2)、`sq_SetCurrentAttackeDamageAct`(2)、`sq_SetAttackInfoHitDelayRateDamager`(1)、`sq_GetAttackInfoHitDelayRateDamager`(1)、`sq_SendHitObjectPacket`(2)
7. **被动对象**：`sq_SendCreatePassiveObjectPacket`(2)、`sq_SendDestroyPacketPassiveObject`(7)、`sq_GetPassiveObject`(1)、`sq_GetObjectByObjectId`(2)、`sq_GetObjectId`(3)、`sq_GetObjectHeight`(6)、`sq_SendCreatePassiveObjectPacketFromPassivePos`(1)
8. **技能数据与表现**：`sq_GetSkillLevel`(4)、`sq_GetLevelData`(5)、`sq_GetIntData`(8)、`sq_GetBonusRateWithPassive`(2)、`sq_GetCastTime`(1)、`sq_PlaySound`(4)、`sq_SetShake`(1)、`sq_SetStaticSpeedInfo`(1)、`sq_StartDrawCastGauge`/`sq_EndDrawCastGauge`、`sq_Abs`(5)
9. **对象宿主方法**（非 `sq_` 前缀，共 24 个）：`getVar`(150)、`isMyControlObject`(30)、`addSetStatePacket`(15)、`getXPos/YPos/ZPos`(各 6)、`setCurrentAnimation`(5)、`getCurrentAnimation`(5)、`setCurrentDirection`(5)、`getState`(4)、`getDirection`(4)、`setValid`(3)、`get_obj_vector`/`remove_obj_vector`(各 3)、`push_obj_vector`/`push_vector`/`resize`/`setCurrentPos`/`isOnEvent`/`getCustomAnimation`(各 2)、`getTopCharacter`(2)、`isDownSkillLastKey`/`isMeleeAttack`/`isMissileObject`/`resetHitObjectList`/`setImageRate`(各 1)

**可行性**：这一档全部有对应物，工程量集中在三件事——(a) `SqrVar` 变量系统；(b) 状态机 + `addSetStatePacket` 的延迟生效语义；(c) 二进制包在发送端/接收端之间的一致性。**没有不可移植的 API**（`sq_SetStaticSpeedInfo` 在 M0 只出现 1 次，可以直接忽略倍率）。

### 5.2 M1 —— 一个技能体系完整

**目标**：男法师（atmage）全部技能 + 被动 + 转职特效可玩。规模：**278 个 `sq_*`、3805 个调用点、107 个文件**（含 `common.gd`、`loadstate.gd`、`init_character.gd`）。

相对 M0 新增的关键能力（按增量价值排序）：

1. **特效动画表**：`sq_LoadSkillEffectAni`(195，全库第二高频)——「给技能注册一串 `.ani`，加载顺序即下标」；配套还有按职业拆分的 `sq_LoadSkillEffect_Swordman` / `sq_LoadSkillEffect_DemonicSwordman`，见 `sqr_gd/common.gd:248-270`。
2. **附加体全链路**：`sq_AppendAppendage`(43)、`sq_GetAppendage`、`sq_RemoveAppendage`(16)、`sq_IsAppendAppendage`(8)、`sq_AddChangeStatus`(6) + 附加体对象自己的一套方法（`sq_getChangeStatus`、`clearParameter`、`addParameter`、`setValidTime`）。
3. **多层动画**：`sq_AddStateLayerAnimation`(62)、`sq_CreateCNRDAnimation`(62)、`sq_flashScreen`(28)、`sq_addFlashScreen`(10)、`sq_RGB`(54)、`sq_SetMyShake`(34)、`sq_CreateParticle`(10)。
4. **攻击信息改状态**：`sq_SetChangeStatusIntoAttackInfo`(11)、`sq_IsValidActiveStatus`(10)、`sq_SetCurrentAttackInfo`(48)。
5. **位移与插值族**：`sq_GetAccel`(25)、`sq_GetShuttleValue`(7)、`sq_GetObjectTime`(8)、`sq_SetStaticMoveInfo`(20)。
6. **范围查询**：`sq_FindFirstTarget` / `sq_FindNextTarget` / `sq_FindShootingTarget`(13 参) / `sq_IsHoldable` / `sq_IsGrabable` / `sq_HoldAndDelayDie`。

**可行性**：仍然全部可移植，但要接受两个「行为近似」——`sq_GetAccel` 的缓动曲线、`sq_AddStateLayerAnimation` 的帧对齐（层动画与主动画的 `frame` 同步）在 Godot 里只能逼近，不能逐像素一致。

### 5.3 M2 —— 全技能

**目标**：193 个脚本全部可跑。规模：**386 个名字、5368 个调用点、170 个文件**。

M2 相对 M1 的增量（约 108 个名字）集中在：

- **创造者法师的 UI 层**：`sq_GetPopupWindows`、`sq_SetClipCursor`、`sq_IsMousePtInWindowRect`、`sq_drawToolTip`、`sq_GetStrikerSkillUi` 等 50 个只在 `.nut` 里出现（§3.3）——**它们不是战斗逻辑**，可以整批 `return null`，只在需要城镇/UI 时才实现。
- **二进制读侧**：`sq_BinaryStartRead` / `sq_BinaryGetDWord`（`po_spincutter.nut`， priest 的旋转刀）。
- **其余职业的注册表**：`CNAvenger.pushState`(16) 等。

**可行性判断（总结）**：

| 判断 | 结论 |
|---|---|
| 能否「照搬参数签名 + 一个引擎适配层」 | **主体可以**。386 个名字里约 360 个是纯查询/纯计算/纯缓冲写入，适配层就是一张 `Dictionary` + 几个单例。 |
| 真正没有对应物的 | ① `sq_BinaryStartWrite` 系列依赖**全局写缓冲**（脚本看不到 buffer 对象，写完由引擎附带发送）——用单例 `PacketBuffer` 可解，但要保证「写完立刻发包」的顺序不被其它脚本插入；② `sq_BinaryParameterWriteDword` 是**第二条并行缓冲**，同样要单例化；③ `sq_GetGlobalIntVector` 是**全局共享向量**，多对象并发时会互相踩，必须「取来即清空 + 用完即弃」，否则行为与原版一致地脆弱；④ `sq_SetFrameDelayTime` / `sq_SetStaticSpeedInfo` 直接改动画时间轴，Godot 只能用 `speed_scale` + 自维护帧延迟表逼近；⑤ `sq_AddStateLayerAnimation` 的多层同步、`sq_flashScreen` 的帧区间淡入淡出，都只能近似。 |
| 工作量估计 | M0 的 68 个 + 24 个对象方法 ≈ **一套 1000 行以内的适配层**；M1 再翻一倍；M2 的剩余部分是「跳过」而不是「实现」。 |
| 最大风险 | 不是 API 缺失，而是**状态机时序**：`sq_AddSetStatePacket` 下一 tick 生效、被动对象 `setCustomData` 与发包的顺序、`onKeyFrameFlag` 的帧回调精度。这三处一旦偏差，技能会「能放但打不中」。 |

### 5.4 给实现者的三条硬约定

1. **坐标系**：脚本里 `X` 是水平、`Y` 是深度（绘制层方向）、`Z` 是高度，且 Y 越大越「靠后」。Godot 是 `Vector3(x, y, z)` 但 Y 向上——映射时把脚本 Z 放 Godot Y、脚本 Y 放 Godot Z，否则 `sq_GetDistancePos(…, ENUM_DIRECTION_UP, …)` 的方向会反。
2. **方向枚举**：`ENUM_DIRECTION_LEFT=0 / RIGHT=1 / UP=2 / DOWN=3 / NEUTRAL=4`（`sqr_consts.gd:88-92`），不要映射成 ±1，否则 `sq_GetDirection()` 与 `ENUM_DIRECTION_LEFT` 的比较会全错。
3. **主控端**：所有发包/建对象/改攻击信息的调用都在 `isMyControlObject()` 里；单机版让它恒 `true` 是对的，联机版必须换成权威判断，否则会出现双倍伤害/双份特效。
