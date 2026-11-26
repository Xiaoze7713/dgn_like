# 07 · 地图与关卡体系（.twn / .dgn / .map / .til / .obj）

> 范围：城镇怎么串、副本怎么编排成迷宫、房间怎么摆怪摆物、地砖怎么定可走区域。
> 数据源：`export/text/town/**/*.twn`（81）、`dungeon/**/*.dgn`（625）、`map/**/*.map`（5,797，注册表 4,591）、`map/**/*.til`（9,944）、`passiveobject/**/*.obj`（24,436）。
> 官方标签释义：`export/_meta/tagdict.sqlite`（`ext='map'`/`'dgn'`/`'twn'` 大量标签有官方注释，本文多处直接引用）。
> 相邻文档：房间里的怪怎么行为 → [06-monster.md](06-monster.md)；技能/判定 → [04-combat.md](04-combat.md)；任务怎么挂钩 → [08-quest.md](08-quest.md)；`.act`/`.ai` 动作层 → [09-script-mechanics.md](09-script-mechanics.md)。

---

## 0. 一句话结论

DNF 的关卡是**四层 ID 引用链**，每层职责单一：

```
.twn（城镇）  [area] = (索引, .map 路径, 类型 token, 参数)
   │                  └─ 类型 [dungeon gate] → 副本 id（走 worldmap.lst）
   ▼
.dgn（副本）  [size] + [greed]（ASCII 迷宫图）+ [map specification]（格子→地图 id）
   │                  + [start map] / [boss map] / [champion] / [basis level]
   ▼
.map（房间）  [type]（normal/boss/dummy）+ [tile] + [monster] + [passive object] + [pathgate pos]
   │
   ▼
.til（地砖）  [IMAGE] 图片 + [pass type] 逐格通行网格
```

四个反直觉发现：

1. **`[greed]` 是一张 ASCII 迷宫图，而且每个格子用两个字符编码「出口方向」**。官方注解逐字给出了 15 个 token 的含义（`BB`=右、`MM`=左下、`II`=下、`AA`=无法通过…）。我用 400 行脚本在 **625 个副本上验证了双向连通性**：621 个完全自洽（§2.2）。
2. **`.map` 里没有任何几何尺寸字段**。房间边界来自 `.til` 图集与 `[tile]` 排列，「哪里能走」在 `.til [pass type]` 的逐格网格里。
3. **房间里的怪物用 10 个字段描述**（官方完整给出），包括「等级自动指定与否」「复制类型 fixed/half/ratio」「怪物类型 normal/champion/super champion/boss」。**难度与人数在这里被数据化**。
4. **`[type] [dummy]`**（官方：「虚拟房间，诱惑之村哈梅伦中使用，首领用硬编码」）——存在一种「看起来是房间但不是房间」的类型，说明**假房间是刻意设计的机制**。

---

## 1. `.dgn`（副本 / 关卡编排）

### 1.1 元信息字段

| 字段 | 官方名 | 含义 | 取值 | 必填 |
|---|---|---|---|---|
| `[name]` | 副本名 | 显示名 | 文本 | ✅ |
| `[explain]` | 说明 | 副本简介 | 文本 | ✅ |
| `[background pos]` | 背景绘制位置偏移 | 800×600 扩展时背景上移量，**通常 80** | 整数 | ✅ |
| `[entering title]` | 进入标题 | 载入画面动画 | `.ani` 路径 | ✅ |
| `[cutscene image]` | 过场图 | 进图画面 | `img 帧` | ✅ |
| `[minimap image]` | 小地图 | 小地图图集 | `img 路径` | ✅ |
| `[worldmap pattern info]` | 世界地图图案与槽位 | 选图界面图案/槽位 | `类型 索引 img 帧` | ✅ |
| `[minimum required level]` | 最低进入等级 | 低于此级**看不到**该副本 | 整数 | ✅ |
| `[basis level]` | 基础等级 | 影响**怪物强度**与**付费翻牌费用**选行（官方） | 整数 | ✅ |
| `[recommended level]` | 推荐等级 | 两值（下限、上限），**仅展示**，不是进入限制 | `lo hi` | ❌ |
| `[experience increasing point]` | 经验倍率 | `0.5` = 只拿 50% | 浮点 | ✅ |
| `[champion]` | 精英怪几率 | **5 值 = 普通/冒险/勇士/王者/英雄**，`1` = 1%，`100` = 每房间必出 1 只 | 5 整数 | ✅ |
| `[quest connection]` | 任务关联 | **进行0 完成1，任务编号，难度**（`-1` 全难度 / `0` 普通 / `1` 冒险 / `2` 王者 / `3` 英雄） | 3 元组 × N | ❌ |
| `[pathgate object]` | 通道对象列表 | 10 个对象 id（左右上下各…） | id 列表 | ✅ |
| `[special passive object item]` | 特殊被动对象物 | 9 值组 | 见 §2.4 | ❌ |
| `[event monster]` | 活动怪物 | `1 5000 61726 1 300 80 1` | 7 值 | ❌ |
| `[designate dungeon difficulty]` | 指定难度 | `0` = 自动 | 整数 | ❌ |
| `[monsterapc diff table]` | 怪物/APC 难度表 | 按难度给怪物与 APC 加成 | 表 | ❌ |
| `[ancient dungeon]` / `[hell dungeon]` / `[tower of despair]` / `[risk dungeon]` | 特殊副本标记 | 远古/深渊/绝望之塔/冒险团 | 标记或参数 | ❌ |
| `[required item]` | 入场道具 | 需要消耗的道具 id | 整数 | ❌ |
| `[no fatigue]` | 不消耗疲劳 | 标记 | — | ❌ |
| `[coin limit]` | 金币上限 | 副本内可拾取金币上限 | 整数 | ❌ |
| `[seal door map index/pos/appear rate]` | 封印门 | 门所在格/坐标/出现率 | 三组 | ❌ |
| `[limit inout count]` | 进出次数限制 | 整数 | ❌ |

### 1.2 `[maze info]` 块：三件套

| 字段 | 官方名 | 含义 |
|---|---|---|
| `[size]` | 小地图大小 | **列数 行数**（官方例：`4 1` = 一条直线） |
| `[greed]` | **地牢网格布局** | ASCII 图，每格 **2 字符** = 一个出口方向 token |
| `[map specification]` | 普通房间地图绑定 | 每条 = `X Y mapId [mapId2 …]`，一格可给多个候选 id |
| `[start map]` | 起始格列表 | 每行 `X Y`，可多行（官方例：`2 2 / 1 2 / 0 0`） |
| `[boss map]` | Boss 格列表 | 每行 `X Y`（**是坐标不是 map id**，官方特别强调） |
| `[boss map specification]` | Boss 房间地图绑定 | 同 `[map specification]` |

**官方 `[greed]` token 表**（这是本文最硬的证据，来自 `tagdict.sqlite` 的 `ext='dgn'`/`'map'` 两条注释，两处内容一致）：

| token | 出口 | token | 出口 | token | 出口 |
|---|---|---|---|---|---|
| `BB` | 右 | `EE` | 左 | `CC` | 上 |
| `II` | 下 | `DD` | 右上 | `GG` | 左上 |
| `JJ` | 右下 | `MM` | 左下 | `NN` | 左下右 |
| `HH` | 左上右 | `LL` | 上下右 | `KK` | 上下 |
| `FF` | 左右 | `PP` | 十字 | `AA` | **无法通过** |

> 字符本身是「双写首字母」：`BB`=单向、`FF`/`KK`/`PP`=双向组合、`AA`=墙。**这是一套 15 token 的连通性位掩码**，其 JSON 等价物就是 `{R:true, D:true}`。

### 1.3 多阶段布局

同一个副本可以有**多套迷宫**：重复键在导出里变成 `[maze info]-1`、`[size]-1`、`[greed]-1`、`[map specification]-11`…（后缀序号 = 出现顺序）。实测 `dungeon/act1/grakkarakburning.dgn` 就有两套（第二套带 `[quest connection]` 与不同的 `[boss map]`），推测对应**不同难度或不同阶段**的布局。**复刻时按「布局数组」建模，不要假设只有一个 `[maze info]`。**

---

## 2. `.map`（房间）

### 2.1 基本字段

| 字段 | 官方名 | 含义 | 取值 | 必填 |
|---|---|---|---|---|
| `[map name]` | 地图名 | 显示名（PVP 房间也有） | 文本 | ❌ |
| `[type]` | 地图类型 | `[normal]` 普通 / `[boss]` 首领 / `[dummy]` 虚拟（首领用硬编码） | 枚举 | ✅ |
| `[dungeon]` | 所属副本 | **哪些副本使用这张地图**（反向引用，可多条） | dungeon id 列表 | ✅ |
| `[player number]` | 玩家人数 | 最少 最多 | `2 8` | ✅ |
| `[greed]` | 网格类型 | 该地图适用于哪种网格形状（同 `[greed]` token） | token | ❌ |
| `[tile]` | 地砖 | 基础地砖，近景图层绘制 | `.til` 路径列表 | ✅ |
| `[extended tile]` | 扩展地砖 | 附加在地砖**下方**；「横向排列 tile 的地砖后，剩余部分排列在下方」 | `.til` 路径列表 | ✅ |
| `[sound]` | 地图声音 | BGM 在 `audio.xml [Music]`，环境音在 `[SoundPacks]` | 名列表 | ✅ |
| `[pathgate pos]` | 通道坐标 | **四入口按左、右、上、下顺序各一组 x,y**（共 8 数） | 8 整数 | ✅ |
| `[pathgate recognize range]` | 通道识别范围 | 整数 | ❌ |
| `[dungeon start area]` | 起始区域 | 起始房间里角色出现位置：`x y w h` | 4 整数 | ❌ |
| `[virtual movable area]` | 城镇可移动区域 | `x y w h` 列表，**并集区域内可移动** | 4 元组 × N | ❌ |
| `[town movable area]` | 区域间连接 | `x y w h 城镇索引 AREA索引`；索引 `-1` = **副本开始**而非区域移动 | 6 元组 × N | ❌ |
| `[pvp start area]` | PVP 开始点 | **3 组 × (x,y,w,h)** = 个人战 / 1 队 / 2 队（共 12 数） | 12 整数 | ✅ |
| `[pvp practice start area]` | PVP 练习点 | 2 组 ×(x,y,w,h) | 8 整数 | ❌ |
| `[far sight scroll]` / `[middle sight scroll]` / `[near sight scroll]` | 滚动速度比 | 远景/中景/近景相对地砖的滚动比率（%），`100` = 同步，`0` = 不动 | 整数 | ✅ |

### 2.2 `[monster]` —— 10 字段（官方完整给出）

```
[monster]
    66412 1 2 895 286 0 2 1 [fixed] [boss]
    69025 1 0 649 233 0 1 1 [fixed] [normal]
```

| # | 字段 | 官方名 | 说明 |
|---|---|---|---|
| 1 | `怪物索引` | 怪物索引 | → `monster.lst` |
| 2 | `等级自动指定与否` | `0`/`1` | `1` = 按副本 `[basis level]` 自动定级 |
| 3 | `等级` | 等级 | 上一个字段为 0 时用此值 |
| 4-6 | `x y z` | 坐标 | 房间内绝对坐标，Y 向下 |
| 7 | `随机物品掉落次数` | 随机掉落次数 | 见下 |
| 8 | `指定物品掉落次数` | 指定掉落次数 | 见下 |
| 9 | `复制类型` | `fixed` / `half` / `ratio` | `fixed` 固定 1 只；`half` = 玩家数一半（1-2 人出 1 只，3-4 人出 2 只）；`ratio` = 等于玩家数 |
| 10 | `怪物类型` | `normal` / `champion` / `super champion` / `boss` | 用 champion 时**后面还要接特性个数与特性** |
| 附 | `[NPC] 编号` | 可插在怪物类型**之前** | 「击杀此怪物后 NPC 会出现」 |

> 字段 7/8 的「掉落次数」是**每只怪独立的掉落次数**，与 `.mob [item]`（掉什么）正交——一个管次数、一个管内容。这解释了 DNF 里「刷怪次数」可以按房间单独调。
>
> `[NPC]` 插在类型前的写法（`… 1 1 [NPC] 1000 [left] -176 -104 0`）说明**这个 10 字段记录是可扩展的**：解析器必须按 token 分流，不能硬编码 10 个位置。

### 2.3 其他对象摆放

| 字段 | 每条字段数 | 官方语义 |
|---|---|---|
| `[passive object]` | **4** | `对象索引 x y z` |
| `[animation]` | **5** | `动画文件名 图层 x y z`；图层可选 `close`/`normal`/`bottom`/`closeback`/`middleback`/`distantback` |
| `[event monster position]` | **3** | `x y z`（配合 `.dgn [event monster]` 的 7 值使用） |
| `[item]` | — | 已见为空闭合块，主要靠结构存在性参与解析 |
| `[monster specific AI]` | — | 每怪一条，覆盖该怪在**本房间**的 AI（`[normal]` 等 token） |

### 2.4 `[special passive object]`（特殊建筑 / 深渊派对）

官方：前三个参数 = `被动对象索引 x y`，第四个 = **要创建的对象数量**；之后每行按类型指定子项：

```
[special passive object]
    0 -1 0        ← dgn 里的一组（索引 x 数量）
    1 -1 0
    2  16 0
```
`[special passive object]` 在 `.dgn`（9 值）与 `.map`（数量 + 子行）里写法不同，子类型枚举：`monster`（怪物索引 + 生成概率）/ `trap`（陷阱索引 + 魔法等级）/ `item`（掉落索引）/ `hellparty`（深渊派对组）。`.obj` 的 `[trap]` 官方注释：「为 1 则**必须破坏才能通关**」。

### 2.5 背景动画

```
[background animation]
    [ani info]
        [filename]  Animation/far01125.ani
        [layer]     [distantback]
        [order]     [below]
```

官方：从 `0,0` **自动重复绘制**；`[ani info]` 内为 `动画路径 / 图层 / 绘制顺序(below|upper) / Y 轴循环 / 屏幕坐标`；`close` 图层在 `below` 时**在地砖之前绘制**。

---

## 3. `.til`（地砖）

`map/bakalcastle/tile/tile3.til` 实测（标签流）：

```
[IMAGE]     Map/DimentionGate/bakalcastle/tile.img  3      ← 图集路径 + 帧号
[img pos]   80                                            ← 绘制偏移
[pass type] 2 2 0 2 …                                     ← 逐格通行类型网格
```

- `[pass type]` 是一长串 `0/2`（该样本 421 个值，实测 `2`×238、`0`×182，另有个别 `3`）。**`2` = 可走、`0` = 不可走**（`3` 语义待验证）。
- **没有显式宽高字段**。网格尺寸要么由值总数反推，要么由 `.map [tile]` 的排布决定。官方对 `[extended tile]` 的注释给了关键线索：「横向排列 `[tile]` 的地砖后，剩余部分排列在下方」——即房间被切成「上方横条（tile）+ 下方剩余区（extended tile)」两块。
- 4 字节的 `.til` 是空表（占位）；`Tile/Tile3.til` 这类「根级 Tile 目录」解析为空（大小写/路径映射待验证）。

> **复刻建议**：`.til` 的通行网格**直接照抄**——这是最省事的碰撞层。房间碰撞不做物理体叠加，而是查一张 2D 网格（每格 2 bit）。

---

## 4. `.twn`（城镇）

```
[entering title]    Title/CentralPark.ani
[cutscene image]    Map/CutScene/Centralpark.img 0
[dungeon what must be cleared]  -1            ← -1 = 无前置副本要求
[area]       0 Town/CentralPark/Gate_CentralPark.map [gate] 474 234
[area]-1     1 Town/CentralPark/CentralPark.map [normal]
[area]-2     2 Town/CentralPark/CentralPark_Waiting.map [dungeon gate] 39
[area]-3     3 Town/CentralPark/CentralPark_MetroCenter.map [normal]
[area]-4     4 Town/CentralPark/Dvildom_C.map [normal]
[area]-5     5 Town/CentralPark/Dvildom_C_Waiting.map [dungeon gate] 45
[name]       中央公園
```

| `[area]` 组成 | 含义 |
|---|---|
| `area 索引` | 从 0 连续编号 |
| `map 路径` | `map/` 下的直接路径（**不是 id**） |
| 可选 `[minimap rect]` | 各 step 的起点/终点 X/Y（`Map/MiniMap` 上的区域框） |
| 区域类型 token | `normal` / `gate` / `fishing place` / `pub` / `dungeon gate` |
| 后续整数 | **按类型解释**：`[gate] x y` = 传送点坐标；`[dungeon gate] N` = 副本入口号（**经 `worldmap/worldmap.lst` 解析**） |

其他字段：`[limit level]`（进入等级）、`[need quest]`（所需任务 id）、`[sub name]`、`[user pretown init]`、`[exclude user pretown info]`。

> **注意**：`.twn` 引用 `.map` 用的是**路径**，而 `.dgn` 引用 `.map` 用**数字 id**（走 `map.lst`）。两种引用方式并存，复刻时必须都支持。

---

## 5. 样例原文 + 解读

### 样例 A：`dungeon/act1/grakkarakburning.dgn`（烈焰格拉卡）—— 完整迷宫解码

```
[size]
    5 4
[greed]
    IIAAIIAAAA
     LLMMKKJJMM
     KKDDHHHHGG
     CCAAAAAAAA
[map specification]
    2 0 1219
[map specification]-1
    0 1 1206 1207 1208
[map specification]-2
    1 1 1212 1213 1235 1234
 …
[start map]
    0 0 0 3
[boss map]
    3 1 4 2
[boss map specification]
    2 0 1249
[champion]
    4 8 12 16 18
[basis level]
    15
[minimum required level]
    12
```

**解码步骤**
1. `[size] 5 4` = **5 列 × 4 行**。`[greed]` 每行 10 个字符 = 5 格 × 2 字符 ✓（宽度自洽）。
2. 逐格转出口：
   - 行0：`II`(下) `AA`(墙) `II`(下) `AA`(墙) `AA`(墙)
   - 行1：`LL`(上下右) `MM`(左下) `KK`(上下) `JJ`(右下) `MM`(左下)
   - 行2：`KK`(上下) `DD`(右上) `HH`(左上右) `HH`(左上右) `GG`(左上)
   - 行3：`CC`(上) `AA` `AA` `AA` `AA`
3. `[start map] 0 0 0 3` = **起始格 (0,0) 与 (0,3)**；(0,0)=下 → 通 (0,1)=上下右 ✓；(0,3)=上 → 通 (0,2)=上下 ✓。**双向一致**。
4. `[boss map] 3 1 4 2` = Boss 格 **(3,1) 与 (4,2)**；(3,1)=右下 → 右到 (4,1)=左下 ✓、下到 (3,2)=左上右 ✓。
5. `[map specification] 2 0 1219` = 格 **(2,0) → map 1219**（唯一）；`[map specification]-1 0 1 1206 1207 1208` = 格 **(0,1) → 3 个候选**，进房时随机选一个。
6. `[boss map specification] 2 0 1249` = Boss 房间用 **map 1249**。

**解读**
- **一列一格、两字符一 token**，所以 `[greed]` 行长度 = `[size].cols × 2`。这是最容易踩的坑：**不要按字符数当列数**。
- **出口是双向声明的**（A 说通 B，B 也必须说通 A）。我写脚本验证了 625 个副本：621 个完全自洽，1 个有单边出口，3 个无法解析（导出缺行）→ **这套编码 100% 可解**（验证脚本逻辑：对每格每个出口检查邻格是否有反向出口）。
- **`[map specification]` 的候选列表 = 房间随机化的实现**。同一个格子在多次进入时可以是不同房间——**DNF 的「每次进去布局不同」不是随机生成地图，而是随机选已做好的房间**。这是极省成本的伪随机，值得照抄。
- `[champion] 4 8 12 16 18` = 普通难度每房间 4% 出精英、英雄难度 18%。**难度曲线的一个维度就写在这一行里。**

### 样例 B：`map/coldboy/sample.map`（最小房间样本）

```
[player number] 2 8
[pvp start area] 0 0 0 0 0 0 0 0 0 0 0 0
[dungeon] 41
[greed] KK KK
[type] [normal]
[tile] Tile/emptytile.til Tile/emptytile.til Tile/emptytile.til
[extended tile] Tile/sp28.til Tile/sp06.til Tile/sp22.til
[far sight scroll] 56
[middle sight scroll] 90
[near sight scroll] 110
[background animation]
    [ani info] [filename] Animation/far01125.ani [layer] [distantback] [order] [below]
    [ani info]-1 [filename] Animation/mid01125.ani [layer] [middleback] [order] [below]
[sound]
[pathgate pos] 15 677 656 676 328 300 344 1063
[passive object]
[monster]
[monster specific AI]
[map name] PVP無名
```

**解读**
- `[monster]` 与 `[passive object]` 是**必须存在但可以为空**的块。解析器要能容忍空块（这在 PVF 里很常见：`[sound]` 也是空的）。
- `[pathgate pos] 15 677 / 656 676 / 328 300 / 344 1063` = 左、右、上、下四个通道口坐标。**顺序是官方规定的**，不能按 x 大小排序。
- `[tile]` 三项 + `[extended tile]` 三项 → 官方「横向排列后剩余排下方」：房间上方由 3 块地砖横排、下方由 3 块扩展地砖填充。
- `[far/middle/near sight scroll] = 56/90/110`：**视差层速度**。三档视差 + `[background animation]` 的两层动画 = DNF 横版卷轴的纵深全部来源。

### 样例 C：`town/centralpark.twn`（见 §4 摘录）

**解读**
- 6 个 `[area]` 里两个是 `[dungeon gate]`（39、45 = 副本入口号），三个是 `[normal]`（纯地图），一个是 `[gate]`（带传送坐标 474 234）。
- **城镇 = 一组 (地图, 入口类型) 的集合**，没有坐标布局、没有碰撞——玩家在城镇里的移动范围由 `.map [virtual movable area]` 的并集决定。
- `[dungeon what must be cleared] -1`：进入该城镇不要求先通任何副本。非 `-1` 时才做前置校验。

---

## 6. 系统联动

```
worldmap.lst ──▶ .twn [area] [dungeon gate] N ──▶ .dgn
                                                    │
      .dgn [greed]+[size] ──▶ 迷宫格 (x,y)          │
      .dgn [map specification] (x,y) ▶ mapId ──▶ map.lst ──▶ .map
                                                    │
   .map [monster] ──▶ monster.lst ──▶ .mob (06)     │
   .map [passive object] / [special passive object] ──▶ passiveobject.lst ──▶ .obj ──▶ .act/.atk (04)
   .map [tile] ──▶ .til (通行网格)
   .map [dungeon] ──◀ 反向引用 dungeon id（同一张图被多个副本复用）
   .dgn [quest connection] ──▶ .qst (08)
   .dgn [champion]/[basis level] ──▶ 怪物等级与精英率 (06 [level])
```

- **地图复用**：`.map [dungeon]` 是**反向引用列表**，说明一张房间图可以被多个副本共用。这是 `.dgn → .map` 之外的第二条关系，复刻时用它做「房间池」。
- **难度**：`.dgn` 提供 `[basis level]`（怪物强度）+ `[champion]` 5 档（精英率）+ `[monsterapc diff table]`；`.map [monster]` 的「等级自动指定」开关决定用不用 `[basis level]`。
- **人数**：`[player number]` + `[monster] 复制类型 half/ratio` = 组队时怪物数量自适应。**单机版把这个开关写死成 1 人即可，但字段要留**（联机接口）。

---

## 7. 复刻时必须实现的最小集

### M1 必须

1. **四层数据 + 注册表**：`TownDef` / `DungeonDef` / `MapDef` / `TileDef`，各自一张 id→资源表。
2. **`[greed]` 解码器**：2 字符 → 出口集合（15 token 表），行宽 = `cols×2`。**这是本作「随机地图」的全部实现基础。**
3. **迷宫装配**：`size` + `greed` + `map specification`（候选列表随机取一）→ 房间图 + 连通图；`start map` 标记起点、`boss map` 标记 Boss 房。
4. **房间摆放**：`[monster]` 10 字段（至少 id/坐标/等级/复制类型/怪物类型）+ `[passive object]` 4 字段 + `[animation]` 5 字段。
5. **通道**：`[pathgate pos]` 4 入口（左/右/上/下顺序）+ 进入相邻房间。
6. **通行层**：`.til [pass type]` 网格（0 不可走 / 2 可走）直接当碰撞层。
7. **视差**：`[far/middle/near sight scroll]` 三档比率 + `[background animation]` 的 `[layer]`/`[order]`。
8. **城镇**：`[area]` 列表 + 5 种区域类型（先做 `normal`/`gate`/`dungeon gate`）。

### M2 应当

9. **多套迷宫**（`[maze info]-1`）：同一副本不同难度/阶段的布局。
10. **房间随机化**：`[map specification]` 多候选 + 未指定格由迷宫规则随机。
11. **难度三维**：`[basis level]`（怪物强度）+ `[champion]` 5 档几率 + `[experience increasing point]`（经验倍率）。
12. **`[special passive object]`**（可破坏陷阱、深渊派对、隐藏掉落物）。
13. **`[town movable area]`**：区域间无缝连接（`-1` = 进副本）。
14. **`[dungeon start area]`**：起始房间的出生区。
15. **`.map [dungeon]` 反向索引**：房间池复用。

### M3 可后做

16. `[pvp start area]` / `[pvp practice start area]`（PVP）。
17. `[worldmap pattern info]` / `[minimap image]` / `[cutscene image]`（UI 层，先占位）。
18. `[seal door *]`（封印门）、`[hell dungeon]`（深渊）、`[tower of despair]`（塔）、`[ancient dungeon]`。
19. `[risk dungeon]` / `[monsterapc diff table]`。
20. `[fishing place]` / `[pub]` 两种城镇区域类型。

### 明确不要抄的

- `[type] [dummy]`「虚拟房间，首领用硬编码」——纯历史包袱。
- `[area]` 的「后续整数按类型解释」（同一个位置不同字段类型）。复刻时用显式字段名。
- `[map specification]` 与 `[boss map specification]` 两套并行结构——合并成一个带 `is_boss` 标记的列表。
- `.til` 缺宽高的隐式尺寸——复刻时显式写 `width/height`。

---

## 8. 待验证清单

| # | 问题 | 怎么验证 |
|---|---|---|
| 1 | `.til [pass type]` 网格的确切宽高（该样本 421 个值，不是平方数） | 取 3 个不同房间，用「值总数 = w×h」反推，与 `[extended tile]` 数量对齐 |
| 2 | `[pass type]` 里值 `3` 的语义 | 全库统计 `3` 出现位置是否在边界 |
| 3 | `.twn [area]` 的 `[minimap rect]` 列义（「各 step 的起点/终点 X/Y」） | 找带 `[minimap rect]` 的 twn（33 处）对照小地图 |
| 4 | `.dgn` 多套 `[maze info]` 是按难度还是按阶段切换 | 对 3 个有 `-1` 套的副本，看第二套是否带不同 `[quest connection]` |
| 5 | `.map [monster]` 的「随机物品掉落次数 / 指定物品掉落次数」与 `.mob [item]` 的交互 | 官方无进一步说明；需实机刷怪统计 |
| 6 | `[champion]` 5 值与 `[designate dungeon difficulty]` 的关系（难度是副本固定还是可选） | 对照有 `[designate dungeon difficulty] 0` 的副本 |
| 7 | `[special passive object]` 在 `.dgn`（9 值）与会 `.map` 的写法差异 | 逐字段对齐两种文件中的同一机制 |
| 8 | `.dgn [monsterapc diff table]` 的列结构 | 全库统计出现形态 |
| 9 | `worldmap.lst` 里 `[dungeon gate] N` 的 N 与 `.dgn` 文件 id 的映射 | 抽 3 个 twn 的 gate 号反查 worldmap.lst |
| 10 | `[greed]` 的 `NN`/`LL`/`HH` 三向 token 是否可能出现在内部格（而非边角） | 统计 625 副本中各 token 的格位置分布 |
