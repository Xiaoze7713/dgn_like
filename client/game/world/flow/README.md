# flow —— WorldDirector 总控

`world_director.gd` 是 `scenes/world.tscn` 的根脚本，负责原生 PVF、原生 NPK、房间、玩家、相机、UI、输入、缓存生命周期。`content` 是 `LivePvfContent`，不读 JSON 内容包。

## 对外入口

| 方法 | 说明 |
|---|---|
| `enter_town(key, area=-1, spawn_edge="center") -> bool` | 进城镇；`area<0` 时用 `_default_area` |
| `enter_town_area(i, spawn_edge="center") -> bool` | 同城内换 area；缺图自动回退 |
| `enter_dungeon(key, maze_index=0) -> bool` | 按 key 进副本 |
| `enter_dungeon_by_id(id) -> bool` | 按 PVF 副本 id 进副本 |
| `dungeon_key_for_id(id) -> String` | 查 `index.dungeons`（原生 `.dgn` 待接） |
| `return_to_town() -> bool` | 回 `last_town_key/last_town_area` |

## 状态

`mode`（""/town/dungeon）、`room`、`grid`、`town`、`town_key`、`town_area`、`dungeon`、`dungeon_key`、`cell`、`last_town_*`。
信号：`room_changed(map_path, mode)`。

## 每帧检查

- 城镇：`_check_town_movable()` → `_check_town_edge()`。
- `player` 建后加入 `world_player` 组，供 `build/movable_gate.gd` 找玩家；`[town movable area with animation]` 的门动画由 `RoomBuilder._build_movable_gates()` 挂到 `Gates` 层。
- 副本：`_check_dungeon_edge()`。
- `_ui_open` 时 `_process` 直接 return，玩家 `set_process(false)`。

## 城镇 movable 规则

`x y w h target_town target_area`：
- `-1/-1`：当前城镇副本入口；
- `-2/-2`：打开城镇列表（会记 `_suppress_movable`，站在触发区里不重复弹）；
- `target_town` 等于当前 `town_id`：同城换 area；
- 其它正数：`content.town_key_by_id()` 跨城。

## 输入

A/D/W/S 移动，E 交互（副本门/副本入口），Esc/R 回城，HOME 重置，M 城镇列表，`[ ]` 缩放，`\` 复位，`; , . /` 装饰调试。F 键禁用（编辑器冲突）。

新增调试键：`G` 地板块、`L` 世界调试面板、`U` 临时隐藏 HUD/面板/城镇列表、`1`–`7` 把固定图层抬到角色下方、`0` 取消、`-`/`=` 移动范围 Y ±16px（−240~240，x 不变）。改后 `_rebuild_room()` 会重建房间；玩家位置保留，卡进阻挡格才回出生点。图层提升的节点来自 `RoomBuilder` 写入的 `meta("layer")` / `meta("z0")`；每帧 `_apply_raise_z()` 取 `min(player.z_index - 1, _raise_ceiling - 1)`，`_raise_ceiling` 是最近 actor 的 z，所以不会盖住 NPC/怪物。

`_sync_parallax()` 只对背景层做 x 视差；y 固定不随镜头上下动（用户 2026-11-26 要求）。

## 释放

`_unload_room()`：
```
for c in room_holder.get_children(): remove_child(c); c.free()
grid=null; room=null; room_node=null
store.trim(320,24)
content.trim_cache(40,80)
```
随后 `_load_room()` 再构建新房间。改这里要同时看 `tests/world_ui.gd` 的缓存断言。


## 区域移动标记（2026-11-25）

- `[town movable area]` 的 raw `x/y/w/h` 默认按 `RectYMode.TOP` 转世界坐标，再 `+grid.origin_y`（固定 120）；必须走 `grid.map_rect()`。调“移动范围 Y”只改 `grid.move_y_offset`，不改 `origin_y`。
- `_check_town_movable()`、`RoomBuilder._debug_boxes()`、`MovableGate` 三处共用这一条转换。
- `]` 开诊断框（粉 `mov→目标`、绿 `movA→目标`）；`world_shot --boxes=1` 可截。
- 全 2 的普通地图不再整间解锁，只有全 `dummy.til` 的过渡图才退化；`world_smoke` 的 `KNOWN_BLOCKED` 记录 4 张。
