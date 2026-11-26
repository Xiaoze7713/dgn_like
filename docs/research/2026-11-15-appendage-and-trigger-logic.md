# Appendage（附魔/装备特效）逻辑在新版客户端里的落点

- 标题：Squirrel appendage 钩子消失后，特效逻辑由什么承载
- 研究者：DSH
- 日期：2026-11-15
- 任务 ID：T-20261115-002（草拟，待用户指派编号）
- 状态：草稿（待评审）
- 前一份：`2026-11-15-squirrel-removal.md`（Squirrel 整体移除的结论）

## 问题与范围

问：老版 `sqr/custom/equipment/appendage/*.nut`、`sqr/monsters_appendage/*.nut` 里的钩子逻辑（`onStart` / `proc` / `onEnd` / `getImmuneTypeDamageRate` 等）在新版里由什么承载？入口是不是被 DNF.exe 收走了？

范围：装备/道具的 appendage 触发、appendage 数据本体、appendage id 注册表。不含：技能本体逻辑（见 squirrel-removal 报告）、服务端。

## 方法与复现步骤

1. 新版查询：`python3 tools/pvf_q.py sql "…"` 或桌面阅读器 `tools/pvf_studio/pvf_studio.py`（图形界面，左树右文，支持 `<N::key>` 还原中文）。
2. 老版取样：`PYTHONPATH=/tmp/shim python3 -c "import sys;sys.path.insert(0,'tools');import pvf_loader as L;pvf=L.load_pvf('/mnt/e/dnf-sf/sf115/Script.pvf');print(L.read_raw(pvf,'<path>')[:400])"`。
3. 标签普查：对 `.equ` 随机抽 1,500 个（`random.seed(11)`）解码，用正则切 `[if]…[/if][then]…[/then]` 块，统计块内标签。
4. 同路径对比：老索引里有、新版也存在的 `.equ` 共 **78,474** 个（老 104,480 / 新 383,719）。

## 观察（可验证事实）

| # | 观察 | 证据 |
|---|---|---|
| A1 | 新版 `.apd`（appendage 数据）**10,301** 个，老版 3,382 个；新版分布 `appendage/` 10,010 / `live/` 180 / `contents/` 111 | 两端统计 |
| A2 | `.apd` 是纯声明式数据，标签只有 57 种核心项：`[type]`（如 `skill data up`）、`[duration]`、`[buff]`、`[icon image]`、`[max overlap]`、`[int data]`、`[float data]`、`[string data]`、`[target]`、`[create limit count]`、`[effect animation]`、`[renewal appendage]`、`[create appendage event]`、`[new random option appendage]`…，**没有任何一行代码** | 2,500 个 `.apd` 标签普查 |
| A3 | appendage 的数字 id 由 **`list/appendage.lst`** 注册映射到 `.apd` 路径，例：`2102` → `Appendage/equipment/100Lv_Epic/armor/Tropical/Tropica_Dragon_fruit_attack_….apd`；该表 83 万字符 / 96,250 B | 解码 `list/appendage.lst` |
| A4 | **老 `.equ` 里没有触发块**：取样 400 个 + 随机 60 个老 `.equ`，`[if]` 出现 **0 次**，连 "appendage" 这个词都 **0 次** | 老端读取 |
| A5 | **新 `.equ` 里出现了声明式触发器**。1,500 个随机 `.equ` 中 174 个（**11.6%**）带 `[if]`，共 373 个 `[if]…[/if][then]…[/then]` 块 | 统计 |
| A6 | 触发条件词汇（出现次数）：`time` 304、`stat change` 136、`cooltime` 61、`attack success` 40、`my appendage` 11、`not my appendage` 9、`character` 9、`module` 9、`casting` 8、`remove equip` 7、`event use skill` 5、`cooltime group` 5、`set my state` 4、`target state by skill index` 4 | 同上 |
| A7 | 触发动作词汇：`target` 372、`equipment duration` 322、`stat by condition` 225、`unique stat by condition` 94、`stat` 86、`appendage` 65、`probability` 49、`add absolute damage buff` 38、`duration` 31、`remove appendage` 15、`active status` 13、`temporary type buff` 13、`passive object` 9、`appendage control` 7 | 同上 |
| A8 | 一个完整实例（`equipment/character/common/jacket/larmor/100070703.equ`，新旧同路径）：新版有 `[cool time] 10000` → `[if]` `[not my appendage] 2100` + `[attack success] 1` + `[cooltime] 30000` `[/if]` → `[then]` `[probability] 3` `[target] \`myself\` -1` `[equipment duration] 20000` `[appendage] 2102` `[appendage] 2099` `[remove appendage] 2101` `[/then]`；老版同路径没有任何这类块 | 两端读取 |
| A9 | 老 `.nut` 的 appendage 钩子形态（实例 `sqr/custom/equipment/appendage/earring/ap_earring_100390753.nut`，376 B）：`sq_AddFunctionName("onStart", …)` / `("proc", …)` / `("onEnd", …)` / `("getImmuneTypeDamageRate", …)` | 老端读取 |
| A10 | 新版全文里 **没有** `[script]` 这种标签（`text` 表 0 命中）；`.apd` 里只剩一个历史命名残留 `[force script duration]`（26 次），语义是"强制持续时间"，不是脚本 | 查询 + 普查 |
| A11 | `.stk`（可堆叠道具）里也有触发器：199,043 个 `.stk` 中 **513** 个带 `[if]` | 查询 |
| A12 | `.skl`（技能）**0 个**带 `[if]`（6,739 个全查） | 查询 |

## 推断（解释）

- **B1（高置信）appendage 的"数据"没变，变的只是"谁来决定什么时候挂上"。** 数据仍是 `.apd` + `list/appendage.lst` 的 id 注册表（A1/A2/A3），这是祖传机制；老版靠 Squirrel 钩子（A9）在运行时决定，新版靠 `.equ`/`.stk` 里的 `[if]/[then]` 声明式触发器（A5–A8）决定。
- **B2（高置信）入口在数据里，不在 DNF.exe 里。** 因为触发条件（`[attack success]`、`[cooltime]`、`[not my appendage]`、`[stat change]`、`[probability]`）与动作（`[appendage]`、`[remove appendage]`、`[stat by condition]`、`[passive object]`）都是数据标签（A6/A7），读出来就能照做；不需要逆加壳的客户端。
- **B3（中高置信）老 `.nut` 里的 `getImmuneTypeDamageRate`、`proc` 这类"逐帧/受击时算一遍"的行为，被引擎内置语义 + `.apd` 字段（`[int data]`/`[float data]`/`[target]`/`[buff]`/`[renewal appendage]`）吸收。** 依据：新版 appendage 数据里没有表达式/脚本字段（A2/A10），但触发侧能表达"每 3 秒挂一次"（A8 的 `[time] 3000 1 0`），说明定周期行为改由数据 + 引擎时钟承担。
- **B4（中置信）`.equ` 之外的"自定义装备逻辑"（老 `sqr/custom/equipment/` 下 190 个 `.nut`）同理落在 `.equ` 的触发器里**；但老端 190 个只是**少数特例**——老端 104,480 个 `.equ` 里只有 190 个配了脚本，说明绝大多数装备本来就不需要脚本；新版把这 190 个特例也数据化了（A5 的 11.6% 是新增能力的扩散，不只是迁移）。
- **B5（待决策）** 需要用户确认：新作要不要这种 `[if]/[then]` 触发器 DSL？它的优点是 mod 友好、可版本比对；缺点是没有循环与局部变量，复杂行为写不出来（DNF 自己也在 `.act` 里补了更细的规则引擎）。

## 与新作设计的关系

- 原作观察：DNF 把"每件装备一条脚脚本"换成了"数据触发器 + 引擎动作库"。这跟已确认的"装备 16 槽位 + 威能可收藏/镶嵌可替换 + 装备资格与威能激活分离"（D-004/D-005）是同一类取舍：把行为收敛到有限动作集，换来可控的数值与版本管理。
- 可借鉴点（建议）：新作的"威能/词条触发"用有限触发器 DSL（条件集 + 动作集）而不是脚本；动作集里至少要包含 DNF 这几种：给自身/目标挂状态、按条件改数值、召唤物（`[passive object]`）、概率（`[probability]`）、持续时间（`[duration]`/`[equipment duration]`）。
- 不建议照搬：DNF 的 `[appendage]` 数字 id + `.lst` 注册表（要维护两处一致，容易对不上）；新作直接用资源引用即可。
- 需要用户决定：触发器 DSL 的边界（是否允许"每 N 秒"这类时钟条件、是否允许嵌套 `[if]`）。

## 结论与交接

- 结论：**appendage 逻辑没被 DNF.exe 收走**——它变成了 `.equ`/`.stk` 里的 `[if]/[then]` 触发器 + `.apd` 数据 + `list/appendage.lst` 的 id 注册表。Squirrel 钩子（`onStart`/`proc`/`onEnd`）在新版没有对应物，语义由引擎动作库承担。
- 建议后续任务：①把 `.equ` 的 `[if]/[then]` 结构化成表（条件/动作/数值三元组），这是复刻"装备特效"最直接的输入；②统计 `.stk` 那 513 个触发器（道具类特效）；③`[stat by condition]` / `[unique stat by condition]` 的数值语义要在 `.equ` 与 `.apd` 之间对一对。
- 未解决问题：`.apd` 的 `[string data]` 里那串 `[at fighter] … [level] … %` 的编码规则（技能等级区间加成）还没拆到底；`[passive object]` 动作与 `.act` 规则的衔接点未取证。
- 复核人/日期：待用户评审。
