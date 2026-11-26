# 14 · 技能 → 动画 → 判定：机器可读链条表

> 产出物：`export/_meta/skill_anim_map.json`（28 条记录）+ 生成器 `tools/skill_chain.py`
> 范围：`analysis/10-SLICE.md` 首切片 Lv1–20 鬼剑士技能（23 行）+ 普攻 3 段 + 跳跃/冲刺攻击 = 28 条
> 一句话结论：**链条在数据侧只对「有 nut 的技能」闭合；首切片 23 个技能里只有三段斬(8) 有 nut，其余 22 个是引擎内置，动作下标不在 PVF 里 —— 但 28 条记录里有 9 条能从 `.ani` 里取到真实的 `[ATTACK BOX]`，够实现组直接开工。**

---

## 1. 链条本身（5 层，每层一个数据源）

```
① .skl  ──id──►  ② .nut (pushState)  ──stateId/substate──►  ③ chr [etc motion][n]
                                                                     │
                                                    ④ .ani 帧（FLAG / ATTACK BOX / DAMAGE BOX）
                                                                     │
                                              chr [etc attack info][m] ──► ⑤ .atk（伤害与硬直参数）
```

| 层 | 数据源（可复现） | 首切片命中率 |
|---|---|---|
| ① `.skl` | `export/structured/skl.jsonl.gz` + `export/_meta/lst/skill__swordmanskill.lst.tsv`（id→path） | 23/23 |
| ② `.nut` | `export/text/sqr/character/swordman_load_state.nut.txt`（87 条 `IRDSQRCharacter.pushState`） | **1/23** |
| ③ `[etc motion]` | `character/swordman/swordman.chr`，**281 项**，0 基 | 18/23（5 个无动作：卡贊/四系精通/邪光斬/死亡抗拒/后跳/受身蹲伏类） |
| ④ `.ani` | `export/text/**/*.ani.bin` + `tools/ani_parser.py`（字段 `0x0F [ATTACK BOX]`、`0x0E [DAMAGE BOX]`、`0x17 [FLAG]`） | 18/23 解析成功，**9 条有判定盒** |
| ⑤ `.atk` | `chr [etc attack info]`（**155 项**，0 基）+ `export/structured/atk.jsonl.gz` | 16/23 |

统计（`skill_anim_map.json → stats`）：

| 指标 | 数 | 说明 |
|---|---|---|
| 记录总数 | 28 | 23 技能 + 5 内置动作 |
| 五层全闭合 | **1** | 只有 `8 三段斬`（nut 给出一切） |
| 断在「无 nut」 | 27 | 引擎内置 —— 见 §3 |
| 断在「无 ani」 | 10 | 纯被动/增益/位移，本来就没有本体动作 |
| 断在「无 atk」 | 12 | 同上（格擋/精通/后跳…） |
| 无 `[ATTACK BOX]` | 19 | 判定盒非数据驱动 —— 见 §5 |
| 无 `[FLAG]` 帧 | 27 | 全切片只有 `十字斬` 有 flag（`[1,2]`） |

---

## 2. 逐条记录（`skill_anim_map.json` 的正文）

> `ani_frames` = **带 `[ATTACK BOX]` 的帧号**（0 基）；`—` = 数据里没有。
> 文件路径省略公共前缀：`.ani` 都在 `export/text/character/swordman/animation/`，`.atk` 都在 `export/text/character/swordman/attackinfo/`。

| id | 名称 | 学习Lv | stateId | .ani | 判定帧 | FLAG | .atk |
|---|---|---|---|---|---|---|---|
| — | basic_attack_1 | 1 | 8 | attack1.ani | — | — | Attack1.atk |
| — | basic_attack_2 | 1 | 8 | attack2.ani | — | — | Attack2.atk |
| — | basic_attack_3 | 1 | 8 | attack3.ani | **2, 3** | — | Attack3.atk |
| — | dash_attack | 1 | — | dashattack.ani | **2–8** | — | DashAttack.atk |
| — | jump_attack | 1 | — | jumpattack.ani | **2** | — | JumpAttack.atk |
| 46 | 上挑 | 1 | — | zrr/upper_body.ani | **3, 4, 5** | — | UpperSlash.atk |
| 5 | 鬼斬 | 1 | — | hardattack.ani | — | — | HardAttack.atk |
| 1 | 格擋 | 5 | — | guard.ani | — | — | — |
| 11 | 連突刺 | 5 | — | dashattackmultihit.ani | **2–6** | — | DashAttackMultiHIt.atk |
| 16 | 銀光落刃 | 5 | — | upperslashafter.ani | — | — | AshenFork.atk |
| 17 | 空中連斬 | 5 | — | jumpattackmultislash2.ani | — | — | —（无同名 atk） |
| 25 | 鬼神·卡贊 | 5 | — | —（召唤类） | — | — | — |
| 58 | 裂波斬 | 10 | — | vaneslashtry.ani | **2, 3** | — | VaneSlashSmash.atk |
| 65 | 崩山擊 | 10 | — | hopsmash.ani | **3, 4, 5** | — | HopSmash.atk |
| 8 | 三段斬 | 15 | **101** | zrr/ghostchangtion/tripleslashbsattacka_body.ani | **1, 2, 3** | — | zrr/tripleslashbs1.atk |
| 20 | 地裂·波動劍 | 15 | — | standalonewavestrong.ani | — | — | StandAloneWave.atk |
| 64 | 十字斬 | 15 | — | gorecross.ani | — | **[1, 2]** | GoreCross1.atk |
| 77 | 月光斬 | 15 | — | moonlightslash1.ani | **2, 3** | — | MoonlightSlash1.atk |
| 12–15 | 四系精通 | 15 | — | —（被动） | — | — | — |
| 18 | 鬼影步 | 20 | — | ghoststepslashmove.ani | — | — | GhostStepSlash.atk |
| 50 | 邪光斬 | 20 | — | — | — | — | — |
| 34 | 死亡抗拒 | 20 | — | —（增益） | — | — | — |
| 169 | 后跳 | 1 | 7 | —（位移） | — | — | — |
| 174 | 基礎精通 | 1 | — | —（被动） | — | — | — |
| 190 | 受身蹲伏 | 1 | — | — | — | — | — |

`export/_meta/skill_anim_map.json` 每条记录字段：`{skill_id,name,level_req,skl,skl_type,state_id,nut,flag_index,ani,ani_motion,ani_index,ani_frames,ani_frame_count,ani_frame_ms,ani_flags,attack_info_index,atk,damage_bonus,atk_fields,hitbox,boxes,ani_source,atk_source,substates,unresolved}`。

---

## 3. 断点一：22 个技能没有 `.nut`（最重要的发现）

扫全库 **2,487 个 `.nut.txt`** 找 `checkExecutableSkill_<Name>` / `onSetState_<Name>`：

| 技能 | 命中 nut？ |
|---|---|
| 三段斬 TripleSlash | ✅ `sqr/character/swordman_jg/tripleslash/tripleslash.nut` |
| 上挑 / 鬼斬 / 連突刺 / 銀光落刃 / 空中連斬 / 卡贊 / 崩山擊 / 地裂波動劍 / 月光斬 / 后跳 / 受身蹲伏 / 基礎精通 | ❌ **0 命中** |
| 格擋 / 死亡抗拒 / 十字斬 / 裂波斬 / 鬼影步 / 邪光斬 | ⚠️ 只在**别的职业**命中（`atswordman/guard`、`atmage/diehard`、`demoniclancer/crescentslash`…），鬼剑士本体的实现是引擎内置 |

→ **推论**：`skillId → stateId → 动作下标` 这张表对老技能硬编码在客户端 exe 里，PVF 只存 `.skl` 数值与 `.ani/.atk` 素材。**复刻时这层映射必须由我们自己建表**（本 JSON 的 `ani_index`/`attack_info_index` 两列就是候选值，来源见 `ani_source`）。

**反向证据**：`swordman_load_state.nut` 里 87 条 `pushState` 中大量 `skillId = -1`（Kalla 44 / BloodSword 60 / ChargeCrash 37 / RapidMoveSlash 39 / IllusionSlash 40 / MomentarySlash 23 / HundredSword 47 …）——`-1` 表示「这个 state 不由技能书触发」，同样说明老技能走引擎。

---

## 4. 断点二：动作下标只能「按名字推断」，且有两条坑

### 坑 1：nut 头部注释里的常量编号已过期

`tripleslash.nut` 前 10 行是注释形式的常量表：

```
//CUSTOM_ANI_TRIPLE_SLASH_BODY_ATK_A <- 240        ← 旧值
//ATTACKINFO_TRIPLESLASH_SWORDSABER_HIT_1 <- 150   ← 旧值
```

权威值在 **`sqr/character/swordman_jg/swordman_value.nut`**（265 行，96 条常量）：

```
第 98 行  CUSTOM_ANI_TRIPLE_SLASH_BODY_ATK_A <- 257
第 148 行 ATTACKINFO_TRIPLESLASH_SWORDSABER_HIT_1 <- 149
第 101 行 CUSTOM_ANI_UPPER_BODY <- 260
第 151 行 ATTACKINFO_SWORDSABER_DASHATTACK <- 152
```

差 17。**以 value 文件为准**（`tools/skill_chain.py` 就是这么做的），否则 `chr [etc motion][240]` 指向的是别的动画。

### 坑 2：`[etc motion]` 与 `[etc attack info]` **下标不对齐**

| 下标 | `[etc motion]`（281 项） | `[etc attack info]`（155 项） |
|---|---|---|
| 0 | `Animation/Guard.ani` | `AttackInfo/HardAttack.atk` |
| 1 | `Animation/HardAttack.ani` | `AttackInfo/HitBack.atk` |
| 11 | `Animation/DashAttackMultiHit.ani` | `AttackInfo/UpperSlash.atk` |
| 14 | `Animation/VaneSlashTry.ani` | `AttackInfo/DashAttackMultiHIt.atk` |

→ **不能按下标平移**，只能名字匹配；且要容错官方拼写 `DashAttackMultiHIt`（大写 I）、`[hit horizen]`（拼错）、`CUSTOM_ANI_UNLMATE_SPEED_SLASH`。

---

## 5. 断点三：判定盒不是数据驱动的（影响手感，必须自定）

### 5.1 同一个 ani 有两份副本，**只有 chr 根那份带 `[ATTACK BOX]`**

| 文件 | 帧数 | `[ATTACK BOX]` 数 | `[FLAG]` |
|---|---|---|---|
| `character/swordman/animation/dashattack.ani.bin` | 10 | **7** | — |
| `equipment/character/swordman/growtype/weaponmaster/dashattack.ani.bin` | 10 | **0** | — |
| `character/swordman/animation/jumpattack.ani.bin` | 6 | **1** | — |
| `equipment/.../weaponmaster/jumpattack.ani.bin` | 6 | **0** | — |

→ `%s/` 展开出来的那份（装备图层副本）判定盒被剥掉了。**解析优先级必须是 chr 根 → weaponmaster → 全局同名**（本工具已按此实现；按名字裸搜会命中怪物/其他职业的同名文件，实测 `Guard.ani` 会撞到 `monster/.../dragonknight/`，`GoreCross.ani` 会撞到 `mage/.../at_cubx/`）。

### 5.2 切片 23 个技能里只有 6 个带盒

带盒：上挑(3 帧)、連突刺(5 帧)、裂波斬(2 帧)、崩山擊(3 帧)、三段斬(3 帧)、月光斬(2 帧)。
不带盒：其余全部，包括**普攻第 1、2 段**（`attack1/2.ani` 只有 `[DAMAGE BOX]` = 角色自身受击盒，没有攻击盒）。

→ 老技能的命中判定盒在客户端里由「武器子类型 + 攻击力」算出来，PVF 里只有 `.atk`（伤害倍率/硬直/击退）。**复刻口径：技能判定盒按上表 6 条照抄，其余按同类技能的盒自定**（例如普攻按 `attack3.ani` 的 `(-32,-13,0,179,26,94)` 缩一档）。

### 5.3 盒的语义

`(相对X, 相对Y, 相对Z, 宽, 高, 深)`，与 `docs/ANI-FORMAT.md` §5 的正样本逐值核对一致（该文档 5/5 命中）。`FLAG = 65534 (0xFFFE)` 是「无 flag」哨兵，不是真实 flagIndex。

---

## 6. 五条逐值核对（脚本行号 → chr 下标 → ani 文件 → 帧号 → atk 字段）

### ① 三段斬 id=8（唯一五层全闭合）

| 步骤 | 证据 |
|---|---|
| `.skl` | `skill/swordman/tripleslash.skl`：`[required level] 15`、`[purchase cost] 15`、`[maximum level] 70`、`[type][active]`、`[command] (RIGHT) & (SKILL)` |
| `.nut` | `sqr/character/swordman_load_state.nut` **第 93 行**：`pushState(0, "character/swordman_jg/tripleslash/tripleslash.nut", "TripleSlash", 101, 8)` → stateId **101**，skillId **8** |
| 常量 | `tripleslash.nut` 第 87-90 行 `substate == 1001` → `sq_SetCurrentAnimation(CUSTOM_ANI_TRIPLE_SLASH_BODY_ATK_A)` + `sq_SetCurrentAttackInfo(ATTACKINFO_TRIPLESLASH_SWORDSABER_HIT_1)`；`swordman_value.nut` 第 98/148 行给出 **257 / 149** |
| `.ani` | `chr [etc motion][257]` = `animation/zrr/ghostchangtion/tripleslashbsattacka_body.ani` → 实文件 `export/text/character/swordman/animation/zrr/ghostchangtion/tripleslashbsattacka_body.ani.bin`，5 帧 / 560ms，**第 1、2、3 帧 AB = (-50,-25,0,200,50,80)** |
| `.atk` | `chr [etc attack info][149]` = `character/swordman/attackinfo/zrr/tripleslashbs1.atk`：`[attack type][physic]`、`[damage reaction][damage]`、`[attack direction][hit horizen]`、`[push aside] 50`、`[lift up] 120`、`[hit wav] R_SWD_HIT`、无 `[damage bonus]` → 100% |

`tripleslash.nut` 的 8 个 substate 全表已写进 JSON 的 `substates`（1000/1002/1004 = 预备动作 READ_A/B/C=254/255/256；1006 = `CUSTOM_ANI_UPPER_BODY`=260 配 `atk 11`=UpperSlash.atk；1007 = `CUSTOM_ANI_BLADECHANGTION_DASHATTACK`=261 配 `atk 152`）。

### ② 上挑 id=46（常量反推 + 交叉验证）

`swordman_value.nut` 第 101 行 `CUSTOM_ANI_UPPER_BODY <- 260` → `chr [etc motion][260]` = `animation/zrr/upper_body.ani`（9 帧 / 550ms）→ **第 3、4、5 帧 AB = (-32,-15,0,238,30,169)**。交叉验证：`tripleslash.nut` 第 165-166 行正是「`CUSTOM_ANI_UPPER_BODY` + `sq_SetCurrentAttackInfo(11)`」，而 `[etc attack info][11] = AttackInfo/UpperSlash.atk` —— **同一条常量对儿在另一处脚本里被复用，证明 260↔上挑 成立**。该 atk：`[damage reaction][down]`、`[attack direction][hit lift up]`、`[hit wav] R_SLESSSWDA_HIT`、无 `[push aside]`/`[lift up]` 数值（浮空力走 .skl 的 `[level info]` 第 2 列）。

### ③ 冲刺攻击（内置，stateId 不进 nut）

`chr [dashattack motion][0]` = `Animation/DashAttack.ani` → `character/swordman/animation/dashattack.ani.bin`，10 帧 / 630ms，**第 2–8 帧 AB = (82,-13,51,85,26,27)**（头顶前伸的长条）。
`chr [dashattack info][0]` = `AttackInfo/DashAttack.atk`：`[damage bonus] 40`（=140%）、`[physic]`、`[damage reaction][damage]`、`[attack direction][hit horizon]`、`[push aside] 50`、`[lift up] 80`。
→ **复刻最省事的一条**：盒、倍率、硬直全部有数，可以直接写进 `.tres`。

### ④ 普攻第三段

`chr [attack motion][2]` = `Animation/Attack3.ani` → 9 帧 / 550ms，**第 2、3 帧 AB = (-32,-13,0,179,26,94) / (15,-13,1,137,26,138)**；`chr [attack info][2]` = `AttackInfo/Attack3.atk`：`[damage bonus] 20`（120%）、`[push aside] 40`、`[lift up] 300`。
相反，`attack1.ani`(10 帧) 与 `attack2.ani`(11 帧) **零攻击盒** —— 三段普攻里只有第三段有数据，前两段必须自定。

### ⑤ 崩山擊 id=65

`etc motion[26]`=`HopSmashReady.ani`(1 帧,无盒) → `[27]`=`HopSmash.ani`(7 帧/900ms)，**第 3、4、5 帧 AB = (-10,-20,-2,86,40,49)**；`etc attack info[25]`=`HopSmash.atk`：`[push aside] 30`、`[lift up] 30`（浮空很小 = 地面砸）。工具按「候选 [27,26]，取第一个带盒的」选中 27。

---

## 7. 复刻时必须实现的最小集

1. **三层查表**（纯数据，可直接生成 Godot `Resource`）：`skill_id → {stateId, ani_index, atk_index, hitbox, frames}` —— 本 JSON 已是这个结构。
2. **帧驱动的判定开关**：`.ani` 里「有 `[ATTACK BOX]` 的帧 = 判定窗口」，其它帧无判定。不要用「第 N 帧固定判定」，要读 `attack_frames`。
3. **盒坐标 = 相对角色锚点**（x 向前、y 向下、z 朝屏幕外），翻转角色时 x 取反、w 不变。
4. **`[FLAG]` 帧回调**：帧上 `flag != 65534` 时给脚本发 `onKeyFrameFlag(state, flag)`；切片里只有 `十字斬` 用（flag 1、2），其余可以留空实现。
5. **`.atk` 只提供「倍率 + 硬直 + 击退/浮空 + 元素 + debuff」，不含盒**——伤害公式的输入是「基表攻击力 × `[damage bonus]`% × 技能 `[level info]` 倍率」。
6. **自建映射表**：22 个内置技能的 `ani_index/atk_index` 必须由我们维护（本 JSON 的候选值可用，标了 `ani_source`），因为 PVF 里没有。

## 8. 待验证 / 已知不闭合

| # | 项 | 现状 |
|---|---|---|
| U1 | 22 个内置技能的**真实**动作下标 | 只有名字/常量推断，无权威来源；`skillId→motion` 表在客户端 exe 里 |
| U2 | `銀光落刃` 用的是 `UpperSlashAfter.ani`？ | 无同名 ani，按「銀光落刃=上挑空中版」猜，**待验证** |
| U3 | `裂波斬` 取 `VaneSlashTry.ani`（14，有盒）而非 `VaneSlash.ani`（15，无盒） | 工具策略「候选里取带盒的」；两段都可能判伤害，`unresolved` 已记 |
| U4 | `空中連斬` 的 atk | `[etc attack info]` 里没有 `JumpAttackMultiSlash*.atk`，可能借用 `JumpAttack.atk` 或独立 atk，**待验证** |
| U5 | `邪光斬` 动作 | 281 项 motion 里没有 `grandwave`/`shockwave` 同名项，可能用 `WaveEye*` 系列或纯特效，**待验证** |
| U6 | 无 nut 技能是否真的是 C++ 内置 | 依据是「nut 里 0 命中 + skillId=-1 大量出现」，未见反例，但与「有 nut 的同名他职业实现」并存，标**推断** |

---

## 9. 更正（v2，captain 实测复核）：普攻 1、2 段的攻击盒在**武器层**动画里

> 本节为**追加更正**，§5.2 的原始结论保留不动以便对照。凡与本节冲突，以本节为准。

### 9.1 原结论错在哪

§5.2 写「普攻第 1、2 段 `attack1/2.ani` 零攻击盒 → 必须自定」——**盒是有的，只是不在身体层**。我当时只解析了 `character/swordman/animation/` 这一层，漏了武器层。

### 9.2 实测证据（两层是叠加关系，不是二选一）

| 层 | 文件 | 帧数 | 时长 | 给什么 |
|---|---|---|---|---|
| 身体 | `character/swordman/animation/attack1.ani` | 10 | 600 ms | 姿态 + **受击盒** `db` 3 块（头/躯干/腿） |
| 武器 | `equipment/character/swordman/weapon/katana/katanac/attack1.ani` | 10 | 600 ms | 轨迹 + **攻击盒** `ab` 1 块（f3） |
| 身体 | `character/swordman/animation/attack2.ani` | 11 | 650 ms | 姿态 + 受击盒 |
| 武器 | `equipment/character/swordman/weapon/katana/katanac/attack2.ani` | 11 | 650 ms | 轨迹 + 攻击盒 2 块（f2、f3） |

**帧数与时长逐一相等**（10/600、11/650），所以武器层的攻击盒可以**直接按帧号叠加到身体层帧上**，不需要时间轴对齐。

太刀（`katanac`）逐值：

```
attack1.ani  f3  ab = (49, -10, 47, 68, 23, 53)
attack2.ani  f2  ab = (58, -26, 54, 74, 49, 30)
             f3  ab = (-45, -17, 36, 91, 55, 35)
```

对照 §6④ 普攻第 3 段（`attack3.ani` 身体层就有盒 `(-32,-13,0,179,26,94)`）——所以「三段普攻里只有第三段有数据」这个说法的一半仍然成立：**第三段的盒在身体层，前两段在武器层**。

### 9.3 覆盖度（两个数都对，是两把尺子）

武器动画套共 **78 套（72 套普攻 1 段有盒 = 92.3%）**；其中帧数与未转职身体层（`attack1.ani` 10 帧）对齐的有 **51 套（45 套有盒 = 88.2%）**，**只有这 51 套可以不经校验直接叠加**，其余 27 套帧数不是 10，配的是别的身体动画（转职变体 / AT 外观），硬套到 `character/swordman/animation/attack1.ani` 上会**帧号错位**。

> 口径：78 套 = `weapon/*/*` 下存在 `attack1.ani` 且排除 `at_*`；51 套 = 其中 `attack1.ani` 恰好 10 帧的（已实测复核：`TOTAL 10帧套: 51 其中有盒: 45`）。

**分族触及 X（`x+w` 最大值，实测 min / 中位 / max）**：

| 武器族 | 套数 | 有盒 | 触及 X（min/中位/max） |
|---|---|---|---|
| katana | 28 | 27 | 104 / 120 / **143** |
| hsword | 17 | **17（全有盒，最稳）** | 104 / 126 / **141** |
| ssword | 13 | 12 | 104 / 117 / 119 |
| beamsword | 11 | 8 | 104 / 134 / 134 |
| club | 9 | 8 | 104 / 112 / **117** |

（族按**目录名**统计，所以是 28 套 katana 含各外观变体，不是「10 套」的子集口径。）

**触及 X 的算法（口径必须写死）**：对每套取 `attack1.ani` 里**所有帧、所有盒**的最大 `x + w`（即该套的最大触及宽度）。早前与 captain 的 hsword 中位差（126 vs 130）源于此处：若每帧只取 `ab[0]`，多盒套会偏大。**以「全盒取最大」为准**；hsword 值域 `104×4, 126×6, 132×3, 141×4` → 中位 **126**、max **141**。

**结论方向不变：换武器确实改手感，且差异不小（117 vs 143，约两成）。复刻时不要用一套盒打所有武器。**

### 9.4 ⭐新坑（比「双份副本」更隐蔽）：`at_` / `ATEquipment` 是另一套图，帧数不同

`atanimation/` 与 `equipment/.../at_*` 用的是 `ATEquipment/Avatar/skin/sg_body%04d.img`，帧数是 **6/5/4** 而不是 **10/11/9**。

它会**静默错配**：整数帧号不错位报错，只是全部打空。所以解析时必须显式过滤：

```python
AT_MARKERS = ("/at_", "atequipment", "at_avatar")
def is_at_avatar(path):
    low = path.replace("\\", "/").lower()
    return any(m in low for m in AT_MARKERS)
```

（`tools/skill_chain.py` 已在 `build_ani_index` / `resolve_ani` / `build_weapon_index` 三处统一走这个过滤器。）

### 9.5 JSON 已做的改动（`export/_meta/skill_anim_map.json`）

新增 4 个字段（**原字段一个没删**）：

| 字段 | 含义 |
|---|---|
| `weapon_ani` | 武器层 ani 路径，太刀 = `equipment/character/swordman/weapon/katana/katanac/attackN.ani.bin`；无对应武器动画时为 `null` |
| `weapon_boxes` | 武器层的 `[ATTACK BOX]` 列表（六元组 + 帧号） |
| `weapon_ani_frames` | 武器层带盒的帧号 |
| `hitbox_source` | **固定三值枚举 `body` / `weapon` / `none`**（不设组合值，下游据此分支）。实测分布：`body` 9、`weapon` 5、`none` 14 |

变化：`no_hitbox` **19 → 14**，`boxes` 非空 **9 → 14**。新增 5 条改由武器层供盒：`basic_attack_1`、`basic_attack_2`、`鬼斬`、`地裂·波動劍`、`十字斬`（十字斬身体层有 FLAG 无盒）。
`unresolved` 措辞同步改为「身体层 ani 无 [ATTACK BOX]（判定盒不在动画里）」与「攻击盒取自武器层 ani（身体层无盒，帧号与身体层一一对应）」。

### 9.6 复刻口径（替换 §7 第 2 条）

**判定窗口 = 该帧「身体层 `ab`」∪「武器层 `ab`」的非空帧**；两层帧号一一对应，直接并集即可。武器层缺失（无武器动画的武器族）时退回只有身体层。判定盒取用时以 `hitbox_source` 为准。

### 9.7 字段契约（下游可依赖）

- `hitbox_source`：**只允许 `body` / `weapon` / `none`**，不设 `body+weapon` 之类组合值。判据 = `boxes` 非空时看盒从哪层来；两层都有盒时记 `body`（`weapon_boxes` 字段仍完整保留武器层数据，需要叠加判定时自行并集）。
- `boxes` 的**帧号永远对应身体层动画**（`ani_frame_count` / `ani_frame_ms` 是身体层值）。武器层帧号与身体层一一对应，所以取 `weapon` 时无需换算；但**必须先校验两层帧数相等**：
  - 切片武器（katana `katanac`）已校验通过（普攻 10/11/9 一一对应）；
  - 若换用帧数不等的武器套（78 套里有 27 套 `attack1.ani` ≠ 10 帧），叠加前必须重算，否则帧号错位且**不会报错**。
- `weapon_ani` 为 `null` 表示该动作没有武器层动画（技能多半如此），此时判定只看身体层。
