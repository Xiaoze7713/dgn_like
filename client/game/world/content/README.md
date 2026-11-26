# content —— 内容读取（原生 PVF / 旧 JSON 兼容）

## 文件

`live_pvf_content.gd`：`LivePvfContent`，世界运行时实际用的内容源；直接读 `Script.pvf` 的 nkpi 容器和 token，不生成/读取 JSON。

`pack_content.gd`：`PackContent`，旧的 JSON 内容包读取器，仅保留兼容；`WorldDirector` 不再实例化它。

## 关键 API

| 方法 | 说明 |
|---|---|
| `load_index() -> Dictionary` | `LivePvfContent` 先扫 `list/town.lst`/`list/npc.lst`/`list/monster.lst`/`list/passiveobject.lst`，再现场解析地区；永久缓存 |
| `key_of(path) -> String` | 路径归一化；正则 `KEY_PATTERN="[^a-z0-9._-]+"` 必须与 `tools/pvf_world/build_pack.py:key_of()` 完全一致 |
| `has_town/has_dungeon/has_map/has_npc` | 存在性判断（只查 index，不读大 JSON） |
| `town(key) -> TownDef` | 永久缓存 |
| `town_key_by_id(id) -> String` | 跨城传送用；来自 index 的 `towns_by_id` |
| `region(key) -> RegionDef` / `regions() -> Array` | 地区与城镇列表 |
| `npc(id) -> NpcDef` | NPC 静态数据（名字/动画/脸图） |
| `monster(id) -> MonsterDef` | `.mob` 的最小模型：名字/站立动画/移动动画；缓存常驻 |
| `object(obj_path) -> ObjectDef` | `.obj` → 可选 `.act` → base ani；缓存常驻 |
| `dungeon(key, maze_index=0) -> DungeonDef` | 永久缓存；原生 `.dgn` 解析尚未接 |
| `map_room(path) -> MapRoom` | 房间级缓存（transient） |
| `tiles_for(room) -> Dictionary` / `anis_for(paths)` | 批量取定义；transient |
| `trim_cache(max_transient=64, max_defs=128)` | 切图/释放时裁剪；`LivePvfContent` 另有 map LRU 16 / ani LRU 256 |
| `cache_stats() -> Dictionary` | `{"permanent","transient","defs","npcs","monsters","objects"}`，HUD 在用 |

## 缓存分层

- `_cache`：index / towns / dungeons / regions / npcs —— 小且常驻。
- `_transient`：maps / tiles / anis / objects —— FIFO，超 `MAX_TRANSIENT=64` 淘汰。
- `_defs`：解析后的 `AniDef` / `TileDef` / `NpcDef` —— FIFO，超 `MAX_DEFS=128` 淘汰。
- `_object_cache` / `_monster_cache`：`.obj`/`.mob` 解析结果，常驻（数量小、跨房间复用）。

**不要**把 map/tile/ani 放进 `_cache`；否则来回切城会一直涨。

## 地砖 `[IMAGE]`

`.til` 的 `[IMAGE]` 是**混合值**：`<img 路径> <帧号>`。解析时必须用 `DocNode.values`，
不能用 `strings()`（后者只留字符串，帧号被丢掉，结果所有地砖都落到 frame 0）。
gent 的 `Imperial_Palace_Tile.img` 有 5 帧，`imperial_palace_tile00..04.til` 分别对应 0..4；
`tests/tile_frames.gd` 就是这条回归。

## 怪物/被动对象

- `[monster]`：一条 label 可含 N 条 8-int 记录；用 `_parse_monsters()` 按 token 流切，不能按固定宽度切。
- `[passive object]`：固定 4-int `id x y z`；id → `list/passiveobject.lst` → `.obj`；优先 `[basic action]` → `.act [BASE ANI]`，否则 `[basic motion]` 直接是 `.ani`。
- 两者只负责地图渲染数据；碰撞/战斗逻辑不在 `LivePvfContent` 里。

## 加新内容类型

1. `build_pack.py` 输出新目录 + index 字段；
2. 这里加 `has_x` / `x()` / 对应模型；
3. 更新 `game/world/README.md` 的调用链。
