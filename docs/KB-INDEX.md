# 知识树索引 · DNF-like 项目

> **怎么用这份文件**：不要从头读。先看 §0 找到"我要做什么"对应的入口，再跳到对应主题行（结论 + 出处）。要读细节时按「出处」列的文档与章节定位。
> **权威顺序**：`analysis/00-SYSTEM.md`（体系与裁定）> 领域文档（02–09）> `docs/PVF-FORMAT.md`（格式概述，个别表述已被推翻，见 00-SYSTEM §5）> `analysis/00-OVERVIEW.md`（自动生成，数字可能滞后）。
> **数字口径**：本页所有计数以 `export/_meta/index.sqlite` 为准（2026-10 重算），与领域文档有出入的已在 00-SYSTEM §5 裁定。
> 全库规模：`data/Script.pvf` 923 MB → 1,460,792 文件 / 6.2 GB 可读导出；`.ani` 1,058,561（72%）；`.act` 77,511；`.nut` 2,489；`.atk` 18,877；`.equ` 108,645；`.stk` 28,794；`.mob` 4,042；`.map` 5,800；`.dgn` 625；`.qst` 3,852；`.skl` 4,005；`.lay` **13**；`.lst` 58。

---

## 0. 按"我要做什么"找入口

| 我要… | 先读 | 再看 | 关键结论 |
|---|---|---|---|
| **搞清整个游戏怎么跑起来** | `00-SYSTEM.md` §0–§2 | §3 引用图 | 四张平表靠下标/路径连接，无嵌套 |
| **实现一次攻击的完整链路** | `00-SYSTEM.md` §2.1–§2.6 | `04-combat.md` §1–§4、`ANI-FORMAT.md` §4 | 几何在 `.ani`、属性在 `.atk`、时序在 `.act`/`.nut` |
| **解析 `.ani`** | `ANI-FORMAT.md` §2、§4、§5 | `tools/ani_parser.py` | v6 文法闭合 95.02%，帧字段已定长 |
| **写动作脚本（怪物）** | `09-script-mechanics.md` §1 | `06-monster.md` §3 | 章 + 编号实例 + 触发器；无脚本 |
| **写动作脚本（玩家技能）** | `09-script-mechanics.md` §3 | `03-skill.md` §6 | 角色无 `.act`，全在 Squirrel 回调 + `pushState` |
| **做伤害与打击感** | `04-combat.md` §2 | `00-SYSTEM.md` §7 P0-3 | 公式不在 PVF，必须自定 |
| **做装备/掉落/强化** | `05-item.md` §1–§5 | `06-monster.md` §5 | 三套独立编码；强化零冗余 |
| **做地图/副本** | `07-map.md` §1–§4 | `00-SYSTEM.md` §3.3 | `[greed]` 2 字符=出口位掩码 |
| **在 Godot 里把地图装起来** | `docs/PVF-MAP-LOADING.md` §1、§5 | §2（各文件规则）、§3（坐标系统） | twn→dgn→map→til 单链；坐标与 pass 行序都是「从下往上」 |
| **今天踩过的坑 / 别重复** | `docs/PVF-MAP-PITFALLS.md` §0、§3 | §5（工作方式纪律）、§6（2026-11-25 NPC/跨城/释放增量）、§7（复查命令） | z_index 越界会静默回落 0；`[img pos]` 是画布顶部空白；`[animation]` 与地砖是两套坐标；NPC 还要加 NPK 帧画布原点 |
| **地图位置不对，按步骤查** | `docs/PVF-MAP-DEBUG.md`、`docs/PVF-MAP-AUDIT.md` | §4（每步的验证声明与停点） | 128 城镇/15,700 map 已审计；120 偏移、`[town movable area]` y 方向、`map_y()` 的 `+img_pos` 仍是待验证假设；图片结论由人判断 |
| **读 latest 的 `.stk` / `.chr`** | `docs/PVF-NEW-STK-CHR-SPEC.md` §2–§4 | §3.2 枚举表、§4.3 skill 三元组 | `.stk` 显式闭合可成树；`.chr` 平铺流必须状态机 |
| **做任务** | `08-quest.md` §1 | `08-quest.md` §2 | 一个枚举 + 变长参数 + 一张全局经济表 |
| **做 UI** | `09-script-mechanics.md` §4 | `08-quest.md` §3 | 四档数据化；HUD 硬编码 |
| **选引擎 / 定工程约束** | `docs/GODOT-EVAL.md` §0、§12 | §10 风险 | 有条件推荐，三个硬条件 C1–C3 |
| **排期** | `docs/ROADMAP.md` | `00-SYSTEM.md` §6 | 先 A 级系统，再 B 级 VM |
| **查某个标签是什么意思** | `01-TAG-DICT.md` | `tagdict.sqlite` | 200+ 条官方注释 |

---

## 1. 主题索引（结论 → 出处）

### 1.1 格式与工具

| 主题 | 结论 | 出处 |
|---|---|---|
| `.ani` v6 文件结构 | `u16 frame_max \| u16 img_count \| img_count×(u32 len+路径) \| 帧×frame_max \| 尾部 0~3 全零`；帧 = `u16 n_head \| n×(u16 id+payload) \| image_slot \| i32 x \| i32 y \| u16 n_tail \| n×(id+payload)` | ANI-FORMAT §2、§4 |
| 帧字段 id 表 | `0x07` IMAGE RATE(8B) `0x08` ROTATE(4B) `0x09` RGBA(4B) `0x0a` INTERPOLATION(1B) `0x0b` 2B `0x0c` DELAY(4B, 99.4% 帧有) `0x0d` DAMAGE TYPE(0/1/2) `0x0e` DAMAGE BOX(24B) `0x0f` ATTACK BOX(24B) `0x10` 字符串 `0x17` 未知(0..7) | ANI-FORMAT §5 |
| 判定盒格式 | 6×i32 = `(相对X, 相对Y, 相对Z, 宽, 高, 深)`；正样本账本 5/5 + 3/3 逐值相等 | ANI-FORMAT §4、§9 |
| 解析质量 | 30,000 抽样：clean 28,505（95.02%）/ fail 1,447 / dirty 48；≈0.43 ms/文件 ⇒ 全量 7.5 min | ANI-FORMAT §9–§10 |
| PVF 文本解析坑 | `dictSegment2text(maxSegNum=50, depth=4)` 会截断 >50 值数组和深嵌套 ⇒ 数值校验必须用 `read_File_In_Dict`；PVF 路径非根相对，须后缀匹配+同根优先；id→文件唯一入口是 `.lst` | PVF-FORMAT（"解析注意"章）、03 §0 |
| 导出名规则 | 文本追加 `.txt`、二进制追加 `.bin`（`boom.act`→`boom.act.txt`，`boom01.ani`→`boom01.ani.bin`） | PVF-FORMAT |
| 查数命令 | `python3 -c "import sqlite3;…index.sqlite"`（环境无 sqlite3 CLI）；`grep -a -rn '\[greed\]' export/text/dungeon`；`python3 tools/ani_parser.py X.ani.bin --json`；`python3 scripts/dump_nut.py X.nut` | 00-SYSTEM §0、09 附录 A |
| **latest（34 版）与旧版差异** | latest 用 token 流（5 字节 `[type][value]`）+ strW 池；`.stk` 有 `[/x]` 闭合、`.chr` 没有；`.chr [skill]` 是三元组 `(id,等级,学习等级)` | PVF-NEW-STK-CHR-SPEC §2、§4.3；`docs/PVF-NEW-FORMAT-34.md` |
| **latest 地图数字** | `.twn` 317 / `.dgn` 7,500 / `.map` 49,170（`map/` 34,610）/ `.til` 141,884 / `.lay` **0**；副本注册表只有 `dungeon/tutorial/dungeon.lst`（1277 条） | PVF-MAP-LOADING §2；`analysis/pvf-new/pvf34.sqlite` |

### 1.2 机制与脚本

| 主题 | 结论 | 出处 |
|---|---|---|
| 四层结构 | 实体声明 → 动作编排 → 判定与属性 → 表现；层间靠整数 id / 数组下标 / 命名约定 | 09 §1.1、00-SYSTEM §1 |
| **角色没有 `.act`** | character/ 下仅 1 个 `.act`（`booster_particle`，140 B）；全库 77,511 个 `.act` 里 53,041 在 monster/、24,107 在 passiveobject/ | 09 §1.1（数字经 index.sqlite 复核） |
| **`[USE SKILL]` 不存在** | 1,460,792 个文件里 0 次。怪物"放技能" = `[SET ACTION] [ATTACK] n [NOW]`；玩家 = `sq_AddSetStatePacket` | 09 §1.2 |
| `.act` 语法 | 章 `[MOTION]/[TRIGGER]/[BEHAVIOR]`；`[XXX]-N` = 第 N+1 个实例；`[DO BEHAVIOR] [ME] n` 按编号调用；`[TRIGGER] 8 [ON/OFF]` 可启停其它触发器 | 09 §1.3、00-SYSTEM §2.4 |
| 状态机注册 | `pushState(job, nutPath, scriptName, stateId[, skillId])`；剑士 state 8 = 普攻（jg 版生效，原版 `:51` 被注释）；`:93` state 101 / skill 8 = 三段斩 | 09 §3、00-SYSTEM §2.3 |
| ⚠️ 两个 "8" | `8` 作 stateId = 普攻；`8` 作 skillId = 三段斩。**必须用 `StateId`/`SkillId` 区分** | 00-SYSTEM §5 #6 |
| 动画下标 | `sq_SetCurrentAnimation(n)` / `CUSTOM_ANI_*` = `.lay [etc motion]` 的 **0 基**下标；`bloodboom.nut:50` 的 122 → `%s/bloodboom.ani` | 00-SYSTEM §5 #7（本轮新结论） |
| `%s` 展开 | 由装备 `[layer variation]`（如 `2790 katanac`）展开成贴图子目录 → 一套动作 × N 套贴图 | 09 §3、05 §2 |
| `.als` 真相 | **不是**动作别名/状态转移：全库无一个 `.als` 含 `[TRIGGER]`，仅 2 个含 `[MOTION]`；7,300 个角色 `.als` 只有 `[use animation]`7292 / `[none effect add]`4299 / `[add]`2751 / `[create draw only object]`538 | 09 §2 |
| `.nut` API | 554 个不同 `sq_*`，280 个方法式；无 widget/文件/网络 API；对外只有发包一族 | 09 §3 |
| 联机接缝 | `if(obj.sq_IsMyControlObject()){ sq_BinaryStartWrite(); …; sq_SendCreatePassiveObjectPacket(…) }`（实测 2,280 次）= owner 发确定性指令、他端重放 | 09 §3、00-SYSTEM §3.4 |
| 多段命中 | 不靠多个攻击盒，靠关键帧里 `obj.resetHitObjectList()` | 00-SYSTEM §2.3 |
| 动作取消 | `onProcCon_*` 是"没进状态也能响应输入"的唯一钩子 | 00-SYSTEM §2.3 |

### 1.3 战斗与数值

| 主题 | 结论 | 出处 |
|---|---|---|
| `.atk` 三文件分工 | 数值与语义 `.atk` / 几何 `.ani` 每帧 / 时序 `.nut`(玩家) 或 `.act`(怪物)；`.atk` 无任何坐标 | 04 §0（18,877 个复核） |
| `.atk` 标签 | 100 个已注释：`[damage bonus]` `[attack type][physic\|magic]` `[elemental property]` `[damage reaction]` `[push aside]/[lift up]/[knuck back]` `[hit info]` 四元组 `[active status]` 16 种 | 04 §1 |
| 反直觉编码 | `[stuck]` 填**负数**才是加命中；`[value]` 实收 **1/5** | 04 §1、§3、05 §9 |
| 待定参数 | `[active status]` 参数个数两说（04 正文 16 种、§8 #3 记 5 个数、样本见 7 个） | 04 §1、§8 |
| 伤害公式 | `基础 = 面板攻 × damage bonus% × 技能等级倍率 × 暴击 × 属性抗性 × 等级差`；**常数不在 PVF** | 04 §2、00-SYSTEM §7 P0-3 |
| PVE/PVP 双列 | 装备/技能字段成对存放（`[equipment physical attack]` 两列）；`.atk` 另有 `[pvp]` 覆盖块 | 04 §1、05 §1 |
| 技能数据 | `.skl [level info]` 首值 = 动态列数；`[level property]` 三元组 (来源,索引,倍率)；`[required level range]` = 等级间隔；`growtype × maximum level` 双表 | 03 §2–§4 |
| 玩家技能链 | skill id → `_load_state.nut` `pushState` → `nut` 里的 `CUSTOM_ANI_*` → `.lay [etc motion]` → `%s` 展开 | 03 §6、00-SYSTEM §2.3 |
| 状态回调 | `onSetState_*` / `onProc*` / `onProcCon*` / `onKeyFrameFlag_*` / `onEndCurrentAni_*` / `onAfterSetState_*` | 09 §3 |
| 命中时序 | 判定框开关 + 命中去重 + 多段命中重置 | 04 §4 |

### 1.4 角色与装备

| 主题 | 结论 | 出处 |
|---|---|---|
| `.chr` 结构 | 13 个文件（`character.lst` 只登 11）；= 1 级基础值 + `[growtype N]` 每级增量 + `[module damage rate]` 4 列模式伤害倍率 + `[skill]` 初始技能 | 02 §2 |
| 单位换算 | 重量单位克（`1350` ≈ 13.5 px/帧 的推力）；exptable 115 级 | 02 §1、§6 |
| 职业枚举 | swordman 0 / fighter 1 / gunner 2 / mage 3 / priest 4；`characteretc` 三类容器（growTypeEquipment、`*.etc`、`*.lst`） | 02 §3 |
| 装备字段 | `[grade]`=实际等级、`[rarity]`=稀有度(0–7 经济档)、`[icon mark]`=UI 边框(62–68)，**三套独立编码**；`[if]/[then]` 规则引擎；`[skill data up]` 是装备改技能的唯一接口 | 05 §1–§4 |
| 套装 | `.equ [set item]` + `equipment/equipmentetc/*.etc` 总表 | 05 §2 |
| 强化/增幅/锻造 | 装备侧只写 `[grade]`+`[rarity]`，数值全在 `etc/upgrade.etc`（`[table]` 每行 5 个概率） | 05 §5 |
| 消耗品 | 27 种 `[stackable type]`；`[int data]` 的设计图编码 | 05 §4 |

### 1.5 怪物与地图

| 主题 | 结论 | 出处 |
|---|---|---|
| `.mob` 字段 | 面板 / 动作槽 / 攻击槽 / AI 槽 / 掉落；基表 100 行 × 11 列（5 组 × min/max），`[ability category]` 乘数覆盖 4,042 只怪 | 06 §1–§2 |
| 三条平行数组 | `[attack action]` / `[attack info]` / `[cooltime]`，由 `[ATTACK] n` 统一下标（长度不一致时行为未定义，P1-4） | 06 §3、00-SYSTEM §7 |
| AI 条件树 | `.ai` 4 文件（Event/DestinationSelect/Action/MoveMethod），DSL = `[think]/[true]/[false]/[return]/[last result]` | 06 §3 |
| APC 宏 | `.aic` = "会按键的玩家"（`attack damage rate 0.1`、按键流），`.key` = 宏；不是 AI | 06 §3 |
| 掉落三层 | 独立掉落 / 精英掉落 / 全局 `worlddrop`，带权重 | 06 §5 |
| 地图四层链 | `.twn`(→`[area]`+坐标) → `.rgn` → `.wdm`(`[dungeon]`+`[ui path]`) → `.dgn`(→`[map specification]`+mapId) → `.map`(→`[dungeon]` 反向指回) | 07 §1–§4、09 §5 |
| `[greed]` 解码 | 每格 **2 字符** = 出口位掩码；625 个 `.dgn` 验证 621 自洽 | 07 §1 |
| "随机地图"真相 | 不是程序生成，是 `[map specification]` 候选列表里**随机挑已做好的房间** | 07 §1、00-SYSTEM §3.3 |
| 难度在关卡 | `.dgn [basis level]` + `[champion]` 5 值（普通/冒险/勇士/王者/英雄） + `.map [monster]` 等级自动指定 | 07 §1–§2、06 §6 |
| 视差 | `.map [far/middle/near sight scroll]` 三档比率 + `[background animation]` 的 `[layer]/[order]` 两层动画 = 纵深全部来源 | 07 §2 |
| 实例 | dungeon 1 = `act1/lorien.dgn`；dungeon 52 = `act6/danceingbutterfly.dgn`；map 6501 = `bloodbutterfly/6501(3,4)start.map`（`[dungeon]=52`） | 09 §5 |

### 1.6 任务、NPC、宠物、活动

| 主题 | 结论 | 出处 |
|---|---|---|
| 任务本质 | 一个 `[type]` 枚举 + 变长 `[int data]` + `[sub type]` 15 种，**零脚本** | 08 §1 |
| 任务经济 | `n_quest/questparameter.etc`：难度字符 × 经验/金币表 × 等级惩罚 → 3,852 个任务的产出全部由 2.6 KB 决定 | 08 §2 |
| `.lst` 覆盖率 | `quest.lst` 只登 339 / 3,852（其余靠其它入口） | 08 §1、00-SYSTEM §3.2 |
| NPC 对话 | 对话树 + 导师商店；`[dialog]` 每行前 4–6 个数的列义未定（P2-17） | 08 §3 |
| 宠物 | `.cre` 的 `skill node` = `.skl`+`.atk`+`.ani` 三件套；三种进化；唯一兽在数据层与普通宠物同构（唯一性属服务端） | 08 §5–§6 |
| 活动 | `.evt` 含自定义块，单机可不做 | 08 §4 |
| 任务奖励通道 | `.qst [monster reward item]`(7 值) / `[enemy reward item]`(8 值) 可临时改写掉落，不污染全局表 | 08 §1、§8 |

### 1.7 UI

| 主题 | 结论 | 出处 |
|---|---|---|
| 四档数据化 | ① 世界地图选图**全数据**（`.wdm [ui path]` → `worldmap/ui/*.ui`）② 城镇/背包**半数据**（`.ui` 只给摆位，控件 ID 三态：`IDC_` 885 / 纯数字 2946 / 符号名 476，句柄在客户端 C++）③ 副本内 HUD **硬编码**（`init_character.nut:53-97` 常量像素）④ 结算 `ui/result/` 0 个 `.ui`、`IDC_RESULT` 零命中 = 全硬编码 | 09 §4 |
| 复刻含义 | UI 只能自建控件库重写，不能"导入"；HUD 照抄常量即可（分辨率变了要重排） | 09 §4、00-SYSTEM §1.3 |

### 1.8 引擎与工程

| 主题 | 结论 | 出处 |
|---|---|---|
| 版本 | Godot **4.7.2-stable**（4.8-beta 不采用） | GODOT-EVAL §1 |
| 三个硬条件 | C1 不把百万帧动画当资源导入（自建 NPK→图集→`Sprite2D.region_rect` 运行时管线）· C2 数据层不走一文件一 JSON（P0.8 出分域二进制+索引+懒加载）· C3 Web 不作主目标 | GODOT-EVAL §0 |
| 实测要点 | 68 MB JSON 1029 ms/内存 +788 MB（≈11×）；`var_to_bytes` 快 2.5×；**导入超线性**（2k 2.9 s / 5k 32 s / 20k >5 min）；10 万小 JSON 使 `--import` 2.9→13.7 s；运行时原生解 DDS | GODOT-EVAL §2 |
| 技术取舍 | 事件帧不用 Call Method Track（查表）、判定不用 `Area2D`（自算 `Rect2`，保确定性/可回放）、地图不是 tile 图、选 GDScript 不选 C#（C# 不能导 Web）、Y 轴转换成本≈0 | GODOT-EVAL §3 |
| 风险 | R1 素材体量 / R2 Web 崩坏 / R3 启动卡顿 / R4 手感（固定 60 Hz + 输入缓冲 + 可回放日志）/ R5 工程规模 | GODOT-EVAL §10 |
| 次选 | Unity 6（要 Web+移动+商业化）、TS+PixiJS（Web 优先）、Godot 3.6 LTS（必须 Web+C#）、Defold | GODOT-EVAL §11 |
| M2 验收 | 60 fps、显存 <100 MB、启动 ≤2 s、Win/Linux 可执行包 | GODOT-EVAL §12 |

---

## 2. 速查：文件与数字

**一个机制要找哪个文件**

```
输入/键位         → 不在 PVF（APC 用 .aic/.key）
技能能否学/怎么放   → .skl [command]/[required level range]/[maximum level]
技能动画哪一帧     → .lay [etc motion][n]（0 基）→ .ani
判定盒几何        → .ani 0x0f / 0x0e（6×i32）
判定开关          → .act [SET DAMAGE BOX][ON] / .nut sq_SetAttackBoundingBoxSizeRate
伤害属性          → .atk（.mob [attack info][n] 或 sq_SetCurrentAttackInfo）
打上去什么效果      → .atk [damage reaction]/[hit info]/[active status]
硬直/击退         → .atk [hit info] 四元组 / [push aside]/[lift up]
角色外观          → .equ [equipment ani script] + [layer variation] + [variation] → .lay → .ani
怪物选招          → .ai（4 文件）→ .mob [attack action][n]
怪物连招          → .act [TRIGGER][FRAME] a b → [BEHAVIOR] → [SET ACTION][ATTACK] n
掉落             → .mob [item] / .map [monster] 掉率 / worlddrop / .qst reward item
任务条件          → .qst [type]+[int data]
地图房间          → .dgn [greed]+[map specification] → .map → .til
界面布局          → .ui（只有摆位） / worldmap/ui/*.ui / init_character.nut 常量
```

**必须记住的数字**

| 值 | 含义 |
|---|---|
| `0xFFFF` | `.ani` 帧 image_slot 的"本帧无图" |
| 6 × i32 | 判定盒 6 元组 `(x,y,z,w,h,d)` |
| `100` ms | 常见帧 DELAY（`boom01.ani` 每帧 100） |
| `-1` | `pushState` 第 5 参 = 无技能数据（普攻） |
| `0 基` | `[etc motion]` 下标基准 |
| `2 字符/格` | `[greed]` 每格的出口位掩码宽度 |
| `15` | `[difficulty]` 字符对（`S 115 / A 90 / B 70 / Z 400`，定义在 `questparameter.etc`） |
| `5` | `.dgn [champion]` 的 5 个难度值 |
| `100 / 102,329 / 32,170` | 怪物基表行数 / 装备注册条数 / 道具注册条数 |
| `1,058,561` | `.ani` 总数（**不要**用 1,047,702） |
| `95.02%` | `.ani` 解析字节级闭合率 |

---

## 3. 待验证清单

> **权威版在 `analysis/00-SYSTEM.md` §7**（20 条，含来源 / 验证方法 / 不解决的后果，按 P0–P3 排序）。此处只列 P0/P1 摘要，避免两处维护。

| 优先级 | 问题 | 来源 |
|---|---|---|
| **P0-1** | 帧标记 `flagIndex` 由 `.ani` 哪个字段承载（`0x17` 值域 0..7 vs 脚本实参 67/100/101） | ANI-FORMAT §10 + 09 §8（未闭合） |
| **P0-2** | `.atk` 整数索引 → 文件的映射规则（全靠命名约定，无 `.lst`） | 本轮新增 |
| **P0-3** | 伤害公式常数（防御/等级差/属强/暴击/PVP 列） | 04 §2 |
| **P1-4** | `.mob` 三条平行数组长度不一致时 `[ATTACK] n` 的取值规则 | 本轮新增 |
| **P1-5** | `.til [pass type]` 网格宽高（值 `3` 语义未知） | 07 §8 |
| **P1-6** | `[SET DAMAGE BOX][ON/OFF]` 作用域与持续时间；无敌帧来源 | 09 §1.6 + 新增 |
| **P1-7** | `[greed]` 三向 token 是否只在边角；多套 `[maze info]` 是否按难度 | 07 §8 |
| **P1-8** | 554 个 `sq_*` 的最小可用子集划分 | 09 §3 |

**已关闭**（不必再查）：`.ani` v6 帧结构（ANI-FORMAT 已解决）· `.atk` 是否有几何（无）· `.act` 目录分布 / `.ani` 总数 / `.mob` 覆盖率（`index.sqlite` 已定案）。

---

## 4. 文档地图

| 文件 | 行数 | 定位 |
|---|---:|---|
| `analysis/00-SYSTEM.md` | — | **总纲**：分层、机制链路、引用网、设计点评、矛盾裁定、待验证 |
| `analysis/00-OVERVIEW.md` | 212 | 数据规模与查法（自动生成，数字可能滞后） |
| `analysis/01-TAG-DICT.md` | 1,039 | 标签字典（官方注释） |
| `analysis/02-character.md` | 335 | 职业 / 成长 / 单位 |
| `analysis/03-skill.md` | 329 | 技能数据与接口 |
| `analysis/04-combat.md` | 361 | `.atk` 全标签、命中时序、伤害公式 |
| `analysis/05-item.md` | 501 | 装备 / 道具 / 强化 / 套装 / 设计图 |
| `analysis/06-monster.md` | 403 | 怪物面板、AI、掉落 |
| `analysis/07-map.md` | 391 | 城镇 / 关卡 / 房间 / 地砖 |
| `analysis/08-quest.md` | 493 | 任务 / NPC / 宠物 / 活动 |
| `analysis/09-script-mechanics.md` | 924 | `.act` / `.als` / `.nut` / UI 机制 |
| `docs/ANI-FORMAT.md` | 255 | `.ani` v6 格式（已实现） |
| `docs/PVF-FORMAT.md` | 203 | PVF 文本解析（其"`.atk` 判定盒"表述已作废） |
| `docs/REFGRAPH.md` | 181 | 引用图统计（2,447,600 边） |
| `docs/GODOT-EVAL.md` | 405 | 引擎评估与工程约束 |
| `docs/ROADMAP.md` | 171 | 阶段与分工 |
| `tools/ani_parser.py` | — | `.ani` 解析器（`--json`） |
| `scripts/dump_nut.py` | — | `.nut` 剥 NUL 带行号输出 |

---

## 5. 维护约定

1. **新结论先落到领域文档**（02–09），再由本页登记一行；不要只写进本页。
2. **数字改动必须写口径**（哪个 sqlite 查询 / 哪个 grep），否则半年后无法复现。
3. **矛盾不下结论就标"待裁定"**，并在 `00-SYSTEM.md` §5 追加一行（甲方 / 乙方 / 核对 / 裁定）。
4. 本页只做索引与速查，**不重复正文**；正文有冲突时以 `00-SYSTEM.md` 为准。
