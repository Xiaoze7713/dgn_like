# 老版 Squirrel（.nut）脚本在新版客户端里的去向

- 标题：Squirrel 脚本体系移除情况与新版的替代机制
- 研究者：DSH
- 日期：2026-11-15
- 任务 ID：T-20261115-001（草拟，待用户指派编号）
- 状态：草稿（待评审）
- 研究对象：国服客户端 `Script.pvf` 34.3.13.22（`dnf_latest/`，850,304,454 B）对比私服端 sf115 `Script.pvf`（923,262,293 B，fileVersion 53579）

## 问题与范围

问：老版用 Squirrel 写的 `.nut` 逻辑（每个技能的 `checkExecutableSkill` / `onSetState` / `sq_*` 引擎调用）在新版里确定没有了吗？如果没了，这些逻辑是被"优化"进了数据还是引擎？对新作复刻有什么影响。

包含：技能逻辑、appendage 逻辑、自定义装备逻辑的数据落点。排除：服务端逻辑、PVF 容器格式（另见 `docs/PVF-NEW-FORMAT-34.md`）。

## 方法与复现步骤

1. 解外层 + 建库（见 `docs/PVF-NEW-FORMAT-34.md`）：`tools/pvf_new_unwrap.py` → `tools/pvf_new_db.py` → `analysis/pvf-new/pvf34.sqlite`（6,288,780 条，解压后 7,142,625,379 B）。
2. 老端索引：`analysis/pvf/index/pvf-index.jsonl.gz`（sf115，1,460,792 条）；老端内容读取用 `PYTHONPATH=/tmp/shim` + `tools/pvf_loader.py`（`zhconv` 用 5 行 stub 顶替）。
3. 查询：`python3 tools/pvf_q.py find|grep|sql|cat`，或 web 工具 `bash tools/pvf_browser/start.sh`（http://127.0.0.1:8770）。
4. 关键统计：

   ```bash
   # 新版里有没有 .nut / sqr
   python3 tools/pvf_q.py sql "select count(*) from files where path like '%.nut' or path like '%sqr%'"        # => 0
   python3 tools/pvf_q.py sql "select count(*) from text where instr(body,'sq_')>0"                          # => 0
   # 唯一带 function 的文本
   python3 tools/pvf_q.py sql "select count(*) from text where instr(body,'function ')>0 and path like '%.lua'"  # => 4491
   ```

## 观察（可验证事实）

| # | 观察 | 证据 |
|---|---|---|
| O1 | 新版 PVF 里 **0 个** `.nut`、**0 个** `sqr/` 路径 | `files` 表 count = 0 |
| O2 | 新版正文里 **0 处** `sq_`、`checkExecutableSkill`、`CNSquirrelAppendage` | `text` 表（599,035 条文本）instr 全 0 |
| O3 | 新版唯一含 `function` 的文本文件是 **.lua：4,491 / 4,496**，全部是 AI 脚本 | `text` 表按后缀统计 |
| O4 | 老端 `.nut` 共 **2,489** 个：`sqr/character/atmage` 357、`atswordman` 249、`atpriest` 206、`sqr/custom/equipment` 190、`thief` 107、`gunner` 106、`sqr/monsters_appendage` 86 … | 老索引 |
| O5 | 老端 `.nut` 是命令式代码，例 `sqr/character/gunner/assault/activation/activation.nut`（2,188 B）含 `function checkExecutableSkill_Activation(obj)`、`obj.sq_IsUseSkill(SKILL_ACTIVATION)`、`obj.sq_AddSetStatePacket(STATE_ACTIVATION, STATE_PRIORITY_USER, true)`、`onSetState_Activation` → `obj.sq_SetCurrentAnimation(CUSTOM_ANI_ACTIVATIONCAST)` | 直接读取 |
| O6 | 同技能的 `checkCommandEnable_Activation` 里是手写状态白名单：`switch(state){ case STATE_STAND: case STATE_ATTACK: case STATE_DASH: return true; }` | 同上 |
| O7 | 新版同名技能 `skill/gunner/activation.skl`（2,359 B 文本）对应字段是 **`[executable states]` → `` `[stand]` `[attack]` `[dash]` ``**，与 O6 一一对应 | `tools/pvf_q.py cat` / web 工具 |
| O8 | 新版 `.skl` 是纯数据（258 种标签，无一行代码）：`[type] [active]`、`[cool time] 5000 5000`、`[start cool time]`、`[level info]`、`[attack list]`、`[damage group]`、`[multi hit]`、`[command]`、`[disable preset]`、`[buff tooltip]`、`[pvp]`、`[dungeon]` | `.skl` 文本统计 |
| O9 | 6,739 个 `.skl` 中：`[executable states]` 1,877、`[command]` 1,987、`[cool time]` 1,939、`[attack list]` 1,654、`[multi hit]` 930 | SQL |
| O10 | `.act`（`[TRIGGER]/[BEHAVIOR]/[MOTION]` 规则引擎）**老端就有**：老端 77,511 个 `.act`（monster 53,041 / passiveobject 24,107 / aicharacter 178 / ui 131…），新版 538,737 个（contents 241,008 / monster 134,979 / passiveobject 122,006 / live 36,964）。1,200 个新 monster `.act` 里 222 种标签（`SET SPEED`、`CREATE PASSIVEOBJECT`、`SET ATTACK ACTION`、`CHANGE ACTION FILE`、`SET TRIGGER ENABLE`、`COMPARE VAR`、`WARNING MARK`…），老端同样有 `SET SPEED`/`COMPARE VAR`/`CREATE PASSIVEOBJECT` | 两端解码对比 |
| O11 | 角色的 `.act` 两端都几乎没有：老端 `character/*.act` 只有 1 个，新版 0 个 | 两端统计 |
| O12 | 角色动画按**命名约定**组织：`character/gunner/animation/activationcast_body.ani`、`activationstart_body.ani`、`activationcast_body.[pvp].ani`；配套 `.als`（70–175 B）只做特效挂接：`[use animation]` + `[none effect add]` | 直接读取 |
| O13 | 新版字符串池 509,898,432 B / strA 0 B，文本全部走 `string/*.chn.str`（38 张，535 MB）；老端文本内联在数据里，`.chn.str` 只有 200 B 量级 | 两端对比 |
| O14 | `.lua` 4,496 个只在 AI 侧：`clientonly/lua/ai/` 框架 11 个 + `contents` 3,293 / `aicharacter` 427 / `monster` 380 / `live` 370 | 路径分布 |

## 推断（解释）

- **I1（高置信）Squirrel VM 已从客户端移除，不是"没导出"。** O1+O2+O3 三条独立证据同时成立：路径没了、正文里引擎 API 名 0 处、唯一保留的脚本语言是只用于 AI 的 Lua。
- **I2（高置信）老 `.nut` 的"决策"部分变成了 `.skl` 字段。** O6→O7 是同一技能同一逻辑的直接对应（手写状态白名单 → `[executable states]`）；O8/O9 说明这类字段被系统性铺开（约 1,900 个技能带这些字段）。同理 `[cool time]`/`[start cool time]`/`[attack list]`/`[damage group]`/`[multi hit]` 对应老 `.nut` 里手写的冷却、攻击信息与多段攻击。
- **I3（高置信）"动作/表现"部分回到引擎 + 命名约定。** 两端角色都没有 `.act`（O11），技能动画靠 `character/<job>/animation/<skill>*.ani`（O12）；老 `.nut` 里的 `sq_SetCurrentAnimation(CUSTOM_ANI_XXX)`、`sq_AddSetStatePacket(STATE_XXX)`、`sq_PlaySound` 在新版数据里找不到对应字段 ⇒ 状态机与动画选择由引擎按"技能 → 约定动画名"完成。
- **I4（中高置信）`.act`/`.als` 不是"逻辑被优化后的新家"。** 它们老端就有且形态相同（O10/O12），只是随内容扩张而增长（`.act` 77,511→538,737、`.als` 77,490→330,266）。把"逻辑搬家"归因给 `.act` 是错的——最初我也这么猜，被 O10 推翻。
- **I5（中置信）appendage / 自定义装备的脚本逻辑同样被移除**：`sqr/custom/equipment`（190 个 `.nut`）与 `sqr/monsters_appendage`（86 个）在新版无对应脚本，而 `.apd`/`.equ` 数据仍在。具体替代机制（引擎内置 or 数据字段）本轮未取证。
- **I6（待决策）** 对复刻而言，"技能行为"不再能从脚本直接读出：能读到参数与状态白名单，读不到"这个技能具体怎么动"。补齐只能靠 ①`.ani` 动画 + `.atk` 攻击盒自证、②`.rep` 录像当 oracle、③实测对照。

## 与新作设计的关系

- 原作观察：现代化版本把"每技能一段脚本"重构为"数据表 + 通用状态机"，代价是脚本可读性，收益是改技能不用改代码、版本间数据可比对。
- 可借鉴点（建议）：新作技能定义也走"数据（.skl 式）+ 引擎状态机（命名约定动画）"两层，避免每技能写一段命令式逻辑——与已确认的"技能树分层"（D-003）不冲突，但**不要把 DNF 的字段命名当成新作设计**。
- 不建议照搬：`[executable states]` 是 DNF 角色状态机（stand/attack/dash）耦合的产物，新作状态机不同则字段应重设计。
- 需要用户决定：新作是否保留"技能脚本层"（便于 mod/扩展）还是纯数据驱动。

## 结论与交接

- 结论：老版 `.nut`（Squirrel）在新版客户端被**整体移除**；"能不能用/什么时候能用/冷却/攻击参数"变成 `.skl` 数据字段，"怎么动/什么状态"由引擎 + 动画命名约定承担；`.act` 规则引擎是老机制，与本次移除无关。AI 是唯一还留有脚本（Lua）的部分。
- 建议后续任务：①把 `.skl` 字段做成结构化表（实现侧导入层可直接吃）；②针对 I5（appendage 逻辑去向）单独取证；③用 `.rep` 录像验证"引擎状态机假设"。
- 未解决问题：I6 的"技能动作读不全"；appendage 替代机制；SGM 的 sk.dat 钥匙链。
- 复核人/日期：待用户评审。
