# 09 · 动作脚本与 UI 的机制表达（.act / .als / .nut / .ui）

> 目标：回答「DNF 的机制是如何**仅通过 PVF 里的文本数据**实现的」——不看美术，只看逻辑、脚本与联动。
> 所有结论附 `文件路径:行号` 或原文片段；无法从 PVF 闭环的标 **【待验证】**。
> 数据基线：`data/Script.pvf`（格式版本 53579，1,460,792 文件），文本树 `export/text/`，索引 `export/_meta/index.sqlite`。

---

## 0. 一句话结论

DNF 的「非素材逻辑」被切成**四层**，每层用不同文件表达，层间靠**整数 id / 数组下标 / 命名约定**接线：

| 层 | 文件 | 表达什么 | 谁执行 |
|---|---|---|---|
| 实体声明 | `.mob` `.obj` `.chr` `.skl` `.apd` | 这个实体有哪些动作槽、攻击属性、数值 | 引擎读表 |
| 动作编排 | `.act`（怪物/物件）/ `.nut`（角色） | 第几帧做什么：生成对象、切动作、开关判定框 | 引擎解释 / Squirrel VM |
| 判定与伤害属性 | `.atk`（属性）+ **`.ani` 帧内嵌判定框** | 打不打得到、打到了什么反应 | 引擎 |
| 表现 | `.ani` `.als` | 帧序列、多层动画别名 | 引擎 |

**最关键的发现（决定后续实现方式）**：
1. **`[USE SKILL]` 这个标签在 1,460,792 个文件里出现 0 次**（`grep -rl '\[USE SKILL\]' export/text` 命中 0）。真正「放技能」在数据层是 `[SET ACTION] [ATTACK] n [NOW]`（怪物）或 `.nut` 里 `sq_AddSetStatePacket`（角色）。
2. **角色不用 `.act`**。全库 `character/` 下只有 1 个 `.act`（`character/common/action/booster_particle.act`，140 字节，只有 `[MOTION]/[BASE ANI]/[SUB ANI]`）。角色的动作编排全部在 **Squirrel 回调函数**里，`stateId → .nut` 的映射由 `*_load_state.nut` 的 `pushState(...)` 注册。
3. **判定框几何不在 `.atk` 里**。`.atk` 只有「伤害属性」（`[push aside] 30`、`[lift up] 75` 之类），没有任何 x/y/w/h。框几何在**二进制 `.ani` 帧数据**中（`docs/PVF-FORMAT.md` 记为版本 6，未解析）。`.act` 只能 `[SET DAMAGE BOX] [ON]` / `[ATTACKRECT] [RESET]` 开关它。
4. **战斗 HUD 不是 `.ui`**，是 `sqr/init_character.nut` 里的**常量像素坐标**（`sq_set_hp_pos(224,533)` …）。`.ui` 只负责城镇/系统窗口的**摆位**，控件句柄由客户端 C++ 结构体提供。
5. **结算界面完全硬编码**：`ui/result/` 有 0 个 `.ui`、11 个 `.act` + 一堆 `.ani`；全库 grep `IDC_RESULT|result_rank|RESULT_RANK` 命中 0。PVF 只给它提供装饰动画。

---

## 1. `.act` 动作脚本

### 1.1 规模与分布

77,511 个 `.act`，按根目录：

| 根 | 数量 | 说明 |
|---|---|---|
| monster | 53,041 | 怪物动作（主战场） |
| passiveobject | 24,107 | 物件/弹道/特效物件动作 |
| aicharacter | 178 | APC（NPC 队友） |
| ui | 131 | UI 装饰动画（含 `ui/result/result_admission0..10.act`） |
| map | 17 | 地图机关 |
| creature | 17 | 宠物 |
| worldmap | 10 | 世界地图 |
| npc | 9 | — |
| **character** | **1** | 只有 `character/common/action/booster_particle.act`（140 字节） |

> 证据：`export/_meta/index.sqlite` 按 `ext='act'` 分组统计；`character` 的那一条即 `export/text/character/common/action/booster_particle.act.txt`，全文只有 `[MOTION]` / `[BASE ANI] ../Animation/booster_particle_0.ani` / `[SUB ANI] ../Animation/booster_particle_1.ani 0 1`。
> 最大 `.act`：`export/text/monster/meisterlaboratory/monster/2phase/identitat/monster/metalgear/action/lv_0.act.txt`，33,892 字节。

### 1.2 语法模型：章（section）+ 编号实例

`.act` 是缩进敏感的**标签流**，不是 INI：

```
[章名]              ← 顶格；章名全大写、可含空格
    [字段] 值 ...   ← 缩进（1 个 tab 或 4 空格）
[章名]-N            ← 同一章的第 N+1 个实例（从 -1 开始编号）
```

三类章：

| 章 | 作用 | 典型字段 |
|---|---|---|
| `[MOTION]` | 声明本动作由哪些动画组成 | `[BASE ANI] <path>`、`[SUB ANI] <path> <x> <aliasIdx> …`、`[SOUND] <name> <frame> …`、`[LAYER]` |
| `[TRIGGER]` | 「在什么时机、满足什么条件」 | `[FRAME] a b`、`[FRAME JUST] n`、`[ON SET ACTION]`/`[ON END ACTION]`/`[ON END ANIMATION]`/`[ON ATTACKSUCCESS]`、`[ENABLE] [ON\|OFF]`、`[WHICH]`、`[CHECKUP]…[/CHECKUP]`、`[CHECKED NO]`、`[FILTER VAR]`/`[COMPARE VAR]`/`[UPDATE VAR]`/`[CREATE VAR]`、`[BEGIN IF]`/`[ELSE IF]`/`[ELSE]`/`[END IF]`、`[DO BEHAVIOR]` |
| `[BEHAVIOR]` | 真正干活的指令序列 | `[SET ACTION]`、`[CREATE PASSIVEOBJECT]`、`[PLAY SOUND]`、`[SET DAMAGE BOX]`、`[ATTACKRECT]`、`[TELEPORT]`、`[MOVE ME]`、`[SHAKING]`、`[FLASH SCREEN]`、`[CHANGE ACTION FILE]`、`[APPENDAGE]`、`[DESTROY]` |

**编号即引用**——这是 `.act` 唯一的「控制流」：
- `[TRIGGER]-3` 是第 4 个触发条件。
- `[BEHAVIOR]-3` 是第 4 个行为块。
- `[DO BEHAVIOR] [ME] 3` = 对**自己**执行 `[BEHAVIOR]-3`。
- `[DO BEHAVIOR] [CHECKUP OBJECT] 3` = 对**`[CHECKUP]` 查出来的每个对象**执行 `[BEHAVIOR]-3`。
- `[TRIGGER] 8 [ON]` / `[TRIGGER] 8 [OFF]` = **动态启停另一个 trigger**（自修改行为表）。

全语料（`export/text/monster/**/*.act.txt`，52,847 个文件）标签频次前 40：

```
[TRIGGER]145638 [DO BEHAVIOR]130191 [BEHAVIOR]125030 [FRAME]66892
[MOTION]52217 [BASE ANI]52211 [POS]50649 [INDEX]39628 [LEVEL]38439
[CREATE PASSIVEOBJECT]37217 [SUB ANI]26873 [ADD ANIMATION EX]6262
[GET TARGET]4388 [PLAY SOUND]3880 [ELSE IF]3797
[INTERPOLATION MOVE TARGET]3327 [RANDOM SELECT]3245 [BEGIN IF]3222
[CHANGE ACTION FILE]3068 [TELEPORT]2641 [ATTACKRECT]2446
[ON ATTACKSUCCESS]2396 [SET TOP PARENT]2228 [FLASH SCREEN]2216
[MOVE ME]2153 [DUNGEON SYMBOL SET]1826 [IGNORE HIT STUN]1821
[ENABLE] [SUB ANI FLAG]1214 [ON END ANIMATION]714 [ADD ANIMATION]383
[CHANGE BASE ANIMATION]297 [CHANGE SUB ANIMATION]195 [PLAY ANIMATION]188
[DELETE ANIMATION OBJECT]186 [PLAY ANIMATION TARGET]148 [SUB ANI VISIBLE]110
```

> 注意：`.act` 内标签**全大写**；`.atk`/`.skl`/`.map`/`.dgn` 内标签**全小写**。grep 必须区分大小写，否则一半标签查不到。

### 1.3 `.act` 与 `.mob` 的接线：动作槽表

怪物不是「按名字找动作」，而是 `.mob` 里给出一组**具名槽位**，槽位内是 `.act` 路径；`[SET ACTION]` 用槽名 + **数组下标**寻址。

`export/text/monster/poongjintrainingroom/sarpoza/sarpoza.mob.txt`：

```
69:[come in action]      Action/Incomming_ETC.act 1000 500   ← 出场动作 + 时长 + 淡入
71:[waiting action]      Action/1Stay.act                    ← 待机
73:[move action]         Action/1Move.act                    ← 移动
75:[damage action 1]     Action/1Damage0.act                 ← 受击 1
77:[damage action 2]     Action/1Damage1.act                 ← 受击 2
79:[attack action]       44 条 .act 的有序数组               ← 攻击动作池
81:[etc action]          其它动作
83:[last action]         Action/1Last.act                    ← 死亡
85:[proc action]         Action/Proc.act                     ← 每帧/后台动作
87:[attack info]         11 条 .atk 的有序数组               ← 攻击属性池
89:[etc attack info]     其它攻击属性
97:[ai pattern]          [normal]/[expert]/[master]/[king]/[slayer] 各 4 个 .ai
```

于是 `.act`/`.nut` 里的 `[SET ACTION]` 参数与槽位一一对应：

| 指令 | 语义 |
|---|---|
| `[SET ACTION] [ATTACK] 12 [NOW]` | 切到「攻击槽第 12 个 .act」，立即生效 |
| `[SET ACTION] [CUSTOM] 11 [NOW]` | 切到自定义动作 11（语义由数据约定，非引擎） |
| `[SET ACTION] [STAY]` / `[MOVE]` / `[DAMAGE]` / `[DAMAGE] 1` / `[LAST]` | 切到上面的具名槽 |
| `[CHANGE ACTION FILE]` 内的 `[STAY] [MOVE] [DAMAGE] [DAMAGE]-1 [LAST]` | 换掉**整张动作槽表**（变身/换阶段） |

> 证据：`export/text/monster/poongjintrainingroom/sarpoza/action/change.act.txt:24-42` 的 `[CHANGE ACTION FILE]` 子标签就是槽名；`export/text/monster/poongjintrainingroom/rosaura/action/attack_10.act.txt:13-19` 是 `[BEHAVIOR]`/`[SET ACTION]`/`[ATTACK] 12`/`[NOW]`。

### 1.4 逐行例子 A：`monster/championtower/saya/action/attack_9.act`（34 行，最简完整链）

文件：`export/text/monster/championtower/saya/action/attack_9.act.txt`

```
 1 [MOTION]
 2     [BASE ANI]
 3         ../Animation/Attack_9_0.ani                  ← 主体动画
 4     [SUB ANI]
 5         ../Animation/Attack_9_1.ani 0 1              ← 副层动画，别名索引 1
 6         ../Animation/Attack_9_2.ani 0 2              ← 副层动画，别名索引 2
 7     [SOUND]  SAYA_BLIZZARD 0  SAYA_ICEMENTLE_ROLL 7  SAYA_SKILL_01_1 7
                                                       ← 第 0/7/7 帧播音效
 8 [TRIGGER]
 9     [FRAME]
10         0 0                                        ← 只在第 0 帧
11     [DO BEHAVIOR]
12         
13     [ME]
14         0                                          ← 对自己执行 BEHAVIOR #0（空，占位）
15 [BEHAVIOR]
16     
17 [TRIGGER]-1                                           ← 第 2 个触发器
18     [FRAME] 4 4                                        ← 第 4 帧
19     [WHICH] [CHARACTER]                                ← 对象=场上所有角色
20     [CHECKUP] [CHECKED NO] [=>] 0 [/CHECKUP]           ← 命中数 ≥ 0（即只要存在）
21     [DO BEHAVIOR] [CHECKUP OBJECT] 1                   ← 对每个命中的角色执行 BEHAVIOR-1
22 [BEHAVIOR]-1
23     [CREATE PASSIVEOBJECT] [INDEX] 74068 [LEVEL] -1 [POS] 545 472 0
                                                       ← 生成被动对象 74068（冰风）
24-32 [TRIGGER]-2/3/4  [FRAME] 7/9/11  →  [DO BEHAVIOR] [ME] 2
                                                       ← 第 7/9/11 帧再各打一次
33 [BEHAVIOR]-2
34     [SHAKING] 2 1000                                  ← 屏幕震 2px × 1s
```

`74068` 在 `export/_meta/lst/passiveobject__passiveobject.lst.tsv` 里是
`ActionObject/Monster/Guild_dungeon/Saya/Ice_Wind/Ice_Wind.obj` —— **和 Saya 的冰风技能语义吻合**，说明 `[INDEX]` 就是全局 passiveobject id。

**这条链解释了「判定框从哪来」的一半**：`.act` 不产生伤害，它只生成**被动对象**；被动对象自己的 `.obj` 指定动画与 `.atk`，命中判定挂在该对象的帧上。

### 1.5 逐行例子 B：`monster/bakalraid/monster/steich/action/attack_7.act`（73 行，完整战术动作）

文件：`export/text/monster/bakalraid/monster/steich/action/attack_7.act.txt`

```
 1-7  [MOTION] [BASE ANI] ../Animation/Attack_07/A07_01_SpearAttack.ani
      [SUB ANI] 10 条（别名 0..9）  [SOUND] 5 条
 8-26 默认 [TRIGGER]（FRAME 0 0，空 BEHAVIOR）—— 全部字段都被列出来当模板

28   [ON SET ACTION] [WHICH] [PLAYER] [CHECKED NO] [>] 0
       [FILTER VAR] [==] [CHECKED NO] [>] 0              ← 有玩家、且变量过滤通过
       [BEGIN IF] [COMPARE VAR] [>]                       ← 内联 if
         [UPDATE VAR] ATK7_GET_TARGET_OFFSET_RIGHT        ← 往右记录目标偏移
       [ELSE] [UPDATE VAR] ATK7_GET_TARGET_OFFSET_LEFT
       [END IF]
       [DO BEHAVIOR] [CHECKUP OBJECT] 0                   ← 对命中对象执行 BEHAVIOR

29-39 [BEHAVIOR]
        [CREATE PASSIVEOBJECT] [INDEX] 109084869 [LEVEL] 0
        [POS] TARGET TARGET 0 TARGET 0                   ← 用「目标坐标」当生成位置
        [SET TOP PARENT]                                 ← 层级挂到父对象之上

41-44 [TRIGGER]-2  [FRAME JUST] 0                        ← 只在第 0 帧触发一次
        [WHICH] [PASSIVE] [CHECKUP] [IS INDEX] 109084869 [/IS INDEX] [/CHECKUP]
        [CHECKED NO] [>] 0                               ← 场上存在该被动对象
        [UPDATE VAR] ATK7_GET_TARGET_DISTANCE …
        [DO BEHAVIOR] [ME] 2
        [BEHAVIOR]-1 [SET DIRECTION TO CHECKUP]          ← 朝向修正
        [BEHAVIOR]-2 [INTERPOLATION MOVE TARGET] [FRAME] 0 1 [OFFSET] 0
                     [MOVE TYPE] [ACCEL] [USE ZPOS OFFSET]
                     [STOP MOVE UNABLE POS]              ← 抛物线弹道（带 z 轴）

52   [TRIGGER]-4 [FRAME JUST] 2 [WHICH] [TARGET] …
        [DO BEHAVIOR] [CHECKUP OBJECT] 4  [DO BEHAVIOR] [ME] 5

56   [CREATE SIMPLE WARNING] [TYPE] Box [POS] PARENT 0 PARENT 0
        [SIZE] 1000 100 [TIME] 1000 [POST TIME] 200
        [FOLLOWING DIRECTION] [MY DIRECTION]             ← 红色预警框（玩家躲的范围提示）

60   [FLASH SCREEN] [TIME VALUE] 100 800 100 [RGBA] 0 0 0 200 [LAYER] [DEFAULT]
64   [DESTROY]
68   [SHAKING] 3 500
70   [ON END ANIMATION] [DO BEHAVIOR] [ME] 9
72   [BEHAVIOR]-9 [SET ACTION] [CUSTOM] 11 [NOW]         ← 动作播完自动切下一式
```

这份文件几乎覆盖了 `.act` 的全部表达能力：**条件（对象查询 + 变量 + 内联分支）→ 副作用（生成对象 / 位移 / 演出 / 预警框 / 切动作）**。它本质上是一门「**帧驱动 + 对象查询**的小语言」，而不是配置表。

> 数据瑕疵：`109084869` **不在** `passiveobject__passiveobject.lst.tsv`（该表 17,692 条，最大 id 491,002,230）。同族的 `109048600` 在（`KContents2/TheEvildomWar/.../Sarpoza_P2_PassiveSkill1.obj`）。**【待验证】** 是私有服数据缺失，还是 `[INDEX]` 另有局部 id 空间。

### 1.6 判定框 / 受击开关：`.act` 只能开关，几何在 `.ani`

`export/text/monster/poongjintrainingroom/rosaura/action/attack_10.act.txt`（55 行）：

```
13-19 [BEHAVIOR] [SET ACTION] [ATTACK] 12 [NOW]          ← 切到攻击动作 12
21-23 [TRIGGER]-1 [FRAME] 0 0 → [BEHAVIOR]-1 [CENTER MSG] 獨自站在光芒之中 5000
25-31 [TRIGGER]-2 [FRAME] 7 7 → 十余条
        [CREATE PASSIVEOBJECT] [INDEX] 19354 [LEVEL] 0
        [POS] [RANDOM] 0 560 [RANDOM] 154 317 0 [USE MAP POS]
                                                       ← 随机撒点（采样器）
35-37 [TRIGGER]-4 [FRAME] 78 78 [WHICH] [CHARACTER]
        [CHECKUP] [DISTANCE] [<] 8000 [/CHECKUP]        ← 条件：距离 < 8000
        [DO BEHAVIOR] [CHECKUP OBJECT] 4
      [BEHAVIOR]-4 [SET DAMAGE BOX] [ON]               ← 打开判定框！
39-41 [TRIGGER]-6 [ON SET ACTION] → [BEHAVIOR]-5
        [TRIGGER] 8 [ON] [APPENDAGE] 10000 [all active status resistance] [%] 100000.0
                                                       ← 用 trigger 8 当「开关变量」
45-51 [TRIGGER]-7 [ON END ACTION] → [BEHAVIOR]-6 [DELETE APPENDAGE]
      [TRIGGER]-8 [ENABLE] [OFF]
      [TRIGGER]-9 → [BEHAVIOR]-7 [TRIGGER] 8 [OFF]     ← 关掉 trigger 8
53-55 [TRIGGER]-10 [ON SET ACTION] → [BEHAVIOR]-8 [CREATE PASSIVEOBJECT] [INDEX] 152299
```

注意 `[SET DAMAGE BOX] [ON]` 出现在**第 78 帧**——这说明「动作的第几帧有判定，多大多长」这件事，`.act` 只知道**开关时刻**，不知道**形状**。

证据链：
- `.atk` 文件无几何字段：`export/text/character/swordman/attackinfo/attack1.atk.txt`（26 行）全文只有 `[damage bonus] -15` / `[attack type]` / `[physic]` / `[weapon damage apply] 1` / `[attack enemy] 1` / `[elemental property]` / `[no element]` / `[damage reaction]` / `[damage]` / `[push aside] 30` / `[lift up] 75` / `[attack direction]` / `[hit down]`。200 个剑士 `.atk` 的标签频次里也没有任何坐标类字段。
- `.act` 里只有 `[ATTACKRECT] [RESET]`（全库 2,446 次）与 `[SET DAMAGE BOX] [ON]`。
- `.nut` 里只有 `sq_SetAttackBoundingBoxSizeRate`（216 次）——**只能缩放，不能定义**。
→ **框几何在二进制 `.ani` 帧数据里**（`docs/PVF-FORMAT.md`：`.ani` 版本 6，尚未解析，P0.5）。**【待验证】**（需先解析 `.ani`）。

### 1.7 AI：`.ai` 是「条件树 + 返回攻击槽下标」

`export/text/monster/poongjintrainingroom/sarpoza/ai/action.ai.txt`：

```
[ai pattern]
  [think]
    [void] is target in attack area() 400.0 400.0 30.0 30.0
      [true]  … 
  [think]-1
    [void] is the skill in cooltime() 0
      [true]
  [think]-2
    [void] is the skill in cooltime() 1
      [true]  [return] -1
      [false] [return] 1
    [return] 0
  [think]-3
    [void] is target in attack area() 850.0 200.0 50.0 50.0
      [return] 6
    [return] 5
```

即：`[think]-N` 是一个判定块，缩进的 `[true]`/`[false]` 是分支，`[return] k` 返回 **`[attack action]` 数组下标 k**（`-1` = 不动），引擎接着执行 `[SET ACTION] [ATTACK] k`。`.mob:97` 的 `[ai pattern]` 按难度给 5 套（normal/expert/master/king/slayer），每套 4 个 `.ai`（Event / DestinationSelect / Action / MoveMethod）。

> 这是「**数据驱动的行为树**」：没有脚本、没有字节码，纯文本谓词 + 返回值。

---

## 2. `.als`：只是 `.ani` 的伴生「动画别名 + 特效挂载」脚本

### 2.1 关系：`.als` ↔ `.ani`，一对一，同目录同基名

77,490 个 `.als`，命名一律 `<基名>.ani.als`，并且与同名 `.ani` 同目录并列：

```
character/swordman/animation/bloodboom.ani
character/swordman/animation/bloodboom.ani.bin      ← 二进制帧数据
character/swordman/animation/bloodboom.ani.als.txt  ← 文本伴生脚本
```

分布：equipment 42,029 / monster 15,359 / passiveobject 9,276 / character 7,530 / creature 1,751 / map 533 / skin 284 / common 261 / localization 120 / npc 87 / worldmap 66 / sqr 60 / uniquebeast 54 / ui 53 / dungeon 20。

### 2.2 它到底做什么：7,300 个角色 `.als` 的标签全表

| 标签 | 次数 | 用途 |
|---|---|---|
| `[use animation]` | 7,292 | 把一个外部 `.ani` 引用进来并起**别名** |
| `[none effect add]` | 4,299 | 以「不受特效影响」的方式叠加该别名层 |
| `[add]` | 2,751 | 叠加层 |
| `[create draw only object]` | 538 | 生成纯绘制对象（拖尾/刀光） |
| `[create draw only object follow parent]` | 49 | 同上但跟随父对象 |
| `[static data]` | 47 | 静态参数 |
| `[remove]` / `[no apply global alpha]` / `[non effect add]` / `[add force effect]` / `[no effect add]` | 个位数 | 细节修饰 |

全文样例 `export/text/character/swordman/animation/bloodrivencast.ani.als.txt`（24 行）：6 条 `[use animation]`（指向 `../Effect/Animation/BloodRiven/cast_*.ani` 并起 `cast_cast_normal` 之类别名）+ 6 条 `[none effect add] 0 1000x <别名>`。

### 2.3 结论 + 反证

- `.als` **不是**状态转移，也**不是**动作别名表（它给的是**动画层**别名，不是动作别名）。
- 反证：全库只有 2 个 `.als` 含 `[MOTION]`（`export/text/monster/newmonsters1/gcontents/210128_ilrustrea/boss/kurkra/animation/effect/die/die_03.ani.als.txt` 及其 `newmonsters` 副本），**没有任何一个 `.als` 含 `[TRIGGER]`**。
- 所以「`.als` = 动作链接/重定向」这个常见说法**不成立**：它只解决「这个动画还要叠哪几层、叠多久、要不要吃全局 alpha」。

> 那「动作之间的链接」在哪？怪物在 `.act` 的 `[SET ACTION]`/`[CHANGE ACTION FILE]`；角色在 `.nut` 的 `sq_AddSetStatePacket`。见 §1.3 与 §3。

---

## 3. `.nut`（Squirrel）：角色侧的真实机制层

### 3.1 规模与加载顺序

2,489 个 `.nut`：character 1,846 / custom 263 / monsters_appendage 93 / monster 63 / js60_qq506807329 59 / skill_2nd_common 58 / ui 38 / passiveobject 17 / appendage 14 / map 14 / unclebang_shared_passive_object 8 / sqr 7 / 根目录 3（`common.nut`、`common_function.nut`、`dnf_enum_header.nut`）。

启动装载（以剑士为例）`export/text/sqr/character/swordman_load_state.nut.txt`：

```
:1   IRDSQRCharacter.pushPassiveObj("skill_2nd_common/share_obj/share_po_swordman_24370.nut", 24370)
:2-6 sq_RunScript("skill_2nd_common/share_obj/swordman/setcustomdata.nut")  … 共 5 个
:8-10 IRDSQRCharacter.pushScriptFiles("character/swordman/swordman_header.nut")
                          / "swordman_common.nut" / "passive_skill_swordman.nut"
:12  IRDSQRCharacter.pushState(ENUM_CHARACTERJOB_SWORDMAN,
         "character/swordman/bloodboom/bloodboom.nut", "swordman_bloodboom", 229, 229)
     签名 = (job, 脚本路径, 名字前缀, stateId, skillId)
:32-48 pushState(..., 44, -1) / (..., 7, -1)  ← BackStep / (..., 13, -1) 投掷
:51   //IRDSQRCharacter.pushState(..., "character/swordman/attack/attack.nut",
      //      "swordman_attack", 8, -1);            ← 原版普攻绑定，被注释
:99   IRDSQRCharacter.pushState(0,
         "character/swordman_jg/attack/attack.nut", "swordman_attack", 8, -1)
                                                   ← 实际生效；job 0 = 剑士，state 8 = 普攻
:66   pushPassiveObj("character/swordman_3rd/swordghost31/po_all_attack.nut", 24352)
:102  pushPassiveObj("character/swordman_jg/po_sprit_swordman.nut", 24389)
```

**这张表就是「角色状态机」的数据化定义**：`stateId → (脚本, 名字前缀)`。引擎在进入某 state 时，按名字前缀拼回调名去脚本里找（`onSetState_<name>`、`onKeyFrameFlag_<name>`、`onProc_<name>` …）。

### 3.2 回调命名 = 引擎的钩子协议

对全库 14,898 个 `function` 定义做统计，去掉 1,643 个 `sq_*` 后，活跃钩子为：

```
onEndCurrentAni 902   onSetState 810        checkCommandEnable 769
checkExecutableSkill 768   onStart 670      onKeyFrameFlag 706
onEnd 454             onProc 421            onAttack 393
procAppend 368        onEndState 287        onProcCon 240
onTimeEvent 208       setCustomData 200     onStartAppend/onEndAppend 189
onChangeSkillEffect 115  onAfterSetState 114  procSkill 99
onSourceKeyFrameFlag 86  onAttackParentAppend 70  onDestroyObject 43
onOpenPopupWindow 25  onClosePopupWindow 25  startSkillCoolTime 26
onStartDungeon 23
```

另外有一组**即时模式绘制**钩子：`prepareDraw`(69)、`drawAppend`(84)、`drawCustomUI`(27)、`onEnterFrame`(97)、`sq_StartDrawCastGauge`(77)/`sq_EndDrawCastGauge`(62)。

appendage（增益/被动）则用字符串注册：`appendage.sq_AddFunctionName("proc","proc_appendage_wavemark")`（`export/text/sqr/character/swordman/appendage/ap_wavemark.nut.txt:6`）。

### 3.3 API 边界：554 个 `sq_*`，能做什么 / 不能做什么

全 `sqr/` 出现 **554 个不同 `sq_*` 标识符**，其中 280 个以 `obj.sq_*()` 方法形式调用。高频前 20：

```
sq_PlaySound 3717            sq_AddSetStatePacket 3171
sq_WriteDword 3160           sq_AddFunctionName 3033
sq_SetCurrentAnimation 2236  sq_IntVectPush 2130
sq_GetBonusRateWithPassive 1878  sq_IntVectClear 1762
sq_GetIntData 1519           sq_SendCreatePassiveObjectPacket 1174
sq_StartWrite 1151           sq_IsAppendAppendage 1006
sq_AppendAppendage 971       sq_IsUseSkill 963
sq_SetCurrentAttackInfo 888  sq_StopMove 812
sq_GetVectorData 738         sq_SetCurrentAttackBonusRate 726
sq_IsMyControlObject 697     sq_SetStaticSpeedInfo 689
```

按「能力边界」归类：

**能做**
| 能力 | 代表 API |
|---|---|
| 状态机切换 | `sq_AddSetStatePacket(state, priority, resetTimer)`（3,171 次）、`sq_GetState()` |
| 动作与判定属性 | `sq_SetCurrentAnimation(n)`、`sq_SetCurrentAttackInfo(n)`、`sq_SetCurrentAttackBonusRate(r)` |
| 读表 | `sq_GetIntData(skill, idx)`、`sq_GetLevelData(skill, col, lv)`、`sq_GetBonusRateWithPassive(...)`、`sq_GetStaticData` |
| 生成对象 | `sq_CreateDrawOnlyObject`、`sq_CreateAnimation`/`sq_CreatePooledObject`+`sq_AddObject`、`sq_SendCreatePassiveObjectPacket(id, …)` |
| 增益 | `CNSquirrelAppendage.sq_IsAppendAppendage(obj, path)`、`sq_AppendAppendage` |
| 音画演出 | `sq_PlaySound`、`sq_flashScreen`、`sq_SetMyShake`、`addLayerAnimation` |
| 命中控制 | `resetHitObjectList()`（同一次挥击可再次命中）、`sq_GetAttackAni` |
| 即时绘制 | `sq_drawCurrentFrame` 风格 + `drawCustomUI`/`drawAppend` 钩子 + `sq_StartDrawCastGauge` |
| 存档/变量 | `getVar().clear_vector()/push_vector()`、`setCustomData` |

**不能做（或只能间接做）**
| 限制 | 证据 |
|---|---|
| 没有通用 widget/UI API（不能 `sq_CreateWindow`/`sq_GetControl`/绑定事件） | `export/text/sqr/ui/` 只有 18 项；全库无此类标识符；只有 `onOpenPopupWindow_*`/`onClosePopupWindow_*` 各 25 处 |
| 不能定义判定框形状，只能缩放 | 只有 `sq_SetAttackBoundingBoxSizeRate`(216) |
| 不能读文件、不能开网络 | 554 个 `sq_*` 里没有任何 file/socket/http 类；对外通信只有「发包」一族 |
| 不能读 `.atk` 的任意字段（只能整体切换） | `sq_SetCurrentAttackInfo(n)` 按索引换整份 |
| 部分逻辑根本不在 PVF | `share_po_swordman_24370.nut` 是**空壳**（3–7 空行），被动对象 24370 的行为全在客户端 |

**联机接口（为单机版留接口的依据）**——发包 API 一族，范式高度统一：

```
sq_AddSetStatePacket 3173        sq_BinaryWriteDword 2212
sq_SendDestroyPacketPassiveObject 2037
sq_SendCreatePassiveObjectPacket 1372
sq_SendCreatePassiveObjectPacketPos 901
sq_BinaryStartWrite 743          sq_BinaryWriteWord 203
sq_SendChangeSkillEffectPacket 145   sq_SendHitObjectPacket 129
sq_sendSetActiveStatusPacket 78   sq_SendHitObjectPacketByAttackInfo 35
sq_BinaryWriteBool 20
```

固定写法（`export/text/sqr/character/swordman/attack/attack.nut.txt:56-68`）：

```squirrel
if (obj.sq_IsMyControlObject()) {          // 只有本机拥有该角色时才发
    sq_BinaryStartWrite();
    sq_BinaryWriteDword(47);               // 技能 id
    sq_BinaryWriteBool(...);
    sq_SendCreatePassiveObjectPacket(obj, 24370, 0,0,0,0, obj.getDirection());
}
```

→ **「owner 发确定性指令包，其它端按包重放」**。这就是它天然的联机接缝：单机版只要把「发本地调用」换成「产生事件 → 广播 → 各端重放同一事件」即可。

### 3.4 真实脚本 1：剑士普攻（`attack.nut`，194 行）

文件：`export/text/sqr/character/swordman/attack/attack.nut.txt`
（注：私有服把**局部变量名**混淆成了随机串，如 `JM8H4uzkC2sc8UKfL7`；函数名/API 名未混淆。）

```
:5  function onAfterSetState_swordman_attack(datas, ...)
:8-9   sq_GetVectorData(datas, 0/1)              ← 从 state packet 的 datas 取参数
:10-12 getVar().clear_vector(); push_vector(...)  ← 把连击段号存进对象变量
:22-23 wavemark_swordman_attack(...) / weaponcombo_swordman_attack(...)   ← 拆到子函数

:26 function onKeyFrameFlag_swordman_attack(obj, flagIndex)
      ← 每到一个「关键帧」就回调一次，flagIndex 是 .ani 里标的帧标记号
:29-30 取 (combo 段, 段号)
:33   case 67:
:36-38 case 100: case 101:
          obj.resetHitObjectList();             ← 清空命中列表 → 同一挥击可再判定
:42   sq_CreateDrawOnlyObject(obj, ".../weaponcombo/reslash_blunt03_dust01.ani",
                              ENUM_DRAWLAYER_NORMAL, true)   ← 纯表现

:54   CNSquirrelAppendage.sq_IsAppendAppendage(obj, ".../appendage/ap_wavemark.nut")
:58   sq_GetBonusRateWithPassive(47, 8, 3+idx, 1.0)    ← (skill, state, idx, 默认值)
:59-68 sq_BinaryStartWrite / WriteDword(47) / WriteBool / SendCreatePassiveObjectPacket(24370)
                                                        ← 生成刀气被动对象（仅 owner）

:81   sq_SetCurrentAttackBonusRate(sq_GetCurrentAttackBonusRate(obj)
                                   + obj.sq_GetBonusRateWithPassive(67,8,0,1.0))
:82   getWeaponSubType()                                ← 武器子类型分支
:89-91  case 2（巨剑）: sq_SetCurrentAnimation(37); sq_Rewind(sq_GetCurrentAni());
                        sq_SetCurrentAttackInfo(36)
:94-96  否则:           sq_SetCurrentAnimation(170); ... ; sq_SetCurrentAttackInfo(100)
                                                        ← 同一 state 按武器换动画+攻击属性

:115-124 sq_GetAttackAni(0/1) / setCurrentAnimation(ani) /
         sq_AddStateLayerAnimation(1, sq_CreateAnimation("", ".../short_new_01.ani"), 0, 0)

:171-189 function onProc_swordman_attack(obj)            ← 每帧（或每逻辑帧）回调
:175   sq_GetSkill(obj, 81)
:176   skill.setCommandEnable(true)
:177-180 obj.sq_IsEnterSkill(81) / obj.sq_IsUseSkill(81)  ← 指令成立？
:183   startSkillCoolTime(81, 1, -1)
:184-186 sq_IntVectClear(); sq_IntVectPush(0);
         sq_AddSetStatePacket(45, STATE_PRIORITY_IGNORE_FORCE, true)  ← 进派生技 state 45
```

### 3.5 真实脚本 2：技能「血爆」（`bloodboom.nut`，105 行）

文件：`export/text/sqr/character/swordman/bloodboom/bloodboom.nut.txt` + `export/text/skill/swordman/swordman_bloodboom.skl.txt`（71 行）

`.skl` 给元数据（引擎读表，脚本读不到的部分）：

```
:16   [type] [active]                       ← 主动技
:29-30 [executable states] 8 0 14           ← 8=ATTACK, 0=STAND, 14=?  ← 决定 checkCommandEnable
:33-34 [icon] Character/Swordman/Effect/SkillIcon.img 412 … 413
:35-36 [command] (RIGHT),(LEFT),(RIGHT),(SKILL)   ← 搓招序列
:39-40 [skill command advantage] 50 50
:43-44 [cool time] 40000 40000              ← ms
:45-48 [dungeon] [static data] 10 110 + [level info] …   ← sq_GetIntData/sq_GetLevelData 的数据源
:61-71 [level property] 逐列声明含义（大小比例 / 可发动最低HP / 消耗HP / 攻击力% /
        出血等级 / 概率 / 持续 / 攻击力 / 对出血敌人增伤 / HP每降1%增伤）
```

`.nut` 给行为：

```
:2  function checkExecutableSkill_swordman_bloodboom(obj)
:5    obj.getHp() < obj.getHpMax()/100.0*obj.sq_GetIntData(229, 0)   ← 读 static data[0]
:8-9  obj.isMessage() / sq_AddMessage(3599)                          ← 前置提示
:12   obj.sq_IsUseSkill(229)
:15   obj.sq_AddSetStatePacket(229, STATE_PRIORITY_USER, false)

:21 function checkCommandEnable_swordman_bloodboom(obj)
:24-30  sq_GetState(); STATE_STAND → true; STATE_ATTACK → obj.sq_IsCommandEnable(229)

:34  反调试闸（数据被改就死循环）:
      if (sq_GetAniFrameNumber(sq_CreateAnimation("","character/swordman/effect/animation/
               dotarearock2_ds.ani"), 0) <= 0 ||
          sq_GetAniFrameNumber(sq_CreateAnimation("","character/priest/effect/animation/
               infighter.ani"), 0) > 0) while(true);

:36 function onSetState_swordman_bloodboom(obj, State, datas, isResetTimer)
:41-43 sq_GetSkillLevel(obj,229) / sq_GetLevelData(229,0,SkillLevel) / setHp(…)
:48   sq_StopMove()
:49   sq_PlaySound("SM_BLOODBOOM_01")
:50   obj.sq_SetCurrentAnimation(122)          ← 122 = CUSTOM_ANI_SWORDMAN_BLOODBOOM
:51-52 sq_SetStaticSpeedInfo(SPEED_TYPE_ATTACK_SPEED, SPEED_TYPE_ATTACK_SPEED,
                             SPEED_VALUE_DEFAULT, SPEED_VALUE_DEFAULT, 1.0, 1.0)

:56 function onKeyFrameFlag_swordman_bloodboom(obj, flagIndex)
:59   if (flagIndex == 1)                      ← 关键帧 1
:64-79 sq_StartWrite() / WriteDword(229) / WriteDword(sq_GetIntData(229,1)) /
       sq_GetBonusRateWithPassive(229,229,1,1.0) / sq_GetLevelData(229,6,SkillLevel) / WriteBool
       ← 把「这一击的全部参数」序列化进包
:80   obj.sq_SendCreatePassiveObjectPacket(24370, 0,0,0,60)   ← 生成真正的伤害源
:81   sq_SetMyShake(obj, 8, 300)
:82   sq_flashScreen(obj, 20,130,100,150, sq_RGB(0,0,0), GRAPHICEFFECT_NONE, ENUM_DRAWLAYER_BOTTOM)
:85-93 sq_CreateAnimation + addLayerAnimation(1,…,true) ×4 + sq_CreatePooledObject + sq_AddObject

:98-103 function onEndCurrentAni_swordman_bloodboom(obj)
       if (sq_IsMyControlObject()) sq_AddSetStatePacket(STATE_STAND, STATE_PRIORITY_USER, false)
```

**接力链（技能）**：
`.skl`（能否学/命令/冷却/等级数据）→ `pushState(job, nut, "swordman_bloodboom", 229, 229)` → `checkExecutableSkill` → `sq_AddSetStatePacket(229)` → `onSetState`（`sq_SetCurrentAnimation(122)` = 放哪段动画）→ **`.ani` 帧数据里标了 `flagIndex`** → `onKeyFrameFlag` → `sq_SendCreatePassiveObjectPacket(24370)` → `passiveobject` 的 `.obj`（`[etc motion]`/`[etc attack info]`）→ `.atk`（伤害属性）→ 服务端算伤害。

### 3.6 真实脚本 3：appendage「剑痕」（`ap_wavemark.nut`，39 行）

文件：`export/text/sqr/character/swordman/appendage/ap_wavemark.nut.txt`

```
:2   sq_AddFunctionName(appendage)
:6   appendage.sq_AddFunctionName("proc", "proc_appendage_wavemark")   ← 注册每帧回调
:10  function proc_appendage_wavemark(appendage)
:16-17 appendage.getParent() / sq_GetCNRDObjectToSQRCharacter(parentObj)  ← 转成角色
:18  sqrChr.getState() == STATE_DIE || isDead()
:21    appendage.setValid(false)                     ← 宿主死了就失效
:26  appendage.getTimer().Get() < 10000              ← 时长（也可由 .apd 声明）
:27-28 sq_IsEnterSkill(47) / sq_IsUseSkill(47) → setValid(false)   ← 用了消耗技就吃掉
```

配套 `.apd` 数据文件（`export/text/appendage/xmn/haoyue13514.apd.txt`）声明元数据，并在 `[string data]` 里写**迷你表达式**（不是脚本）：

```
[type] skill data up        [duration] 20000      [max overlap] 1
[string data]
    [demonic swordman] 238 [dungeon type] [level] 0 % 30   ← job, skillId, 场景, 字段, 下标, 运算符, 值
    [level] 1 + 5
    [static] 1 % -30
    [cooltime] 0 + -3000
```

→ **`.apd` = 声明式数值修正；`.nut` = 过程式行为**。同一个「增益」被拆成两份文件。

### 3.7 三个「不在 PVF」的断点（重要）

1. **基础动画索引 / 攻击属性索引无数据表**。`sq_SetCurrentAnimation(37)`、`sq_SetCurrentAttackInfo(36)` 里的 37/36 无法在数据层查到对应文件；`character/swordman/attackinfo/` 有 111 个 `.atk`，但 `grep -rl 'attackinfo/' export/text/character --include='*.txt'` **零命中**。→ 索引→文件映射硬编码在客户端 exe。**【待验证】**
   - 反例（可解析的那一类）：`CUSTOM_ANI_*` 常量能和文件名对上——`CUSTOM_ANI_SWORDMAN_BLOODBOOM <- 122` ↔ `character/swordman/animation/bloodboom.ani`；`..._BLOODRIVENCAST <- 123` ↔ `bloodrivencast.ani`；`..._RAGESTARTBODY_BODY <- 129` ↔ `ragestartbody_body.ani`。命名规则 = **常量名小写化** + `character/<job>/animation/`。
2. **`.chr` 只是数值表**。`export/text/character/swordman/swordman.chr.txt`（102 行）只有 `[HP MAX] 180.0`、`[physical attack] 7.5`、`[move speed] 1350.0` 一类数值 + 转职成长系数，**没有动画表、没有 attack info 表**。
3. **枚举只以「注释头文件」形式存在**：`export/text/sqr/dnf_enum_header.nut.txt`（1,694 行）与 `export/text/sqr/character/swordman/swordman_header.nut.txt` 是**给脚本用的常量定义**，不是引擎读取的表。`STATE_STAND <- 0` / `STATE_ATTACK <- 8` / `STATE_DIE <- 5`（`dnf_enum_header.nut.txt:202,207,210`）、`STATE_PRIORITY_AUTO..IGNORE_FORCE <- 0..4`（:656-660）、`ENUM_CHARACTERJOB_SWORDMAN <- 0 … CREATOR_MAGE <- 10`（:1447-1458）、`SPEED_TYPE_* <- 0..4`（:1542-1546）、`ENUM_DRAWLAYER_CONTACT..MAX <- 0..7`（:193-200）。

---

## 4. UI 是怎么做的

### 4.1 `.ui` 的规模与目录

378 个 `.ui`（根 `ui/` 1,468 个文件里）：

```
ui/ui 78      ui/event 57     ui/inventory 28   ui/pvp 18
ui/common 10  ui/randomoption 10  ui/skill 9    ui/chat 8
ui/cargo 7    ui/selectcharacter 7  ui/expertjob 7
ui/characterinfowindow 6  ui/titlebook 6  ui/raid_ui 6  ui/mercenary 6
ui/channel 5  ui/party 5      ui/optionwindow 4   …
worldmap/ui/*.ui（abnoba / airship / anton / aradcartel …）
```

### 4.2 `.ui` 的语法：控件清单 + 绝对坐标

`export/text/ui/hud/hud.ui.txt`（13 行，全文）：

```
[ui controls]
    [highlight button] myinfo_button    836 45 1 interface2/HUD/HUD.img 5 5 6 7 93 98
[ui controls]-1
    [highlight button] inventory_button 855 45 1 interface2/HUD/HUD.img 5 8 9 10 94 98
[ui controls]-2
    [highlight button] quest_button     874 45 1 interface2/HUD/HUD.img 5 11 12 13 95 98
[ui controls]-3
    [highlight button] skill_button     893 45 1 interface2/HUD/HUD.img 5 14 15 16 96 98
...
```

解析：`[控件类型] <控件 ID/名字> <x> <y> <层> <图集> <帧索引们…>`。
末尾一串整数是**图集帧索引**（普通/悬停/按下/禁用态的帧号）+ 单元格尺寸。

`export/text/ui/inventory/inventory_item.ui.txt`（34 行）引入了一种「容器」写法：

```
[ui controls]
    [control] 1500 0 0 0 0                ← 匿名容器，ID=1500
[ui controls]-1
    [image] -1 -3 42 1 Interface/newstyle/windows/Inventory/Inventory.img 1 0
[ui controls]-3
    [control] 1199 55 39 0 2 130 143      ← 嵌套容器 + 尺寸 130×143
[variable]
    [int] 1600 2 0 -26                    ← 定义一个整型布局变量（偏移用）
```

`export/text/ui/inventory/iteminventorywindow.ui.txt`（36 行）是**窗口级**声明：

```
[window]
    [type]                  popup
    [horizontal alignment]  left
    [horizontal distance]   473
    [vertical alignment]    top
    [vertical distance]     100
    [tile type]             5
    [size]                  20 38            ← 20 列 × 38 行格子
    [title accesorry type]  …
```

### 4.3 关键证据：控件 ID 有三种写法并存

对 369 个可解析的 `.ui.txt` 统计控件 ID 形态：

| 形态 | 数量 | 例子 |
|---|---|---|
| `IDC_*` 常量名（MFC 风格） | 885 | `IDC_HUD_MENU`、`IDC_DUNGEONLOADING_TOPBOTTOM_BANNER` |
| 纯数字 ID | 2,946 | `[control] 1500`、`[image] -1`、`[control] 1100` |
| 符号名（snake_case） | 476 | `myinfo_button`、`server`、`name`、`confirm`、`animation`、`icon`、`cancel` |

**结论：`.ui` 不是「控件定义」，而是「控件摆位表」。** 控件的**存在、类型语义、事件处理**都在客户端 C++ 里（`IDC_` 是典型 MFC 资源 ID），PVF 只提供：这个控件放哪、用哪张图的哪一帧、窗口多大。

一个旁证：`export/text/ui/dungeonloading/*.ui.txt` 只有 2 个控件，且是纯装饰 + 提示文本：

```
[image] IDC_DUNGEONLOADING_TOPBOTTOM_BANNER 0 0 1 WorldMap/selectdungeon02.img 3 79 1 0
[text]  IDC_DUNGEONLOADING_TIP_TEXT 20 580 0 9 316 760 1 1 1 0 255 255 0
                                            ← 末段是 RGB/描边/字体等渲染参数
```

### 4.4 反证：三处「根本不是数据驱动」

**(a) 结算界面完全硬编码**

```
$ ls export/text/ui/result/*.ui.txt     → 0 个
$ ls export/text/ui/result/*.act.txt    → 11 个（result_admission0..10）
$ ls export/text/ui/result/*.ani.bin    → 大量
$ grep -rl 'IDC_RESULT\|result_rank\|RESULT_RANK' export/text   → 0
```

→ 结算（评分、翻牌、金币/经验结算）的**布局与数值公式都不在 PVF**。PVF 只交付 11 个装饰用 `.act`。**【待验证】** 评分公式在服务端（与 `docs/PVF-FORMAT.md` 的结论一致：伤害/掉落/经验公式不在 PVF 内）。

**(b) 副本内战斗 HUD 是脚本里的常量坐标**

`export/text/sqr/init_character.nut.txt`（102 行），`onSetCharacter(obj)` 从 :50 开始：

```
:53  sq_set_hp_pos(224, 533)
:54  sq_set_mp_pos(518, 533)
:55  sq_set_sp_pos(580, 589)
:56  sq_set_level_pkc_pos(198, 588)
:57  sq_set_level_dgn_pos(195, 588)
:58  sq_set_fatigue_pos(655, 581, 300, 4)
:59  sq_set_expbar_pos(249, 595, 300, 4)
:60  sq_set_buff_pos(2, 545)
:61-62 sq_set_hp_precent_pos(242,559) / sq_set_mp_precent_pos(534,559)
:67-69 sq_SetExSkillSlotVisible(true) / sq_SetSkillSlotVisible(10,true) / sq_SetSkillSlotEnable(10,true)
:71-77 local SKILLICON_START_X = 538; local SKILLICON_START_Y = 558;
       for (i = 0; i < 6; i++) sq_SetSkillSlotPos(i, 538 + i*30, 558)
:79-91 sq_set_skill_slot_pos(0..12) →（300,565）/（331,565）… 逐槽像素
:92-97 sq_set_item_slot_pos(-3..2)  →（3,568）/（34,568）/（65,568）/（96,568）/（127,568）/（158,568）
```

→ **血条/蓝条/技能槽/物品槽的位置是脚本里的整数字面量**，与分辨率绑定（这批坐标对应 800×600 时代布局）。这不是 `.ui`，也没有任何布局文件。

**(c) Squirrel 没有 UI 框架，只有即时模式绘制**

`export/text/sqr/ui/` 全部 18 项（`ui.nut`、`ui_function.nut`、`file.nut`、`ap_ui.nut`、`ap_oncity.nut`、`ap_equipment_anton.nut`、`ap_monster_ui.nut`、`ap_monster_ui2.nut`、`equipment_effect.nut` + 子目录 `ap/ cutscene/ damagefont/ dpl/ equ/ hud_alarm/ pvpfont/ skinstorage/ sync/`）里**没有任何 `sq_CreateWindow` / `sq_GetControl` / 事件绑定**。它只有：

- 两个窗口级钩子：`onOpenPopupWindow_*`（25 处）、`onClosePopupWindow_*`（25 处）；
- 一组**即时模式**绘制钩子：`prepareDraw`(69)、`drawAppend`(84)、`drawCustomUI`(27)、`onEnterFrame`(97)、`sq_StartDrawCastGauge`(77)/`sq_EndDrawCastGauge`(62)。

**唯一的「数据驱动 UI」实例**：世界地图。

```
export/text/worldmap/lorien.wdm.txt:1-2   [map image] WorldMap/Lorien.img 0
:3-4   [ui path] WorldMap/UI/Lorien.ui          ← 数据文件指向 UI 文件
:5-6   [dungeon] 1 -1 2 -1 1500 428 1501 4340   ← 副本 id + 槽位图索引 + 图标帧
:9     [hell dungeon] 1
       [hell freepass item] 8272 1 8376 1 8247 1
       [hell quest] 1016
```

对应的 `export/text/worldmap/ui/lorien.ui.txt` 存在 → **世界地图的选点热点是数据驱动的**（74 个 `.wdm` + 同名 `.ui`），这和 `ui/` 下的窗口布局形成对比。

### 4.5 小结：UI 的四档「数据化程度」

| 档 | 界面 | 数据来源 | 证据 |
|---|---|---|---|
| 全数据 | 世界地图选点 | `.wdm` + `worldmap/ui/*.ui` | `lorien.wdm.txt:3-4` 的 `[ui path]` |
| 半数据 | 城镇/背包/技能/选项等窗口 | `ui/**/*.ui` 提供摆位，控件与事件在 C++ | 控件 ID 三态统计；`iteminventorywindow.ui.txt` 的 `[window]` |
| 硬编码（脚本） | 副本内 HUD | `sqr/init_character.nut:53-97` 常量坐标 | 见 §4.4(b) |
| 硬编码（客户端） | 结算界面 | 无 | `ui/result/` 无 `.ui`，`IDC_RESULT` 零命中 |

---

## 5. 流程串联：城镇 → 选图 → 副本 → 结算 → 回城

### 5.1 全局 id 空间 = 注册表 `.lst`

`export/_meta/lst/*.tsv` 是「整数 id → 文件路径」的全局命名空间，两列 `id<TAB>path`。**表内无序**（首行不一定是 id 1），必须 grep 定位。

| 注册表 | 条数 | 作用 |
|---|---|---|
| `town__town.lst.tsv` | 58 | 城镇 id → `.twn` |
| `region__region.lst.tsv` | 24 | 区域 id → `.rgn`（把多个城镇分组） |
| `worldmap__worldmap.lst.tsv` | 74 | 世界地图 id → `.wdm` |
| `dungeon__dungeon.lst.tsv` | 591 | 副本 id → `.dgn` |
| `map__map.lst.tsv` | 4,592 | 地图 id → `.map` |
| `monster__monster.lst.tsv` | 3,549 | 怪物 id → `.mob` |
| `passiveobject__passiveobject.lst.tsv` | 17,692 | 物件 id → `.obj`（`.act` 的 `[INDEX]` 指向这里） |

### 5.2 完整链路（每一步都给出真实 id 走通）

```
[城镇]
 town__town.lst.tsv  →  .twn
 export/text/town/1_new/new_elvengard.twn.txt
   :3   [cutscene image] Map/CutScene/Elvengard.img 0
   :5   [dungeon what must be cleared] -1          ← -1 = 无前置副本
   :7   [area]     0 1_new/Cataclysm/Town/Elvengard/new_Elvengard.map [normal]
   :9   [area]-1   1 1_new/Common/Gate_Seria_Elvengard.map [gate] 450 234
                                                        ← [gate] 带落点坐标
   :11-19 [area]-2..-6 另外 5 张地图（含 death_valley）
   :21  [name] 艾爾文防線
 → 城镇 = 若干张 map 的集合，每张标记 [normal] / [gate]

[区域 / 世界地图]
 export/text/region/shonan.rgn.txt:1  [towns] 11 12 13 16 10   ← 区域→城镇 id 列表
 export/text/worldmap/lorien.wdm.txt
   :1-2 [map image] WorldMap/Lorien.img 0
   :3-4 [ui path]   WorldMap/UI/Lorien.ui          ← 选图 UI 由数据指定
   :5-6 [dungeon] 1 -1 2 -1 1500 428 1501 4340
                 ↑副本 id 1 ↑槽位/图索引
        ↑ 1 = act1/lorien.dgn（dungeon.lst.tsv 第 38 行 `1	act1/lorien.dgn`）
   :9   [hell dungeon] 1 / [hell freepass item] 8272 1 8376 1 8247 1 / [hell quest] 1016

[副本定义]
 export/text/dungeon/act1/lorien.dgn.txt
   :3-4  [entering title] Title/Lorien.ani
   :5-6  [cutscene image] / :7-8 [minimap image] Map/MiniMap/Act1.img
   :9-10 [worldmap pattern info] 1 1 WorldMap/SelectdungeonSlot/elvengard.img 0
   :11   [minimum required level] 1   :13 [basis level] 1
   :15   [experience increasing point] 10.0
   :17   [champion] 0 0 0 0 0                     ← 精英怪替换概率
   :19   [pathgate object] 361 362 … 370          ← 10 个门 = passiveobject id
   :23-24 [size] 2 3                              ← 房间网格 2 列 × 3 行
   :25   [greed]                                  ← 房间连通布局（ASCII）
            JJEE
             LLMM
             DDGG
   :29-30 [start map] 0 0 1 0                     ← 起点格 + 朝向/落点
   :31-32 [boss map]  0 2 1 2                     ← BOSS 格
   :33   [designate dungeon difficulty] 0
   :35   [special passive object item] …          ← 特殊掉落
   :37   [event monster] 1 5000 61726 1 300 80 1
   :39   [name] 洛蘭   :41 [explain] …

 更完整的例子 export/text/dungeon/act6/danceingbutterfly.dgn.txt
   :35-54  [map specification]-N   (列, 行, mapId)
             0 0 6508 / 1 0 6509 / 2 0 6510 / 0 1 6507 / … / 3 4 6501
   :43-44  [boss map specification] 1 1 6512 6513
   :56-58  [start map] 3 4      :59-60 [boss map] 1 1
   :61     [hell dungeon] 1
   :62-64  [seal door map index] 60048 / [seal door pos] 0 2
   :65     [hit count] 50 50 50 50 50
   :66     [seal door appear rate] 10
   :69     [quest connection] 0 5809 1
   :70-72  [size]-1 4 5 + [greed]-1               ← 第二套迷宫（同一副本两种布局）

[地图]
 map__map.lst.tsv:1053  6508  bloodbutterfly/6508(0,0)nomal.map
 map__map.lst.tsv:1046  6501  bloodbutterfly/6501(3,4)start.map
                        ↑ 文件名里内嵌 (列,行) 与角色 start/nomal/boss
 export/text/map/bloodbutterfly/6501(3,4)start.map.txt:5-6  [dungeon] 52
                        ↑ 反向指回 dungeon id 52 = act6/danceingbutterfly.dgn
 export/text/map/lorien/s1.map.txt
   :5-6   [dungeon] 1                     ← 反查副本
   :7-8   [player number] 2 8
   :9-10  [greed] BB BB                   ← 本格自身的房间形状
   :11-12 [tile]                          ← 图块层
   :29-30 [pathgate pos] 15 225 1108 223 554 146 560 348
   :37-38 [passive object]               ← 物件 + 坐标
   :39-40 [monster]  1 1 0 428 180 0 1 1 [fixed] [normal]   ← 刷怪表
   :31-36 [dungeon start area] 272 377 117 43 / [background animation] /
          [sound] AMB_FOREST_01 M_FOREST_01_NEW / [animation] / [monster specific AI]
   :45-46 [map name] PVP無名

[结算]
 ui/result/ 只有 11 个 .act + .ani；无 .ui；全库无 IDC_RESULT / result_rank
 etc/、common/ 无 [rank]/rating/dungeon rank
 → 评分/翻牌/结算布局 = 客户端 + 服务端硬编码（【待验证】具体公式）
 PVP 连招练习留了输入录放样本：etc/pvppracticecombo/replay/*/*.rep（484 个）

[回城]
 结算后由客户端按 town id 重新载入 .twn，落点取该 .twn 中标 [gate] 的那张 map 的坐标
 （`[area]-1 … [gate] 450 234`）
```

### 5.3 一句话总结这条链

**`.lst` 提供 id 空间；`.twn` 给「城 = 哪些 map + 哪个门」；`.rgn`/`.wdm` 给「区域里有哪些城 + 选图 UI 放哪」；`.dgn` 给「副本 = 网格 + 房间布局 + 起终点 + 门物件 + 难度成长」；`.map` 给「这一格 = 图块 + 刷怪 + 物件 + 背景音」；`.map` 的 `[dungeon]` 字段反向指回副本，构成可校验的双向引用。**

> 值得注意的设计：**地图文件名把坐标写进文件名**（`6501(3,4)start.map`），而 `.dgn` 的 `[map specification]` 又存一份 `(列,行,mapId)`。两处重复 → 私有服改名时容易不一致，是个可借鉴的「别这么干」的反面教材。

---

## 6. 机制表达范式表

| 机制类别 | 表达文件 | 关键字段 / 标签 | 数据 or 硬编码 | 证据 |
|---|---|---|---|---|
| **实体属性**（HP/攻/速/抗性/等级） | `.chr`（角色）`.mob`（怪物）`.cre`（宠物） | `[HP MAX]` `[physical attack]` `[move speed]` `[growth type]`；怪物 `[level] [category] [ability category] [* resistance] [cooltime] [think term]` | 数据 | `swordman.chr.txt`；`sarpoza.mob.txt:1-68` |
| **动作池** | `.mob` `[attack action]` 等槽位；`.obj` `[basic motion]`/`[etc motion]` | 具名槽 + 有序 `.act`/`.ani` 数组 | 数据 | `sarpoza.mob.txt:69-97`；`new_swordman_24370.obj.txt` |
| **动作编排**（怪物/物件） | `.act` | `[MOTION]` `[TRIGGER]` `[BEHAVIOR]` + `-N` 编号 + `[DO BEHAVIOR]` | 数据（帧驱动小语言） | §1.4 / §1.5 |
| **动作编排**（角色） | `.nut` | `pushState(job,nut,name,state,skill)` + `onSetState_*` / `onKeyFrameFlag_*` | 数据（Squirrel 过程式） | `swordman_load_state.nut:12`；`attack.nut` |
| **位移 / 弹道** | `.nut`（`sq_StopMove`）；`.act`（`[MOVE ME]` `[TELEPORT]` `[INTERPOLATION MOVE TARGET]`）；`.ani`（帧内位移曲线） | `[MOVE TYPE] [ACCEL] [USE ZPOS OFFSET] [STOP MOVE UNABLE POS]` `[OFFSET]` | 混合：指令在文本、位移曲线在 `.ani` | `steich/action/attack_7.act.txt:46` |
| **攻击 / 命中** | `.skl`（能否用）→ `.nut`/`.act`（什么时候）→ **`.ani` 帧内判定框** → `.atk`（伤害属性） | `sq_SetCurrentAttackInfo(n)`、`[SET DAMAGE BOX] [ON]`、`.atk` 的 `[physical]`/`[element]`/`[push aside]`/`[lift up]` | **属性=数据；几何=二进制** | `attack1.atk.txt`（无几何）；`rosaura/attack_10.act.txt:37` |
| **受击 / 硬直 / 击退** | `.atk` | `[damage reaction]` `[push aside] 30` `[lift up] 75` `[hit down]` `[stuck]` `[bounce]` `[stun]` `[down]` | 数据 | `attack1.atk.txt`；`.atk` 标签频次 |
| **霸体 / 不可中断** | `.act` | `[IGNORE HIT STUN]`(1,821) `[UNINTERRUPTIBLE]`(137) | 数据 | 全语料频次 |
| **技能** | `.skl`（元数据）+ `.nut`（逻辑）+ `.ani`（帧标记）+ `passiveobject`（伤害载体） | `[type] [executable states] [command] [cool time] [level info] [level property]`；`checkExecutableSkill_*` `sq_AddSetStatePacket` `sq_SendCreatePassiveObjectPacket` | 混合；**没有 `[USE SKILL]` 这个标签** | `bloodboom.skl`；`bloodboom.nut:2-80` |
| **状态机** | `.nut` 的 `*_load_state.nut` + `dnf_enum_header.nut` | `pushState`、`STATE_*`、`STATE_PRIORITY_*` | 数据（注册表 + 常量定义） | `swordman_load_state.nut:99`；`dnf_enum_header.nut:202-210,656-660` |
| **增益 / Debuff** | `.apd`（1,867 个，声明式）+ `.nut`（`appendage/*.nut`，过程式） | `[type] [duration] [max overlap] [string data]` 迷你表达式；`sq_AddFunctionName("proc",…)` `setValid(false)` | 双文件表达同一机制 | `haoyue13514.apd.txt`；`ap_wavemark.nut:6,21` |
| **召唤 / 弹幕 / 特效物件** | `.act` `[CREATE PASSIVEOBJECT] [INDEX] n` → `passiveobject__passiveobject.lst` → `.obj` → `.ani` + `.atk` | `[INDEX] [LEVEL] [POS] [SET TOP PARENT] [PARTICLE FILENAME]` | 数据（id 链） | `saya/attack_9.act.txt:23`（74068 = Ice_Wind.obj） |
| **AI 决策** | `.ai`（每难度 4 个） | `[think]` `[true]`/`[false]` `[return] k`（k = 攻击槽下标）、`is target in attack area()` | 数据（数据化行为树） | `sarpoza/ai/action.ai.txt` |
| **随机 / 采样** | `.act` | `[RANDOM] min max`、`[RANDOM SELECT]`(3,245) | 数据 | `rosaura/attack_10.act.txt:27` |
| **掉落** | **不在 PVF**（`etc__independentdrop.lst` 161 条 / `etc__randomoption.lst` 125 条只给候选池） | — | 服务端 | 【待验证】 |
| **任务** | `.qst`（3,852 个）+ `.lst`（340 个） + `.dgn` 的 `[quest connection]` | `[quest connection] 0 5809 1` | 数据 | `danceingbutterfly.dgn:69` |
| **流转**（城→图→副本） | `.lst` + `.twn` `[area]` + `.rgn` `[towns]` + `.wdm` `[dungeon]` + `.dgn` `[map specification]`/`[greed]`/`[start map]`/`[boss map]` + `.map` `[dungeon]` 反查 | 见 §5 | 数据（双向引用） | §5.2 |
| **结算** | 无 | — | 客户端 + 服务端硬编码 | `ui/result/` 无 `.ui`；`IDC_RESULT` 零命中 |
| **UI 摆位** | `.ui`（378 个）；世界地图 `.wdm [ui path]` | `[window] [ui controls] [control] [image] [text] [variable]` | 半数据（摆位=数据，控件/事件=C++） | §4.2 / §4.3 |
| **副本内 HUD** | 无 `.ui`；`sqr/init_character.nut` | `sq_set_hp_pos(224,533)` 等常量 | 硬编码（脚本） | `init_character.nut:53-97` |
| **表现层叠加** | `.als` | `[use animation]` `[none effect add]` `[create draw only object]` | 数据（纯表现，无逻辑） | §2.2 |
| **音效** | `.act` `[PLAY SOUND]`/`[SOUND]`；`.nut` `sq_PlaySound`；`.map` `[sound]` | `[SOUND] <name> <frame>` | 数据 | `saya/attack_9.act.txt:7` |
| **联机同步** | `.nut` 发包 API | `sq_IsMyControlObject()` + `sq_BinaryStartWrite` + `sq_SendCreatePassiveObjectPacket` | 数据（协议即范式） | `attack.nut:56-68` |

---

## 7. 对 Godot 4 实现的直接启示（可执行结论）

1. **动作编排分两套，别硬统一**。怪物用「声明式帧事件表」最省事（`.act` 的 `[TRIGGER]/[BEHAVIOR]` 直接映射成 `AnimationPlayer` 的 keyframe call + `Resource` 数组）；角色用「脚本」（GDScript / 或一个轻量自定义 VM）。原版就是这么分裂的，照抄这个分裂反而好维护。
2. **判定框必须进动画资源**。原版把 hitbox 放在 `.ani`（二进制）里，`.atk` 只放属性——这个「几何与属性分离」的设计是对的：`AttackInfo` 资源（属性）+ `Animation` 里的 `Area2D` 关键帧（几何）。不要试图把几何塞进 `.atk` 等价物。
3. **伤害源用「被动对象」模式**。`sq_SendCreatePassiveObjectPacket(id)` 意味着「技能本身不判伤，它生成一个独立的伤害实体」。Godot 里就是 `PackedScene` + `id → scene` 字典，好处是同屏多段伤害/延迟判定/弹道全部统一。
4. **状态机用 `pushState` 式的注册表**，不要用 enum + match。原版 `pushState(job, script, name, stateId, skillId)` 让「加一个技能」= 加一行注册 + 一个脚本文件，这才是它 244 个剑士技能能维护的原因。
5. **UI 分三档做**：世界地图/选图 → 数据驱动（`.ui` + 热点坐标）；背包/技能/选项 → 每个窗口一个场景（**不要**复刻 `.ui` 的绝对坐标摆位，那是 800×600 时代的产物）；副本 HUD → 一个 `CanvasLayer` + 常量锚点（对应 `init_character.nut`，但要改成锚点百分比以适配分辨率）。
6. **联机接口现在就留**：所有「生成对象 / 切状态 / 命中」都走一个 `Event` 结构 + `EventBus`，本地直接 `apply(event)`，联机时 `broadcast(event)` 后各端 `apply`。这就是 `sq_IsMyControlObject()` + `sq_Send*Packet` 的等价物，改动成本几乎为零。
7. **数值公式不要从 PVF 里找**（伤害/掉落/经验/评分都不在）。用 `.skl`/`.mob` 里的系数做「输入」，公式自己设计。

---

## 8. 待验证清单

| # | 事项 | 现状 | 下一步 |
|---|---|---|---|
| 1 | `.ani` 版本 6 的帧结构（含攻击框几何、帧标记 flagIndex、位移曲线） | 未解析（`docs/PVF-FORMAT.md` P0.5） | 需要一个 `.ani` 解析器；样本建议 `character/swordman/animation/bloodboom.ani.bin` |
| 2 | 基础动画索引（`sq_SetCurrentAnimation(37)`）↔ `.ani` 文件 | 无数据表，疑似 exe 内置 | 反查客户端；或对比 `CUSTOM_ANI_*` 命名规律推测 |
| 3 | 攻击属性索引（`sq_SetCurrentAttackInfo(36)`）↔ `.atk` 文件 | 同上 | 试按目录字母序/`.lst` 序建立映射并抽样验证 |
| 4 | `109084869` 这个 passiveobject id 不存在于注册表 | 数据瑕疵 or 局部 id 空间 | 抽查其他 `.act` 是否也有此现象 |
| 5 | 结算评分 / 翻牌 / 掉落公式 | 全库无数据 | 查服务端；PVF 只留候选池 `etc__independentdrop.lst` |
| 6 | `.act` 的 `[PROC]` 章语义（2,938 次） | 未细读 | 找一个含 `[PROC]` 的 `.act` 与 `[proc action]` 槽位对照 |
| 7 | `[PULL APPENDAGE] 7 3 4000` 参数含义 | 猜测 (appendage 类型, 强度, 时长) | 找 `appendage.lst` 里的 id 对照 |

---

## 附录 A：本文用到的辅助脚本

| 脚本 | 作用 | 说明 |
|---|---|---|
| `scripts/dump_nut.py` | 剥掉 `.nut` 内嵌 NUL 字节并加行号输出 | 部分 `.nut` 含 1 个 `0x00`（如 `character/swordman/attack/attack.nut`），直接 `read`/`grep` 会被判为二进制拒读。用法：`.venv/bin/python scripts/dump_nut.py <path> [start] [end]` |

> 环境注意：系统无 `sqlite3` CLI，查索引请用 `.venv/bin/python -c "import sqlite3; ..."`；`files.ext` 列**不带点**（是 `act` 而不是 `.act`）。

## 附录 B：本文引用的关键文件清单

```
export/text/sqr/character/swordman_load_state.nut.txt          ← 角色状态机注册
export/text/sqr/character/swordman/attack/attack.nut.txt       ← 普攻逻辑
export/text/sqr/character/swordman/bloodboom/bloodboom.nut.txt ← 技能逻辑
export/text/sqr/character/swordman/appendage/ap_wavemark.nut.txt
export/text/sqr/character/swordman/swordman_header.nut.txt     ← 状态/动画常量
export/text/sqr/dnf_enum_header.nut.txt                        ← 全局枚举镜像
export/text/sqr/init_character.nut.txt                         ← HUD 硬编码坐标
export/text/skill/swordman/swordman_bloodboom.skl.txt          ← 技能元数据
export/text/character/swordman/swordman.chr.txt                ← 角色数值
export/text/character/swordman/attackinfo/attack1.atk.txt      ← 攻击属性（无几何）
export/text/passiveobject/script_sqr_nut/swordman/new_swordman_24370.obj.txt
export/text/appendage/xmn/haoyue13514.apd.txt                  ← 增益声明 + 迷你表达式
export/text/monster/poongjintrainingroom/sarpoza/sarpoza.mob.txt   ← 动作槽表
export/text/monster/poongjintrainingroom/sarpoza/ai/action.ai.txt  ← AI 伪代码
export/text/monster/championtower/saya/action/attack_9.act.txt     ← 最简 .act
export/text/monster/bakalraid/monster/steich/action/attack_7.act.txt ← 完整 .act
export/text/monster/poongjintrainingroom/rosaura/action/attack_10.act.txt ← 判定框开关
export/text/ui/hud/hud.ui.txt / ui/inventory/*.ui.txt          ← .ui 语法
export/text/town/1_new/new_elvengard.twn.txt                   ← 城镇
export/text/region/shonan.rgn.txt                              ← 区域
export/text/worldmap/lorien.wdm.txt + worldmap/ui/lorien.ui.txt ← 选图（数据驱动 UI）
export/text/dungeon/act1/lorien.dgn.txt                        ← 副本（简单）
export/text/dungeon/act6/danceingbutterfly.dgn.txt             ← 副本（完整）
export/text/map/lorien/s1.map.txt / bloodbutterfly/6501(3,4)start.map.txt
export/_meta/lst/{town,dungeon,map,worldmap,region,passiveobject}__*.tsv
```
