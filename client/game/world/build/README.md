# build —— 房间构建 / 通行 / 动画

## 文件

| 文件 | 职责 |
|---|---|
| `room_builder.gd` | `build(room, defs) -> {"node","pass","actors"}`；节点顺序 Background/Tiles/Deco/Objects/Gates/Actors |
| `pass_grid.gd` | `build(tiles, defs)`、`move(pos, delta)`、`spawn_at(edge)`、`walkable_ratio()`、`make_all_walkable()`；`[pass type]` **0=可走、2=阻挡**，行序按图像自上而下，不翻转 |
| `ani_sprite.gd` | `AniSprite.setup(def, store, offset, apply_frame_pos=true, apply_canvas_offset=false)` |
| `movable_gate.gd` | `[town movable area with animation]` 的可视门：`basic → open → loop / close`，由 `RoomBuilder._build_movable_gates()` 创建 |
| `debug_floor` / `placements` | 地板块叠加与资源落点记录；每次 `build()` 结束由 `_log_placements()` 打 DEBUG |

## 坐标 / 层级（改之前先看）

- 基础地砖：`s.position=(i*224+rect.x, grid.height-rect.height)`，z=-50。
- 通行网格：`cells.fill(2)` 起手（缺图=阻挡），`walkable()` 只认 0；`PassGrid.build()` 的 `vy = y_off + r`，不要再改回 `rows-1-r`。
  - **注意**：这里假设每块地砖 224 宽；已发现 240（`bar06.til`）、218（inae waitingroom）、1（airship dummy）三种非 224 图，`tests/tile_width_audit.gd` 会列出。统一位置前不要把它当唯一规则。
- 扩展地砖：`(i*224+rect.x, grid.height+GROUND_GAP)`，z=-79。
- `[animation]` 装饰：`y = d.y + y_shift - d.z`，画面系；anchor 里加 NPK 帧画布原点，AniSprite 只加 `[IMAGE POS]`。
- 背景：`bg_y = rect.position.y + background_pos + _bg_dy`，`AniSprite(..., apply_pos=false)`；整层只跟镜头 x 做视差，y 固定。
- z 分带见 `_layer_z()`：distantback -70 / middleback -65 / closeback -60 / bottom -50 / normal -40 / close -30 / front 20。
- `[town movable area with animation]`：`grid.map_rect(raw)` 把 raw 转世界坐标（默认 `RectYMode.TOP` 再 `+origin_y`），门节点放在转换后的左上角，局部触发矩形是 `(0,0,w,h)`。
- gate 系地图（`Gate_Seria`）的 5 块 `dummy.til` 没有 `[IMAGE]`，地面不可见；这不是 movable 的问题。
- NPC：`holder.position = (x, raw.y + pass_y_offset)`（2026-11-25 改；旧 `map_y` 会让 NPC 压到可走区底部）；`AniSprite.setup(..., true, true)` 把 NPK 帧画布原点也加上，否则会浮空。名字 Label 按首帧 `dy+canvas.y` 放在头顶。
- 调试地板块：`debug_floor=true` 时 `_build_floor_boxes()` 按**实际帧尺寸**画绿色半透明框 + `T列 宽×高 文件名`，z=2400；用来直接看 218/240/1px 的拼接异常。
- `block_w` 固定 224，用于基础/扩展地砖 x、`map_y()`、`PassGrid.block_w`、地板块和背景平铺宽度；不要再把它当可调参数。
- `movable_y_offset`（默认 0，16px 步长）只加到 `PassGrid.move_y_offset`，只移动**通行网格**（格子/出生点）；`PassGrid.origin_y` 固定 120，area/传送门/副本框不跟。NPC/装饰/地砖也不跟。
- 所有可见资源（地砖/扩展/背景/装饰/物件/movable/NPC/pathgate/marker）都走 `record()`；`_log_placements()` 每条打印 `node`（锚点）、`canvas`（NPK 画布原点）、`off`（`[IMAGE POS]`）、`final`、`size`、`z`、`layer`。

## 缓存

`RoomBuilder` 不持有房间级缓存；`content` 和 `store` 由 `WorldDirector` 注入。释放由 `WorldDirector._unload_room()` 统一做。

## 验证

- `world_smoke.gd`：每个 area/副本格都能装载、通行率 > 0。
- `world_shot.gd`：城镇、副本各一张；改单点时用 sha256 证明另一张没变。


## 通行/区域框（2026-11-25）

- `PassGrid.map_rect(raw)`：地图原始矩形 → 世界 `Rect2`；默认 `RectYMode.TOP`（用户确认粉色 top 框对），再加 `origin_y(120)`；区域触发、调试框、动画门统一用它。bottom 只作 A/B 对照。
- `PassGrid.walk_rects`：`town_movable` / `town_movable_anim` / `virtual_movable` 转世界矩形后取并集；`walkable_at()` 命中矩形即可走，用于补地砖 pass 网格的边角。触发逻辑不读它。
- `_debug_grid()` 绿=可走、红=阻挡；`world_shot --grid=1`。
- 全 2 图不再默认 `make_all_walkable()`，仅 `dummy.til` 过渡图允许。
