# 新端（34.3.13.22）AI / 逻辑脚本架构

> 数据来源：`analysis/pvf-new/pvf34.sqlite`（6,288,780 条全量导出），`clientonly/lua/ai/*`、`monster/**.lua`、`contents/**.lua`。
> 结论先说：**AI 是数据驱动的 Lua 状态机，框架与全部枚举都随 PVF 一起发布**，复刻时不需要逆向 DNF.exe 就能把怪物行为跑起来。

## 1. 文件分布

| 位置 | 数量 | 说明 |
|---|---|---|
| `contents/<年份>/<内容包>/…/*.lua` | 3,293 | 新副本/军团本/新职业的怪 AI，按版本年份分目录 |
| `aicharacter/**/*.lua` | 427 | APC / 支援兵（AI 角色） |
| `monster/**/*.lua` | 380 | 老世界怪物 AI 残留 |
| `live/**/*.lua` | 370 | Live 内容（活动副本） |
| `clientonly/**/*.lua` | 26 | 其中 11 个是框架本体（下面详述），其余是 boss_spiderprince / metalgear / rockslotor 三个**完整怪物样例包**（.mob+.act+.ani+.atk+ai 全套，复刻时最值得抄） |
| 合计 | 4,496 | 老端是 114 个 `.lua` + 2,489 个 Squirrel `.nut`（已全部消失） |

框架文件（`clientonly/lua/ai/`）：

| 文件 | 大小（字节 / 字符） | 作用 |
|---|---|---|
| `AIBaseScripts.lua` | 1,000 / 499 | 入口：保存 `begin_pattern` 指针 + require 全部框架模块 |
| `AIBaseScriptsNew.lua` | 2,790 / 1,394 | 新一代替换入口（1,353 个 AI 引用它，旧入口 2,637 个） |
| `AIBridge.lua` | 3,108 / 1,553 | **引擎查询接口的空壳**（全部 `return true/false/0`，由引擎侧实现） |
| `AIStructures.lua` | 19,174 / 9,586 | 全部枚举：State / Buff / DestinationSelect / AIEvent / ObjectType… |
| `AIFSMBaseScript.lua` | 8,956 / 4,477 | 命令式状态机：`BindCommand/ChangeCommand/Init/Proc/Exit` + 15 个事件转发 |
| `AI_Idle_Responce.lua` | 7,318 / 3,658 | `Idle:` 命名空间实现（设动作、随机、状态判定） |
| `AI_Battle_Responce.lua` | 4,526 / 2,262 | `Battle:` 命名空间（技能 CD、血量、事件标志） |
| `AI_Patrol_Responce.lua` | 7,298 / 3,648 | `Patrol:` 命名空间（视野/攻击区判定） |
| `AI_Common_Responce.lua` | 12,332 / 6,165 | `Common:` 命名空间（随机、找位、墙体计数…） |
| `AI_Dead_Responce.lua` | 610 / 304 | `Dead:` |
| `AI_Pvp_Responce.lua` | 4,914 / 2,456 | `Pvp:` |
| `clientonly/lua/MinimumRequire.lua` / `Tester.lua` | 694 / 1,006 | 最小加载集 / 测试桩 |

> 注意：PVF 里 `.lua` 的 `dtype=3`，存的是 **UTF-16LE**，所以 `size` 字节数 ≈ 2×字符数。

## 2. 运行模型（可 1:1 复刻）

```
引擎每帧/每事件
  └─ 调 AIBaseScripts / AIFSMBaseScript 的顶层函数
       ├─ Init(filePath)        绑命令、进入 MoveCommand
       ├─ Proc()                每帧驱动 CurrentCommand.Proc()
       ├─ On* (15 个事件)        转发给 CurrentCommand.On*
       └─ AI 脚本的 begin_pattern()  被调用来"选下一步"
            └─ 读全局 MyInfo / EnemyInfo，写 MyInfo.nextAction / nextMoveMethod
                 └─ 引擎读取这两个字段执行动作
```

关键全局表（AI 脚本读写，引擎提供）：

- `MyInfo.ObjectInfo` — `hp / mp / state / level / x / y …`
- `MyInfo.nextAction` — **要执行的 action（技能）索引**，`Idle:setAction(n)` 就是 `MyInfo.nextAction = n`
- `MyInfo.nextMoveMethod` — `Idle:setMoveMethod(v)`
- `MyInfo.currentAIEventList[AIEvent.X]` — 当前事件标志位
- `EnemyInfo.targetObjectID` — 当前目标

事件回调（`AIFSMBaseScript.lua` 全量，共 15 个）：
`OnActionEnd(actionIndex)`、`OnChangeState(newState)`、`OnActionSkillEnd(actionIndex)`、`OnUseSkill()`、`OnAttack()`、`OnDamage()`、`OnMyDie()`、`OnChangeTargetHitable(bHitable)`、`OnWarningArea(bEnter)`、`OnTargetUseSkill(skillIndex)`、`OnResetComboDamage(damageType)`、`OnActiveStatus()`、`OnUseCubeSkill()`、`OnStartMap()`、`OnStartBattle()`。

## 3. 引擎桥（AIBridge，复刻时必须自己实现的部分）

`AIBridge.lua` 里只有空壳签名，语义由客户端实现；按签名可以确定引擎要提供的能力：

```
getObjectInfo(objectID)            -> {hp,mp,state,level,x,y,...}
isSkillCooltime(skillIndex)        isSkillUsable(skillIndex)
getNumberOfAttackArea(parameterTable)
isMyActiveStatus(type)             isTargetActiveStatus(type)
getDamageValue(compareValue)       inEnableAttackAction(actionIndex, triggerIndex)
inEnableCustomAction(actionIndex, triggerIndex)
isActionEnd()                      clearAction()
isBuff(buffIndex)                  getBuffCount(buffIndex)
getItemIndex(slotIndex)            useItem(slotIndex)
getNearItemCreateObjectIndex(xR,yR) getNearItemDropObjectIndex(xR,yR)
setForceTarget(targetId)           useUltimateSkill()
getDungeonStarLevel()              getDungeonStarLevelPlusDifficulty()
isNeutralizeRecoveryState()        isMovablePosX(x)
getMyWarlikeRange(low,high)        getMyVisionRange(low,high)
isSkillDifficulty(...)             setActionMove(...)
```

## 4. 枚举（直接抄表即可，出自 `AIStructures.lua`）

**State**：`0 STAND / 1 SIT / 2 SIT_FOREVER / 3 DAMAGE / 4 DOWN / 5 DIE / 6 JUMP / 7 JUMP_ATTACK / 8 ATTACK / 9 HOLD`

**ObjectType**：`character / monster / passiveObj / player / none`
**ObjectGroup**：`enemy / neutral / friend / all`
**DifficultType**：`normal / expert / master / king / slayer`

**DestinationSelect**（走位策略，`Common:setDestinationSelect` 的取值）：
`0 CHASE, 1 KEEP_DISTANC, 2 RUNAWAY, 3 SPIN_AROUND, 4 ROVE, 5 CHASE_FRIEND_CHARACTER, 6 CHASE_TARGET_MONSTER, 7 SPIN_AROUND_FRIEND_CHARACTER, 8 SPIN_AROUND_FRIEND_OBJECT, 9 SPIN_AROUND_TARGET_MONSTER, 10 CHASE_ROUNDABOUT, 11 KEEP_DISTANCE_EXPAND, 12 CHASE_OBJECT, 13 CHASE_FRIEND_MONSTER, 19 CHASE_OBJECT_BACK, 20 AVOID_FRONT_FACE, 21 EVADE_FURTIVELY, 22 MOVE_ZIGZAG, 23 BE_SCATTERED, 24 JOIN_EFFORTS, 25 HIDE_BACK, 26 QUICKSTEP, 27 RUNAWAY_AND_EVADE, 28 ESCAPE_WALL, 29-35 *_TARGET_POSITION 系列, 36 CHASE_FRIEND_OBJECT, 37 CHASE_TARGET_APC, 39 CHASE_AGRO_TARGET, 44 MOVE_TO_DESTINATION, 46 CHASE_GROUP_LEADER, 100 EVADE_FURTIVELY_EXPAND`

**Buff**（按职业分段编号，`AIBridge:isBuff` 的参数）：`0-7` 通用（FRENZY/DOT_AREA/WAVEMARK/GHOSTSTEP/KALLA/…），`100-106` 增益（SUPERARMOR/MUSCLESHIFT/DEFINITE_GRAB/NEN_MONSTER_WHITE_TIGER/SPIRAL_NEN/…），`200-215` 枪手，`300-309` 召唤，`400-404` 圣职者，`600-607` 死灵/魔道，`700-715` 盗贼系，`800-813` 元素/鬼剑，`1100-1102` 剑魂，`1200-1221` 圣骑士，`1300`，`1400-1408` 圣骑士光环。

## 5. 一个真实怪物 AI（`monster/kcontents2/siroco_raid_challenge/phase1/named/raina/ai/action.lua`）

```lua
local L = {};
require("/ClientOnly/Lua/AI/AIBaseScripts.lua");
function L.begin_pattern()
    if Patrol:isTargetAttackArea(250, 100, 100, 100) then
        if Common:getrandomIsPercent(40) then
            if Battle:isSkillCooltime(0) == false then Idle:setAction(0); return end
        end
        ... 依次 40% 概率尝试 skill 0/1/2/3/42/10/12/9/32/39，最后 99% 尝试 7
    else
        ... 目标不在攻击区时的走位/等待分支
```

模式非常统一：**优先队列 + 概率门 + CD 检查 + `Idle:setAction(技能索引)`**，技能索引即 `setAction` 参数（对应怪物 `.mob`/`.act` 里的 action 列表）。→ 只要实现 `Patrol/Battle/Common/Idle` 四个命名空间与 `MyInfo/EnemyInfo`，这些 AI 文件可以**原样运行**。

## 6. 旧式 `.ai` 行为树（24,644 个，已全部解码成可读文本）

新端怪物 AI **不止 Lua**：`.ai` 有 24,644 个，和 `.lua` 并存。`.ai` 也是 dtype=1 的 token 流，解出来是一棵带控制词的**可读行为树**，不需要任何反编译：

```
[ai pattern]
    [think] [void] `is target in attack area()` 150.00 30.00 20.00 20.00
        [true]  [think] [void] `is the skill in cooltime()` 1
                    [true]  [return] -1
                    [false] [return] 1
                [/think]
        [false] ...
    [/think]
[/ai pattern]
```

- 控制词（实测统计，全量 24,644 个文件的词表在 `analysis/pvf-new/ai-legacy-census.json`）：
  `[ai pattern] / [/ai pattern]`、`[think] / [/think]`、`[true] / [false]`、`[return]`、`[return str]`、`[void]`、`[last result]`、`[import ai] / [import ai ex]`、`[hp]`、`[mp]`、`[my state]`、`[target state]`、`[my level]`、`[my attack]`、`[target distance]`、`[hit]`、`[state]`、`[command]`、`[set agro]`、`[set bound]`、`[set target monster/character/position/party member/friend object]`、`[check use skill]`、`[check skill on]`、`[check key cooltime]`、`[check item slot cooltime]`、`[check party buff on]`、`[skill cooltime correction]`、`[cube item number]`、`[attack success]`、`[my hp down]`、`[my active status]`、`[party member hp]`、`[ai think]`、`[second type]`、`[summon]`、`[monster]`、`[passive object]`
- 命令名（2181 种，top）：`is the skill in cooltime()`、`is target in attack area()`、`check random()`、`get random()`、`number of in attack area()`、`enemy number of in attack area()`、`is attack action enable()`、比较符 `<=' '>=' '%<=' '%>=' '=='`。
- 已全量导出到 **`analysis/pvf-new/ai-legacy/`**（24,644 个 `.ai` → 文本，按原路径分目录），`tools/pvf_ai_dump.py` 可重跑。

⇒ 也就是**两代 AI 都是人可读的**：`.ai` 是词条式行为树（早），`.lua` 是脚本状态机（新）。老副本与老怪基本还是 `.ai`，新副本走 `.lua`。

## 7. 其他逻辑型数据（新端独有，也在 PVF 里）

| 路径 | 大小 | 内容 |
|---|---|---|
| `clientonly/dropinfo/(r)dropinfo.db` | 100,204,549 B | 掉落表（新端改为 db 文件） |
| `clientonly/skilltree/<job>_sp.co` / `_tp.co` | 每职业各一份 | 技能树（SP/TP） |
| `clientonly/cancelskilllist.co` | 4,815 B | 技能取消表 |
| `clientonly/townmappath.co` | 6,250 B | 城镇寻路 |
| `clientonly/hotkeysystem_ver3.co` | 7,345 B | 快捷键系统 v3 |
| `clientonly/partsetequipmentindexlist.co` | 1,576,845 B | 套装索引 |
| `clientonly/skillreplay/*.co` | — | 技能演示回放 |
| `string/*.chn.str` | 38 张 / 535 MB | 全部游戏文本（UTF-16，`key>文本`） |

## 8. 复刻路径建议

0. **直接抄三个完整样例包**：`clientonly/lua/boss_spiderprince/`（`.mob` + `.act` + `.ani` + `.atk` + ai 全套）、`metalgear`、`powerstation/rockslotor` —— 一个怪从上场到技能判定的所有文件都在，且都不大。
1. **先抄表**：把 `.equ/.stk/.skl/.mob/.act/.ani` 这些标签式脚本按 tag 解析成结构化数据（tag 名自带语义，已实测与老端同构）。
2. **实现 AIBridge + MyInfo/EnemyInfo**，直接执行 `clientonly/lua/ai/*` 与怪物 `*.lua`，怪物行为就等于官方行为。
3. **用 `.rep` 录像（客户端里 5,833 个）做回归 oracle**：回放输入流比对战斗数值，比逆向 exe 便宜一个数量级。
4. 剩下真正需要引擎语义的部分（伤害公式、硬直、浮空、抓取判定）在 `.act/.atk/.equ` 的 tag 里有大量显式参数，缺的部分用录像反推。
