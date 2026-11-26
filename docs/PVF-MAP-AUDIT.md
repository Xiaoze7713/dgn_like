# PVF 地图全量审计（twn + dgn）

> 2026-11-25。只读审计：把 `index["towns"]` 引用到的全部 map，以及 `dungeon/**/*.dgn`（3,961 个文件，3,507 个唯一 basename）按目录约定 `map/<dgnbasename>/` 对应的全部 map 都实际 `map_room` 一遍。
> 目的：找出「加载器没解析/没实现的字段」和「资源缺失」，不猜位置、不擅自修。

## 1. 规模与结果

| 项 | 数量 |
|---|---:|
| twn 引用 map（去重） | 489 |
| dgn 文件 / 唯一 basename | 3,961 / 3,507 |
| 实际加载 map（去重） | **15,700** |
| 其中 town / dgn / 两者都有 | 480 / 15,211 / 9 |
| 加载失败 | 114（全部为空文件） |
| 耗时 | 73.3 s（2026-11-25 20:52 最终一次，带 root 字段和对象解析） |
| 未解析 label | 302 个，合计 97,438 次 |

报告产物：`dnf_like/data/debug/audit_maps.md`（字段排行+失败清单）、`audit_maps.json`（每张 map 的 source/tiles/ext/npcs/anims/bg/mov/movA/virtual/objects/monsters/bgpos/root/unknown）。

## 2. 偏移 120 的审计结论

- 用户已确认：**物体/通行/区域框先统一用 `+120`**；`[background pos] 80` 不作为城镇偏移来源。
- 全量 `[background pos]` 分布：`0` 15,532 张、`80` 54 张、缺失 114 张。
- `80` 的 54 张里确实有旧城镇（如 `map/hendonmyre/hendon.map`、`hendon_auction`、`alfhlyra` 等）和部分 dgn；但 `new_hendon_main.map` 没有该字段（=0），说明它不能解释“120 随图变化”。
- 结论：120 不是从 `[background pos]` 或 `[far/middle sight scroll]` 推出来的。`new_hendon_main` 的 `80` 来自 `[far sight scroll]`，不是偏移量。保留固定 120，逐图变化的原因待查。

## 3. 根字段：已知但未实现/未消费

| 字段 | 出现 map 数 | 当前状态 |
|---|---:|---|
| `[monster]` | 14,163 | 已解析；14,152 张 map 非空，共 101,467 条（token 流，一条 label 多记录）。 |
| `[passive object]` | 14,396 | 已解析；14,382 张 map 非空，共 288,931 条；`.obj`→base ani 已接。 |
| `[sound]` | 15,519 | 已读入 `MapRoom.sound`，运行时不播放。 |
| `[greed]` | 15,012 | 已读入 `greed`，运行时不用于迷宫格。 |
| `[dungeon]` | 14,987 | 已读入 dungeon id，运行时不用于城镇入口。 |
| `[map name]` | 13,051 | 已读入 name，不显示。 |
| `[type]` | 15,536 | 已读入 map type，运行时不按类型分支。 |
| `[way point]` | 672 | 已读入 `way_point`，运行时不使用。 |
| `[teleport area option]` | 16 | **未解析**。 |
| `[pathgate pos]` | 15,368 | 已读入 `pathgate`，运行时不渲染/不用于通行。 |
| `[background pos]` | 54 | 只读入 `background_pos`，当前不作为偏移。 |
| `[import script]` | 54 | 递归解析父图。 |

## 3.5 加载器逻辑状态（逐环节）

| 环节 | 状态 | 说明 |
|---|---|---|
| `.twn` → area（含 `[permission]` 嵌套） | 已实现 | `[phase]` 只记录，不选图 |
| `.twn` → 跨城 `[town movable area]` / `[town movable area with animation]` | 已实现 | `targetTown>0` 跨城、`-1/-1` 副本、`-2/-2` 列表；`[town movable area pathgate animation]` 未解析 |
| `.map` → 地砖 / 扩展地砖 | 已实现 | 扩展层当前在相机可见区下方，属位置问题 |
| `.map` → 通行 `[pass type]` | 已实现 | 0 可走、2 阻挡；`dummy.til` 仍兜底整图可走 |
| `.map` → `[import script]` | 已实现 | 兼容 `(f)/(r)` 变体 |
| `.map` → `[animation]` / `[background animation]` | 已实现 | 背景含 `[ani info]` 的 filename/layer/order |
| `.map` → `[NPC]` | 已实现 | 条件 tag + 方向 + x/y/z |
| `.map` → `[monster]` | 已解析 | 14,152 张 map 非空；`MapRoom.monsters` 共 101,467 条；渲染只在有 `.mob [waiting motion]` 时用站立动画，否则红块 |
| `.map` → `[passive object]` | 已解析 | 14,382 张 map 非空；`MapRoom.objects` 共 288,931 条；`.obj`→`.act [BASE ANI]`/`[basic motion]` 已接 |
| `.map` → `[pathgate pos]` | 仅读数据 | 不渲染、不参与通行 |
| `.map` → `[teleport area option]` | **未实现** | 16 张 map |
| `.map` → `[way point]` / `[sound]` / `[greed]` / `[dungeon]` / `[map name]` / `[type]` | 仅读数据 | 运行时不使用 |
| `.map` → `[near/far/middle sight scroll]` | 部分 | far/middle 读入；`[near sight scroll]` 10,300 次未解析 |
| `.map` → camera 限制字段 | **未实现** | `[limit map camera move]`/`[top edge]`/`[wide mode...]` 等 |
| `.dgn` 解析 | **未实现** | 迷宫尺寸/格子角色/邻接/难度选图都没有 |
| 副本加载 | **未实现** | 城镇入口只到 id，未进 `.dgn` |

## 4. 未解析字段的类别（按出现次数）

| 类别 | 出现次数 | label 数 |
|---|---:|---:|
| 出生/PvP/流程 | 34,876 | 25 |
| 怪物/AI | 30,116 | 28 |
| 相机/渲染 | 14,224 | 46 |
| 物件/交互/道具 | 11,845 | 22 |
| 其他/未分类 | 4,067 | 144 |
| UI/小地图 | 1,438 | 19 |
| 规则/限制 | 678 | 13 |
| 声音 | 194 | 5 |

最高频的具体 label：

| label | 次数 | 类别 |
|---|---:|---|
| `[player number]` | 15,536 | 出生/PvP/流程 |
| `[pvp start area]` | 15,534 | 出生/PvP/流程 |
| `[event monster position]` | 14,560 | 怪物/AI |
| `[monster specific AI]` | 14,070 | 怪物/AI |
| `[near sight scroll]` | 10,300 | 相机/渲染 |
| `[special passive object]` | 3,581 | 物件/交互/道具 |
| `[buff]` | 2,447 | 物件/交互/道具 |
| `[dungeon start area]` | 2,352 | 出生/PvP/流程 |
| `[basic action]` | 2,133 | 物件/交互/道具 |
| `[pathgate recognize range]` | 1,370 | 物件/交互/道具 |
| `[dungeon movable area]` | 1,014 | 物件/交互/道具 |
| `[extended fullview]` | 810 | 相机/渲染 |
| `[scroll animation]` | 761 | 相机/渲染 |
| `[screen pos]` | 678 | 相机/渲染 |
| `[ai character]` | 672 | 其他/未分类 |
| `[pathgate object]` | 653 | 物件/交互/道具 |
| `[monster team]` | 624 | 怪物/AI |
| `[heroes mode map index]` | 410 | 其他/未分类 |
| `[quest start map]` | 339 | 出生/PvP/流程 |
| `[visible minimap]` | 331 | UI/小地图 |
| `[visible town minimap]` | 331 | UI/小地图 |
| `[pvp practice start area]` | 248 | 出生/PvP/流程 |
| `[Use Fatigue]` | 232 | 规则/限制 |
| `[title name]` | 217 | UI/小地图 |
| `[show dust]` | 212 | 相机/渲染 |
| `[arcade scroll area]` | 193 | 相机/渲染 |
| `[monster create trigger]` | 173 | 怪物/AI |
| `[Use Endurance]` | 162 | 规则/限制 |
| `[all]` | 151 | 其他/未分类 |
| `[map character move sound]` | 151 | 声音 |

完整 302 项在 `audit_maps.md` 的“未解析字段”一节。

## 5. 加载失败资源（114 张）

- `map/oldscreamingcave_r/*`：112 张，全部 `:empty`（PVF 里文件内容为空或压缩块空）。
- `map/contents/2026/defianceofafterglow/town/seria.map`：1 张，`empty`；也是 `town/defianceofafterglow.twn` a0 的 map。
- `map/kcontents3/theevildomgathering/655509_(0,0)_q6303_map3.map`：1 张，`empty`。
- 这些是**资源空文件**，不是解析异常；不要当“路径没找到”处理。

## 6. dgn 逻辑缺口

- 当前 `LivePvfContent` **没有 `.dgn` 解析器**；本次 dgn map 是按目录约定 `map/<dgnbasename>/**/*.map` 枚举的，不是按 `.dgn` 的 `[maze info]/[greed]/[start map]` 解析。
- 因此 dgn 的迷宫尺寸、格子角色（start/normal/boss）、房间邻接、随难度/阶段选图都未实现。
- 城镇→副本入口目前只在 twn 的 `[dungeon gate]` / `[town movable area]` 的 `-1/-1` 侧，副本加载路径缺失。

## 7. 地图特征计数

| 特征 | map 数 |
|---|---:|
| `tiles` 非空 | 15,586 |
| `npcs > 0` | 1,854 |
| `anims > 0` | 15,231 |
| `town_movable > 0` | 547 |
| `town_movable_anim > 0` | 123 |
| `virtual_movable > 0` | 568 |
| `monsters > 0` | 14,152 |
| `objects > 0` | 14,382 |

## 8. 边界与未确认

- 本次只审计“能按目录约定枚举到”的 map；`[import script]` 父图、`[phase]` 备选图、`[map specification]` 动态引用是否都被覆盖，仍未证明。
- `[monster]/[passive object]` 已解析并有渲染回退；但位置偏移仍按用户要求不主动改，任何“怪物/物件位置对不对”的结论仍要单独截图确认。
- `[phase]` 按用户要求只记录不实现。
- 120 是否随图变化尚未找到来源；当前固定 120 是用户确认的临时正确值。

## 9. 复跑

```bash
cd /home/sunmingze/dnf_like
XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
  ./tools/godot.sh --headless --script res://tests/audit_maps.gd
  ./tools/godot.sh --headless --script res://tests/world_entities.gd   # 12 项：怪物/对象解析
```
