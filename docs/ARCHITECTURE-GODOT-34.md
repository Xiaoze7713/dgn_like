# dnf_like（Godot）现有架构说明书

> 目的：给接手做架构优化的人一份「哪个文件负责哪件事、从哪进、数据从哪来、哪里已经烂了」的完整地图。
> 实测基准：`client/`（工作区符号链接 `dnf_like/dnf_like`），2026-11-15，Godot 4.7.2。
> 全部结论来自源码 grep + headless 实跑，不是推测；推测处会标「推断」。

---

## 0. 一句话总览

一个**单房间（Single Room）原型**：主场景 `scenes/sf85_mirkwood.tscn` 的根节点 `Room`（`game/sf85/room.gd`，513 行）在 `_ready()` 里顺序做完「装键位 → 打开 PVF/NPK 资产 → 铺地图 → 生成怪物和玩家 → 挂 HUD → 挂 UI → 调相机」，之后每帧轮询热键/手柄，并把战斗事件转发给 UI。UI 是一套自研的 DNF 风格控件库（`ui/`），数据是真 PVF（`utils/pvfloader` + `utils/npk`）但**物品/背包用的是假数据**（`ui/data/item_db.gd`）。

没有网络、没有存档、没有场景管理、没有 AI 模块（怪物 AI 就是 `monster.gd` 里 30 行的追击状态机）。

---

## 1. 工程配置（`project.godot`）

| 项 | 值 |
|---|---|
| 主场景 | `res://scenes/sf85_mirkwood.tscn` |
| Autoload | `Env` → `core/app_env.gd`；`Log` → `core/log/log.gd` |
| 视口 | 1600×1000，`window/stretch/mode="disabled"`，aspect `expand` |
| 物理 | `3d/physics_engine="Jolt Physics"`（但本工程 2D 玩法未用物理引擎） |
| 渲染 | `rendering_device/driver.windows="d3d12"` |
| C# | `[dotnet] project/assembly_name="dnf_like"`（**占位**：`find -name "*.cs"` 与 `*.csproj` 均为 0） |
| 输入 | **没有 `[input]` 段** —— 所有 InputMap 动作都是运行时 `InputMap.add_action()` 建的 |
| 自定义设置 | `sf85/pvf`（PVF 路径覆盖，读于 `room.gd:_pvf_path()`） |

工程根还有：`project.godot.bak_ui2_20261114_172449`、`project.godot.bak_ui3_20261114_184951`（两代 UI 重构备份，可直接删）。

---

## 2. 目录地图

| 目录 | 职责 | 状态 |
|---|---|---|
| `game/sf85/` | 玩法层：房间编排、玩家、怪物、精灵、资产库、PVF 装配、HUD | **活跃**（唯一的游戏逻辑） |
| `ui/core/` | UI 框架：根容器、窗口、面板、按钮、页签、格子、提示、主题工具 | **活跃** |
| `ui/windows/` | 具体窗口：背包、金库、键位设置 | **活跃** |
| `ui/data/` | 物品数据：`ItemDef` + `ItemDB`（**假数据**） | 半活跃（只被背包/金库用） |
| `ui/debug/` | 调试控制台（F1）与三种控件 | 活跃（开发用） |
| `ui/theme/`、`ui/shaders/` | 主题数据（`UITheme`）、磨砂玻璃 shader | 活跃 |
| `ui/themes/` | 只有 README，**没有实际主题文件** | 空壳 |
| `core/input/` | 键位系统：`DnfKeys`（键盘，123 动作）、`GamepadKeys`（手柄，双预设） | **活跃** |
| `core/log/` | 自研日志（`LogCore` 526 行 + `Log` autoload） | **可用但没人用**：只有 `tests/probe_scene.gd`、`tests/test_logger.gd` 调；`game/` 与 `ui/` 里 0 处 `Log.`、0 处 `print` |
| `core/app_env.gd` | 环境探测（平台/版本/路径），autoload `Env` | 活跃（用途主要是日志与诊断） |
| `core/config.gd`、`constants.gd`、`global.gd` | 各 11 行空壳 | **死**（历史遗留） |
| `utils/pvfloader/` | PVF 容器读取：`PvfArchive`/`PvfDocument`/`PvfTypes`/`PvfAnimation` + `PVFLoader` | **活跃**（核心数据入口） |
| `utils/npk/` | NPK 图集读取与缓存：`NpkStore`/`NpkIndex`/`NpkImage` | **活跃** |
| `services/` | `database_service`/`logger_service`/`redis_service` 各 11 行空壳 | **死**（0 引用、未注册 autoload） |
| `sqr_gd/` | 老 DNF Squirrel→GDScript 转写的**遗留大目录**（196 个 .gd：角色技能、被动对象等） | **死**（只有 `tests/check_sqr.gd` 会 load 它们做语法检查） |
| `tests/` | 18 个 `SceneTree` 脚本（`test_*` 断言 + `probe_*` 探针） | 活跃（手工跑） |
| `assets/` | `npk-index.bin`（2.9 MB 图集索引缓存）、`sf85/Script.utf8.pvf`（数据源） | 活跃 |
| `data/` | `dnf_hotkeys.json`（123 条 DNF 动作表，从客户端 PVF 导出） | 活跃（被 DnfKeys 读） |
| `models/`、`resources/`、`zz_tmp_s14/` | 空 | 死 |
| 场景文件 | 全工程只有 4 个：`scenes/sf85_mirkwood.tscn`、`ui/ui_demo.tscn`、`tests/probe_scene.tscn`、`node_2d.tscn` | — |

---

## 3. 启动时序（`room.gd:_ready()` 逐行实测）

```
Room._ready()
├─ RenderingServer.set_default_clear_color(...)
├─ DnfKeys.install()            # 建 123 个 InputMap 动作 + 8 个语义动作，apply()
├─ GamepadKeys.install()        # 建 pad_* / dodge / pad_look_*，apply()；并 DnfKeys.watch(...)
├─ _bind_keys("debug_toggle",[F12]) / ("ui_console",[`]) / ("sf85_warehouse",[K])
├─ _open_assets()               # → Sf85Assets.open(pvf_path, npk-index.bin)  失败则 HUD 报错并 return
├─ _build_tiles() / _build_background() / _build_decos()
├─ _build_pass()                # 30×30 通行格，cell=16
├─ _spawn_monsters()            # 读 monster/monster.lst
├─ _spawn_player()              # 读 character/swordman/swordman.chr + 默认时装/武器
├─ DamageLayer(Node2D, z=200)
├─ hud.setup(player, damage_layer, camera)
├─ _setup_ui()                  # IngameUI.new() → add_child → ui.bind(assets, player.def, hud, self)
├─ _build_bottom_hud()          # Sf85HudBottom，连 3 个信号
├─ camera 限制 + size_changed→_update_camera_zoom()
└─ 环境变量开关：SF85_DEMO / SF85_UI_SCALE / SF85_UI_DEMO
```

每帧：
```
Room._process(delta)
├─ _poll_hotbar_keys()     # 12 个技能键 + 6 个物品键 + I61 设置 + _poll_gamepad()
├─ hud_bottom.set_skill_cd(0, ...)
├─ demo_mode → _demo_tick()
├─ camera.global_position = player.global_position + (0,-60)
└─ debug_toggle → debug_draw
```

---

## 4. 六个入口（接手时最该先认的六件事）

### 入口 A：场景入口 —— `game/sf85/room.gd`
整个游戏只有它一个入口。没有 class_name，靠场景挂载。
它同时承担 7 个职责：资产装载 / 关卡几何 / 实体生成 / 输入轮询 / HUD 桥接 / UI 桥接 / 相机与调试绘制。
**它是所有架构问题的发源地**（见 §12 P0-1）。

### 入口 B：UI 入口 —— `ui/ingame_ui.gd` → `ui/core/ui_root.gd`
- `IngameUI`（69 行）：一个 `CanvasLayer(layer=10)` + 一个 `UIRoot` 子节点；提供 `open_inventory/open_console/open_keybinds/toggle_inventory` 转发；`bind(assets, actor, hud, room)` 把资产与调试钩子灌进 `UIRoot`。
- `UIRoot`（375 行）：窗口管理器。持有 `dim`（遮罩）+ `back_buffer`（磨砂玻璃用 `BackBufferCopy`）+ 窗口字典；负责主题、缩放、窗口居中、`_unhandled_input` 快捷键、`close_all()`。
- **注意**：`UIRoot` 是 `Control` 而不是 `CanvasLayer`，它由 `IngameUI` 承载；`IngameUI` 只被 `room.gd` `new()` 出来，没有 .tscn 模板。

### 入口 C：输入入口（**当前有三处，彼此不知道对方存在**）
1. `core/input/dnf_keys.gd`（Keyboard）+ `core/input/gamepad_keys.gd`（Gamepad）—— **建表**：`install()` 把 123 个 DNF 动作 + 语义动作（`move_left/attack/jump/skill/skill2`）+ 手柄动作（`pad_*`、`dodge`）写进 InputMap。
2. `room.gd:_poll_hotbar_keys()` / `_poll_gamepad()` —— **轮询式**读取：`DnfKeys.is_just_pressed(id)`、`GamepadKeys.read()`。技能/药水/切目标/菜单都在这。
3. `ui/core/ui_root.gd:_unhandled_input()`（337 行起）—— **事件式**读取：I12 背包、`sf85_warehouse` 金库、I61 键位、F1 控制台、F3 换肤、Esc 逐层关闭。
4. 还有第四种：`player.gd:_physics_process()` 里**直接** `Input.is_action_pressed("move_left")` 等。

后果：UI 打开时游戏仍在读移动/攻击输入（没有输入屏蔽层、没有 context stack）；同一按键在 UI 与玩法两侧可能同时命中；手柄输入完全不经过 UI（`ui_root` 只处理 `InputEventKey`）。

### 入口 D：数据入口 —— `Sf85Assets.open()` → `Sf85Pvf` → `PVFLoader`
`game/sf85/asset_lib.gd`（203 行）是**资产门面**，`game/sf85/pvf_lib.gd`（512 行）是**PVF→游戏对象的装配器**：
`build_player()/build_monster()/build_room()/animation()/equ_layers()/skill_info()/mob_info()` 把 PVF 文本变成"动画层 + 判定框 + 数值"。
底层 `utils/pvfloader/*` 只做容器解析（`PvfArchive` 解压、`PvfDocument` 取 tag、`PvfAnimation` 还原 ani），`utils/npk/*` 负责图集与纹理。

### 入口 E：事件/信号入口（跨层通信只有这几条线）
- `Sf85Actor`（`actor_sprite.gd`）：`anim_finished(anim_name)`、`frame_changed(anim_name, index)` —— 动画是唯一的时间基准。
- `Sf85Player`：`hit_landed(boxes, damage, launch, push)`、`damaged(amount, world_pos)`。
- `Sf85HudBottom`：`skill_used(index)`、`consumable_used(index)`、`button_pressed(id)`。
- `UIWindow`：`opened`、`closed`、`item_selected(item)`。
- 连线点全在 `room.gd`（`_on_player_hit` / `_on_player_damaged` / `_on_skill_used` …）。**没有全局 EventBus**，所以新增跨层事件必须改 room。

### 入口 F：调试/自动化入口（环境变量 + 测试脚本）
见 §10 环境变量表；`tests/*.gd` 全部 `extends SceneTree`，`tools/godot.sh --headless --script res://tests/xxx.gd` 跑。

---

## 5. 分层图

```
┌──────────────────────────────────────────────────────────────┐
│ 入口层   scenes/sf85_mirkwood.tscn → Room(room.gd)            │
├──────────────────────────────────────────────────────────────┤
│ 输入层   core/input/dnf_keys.gd   core/input/gamepad_keys.gd  │
│          （建表）        ↑轮询                 ↑轮询           │
├──────────────────────────────────────────────────────────────┤
│ 玩法层   Sf85Player ─┐                                        │
│          Sf85Monster ┴→ Sf85Actor(Node2D: 精灵+动画+判定框)    │
│          Sf85DamageNumber / pass_grid / mesh tiles            │
├──────────────────────────────────────────────────────────────┤
│ 表现层   Sf85Hud(左上状态条)  Sf85HudBottom(底部技能/消耗品条)  │
│          IngameUI → UIRoot → UIWindow(背包/金库/键位/控制台)    │
├──────────────────────────────────────────────────────────────┤
│ 数据层   Sf85Assets → Sf85Pvf → PVFLoader(PvfArchive/Document/ │
│                           Animation) + NpkStore(NpkIndex/Image)│
│          ItemDB(假数据) ← 只被 UI 用                            │
├──────────────────────────────────────────────────────────────┤
│ 基础设施 Env / Log / DnfKeys / GamepadKeys / UITheme / UIKit   │
├──────────────────────────────────────────────────────────────┤
│ 遗留层   sqr_gd/(数百文件) services/(空壳) core/{config,       │
│          constants,global}(空壳) ui_demo/models/resources      │
└──────────────────────────────────────────────────────────────┘
```

---

## 6. 玩法层详解

### 6.1 `Sf85Actor`（`game/sf85/actor_sprite.gd`，178 行）—— 名字骗人
它**不是**角色基类，而是"**精灵+动画播放器**"：持 `def`（PVF 的 actors 节点）、`assets`、`_layers: Array[Sprite2D]`、`_frames_pos`、`_layer_defs`，暴露 `play(name)`、`stop()`、`boxes(kind)`（取判定框）、`body_width`、`body_rect`、`frame_changed`/`anim_finished` 信号。
`Sf85Player`/`Sf85Monster` 都 `extends Sf85Actor` —— 是**继承错位**（"玩家是一种精灵"），导致角色逻辑与渲染耦合在一个节点上（见 P0-3）。

### 6.2 `Sf85Player`（`player.gd`，295 行）
- 状态机字段 `state: "idle/move/jump/attack/skill/hit"`（**用字符串枚举**，无 enum、无状态类）。
- 移动：`_physics_process` 里直接读 InputMap，`SPEED_SCALE=0.26`、`speed_x=220`、`speed_y=150`、`VERTICAL_RATIO=0.68`；跳跃 `z_height/z_vel`（伪 3D 高度，`GRAVITY=1100`、`jump_v=330`）。
- 攻击：`_attack()` → `_start_attack(i)` → 播 `COMBO` 动画之一，`_hit_frames` 记录"已触发判定的帧集合"，到帧时发 `hit_landed(boxes, damage, launch, push)`；连击窗口 `COMBO_WINDOW=0.85`。
- 技能：`_can_use_skill()`（MP/冷却）→ `_skill()`，动画固定 `SKILL_ANIM="attack2"`；`skill_info` 来自 `skill/swordman/upperslash.skl`；`hotbar_skill(index)` 目前只认 index 0。
- 受击：`take_damage(amount, from_x)`，带 `_invuln` 与 `state="hit"`。
- 数值来自 PVF：`_read_stats()`（`.chr` + `.equ`），`DAMAGE_SCALE=0.03` 是全局伤害缩放。

### 6.3 `Sf85Monster`（`monster.gd`，157 行）
`state: "idle/chase/attack/hit/down/dead"`；`sight=300`、`reach=56`、`attack_cd=1.6`、`HP_SCALE=0.6`、`PUSH_SCALE=0.4`。
AI 全在 `_physics_process` 里：距离 < sight → chase；距离 < reach 且冷却好 → attack → `_try_hit_target()` → `target.take_damage(...)`；`take_hit()` 处理击退/浮空/死亡。

### 6.4 战斗数据的流向（唯一一条链）
```
动画帧事件 → Sf85Actor.frame_changed
   → Sf85Player._physics_process 检查 _hit_frames
   → emit hit_landed(boxes, damage, launch, push)
   → Room._on_player_hit()  ← 这里做命中判定（遍历 monsters、算伤害/击退）
   → Sf85Monster.take_hit(damage, from_x, launch, push)
   → Sf85Hud 飘字（`hud.gd:84-101`，`show_damage_numbers` 开关，节点挂到 room 建的 DamageLayer）
```
**命中判定不在角色里，在 room 里**（`_on_player_hit`），这是 P0-2 的核心：战斗逻辑与场景编排混在一个脚本，无法单测、无法复用。

---

## 7. AI 现状（重要：**没有 AI 模块**）

- 活跃 AI = `monster.gd` 的 30 行状态机（追-打-受击-死）。**没有寻路**（`pass_grid` 只给玩家与 tile 用，怪物直接朝玩家直线走）、没有仇恨表、没有技能选择、没有多阶段。
- DNF 客户端那套 AI（`.ai` 数据 2 万+ / `.lua` 4,496 个）**本工程完全没有接入**，PVF 里的 `clientonly/lua/ai/*` 一行都没读。
- `sqr_gd/` 里也没有 AI（只有角色技能/被动对象转写）。
- 结论：要做"怪物行为"，现在是**从零开始**，建议直接接入我们已解出的 `.ai`/`.lua` 语义（见 `docs/AI-LOGIC-34.md`），而不是继续扩 `monster.gd`。

---

## 8. UI 层详解

### 8.1 框架骨架
| 文件 | 行 | 角色 |
|---|---|---|
| `ui/ingame_ui.gd` | 69 | CanvasLayer(10) + UIRoot 宿主，被 room 创建 |
| `ui/core/ui_root.gd` | 375 | 窗口管理器：dim 遮罩、`BackBufferCopy`(磨砂)、窗口增删/居中/缩放、快捷键、主题切换 |
| `ui/core/ui_window.gd` | 211 | 窗口基类：标题栏/状态栏/body/content、开合动画、拖动、`wire_slot()` 接 tooltip |
| `ui/core/ui_panel.gd` | 97 | 面板九宫格 |
| `ui/core/ui_title_bar.gd` | 112 | 标题栏（标题/关闭钮/拖拽） |
| `ui/core/ui_tab_bar.gd` | 154 | 页签 |
| `ui/core/ui_slot.gd` | 287 | 格子（图标/数量/稀有度边框/选中） |
| `ui/core/ui_item_grid.gd` | 165 | 可滚动格子网格 |
| `ui/core/ui_tooltip.gd` + `ui_tooltip_layer.gd` | 233+75 | 物品提示 |
| `ui/core/ui_kit.gd` | 181 | 静态绘制工具：主题取值、样式盒、文本、菱形、角标、分隔线、数字格式化 |
| `ui/core/ui_weight_bar.gd` / `ui_currency_bar.gd` | 83+83 | 负重条 / 货币条 |
| `ui/core/ui_character_preview.gd` | 200 | 角色预览（用 NPK 帧拼） |
| `ui/core/ui_bag_summary.gd` | 107 | 背包摘要 |
| `ui/theme/ui_theme.gd` | 275 | 主题 Resource（颜色/字号/间距字典） |
| `ui/theme/ui_theme_presets.gd` | 148 | 4 套预设：abyss / ember / jade / violet |

### 8.2 窗口清单
| 文件 | 行 | 说明 |
|---|---|---|
| `ui/windows/inventory_window.gd` | **853** | 全工程最大单文件：装备栏 + 属性面板 + 物品格 + 分类页签（物品/时装/宠物） |
| `ui/windows/warehouse_window.gd` | 209 | 个人/账号金库，6 个筛选页签 |
| `ui/windows/keybind_window.gd` | 297 | 键盘设置：5 页签（系统/角色/技能/聊天/手柄）+ 按键录制 |
| `ui/debug/ui_debug_console.gd` | 328 | F1 控制台（含 `ui_debug_toggle/slider/option` 三控） |

### 8.3 数据：`ItemDB` 是**假数据**
`ui/data/item_db.gd`（603 行）里全是硬编码物品（`equipment()` / `inventory_items()` / `warehouse_items()` / `common_materials()` / `character_attributes()`），图标靠 `icon_*()` 里写死的 NPK 帧号。
**它与 PVF 的真实装备体系（38 万 .equ / 383,719 个）完全不通** —— 背包/金库现在只是 UI 演示。这是 P1-3。

### 8.4 快捷键（`ui_root.gd:_unhandled_input`）
I12 → 背包 / `sf85_warehouse`(K) → 金库 / I61(F9) → 键位 / F1 → 控制台 / F3 → 换肤 / Esc → 逐层关闭（键位 → 控制台 → 金库 → 背包）。

### 8.5 主题与磨砂
`UIRoot._ready()` 建 `dim`(黑 34%) 与 `BackBufferCopy(COPY_MODE_VIEWPORT)`；窗口用 `ui/shaders/frosted_glass.gdshader` 采样已画好的画面做玻璃效果。**顺序敏感**（注释里明确写了"在这之后画的内容…"），改层级时容易翻车。

---

## 9. 数据与资源链

```
room._pvf_path()  ── 优先级：env SF85_PVF > ProjectSettings "sf85/pvf"
                    > res://assets/sf85/Script.utf8.pvf
                    > /home/sunmingze/dnf_like/build/sf85.Script.utf8.pvf
                    > E:/dnf-sf/sf85/老牛DNF客户端/Script.pvf
                    > /mnt/e/dnf-sf/sf85/老牛DNF客户端/Script.pvf
        ↓
Sf85Assets.open(pvf_path, "res://assets/npk-index.bin")
        ├─ Sf85Pvf.open()  → PVFLoader → PvfArchive(容器/解压) + PvfDocument(tag 读取) + PvfAnimation(ani 还原)
        └─ NpkStore.load(index) → NpkIndex(索引缓存) → NpkImage(按需读 NPK 内 img)
        ↓
Sf85Pvf.build_player()/build_monster()/build_room()
        ├─ character/swordman/swordman.chr   （角色）
        ├─ equipment/.../askin_default.equ   （默认外观）
        ├─ equipment/.../sswd_shockwave.equ  （默认武器）
        ├─ skill/swordman/upperslash.skl     （技能）
        ├─ monster/monster.lst               （怪物清单）
        └─ map/mirkwood/n201.map             （房间）
```

硬编码路径常量集中在 `asset_lib.gd`（`DEFAULT_SKIN`/`DEFAULT_WEAPON`/`PLAYER_CHR`/`SKILL_UPPERSLASH`/`MONSTER_LIST`）与 `room.gd:ROOM_ID`。**没有资源清单/配置化**，加内容要改代码。

---

## 10. 全局开关（环境变量，全工程实测）

| 变量 | 作用 | 读点 |
|---|---|---|
| `SF85_PVF` | 指定 PVF 文件 | `room.gd:_pvf_path` |
| `SF85_HUD_SCALE` | HUD 缩放 | `room.gd:_ready` |
| `SF85_UI_SCALE` | UI 缩放 | `room.gd:_ready` |
| `SF85_UI_DEMO=1` | 启动即开背包 | `room.gd:_ready` |
| `SF85_HUD_BOTTOM=0` | 关底部 HUD | `room.gd:_build_bottom_hud` |
| `SF85_HUD_PAD=1` | 强制手柄版式 | `room.gd:_poll_gamepad` |
| `SF85_UI_SHOT=<path>` + `SF85_UI_SHOT_FRAMES` | 截图后退出（CI/自动化用） | `ingame_ui.gd:_capture` |
| `SF85_UI_KEYBINDS=1`（+`SF85_UI_KEYBINDS_PAD=1`） | 启动即开键位窗口 | `ui_root.gd` |
| `SF85_DEMO=1` | 自动演示模式 | `room.gd` |
| `SF85_DEBUG` | 通行格调试绘制 | `room.gd` |

---

## 11. 代码规模（非遗留部分，按行数）

| 文件 | 行数 |
|---|---|
| `ui/windows/inventory_window.gd` | 853 |
| `ui/data/item_db.gd` | 603 |
| `core/log/log_core.gd` | 526 |
| `game/sf85/room.gd` | 513 |
| `game/sf85/pvf_lib.gd` | 512 |
| `utils/npk/npk_image.gd` | 519 |
| `game/sf85/hud_bottom.gd` | 489 |
| `core/input/gamepad_keys.gd` | 446 |
| `utils/pvfloader/pvf_archive.gd` | 388 |
| `ui/core/ui_root.gd` | 375 |
| `core/input/dnf_keys.gd` | 333 |
| `ui/debug/ui_debug_console.gd` | 328 |
| `utils/pvfloader/pvf_animation.gd` | 304 |
| `core/app_env.gd` | 299 |
| `ui/windows/keybind_window.gd` | 297 |
| `game/sf85/player.gd` | 295 |
| `ui/core/ui_slot.gd` | 287 |
| `ui/theme/ui_theme.gd` | 275 |
| 非遗留 .gd 合计 | 约 12,000 行 |
| `sqr_gd/` 遗留 | 196 个文件（未计入） |

---

## 12. 架构问题清单（做优化的靶子）

### P0-1 `room.gd` 上帝对象（513 行，7 个职责）
症状：资产装载、关卡几何、实体生成、输入轮询、HUD 桥接、UI 桥接、相机/调试绘制全在一个类；无 class_name；所有跨层信号都在这里连线。
后果：任何改动都要碰它；无法单测战斗；新增内容必须改代码。
建议：拆 `RoomLoader`（资产/几何）、`EntitySpawner`、`InputRouter`、`CombatResolver`、`RoomUiBridge` 五个角色；`room.gd` 只保留"装配 + 生命周期"。

### P0-2 战斗判定在 room 里（`_on_player_hit`）
症状：命中判定、伤害计算、击退、伤害数字生成、死亡清理全在 room 的一个函数里；player 只负责发信号。
后果：战斗规则无法复用到怪物打玩家（另写一份）、无法做伤害公式表、无法单测。
建议：抽 `CombatResolver`（纯数据进纯数据出）+ `DamageTable`（读 PVF `.atk`）。

### P0-3 `Sf85Actor` 继承错位
症状：`Sf85Player extends Sf85Actor`、`Sf85Monster extends Sf85Actor`，而 `Sf85Actor` 实际是"精灵+动画播放器"。
后果：角色逻辑（状态机/输入/数值）与渲染（图集/图层/帧）绑在一个节点；想做"无渲染逻辑测试"或"换渲染实现"都很难。
建议：`Sf85Actor` 改名 `ActorSprite`（或 `VisualActor`），角色改为**持有**它（组合），角色节点只做逻辑。

### P0-4 输入三处割裂、无输入上下文
症状：① `DnfKeys/GamepadKeys` 建表；② `room` 轮询技能/药水；③ `ui_root._unhandled_input` 处理快捷键；④ `player` 直接读 `Input.is_action_*`。
后果：UI 打开时角色仍会动/攻击；手柄不参与 UI 导航；按键冲突需人肉协调（`DnfKeys.watch` 只是重建表）。
建议：引入 `InputRouter`（单一入口 + 上下文栈 `Gameplay / UIModal / Console`），`player` 从 router 拿"意图"而不是直接读 Input；UI 打开时压栈屏蔽玩法。

### P1-1 无场景/关卡管理
只有 `ROOM_ID="map/mirkwood/n201.map"` 一个常量，关卡几何、碰撞格、背景都在 room 里临时构建；无"进出门/切图/加载过渡"。
建议：抽 `RoomDefinition`（数据）+ `RoomBuilder`（构建）+ `GameFlow`（切换/加载/存档点）。

### P1-2 `ItemDB` 假数据与真 PVF 不通
背包/金库/属性面板是**演示品**：603 行硬编码物品 + 写死的图集帧号；不进背包、不穿装备、不减数量。
建议：先做 `EquipmentRepository`（读 PVF `.equ` + `string/*.chn.str` 名称），把 `ItemDB` 降级为"缺数据时的 fallback"。

### P1-3 无事件总线，跨层靠 room 手工连线
新增一条"怪物死亡 → 掉落 → UI 提示"要改 room。
建议：轻量 `Signals` autoload（或 `EventBus` 单例）承载 5–8 个领域事件；room 不再当中间人。

### P1-4 日志组件形同虚设
`core/log/` 526 行自研 + autoload `Log`，但**生产代码 0 处调用**（只有 `tests/probe_scene.gd` 与 `tests/test_logger.gd` 用）；`game/sf85/*` 里既没有 `Log.` 也没有 `print`。全工程 101 处 `print(` 全在 `core/log/log_core.gd`、`tests/probe_*`、`tests/check_sqr.gd`。
后果：玩法出问题只能靠 HUD 文本；headless 跑没有诊断输出。
建议：先在 `room/player/monster/asset_lib` 的关键分支接 `Log.info/warn`（用 `log_tag.gd` 定义 tag），并给 headless 测试加 `--verbose` 开关。

### P1-5 死代码占地
`services/`（3 个空壳）、`core/{config,constants,global}.gd`（3 个 11 行空壳）、`sqr_gd/`（196 个文件，只被 `tests/check_sqr.gd` load 做语法检查）、`ui/themes/`（空）、`models/`、`resources/`、`zz_tmp_s14/`、2 个 `project.godot.bak_*`。
建议：删 `services/`+`core` 三空壳+两个 bak；`sqr_gd/` 移出工程目录（或加 `.gdignore`）只保留 `tests/check_sqr.gd` 的独立副本；空目录删掉。

### P1-6 资源路径硬编码 + 开发机绝对路径
`_pvf_path()` 的回退列表里有 `/home/sunmingze/...` 与 `E:/dnf-sf/...`。
建议：改成 `user://` 配置 + 首次运行引导选择 PVF；代码里只保留 `res://` 与相对路径。

### P2-1 字符串状态机
`state: String`（"idle/move/attack/…"），拼错不报错。
建议：`enum State { IDLE, MOVE, JUMP, ATTACK, SKILL, HIT }`。

### P2-2 无对象池
`Sf85DamageNumber` 每次 `new()` + `queue_free()`（`hud.gd:97`），高连击时会抖动。
建议：`DamageNumberPool`（复用 32 个）。

### P2-3 命中时机绑死在美术帧上
实测 `player.gd:270-282`：攻击/技能期间每帧调 `boxes("attack")`（武器层 `.ani` 里该帧有没有 `[attack box]`），有框就打，`_hit_frames["<anim>#<frame>"]` 只用来保证「同动画同帧不重复打」。PVF `.atk` 里已有的命中帧/反应方向数据只用了 `direction`、`damage_bonus` 等少数字段。
后果：手感完全由美术资源的判定框位置决定；同一动画在连击链里复用时去重键会撞车（前一段的帧号与后一段相同就漏判）；无法做"命中帧表"这种可调参数。
建议：把命中帧表读成资源（`.atk` + `[hit frame]`），判定改为「按帧表触发 + 判定框只定范围」，`_hit_frames` 换成 `attack_instance_id`。

### P2-4 主题/玻璃渲染顺序脆弱
`UIRoot` 依赖 `dim` → `BackBufferCopy` → 窗口 的添加顺序。
建议：把那三条注释变成断言（`assert(get_index_of(back_buffer) < windows_layer_index)`）。

### P2-5 演示/自测逻辑混在生产脚本里
`room.gd:_demo_tick()` + `_pulse(action)` 用 `Input.action_press()` 模拟按键（`SF85_DEMO=1` / `SF85_DUEL=1` 触发），`_spawn_test_damage()` 直接造伤害数字；这些都写在主场景脚本里，与正式流程共用同一个类。
建议：挪到 `tests/` 或 `game/dev/` 下，用 `if OS.has_feature("editor")` 或显式 flag 隔离。

### P2-6 测试无统一 runner
18 个脚本要一个个手动跑；`probe_*` 与 `test_*` 混在一起。
建议：`tools/run_tests.sh` + 约定 `test_*.gd` 返回退出码，`probe_*` 归入 `tools/probes/`。

---

## 13. 建议的接手分工（三块，可并行）

| 块 | 范围 | 先动的文件 | 风险 |
|---|---|---|---|
| **A. 玩法与战斗** | `game/sf85/*`（除 hud_bottom）、`pass_grid`、伤害链 | `room.gd`（拆）、`player.gd`、`monster.gd`、`actor_sprite.gd` | 高：动 room 会同时影响 HUD/UI/输入 |
| **B. UI 框架与窗口** | `ui/**` | `ui_root.gd`、`inventory_window.gd`（853 行拆分）、`item_db.gd` | 中：玻璃渲染顺序、主题预设 |
| **C. 数据与资源** | `utils/**`、`asset_lib.gd`、`pvf_lib.gd`、`ItemDB→真数据` | `asset_lib.gd`、`pvf_lib.gd`、新增 `EquipmentRepository` | 中：PVF 读取性能、缓存策略 |

**第一步建议（按收益/风险比排序）**
1. 删死代码（§12 P1-5）——半天，零风险，立刻让 `grep` 好用。
2. 接日志（§12 P1-4）——半天，之后所有重构都有诊断。
3. 抽 `InputRouter`（P0-4）——1–2 天，玩家/UI 都受益，且能顺手修"UI 打开还能动"。
4. 抽 `CombatResolver`（P0-2）——2–3 天，需要先写 `DamageTable`。
5. 拆 `room.gd`（P0-1）——3–5 天，前面 3 步做完再动。

---

## 14. 怎么跑、怎么验

```bash
# 跑游戏（WSLg 窗口）
cd /home/sunmingze/dnf_like && DISPLAY=:0 ./tools/godot.sh

# 无头冒烟（应 0 个 SCRIPT ERROR；sqr_gd 的解析错误是既存噪音）
GODOT_PROJECT=$PWD/client ./tools/godot.sh --headless --quit-after 90

# 键位 / 手柄自测
./tools/godot.sh --headless --script res://tests/test_dnf_keys.gd   # 25 项
./tools/godot.sh --headless --script res://tests/test_gamepad.gd    # 50 项

# 截图（也会跑一遍完整启动链）
SF85_UI_SHOT=/tmp/s.png SF85_UI_SHOT_FRAMES=200 DISPLAY=:0 ./tools/godot.sh --quit-after 260
```

**注意**：新增 `class_name` 后必须先用 `--headless --editor --quit` 扫一遍（写 `.godot/global_script_class_cache.cfg`），否则 runtime 报"找不到类型"。

**代码量口径**：全工程 `.gd` 271 个 = 活跃 75 个（非遗留，约 12,000 行）+ `sqr_gd/` 遗留 196 个。

---

## 附录 A：全量文件职责表（非遗留）

| 文件 | 行 | 类型 | 一句话 |
|---|---|---|---|
| `core/app_env.gd` | 299 | Node / autoload `Env` | 平台/版本/路径环境探测 |
| `core/log/log.gd` | 172 | Node / autoload `Log` | 日志门面（**当前 0 调用**） |
| `core/log/log_core.gd` | 526 | RefCounted `LogCore` | 日志核心（分级/缓冲/输出） |
| `core/log/log_tag.gd` | 48 | RefCounted `LogTag` | tag 定义 |
| `core/input/dnf_keys.gd` | 333 | RefCounted `DnfKeys` | 123 个 DNF 动作 + 51 个临时默认键 + 存读 `user://keybindings.cfg` |
| `core/input/gamepad_keys.gd` | 446 | RefCounted `GamepadKeys` | 手柄双预设（design/dnf）× 双模式（2.5D/俯视）+ 描述表 |
| `game/sf85/room.gd` | 513 | Node2D（无 class_name） | **主入口**，编排一切 |
| `game/sf85/player.gd` | 295 | `Sf85Player : Sf85Actor` | 玩家状态机/连击/技能/受击 |
| `game/sf85/monster.gd` | 157 | `Sf85Monster : Sf85Actor` | 怪物 AI（追/打/死） |
| `game/sf85/actor_sprite.gd` | 178 | `Sf85Actor : Node2D` | 精灵+动画+判定框（被继承，实际是表现层） |
| `game/sf85/asset_lib.gd` | 203 | `Sf85Assets` | 资产门面（PVF+NPK）与路径常量 |
| `game/sf85/pvf_lib.gd` | 512 | `Sf85Pvf` | PVF→玩家/怪物/房间/技能装配 |
| `game/sf85/hud.gd` | 185 | `Sf85Hud : Control` | 左上状态条（HP/MP/提示/伤害数字入口） |
| `game/sf85/hud_bottom.gd` | 489 | `Sf85HudBottom : Control` | 底部条（12 技能格/6 消耗品格/双球/5 按钮），键盘与手柄两套版式 |
| `game/sf85/damage_number.gd` | 52 | `Sf85DamageNumber` | 飘字 |
| `ui/ingame_ui.gd` | 69 | `IngameUI : CanvasLayer` | UI 宿主 + 截图钩子 |
| `ui/core/ui_root.gd` | 375 | `UIRoot : Control` | 窗口管理器/主题/快捷键/遮罩 |
| `ui/core/ui_window.gd` | 211 | `UIWindow : Control` | 窗口基类 |
| `ui/core/ui_panel.gd` | 97 | `UIPanel` | 面板 |
| `ui/core/ui_title_bar.gd` | 112 | `UITitleBar` | 标题栏 |
| `ui/core/ui_button.gd` | 28 | `UIButton : Button` | 按钮 |
| `ui/core/ui_tab_bar.gd` | 154 | `UITabBar` | 页签 |
| `ui/core/ui_slot.gd` | 287 | `UISlot` | 物品格 |
| `ui/core/ui_kit.gd` | 181 | `UIKit` | 静态绘制/主题工具 |
| `ui/core/ui_tooltip.gd` | 233 | `UITooltip` | 物品提示 |
| `ui/core/ui_tooltip_layer.gd` | 75 | `UITooltipLayer` | 提示层 |
| `ui/core/ui_weight_bar.gd` | 83 | `UIWeightBar` | 负重 |
| `ui/core/ui_currency_bar.gd` | 83 | `UICurrencyBar` | 货币 |
| `ui/core/ui_item_grid.gd` | 165 | `UIItemGrid : ScrollContainer` | 格子网格 |
| `ui/core/ui_character_preview.gd` | 200 | `UICharacterPreview` | 角色预览 |
| `ui/core/ui_bag_summary.gd` | 107 | `UIBagSummary` | 背包摘要 |
| `ui/data/item_db.gd` | 603 | `ItemDB` | **假数据**物品仓库 |
| `ui/data/item_def.gd` | 82 | `ItemDef : Resource` | 物品数据类 |
| `ui/windows/inventory_window.gd` | 853 | `InventoryWindow : UIWindow` | 背包（最大文件） |
| `ui/windows/warehouse_window.gd` | 209 | `WarehouseWindow : UIWindow` | 金库 |
| `ui/windows/keybind_window.gd` | 297 | `KeybindWindow : UIWindow` | 键盘/手柄设置 |
| `ui/debug/ui_debug_console.gd` | 328 | `UIDebugConsole : UIWindow` | F1 控制台 |
| `ui/theme/ui_theme.gd` | 275 | `UITheme : Resource` | 主题数据 |
| `ui/theme/ui_theme_presets.gd` | 148 | `UIThemePresets` | 4 套预设 |
| `utils/PVFLoader.gd` | 174 | `PvfLoader` | PVF 门面（archive+document+animation） |
| `utils/pvfloader/pvf_archive.gd` | 388 | `PvfArchive` | 容器/目录树/解压 |
| `utils/pvfloader/pvf_document.gd` | 141 | `PvfDocument` | tag 流读取 |
| `utils/pvfloader/pvf_types.gd` | 208 | `PvfTypes` | 类型/标签常量 |
| `utils/pvfloader/pvf_animation.gd` | 304 | `PvfAnimation` | ani → 帧 |
| `utils/npk/npk_image.gd` | 519 | `NpkImage` | IMG 解析与贴图解码 |
| `utils/npk/npk_index.gd` | 122 | `NpkIndex` | NPK 索引缓存 |
| `utils/npk/npk_store.gd` | 183 | `NpkStore` | 多 NPK 管理与缓存 |
