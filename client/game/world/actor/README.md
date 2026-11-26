# actor —— 玩家

`world_player.gd`：`WorldPlayer`，`_process` 读取输入，按 `pass_grid` 做轴分离移动（撞墙时还能沿另一轴滑）。

| 成员 | 说明 |
|---|---|
| `move_speed` / `SPEED_SCALE=0.26` | 实际像素速度 `speed_px()` |
| `pass_grid: PassGrid` | 由 director 注入 |
| `position` | 世界坐标；`reset_to_spawn()` 会用 `grid.spawn_at()` 重置 |
| `facing` / `moving` | 朝向 / 是否在移动；决定 move 还是 stay |

当前城镇角色是 **鬼剑士**：`setup_visual(content, store)` 用 `character/swordman/animation/move.ani` / `stay.ani`，按 body 的 `AniDef` 复制出 5 层同帧图（look=0）：skin → pants → shoes → coat → hair，只播 move/stay，不接攻击/跑步。各层图在 `character/swordman/equipment/avatar/{skin,pants,shoes,coat,hair}/`，同帧号、同画布；缺哪层就跳过哪层，全缺回退原色块。

换角色资源时不要把移动/通行逻辑塞进绘制。
