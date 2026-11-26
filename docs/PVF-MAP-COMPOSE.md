# 格兰之森（Elvengard / granfloris）资产怎么组合的

> 目标：知道「进一张图」需要哪些文件、按什么顺序画、怪物/机关从哪来。
> 结论全部来自 sf115 `Script.pvf` 实测，路径可在 `python3 tools/pvf_unpack.py list --grep` 里搜。

---

## 1. 三层：区域 → 副本 → 地图

```
dungeon/act1/mirkwood.dgn          副本定义（这次进的是哪个副本）
        │  [start map] / [boss map] → map/map.lst 里的 id
        ▼
map/mirkwood/n201.map              一张具体的地图（有背景、有物件、有怪）
        │  [tile]      8 个 .til 图块层
        │  [background animation] 远景动画
        │  [monster] / [passive object] / [item]  放置物
        ▼
tile/forestover.til                一个图块层 = 1 张图 + 一张通行表
        │  [image] map/01tile00.img <frame>
        │  [pass type] 420 个值（约 20×21 格，2=可走 / 其它=阻挡）
        ▼
sprite 里的 .img → NPK
```

格兰之森的副本文件（`dungeon/act1/`）：`lorien.dgn`（洛恩）、`mirkwood.dgn`、`mirkwooddeep.dgn`、
`mirkwoodfrost.dgn`、`sunderland*.dgn`、`grakkarak*.dgn` 共 10 个。

---

## 2. `.dgn` 里有什么（99 行，全是「配置」不是「地图」）

| 段 | 内容 | 用途 |
|---|---|---|
| `[entering title]` | `title/mirkwood.ani` | 进图时的标题动画 |
| `[cutscene image]` | `map/cutscene/granfloris.img` + 帧号 | 过场插画 |
| `[minimap image]` | `map/minimap/act1.img` | 小地图底图 |
| `[worldmap pattern info]` | 1 1 `worldmap/selectdungeonslot/granfloris.img` 0 | 选图界面的格子 |
| `[background pos]` | 80 | 背景滚动基准 |
| `[minimum required level]` / `[basis level]` | 2 / 4 | 等级 |
| `[pathgate object]` | 371..380（10 个 id） | 左右上下 × normal/boss/wall 的传送门物件，查 `passiveobject/passiveobject.lst` |
| `[start map]` / `[boss map]` | 地图 id | 查 `map/map.lst` |
| `[maze info][size]` | 3 | 迷宫的宽高（房间数） |
| `[event monster]` | —— | 事件怪 |
| `[champion]` | 1..5 | 难度 |

**注意：`.dgn` 本身不含坐标，也不含贴图。** 它是「选哪几张 map + 用什么门/标题」。

---

## 3. `.map` 里有什么（356 行，这是一张图的全部内容）

### 3.1 图块层 `[tile]`

按顺序列 8 个 `.til`（远景 → 近景）：

```
[tile]
    tile/forestover.til      ← 远
    tile/forestover.til
    tile/forestover.til
    tile/forestover.til
    tile/forestoverunder.til
    tile/forestunder.til
    tile/forestunder.til
    tile/forestunder.til     ← 近
[/tile]
```

每个 `.til` = **1 张整图 + 一张通行网格**：

```
[image]
    map/01tile00.img
    0                     ← 帧号
[pass type]
    2 2 2 ... （420 个，2=可走，其它=阻挡/不同层）
```

绘制方式：8 层按顺序贴，每层整张图铺在原点（图块系统是「预渲染大图 + 通行掩码」，
不是 32×32 拼图）——所以**一张图的背景其实只有 8 张图**，量很小。

### 3.2 远景动画 `[background animation]`

```
[background animation]
    [ani info]
        [filename] animation/far0.ani
        [layer]    [distantback]
        [order]    0
```

### 3.3 物件放置（三类层标签 + 坐标）

```
animation/flower1.ani
[normal]        ← 层：normal / bottom / fixed
509             ← x
272             ← y
0               ← order（同一层内的前后）
```

实测 `map/mirkwood/n201.map` 里有 22 个 `[normal]`、10 个 `[bottom]`、7 个 `[fixed]`。
`[fixed]` = 不随视差滚动的固定层（UI 式装饰），`[normal]` = 普通物件，`[bottom]` = 贴地物件。

### 3.4 怪物 `[monster]`

```
[monster]
    4        ← 怪物 id（查 monster/monster.lst）
    1        ← 数量
    0
    796      ← x
    202      ← y
    0
    1
    1
    [fixed]  ← 层
    [normal]
```

每 8 个数一组 + 层标签。怪物 id → `monster/monster.lst` → `monster/<name>.mob`，
`.mob` 再引用 `ai/`、`act/`、`animation/`、`atk/`（见 `docs/PVF-DEPENDENCY-GRAPH.md`）。

还有 `[passive object]`（机关/传送门）、`[item]`（掉落/可拾取）。

---

## 4. 组合顺序（画一张图）

```
1. 视差背景：8 个 .til 整图，按 [tile] 顺序从远到近；每层按 [background pos] 做视差
2. 远景动画：[background animation] 的 .ani（distantback 层）
3. [bottom] 物件 → [normal] 物件 → [fixed] 物件（同层按 order）
4. 怪物 / 机关 / 玩家：站在 [pass type]=可走 的格子上，按 y 排序（DNF 是斜 45° 视角，y 大者在前）
5. 前景层（部分图有 [bottom] 中的遮挡物）盖住角色
```

---

## 5. 一份可用的最小资产清单（一张图）

```
dungeon/act1/mirkwood.dgn
map/mirkwood/n201.map
tile/*.til ×8           → 各 1 个 .img（在 NPK 里）
animation/far0.ani      → 远景
animation/flower*.ani ×22 + 对应 .img
monster/monster.lst → monster/goblin/*.mob → 动画/攻击/掉落
passiveobject/...       → 传送门、机关
```

数量级：一张图 ≈ 8 张背景 + 30~40 个物件 + 怪物若干；**不是几千个素材**，导入很轻。

---

## 6. 复现

```bash
python3 tools/pvf_unpack.py cat dungeon/act1/mirkwood.dgn
python3 tools/pvf_unpack.py cat map/mirkwood/n201.map
python3 tools/pvf_unpack.py cat map/sunderland/tile/forestunder.til
python3 tools/pvf_unpack.py list --grep "map/mirkwood"
```
