# DNF-like 项目路线图

> 目标：以现有 DNF 私服数据（PVF + NPK）为参考，解析游戏设计体系，并逐步开发一款同类 2D 横版动作游戏。
> 本文回答三件事：**这几件事怎么排序、每件事拆成哪些任务、哪些信息还不全需要一起补。**

---

## 一、结论先行：排序

你说的是「① 解析 PVF → ② 分析设计 → ③ 机制开发」。方向对，但直接串行会踩两个坑：

- 只解析不建模：1,460,792 个文件堆在磁盘上，不等于「能分析」——中间缺一层**实体/关系模型**（谁引用谁、字段什么意思）。
- 死磕完整分析：DNF 是运营 20 年的 MMO，完整体系分析是无底洞，会永远开不了工。

所以实际排序是 **三段并行推进**：

```
P0 数据管道  ──▶  ┬─▶ P1 设计体系分析（按需、按切片优先级）
   （并行前置）     └─▶ P2 技术选型与框架 ──▶ P3 垂直切片开发 ──▶ P4 内容扩张
```

- **P0 必须先做**（否则后面全是拍脑袋）。
- **P1 与 P2 并行**：分析为开发供料，开发为分析定优先级。
- **P3 先做垂直切片**（一个职业 + 一张图 + 一只怪 + 掉落结算），而不是先铺系统。
- 分析跟着切片走：切片要什么，就先分析什么。

---

## 二、阶段与任务拆解

状态：`✅ 已完成` / `🔄 进行中` / `⬜ 未开始` / `⛔ 缺信息`

### P0 数据管道（当前阶段）

| 编号 | 任务 | 产出 | 状态 |
|---|---|---|---|
| P0.1 | PVF 解密 + 文件树索引 | `export/_meta/index.sqlite`（146 万条） | ✅ |
| P0.2 | 全量文本导出为可读目录树 | `export/text/`（41.0 万文本 + 105.0 万二进制，47s） | ✅ |
| P0.3 | 混合编码修复（台服 Big5 + 国服 GBK 注入） | `decode_any()` + `data/zh-common.txt` | ✅ |
| P0.4 | 元数据导出：stringtable / n_string / .lst 注册表 | `export/_meta/`（54 个 .lst 表 + 3 个标签流配置，58/58 全可读） | ✅ |
| P0.5 | **ANI 二进制解码器** | `export/ani/`（185 片 JSONL、1.66 GiB、996,999/1,047,702 = **95.16%** ok、1,091.8 万帧）+ `docs/ANI-FORMAT.md` + `analysis/ani/QUALITY.md` | ✅ |
| P0.6 | **NPK/IMG 解码器** | 图片帧 → 2048² 图集 + 帧矩形表 | ⬜ |
| P0.7 | 引用图（path → 引用的 path） | `export/_meta/refgraph.sqlite`（244.8 万边）+ `docs/REFGRAPH.md` | ✅ |
| P0.8 | 结构化导出（标签流 → 每行一实体的 JSONL） | `export/structured/*.jsonl.gz`（**30 MB** 覆盖约 40 万实体）+ `tools/pvf_structured.py` + `docs/STRUCTURED-DATA.md` | ✅ |
| P0.9 | 数据字典（标签 → 中文语义） | `analysis/01-TAG-DICT.md` + `export/_meta/tagdict.sqlite` | ✅ |

**P0 阻断三问（`analysis/11-P0-BLOCKERS.md`，t9 收口）**：
1. `flagIndex` = `.ani` 每帧 `0x17` 字段（i32 小端），与脚本实参逐值相等 → 动画回调有入口了。
2. `.atk` 整数索引 = `.chr [etc attack info]` 有序数组的 **0 基下标**（swordman 155 项、fighter 104 项），无全局注册表。实测 `[36]=WeaponComboBlunt3.atk`、`[100]=WeaponComboBlunt4.atk`。
   **私服数据不同步（要记住）**：zrr 从下标 117 起穿插插入了 `attackinfo/zrr/*` 条目，而 `sqr/character/swordman_jg/swordman_value.nut` 的 35 个 `ATTACKINFO_*` 常量仍指向原编号（0/35 命中）→ 剑神技能的攻击信息在这份私服里大概率是错位的。我们复刻时**用 `[etc attack info]` 位置解析，不要用那些常量名**。
3. 伤害公式四段式 + Lv1 基准：物攻 7.5、每级 +4.8、`attack1.atk damage bonus -15`（0.85×）→ 单次普攻 ≈6（推断）。防御减免不在 PVF，用 `1-def/(def+K1+20×lv)` 线性替代（自定）。**唯一加急未闭合项**：`[weapon damage apply]` 是否计武器攻击力（影响伤害一倍 → 直接决定 TTK）。

**P1 结论修正（`analysis/14-SKILL-ANIM-MAP.md`，t14 收口，2026-10-26）**——这两条推翻了 `analysis/00-SYSTEM.md §2` 与 `analysis/03-skill.md` 里「技能链已闭合」的说法，**以本节为准**：

1. **玩家技能链在引擎里，不在数据里。** 23 个切片技能中只有 `三段斬`(skillId 8) 有 Squirrel 脚本（`swordman_load_state.nut:93` → stateId 101）；其余 22 个在 2,487 个 `.nut` 里对 `checkExecutableSkill_` / `onSetState_` **0 命中**。→ `skillId → 动作下标` 这张表在客户端 exe 内，**Godot 侧必须自建，并以我们的表为权威**；`export/_meta/skill_anim_map.json` 里的 `ani_index/atk_index` 只是候选（每条带 `ani_source` 溯源）。统计：total 28 / full 1 / no_nut 27 / no_ani 10 / no_atk 12 / no_hitbox 19。
2. **`.ani` 有双份副本，只有一份带 `[ATTACK BOX]`。** `character/swordman/animation/dashattack.ani` 10 帧 7 盒，`equipment/…/weaponmaster/dashattack.ani` 10 帧 **0 盒**（jumpattack 1 vs 0 同理）。解析顺序必须 **chr 根 → weaponmaster → 全局同名**（按名裸搜会撞到 `monster/`、`mage/` 的同名 ani）。**搞反 = 所有攻击打不到人。**
3. 9 条技能有真实判定盒可直接落 `.tres`：普攻三段 `(-32,-13,0,179,26,94)`@f2、冲刺 `(82,-13,51,85,26,27)`@f2–8、跳跃 `(13,-13,-11,88,26,167)`@f2、上挑 `(-32,-15,0,238,30,169)`@f3–5、崩山擊 `(-10,-20,-2,86,40,49)`@f3–5、三段斬 `(-50,-25,0,200,50,80)`@f1–3 等。**普攻第 1/2 段只有 DAMAGE BOX、没有 ATTACK BOX → 自定（按三段缩一档）。** 语义 = `(相对X, 相对Y, 相对Z, 宽, 高, 深)`，翻转时 x 取反。
4. `[FLAG]` 帧在切片里只有十字斬用到（flag 1、2）；**`flag 65534` 是「无 flag」哨兵，不是真 flag**。
5. **普攻 1/2 段的攻击盒在「武器动画」里，不是没有**（`analysis/15-WEAPON-ATKBOX.md`，capain 实测）——上一条「普攻 1/2 段无盒需自定」**作废**。玩家普攻 = `character/<job>/animation/attackN.ani`（姿态+受击盒）+ `equipment/character/<job>/weapon/<type>/<set>/attackN.ani`（武器轨迹+**攻击盒**）**两层叠加，帧数相等**（鬼剑士 attack1/2/3 = 10/11/9 帧）。45/51 个非 `at_` 武器套在普攻 1 段有盒，不同武器判定范围不同（katana 触及 111 vs 其余 104）。`at_` 前缀 / `ATEquipment` 是另一套外观（6/5/4 帧），**解析时必须过滤**，否则 6 帧动画错配到 10 帧本体上。

**P0.5 为什么关键**：全库 106 万 `.ani`，是「脚本逻辑 → 动作 → NPK 图像」的唯一桥梁。不解析它，动画/攻击盒/判定帧全部读不出来，P3 的动画状态机就是空中楼阁。

**P0.6 为什么关键**：`Script.pvf` 里只有「引用」（`Monster/Guild_dungeon/john.img`），真正的像素在客户端 `ImagePacks2/*.NPK`（约 33GB）。想要能看的画面，必须有 NPK 解码 + 图集打包。

### P1 设计体系分析

| 编号 | 任务 | 产出 |
|---|---|---|
| P1.1 | 顶层架构：模块划分、注册表（.lst）拓扑、版本谱系 | `analysis/01-topology.md` |
| P1.2 | 角色与职业：14 个职业树、成长曲线、属性 | `analysis/02-character.md` |
| P1.3 | 技能体系：3,656 个 .skl 的参数列、状态、连招 | `analysis/03-skill.md` |
| P1.4 | 战斗判定与数值：atk 盒/伤害类型/抗性/硬直 | `analysis/04-combat.md` |
| P1.5 | 装备道具经济：10.4 万 .equ、2.9 万 .stk、强化/合成 | `analysis/05-item.md` |
| P1.6 | 怪物与 AI：369k 怪物文件、11.4k .ai、行为树 | `analysis/06-monster.md` |
| P1.7 | 地图/副本/城镇：5,800 .map、625 .dgn、81 .twn | `analysis/07-map.md` |
| P1.8 | 任务/活动/宠物/唯一兽 | `analysis/08-quest.md` |
| P1.9 | 汇总：《DNF-like 设计体系》 | `analysis/00-SYSTEM.md` |
| P1.10 | 脚本与 UI 机制：动作编排 / 状态注册 / UI 四档数据化 / 联机接缝 | `analysis/09-script-mechanics.md` |
| P1.11 | 引擎可行性：平台、导入开销、动画与判定方案 | `docs/GODOT-EVAL.md` |

**按切片优先级排序**（不是按编号顺序做）：
`P1.2 角色 → P1.3 技能 → P1.4 战斗 → P1.6 怪物 → P1.5 道具 → P1.7 地图 → P1.8 任务`

### P2 技术选型与框架

| 编号 | 任务 | 需要你先定的事 |
|---|---|---|
| P2.1 | 端形态与引擎决策 — **Godot 4.7.2 + GDScript，有条件推荐**（见 `docs/GODOT-EVAL.md`，三硬条件 C1–C3） | Q1 ✅ / Q2 ✅ |
| P2.2 | 数据管线：PVF → 运行时数据（**分域二进制 + 索引**，不上一文件一 JSON） | — |
| P2.3 | 资源管线：NPK → 纹理图集（每 .img 打 2048² 图集 + 帧矩形表） | Q3 ✅ 复用原图 |
| P2.4 | 客户端骨架：渲染/输入/相机/场景 | — |
| P2.5 | 逻辑层：单机模拟 + 留联机接缝（Event/EventBus，本地 apply，联机 broadcast 后 apply） | Q1 ✅ 单机 |

### P3 机制开发（垂直切片优先）

| 编号 | 任务 | 验收 |
|---|---|---|
| P3.1 | 角色移动/跳跃/地形碰撞 | 能跑能跳，卡不住墙 |
| P3.2 | 动画状态机（act 驱动、ani 帧表、事件帧） | 动作切换不错帧 |
| P3.3 | 普攻与连击（Z 键链） | 三段连击手感成立 |
| P3.4 | 判定盒与伤害结算 | 命中数字、击退方向正确 |
| P3.5 | 受击/硬直/浮空/倒地 | 受击反馈完整 |
| P3.6 | 技能框架（先做 2 个技能） | 冷却/消耗/前摇/判定/特效 |
| P3.7 | 怪物 AI（巡逻/追击/攻击） | 会追会打 |
| P3.8 | 掉落与拾取 | 掉落表 → 地面物品 → 进背包 |
| P3.9 | 城镇 ↔ 副本切换 | 选图进本、通关回城 |
| P3.10 | 存档 | 关掉重开进度还在 |

### P4 内容扩张

多职业、多副本、装备成长、任务链、活动、平衡。

---

## 三、信息缺口（需要一起补的）

### 需要你拍板（会改变技术路线）

| 编号 | 问题 | 状态 | 已定结论 / 我的默认建议 |
|---|---|---|---|
| Q1 | 单机还是联机？ | ✅ 已定 | **单机优先**，逻辑层留联机接口 |
| Q2 | 引擎？ | ✅ 已定 | **Godot 4.7.2 + GDScript**（有条件推荐，见 `docs/GODOT-EVAL.md`） |
| Q3 | 素材策略？ | ✅ 已定 | **直接复用 NPK 原图**（用户明确「素材复用没问题」） |
| Q4 | 版本基线？ | ✅ 已定 | **sf115**（内容最全，已解析） |
| Q5 | 首个垂直切片？ | ⛔ **仍缺你的答复** | 建议：鬼剑士 + 洛兰/幽暗密林类低级图 |
| Q6 | 数值还原度？ | ⛔ **仍缺你的答复** | 建议：只还原手感与结构 |
| Q7 | 语言与字体？ | 🔄 默认简体 | 简体（数据可转码）；要繁体也能出 |

### 技术性缺口（我来解决，但需要时间）

| 编号 | 缺口 | 现状 / 计划 |
|---|---|---|
| G1 | 服务端逻辑不在 PVF 内 | 伤害公式、掉落率、经验在服务端 exe。先用「读客户端可见参数 + 公开资料 + 实测反推」补 |
| G2 | `.nut` 脚本 = Squirrel VM | 已摸清：`pushState(job, nut, name, state, skill)` 注册 + 回调。P3 用「数据驱动 + 少量脚本」替代，不复刻 VM |
| G3 | ANI 二进制格式未解 | ✅ 已解（v6 帧文法；95.16% ok，4.84% 报错不产错数据；残留：帧前导宽度变体 ~3.4 万、damagefont 族 8,400、23 个未知 id） |
| G4 | NPK 版本 2/4/5/6 混合 | 用 npk-api 的 Java 实现做参考，移植 Python |
| G5 | 3 套版本数据不一致 | 已选 sf115 为基线，其他仅做对照 |
| G6 | ~~3 个 .lst 解析失败~~ **已关闭** | 真相：不是解析 bug，而是这三个文件**根本不是 id→路径表**，是套了 `.lst` 后缀的**标签流配置**（`[episode]` / `[epic_index]` / `[complete_text]`、`[group]`）。`pvf_loader.read_lst_any()` 现在先试 `Lst_lite2`，失败即回退标签流渲染；58 个 `.lst` 全部可读（55 表 + 3 标签流） |
| G8 | 地图/怪物等的**数字 id 不是文件名** | `.dgn` 的 `[map specification]`/`[start map]`/`[boss map]` 写的是 map id，必须过 `map/map.lst`（`id → path`）反查；当文件名用会 0/18 命中（实测 dgn6：852→`e817(1,2).map`、877→`h832(4,3).map`）。同理 `.skl`/`.mob`/`.equ` 的 id 都走各自 `.lst`/注册表 |
| G7 | ~~判定框几何只在 `.ani` 里~~ **已解** | 每帧 0x0E/0x0F 尾块 = 24B = 6×i32（相对 X/Y/Z + W/H/D）；`0x17` = flagIndex（i32）；`.act` 只给触发帧 |

---

## 四、里程碑

| 里程碑 | 内容 | 判定标准 |
|---|---|---|
| **M0** | 数据可见 | `export/text/` 能按目录浏览、能 grep、能按 ID 查 |
| **M1** | 设计体系 | 角色/技能/战斗/怪物四份文档 + 结构化 JSON |
| **M2** | 能动 | 引擎里一个角色在地图上跑跳、播放正确动画 |
| **M3** | 垂直切片 | 进副本 → 打怪 → 掉落 → 结算 → 回城 |
| **M4** | 可玩原型 | 3 职业 / 5 副本 / 装备成长闭环 |

---

## 五、当前进度

- **M0 已达成**：923MB `Script.pvf` → 1,460,792 个文件全部可见，0 个解码错误。
  - 文本 410,438 个（390MB 可读文本），二进制 1,050,354 个（.ani 原样保留）
  - 索引 + 57 个 `.lst` 注册表 + 165 万条 stringtable
  - 校验样例：`skill/swordman/armormasterycloth.skl` → 「布甲精通 / 裝備布甲系防具時，可以增加MP最大值…」；
    `stackable/lv105_equipment/6012124.stk` → 「[Lv.13]隱沒的邪念戒指 設計圖」，与官方代码表一致。
- 已完成：**P0.1 ~ P0.5、P0.7 ~ P0.9**；只剩 P0.6（NPK/IMG 图像解码）。
- 总览：`analysis/00-OVERVIEW.md`（数据一览）、`analysis/01-TAG-DICT.md`（标签语义）、`docs/REFGRAPH.md`（引用图）。
- 下一步：P0.5（ANI 解码，最大盲点）→ P0.6（NPK/IMG，要画面才有得看）→ P0.8（结构化导出）。

### P1 并行分工（AgentTeams 团队 `dnf-like`）

| 成员 | 负责 | 产出 |
|---|---|---|
| `ani-reverse` | .ani v6 二进制逆向 | `tools/ani_parser.py`、`docs/ANI-FORMAT.md`、`analysis/ani/` |
| `script-mechanics` | 脚本/UI/机制表达 | `analysis/09-script-mechanics.md` ✅ |
| `design-analyst` | 设计体系（职业/技能/战斗/怪物/道具/地图/任务） | `analysis/02`~`08` |
| `godot-scout` | 引擎可行性 | `docs/GODOT-EVAL.md` ✅ |
| `archivist` | 总纲与知识拓扑（只整合，不干新活） | `analysis/00-SYSTEM.md`、`docs/KB-INDEX.md` |
| lead（我） | 数据基建 + 交叉验证 + 排期 | `tools/*`、`export/_meta/*`、`docs/PVF-FORMAT.md`、`docs/REFGRAPH.md` |

### 格式与工程坑（已解决，记录备查）

1. **混合编码**：stringtable 里 Big5 繁体与 GBK 简体并存，必须逐串判别（`decode_any`）。
2. **stringtable 索引步长**：每串只占 1 个 u32 起始偏移（第 n 串 = `u32[n]..u32[n+1]`），
   误按 `n*8` 读会整体偏移一倍，而读出来**仍是通顺中文**，极难察觉。
3. **PVF 路径引用不是根相对**：大量写成 `../Animation/x.ani`，基准是「逻辑根」（如 `character/swordman/`）。
   只用根相对解析会有 48 万条 `.ani` 悬空；需「后缀匹配 + 同根优先」回退。
4. **不要一帧一文件 / 一文件一 JSON**：Godot 导入海量小文件是超线性的（5k 张 32s、20k 张 >5min）。
   P0.5 出「帧表」（已交付 `export/ani/`）、P0.6 出「图集 + 帧矩形」、P0.8 出「结构化数据集」（已交付 `export/structured/`）。
