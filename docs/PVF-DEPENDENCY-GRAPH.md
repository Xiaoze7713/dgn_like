# PVF 依赖图（P1）

> 目标：把 146 万个 PVF 条目之间的引用关系变成一张可查询的图，回答「这个技能/怪物/道具依赖哪些文件」。
> 工具：`tools/pvf_graph.py`（sqlite）。产物：`analysis/pvf/graph.sqlite`、`analysis/pvf/reports/dep-graph.md`、`analysis/pvf/reports/idmap.json`。
> 格式本身见 [PVF-FORMAT-BYTES.md](PVF-FORMAT-BYTES.md)。

## 0. 一句话结论

PVF 不是「一堆配置文件」，而是一张**有明确四层的依赖图**：注册表（`.lst`）→ 内容定义（`.chr/.mob/.equ/.stk/.map/.qst…`）→ 行为（`.act/.als/.ai`）→ 表现（`.ani` → `.img`）。全部 146 万条目里，**只有 39.9 万个 Document**（其余是 105.8 万 `.ani` + 2.6 千文本），而 Document 里的引用 **99.99% 是路径字符串**——也就是说，**关系是显式写死的，几乎不需要语义推断**。这是本次最重要的发现：复刻时可以先把图建出来，再按图施工。

## 1. 图规模（sf115 人造神，全量）

| 指标 | 数值 |
| --- | --- |
| 节点 | **1,460,792**（= PVF 全部条目） |
| 边 | **2,589,988** |
| 　├ `path` 边（文本里的相对/绝对路径） | 1,190,219 |
| 　├ `img` 边（`.ani` 资源表 → NPK 里的 `.img`） | 1,364,458 |
| 　└ `id` 边（整数 ID → `.lst` 注册表） | 35,311 |
| 注册表条目 | 171,325（58 个 `.lst`，最大 `equipment/equipment.lst` 102,330 条） |
| 断链（引用目标不存在） | 227,725 |
| 被引用的唯一 `.img` | **60,923** |
| 数据库大小 | 1.28 GB |

构建耗时：全量约 4 分钟（399,599 个 Document，1,827 docs/s）+ `.ani` 扫描 81 秒。

## 2. 反推出的四层架构

把边按「源后缀 → 目标后缀」聚合，层的边界就自己浮出来了：

| 源 | 目标 | 边数 | 含义 |
| --- | --- | --- | --- |
| `lst` | `equ`/`stk`/`obj`/`mob`/`map`/`skl`/`apd` | 106,484 / 28,017 / 18,293 / 3,550 / 3,211 / 2,968 / 1,863 | **注册表层**：ID → 定义文件 |
| `equ` | `img` / `lay` / `ani` | 206,363 / 165,708 / 7,911 | 装备：图标 + 外观层 + 动作 |
| `stk` | `img` | 88,233 | 道具图标 |
| `chr` | `ani` / `atk` | 4,143 / 1,512 | 角色：动作 + 攻击载荷 |
| `mob` | `ai` / `act` / `atk` / `ani` / `img` | 58,916 / 46,369 / 11,631 / 9,350 / 4,132 | **怪物：AI + 动作 + 攻击载荷** |
| `act` | `ani` / `ptl` / `act` / `atk` | 191,608 / 7,513 / 3,101 / 880 | **行为层**：动作 → 动画/粒子/子动作/伤害 |
| `als` | `ani` / `img` | 216,328 / 1,043 | 动作列表（`[use animation]`）→ 动画 |
| `map` | `ani` / `til` | 140,959 / 60,957 | 地图：装饰动画 + 图块 |
| `obj` | `act` / `atk` / `ani` / `ptl` | 38,012 / 11,390 / 11,699 / 1,712 | 机关物件 |
| `ani` | `img` | 1,034,774 | **表现层终点：动画 → 贴图** |
| `dgn` | `map` / `obj` | 10,215 / 5,785(id) | 地下城：房间 + 机关 |

一句话读法：**`.lst` 给 ID 找文件，`.chr/.mob/.equ` 描述"是什么"，`.act/.als/.ai` 描述"做什么"，`.ani` 描述"怎么动"，`.img` 是像素**。

## 3. 枢纽文件（复刻时第一批要看的）

**被引用最多（入度 Top 10）**

| 目标 | 入边 | 说明 |
| --- | --- | --- |
| `item/iconmark.img` | 73,550 | 全游戏道具图标总图集（**这就是 DNF 手工做的 atlas**） |
| `item/fieldimage.img` | 37,092 | 掉落物地面图标 |
| `equipment/character/mage.lay` | 28,631 | 法师装备外观层表 |
| `item/field_equip.img` | 19,158 | 地面装备图标 |
| `equipment/character/swordman.lay` | 17,160 | 剑士外观层表 |
| `equipment/character/gunner.lay` | 15,257 | |
| `equipment/character/fighter.lay` | 14,749 | |
| `equipment/character/priest.lay` | 14,046 | |
| `equipment/character/atfighter.lay` | 13,067 | 二觉职业各有独立 `.lay` |
| `equipment/character/dsswordman.lay` | 12,481 | |

> 含义：`.lay` 是「职业 → 各装备部位 → 图像坐标」的绑定表，是整个纸娃娃系统的核心；`iconmark.img` 这类大图集是 DNF 用「一个 `.img` 装几千个图标 + 帧索引」的方式手工做的 atlas，迁移时正好可以逐一换成 Godot 的 atlas。

**依赖最多（出度 Top）**：`equipment/equipment.lst` 102,330、`stackable/stackable.lst` 32,171、`passiveobject/passiveobject.lst` 17,691、`etc/skillpreload.etc` 9,701、`monster/monster.lst` 3,549、`map/map.lst` 3,211、`character/swordman/atswordman.chr` 1,013。

## 4. 字段 → 注册表（ID 边的推断结果）

ID 引用**不能**靠字符串匹配，必须知道「这个整数属于哪张表」。做法：对每个 `(后缀, 字段名)` 收集整数样本，与 50 张 `.lst` 的 id 集合比对命中率，再用「样本 ≥ 40 + 命中率 ≥ 90% + 与次优候选 margin ≥ 0.2 + 领域一致」过滤。

自动推断产出 2,078 组候选，但**绝大多数是噪声**——因为 `skill/*.lst`（4,000 个 id）和 `equipment/*.lst`（102,330 个 id）几乎覆盖了所有小整数，任何 `[level]`/`[index]` 都会"100% 命中"。人工核过、可信的是这 23 条：

| 源 | 字段 | → 注册表 | 命中率 | 边数 |
| --- | --- | --- | --- | --- |
| `.dgn` | `[map specification]` | `map/map.lst` | 2,945/3,040 | 9,643 |
| `.dgn` | `[pathgate object]` | `passiveobject/passiveobject.lst` | 848/897 | 5,785 |
| `.map` / `.wdm` | `[dungeon]` | `dungeon/dungeon.lst` | 556/566 | 5,289 |
| `.stk` / `.equ` | `[appendage]` | `appendage/appendage.lst` | 722/723 | 5,142 |
| `.qst` | `[npc index]` | `npc/npc.lst` | 133/133 | 3,722 |
| `.equ` | `[dungeon check]` | `dungeon/dungeon.lst` | 54/54 | 1,409 |
| `.qst` | `[complete npc index]` | `npc/npc.lst` | 99/99 | 825 |
| `.qst` | `[dungeon info]` | `dungeon/dungeon.lst` | 207/208 | 777 |
| `.dgn` | `[boss map specification]` | `map/map.lst` | 245/254 | 708 |
| `.equ` | `[creature species]` | `creature/creature.lst` | 539/543 | 681 |
| `.dgn` | `[seal door map index]` | `map/map.lst` | 73/73 | — |
| `.map` | `[heroes mode map index]` | `map/map.lst` | 51/51 | — |
| `.equ` | `[summon monster]` / `.obj [homing follow]` / `.etc [summon object]` | `monster/monster.lst` | 87/96 | 324 |
| `.shp` | `[npc]` | `npc/npc.lst` | 113/119 | 131 |
| `.skl` | `[usable passiveobject]` | `passiveobject/passiveobject.lst` | 41/41 | — |
| `.etc` | `[unable to quickparty]` / `[dungeon index]` | `dungeon/dungeon.lst` | 95–121/121 | 219 |
| `.evt` | `[unable dungeon]` | `dungeon/dungeon.lst` | 120/120 | 120 |
| `.rgn` | `[towns]` | `town/town.lst` | 42/42 | — |

映射清单存在 `analysis/pvf/reports/idmap-curated.json`，由 `pvf_graph.py idedges` 落成边（35,311 条）。

## 5. 断链（22.8 万条）是不是问题？

不是。按类型看：

| 目标后缀 | 断链数 | 真实原因 |
| --- | --- | --- |
| `.ani` | 209,894 | 多为 `(0824)crystal.ani`、`1.ani` 这类**其它版本/未启用内容**的引用；也有 `.ani` 在别的包里（客户端按包合并后的路径） |
| `.key` / `.ai` | 6,150 / 5,223 | `.key` 是按键映射老表，多数已废弃 |
| `.ptl` / `.equ` / `.act` / `.atk` | 2,293 / 1,210 / 1,145 / 709 | 版本差（sf115 引用了未随档的旧路径） |
| `.map` / `.til` / `.aic` / `.lua` / `.obj` | 459 / 292 / 134 / 68 / 53 | 同上 |

处理方式：**断链不阻断建模**，按「目标不存在就当空实现 / 记告警」处理即可。这也说明 PVF 是一个**长期热更过的库**，不是一次性生成的干净数据。

## 6. 查询手册

```bash
# 某文件依赖谁 / 被谁依赖
python3 tools/pvf_graph.py query analysis/pvf/graph.sqlite "monster/goblin/action/attack.act"

# 重建（4 分钟）
python3 tools/pvf_graph.py build "/mnt/e/dnf-sf/sf115/Script.pvf" analysis/pvf/graph.sqlite
python3 tools/pvf_graph.py ani   "/mnt/e/dnf-sf/sf115/Script.pvf" analysis/pvf/graph.sqlite
python3 tools/pvf_graph.py idedges "/mnt/e/dnf-sf/sf115/Script.pvf" analysis/pvf/graph.sqlite
python3 tools/pvf_graph.py report analysis/pvf/graph.sqlite analysis/pvf/reports/dep-graph.md

# 直接 SQL（很实用）
sqlite3 analysis/pvf/graph.sqlite "select dst from edge where src='character/swordman/swordman.chr'"
```

数据库结构：

```sql
node(path, ext, size, enc)          -- 146 万个条目（enc: doc/ani/text）
edge(src, dst, kind, field)         -- 259 万条边（kind: path/img/id）
reg(lst, id, target)                -- 17 万条 (注册表, ID) → 路径
missing(src, raw, cand, kind)       -- 22.8 万条断链
```

## 7. 这张图已经能回答的问题

- **技能**：`skl` → `img`（图标）8,008 条；技能的动作/伤害在 `.act` + `.atk` 里，`.chr [skill]` 是职业技能表。
- **怪物**：`mob` 平均 32 条出边，其中 AI 脚本（`.ai` 14.6 条/怪）+ 动作（`.act` 11.5 条/怪）+ 攻击载荷（`.atk` 2.9 条/怪）。
- **地图**：`map` 平均 34.8 条出边（图块 `.til` + 装饰动画 `.ani`），`dgn` 再组织成房间序列。
- **道具**：`.stk/.equ` → `img` 图标 + `apd`（appendage，buff/被动）→ 这就是「一个道具影响角色属性」的链路。
- **纸娃娃**：`equ` → `lay`（职业外观层）→ `act/ani`（动作）→ `img`。

## 8. 局限与下一步

1. **`.atk` 是叶子**（18,877 个，出边 0）——伤害数值全在里面，但「谁引用了哪个 `.atk`」才能反查；下一步要把 `mob/act/chr → atk` 的边按「技能/攻击编号」细化。
2. **`.qst` 也是叶子**（3,852 个）——任务奖励/条件靠 `[npc index]` 等 ID 边连出去，需要更多字段映射。
3. **`.nut`（Squirrel）不在这张图里**：它是技能逻辑代码，引用关系在代码里（`sq_*` API），需要静态分析才能建边。
4. **`.lua`（怪物 AI）114 个**，同理，靠代码里的路径字符串（`require("/ClientOnly/Lua/AI/AIBaseScripts.lua")`）。
5. 下一步 P2 垂直切片：拿 `swordman` + `goblin` 的这张子图，直接生成「一个能跑的最小战斗场景」所需的全部资源清单。
