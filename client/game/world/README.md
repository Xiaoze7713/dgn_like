# game/world —— 城镇 / 副本世界

`scenes/world.tscn` 的根节点挂 `flow/world_director.gd`，由它把原生 `Script.pvf` 的内容现场解析成可走的地图；不读 `assets/pvf/world/*.json`，也不读预生成的 NPK 索引。

## 入口（先看这里）

| 层级 | 文件 | 职责 |
|---|---|---|
| 总控 | `flow/world_director.gd` | `enter_town()` / `enter_town_area()` / `enter_dungeon()` / `return_to_town()`；装载、输入、换图、缓存释放 |
| 内容 | `content/live_pvf_content.gd` | 直接读 `/mnt/d/dnf_latest/Script.pvf`；`LivePvfContent`，按需解析城镇/地图/地砖/ANI/NPC/怪物/被动对象 |
| 内容（旧） | `content/pack_content.gd` | 仅保留给旧 JSON 内容包的兼容层，世界运行时不走它 |
| 模型 | `model/*.gd` | `TownDef` / `MapRoom` / `DungeonDef` / `NpcDef` / `RegionDef` / `AniDef` / `TileDef` |
| 构建 | `build/room_builder.gd` | 把一张 `MapRoom` 变成节点树：地砖/背景/装饰/物件/门/怪物/NPC；怪物/对象有动画走 `AniSprite`，缺资源回退占位 |
| 通行 | `build/pass_grid.gd` | 16px 格通行网格、移动、出生点；`[pass type]` **0=可走，2=阻挡**，行序不翻转；`block_w` 固定 224（14 列/块） |
| 动画 | `build/ani_sprite.gd` | 轮播 `.ani`，处理 `[IMAGE POS]` / NPK 画布原点 / 加色 / alpha |
| 角色 | `actor/world_player.gd` | 玩家移动；城镇鬼剑士 move/stay 五层（skin/pants/shoes/coat/hair） |
| UI | `ui/town_list_ui.gd`、`ui/world_debug_ui.gd`、`ui/world_font.gd` | 城镇列表（M）、世界调试面板（L）、中文 SystemFont |

## 调用链

```
world_director.enter_town(key)
  → LivePvfContent.town(key)              # 首次现场解析 .twn，永久缓存
  → enter_town_area(i)
      → LivePvfContent.map_room(map)      # 首次现场解析 .map，LRU 16
      → LivePvfContent.tiles_for(room)    # 首次现场解析 .til，LRU
      → RoomBuilder.build(room, tiles)    # 地砖/背景/装饰/物件/门/Actors
      → PassGrid.build(tiles, defs)
      → WorldPlayer.position = grid.spawn_at()
```

副本同理：`enter_dungeon` → `DungeonDef` → `_enter_cell(cell)` → `_load_room()`。

## 城镇拓扑 / 跨城

- 同一城镇的 `[town movable area]` 6 元组：`x y w h targetTown targetArea`。
- `-1/-1` = 当前城镇的副本入口；`-2/-2` = 世界地图（打开城镇列表）。
- `targetTown > 0` 且不是当前城镇时，`LivePvfContent.town_key_by_id()` 找 `towns_by_id`，再 `enter_town(key, target_area)`。
- 城镇边缘的 area 邻接由 `TownDef.neighbor_of(area, dir)` 用 `[minimap rect]` 贴边计算。
- 地区分组来自 `regions/*.json` 的 `town_keys`；城镇列表按 `region_name` 分组。

## 懒加载与释放

- `LivePvfContent` 永久缓存：index / towns / dungeons / regions / npcs（索引只含 128 个“至少有一张可读地图”的城镇）。
- `LivePvfContent` 房间级缓存：`_map_cache` LRU 16、`_ani_cache` LRU 256；`_defs` 仍受 `MAX_DEFS=128` 约束。
- `NpkStore` 贴图缓存：条数 `MAX_TEX=800` + 字节预算 `MAX_TEX_BYTES=64 MB`，命中时把 key 移到队尾，按“最久未用”淘汰；Img 缓存 LRU 48。
- 每次 `_unload_room()`：旧节点 `remove_child + free`，`NpkStore.trim(320, 24)`，`LivePvfContent.trim_cache(40, 80)`。

### 缓存数字别混（2026-11-25 核对）

| 常量 | 值 | 单位/含义 |
|---|---|---|
| `PackContent.MAX_TRANSIENT` | 64 | JSON 房级缓存；`LivePvfContent` 不拿它当房间硬上限 |
| `LivePvfContent._map_cache` | 16 | 当前房间级 JSON 缓存；HUD 的 `transient` 是它的 size（常见 2） |
| `LivePvfContent._ani_cache` | 256 | 现场解析的 AniDef 缓存 |
| `MAX_DEFS` | 128 | Tile/Ani/Obj 定义缓存 |
| `NpkStore.MAX_TEX` | 800 | 贴图条数，不是 64 |
| `NpkStore.MAX_TEX_BYTES` | 64 MB | 贴图字节预算，按宽×高×4 |
| `NpkStore.MAX_IMG` | 48 | `NpkImage` 对象条数，最接近上限的一项 |
| `CACHE_TEX_KEEP` / `CACHE_IMG_KEEP` | 320 / 24 | 换图后压回的水位 |

- HUD `tex=68` 是**贴图条数**；`transient=2` 是房间缓存条数。不要把 `tex=64` 当成 64 上限。
- 背景层加载后 `img` 会接近 48；`NpkImage` 持有原始 `_buf`，所以下一步若要扩背景/大图，先看 `img` 是否顶到 48。
- 不是“全部常驻”：城镇/地图/贴图都是用到才解析，切图后按 LRU/字节预算出队；解析结果不做磁盘落地。

## 坐标（容易错，先读）

- 地砖 / pass 网格 / 怪物 / NPC / 物件 / `[pathgate pos]`：`y` 是「距房间下沿高度」，`screen_y = 网格高 + 该列 tile.img_pos - y`；NPC/怪物/对象的 `AniSprite` 还要加 NPK 帧画布原点。
- pass 网格：`[pass type]` 的 **0 可走、2 阻挡**，第 0 行对图像顶部，不能翻行序。
- `[animation]` 装饰：画面系，`y` 向下；落点还要加 NPK 帧的画布原点。
- 背景：`[background pos]` 是整层锚点，横向平铺，竖向忽略 `[IMAGE POS]` 的 dy；视差**只跟 x**，y 固定（2026-11-26 用户要求）。
- NPC 立绘：`[IMAGE POS]` 是相对脚下锚点，但 **NPK 帧头还有自己的画布原点**；`AniSprite.setup(..., true, true)` 会加上，漏掉就会有的贴底、有的浮空。

## 调试叠加层 / 临时 UI

| 键 | 作用 |
|---|---|
| `M` | 城镇列表 |
| `L` | 世界调试面板（地板块/区域框/落点/网格/图层提升/**移动范围 Y 滑块**） |
| `G` | 绿色透明地板块叠加 |
| `[` / `]` / `\` | 区域框 / 每张图落点 / 通行网格 |
| `U` | 临时隐藏 HUD、调试面板、城镇列表；再按恢复 |
| `1`–`7` | 把 distantback/middleback/closeback/bottom/normal/close/front 抬到角色下方；`0` 取消 |
| `-` / `=` | 移动范围 Y −16 / +16 px（−240~240）；调试面板里也有 16px 步长滑块，松手才重建 |

- 地板块按**实际贴图尺寸**画，不是固定 224；标签 `T列 宽×高 文件名` 会直接暴露非 224 地砖。
- `block_w` 固定 224，不再提供调宽；只提供 `movable_y_offset`（16px 步长，x 不变），**只移动通行网格/出生点**；area/触发框/传送门/副本框固定按 `origin_y`，不跟。NPC、装饰、地砖也不动。调整后房间会重建；玩家位置保留，落到阻挡格才回出生点。
- 图层提升只改 `meta("layer")` 匹配的节点，原 z 存在 `meta("z0")`；每帧取 `min(player.z_index - 1, 最近 actor 的 z - 1)`，所以既比角色低、也不会盖住 NPC/怪物。取消或换层恢复 `z0`。
- 每次 `_load_room()` / `_rebuild_room()` 都由 `RoomBuilder._log_placements()` 打 DEBUG 级 `[MapPlace]`，逐条含 `node` / `canvas` / `off` / `final` / `actual` / `size` / `z` / `layer`（`actual` 是最终落点，NPC 已加画布原点）；区域移动另打 `[AreaMove]` / `[AreaSpawn]`。全量冒烟日志会到 20 MB 级，测试可用 `WORLD_PLACE_LOG=0` 关掉落点日志。

## 自测

```bash
export XDG_DATA_HOME="$PWD/.tmp_udata"
export GODOT_PROJECT=$PWD/client
./tools/godot.sh --headless --script res://tests/world_smoke.gd   # 669 项：128 城镇全部 area
./tools/godot.sh --headless --script res://tests/world_entities.gd # 12 项：怪物/被动对象解析
./tools/godot.sh --headless --script res://tests/tile_frames.gd # 6 项：地砖 [IMAGE] 帧号（gent 5 帧）
./tools/godot.sh --headless --script res://tests/world_ui.gd      # 53 项：UI/跨城/缓存释放/调试层/通行/图层 cap/移动范围Y/背景视差
./tools/godot.sh --headless --script res://tests/world_walk.gd    # 8/2：城镇手感通过；副本待接
./tools/godot.sh --script res://tests/world_shot.gd -- \
  --out=/tmp/world.png --town=town_hendonmyre.twn --area=1 --ui=1
# 调试面板 + 地板块 + 近背景提升：
./tools/godot.sh --script res://tests/world_shot.gd -- \
  --out=/tmp/world_debug.png --town=town_hendonmyre.twn --area=1 --debug=1 --layer=closeback
```

## 原生来源

- PVF / NPK 路径由 `utils/path_util.gd` 的 `PathUtil.dnf_script()` / `dnf_imagepacks()` 决定（`DNF_ROOT` > 项目设置 `dnf/root` > 默认路径）；由 `utils/pvfloader/pvf_new_archive.gd` 解 nkpi 容器，不经过 sqlite/JSON。
- NPK 由 `utils/npk/npk_live_index.gd` 按路径猜包名、只读候选包表，不做全量扫描。
- 不要在 `game/world` 里重新引入 `assets/pvf/world` 或 `npk-index-latest.bin`；旧静态资产已移到 `_archive/`（有 `.gdignore`，不参与打包/导入）。

## 改本目录时的规矩

1. 新增/修改对外函数、常量、信号、JSON 字段，**同一次改动里更新本文件或对应子目录 README**。
2. 改公式/坐标前先 grep 使用点；成对实现要同步（地砖基础/扩展、城镇/副本、背景/装饰）。
3. 验证至少：`world_smoke` + 相关截图；不该变的画面用 sha256 比较。

## 图层 z 表（2026-11-26）

- 统一在 `build/layer_z.gd` 的 `LayerZ`：`distantback -70`、`middleback -65`、`bottom -50`、`normal -40`、`closeback -35`、`close -30`、`front +20`；背景 -95/-90、地砖 -50、扩展地砖 -79。全部手填在 `[-100,100]`，不做归一化/按高度换算。
- 数字键 `1..7` 依次对应上表；`3` = `closeback`（用户确认置顶效果对）。临时提升目标 `LayerZ.Z_RAISE=95`，再取 `min(95, 最近 actor-1)` 并 clamp `[-100,100]`。
- `[town movable area]` 的 raw(top) 已验证为正确；bottom-up 青色框已从 `_debug_boxes()` 删除，不要再恢复。

## 相机/传送区（2026-11-25）

- 相机 zoom 用固定 `VIEW_SIZE.y / view_h`（`view_h=VIEW_WORLD_H=480`）；**不要**改用 `get_viewport().get_visible_rect().size`，用户明确否定了那套（`world_shot --size` 只改截图尺寸）。
- `[town movable area]` 默认 `movable_y_mode="top"`（raw）；`"bottom"` 才做 `height-y-h`。当前实际触发与粉色 top 框一致。
- `pass_y_offset` 固定 120；`movable_y_offset` 只用于现场调**通行网格**的 y（16px 步长，x 不变），触发框/传送门不动，不要写进内容数据。
- `world_shot --size=1600x1000 --boxes=1 [--movable-y=16]` 可复现 PC 比例并验证竖移；`tests/movable_y_ab.gd` 跑两种 y 假设。

## 坐标偏移（2026-11-25）

- 主 map 用 `town/new_hendonmyre.twn`；默认 `WorldDirector.start_town` 已改。
- `RoomBuilder.pass_y_offset = 120`、`y_shift = 120`；`build()` 写入 `PassGrid.origin_y = pass_y_offset`（area/传送框基准）和 `PassGrid.move_y_offset = movable_y_offset`（**只移动通行网格**）；`walkable_at` 减两者，相机用 `grid.world_height()`。调“移动范围 Y”不改变 area/传送门/副本框。
- NPC y = `raw.y + pass_y_offset`（不是 `map_y`；当前固定 `pass_y_offset=120`，不再读 `[background pos]`）。
- `[town movable area]` 默认 `RectYMode.TOP`，再 `+ origin_y`；`origin_y` 固定 120，不受“移动范围 Y”影响。调试框只画 active（top）那套。
- **可走范围取并集**：`PassGrid.walk_rects` 收集 `town_movable`、`town_movable_anim`、`virtual_movable`（都按 area 坐标 + `origin_y`）；`walkable_at()` 先判矩形，再判地砖 pass 网格。触发/传送仍只认 `room.town_movable`，不因并集而改变。
- **只走 area 调试模式**：`area_walk_only` / `PassGrid.walk_rects_only`，忽略地砖 0/2，只让上面三类矩形决定可走。UI 面板按钮“只走area”，`world_shot --walk=area`。
- 回归：`world_smoke 669`、`world_ui 53`、`world_entities 12`、`tile_frames 6`、`world_walk 8/2`（副本未接）。
