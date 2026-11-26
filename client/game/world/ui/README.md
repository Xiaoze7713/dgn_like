# ui —— 世界 UI

## town_list_ui.gd

`TownListUI` 是 `Control`，由 `WorldDirector._build_ui()` 放进 `CanvasLayer`。

| 成员 | 说明 |
|---|---|
| `setup(content: PackContent)` | 注入内容包 |
| `open_for(current_key)` / `close()` / `toggle(current_key)` | 开关 |
| `is_open()` | 状态 |
| 信号 `town_selected(key)` | 点行；由 director 接 `_on_town_selected` |
| 信号 `opened` / `closed` | director 用它们暂停/恢复玩家 |

- 数据只读 `content.load_index().towns`，按 `region_name` 分组，按 `town_id` 排序。
- 当前城用 `●`，其余 `○`；行文本含中文名和 area 数。
- `_input` 里 M / Esc 关闭，并 `set_input_as_handled()`，避免和 director 的 action 双触发。
- 字体走 `WorldFont`，不要用默认字体（中文会缺字）。

## world_debug_ui.gd

`WorldDebugUI` 是 `Control`，由 `WorldDirector._build_ui()` 放进 `WorldUI` CanvasLayer，默认隐藏，`L` 开关；顶部有“移动范围 Y”滑块（16px 步长），拖动时只更新数值，松手 `drag_ended` 才发 `action("movable_y", ...)`；只改 y，x/宽度不动。

| 成员 | 说明 |
|---|---|
| 信号 `action(name, arg)` | director 接 `_on_debug_action`；`floor/boxes/place/grid/walk_area` 是开关，`layer` 带层名 |
| `set_state(key, on)` | 同步开关按钮，不触发信号 |
| `set_layer(key)` | 高亮当前提升层（绿色） |
| `set_movable_y(value)` | 同步“移动范围 Y”滑块与数值标签（−240~240，16px 步长，默认 0） |
| `LAYERS` / `LAYER_LABELS` | 7 个固定层和中文名 |

- 面板只发动作，不直接碰场景；所有开关走 director 同一条入口。
- 右侧固定 326px 面板，`U` 会连同 HUD/城镇列表一起隐藏。

## world_font.gd

`WorldFont.make(weight: int = 400) -> SystemFont`：CJK family + `allow_system_fallback=true`。新增 UI 一律用它。

## 自测

`tests/world_ui.gd` 覆盖：打开、分组、4 个按钮、当前标记、点击传送、关闭恢复、跨城、`-2/-2` 弹窗抑制、缓存上限，以及实时角色坐标、地板块、图层提升、`L`/`U` 调试开关。
