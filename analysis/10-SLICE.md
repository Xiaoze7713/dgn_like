# 10 · 首切片设计包（M3 垂直切片）

> 本文把 `02-character` ~ `08-quest` 的结构分析落成**一个能直接开工的内容集**：1 个职业、1 个城镇、3 个副本、12 只怪、10 件装备、4 环主线任务、1 条任务道具链。
> 所有 id / 路径均来自本仓库 `export/text/`（sf115 Script.pvf）实测，可直接抽验。凡「数据里没有、必须自己定」的量，一律在 §12 标注，不在正文里伪装成官方值。

---

## 0. 结论速览（先看这 6 行）

| 决策 | 值 | 理由 |
|---|---|---|
| 职业线 | **未转职鬼剑士（swordman，growtype 0）**，Lv1–20 | 转职后每个分支要独立技能树 + `.lay` 分叉 + 装备 variation，Lv1–20 基础鬼剑士已有 20+ 技能（§3），足够撑起切片；转职放 M4 |
| 起始城镇 | 艾爾文防線 `town/1_new/new_Elvengard.twn`（town.lst = 1） | 主线副本入口，全服最低级城镇 |
| 副本 | `dungeon/act1/lorien.dgn`(1) · `dungeon/act1/mirkwooddeep.dgn`(4) · `dungeon/act1/sunderlandpoison.dgn`(6) | 最低三级阶梯 1→3→7，覆盖 boss 图，且都有 `[greed]` 可还原 |
| 怪物 | 12 只：goblin 族 8（id 1/2/3/4/5/6/8）+ tau 1（id 12）+ lugaru 4（5001–5004） | 全部 `[ability table]` 默认 0 → 直接吃 `monsterbaseparameter.tbl` |
| 装备 | 太刀 5 件（27600/27601/27602/27606/27611）+ 上衣 3 件（10000/10001/10002）+ 任务腰带 16400 + 短裤 12401 | act1 **怪物不掉装备**（§8 实测），装备来源只能是商店 + 任务奖励 |
| 任务 | 101 → 102 → 103 → 104（主线 4 环）+ 支线 `normal_2_lorieninside_seria_ring`（含任务道具掉落链） | `epicquest.lst` 第一章 `[epic_index]` 就写着 `101 102 103 …` 是同一章节的前三环 |

---

## 1. 口径与边界

- **只读 `export/`**；本文是唯一产出。
- 「PVF 内真实值」写成具体数字并给路径；「设计自定值」一律前缀 `★`。
- 时间单位：`.skl [cool time]` 毫秒；`.atk` 无时间字段；`[push aside]/[lift up]` 单位是**百分比**（10 = 10%）。
- 距离单位：像素。地图坐标原点在房间左上，y 向下（与 `.map [monster]` 的 x/y 一致）。
- `[greed]` 每格 **2 字符**，行宽 = `[size].cols × 2`，15 个出口 token 见 §5.1。

---

## 2. 切片内容总表

| 系统 | 内容 | PVF 路径 / id | 必需(M3) | 可后做(M4) |
|---|---|---|---|---|
| 角色 | 未转职鬼剑士 | `character/swordman/swordman.chr` | ✅ | 转职/觉醒 |
| 成长 | 每级增量（HP+45/MP+25/物攻+4.8…） | `swordman.chr [growtype 1]` | ✅ | 二次成长曲线 |
| 经验 | 升级经验表 | `character/exptable.tbl` | ✅ | 疲劳值/经验加成 |
| SP | 技能点表 | `etc/sptable.etc [sp table]` | ✅ | TP/GSP |
| 技能 | 20 个 Lv1–20 可用技能 | `skill/swordman/*.skl`（§3.2） | ✅ | 转职技能、TP、指令扩展 |
| 技能逻辑 | `_load_state.nut` 状态机 | `sqr/character/swordman_load_state.nut` | ⚠️ 用引擎内建代替 | 全量脚本 |
| 动作 | `.lay` + `.ani` | `equipment/character/swordman.lay` | ✅ | 全技能动画 |
| 城镇 | 艾爾文防線 | `town/1_new/new_Elvengard.twn` + `map/1_new/Cataclysm/Town/Elvengard/new_Elvengard.map` | ✅ | 其余 6 个 area |
| NPC | 林納斯(1) + 賽麗亞(2) | `npc/1_new/linus.npc` / `npc/Seria.npc` | ✅ | 卡妮娜(3) 等 |
| 商店 | 武器店 | `itemshop/EquipmentShop1.shp` | ✅ | 其余 123 个 shp |
| 世界地图 | 洛蘭 | `worldmap/Lorien.wdm` | ✅ | 世界地图 UI |
| 副本 | 洛蘭 / 幽暗密林深處 / 猛毒雷鳴廢墟 | dgn 1 / 4 / 6 | ✅ | act2+ |
| 房间 | 15 / 63 / 80 间（切片只取子集，§5） | `map/lorien/*`、`map/…/4xx`、`map/…/8xx` | ✅ | 全量房间 |
| 怪物 | 12 只（id 1,2,3,4,5,6,8,12,5001,5002,5003,5004） | `monster/{goblin,tau,lugaru}/*.mob` | ✅ | 其余 3,530 只 |
| 怪物 AI | 4 件套 `.ai` | `monster/goblin/ai/*.ai` 等 | ✅（简版） | 复杂条件树 |
| 攻击数据 | `.atk` | `monster/goblin/attackinfo/*.atk` | ✅ | 全量 |
| 掉落 | 消耗品/材料 9 种 | `.mob [item]` 表 | ✅ | 独立掉落表（act2 起才有） |
| 装备 | 太刀 5 + 上衣 3 + 腰带 1 + 短裤 1 | `equipment/character/…` | ✅ | 全套 9 部位 |
| 强化/修理 | **不进切片** | `etc/upgrade.etc` | ❌ | M4 再评估 |
| 任务 | 101/102/103 + 支线 | `n_quest/elvengard/**` | ✅ | 任务链扩充 |
| 任务经济 | 经验/金币基数 | `n_quest/questparameter.etc` | ✅ | 难度曲线 |
| UI | 主 HUD + 背包 + 任务栏 | 见 `09-script-mechanics.md` §UI | ✅ | 商城/工会等 |

---

## 3. 职业线：未转职鬼剑士 Lv1–20

### 3.1 初始属性与成长

`character/swordman/swordman.chr`（顶层 = Lv1 基础值；`[growtype 1]` = **每级增量**）：

| 字段 | Lv1 基础 | 每级增量 | Lv20 推算 | 单位/说明 |
|---|---|---|---|---|
| `[HP MAX]` | 180.0 | +45.0 | 1035 | 点 |
| `[MP MAX]` | 140.0 | +25.0 | 615 | 点 |
| `[physical attack]` | 7.5 | +4.8 | 98.7 | 角色物攻属性（不是装备物攻） |
| `[physical defense]` | 7.5 | +4.8 | 98.7 | 物防 |
| `[magical attack]` | 4.5 | +4.2 | 84.3 | 魔攻 |
| `[magical defense]` | 4.5 | +4.2 | 84.3 | 魔防 |
| `[dark resistance]` | 20.0 | — | 20 | 暗抗（% 加成） |
| `[light resistance]` | -20.0 | — | -20 | 光抗（负 = 光属性挨打更疼） |
| `[inventory limit]` | 248000.0 | +300.0 | 253700 | 单位 **10g** → 24.8kg 起 |
| `[weight]` | 68000.0 | — | 68000 | 单位 10g = 6.8kg |
| `[MP regen speed]` | 50.0 | +2.5 | 97.5 | 每 10 秒回 MP 的千分比 |
| `[move speed]` | 1350.0 | — | 1350 | 1000 = 100% |
| `[attack speed]` | 1150.0 | — | 1150 | 攻击速度 |
| `[cast speed]` | 1000.0 | — | 1000 | 施法速度 |
| `[hit recovery]` | 600.0 | +1.5 | 628.5 | 受击硬直（越大越长） |
| `[jump power]` / `[jump speed]` | 430.0 / 97 | — | — | 跳跃初速 / 空中水平速度 |
| `[width]` | 40 10 | — | — | 碰撞盒 宽×高（像素） |
| `[module damage rate]` | 0.95 1.0 1.0 0.95 | — | — | 模式伤害倍率序列 |

> `[growtype 1]` 块另有 `[module damage rate] 0.95 1.0 1.0 0.95`，`[growtype 2]` 是 `0.7 1.0 1.1 0.7`（狂战士那档）。**切片用 Lv1 基础块 + `[growtype 1]` 的 9 个增量**；`[growtype] 块序号与转职的严格对应待验证（§12-R4）**。

### 3.2 技能清单（Lv1–20，全部实测字段）

> **口径说明**：本节 20 条 = `skill/swordman/*.skl` 共 **278** 个文件里，按 **`[required level] ≤ 20`** 筛过、且属于鬼剑士基础（`[skill fitness growtype]` 含 0）、去掉纯 TP/觉醒/转职专属之后的结果。转职后（growtype 1–4）专属技能与 21 级以上的技能**全部不在切片内**。

**初始白送**（`swordman.chr [skill] 181 2 182 2 184 1 179 7 5 1 46 1 169 1 198 1 199 1 174 1`，格式 = id 等级对）：
`181 副职业·分解`(2级) `182 副职业·制作`(2) `184 副职业·化学`(1) `179 副职业·炼金`(7) `5 鬼斬`(1) `46 上挑`(1) `169 后跳`(1) `198 炼化`(1) `199 平衡`(1) `174 基礎精通`(1)

**可学主动（id 来自 `npc/1_new/linus.npc [skill] [swordman] 1 5 28 8 11 16 20 25 46` = 导师商店可卖清单）**

| id | 名称 | `.skl` 路径 | 学习Lv | SP/级 | 上限 | 指令 | MP(低→高) | CD(ms) |
|---|---|---|---|---|---|---|---|---|
| 46 | 上挑 | `Swordman/UpperSlash.skl` | 1 | 20 | 50 | `Z` | 6→40 | 2000 |
| 5 | 鬼斬 | `Swordman/HardAttack.skl` | 1 | 15 | 700 | `↑+Z` | 17→196 | 6000 |
| 1 | 格擋 | `Swordman/Guard.skl` | 5 | 20 | 50 | `↓↓+X` | 3→4 | 2000 |
| 11 | 連突刺 | `Swordman/DashAttackMultiHit.skl` | 5 | 15 | 70 | `X` | 8→70 | 1000 |
| 16 | 銀光落刃 | `Swordman/AshenFork.skl` | 5 | 15 | 70 | `Z` | 10→120 | 4000 |
| 17 | 空中連斬 | `Swordman/JumpAttackMulti.skl` | 5 | 50 | 50 | `X` | ★(见注) | ★ |
| 25 | 鬼神·卡贊 | `Swordman/Khazan.skl` | 5 | 20 | 50 | `→+空格` | 10→400 | 10000 |
| 58 | 裂波斬 | `Swordman/VaneSlash.skl` | 10 | 15 | 70 | `→↑+Z` | 20→310 | 8000 |
| 65 | 崩山擊 | `Swordman/HopSmash.skl` | 10 | 15 | 70 | `→↓+Z` | 17→150 | 4000 |
| 8 | 三段斬 | `Swordman/TripleSlash.skl` | **15** | 15 | 70 | `→+Z` | 12→120 | 6000 |
| 20 | 地裂·波動劍 | `Swordman/NormalWave.skl` | 15 | 15 | 70 | `↓→+Z` | 17→168 | 3000 |
| 64 | 十字斬 | `Swordman/GoreCross.skl` | 15 | 15 | 70 | `←→+Z` | 17→170 | 3000 |
| 77 | 月光斬 | `Swordman/MoonlightSlash.skl` | 15 | 20 | 70 | `↑→+Z` | 17→182 | 4000 |
| 12 | 短劍精通 | `Swordman/ShortSwordMastery.skl` | 15 | 20 | 50 | — (passive) | — | — |
| 13 | 太刀精通 | `Swordman/BladeMastery.skl` | 15 | 20 | 50 | — (passive) | — | — |
| 14 | 巨劍精通 | `Swordman/HeavySwordMastery.skl` | 15 | 20 | 50 | — (passive) | — | — |
| 15 | 鈍器精通 | `Swordman/BluntMastery.skl` | 15 | 20 | 50 | — (passive) | — | — |
| 18 | 鬼影步 | `Swordman/GhostStep.skl` | 20 | 30 | 70 | `↑↓+空格` | 240→2016 | 30000 |
| 50 | 邪光斬 | `Swordman/GrandWave.skl` | 20 | 25 | 70 | `→→+Z` | 65→616 | 10000 |
| 34 | 死亡抗拒 | `Swordman/DieHard.skl` | 20 | 20 | 50 | `↑↑+空格` | 40→448 | 20000 |
| 169 | 后跳 | `Passive/BackStep.skl` | 1 | 30 | 1 | `↓+C` | — | — |
| 174 | 基礎精通 | `Swordman/BasicAttackUp.skl` | 1 | **0** | 110 | — (passive) | — | — |
| 190 | 受身蹲伏 | `Swordman/QuickStanding.skl` | 1 | 10 | 20 | `C` | — | — |

注：`17 空中連斬` 的 `[dungeon]` 块在本 PVF 中缺 `[consume MP]`/`[cool time]` 两项（脚本待查），切片按 ★MP 15→150、★CD 3000 填。

**指令语法**（官方 tagdict）：`(UP)(DOWN)(LEFT)(RIGHT)` 方向，`(SKILL)`=Z，`(ATTACK)`=X，`(JUMP)`=跳(C)，`(BUFF)`=空格；`,` = 顺序衔接，`&` = 按住方向。

**学习等级 → 时间线**（技能池 = 上表去掉转职专属）：

| 达到Lv | 新开学习 | 累计 SP 池 | 建议配点（★） |
|---|---|---|---|
| 1 | 上挑·鬼斬·后跳·基礎精通（白送1级） | 0 | — |
| 2 | — | 630 | 上挑→10、鬼斬→5（消 275） |
| 5 | 格擋·連突刺·銀光落刃·空中連斬·鬼神卡贊 | 630 | 連突刺→1、銀光落刃→5 |
| 10 | 裂波斬·崩山擊 | 630 | 崩山擊→5 |
| 11 | — | 660 | — |
| 15 | 三段斬·地裂波動劍·十字斬·月光斬·四系精通 | 660 | 三段斬→5、太刀精通→5、地裂→3 |
| 20 | 鬼影步·邪光斬·死亡抗拒 | 660 | 邪光斬→2 |

> ⚠️ `etc/sptable.etc [sp table]` 实测：`1 0 / 2 630 / 3 630 / … / 10 630 / 11 660 / … / 20 660`，官方注释「右边是升到当前等级可获得的 sp 点」→ **累计池**。Lv2 一次给 630 明显是后期重平衡口径，切片照用即可（技能 `purchase cost` 也是同版本口径，两者自洽）。

### 3.3 技能 → 动作/攻击数据 的接线（不在 .skl 里）

`.skl` 只有数值，**没有 ani、没有 atk、没有 .act**（玩家技能全库 0 个 `.act`）。真实链路（详见 `03-skill.md` §5）：

```
skill id ──► sqr/character/swordman_load_state.nut 里的
             IRDSQRCharacter.pushState(job, nut路径, 名字, stateId, skillId)
          ──► <skill>.nut 的 checkExecutableSkill_* / onKeyFrameFlag_*
          ──► CUSTOM_ANI_<名字> 常量（定义在 sqr/character/swordman_jg/swordman_value.nut）
          ──► 整数 = equipment/character/swordman.lay 的 [etc motion] 数组下标
          ──► %s 由装备 [layer variation] 展开 → 真实 .ani
          ──► ATTACKINFO_<名字> 常量 → .atk
```

**M3 实现口径**：不要还原 Squirrel。建一张 `SkillDef` 表（id / 状态id / ani 数组 / atk 路径 / 帧事件表），由 Godot 的 `SkillState` 直接读。切片的 20 个技能里，**只做 6 个有完整 ani+atk 的主动**（§3.4），其余做成可学但「播放同一套基础动作 + 数值不同」的占位。

### 3.4 M3 必须做完的技能（6 个）

| skill id | 名字 | 为什么选 | 需要的 ani 源 |
|---|---|---|---|
| 46 | 上挑 | 起手技，浮空（`[lift up]`）验证浮空系统 | `tripleslash` 家族同目录，`swordman/animation/*` |
| 5 | 鬼斬 | 魔法伤害分支（`[weapon effect type][magical]`） | 同上 |
| 8 | 三段斬 | 多段 hit + 帧事件（`[level info]` C=6，3 段伤害） | `equipment/character/swordman/growtype/weaponmaster/tripleslashbsattacka_body.ani` 等 |
| 11 | 連突刺 | 位移突进 + 多段 | 同上 |
| 16 | 銀光落刃 | 下劈 + 击倒（`[damage reaction][down]`） | 同上 |
| 25 | 鬼神·卡贊 | buff/召唤（可先做成纯属性 buff） | 可省 ani |

> ani 具体帧名不在本文硬编码：用 `docs/PVF-FORMAT.md` 的 `.ani` 解码（P0.5）拿到帧数，或在 Godot 里直接用 `equipment/character/swordman/growtype/weaponmaster/*.ani` 对应名称的 PNG 序列。**这是 M3 唯一必须碰二进制的点。**

---

## 4. 城镇：艾爾文防線（最小可用 = 2 个 NPC）

### 4.1 入口链路

```
town/town.lst            → 1 = 1_new/new_Elvengard.twn
new_Elvengard.twn [area] → 0: 1_new/Cataclysm/Town/Elvengard/new_Elvengard.map  [normal]   ← 主街
                           1: 1_new/Common/Gate_Seria_Elvengard.map             [gate] 450 234
                           2,3,4: new_D_Elvengard_L / Elvengard_hendon_storm / new_D_Elvengard_R
                           5,6: death_valley 两张
worldmap/worldmap.lst    → 1 = Lorien.wdm  [name] 洛蘭
Lorien.wdm [dungeon]     → 1 -1   2 -1   1500 428   1501 4340   （两值一组：副本id + 前置任务id，-1=无）
```

**注意**：`new_Elvengard.twn` 没有 `[dungeon gate]` —— 进副本走**世界地图 UI**（`WorldMap/UI/Lorien.ui`），不是走到门口。M3 可以先用一个按钮直接选副本，M4 再做 wdm 的坐标点。

### 4.2 主街房间 `new_Elvengard.map` 关键字段

| 字段 | 值 | 含义 |
|---|---|---|
| `[NPC]` | `1 [left] 1026 164 0` · `592 [left] 351 192 0` · `603 [right] 2543 170 0` · `618 [left] 2062 160 0` · `621 [left] 2062 160 0` · `40040 [right] 2146 160 0` | 每 NPC 4 值：id, 朝向, x, y, z |
| `[tile]` | `Tile/EGtile_basic.til` × 12 | 地形块，`[pass type]` 决定可行走格 |
| `[town movable area]` | `622 196 0 0 1 1` `571 129 50 50 1 1` | 可走矩形（x y ? ? ? ?） |
| `[virtual movable area]` | 8 组 6 值 | 视觉遮挡区 |
| `[far sight scroll]` | 103 | 远景视差滚动量 |
| `[sound]` | `M_FOREST_TOWN` `AMB_FOREST_01` | BGM + 环境音 |
| `[animation]` | 80+ 组（路径 图层 x y z） | 全部城镇装饰物 |

### 4.3 NPC（最小集 = 2）

| id | 名字 | `.npc` 路径 | role | 切片里干什么 |
|---|---|---|---|---|
| **1** | 林納斯（鐵匠林納斯） | `npc/1_new/linus.npc` | `[item shop] 2` + `[make weapon skin] 0` | ① 装备/药水商店（shop 2 = `itemshop/EquipmentShop1.shp`）② **技能学习**（`[skill] [swordman] 1 5 28 8 11 16 20 25 46`，即 §3.2 导师清单）③ 主线任务 102/103 的完成处 |
| **2** | 賽麗亞·克魯敏 | `npc/Seria.npc` | `[item shop] 15` + `[random option operate] 0` | ① 任务 101 的发布者、104 的完成处 ② `[quest speech] 願精靈的光芒照耀您……`（任务对话框） |

可选（M4）：`3 kanna.npc` 卡妮娜·雷米尼斯（`[item shop] 84`，消耗品店）、`592 tobi.npc` 跑腿的托比（纯对话）、`603 beatrice_arad.npc` 貝雅特麗齊。

**「最小可用城镇」= 2 个 NPC**：1 个能买卖+学技能（林納斯），1 个能接交任务（賽麗亞）。第 3 个起都是内容量，不是系统量。

**关于「仓库 / 修理」这两个常被问的功能**：本 PVF 的 `[role]` 枚举（官方 tagdict 全文见 `analysis/01-TAG-DICT.md`）里**没有仓库 NPC**，也没有独立修理 NPC —— 有的是 `[item shop]`(商店编号) `[secret shop]`(加百利) `[upgrade item]`(强化) `[recover stamina]`(解除虚弱) `[sera shop]`(商城) `[job change]`(副职业) `[product item]`(生产) 等。仓库与修理在原作里是**城镇 UI 功能**（点铁匠开「修理/强化」面板，点角色开「仓库」页签），不是 NPC 实体。所以：
- 修理：M3 挂在林納斯的交互菜单里（不需要新 NPC）
- 仓库：M3 直接做成 HUD 里的一个按钮（`[inventory limit] 248000` = 24.8kg 上限；无重量上限就退化成无限格）

**关于「技能学习」的接线**：`[skill]` 必须写在 `[role]` **外边**（官方注释原话：「导师技能商店（需写在 `[role]` 词条的外边）」）。`linus.npc` 的 `[skill] [swordman] 1 5 28 8 11 16 20 25 46` = 「职业 → 该职业可学技能 id 列表」，这正是 §3.2 的导师清单。

### 4.4 商店 `itemshop/EquipmentShop1.shp`

```
[NPC] 1
[type] [weapon shop]
[sell item] 1106 1107 1112 1113  -1  3175 3161 27601 29901 31301 33601 35002 37003  -1
```
`-1` = 分页符。第一页卖 4 瓶药，第二页卖 6 件各职业 Lv3 武器 + 2 张券：

| id | 名字 | 价格 | 说明 |
|---|---|---|---|
| 1106 | 諾頓的新手HP藥劑 | 100 | 消耗品，`[waste] 4` |
| 1107 | 諾頓的入門HP藥劑 | 200 | Lv6 起 |
| 1112 / 1113 | 羅莉安的新手/入門MP藥劑 | 100 / 200 | 同上 |
| 3175 / 3161 | 林納斯的火盆/鐵匠鋪使用券 | 10 / 500 | **切片不需要，跳过** |
| **27601** | 太刀（名称在本 PVF 里是乱码） | 2500 | 物攻 27 / 魔攻 29，鬼剑士唯一的店货 |
| 29901 / 31301 / 33601 / 35002 / 37003 | 各职业 Lv3 武器 | 2100 | 非鬼剑士，切片只留数据不启用 |

---

## 5. 副本 × 3

### 5.1 `[greed]` 解码（先把规则说清）

`[size] cols rows`；`[greed]` 有 rows 行，每行 ASCII，**每格 2 字符** = 一个出口位掩码 token（`BB`=右连、`EE`=左连…）。切片用到的 15 个 token：

`BB` 右 · `EE` 左 · `CC` 上 · `II` 下 · `FF` 左右 · `KK` 上下 · `PP` 十字 · `DD` 右上 · `GG` 左上 · `JJ` 右下 · `MM` 左下 · `HH` 左上右 · `LL` 上下右 · `NN` 左下右 · `AA` 无法通过

> 🔴 **红线（错了会让整张图 0 命中）**：**地图加载 = `map/map.lst` 的 `id → path` 表**。`.dgn` 里 `[map specification]` / `[start map]` / `[boss map]` 写的**全是数字 id，不是文件名**；这些 id 在目录下常常**没有同名文件**（`sunderlandpoison/` 下没有 `852.map`，852 是 `e817(1,2).map`）。任何「`id.map` 拼路径」的写法都是错的。

坐标 `(x, y)` 从 0 起，x 向右、y 向下。已在全部 625 个 `.dgn` 上验证双向连通性（621 自洽）。

**房间分配的「三级回退」（M3 必须实现，按序尝试，命中即停）**：

1. **`[map specification]`**：该格有 `X Y mapId…` 条目 → 从候选里随机取 1 个；
2. **`.map` 文件名里的 `(col,row)`**：act1 后期副本的房间文件名自带网格坐标（如 `map/sunderlandpoison/e817(1,2).map`）→ 用文件名里的坐标匹配格子（注意：文件名的 row 与 `[greed]` 的 y 可能是**倒序**，取到后要校验连通性）；
3. **按 id 递增**：前两级都没命中 → 把该副本房间池（`.map [dungeon] == 本副本 id` 的集合，用 `/tmp/mapindex.json` 同法可重建）按 id 排序后顺序填格。

> `dungeon/act1/lorien.dgn` **完全没有 `[map specification]`**，只有 `[size] 2 3` + `[greed]` + `[start map]/[boss map]`，是必须走 2/3 级的真实例子；`mirkwooddeep.dgn`（10 条）、`sunderlandpoison.dgn`（8 条）走 1 级。
> **未在 `[map specification]` 里指定的格子，由「迷宫规则」随机选地图——规则不在数据里**（官方 tagdict 原话），所以第 2/3 级本质是我们在补服务端那份缺失的规则。

### 5.2 副本 1 洛蘭（Lv1 入场）

| 项 | 值 |
|---|---|
| `.dgn` | `dungeon/act1/lorien.dgn`（dungeon.lst = **1**） |
| `[size]` | 2 × 3（6 格） |
| `[greed]` | `JJEE` / `LLMM` / `DDGG` |
| `[start map]` | `0 0` `1 0`（两格任选） |
| `[boss map]` | `0 2` `1 2` |
| `[champion]` | `0 0 0 0 0`（不出精英） |
| `[map specification]` | **无** → 全 6 格都要我们按房间池指定（见下） |
| `[pathgate object]` | 361 … 370 |
| `[experience increasing point]` | 10.0 |
| `[special passive object item]` | `0 -1 2 1000 2000 1004 2000` / `1 -1 0`（可破坏物掉 1000、1004 各 2000 权重） |
| `[event monster]` | `1 5000 61726 1 300 80 1`（切片不做，M4 活动怪） |
| 房间池 | 15 间：`s0..s3`(起) `4,6,7,8,9`(普通) `bn10..bn12`(普通) `b1..b3`(boss) |

**切片取 5 间**（保留 start/boss + 3 个普通房的真实怪物布点）：

| 格(x,y) | map id | 路径 | 怪物（id, 等级, x, y, 数量） | 备注 |
|---|---|---|---|---|
| (0,0) | **1** | `map/lorien/s0.map` | 1×3（535,180 / 695,248 / 582,302） | 起始房，`[dungeon start area] 210 308 104 45` |
| (1,0) | **6** | `map/lorien/6.map` | 1×6（479,201 / 874,216 / 402,217 / 1008,260 / 341,266 / 1085,295） | 最密集普通房 |
| (0,1) | **10** | `map/lorien/bn10.map` | 1×6（726,210 / 921,211 / 611,259 / 1073,261 / 1000,290 / 767,337） | |
| (1,1) | **9** | `map/lorien/9.map` | 1×6（350,191 / 577,228 / 714,262 / 355,315 / 688,332 / 480,338） | 该房 6 只的「随机掉落次数」= 0 |
| (0,2) | **13** | `map/lorien/b1.map` | 1×6 + **2×1 [boss]**（1072,267） | `[type] [boss]`，boss = 投擲哥布林 |

### 5.3 副本 2 幽暗密林深處（Lv3 入场，basis 6）

| 项 | 值 |
|---|---|
| `.dgn` | `dungeon/act1/mirkwooddeep.dgn`（**4**） |
| `[size]` | 3 × 4（12 格） |
| `[greed]` | `IIJJEE` / `LLHHMM` / `DDNNGG` / `BBHHEE` |
| `[start map]` | `0 3` `2 3` |
| `[boss map]` | `0 0` `2 0` |
| `[champion]` | `2 4 6 8 10`（普通2% / 冒险4% / 勇士6% / 王者8% / 英雄10% 出精英） |
| `[map specification]` | 10 条：(0,0)→415 413 · (0,1)→409 417 · (0,2)→405 418 · (1,0)→415 413 · (1,1)→411 424 425 · (1,2)→407 420 · (1,3)→406 403 · (2,0)→416 · (2,1)→412 414 · (2,2)→419 408 |
| 房间池 | 63 间（`401..463`，`s401/s404` 起，`b4xx` boss） |

**切片取 6 间**（直接用 `[map specification]` 的首选 id，路径已核实）：

| 格 | map id | 文件 | 怪物构成（实测） | 数量 |
|---|---|---|---|---|
| (0,3) 起 | **403** | `map/mirkwooddeep/403.map` | id6×2 + id1×5 + id5×2 | 9 |
| (1,3) | **406** | `map/mirkwooddeep/406.map` | id4×3 + id5×1 + id6×2（全 lv6） | 6 |
| (1,2) | **407** | `map/mirkwooddeep/407.map` | id5×3 + id6×1 + id2×2(lv4) | 6 |
| (2,1) | **412** | `map/mirkwooddeep/412.map` | id3×6 + id5×2 | 8 |
| (1,1) | **411** | `map/mirkwooddeep/411.map` | id3×2 + id5×2 + id6×2 + id2×2 | 8 |
| (0,0) boss | **b4xx** | `map/mirkwooddeep/b413.map`（`[type][boss]`） | 5001×7 + id3/4/5/6 若干 + **5002×1 `[boss]`**（指定掉落次数 2） | 13 |

> 注意：`[boss map]` 给的是**网格坐标对**（这里是 `0 0` / `2 0` 两格），不是 map id。这两格要放 boss 房（`b4xx` 系列），不是 `[map specification]` 里那个候选 id。这是 `.dgn` 最容易踩的一处。
> **如果某格在 `[map specification]` 里没有条目、或候选里根本没有 boss 房**（`dungeon/act1/lorien.dgn` 就是完全没 spec 的例子），按 §5.1 的**三级回退**取房；此时 **boss 实体 = 该房里 `[monster]` 最强的那只**（不看 `[type]`）。dgn6 的 boss 候选格（(2,0) 四选 + (4,1)=877）**全部标 `[type][normal]`**，落到哪格 boss 就是哪格房内最强的怪 —— 例如 877 = tau `12` + lugaru 精英，827 = 全员 lugaru 精英（见 §5.4）。

### 5.4 副本 3 猛毒雷鳴廢墟（Lv7 入场，basis 10）

| 项 | 值 |
|---|---|
| `.dgn` | `dungeon/act1/sunderlandpoison.dgn`（**6**） |
| `[size]` | 5 × 2（10 格） |
| `[greed]` | `BBMMBBNNMM` / `AADDFFGGCC` |
| `[start map]` | `0 0` |
| `[boss map]` | `2 0` `4 1` |
| `[champion]` | `3 6 9 12 14` |
| `[map specification]` | 8 条：(1,0)→852 856 861 · (1,1)→862 863 840 · (2,0)→827 853 859 860 · (2,1)→845 854 865 864 · (3,0)→828 872 873 837 · (3,1)→867 866 · (4,0)→876 875 · (4,1)→877 |
| 房间池 | 80 间（`801..880`） |
| 怪物 | 普通 id {3,6,8,12,5001,5002,5003}；boss **5004 毒貓王**（`[level] 13 19`，`[item] 3069 2500 1013 200 1047 200 1065 100`） |

**切片取 5 格**（⭐ 全部经 `map/map.lst` 反查，**不是文件名**；`[start map]` 只给 (0,0)，spec 里也没有 (0,0)/(0,1) 两格 → 走 §5.1 三级回退）：

| 格 | map id | 文件（= lst 反查结果） | 怪物构成（实测） | 精英数 |
|---|---|---|---|---|
| (0,0) 起 | **801** | `sunderlandpoison/s801.map` | id3×3 + 5001×2 + id8×1 + 5002×1 | 3 |
| (1,0) | **852** | `sunderlandpoison/e817(1,2).map` | id3×4 + id6×2 + id8×2 | 0 |
| (2,1) | **859** | `sunderlandpoison/n809(2,1).map` | id8×4 + 5003×2 + 5002×2 | 4 |
| (3,0) | **872** | `sunderlandpoison/h825(3,2).map` | 5002×3 + 5003×2 + 5001×1 + id8×1 + id6×1 | 6 |
| **(4,1) boss** | **877** | `sunderlandpoison/h832(4,3).map` | id8×4 + 5001×2 + 5003×1 + 5002×1 + **id12×1** | 4 + tau |

> **8 格完整候选（`[map specification]` 原文，数字全部走 `map.lst`）**：
> (1,0)=852/856/861 · (1,1)=862/863/840 · (2,0)=**827/853/859/860** · (2,1)=845/854/865/864 · (3,0)=828/872/873/837 · (3,1)=867/866 · (4,0)=876/875 · (4,1)=**877**。
> `[boss map] 2 0 4 1` → boss 候选 = {827, 853, 859, 860} ∪ {877}。**这五格的怪构成完全不同**，按「boss = 房内最强」实测：精英怪（5001/5002/5003）数量 **827=8 · 859=4 · 877=4 · 860=1 · 853=0**；`12` 牛頭巨獸在 **853/860/877** 都有（不是 877 独有）。→ **要 tau 当 boss 选 877**（唯一 tau 与 lugaru 混编），**要满编精英选 827**（全员 lugaru 精英，含 0 只哥布林）。**不要按 `[type]` 筛**（这 5 格全标 `[normal]`）。
> `b801/b802/b813(5,1)/b827(2,2)/b831(4,3)` 这 5 个 `b*` 房里的 **5004 毒貓王** 是另一套（`[type][boss]`）命名，**不在 `[map specification]` 的候选里**，走 spec 时用不上；只有手工指定 boss 房时才用它。

---

## 6. 怪物表（12 只，含全部 id→路径→数值）

### 6.1 字段口径

`.map [monster]` 每记录 **10 值**：`怪物id, 等级自动指定(0|1), 等级, x, y, z, 随机掉落次数, 指定掉落次数, 复制类型([fixed]), 怪物类型([normal]|[champion]|[boss])`。
等级自动指定 = 1 时，实际等级取该副本的 `[basis level]`；= 0 时用第 3 个值（例：`(3,0,6,…)` = 怪物 3 号，等级 6）。

怪物能力值 = `monster/monsterbaseparameter.tbl` 中 **等级行** × `[ability category]` 的百分比乘数。

- 表形状：**100 行 × 11 列**，**row = level**（col0 恰为 1..100）；`read_File_In_List2` 返回 2 行，row0 全是 `2` 是表头，row1 才是数据。
- 列语义（**已定案，详见 `analysis/10a-MONSTER-STATS.md`**）：`col0=等级`、**`col5=HP`**（实证）、`col7=物攻/魔攻基值`、`col2=物防/魔防基值`、`col8=经验`（=150×等级）、`col1=col3=30 常量`（未知，忽略）。每对(col5/col6、col7/col9…)是同一属性的 min/max 两个席位，**100 行里恒等**，取首席位即可。
- 乘数叠法：**`实际值 = 基表值 × 乘数 / 100`**（实证：`[ability category]` 是 `[KEY] * 数值` 三元组，众数为 100 = ×1）。
- `[ability table] N` 是**选哪张表**（0 基本/1 召唤物/2 竞争地牢，默认 0），**不是选哪一行**；首切片 12 只怪全无该标签，统一读 `monsterbaseparameter.tbl`。
- ⚠️ `.mob` **没有** `[hp max]` 绝对血量字段 —— HP 只能这样算出来。

### 6.2 主表

| id | 名字 | `.mob` 路径 | 乘数（HP/物攻/物防/魔攻/魔防 %） | 等级区间 | 攻击槽（`.atk`） | 掉落 `[item]`(id 权重) |
|---|---|---|---|---|---|---|
| **1** | 哥布林 | `monster/goblin/goblin.mob` | 70/90/90/90/90 | 1–6 | 1 槽：`attackinfo/attack1.atk` | **无** |
| **2** | 投擲哥布林 | `monster/goblin/goblinthrower.mob` | 65/75/80/80/80 | 2–6 | `attack1.atk` + `[throw attack]`→`Particle/ThrowStone.ptl`(passiveobject 30001) | 6003 300 · 1000 50 · 1047 200 · 1004 100；`[common champion drop item] 3171 7000` |
| **3** | 青哥布林 | `monster/goblin/seagab.mob` | 70/70/70/80/100 | 10–15 | `attack1.atk` + `IceMissile.ptl`(30057) | 1062 50 · 1065 100 · 1047 200 |
| **4** | 赤哥布林 | `monster/goblin/hillgab.mob` | 70/…/… | 3–9 | `attack1.atk` | 1062 50 · 1065 100 · 1047 200 |
| **5** | 十夫長 | `monster/goblin/goblintaskmaster.mob` | 70/100/100/… | 7–12 | `attackinfo/attack2.atk` | 1062 50 · 1065 100 · 1047 200 |
| **6** | 投擲十夫長 | `monster/goblin/goblinthrowertaskmaster.mob` | 75/… | 5–10 | `attack1.atk` + throw | 6003 100 · 1062 50 · 1065 100 · 1047 200 |
| **8** | 冰霜哥布林 | `monster/goblin/flagseagab.mob` | 80/… | 8–16 | `attack1.atk` + throw | 1062 50 · 1065 100 · 1047 200 |
| **12** | 牛頭巨獸 | `monster/tau/taubeast.mob` | 175/100/100/80/80 | 4–20 | 3 槽：`AttackInfo/{Beast,Tackle,Roar}.atk` | 1062 50 · 1065 100 · 1047 200 |
| **5001** | 貓妖 | `monster/lugaru/lugaru.mob` | 85/80/80/… | 9–14 | 4 槽：`Attack,JumpAttack1,JumpAttack2,TryBite` | 1062 50 · 1065 100 · 1047 200 |
| **5002** | 暗咒貓妖 | `monster/lugaru/kurogaru.mob` | 100/100/100/90/90 | 19–19 | 4 槽：`*_Curse.atk` | **无**（靠 `.dgn`/任务奖励） |
| **5003** | 螢光貓妖 | `monster/lugaru/sirogaru.mob` | 85/90/80/100/120 | 8–19 | 5 槽（含 `AttackL` 系列） | 1001 50 · 1047 200 · 1065 100 |
| **5004** | 毒貓王（boss） | `monster/lugaru/penril.mob` | 115/110/100/… | 13–19 | 5 槽：`*_Poison.atk` | 3069 **2500** · 1013 200 · 1047 200 · 1065 100 |

### 6.3 AI

`.mob` 里**没有** `[ai pattern]` → 用同目录默认 4 件套，顺序固定：

```
monster/<族>/ai/event.ai  → destinationselect.ai → action.ai → movemethod.ai
```

| 族 | 目录 | 用法 |
|---|---|---|
| goblin | `monster/goblin/ai/` | id 1/2/3/4/5/6/8 共用 |
| tau | `monster/tau/ai/` | id 12 |
| lugaru | `monster/lugaru/ai/` | id 5001/5002/5003/5004 |

`.ai` 是条件树 DSL：`[think]` + `[return] n`（n = `[attack motion]` 的下标）。M3 建议**只实现 3 个原语**：`is target in attack area() x y w h`、`check random() p 100`、`is the skill in cooltime() n`，其余 think 全部跳过（走到下一个）。

### 6.4 怪物攻击数据样例（哥布林，逐字段）

`monster/goblin/attackinfo/attack1.atk`：

```
[attack type] [physic]          物理
[weapon damage apply] 1         吃装备攻击力
[attack enemy] 1                打敌人
[elemental property] [no element]
[damage reaction] [damage]      普通受击（不击倒不浮空）
[push aside] 100                平推 100%  ← 会被推很远
[lift up] 300                   浮空 300%
[hit wav] STAFF_HIT
[attack direction] [hit down]   朝下打
[hit info] [blow] [no blood] 200 1.0
```

**没有 `[damage bonus]` → 伤害比率 = 100%。**

---

## 7. 战斗数值

### 7.1 玩家面板（Lv1–20，含 §3.1 成长）

| Lv | HP | MP | 物攻(角色) | 物防 | 魔攻 | 魔防 |
|---|---|---|---|---|---|---|
| 1 | 180 | 140 | 7.5 | 7.5 | 4.5 | 4.5 |
| 2 | 225 | 165 | 12.3 | 12.3 | 8.7 | 8.7 |
| 5 | 360 | 240 | 26.7 | 26.7 | 21.3 | 21.3 |
| 8 | 495 | 315 | 41.1 | 41.1 | 33.9 | 33.9 |
| 10 | 585 | 365 | 50.7 | 50.7 | 42.3 | 42.3 |
| 12 | 675 | 415 | 60.3 | 60.3 | 50.7 | 50.7 |
| 15 | 810 | 490 | 74.7 | 74.7 | 63.3 | 63.3 |
| 18 | 945 | 565 | 89.1 | 89.1 | 75.9 | 75.9 |
| 20 | 1035 | 615 | 98.7 | 98.7 | 84.3 | 84.3 |

### 7.2 怪物面板（按切片实际等级算）

| 怪物 | 等级 | 基表行 HP | ×乘数 = **实际 HP** | 基表攻击(col7) | ×乘数 = **实际攻击** | 经验(col8) |

> `★` = 该怪的 `[ability category]` 只明确给了 `[HP MAX]`，攻击% 未写 → 按同族默认值取（赤哥布林按 90%、冰霜哥布林按 80%），跑起来偏了改这一个数即可。
|---|---|---|---|---|---|---|
| 哥布林 | 1 | 50 | 50×70% = **35** | 2 | 2×90% = 1.8 | 150 |
| 哥布林 | 4 | 133 | 133×70% = **93** | 17 | 17×90% = 15.3 | 600 |
| 赤哥布林 | 4 | 133 | 133×70% = **93** | 17 | ★17×90% = 15.3 | 600 |
| 投擲哥布林 | 4 | 133 | 133×65% = **86** | 17 | 17×75% = 12.8 | 600 |
| 十夫長 | 7 | 250 | 250×70% = **175** | 32 | 32×100% = 32.0 | 1050 |
| 冰霜哥布林 | 8 | 296 | 296×80% = **237** | 37 | ★37×80% = 29.6 | 1200 |
| 青哥布林 | 10 | 401 | 401×70% = **281** | 47 | 47×70% = 32.9 | 1500 |
| 牛頭巨獸 | 10 | 401 | 401×175% = **702** | 47 | 47×100% = 47.0 | 1500 |
| 貓妖 | 9 | 347 | 347×85% = **295** | 42 | 42×80% = 33.6 | 1350 |
| 螢光貓妖 | 10 | 401 | 401×85% = **341** | 47 | 47×90% = 42.3 | 1500 |
| 暗咒貓妖(boss) | 19 | 1060 | 1060×100% = **1060** | 92 | 92×100% = 92.0 | 2850 |
| 毒貓王(boss) | 15 | 729 | 729×115% = **838** | 72 | 72×110% = 79.2 | 2250 |

> 基表原行（列序：等级,30,?,30,?,HP,HP,攻击,经验,攻击,经验）：
> 第 1 行 `1,30,0,30,0,50,50,2,150,2,150` · 第 4 行 `4,30,17,30,17,133,133,17,600,17,600` · 第 7 行 `7,30,35,30,35,250,250,32,1050,32,1050` · 第 8 行 `8,30,42,30,42,296,296,37,1200,37,1200` · 第 10 行 `10,30,56,30,56,401,401,47,1500,47,1500` · 第 15 行 `15,30,96,30,96,729,729,72,2250,72,2250` · 第 19 行 `19,30,133,30,133,1060,1060,92,2850,92,2850`

### 7.3 技能伤害倍率：从 `[level info]` 取哪几列

`[level info]` 首个值 = **列数 C**，其后 `C × 级数` 行优先铺开。取某一级：`row(level) = data[1 + (level-1)*C : 1 + level*C]`。

| skill | C | Lv1 行（原值） | Lv2 | 取哪列做什么 |
|---|---|---|---|---|
| 46 上挑 | 4 | `120 350 100 30` | `135 367 100 34` | col0=伤害% · col1=浮空力 · col2=? · col3=? |
| 5 鬼斬 | 2 | `260 65` | `292 73` | col0=伤害% · col1=暗属性武器魔攻% |
| 8 三段斬 | 6 | （70 级 × 6 列，3 段 × 2 值） | | col0/1=第1段伤害+浮空 · col2/3=第2段 · col4/5=第3段 |

`[level property]` 才是「这些列叫什么」的唯一出处。上挑的原文：

```
[level property]
  1 99 "物理攻擊力 : <int>%% + <int>\n浮空力比率 : <float1>%%"
  (-1,0,1.0) (-2,3,1.0) (-1,1,0.2857142984867096)
```

读法：三元组 `(来源, 列号, 倍率)`；`来源 -1` = 读 `[level info]` 的该列，`-2` = 直接加常数。`<int>` 按出现顺序取列 0、3，`<float1>` 取列 1。→ **上挑 Lv1 = 物攻×120% + 30，浮空 = 350%×0.2857 = 100%。**

### 7.4 一次完整伤害计算的输入项

```
物理伤害 = max(1, floor(
              ( 角色物攻 + Σ装备[equipment physical attack][0] )   ← A
              × (技能列0 / 100)                                    ← B
              × (1 + [damage bonus] / 100)                         ← C
              × [module damage rate][0]                            ← D
            ) − 怪物物防 )

魔法伤害 = 同一公式，A 换 (角色魔攻 + Σ装备[equipment magical attack][0])，
           D 换 [module damage rate][2]（鬼斬那种 [weapon effect type][magical] 才走这路）
```

| 输入 | 在 PVF 里吗 | 路径 |
|---|---|---|
| A1 角色物攻/魔攻 | ✅ | `swordman.chr [physical attack]` + `[growtype 1]` 增量 |
| A2 装备物攻/魔攻 | ✅ | `.equ [equipment physical attack]` = `[地下城值, PVP值]`，取 [0] |
| B 技能倍率 | ✅ | `.skl [dungeon][level info]` 对应行 `列0/100` |
| C 攻击比率 | ✅ | `.atk [damage bonus]`（0/缺省 = 100%，20 = 120%，-15 = 85%） |
| D 模式倍率 | ✅ | `.chr [module damage rate]`（4 个数，序列含义见 §12-R5） |
| E 怪物物防 | ⚠️ | 基表列 2（Lv1=0 → Lv100=1733），**列语义待验证** |
| F 暴击 | ⚠️ | 本 PVF 无暴击字段，`.atk` 也没有；★M3 不做暴击 |
| G 属性克制 | ⚠️ | `[elemental property]` + 怪物抗性字段存在，但公式不在数据里；★M3 只做「火/冰/暗/光/无」的标签透传，不乘系数 |

**结论**：A–D 全部有据可查，E 靠推断，F/G 必须自己定。M3 建议把 E 写成 `怪物物防 = 基表列2 × 0.5`（先这样拍，跑通再调）。

### 7.5 怪物打玩家

```
怪物伤害 = 基表攻击(col7) × [ability category 的攻击%] × 攻击箱命中
玩家受击 = 怪物伤害 − 玩家物防/2（物防直接减半粗略换算）
```
哥布林 Lv1：`2 × 0.9 = 1.8` → 玩家物防 7.5/2=3.75 → 最小伤害 1。**Lv1 挨打几乎不掉血是符合原作的**（原作 Lv1 哥布林确实挠痒），真正威胁从 Lv4 起（15.3）。

### 7.6 硬直/击退/浮空（`.atk` 三件套）

| 字段 | 哥布林 attack1 | 鬼剑士 dashattackmultihit | 效果 |
|---|---|---|---|
| `[damage reaction]` | `[damage]` | `[damage]` | 受击动画：damage 后退 / down 倒地 / blow 击飞 / stuck 定身 |
| `[attack direction]` | `[hit down]` | `[hit horizon]` | 击倒 / 平推 / 浮空 |
| `[push aside]` | 100 | 250 | 平推速度 % |
| `[lift up]` | 300 | 200 | 浮空高度 % |
| `[knuck back]` | 缺省 | 1 | 1 开 / -1 禁 / >1 加强 |
| `[hit info]` | `[blow] [no blood] 200 1.0` | 同 | 打击类型 + 血效 + 命中停顿 + 受击延迟倍数 |

---

## 8. 掉落与经济

### 8.1 实测结论：act1 不掉装备

- 12 只怪的 `[item]` 全是消耗品/材料（§6.2），一只都不掉 `.equ`。
- `etc/worlddrop.etc [world drop]` 200 行**完全一样**，只给商城道具（31003915 / 490000000 / 10309021）→ 与等级无关，切片不用。
- `etc/independentdrop/*.etc` 共 181 个，命名 `<序号>_<boss>_<难度>.etc`，从 act2 的 magneus 起 → **act1 没有独立掉落表**。

**所以装备来源只有两条**：① 商店（§4.4）② 任务奖励（§9）。这就是切片的经济骨架，也是原作低级的真实体验。

**精英（champion）掉落是另一条独立通道**：`[common champion drop item]`。实测只有投擲哥布林有（`3171 7000` = 爐巖炭，权重 7000）；其余 11 只没有 → 精英怪（champion）死掉时的额外掉落按「怪物自己的 `[common champion drop item]`，没有就只走 `[item]` 表 × `[champion]` 概率」。`[champion]` 在 `.dgn` 里定的是**出现概率**（洛蘭全 0 → 不刷精英；幽暗密林深處 `2 4 6 8 10` → 各难度 2%~10%）。M3 只实现「普通 + boss」，精英开关留着（一个 bool）。

### 8.2 掉落物一览（9 种，全部 stackable）

| id | 名字 | `.stk` 路径 | grade | 价格 | 堆叠 | 图标 |
|---|---|---|---|---|---|---|
| 1000 | 野草莓 | `stackable/food_strawberry.stk` | 2 | 100 | 1000 | `Item/IconStackable.img 0` |
| 1001 | 烤硬的黑面包 | `stackable/food_rhybread.stk` | 10 | 400 | 1000 | `Item/IconStackable.img 1` |
| 1004 | 苧麻花葉 | `stackable/plant_lamihwaleaf.stk` | 3 | 150 | 1000 | `Item/IconStackable.img 4` |
| 1013 | 肉干 | `stackable/food_driedmeat.stk` | 13 | 390 | 1000 | `Item/IconStackable.img 14` |
| 1047 | 命運硬幣 | `stackable/ftcoin.stk` | 1 | 10 | 1000 | `Item/stackable/consumption.img 0` |
| 1062 | 越桔 | `stackable/food_blueberry.stk` | 6 | 240 | 1000 | `Item/stackable/consumption.img 4` |
| 1065 | 魔力之花 | `stackable/flower_magical.stk` | 7 | 280 | 1000 | `Item/stackable/consumption.img 7` |
| 3069 | 毒貓王的毒牙 | `stackable/material/tooth_poison.stk` | 10 | 300 | — | `Item/IconMaterial2.img 38` |
| 3171 | 爐巖炭 | `stackable/material/ryan_cokes.stk` | 1 | 10 | — | `Item/stackable/material.img 48` |
| 6003 | 石頭 | `stackable/throw/stone1.stk` | 1 | 10 | — | `Item/IconMaterial.img 39` |

### 8.3 金币量级

- 卖店价 = `.equ/.stk [price]`，`[value]` 只有 1/5 → **卖价 ≈ price/5**（五折以下，具体系数见 `05-item.md`）。
- 一趟洛蘭（5 房 ≈ 21 只怪）期望：goblin 只掉 1000/1047/1004 各 50~200 权重 → ★按权重归一后约 1.5 件/只 → 收入 ≈ `1.5 × (150..400)/5 ≈ 100~160 金币`。
- 任务 102 给 200 金币，103 给 200 金币 → 主线前 3 环 = 500 金币，够买 1 瓶入门 HP 药（200）+ 一半张券。
- ★设计校准：让 Lv1–20 全部收入 ≈ 6,000 金币，恰好买齐 §8.4 的 5 件太刀（22,600）+ 3 件上衣（5,800）明显不够 → **必须保留「卖掉打到的材料 + 任务奖励」两条腿**，这也是原作的节奏。

### 8.4 切片装备（10 件）

**太刀线**（`[equipment physical attack]` = `[地下城, PVP]`）：

| id | 名字 | `.equ` 路径 | Lv | grade | rarity | 物攻 | 魔攻 | 价格 | 来源 |
|---|---|---|---|---|---|---|---|---|---|
| 27600 | 破損的武士刀 | `character/swordman/weapon/katana/kat_damaged.equ` | 1 | 1 | 0 | 22 | 24 | 700 | ★初始装备（M3） |
| 27601 | （乱码，建议改叫「旧太刀」） | `…/katana/kat_worn.equ` | 3 | 3 | 0 | 27 | 29 | 2500 | 商店 `EquipmentShop1.shp`（M3 真数据） |
| 27602 | 武士刀 | `…/katana/kat.equ` | 5 | 5 | 1 | 49 | 55 | 5000 | ★M3 加进商店第二页（原表没有，但价格/等级与 27601 连续） |
| 27606 | 鋒利的小太刀 | `…/katana/kat_hkotachi.equ` | 8 | 8 | 1 | 72 | 80 | 8000 | ★M4 · 任务 105 奖励 |
| 27611 | 枯葉刀 | `…/katana/kat_kogaras.equ` | 15 | 15 | 1 | 125 | 139 | 15000 | ★M4 · 任务 106 奖励 |

**防具线**（`equipment/character/common/`）：

| id | 名字 | 路径 | Lv | 物防 | 价格 |
|---|---|---|---|---|---|
| 10000 | 粗布襯衫 | `jacket/cloth/sht_ragcloth.equ` | 1 | 11 | 400 |
| 10001 | 殘破的粗布襯衫 | `jacket/cloth/sht_tatcloth.equ` | 3 | 24 | 1200 |
| 10002 | 破舊的棉布襯衫 | `jacket/cloth/sht_sbcloth.equ` | 5 | 48 | 2000 |
| **16400** | 殘破的牛皮腰帶 | `belt/leather/str_crleather.equ` | 1 | 0 | 200 | ← 任务 102 奖励（真实） |
| **12401** | 磨損的牛皮短褲 | `pants/leather/pant_wleather.equ` | 3 | 0 | 1200 | ← 支线奖励（真实） |

图标：太刀 `Item/weapon/swordman/katana.img`，上衣 `Item/IconArmor.img 0/1`，腰带 `Item/IconArmor.img`（需按 `.equ [icon]` 的 img+idx 取帧）。

### 8.5 强化/修理：**不进切片**

理由：`etc/upgrade.etc` 的 `[table]` 是 50 级 × 5 概率的长表，`[destroy level by rarity] common 10`（+10 起会碎），还牵扯 `[disjoint]` 分解、`[correction grade by rarity]` 等 7 个子系统。切片里装备 5 级一换，强化收益根本体现不出来。**M3 只保留「耐久度扣减 + 铁匠修理」**（`[durability] 45` → 0 时攻击力打八折，修理价格 = `[repair price]`），够用且便宜。

---

## 9. 任务（主线 4 环 + 支线 1 条，含任务道具链）

### 9.0 先看章节结构：`n_quest/epicquest.lst`（**不是 id→路径表**）

`export/text/n_quest/epicquest.lst.txt`（35KB）是套了 `.lst` 后缀的**标签流配置**，给出「章节 → 有序任务 id 列表」：

```
[episode]
    [episode_name]  1 6 開始冒險
    [epic_index]    101 102 103 4301 104 105 106 107 108 4302
    [complete_text] 被譽為"精靈圣地"的格蘭之森，在大火吞陷前是精靈的樂園……
[episode]-1
    7 10  [episode_name] 怪獸獵殺者  [epic_index] 109 115 111  [complete_text] ……
```

→ **第一章（Lv1–6）的官方推荐顺序就是 `101 102 103 4301 104 105 106 107 108 4302`**，本章完成文本也点明了「格兰之森」。这就是为什么下方主线选 101→102→103：**它们不只是 id 连续，是同一章节的前三环**。
（`4301/4302` 是章节内的插入节点，本 PVF 里查不到独立 `.qst`，疑为服务端/活动占位 —— §12-R12。）

同目录另有 `trainingquest.lst`（教学任务，同结构）、`dailyrandomquest.lst`（`[group]` → 每日随机任务 id）。

**任务 0（教程）**：`n_quest/elvengard/lorien/sq.qst` — 與賽麗亞的初次見面，`[event] 1`、`[meet npc]`、`[int data] 2`、`[reward int data] 200106172 1 491711473 1`（两件新手礼包道具）。M3 用它当「进游戏第一句话」。

### 9.1 主线（官方 act1 真实链，id 连续）

| id | 名字 | `.qst` 路径 | 品级 | 难度 | 类型 | `[int data]` | 前置 | 奖励 |
|---|---|---|---|---|---|---|---|---|
| **101** | 鐵匠林納斯 | `n_quest/elvengard/lorien/epic_1_lorien_1.qst` | `[epic]` | O | `[meet npc]` | `1`（去和 NPC 1 对话） | 无 | `[reward int data] 0 100` = 100 金币 |
| **102** | 開始冒險 | `n_quest/elvengard/lorien/epic_1_lorien_2.qst` | `[epic]` | W | `[condition under clear]` + `[sub type] 6`（直接通关） | `1 -1`（副本1 洛蘭，全难度） | 101 | `0 200 16400 1` = 200 金币 + **殘破的牛皮腰帶 ×1** |
| **103** | 噪音公害 | `n_quest/elvengard/lorieninside/epic_2_lorieninside_3.qst` | `[epic]` | X | `[hunt monster]` | `2 -1 1 10`（副本2 全难度 · 怪物1 号 · 10 只） | 102 | `0 200 1106 5 1112 5` = 200 金币 + HP药×5 + MP药×5 |
| 104 | 與賽麗亞的緣分 | `n_quest/elvengard/lorieninside/epic_2_lorieninside_4.qst` | `[epic]` | O | `[meet npc]` `2` | 2 | 103 | 100 金币 |
| 105 / 106 / 107 / 108 | ★（章节 1 的后续 4 环，id 由 `epicquest.lst` 给出，本 PVF 的 `.qst` 文件不在 `n_quest/elvengard/` 下，需按 `quest.lst` 反查） | — | — | — | — | — | 104 | — |

> 切片 M3 **只做 101→102→103→104 四环**；105–108 留给 M4，届时有 §8.4 里 `27606`/`27611` 两件太刀的奖励落点。

**任务链形态**：接任务 → 去对话 → 通关副本 → 杀 N 只怪 → 回城交任务。103 的「副本 2 杀 10 只 1 号怪」是全链唯一的战斗目标，**M3 必须让「通关」和「杀怪」两种计数都工作**。

### 9.2 支线：赛丽亚的戒指（**任务道具掉落链就在这里**）

`n_quest/elvengard/lorieninside/normal_2_lorieninside_seria_ring.qst`

```
[grade] [common unique]      [difficulty] C      [gold multiple] 50
[npc index] 1                [complete npc index] 2
[level] 2 120                [pre required quest] 102
[clear reward item] 2 -1 3087 1 100 1     ← 关键
[type] [seeking]  [sub type] -1
[int data] 3087 1                          ← 需要「賽麗亞的戒指」×1
[reward type] [item]
[reward int data] 1001 1 1004 2 12401 1    ← 烤硬的黑面包1 + 苧麻花葉2 + 磨損的牛皮短褲1
```

`[clear reward item]` 官方语义：**6 值一组 = 副本编号, 副本难度(-1=全), 物品编号, 最大数量, 出现概率(%), 最大拥有数量(-1=无限制)**。
→ 通关洛蘭深處（副本 2，任意难度）时，**100% 掉 1 个 3087 賽麗亞的戒指**（1 = 100%）。

`3087` = `stackable/material/seria_ring.stk`，`[stackable type] [quest] 0`，rarity 3，`[attach type] [trade]`。

**这条链必须做**：它是「打怪/通关 → 掉任务道具 → 交任务」的唯一数据驱动范例，而且 `[clear reward item]` 的 6 元组格式在 8 种任务类型里最容易被误判。

### 9.3 任务经济（`n_quest/questparameter.etc`）

- `[difficulty]` 字符 → 百分比：`S 115 A 90 B 70 C 50 M 10 Z 400 Y 370 X 340 W 300 O 10 E 40 F 60 G 80 D 200 U 250`（15 对）。
  → 101 的 `O`(10) 给 100 金；102 的 `W`(300) 给 200 金；103 的 `X`(340) 给 200 金。**金币 = 等级基数 × 难度% × `[gold multiple]`%**。
- `[exp reward table]` / `[gold reward table]` 各 200 项（按等级取行）。
- `[green level penalty] 80` / `[grey level penalty] 30`（低等级打高等级图的惩罚阈值）。
- `[ignore quest level 4 exp] 1` → 经验跟**角色**等级走（否则跟任务等级）。

⚠️ exp/gold 基数表**非严格单调**（第 24/40/44 项比前一项小），「1 基索引」未闭合 → **不要照抄数值**，M3 用自己的经验曲线（§9.4）。

### 9.4 ★M3 自定经验曲线

`character/exptable.tbl` 实测开头：`1000, 2653, 5543, 10575, 18509, 30205, 46627, 68840`（Lv1→2 需要 1000）。照抄会让 Lv1 打 7 只哥布林就升级（150 exp × 7），节奏太快。

★建议：**每级经验 = `exptable[level] × 3`**，即 Lv1→2 = 3000 exp ≈ 20 只哥布林（150/只）或「打完一趟洛蘭 + 交任务 102」。这样 1→20 大约 25~30 趟副本，符合切片体量。

---

## 10. 明确不做（切片范围外，容易手滑带进来）

| 系统 | 为什么容易误入 | 处理 |
|---|---|---|
| 时装 / 装扮（avatar） | `equipment/character/swordman/avatar/` 有全套 + `characteretc` 的 11 槽 `[equipment index]` | 数据保留不实现；`.lay` 的 `[layer variation]` 只认武器 |
| 转职 / 觉醒 | `.skl [growtype maximum level]` 里 index 1–5 全是转职后的技能 | 切片只让 growtype 0 的技能可学 |
| 宠物（`.cre`） | `creature/` 566 个，`[skill node]` 自带 `.skl+.atk+.ani` | 完全不做 |
| 唯一兽 | 数据层与普通宠物同构（唯一性在服务端） | 完全不做 |
| 副职业（分解/制作/炼金/化学） | `swordman.chr [skill]` **白送了 4 个副职业技能**（181/182/184/179） | 学到但灰掉，不做合成 |
| 强化 / 增幅 / 锻造 | `etc/{upgrade,amplifyupgrade,upgrade_separate}.etc` 三张表 | 见 §8.5，只留修理 |
| 设计图（recipe） | `.stk [stackable type][recipe]` + `[int data]` 材料编码 | 不做 |
| 分解（disjoint） | `upgrade.etc [disjoint]` | 不做 |
| PVP / 战场 / 死亡之塔 | `.atk` 有 `[pvp]` 覆盖块，`.skl` 有 `[pvp]/[death tower]/[warroom]` 分支 | 只在解析器里**兼容这些键**，不实现玩法 |
| 公会 / 商城 / 活动（`.evt`） | `event/*.evt` 82 个 | 完全不做 |
| 史诗图鉴 / 称号簿 | `.qst [reward type] [title]` | 不做，`[title]` 类型直接当非法值跳过 |
| 疲劳值 | `.dgn [no fatigue]` 字段存在 | 不做体力系统 |
| 深渊 / 地狱难度 | `.dgn [hell dungeon]`、`Lorien.wdm [hell dungeon] 1` | 读进来但只跑 normal |
| 联机 | 用户要求留接口 | **只留**：`DamageEvent` 用结构体、状态机输入走 `InputCommand` 队列、随机数走可注入 RNG。不写网络代码 |

---

## 11. 实现顺序（10 步，按依赖排）

| # | 步骤 | 依赖 | 验收 |
|---|---|---|---|
| 1 | **数据解析层**：PVF 标签流 → JSON（绕过 `maxSegNum=50/depth=4` 截断）；产出 `swordman.chr / *.skl / *.atk / *.mob / *.map / *.dgn / *.equ / *.stk` 的结构化 JSON | — | 随便抽 10 个 id，字段与 `export/text/` 原文逐字一致 |
| 2 | **表驱动装配**：`monsterbaseparameter.tbl`(100×11) + `exptable.tbl` + `sptable.etc` 读成 Godot `Resource` | 1 | Lv1 哥布林 HP = 35（50×70%），Lv20 玩家 HP = 1035 |
| 3 | **战斗核心**：`DamageEvent` 走 §7.4 公式；`.atk` 的 push/lift/reaction 三件套驱动受击状态 | 2 | 上挑把哥布林打浮空；鬼斬走魔法分支 |
| 4 | **玩家状态机**：idle/walk/dash/jump/attack×3/jumpattack/damage/down/getup/skill；帧事件表驱动 hitbox 开关 | 3 | 8 个基础动作全通，`.ani` 帧数对齐 |
| 5 | **6 个技能**：SkillDef 表 + 状态注册（§3.4） | 4 | 6 个技能都能打出伤害且 CD/MP 生效 |
| 6 | **怪物**：12 只 `.mob` + 4 件套 `.ai` 的 3 原语 + `.act` 帧触发 | 3 | 哥布林会追人、进攻击范围就 `[return]` 对应 attack motion |
| 7 | **房间与副本**：`.map` → 房间（tile 通行网格 + `[monster]` 10 值布点 + `[pathgate pos]` 门）；`.dgn` → `[greed]` 图 + 我们显式给的 `[map specification]` | 6 | 3 个副本各能走完 start→boss，房间连接与 `[greed]` 一致 |
| 8 | **城镇 + NPC 交互**：`new_Elvengard.map` 主街 + 林納斯（商店/学技能）+ 賽麗亞（任务） | 7 | 能买 27601、能学上挑、能接 101 |
| 9 | **掉落 + 背包 + 装备穿脱**：`[item]` 权重表 + 堆叠 + 5 槽装备（武器/上衣/下装/腰带/鞋） | 8 | 打 20 只哥布林能捡到 4 种消耗品；穿上 27601 后物攻 +27 |
| 10 | **任务系统**：8 种 `[type]` 里只实现 4 种（meet npc / condition under clear / hunt monster / seeking）+ `[clear reward item]` | 9 | 101→102→103→104 全通，支线的戒指 100% 掉 |

> 第 1 步是**唯一的硬骨头**（`docs/PVF-FORMAT.md` + `analysis/09-script-mechanics.md` 已铺好）。第 4 步要碰 `.ani` 二进制（P0.5 未完成 → 见 §12-R1）。

---

## 12. 风险与未知

| # | 风险 | 影响 | 建议口径 |
|---|---|---|---|
| **R1** | `.ani` 二进制格式未解（P0.5 未完成） | 所有动作帧数/攻击盒坐标拿不到 | 先用 `export/text/**/*.ani.bin` 头部已知的 img 路径 + 猜测的盒矩形（tag `0x0e` + 4×int32）做**手填帧表**；或退一步用「固定 4 帧 × 固定盒」占位，把 `.ani` 解码放到 M4 |
| **R2** | **已降级/基本定案**，见 `analysis/10a-MONSTER-STATS.md`：`col5=HP`（实证·排除法）、`col7=攻击`（推断强）、`col2=防御`（推断中）、`col8=经验`（推断强，=150×级）、`col1/col3=30`（未知·忽略）；乘数 = `×v/100`（实证，众数 100）。用户已定调「可玩性优先，随便调」 | 只剩「防御如何进公式」真未知 | 直接抄 10a §4 的查找函数 + §8 的 Lv1–20 粗表；防御进公式的方式自定，Lv1 防御基值=0 所以首刀不受影响 |
| **R3** | 伤害公式的防御项（减法 vs 百分比）在数据里没有 | 数值手感 | ★用 `伤害 − 怪物物防×0.5`，把 0.5 提成配置 |
| **R4** | `.chr [growtype 1]/[growtype 2]` 与「转职序号」的严格对应未验证（官方 growtype 序：0 男鬼剑 / 1 剑魂 / 2 鬼泣 / 3 狂战士 / 4 阿修罗 / 5 第五） | 切片只用基础块，影响小 | 切片用 `[growtype 1]` 的增量（+45HP/+4.8物攻）当**基础成长**，M4 转职时再逐块验证 |
| **R5** | `[module damage rate]` 4 列的序列含义（PVP/战场/混沌/？） | 切片单机只走地下城 | ★取 `[0]`（0.95）当全局倍率，其余忽略 |
| **R6** | 技能 `[level info]` 的列语义只对 3 个技能验证过（上挑 4 列 / 鬼斬 2 列 / 三段斬 6 列） | 其余 17 个技能的「哪列是伤害」不确定 | 逐个用 `[level property]` 的占位符反推（这是**唯一**权威），推不出就★按 col0 当伤害% |
| **R7** | `[dungeon]` 分支缺失（如 17 空中連斬没有 `[consume MP]`） | 少数技能无法照抄数值 | ★填自定值（见 §3.2 注） |
| **R8** | 任务 exp/gold 基数表非单调，索引基准未闭合 | 升级/金币节奏 | ★直接用 §9.4 自定曲线，不照抄 |
| **R9** | act1 没有独立掉落表 → 装备只能靠商店/任务 | 玩法循环只有「打材料卖钱 + 交任务」 | 这是**原作真实设计**，不是缺陷；如果 M3 手感太贫，★允许给 boss 加一张手工掉落表（3~5 个 id），但要标注「非 PVF 口径」 |
| **R10** | 部分 `.equ` 名字在本 PVF 里是乱码（如 27601、27001） | 界面显示 | 用 `localization/*.chn.str` 或 `equipment.chn.str` 复原；找不到就★用「旧太刀」之类占位名 |
| **R11** | 玩家技能 0 个 `.act`，全靠 Squirrel | 引擎必须自建技能状态机 | 已定：不还原 Squirrel，用 `SkillDef` 表（§3.3） |
| **R12** | `epicquest.lst` 第一章的 `4301` / `4302` 在本 PVF 里没有对应 `.qst` 文件；`105`–`108` 的 `.qst` 也不在 `n_quest/elvengard/` 下 | 章节线不完整 | M3 只做 101–104（4 环已够演完「进城→通关→杀怪→告别」），4301/4302 当不存在 |
| **R13** | **已定案（口径推翻旧版）**：dgn6 `[boss map] 2 0 4 1` → boss 候选 = (2,0) 四选 **{827,853,859,860}** ∪ (4,1) **{877}**，**全部 `[type][normal]`**，`[map name]` 都是占位 `PVP無名`；dgn1 的 `4..9.map` 同样。（注：原始用例里曾把 (2,1)(4,0) 的候选也算进来凑成 11 个，实际只有这 5 个。）全库 `[type][boss]` 仅 684 个且全在 act2 之后 | 若按 `[type]` 找 boss 会永远找不到 | **四条口径**：① 房间集合 = `[map specification]` 每格候选随机取一；② **boss 房 = `[boss map]` 的坐标对（2 个格子，不是 1 个），不要按 `[type]` 筛**；③ **boss 实体 = 该房 `[monster]` 里最强的那只**（dgn6：要 tau `12` 就选 877，要满编精英就选 827）；④ act1 的 `[type][boss]` 与 `[map name]` 是遗留占位，**不承载玩法语义**（act2+ 才好用） |

---

## 13. 抽验索引（22 个 id，抽查用）

| id | 类型 | 落到哪 | 关键字段 |
|---|---|---|---|
| 1（dgn） | 副本 | `export/text/dungeon/act1/lorien.dgn.txt` | `[size] 2 3`、`[greed] JJEE/LLMM/DDGG`、`[boss map] 0 2 1 2`、无 `[map specification]` |
| 1（mob） | 怪物 | `export/text/monster/goblin/goblin.mob.txt` | `[ability category] [HP MAX]*70`、`[level] 1 6`、`[attack info] AttackInfo/Attack1.atk` |
| 1（npc） | NPC | `export/text/npc/1_new/linus.npc.txt` | `[role] [item shop] 2`、`[skill] [swordman] 1 5 28 8 11 16 20 25 46` |
| 1（town） | 城镇 | `export/text/town/1_new/new_Elvengard.twn.txt` | `[area] 0 …new_Elvengard.map [normal]` |
| 2（mob） | 怪物 | `export/text/monster/goblin/goblinthrower.mob.txt` | `[item] 6003 300 1000 50 1047 200 1004 100`、`[throw attack]` |
| 2（npc） | NPC | `export/text/npc/Seria.npc.txt` | `[role] [item shop] 15`、`[quest speech]` |
| 5（skl） | 技能 | `export/text/skill/swordman/hardattack.skl.txt` | `[required level] 1`、`[purchase cost] 15`、`[command] (UP) & (SKILL)`、`[weapon effect type][magical]` |
| 6（dgn） | 副本 | `export/text/dungeon/act1/sunderlandpoison.dgn.txt` | `[size] 5 2`、`[boss map] 2 0 4 1`、8 条 `[map specification]` |
| 8（skl） | 技能 | `export/text/skill/swordman/tripleslash.skl.txt` | `[required level] 15`、`[level info]` 长度 421（C=6） |
| 46（skl） | 技能 | `export/text/skill/swordman/upperslash.skl.txt` | `[level property] 1 99 "物理攻擊力 : <int>%% + <int>\n浮空力比率 : <float1>%%"` |
| 101（qst） | 任务 | `export/text/n_quest/elvengard/lorien/epic_1_lorien_1.qst.txt` | `[grade][epic]`、`[type][meet npc]`、`[int data] 1`、`[reward int data] 0 100` |
| 103（qst） | 任务 | `export/text/n_quest/elvengard/lorieninside/epic_2_lorieninside_3.qst.txt` | `[type][hunt monster]`、`[int data] 2 -1 1 10`、`[pre required quest] 102` |
| 3087（stk） | 任务道具 | `export/text/stackable/material/seria_ring.stk.txt` | `[stackable type][quest] 0`、`[rarity] 3` |
| 10000（equ） | 装备 | `export/text/equipment/character/common/jacket/cloth/sht_ragcloth.equ.txt` | `[equipment physical defense] 11 11`、`[equipment type][coat] 14` |
| 16400（equ） | 装备 | `export/text/equipment/character/common/belt/leather/str_crleather.equ.txt` | `[equipment type][waist] 12`、`[price] 200` |
| 27600（equ） | 装备 | `export/text/equipment/character/swordman/weapon/katana/kat_damaged.equ.txt` | `[equipment physical attack] 22 22`、`[minimum level] 1` |
| 27611（equ） | 装备 | `export/text/equipment/character/swordman/weapon/katana/kat_kogaras.equ.txt` | `[equipment physical attack] 125 125`、`[grade] 15` |
| 5004（mob） | 怪物 | `export/text/monster/lugaru/penril.mob.txt` | `[ability category][HP MAX]*115`、`[level] 13 19`、5 个 `*_Poison.atk` |
| 403（map） | 房间 | `export/text/map/mirkwooddeep/403.map.txt` | `[dungeon] 4`、`[monster]` 9 只 = id6×2+id1×5+id5×2 |
| 4301（epic） | 章节节点 | `export/text/n_quest/epicquest.lst.txt` 第一章 `[epic_index]` | 无独立 `.qst`（§12-R12） |
| 852（map） | 房间 | `export/text/map/sunderlandpoison/e817(1,2).map.txt` | `[dungeon] 6`、`[type][normal]`、`[monster]` 10 值组（id3×4+id8×2+id6×2） |
| 1106（stk） | 消耗品 | `export/text/stackable/ptn_hplowest.stk.txt` | `[price] 100`、`[stack limit] 1000` |

---

## 附：与其它文档的接缝

- 字段级语义 → `05-item.md`（.equ/.stk）、`06-monster.md`（.mob/.ai）、`07-map.md`（.map/.dgn/.til）、`08-quest.md`（.qst）、`03-skill.md`（.skl）、`04-combat.md`（.atk/.ani）
- 脚本与 UI → `09-script-mechanics.md`（.act/.nut/.ui/.als）
- 数据坑 → `docs/PVF-FORMAT.md`，特别是 `pvfReader.py:659` 的 `maxSegNum=50 / depth=4` 截断
