# 08 · 任务 / 活动 / 宠物 / 唯一兽（.qst / .evt / .cre）

> 范围：任务怎么定义与结算、NPC 怎么串任务、活动怎么配置、宠物怎么成长。
> 数据源：`n_quest/**/*.qst`（3,852；注册表 `n_quest__quest.lst` 仅 339 条）、`n_quest/questparameter.etc`（任务经济总表）、`n_quest/quest.chn.str`（2.6MB 本地化串）、`quest/epicquest.lst`、`quest/trainingquest.lst`、`*.evt`（82）、`npc/*.npc`（811）、`creature/**/*.cre`（631，注册表 566）。
> 官方标签释义：`export/_meta/tagdict.sqlite`（`ext='qst'` 有大量字段带完整官方注释，本文多处直接引用）。
> 相邻文档：任务的目标是副本/怪物/物品 → [07-map.md](07-map.md)、[06-monster.md](06-monster.md)、[05-item.md](05-item.md)；NPC 对话的 UI → [09-script-mechanics.md](09-script-mechanics.md)。

---

## 0. 一句话结论

任务系统是**「一个枚举 + 一个变长参数数组」**的设计：

```
[type]（8 种完成条件）+ [int data]（长度与含义完全由 type 决定）+ [sub type]（type 的子判定）
```

**整个任务体系没有一条脚本**。3,852 个任务全靠这套「枚举 + 参数」+ 一张全局经济表（`questparameter.etc`）跑起来。这是本作最该 1:1 复刻的系统：**数据结构极简，但表达力靠枚举铺满**。

三个反直觉发现：

1. **任务不按 id 组织，按路径组织**。`quest.lst` 只登记 339 条「重要任务」，而 `.qst` 文件有 3,852 个——说明**绝大多数任务靠文件名/路径寻址**，注册表只给主线/重要任务留号。复刻时用「任务 id + 分类目录」更省事。
2. **奖励经过两次放大**：`[difficulty]` 是**单字符常数**（`S`/`A`/`B`/`D`/`Y`…），其数值在 `questparameter.etc [difficulty]` 里定义（`S 115 A 90 B 70 C 50 D 200 …`），最终金额 = `[exp/gold reward table][等级] × 难度% × [gold multiple]%`。**一个字母就是一条乘法链**。
3. **宠物自带一套完整技能系统**：`[skill list]` → 每个 `[skill node]` 都是一份 `.skl` + 一份 `.atk` + 一个动作动画，还有 `[over skill *]`（超越技能）与 `[selective grow creature]`（分支进化）。宠物不是挂件，是**第二个可编程角色**。

---

## 1. `.qst`（任务）

### 1.1 身份与可见性

| 字段 | 官方名 | 含义 | 取值 | 必填 |
|---|---|---|---|---|
| `[name]` | 任务名称 | `<11::name_xxxx>` 引用 `quest.chn.str` | 本地化串 | ✅ |
| `[grade]` | 任务品级 | 决定任务簿**颜色与排序** | `[normaly repeat]` / `[common unique]` / `[epic]`（主线）/ `[achievement]` / `[daily]` / `[training]` / `[title]` | ✅ |
| `[level]` | 可行等级范围 | 接取等级下限、上限（**上限目前不生效**） | 两整数，如 `40 120` | ✅ |
| `[quest point]` | 任务点数/分类值 | 单数值分类参数（实测 0/4/8/10/14/30），精确映射**未闭合** | 整数 | ✅ |
| `[job]` | 可接受任务的职业 | 职业白名单 | `[all]` / `[swordman]` / `[fighter]` / `[gunner]` / `[mage]` / `[priest]` / `[thief]` / `[at swordman]` … | ✅ |
| `[grow type]` | 可行成长类型 | 转职限制，`-1` = 不限 | 整数 | ✅ |
| `[target character]` | 目标角色（可多职业组合） | `[job]`+`[grow type]` 的**合并替代写法**，可重复 (职业, 转职, 觉醒) | 三元组 × N | ❌ |
| `[npc index]` | 接取 NPC | NPC id | 整数 | ✅ |
| `[complete npc index]` | 完成 NPC | `-1` = 与接取同 | 整数 | ✅ |
| `[exposed by npc]` | 由 NPC 曝光 | 0/1 | ❌ |
| `[pre required quest]` | 前置任务 | 可多个（**与**关系）；若出现第二个该块，则两组之间是**或**关系 | task id × N | ❌ |
| `[relation quest]` | 关联任务（完成后自动接取） | `-1` 或无 = 无 | task id | ❌ |
| `[cant giveup]` | 放弃限制 | `0` 完成后可放弃（默认）/ `1` 不可放弃 / `2` 队伍成员也可放弃 | 0-2 | ❌ |
| `[event]` | 活动任务 | `1` = 置顶、最高优先级标记 | 0/1 | ❌ |
| `[epic]` / `[daily]` / `[achievement]` / `[urgent]` | 主线 / 每日 / 成就 / 紧急 | 标记 | — | ❌ |
| `[exception quest]` | 例外任务列表 | 反引号字符串/token | — | ❌ |
| `[level]` 之外还有 `[exceptional grow type]` | 例外转职 | — | — | ❌ |

### 1.2 完成条件（核心）

| 字段 | 官方名 | 取值 |
|---|---|---|
| `[type]` | 任务完成条件类型 | 见下表 8 种 |
| `[sub type]` | 任务子类型 | 与 `[type]` 配合，见下 |
| `[int data]` | 整数数据 | **长度与含义完全由 `[type]` 决定** |

**`[type]` 枚举 × `[int data]` 编码**（官方 + 实测交叉确认）

| `[type]` | 含义 | `[int data]` 编码 | 实测 |
|---|---|---|---|
| `[seeking]` | 需要道具 | `物品id 数量` | `4342 15` |
| `[hunt monster]` | 击杀怪物 | `副本代码 难度 怪物ID 数量` × N | — |
| `[hunt enemy]` | 击杀敌人（含 APC） | `副本id 难度 怪物id 1 次数` × N（**5 元组、无前导计数**） | `62 -1 61809 1 2 63 -1 61128 1 2 …` |
| `[condition under clear]` | 限定条件通关 | `副本代码 难度 [可选：组队人数/限时]` | — |
| `[meet npc]` | 对话 NPC | `npcId` | `18` |
| `[clear map]` | 通关地图 | `mapId`；`[dungeon info]` 另给 `副本id 难度` | `5014` + `[dungeon info] 34 2` |
| `[custom quest]` | 自定义（学技能/加点） | 三个数值 | — |
| `[disjoint item]` | 分解装备 | 数量 | — |

**`[sub type]`（仅 `[condition under clear]` 时有效，官方完整表）**

`0` 限时通关 · `1` 累计被击数低于指定量 · `2` 技巧评分高于指定量 · `3` 风格评分高于指定量 · `4` 不使用复活币通关 · `5` 指定队伍人数通关 · `6` 直接通关 · `7` 达到特定连击评分 · `8` 背击成功次数 · `9` 破招成功次数 · `10` 最大连击数 · `11` 通关指定数量的地图 · `12` 限制技能使用次数 · `13` 限制消耗品使用 · `14` 限制材料道具使用 · `15` 限制多…（官方截断）

> `[type] = [clear map]` 且为 APC 同行任务时 `[sub type] = 0`。

### 1.3 奖励

| 字段 | 官方名 | 含义 |
|---|---|---|
| `[reward type]` | 任务奖励类型 | `[item]` / `[title]` 点亮称号簿 / `[hero]` 开英雄级地图 / `[grow type]` 转职 / `[expert job]` 副职业 / `[slot expansion]` 左右槽 / `[hell challenge]` 开深渊 / `[awakening type]` 觉醒 / `[creature evolution]` 宠物进化 / `[event creation]` 活动创建 |
| `[reward int data]` | 固定奖励 | **两值一组 = 代码 + 数量**；**代码 `0` = 金币**，触发 `[gold multiple]`；可用 `[job]` 语法按职业发 |
| `[reward selection int data]` | 可选奖励（多选一） | 两种写法：①两值一组（同上一行）；②**五值一组** = `道具ID + [job] + 职业类型 + 转职限制(-1不限) + 数量`；职业类型 `0`男鬼剑/`1`女格斗/`2`男枪手/`3`女魔法/`4`男圣职 |
| `[gold multiple]` | 金币奖励倍数 | 百分比；**实际金额 = 等级奖励基数 × 任务难度 × 倍数** |
| `[difficulty]` | 任务奖励难度 | **单字符常数**（`S`/`A`/`B`/`D`/`Y`…），数值在 `questparameter.etc` 定义 |
| `[ignore quest level 4 exp]` | 经验跟随角色等级 | `1` = 经验与金币**跟随角色等级**而非任务等级，且任务标题**始终保持橙色**；缺省 `0` |

### 1.4 任务期间掉落（两条独立通道）

| 字段 | 每组成员数 | 编码 |
|---|---|---|
| `[monster reward item]` | **7** | `怪物ID, 副本编号, 副本难度, 物品代码, 每次获得数量, 出现概率(%), 获得上限(-1无上限)` |
| `[enemy reward item]` | **8** | `怪物编号, 敌人类型(1怪物/2APC/3obj), 副本编号(-1不指定), 副本难度(-1), 物品编号, 每次获得数量, 出现概率(%), 获得上限(-1)` |

> 这条设计很妙：**"打怪掉任务道具"不由怪物配置，而由任务配置**。同一只怪在接不同任务时掉不同东西，无需改 `.mob`。复刻时务必保留——否则任务道具要么写进掉落表污染全局，要么硬编码。

### 1.5 文本与呈现

| 字段 | 含义 |
|---|---|
| `[depend message]` | 接受任务时的对话（`<11::depend_message_xxxx>`） |
| `[solve message]` | 完成时的提示（`<11::solve_message_xxxx>`） |
| `[condition message]` | 任务栏的详细条件提示（`<11::condition_message_xxxx>`） |
| `[job message]` | **按职业显示不同文本**，与上述三者配合 |
| `[substitutive names]` | 替换任务界面中的对象名；数量须与 `[int data]` 的对象种类数一致，空串 = 不显示 |
| `[dungeon info]` | 任务窗口显示的副本目的地（`副本id 难度`）；`[clear map]` 时必填 |

---

## 2. 任务经济总表：`n_quest/questparameter.etc`

**这是全库最重要的"一个国家预算表"**，2.6KB 决定所有任务的产出。

```
[difficulty]
    S 115 A 90 B 70 C 50 M 10 Z 400 Y 370 X 340 W 300 O 10 E 40 F 60 G 80 D 200 U 250
[exp reward table]
    100 156 254 365 488 625 775 1251 1485 3473 4011 5042 5711 6419 7163 …
[gold reward table]
    72 101 130 158 187 216 245 281 317 360 403 454 504 554 605 …
[green level penalty]  80
[grey level penalty]   30
[bal kun penalty]      5
[piece reward table]   1 6 2 12 3 18
[piece reward]         [physical attack] 1 + 100 [physical defense] + 100 … [attack speed] % 2 …
[quest parameter end]
```

| 字段 | 含义 | 判读 |
|---|---|---|
| `[difficulty]` | **难度字符 → 百分比** | 15 对（实测长度 30）＝`S`=115%、`A`=90%、`B`=70%…`Z`=400%。这就是 `[difficulty]` 字符常数的定义处 |
| `[exp reward table]` | 等级 → **经验基数** | 首值 `100`；**索引键未闭合**（序列非严格单调，见样例 A 注） |
| `[gold reward table]` | 等级 → **金币基数** | 首值 `72`；与经验表同为 **200 项** |
| `[green level penalty]` `80` | 绿色（等级偏高）任务的经验惩罚 | 保留 80% |
| `[grey level penalty]` `30` | 灰色（等级过低）任务的惩罚 | 保留 30% |
| `[bal kun penalty]` `5` | 惩罚下限 | |
| `[piece reward table]` | 任务碎片数 → 奖励档位 | 3 对：`1→6, 2→12, 3→18` |
| `[piece reward]` | 档位 → 属性加成 | `[physical attack] +100` / `[attack speed] % 2` |

> **结算公式（复刻用）**
> `经验 = exp_table[等级] × difficulty% × 等级惩罚%`
> `金币 = gold_table[等级] × difficulty% × [gold multiple]% × 等级惩罚%`
> 等级选「任务等级」还是「角色等级」由 `[ignore quest level 4 exp]` 决定。

---

## 3. NPC（`.npc`）—— 任务的接线柱

`npc/danjin1.npc` 实测（节选）：

```
[small face]   Map/Npc/NpcFace03.img 17
[big face]     Map/Npc/NpcFace03.img 16
[popup face]   Map/Npc/NpcFace02.img 63
[field animation]  Animation/Npc_dj1.ani
[field wav]    R_NPC_JAR_AMB_LOOP
[popup wav]    R_NPC_JAR_TALK R_NPC_JAR_FAREWELL
[role]
    [item shop] 13
[name]         火罐
[field name]   火罐
[quest speech] 我叫火罐！ 我的袖珍罐， 絕對比土罐哥哥的好！
[dialog]       1 1 100 -1 0 0 <npc::20>我們是帝國傳承道具挖掘團的成員…
[dialog]-1     2 1 100 -1 0 0 <npc::20>我出售初級冒險家喜歡的袖珍罐！…
[dialog]-2     3 1 100 -1 2 0 <npc::20>真是的！ 忙死了！…
[favor_dialog] 3 0 0 <npc::20>我破例給你展示了我超強的力量！…
[favor_dialog]-1 3 0 1 <npc::20>能有人陪我聊天， 我就很滿足了…
```

| 字段 | 官方名 | 含义 |
|---|---|---|
| `[name]` / `[field name]` | 内部名 / 场景显示名 | `[name]` 是 PVF 内部标识，`[field name]` 是头顶显示的称呼 |
| `[role]` | NPC 的各项功能 | 子标签：`[item shop] N`（商店号）/ `[skill]`（导师技能商店）/ `[move town] N`（移动到城镇） |
| `[dialog]` | 对话 | 每行 = `对话索引 等级限制 概率? -1 …` + `<npc::20>文本`（前几个数值的列义待验证） |
| `[speech]` | 一段对话开始 | **对话树节点**：对话索引、等级限制、标题（按钮文字）、内容、子对话索引；初次对话从 1 号索引开始 |
| `[favor_dialog]` | 好感度对话 | 每行 = `阶段 礼物等级 ?` + 文本（好感度系统） |
| `[quest speech]` | 任务台词 | 接任务时的台词 |
| `[balloon message]` | 气泡消息 | |
| `[look around]` | 环顾四周 | `0` = 固定朝向；缺省 `1` = 朝向玩家 |
| `[item shop]` / `[skill]` / `[move town]` | 商店 / 导师技能 / 区域移动 | `[skill]` 写作 `[swordman] 1` = 男鬼剑 1 号技能（左侧技能编号、右侧等级） |
| `[move town confirm str]` / `[move town limit str]` | 移动确认/限制弹窗串 | |

> **导师技能商店**是「技能怎么获得」的答案之一：技能不由角色自己的 `.chr [skill]` 全给，而是**NPC 卖**。`.chr [skill]` 是初始赋予，NPC 的 `[skill]` 是后续购买。

---

## 4. 活动（`.evt`）

`.evt`（82 个）是**活动配置容器**，一个文件 = 一个活动，插件式自定义块。

`event/bingoevent.evt` 实测：

```
[use item]     3037 3037 3037 3037 3037        ← 消耗哪些道具（5 格 = 5 条线？）
[reward]       2 1 1 1 3 900 1                 ← 奖励参数
[board]        31 1 13 2 10 50 1 28 …          ← 宾果盘面（数字=奖励格权重）
[quiz value]   31 1 84 2 63 3 86 4 22 5 …      ← 格子 → 数值
```

| 字段 | 官方名 | 含义 |
|---|---|---|
| `[event info]` | 活动资讯 | 整体信息：名称、类型、持续时间、参与条件 |
| `[entry]` | 条目 | 一个活动可含**多个条目**，各定义不同奖励条件/怪物配置/邮件内容 |
| `[idx]` | 活动编号 | 活动唯一标识，其余配置用它关联 |
| `[reward]` | 完成获得的奖励 | 道具 id、数量、金币、经验 |
| `[mail title]` / `[mail content]` | 邮件标题/正文 | 活动奖励通过邮件发 |
| `[can not give item]` | 不可赠送物品 | 活动期间禁止交易/赠送的道具 |
| `[job const]` / `[job type]` / `[select group]` / `[step]` / `[sub type]` | 职业常量 / 职业类型 / 选择分组 / 阶段 / 子类型 | 活动内按职业/阶段分支 |
| **自定义块** | — | 每个活动可定义私有块（`[board]`/`[quiz value]`…），由服务端逻辑解释 |

另有 `event/eventserver/eventserverworlddrop.evt`（97KB）——**活动期间改写全局掉落表**。这说明 `etc/worlddrop.etc` 有「可被活动覆盖」的设计。

> **单机版建议**：`.evt` 是纯服务端驱动的，**不在最小集内**。但「活动任务」在 `.qst` 侧只靠 `[event] 1` 一个标记就实现了置顶——这个必须留（用来做限时支线）。

---

## 5. 宠物（`.cre`）

### 5.1 面板与外观

`creature/woodendoll/woodendoll.cre` 实测：

```
[name]            地獄犬
[width]           10 10
[floating height] 0
[character span]  -50
[layer]           [normal]
[direction correct] 1
[move speed]      286 238 114 95 70      ← 5 档速度（走/跑/…）
[gravity]         1500
[start level]     1
[permission level] 1
[max level]       50
[parent max level] 50
[artifact slot]   red blue green
[learn overskill level] 100
[basic motion]    Animation/woodendoll_stand.ani
[walk motion]     Animation/woodendoll_walk.ani
[run motion]      Animation/woodendoll_run.ani
[response motion] Animation/woodendoll_call.ani
[get exp motion]  Animation/woodendoll_exp.ani
[random motion]   Animation/woodendoll_random.ani
[revision x]      0
[revision y]      0
```

| 字段 | 官方名 | 含义 |
|---|---|---|
| `[name]` `[width]` `[floating height]` | 名称 / 宽度 / 浮游高度 | 同 `.mob` 语义 |
| `[character span]` | 角色间距 | 宠物相对角色的水平偏移 |
| `[layer]` | 图层 | `[normal]` / `[bottom]` 等 |
| `[direction correct]` | 朝向修正 | 0/1 |
| `[move speed]` | 移动速度 | **5 档**（走/跑/…各自一档） |
| `[gravity]` | 重力 | |
| `[start level]` / `[permission level]` / `[max level]` / `[parent max level]` | 起始等级 / 许可等级 / 上限等级 / **受主人等级限制的上限** | 宠物有**独立等级**，且 `[parent max level]` 把宠物等级绑在角色等级上 |
| `[artifact slot]` | 宠物装备槽 | `red blue green`（宠物专属装备，`.equ` 走同一套） |
| `[learn overskill level]` | 学习超越技能等级 | 达到该等级才可学超越技能 |
| `[basic/walk/run/response/get exp/random motion]` | 主动画/行走/奔跑/响应/获得经验/随机动作 | `.ani` 路径 |
| `[revision x/y]` | 修正坐标 | |

### 5.2 宠物技能系统（第二个可编程角色）

```
[skill list]
    [skill node]
        [skill type]          0 general skill
        [skill name]          烏登攻擊
        [skill explain]       利用身體的一部分攻擊前方的敵人。
        [skill recovery time] 40000            ← 毫秒
        [learn skill level]   1
        [skill mp]            10
        [skill motion]        Animation/woodendoll_skill(A1).ani
        [skill under effect]
        [skill over effect]
        [skill info]          skill/skill1.skl   ← 一个完整 .skl！
        [attack info]         AttackInfo/attack1.atk
    [skill node]-1 … -3                        ← 共 4 个技能节点
[using random skill]
    1
```

| 字段 | 官方名 | 含义 |
|---|---|---|
| `[skill node]` | 技能节点 | 每节点 = 一个宠物技能；**节点按 0..N 编号** |
| `[skill type]` | 技能类型 | `0 general skill` 普通技能（另有超越技能等） |
| `[skill name]` / `[skill explain]` | 名称 / 说明 | 文本 |
| `[skill recovery time]` | 技能恢复时间 | **毫秒**，用后回到攻击待机的冷却 |
| `[learn skill level]` | 学习技能等级 | 多少级学会 |
| `[skill mp]` | 技能 MP | 消耗主人 MP？待验证 |
| `[skill motion]` | 技能动作动画 | `.ani` |
| `[skill under effect]` / `[skill over effect]` | 技能下层/上层效果 | 特效 |
| `[skill info]` | 技能信息 | **指向一个 `.skl`** —— 宠物技能用玩家技能系统描述 |
| `[attack info]` | 攻击信息 | `.atk` |
| `[using random skill]` | — | `1` = 随机选技能 |

> 宠物技能 = `.skl` + `.atk` + `.ani` 三件套，**与玩家技能同构**。所以「宠物会放技能」不需要新系统，只需要一个宠物专用的施法者。

### 5.3 进化（三种）

```
[selective grow creature]          ← 分支进化
    [using exp item]        1
    [grow Atype item index] 8472   ← A 路线道具
    [grow Btype item index] 8473   ← B 路线道具
    [grow level]            10
    [grow Atype creature id] 123   ← A 路线结果宠物
    [grow Btype creature id] 126   ← B 路线结果宠物
```

| 字段 | 官方名 | 含义 |
|---|---|---|
| `[evolution quest]` | 进化任务 | 完成该任务才可进化 |
| `[evolution creature id]` | 进化宠物 id | 线性进化结果 |
| `[selective grow creature]` | **分支进化** | 用不同道具 → 不同结果宠物（`Atype`/`Btype` 两条线 + 等级门槛） |

> 加上 `.qst [reward type] [creature evolution]`：**宠物进化是任务奖励的一种**。三个系统在这里咬合。

---

## 6. 唯一兽

**结论：在数据层，唯一兽与普通宠物共用同一套 `.cre` 格式与 `creature.lst` 注册表，没有独立的 `[unique]` 标签。**

证据：全库 `creature/**/*.cre` 中检索 `unique` 只命中**动画路径片段**（`thief/animation/unique_1st/sinsuthiefstay_03.ani`，来自 `creature/2020new/diy_ry13/diyry10.cre`），不是字段名；`tagdict.sqlite` 的 `ext='cre'` 下也没有任何「唯一」相关标签。

因此「唯一性」属于**服务端/运营约束**（同账号只能有一只、不可交易等），在客户端 PVF 里没有对应字段。宠物侧的差异只体现在：
- 更复杂的 `[selective grow creature]` / `[evolution quest]`（成长线）
- 更完整的 `[artifact slot]` 与 `[over skill *]`（超越技能）
- id 段不同（`creature.lst` 内）。

> **复刻建议**：单机版**不做「唯一」概念**；若要，用一个 `unique: bool` + 存档标记即可（属游戏规则，不是数据）。存档里的宠物实例记录 `creatureId + level + exp + 已学技能 + 装备槽`。

---

## 7. 样例原文 + 解读

### 样例 A：`n_quest/alphraira/magmacave/epic_40_magmacave_titan_4.qst`（通关地图型主线）

```
[grade]      [epic]
[difficulty] Y
[gold multiple] 250
[npc index]  26
[complete npc index] -1
[job]        [all]
[grow type]  -1
[level]      40 120
[pre required quest] 49
[quest point] 10
[type]       [clear map]
[sub type]   -1
[int data]   5014
[dungeon info] 34 2
[reward type] [item]
[reward int data] 0 100 7589 1
[reward selection int data]
[name]       先發制人
```

**解读**
- `[difficulty] Y` → 查 `questparameter.etc [difficulty]`：`Y` = **370%**。这是"一个字母 = 一条乘法链"的实例：`Y` → 370% → 乘到经验/金币基数上。
- ⚠️ 基数表的**索引方式未闭合**：`[exp reward table]` 与 `[gold reward table]` 都非严格单调（经验表第 24、40、44 项比前一项小，如 `… 39822 34730 36310 …`），说明它未必是「1 基的等级索引」，也可能是按别的键（任务等级基数/版本追加）。复刻时先用自己的一条单调曲线，不要照抄数值。
- `[reward int data] 0 100 7589 1` = **两对**：`(0, 100)` 是金币（代码 0 = 金币，实际 = 100 × `[gold multiple] 250%` = 250）、`(7589, 1)` 是物品 7589 × 1。**`[reward int data]` 是变长对列表，不是固定长度**。
- `[type] [clear map]` + `[int data] 5014`（map id）+ `[dungeon info] 34 2`（副本 34、难度 2）：**完成条件是"通关 5014 这张图"**，任务窗口显示"去 34 号副本（王者级）"。
- `[pre required quest] 49`：前置是 49 号任务，形成**任务链**；配合 `[relation quest]` 可自动接下一环。
- `[quest point] 10`：分类值 10（实测常见值 0/4/8/10/14/30，含义未闭合）。
- `[complete npc index] -1`：完成后回 26 号 NPC 交（和接取同一个）。

### 样例 B：`n_quest/alphraira/noirpera/scroll_61_noirpera2.qst`（对话型成就）

```
[grade]      [achievement]
[ignore quest level 4 exp] 1
[difficulty] D
[gold multiple] 200
[npc index]  18
[complete npc index] 18
[exposed by npc] 0
[job]        [all]
[grow type]  -1
[level]      61 120
[pre required quest] 138
[quest point] 0
[type]       [meet npc]
[sub type]   -1
[int data]   18
[reward type] [item]
[reward int data] 4152 2 0 20000
```

**解读**
- `[type] [meet npc]` + `[int data] 18`：完成条件就是**和 18 号 NPC 说话**。整个任务零战斗，是纯剧情/引导。
- `[ignore quest level 4 exp] 1`：因为这个标记，**奖励按角色等级算而不是任务等级 61**，所以 61 级角色做这个任务不会因为"任务等级太高"而拿到超额奖励。官方注释还补了一条 UI 语义：**任务标题始终保持橙色，不会变灰**。
- `[reward int data] 4152 2 0 20000` = 物品 4152 ×2 + 金币 20000（× 200%）。
- `[grade] [achievement]`：成就类任务，在任务簿里有独立颜色与排序权重。
- 注意 `[int data]` 只有 **1 个数**——**解析器必须按 `[type]` 决定读几个数**，不能统一读成定长数组。

### 样例 C：`creature/woodendoll/woodendoll.cre`（见 §5 摘录）

**解读**
- `[move speed] 286 238 114 95 70`：5 档速度。宠物在不同状态下（跟随/奔跑/被召唤…）取不同档——**宠物移动不是单一速度**。
- `[max level] 50` + `[parent max level] 50`：宠物能练到 50 级，但**上限也被主人等级卡住**。这是双约束，不能只存一个。
- 4 个 `[skill node]` 结构完全相同，只是 `skill1..4.skl` + `attack1..4.atk` + `Animation/woodendoll_skill(A1/A2/B1/B2).ani` 不同。**A/B 两条分支各 2 个技能**，与 `[selective grow creature]` 的 A/B 进化路线对应——**进化改变的不只是外观，还有技能表**。
- `[using random skill] 1`：宠物放技能是随机的，所以「技能选择」被下放给引擎而不是数据。

---

## 8. 系统联动

```
NPC(.npc) ──[item shop]/[skill]/[move town]──▶ 商店 / 技能学习 / 区域移动
   │
   └──[quest speech] + .qst [npc index]/[complete npc index] ──▶ 任务接取/交付
                                                                    │
 .qst [type]+[int data] ──▶ 目标：副本(.dgn) / 怪(.mob) / 物品(.equ,.stk) / 地图(.map) / NPC
 .qst [monster reward item]/[enemy reward item] ──▶ 临时改写掉落（不改 .mob）
 .qst [reward *] ──▶ 道具 / 称号 / 转职 / 觉醒 / 左右槽 / 宠物进化
 .qst [difficulty] ──▶ questparameter.etc [difficulty] ──▶ exp/gold table ──▶ 最终奖励
 .cre ──[skill info]──▶ .skl ──▶ (03-skill)
      ──[attack info]──▶ .atk ──▶ (04-combat)
      ──[movtion]────▶ .ani
      ──[evolution *]──▶ .cre（另一只）+ .qst（进化任务）
      ──[artifact slot]──▶ .equ（宠物装备，见 05）
.evt ──[reward]/[mail]──▶ 道具邮件；eventserverworlddrop.evt ──▶ 覆盖 etc/worlddrop.etc
```

- **任务↔副本**：`.dgn [quest connection]`（进行中/已完成 + 任务 id + 难度）与 `.qst [dungeon info]` **双向声明**，任意一侧都能查。
- **任务↔地图**：`.dgn` 的 `[quest connection]` 让副本入口在有小任务时闪烁（`.qst [dungeon info]` 官方注释点名了这个 UI 行为）。
- **宠物↔装备**：`[artifact slot] red blue green` 三色槽 + 宠物装备走 `.equ`。
- **活动↔掉落**：`eventserverworlddrop.evt` 覆盖全局掉落，说明掉落表是**可运行时替换的资源**而不是常量。

---

## 9. 复刻时必须实现的最小集

### M1 必须

1. **`QuestDef`**：id、name、grade（7 枚举）、level(lo,hi)、job/growtype 白名单、giverNpc/completeNpc、preQuests[]、relationQuest、`type` + `params[]`（变长）+ `subType`、rewardType、rewardFixed[]（`code,count` 对，code 0 = 金币）、rewardSelect[]、goldMultiple、difficulty(字符)、dungeonInfo。
2. **8 种 `[type]` 的判定器**：至少 `seeking`（背包计数）/`hunt monster`/`hunt enemy`/`meet npc`/`clear map`。每种负责「从 params 解出目标 + 在事件里累加进度」。
3. **任务状态机**：`未接 → 进行中 → 可交付 → 已完成`，加 `放弃`。事件源：击杀、拾取、进图、通关、对话。
4. **奖励结算**：`exp_table[level] × difficulty% × 惩罚%`、`gold_table[level] × difficulty% × goldMultiple%`。
5. **`questparameter.etc` 等价物**：难度字符表 + 经验表 + 金币表 + 两级等级惩罚。
6. **NPC 最小功能**：`[dialog]`/`[quest speech]` 台词、任务列表、`[item shop]`、`[skill]` 卖技能。
7. **宠物**：`CreatureDef`（面板 + 动作 + `[parent max level]` 双等级约束）+ 跟随/攻击待机 + `skill node` 技能（`.skl` 同构 + `.atk`）+ 冷却（`skill recovery time`）。

### M2 应当

8. **任务道具掉落通道**（`[monster reward item]` / `[enemy reward item]`）——**这一条很容易被跳过，但它是"任务不污染全局掉落"的关键**。
9. **`[pre required quest]` 的与/或语义**（两组之间是或）+ `[relation quest]` 自动接取 → 任务链。
10. **`[reward selection int data]` 的按职业分支**（五值写法）。
11. **`[ignore quest level 4 exp]`**（奖励跟随角色等级 + 标题不变灰）。
12. **`[grade]` 的 7 种品级 → 任务簿颜色/排序**。
13. **宠物线性进化 + `[evolution creature id]`**（分支进化可后做）。
14. **`[event] 1` 活动任务置顶**。

### M3 可后做

15. `[condition under clear]` 的 15 种 `[sub type]`（先做 0 限时、1 被击数、6 直接通关）。
16. `[custom quest]`（学技能/加点触发）。
17. `[disjoint item]`（分解装备）。
18. `[cant giveup]` / `[exception quest]` / `[substitutive names]`。
19. `[piece reward]`（任务碎片属性加成）。
20. `.evt` 活动系统（宾果、邮件、掉落替换）——单机版整体跳过。
21. 宠物 `artifact slot` 三色装备槽 + `[over skill *]` 超越技能。
22. NPC 好感度（`[favor_dialog]`）。

### 明确不要抄的

- `.qst` 靠**路径**而非 id 组织（3,852 文件 / 339 注册条目）。复刻用统一 id + 分类字段。
- `[quest point]` 这种「数值 0/4/8/10/14/30 但含义未闭合」的字段——用显式分类枚举。
- `[difficulty]` 的**单字符**常数（`S`/`Y`/`Z`/`U`…共 15 个且顺序全无规律）——用 `float 倍率`。
- `[int data]` 按 `[type]` 变长（解析器要 switch）。复刻时每个 type 用独立结构体（`SeekingParams`/`HuntParams`…），序列化到磁盘时再拍平成数组。
- 「唯一兽」的唯一性（服务端概念，不是数据）。

---

## 10. 待验证清单

| # | 问题 | 怎么验证 |
|---|---|---|
| 1 | `[quest point]` 的数值语义（0/4/8/10/14/30） | 全库统计各值与 `[grade]`/`[type]` 的交叉表 |
| 2 | `exp/gold reward table` 的索引是 0 基还是 1 基（`[1]` 是 100 还是第一级） | 用一个 1 级任务实机对照 |
| 3 | `[dialog]` 每行前 4–6 个数的列义（官方只给了「对话索引/等级限制/概率」三个） | 抽 5 个 NPC 对照对话分支 |
| 4 | `[difficulty]` 15 个字符分档为何如此不规则（`M 10`/`O 10`/`Z 400`） | 对照任务 grade 分布，看是否按版本追加 |
| 5 | `[hunt enemy]` 5 元组里第 4 个数是否恒为 1（`1 次数`） | 全库统计该位置取值分布 |
| 6 | 任务 id 空间：339 条注册 vs 3,852 文件，未注册的任务怎么被引用 | 检查 `[pre required quest]` 是否只指向已注册 id |
| 7 | `n_quest/trainingquest.lst`（12.7KB）与 `quest.lst` 的关系 | 对比两份 lst 的条目重叠 |
| 8 | `[skill mp]` 消耗的是主人 MP 还是宠物资源 | 实机观察 |
| 9 | 宠物 `[move speed]` 5 档分别对应什么状态 | 对照 `.cre` 与宠物状态机（在 `.nut` 里） |
| 10 | `pvp_mission/*.msn`（126 个）是否属于任务体系 | 打开一个 `.msn`（实测 140B~2704B）看结构 |
