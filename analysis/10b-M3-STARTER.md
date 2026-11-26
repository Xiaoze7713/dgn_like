# 10b · M3 开工单（一页版）

> 用途：实现组照这张单子开工，**不用再翻 02–10a**。凡标 `自定` 的数字都可随手改，改了不用回来问。
> 上游依据：`analysis/10-SLICE.md`（内容集与 id）、`analysis/10a-MONSTER-STATS.md`（怪物数值列）、`analysis/12-SLICE-VERIFY.md`（12/12 抽验）。

## 1. id 清单（全部已核实在 `export/text/` 下存在）

| 类别 | id | PVF 路径 |
|---|---|---|
| 职业 | 鬼剑士 | `character/swordman/swordman.chr` |
| 经验表 | — | `character/exptable.tbl`（115 级） |
| SP 表 | — | `etc/sptable.etc` |
| 城镇 | 1 | `town/1_new/new_Elvengard.twn` → `1_new/Cataclysm/Town/Elvengard/new_Elvengard.map` |
| 世界地图 | 1 | `worldmap/Lorien.wdm`（`[dungeon] 1 -1 2 -1 …` = 副本id+前置任务） |
| NPC | 1 / 592 / 603 | `npc/1_new/linus.npc`（鐵匠·商店) · `npc/1_new/592_tobi.npc` · `npc/1_new/603_beatrice_arad.npc` |
| 商店 | 2 | `itemshop/EquipmentShop1.shp` |
| 副本 1 | 1 | `dungeon/act1/lorien.dgn`（2×3，无 map spec） |
| 副本 2 | 4 | `dungeon/act1/mirkwooddeep.dgn`（3×4，10 条 spec） |
| 副本 3 | 6 | `dungeon/act1/sunderlandpoison.dgn`（5×2，8 条 spec） |
| 房间 | 1 / 6 / 10 / 9 / 13 | `map/lorien/{s0,6,bn10,9,b1}.map` |
| 房间 | 403 / 406 / 407 / 411 / 412 / 427(`b413.map`) | `map/mirkwooddeep/*.map` |
| 房间（dgn6 八格） | (1,0)=852/856/861 · (1,1)=862/863/840 · (2,0)=**827/853/859/860** · (2,1)=845/854/865/864 · (3,0)=828/872/873/837 · (3,1)=867/866 · (4,0)=876/875 · (4,1)=**877** | 一律经 `map/map.lst` 反查：852→`e817(1,2)` · 853→`n802(1,0)` · 859→`n809(2,1)` · 860→`n816(0,2)` · 877→`h832(4,3)` · 872→`h825(3,2)` · 876→`h830(4,2)`（均在 `map/sunderlandpoison/`） |
| 怪物 | 1 / 2 / 3 / 4 / 5 / 6 / 8 | `monster/goblin/{goblin,goblinthrower,seagab,hillgab,goblintaskmaster,goblinthrowertaskmaster,flagseagab}.mob` |
| 怪物 | 12 | `monster/tau/taubeast.mob`（牛頭巨獸） |
| 怪物 | 5001 / 5002 / 5003 / 5004 | `monster/lugaru/{lugaru,kurogaru,sirogaru,penril}.mob` |
| 怪物基表 | — | `monster/monsterbaseparameter.tbl`（100级×11列，col5=HP/col7=攻击/col2=防御） |
| 技能 | 46 / 5 / 8 / 11 / 16 / 25 | `skill/swordman/{UpperSlash,HardAttack,TripleSlash,DashAttackMultiHit,AshenFork,Khazan}.skl` |
| 技能（被动/通用） | 169 / 174 / 190 / 1 / 17 / 58 / 65 | `skill/swordman/*.skl` |
| 装备 | 27600 / 27601 / 27602 / 27604 / 27606 / 27608 / 27611 | `equipment/character/swordman/weapon/katana/{kat_damaged,kat_worn,kat,kat_s,kat_hkotachi,kat_yaiba,kat_kogaras}.equ` |
| 装备 | 10000 / 10001 / 10050 / 10002 / 10003 | `equipment/character/common/jacket/cloth/*.equ` |
| 掉落物 | 1001 / 1013 / 1047 / 1062 / 1065 / 6003 / 1004 / 3069 / 3171 | `stackable/**/*.stk` |
| 任务 | 101 / 102 / 103 / 104 | `n_quest/elvengard/lorien/epic_1_lorien_{1,2}.qst` · `n_quest/elvengard/lorieninside/epic_2_lorieninside_{3,4}.qst` |
| 支线 | — | `n_quest/elvengard/lorieninside/normal_2_lorieninside_seria_ring.qst`（`[clear reward item] 2 -1 3087 1 100 1`） |

**🔴 红线（错了会让整张图 0 命中）**：**地图加载 = `map/map.lst` 的 `id → path` 表**。`.dgn` 里 `[map specification]` / `[start map]` / `[boss map]` 写的**全是数字 id，不是文件名**，而且这些 id 在目录下常常**没有同名文件**（`sunderlandpoison/` 下就没有 `852.map`，852 是 `e817(1,2).map`）。任何按「id.map」拼路径的写法都是错的。

**另外两条最容易踩的口径**（必须先看）：
① **boss 房 = `[boss map]` 的坐标对（2 个格），不按 `[type]` 筛**；act1 的 `[type][boss]` 与 `[map name]` 是遗留占位。**boss 实体 = 该房 `[monster]` 里最强的那只**（dgn6 实证：boss 候选 {827,853,859,860,877} 的怪构成完全不同 —— 精英怪 5001/5002/5003 数量 827=**8** · 859=4 · 877=4 · 860=1 · 853=0；`12` 牛頭巨獸在 853/860/877 都有，不是 877 独有。**要 tau 当 boss 就选 877**（唯一 tau 与 lugaru 混编的候选），**要满编精英就选 827**）。
② **房间分配三级回退**：`[map specification]` 候选随机 → `.map` 文件名里的 `(col,row)` → 按 id 递增。`lorien.dgn` 无 spec，必走 2/3 级。

## 2. 十步实现顺序（每步输入 → 输出）

| # | 步骤 | 输入 | 输出 |
|---|---|---|---|
| 1 | 数值基座 | `swordman.chr`、`exptable.tbl`、`sptable.etc`、`monsterbaseparameter.tbl` | `StatTable.tres`：玩家 Lv1–20 成长 + 怪物 Lv1–20 基表 + 两条查找函数 |
| 2 | 玩家移动/跳跃 | 初始属性（`[move speed] 1350`、`[jump power] 430`） | 一个能跑能跳的胶囊体；速度/重力 `自定`（跑 300–400 px/s、跳高 2 人高） |
| 3 | 普攻与受击 | `attack1.atk` 口径、`swordman.lay` 的 `attack motion` 3 段 | 三连击状态机 + 命中判定（矩形，几何 `自定`：身前 60×50） |
| 4 | 怪物与 AI | 7 只哥布林 + tau + 4 只貓妖 `.mob` + `ai/{action,movemethod}.ai` | 巡逻→发现→追击→攻击四态；同一套 `MonsterDef` 表驱动 |
| 5 | 伤害与死亡 | `[damage bonus]`、`[attack type]`、`[push aside]/[lift up]`、10a 公式 | 伤害数字、击退/浮空、硬直、死亡淡出 + 经验结算 |
| 6 | 技能系统 | 6 个 `.skl` + `.lay [etc motion]` + `.atk` | `SkillDef` 表 + 6 个技能状态；后 13 个技能做成「同学同动作、只换数值」占位 |
| 7 | 副本运行时 | 3 个 `.dgn` + 房间池 + `[greed]` 15 token | 迷宫生成（三级回退）、房间切换、`[start map]`/`[boss map]` 落点、boss 判定 |
| 8 | 城镇与 UI | `new_Elvengard.twn/.map`、3 个 NPC、`EquipmentShop1.shp`、`Lorien.wdm` | 城镇行走 + 3 NPC 对话 + 商店买卖 + 世界地图选副本 + 进副本/回城 |
| 9 | 掉落与经济 | `.mob [item]`（id+权重）、`etc/worlddrop.etc`、`[reward int data]` | 掉落表 + 拾取 + 金币；**act1 怪不掉装备，装备只能买/任务给**（原作事实） |
| 10 | 任务链 | 4 个 `.qst` + `questparameter.etc` 难度字符 | 接取→条件跟踪（`[meet npc]`/`[condition under clear]`/`[hunt monster]`）→ 交任务→发奖 |

## 3. 数值栏（全部 `自定`，只给区间）

| 量 | 区间 | 备注 |
|---|---|---|
| Lv1 小怪 HP | **30–50** | 按 10a 表 col5×70% 得 35，直接可用 |
| 玩家单次普攻伤害 | **5–8** | 现状算出 29 → 要么把武器物攻压到 5–8，要么按 10a §8 把怪 HP 提到 150% |
| TTK（普通怪） | **5–8 下** | 首切片唯一需要手调的指标 |
| TTK（boss） | **40–80 下** | |
| 小怪一击伤玩家 | 玩家 HP 的 **2%–8%** | |
| 玩家 Lv1 HP / MP | 180 / 140（`自定` 可改 150–200 / 100–150） | `.chr` 原值 |
| 一趟 5 房副本 | 升 **1–2 级** | 21 只×150exp ≈ 3150 |
| 金币（普通怪） | 0（act1 不直接掉金币，靠卖材料 + 任务） | |

## 4. 明确不做

转职/觉醒、TP、时装、宠物、唯一兽、公会、PVP、史诗图鉴、独立掉落表（act1 本就没有）、强化/增幅/锻造（`etc/upgrade.etc` 留到 M4）、`.act` 行为脚本引擎（player 技能无 `.act`，全用 `SkillDef` 表）、Squirrel 脚本。

## 5. P0.6 图集到货后可替换的一层

**只替换「渲染层」**：`SkillDef` / `MonsterDef` / `RoomDef` 里的 `ani → SpriteFrames` 引用，其余（数值表、状态机、房间生成、任务）一行不动——M3 用占位色块/Sprite2D 即可，接图后按 `.ani` 解码结果替换为 AnimationPlayer 轨道。
