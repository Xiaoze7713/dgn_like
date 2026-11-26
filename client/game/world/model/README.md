# model —— 纯数据模型

这些类只做 JSON → 字段 + 少量查询，不碰节点、不读 NPK。

| 文件 | 类 | 关键接口 |
|---|---|---|
| `town_def.gd` | `TownDef` | `from_dict`、`area_count()`、`area(i)`、`map_of(i)`、`dungeon_entrances()`、`neighbor_of(area, dir)`、`display_name()` |
| `map_room.gd` | `MapRoom` | `from_dict`、`tile_count()`、`width()`、`gates()`、`gate(dir)`、`all_tile_paths()` |
| `dungeon_def.gd` | `DungeonDef` | `from_dict`、`walkable_cells()`、`map_path(x,y)`、`start_cell()`、`cell_extent()`、`has_cell()` |
| `greed_grid.gd` | `GreedGrid` | `step(x,y,bit)`、`neighbors(x,y)`、`has()` |
| `tile_def.gd` | `TileDef` | `from_dict`、`img`/`frame`/`img_pos`/`pass` |
| `ani_def.gd` | `AniDef` | `from_dict`、`is_empty()`、`at(i)`、`total_ms()` |
| `npc_def.gd` | `NpcDef` | `from_dict(d, ani)`、`display_name()`（过滤 `Animation/...`、`[role]` 之类假名字） |
| `region_def.gd` | `RegionDef` | `from_dict`；`name`、`town_keys`、`minimap` |
| `monster_def.gd` | `MonsterDef` | `from_dict`；`id`/`name`/`width`/`stay_ani_path`/`move_ani_path` |
| `object_def.gd` | `ObjectDef` | `from_dict`；`id`/`name`/`layer`/`pass_type`/`basic_action`/`ani_path`/`sub_anis` |

## 数据结构要点

- `MapRoom.town_movable`：平铺 int，每 6 个一组 `x y w h target_town target_area`。
- `MapRoom.pathgate`：左 右 上 下 四组 `x,y`。
- `TownDef.neighbor_of`：用 `[minimap rect]` 的 Rect2 贴边 + 重叠判断。
- `NpcDef.display_name()` 优先 `field_name`，其次 `name`；路径/角色标签会被过滤。
- `MapRoom.monsters`：`id/auto/level/x/y/z/rdrop/sdrop/copy/kind/npc`（`copy`=fixed/half/ratio，`kind`=normal/champion/boss）。
- `MapRoom.objects`：`id/x/y/z/obj/ani/layer/pass_type`。

## 改动规则

改字段先在 `build_pack.py` 找写入点，再 grep 运行时读取点；两边字段名必须一致。
