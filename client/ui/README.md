# res://ui —— DNF 风格 UI 组件库

一套用 Godot 原生 `Control` + `_draw` 画的 DNF 风格界面，不依赖 DNF 客户端里的 UI 贴图。
目前包含：**装备栏/物品栏**、**泰拉石金库**、**鼠标跟随物品浮框**、**游戏内 HP/MP HUD**、**漂浮伤害数字**、**可扩展的 UI 调试控制台**，以及可复用的面板、标题栏、按钮、页签、格子、权重条、货币条、角色纸娃娃预览。

### 本轮布局（2026-11-14）

- 物品栏：440×760 逻辑尺寸，8×6 格（48 格，不滚动、全量展示）；格子 42px、间距 3px；去掉「全部」页签，按装备/消耗品/材料/副职业/任务分类，五个页签均分整条宽度；负重按整个背包计算，切页签不改变。
- 底部：缩短的重量条 + `排序`（展开规则：稀有度/等级/部位/获取时间/名称）+ `锁`（整页锁定；Ctrl+左键单格锁定）+ `整理`；锁定后整理/排序不生效，单格锁定的物品排序时留在原位。
- 左侧 8 格：称号/头/肩/上衣/下装/腰带/鞋子/护腕；右上方 2×2 武器（主手/副手/备用 1/备用 2），右下方 2×2 饰品（项链/耳饰/双戒指）。
- 四个武器槽是通用槽，不预留箭袋：弓箭手副手放箭袋、圣骑士放盾、法师放球；野蛮人等四武器职业解锁备用槽。按职业自动启用/禁用，禁用位压暗并画斜线，不再有手动切换按钮。
- 装备栏与物品分类之间新增一排工具条（`Ctrl+左键 锁定` 提示 + `详情`），页签不再挤占头部；五个分类页签均分整条宽度。
- 详情抽屉从物品栏左侧独立展开，不占物品栏位置；顶部 `属性 / 材料` 切换，材料一行一个（小图标 / 名称 / 数量），独立计数、不占物品格、不参与负重。
- 稀有度动效：**只对已装备的槽位生效**，5 阶起槽位边缘环绕星芒，6 阶（传说）再加 HSV 多色渐变描边；已去掉外圈呼吸光，只保留边缘闪光。无需额外美术资源，`UISlot._draw_rarity_fx()` 按 `equipped && ItemDef.rarity >= 5` 触发。
- 金库：14×6 格，无重量限制；顶部按类型过滤，保留「全部」。
- 项目初始窗口改为 1600×1000，最小 1280×900；UI 默认缩放 0.9，仍按物理像素绘制；世界由相机缩放，UI 由 `UIRoot.set_ui_scale()` 单独缩放。

---

## 1. 先看效果

在项目根目录直接跑演示场景：

```bash
# Windows
godot --path . res://ui/ui_demo.tscn

# WSL（本机调试命令，按自己的 Godot 路径改）
DISPLAY=:0 /path/to/godot --path . --rendering-driver opengl3 res://ui/ui_demo.tscn
```

演示场景不加载主场景，所以不用等 200MB 的 PVF；它只读 `assets/npk-index.bin` 和真实 `Script.pvf`，用来拿物品图标和角色纸娃娃。

演示快捷键：

| 键 | 作用 |
|---|---|
| `I` | 开关装备栏 |
| `K` | 开关金库 |
| `F3` | 轮换配色（abyss → ember → jade → violet） |
| `Esc` | 关闭最上层窗口 |
| 拖动标题栏 | 移动窗口 |

调试用环境变量：

```bash
UI_PRESET=ember        # 启动配色
UI_DEMO=warehouse      # inventory | warehouse | both
UI_TOOLTIP=1           # 固定显示一个示例浮框，方便截图
UI_DRAWER=attrs        # attrs | materials：打开物品栏左侧抽屉
UI_WINDOW=1600x1000    # 演示前把窗口切成指定尺寸
UI_SHOT=/tmp/ui.png    # 等 24 帧后截图并退出
```

---

## 2. 目录

```
ui/
├── theme/
│   ├── ui_theme.gd           # UITheme：所有可调参数都在这里
│   └── ui_theme_presets.gd   # abyss / ember / jade / violet 四套预设
├── core/
│   ├── ui_kit.gd             # 静态绘制/取色工具
│   ├── ui_panel.gd           # 磨砂玻璃面板（shader）
│   ├── ui_window.gd          # 可拖动窗口外壳
│   ├── ui_title_bar.gd       # 标题栏
│   ├── ui_button.gd          # normal / accent / ghost 按钮
│   ├── ui_tab_bar.gd         # 页签
│   ├── ui_slot.gd            # 单个物品格
│   ├── ui_item_grid.gd       # 固定列数物品网格
│   ├── ui_tooltip.gd         # 物品浮框本体
│   ├── ui_tooltip_layer.gd   # 浮框层（跟随鼠标/边缘翻转）
│   ├── ui_weight_bar.gd      # 重量条
│   ├── ui_currency_bar.gd    # 底部货币条
│   ├── ui_bag_summary.gd     # 旧版背包概览（本轮已从物品栏移除，保留组件）
│   ├── ui_character_preview.gd # 纸娃娃预览
│   └── ui_root.gd            # UI 根节点：主题/层/快捷键/UI 缩放
├── debug/
│   ├── ui_debug_slider.gd    # 调试滑条
│   ├── ui_debug_toggle.gd    # 调试开关
│   ├── ui_debug_option.gd    # 调试选项（点击轮换）
│   └── ui_debug_console.gd   # UI 调试控制台
├── windows/
│   ├── inventory_window.gd   # 装备栏 + 物品栏
│   └── warehouse_window.gd   # 金库
├── data/
│   ├── item_def.gd           # 单件物品数据
│   └── item_db.gd            # mock 数据 + 槽位/页签常量
├── shaders/frosted_glass.gdshader
├── themes/                   # 预留：可放 .tres 主题
├── ingame_ui.gd              # 游戏内挂载点（CanvasLayer + UIRoot）
├── ui_demo.gd / ui_demo.tscn # 独立演示场景
└── README.md
```

---

## 3. 主题参数（`UITheme`）

改配色不需要动任何控件：新建/复制一个 `UITheme` 资源，改字段，赋给 `UIRoot.theme_data` 即可。
所有字段都带 `@export`，可以在 Inspector 里实时调。

### 3.1 主色

| 字段 | 默认（abyss） | 说明 |
|---|---|---|
| `accent` | 青蓝 | 主强调色：页签下划线、按钮、进度条、选中态 |
| `accent_soft` | 浅青 | 次级强调/点券 |
| `accent_deep` | 深蓝 | 阴影/渐变的深色端 |
| `gold` | 金 | 标题装饰线、金币、选中描边 |
| `gold_soft` | 淡金 | 金色高光 |

### 3.2 玻璃与透明度

| 字段 | 默认 | 说明 |
|---|---|---|
| `preset_key` | `abyss` | 预设键：`abyss` / `ember` / `jade` / `violet`；自定义主题可留空 |
| `glass_tint` | 深蓝 | 玻璃染色 |
| `glass_alpha` | `0.78` | **整体不透明度**，越小越透 |
| `glass_blur` | `6.5` | 背景模糊半径（像素） |
| `glass_noise` | `0.028` | 磨砂颗粒 |
| `glass_brightness` | `0.92` | 背景亮度 |
| `glass_saturation` | `0.82` | 背景饱和度 |
| `glass_vignette` | `0.30` | 四周压暗 |
| `frame_color` | 蓝灰 | 面板描边 |
| `frame_highlight` | 亮蓝 | 顶部高光描边 |
| `shadow_color` | 黑 | 窗口投影 |
| `shadow_size` | `18` | 投影大小 |
| `corner_radius` | `10` | 圆角 |
| `border_width` | `1` | 描边宽度 |

> 磨砂是屏幕空间效果：`UIRoot` 里有一个 `BackBufferCopy`，面板 shader 采样 `hint_screen_texture`。
> 窗口必须放在 `UIRoot` 之下，不要单独把 `UIPanel` 挂到没有 `BackBufferCopy` 的场景里。

### 3.3 标题栏 / 格子

| 字段 | 默认 | 说明 |
|---|---|---|
| `title_top` / `title_bottom` | 深蓝渐变 | 标题栏 |
| `title_text` | 近白 | 标题字 |
| `title_height` | `42` | 标题栏高度 |
| `slot_bg` / `slot_bg_alt` | 深蓝 | 格子底色 |
| `slot_border` | 蓝灰 | 格子边 |
| `slot_hover` | 青 | 悬停 |
| `slot_selected` | 金 | 选中 |
| `slot_size` | `46` | 格子边长 |
| `slot_gap` | `6` | 格子间距 |

### 3.4 文字

`text_primary`、`text_secondary`、`text_muted`、`text_gold`、`text_danger`、`text_success`；
`font_family`、`font_family_bold`、`font_size_base`、`font_scale`。
默认用 `SystemFont`，候选：Noto Sans CJK SC / Microsoft YaHei / WenQuanYi Zen Hei，WSL 下已验证中文正常。

### 3.5 品质色

`rarity_colors` 是 7 个 `Color`，顺序：普通 / 高级 / 稀有 / 勇者 / 神器 / 史诗 / 传说。
`UITheme.rarity_color(rarity)` 取色；浮框、格子描边、物品名都走它。

### 3.6 运行时换肤

```gdscript
ui.apply_theme_preset("ember")     # 四套预设之一
ui.cycle_theme()                   # F3 同款轮换
ui.apply_theme(my_theme_resource)  # 任意自定义 UITheme
```

`UITheme.copy_with({...})` 可以在预设基础上只改几个字段：

```gdscript
var t := UIThemePresets.get_theme("abyss")
t = t.copy_with({"glass_alpha": 0.55, "accent": Color("46d6ff"), "glass_blur": 12.0})
ui.apply_theme(t)
```

---

## 4. 常用组件

### UIRoot

挂在 `CanvasLayer` 下的全屏 `Control`。

```gdscript
var layer := CanvasLayer.new()
layer.layer = 10
add_child(layer)

var ui := UIRoot.new()
layer.add_child(ui)
ui.bind_assets(assets, assets.actor("player"))
```

主要成员：

- `inventory: InventoryWindow`、`warehouse: WarehouseWindow`
- `tooltip_layer: UITooltipLayer`
- `apply_theme(data)` / `apply_theme_preset(name)` / `cycle_theme()`
- `bind_assets(assets, player_actor)`：传 `Sf85Assets` 和 `assets.actor("player")` 后，角色预览和物品图标都能用
- `item_texture(item)`：按 `icon_img` + `icon_frame` 从 NPK 取 `Texture2D`
- `open_inventory()` / `open_warehouse()` / `toggle_*()` / `close_all()`
- `set_ui_scale(v)`：只缩放 UI（`content_root`），世界相机不受影响
- `set_window_size(Vector2i)`：切换游戏窗口尺寸；控制台「窗口尺寸」走这里
- `attach_debug(hud, room)` / `open_console()` / `toggle_debug_console()`：打开 UI 调试控制台

### UIWindow

```gdscript
class_name MyWindow
extends UIWindow

func _ready() -> void:
    window_title = "我的窗口"   # 必须在 super._ready() 之前
    super._ready()
    custom_minimum_size = Vector2(600, 400)
    content.add_child(my_control)
```

`content` 是 `VBoxContainer`；子类只往里塞内容。`setup(tooltip_layer)`、`wire_slot(slot)` 由 `UIRoot` 调好。

### UIItemGrid + UISlot

```gdscript
grid.set_items(items, 48)       # 48 格，不足补空格
grid.set_filter("equipment")    # "" = 全部
grid.filtered_items()
grid.get_slot(0)
```

信号：`slot_hovered(slot)`、`slot_unhovered(slot)`、`slot_activated(slot)`、`slot_right_clicked(slot)`。
`UISlot.item` 是 `ItemDef`；`UISlot.equipped` 控制左上角金色小菱形。

### UITooltipLayer

```gdscript
ui.tooltip_layer.show_item(item, slot.get_global_rect())
ui.tooltip_layer.hide_tooltip()
ui.tooltip_layer.show_item_at(item, Vector2(700, 150))  # 固定位置（手柄/截图）
```

浮框会跟随鼠标、贴右边自动翻到左边、贴底自动翻上去，并夹在屏幕内。

---

## 5. 接入真实场景（sf85_mirkwood）

推荐直接挂 `IngameUI`（它内部就是 `CanvasLayer(layer=10) + UIRoot`，默认不自动打开背包）：

```gdscript
# room.gd
var ui: IngameUI

func _ready() -> void:
    # ... 原来的 _spawn_monsters() / _spawn_player()
    ui = IngameUI.new()
    ui.name = "UI"
    add_child(ui)
    ui.bind(assets, player.def, hud, self)   # hud 为 Sf85Hud，self 用于世界缩放
```

如果不想改 `room.gd`，也可以在场景里加：

```
CanvasLayer (layer=10, script=res://ui/ingame_ui.gd)
```

然后从房间拿到它并调用 `bind(assets, player.def, hud, room)`。

手动创建 `UIRoot` 也可以：

```gdscript
var layer := CanvasLayer.new()
layer.layer = 10
add_child(layer)

var ui := UIRoot.new()
ui.open_inventory_on_start = false
layer.add_child(ui)
ui.bind_assets(assets, player.def)
```

> 注意：`UIRoot` 在 `_ready()` 里就创建窗口；`bind_assets()` 之后会补角色预览和物品图标。
> 真实项目第一次加 `class_name` 脚本后，跑一次
> `godot --headless --editor --quit --path <项目>` 让 `.godot/global_script_class_cache.cfg` 认识 `UIRoot`、`IngameUI` 等类。
> 如果只是临时进游戏看效果，可以设 `SF85_UI_DEMO=1`，房间会在启动时直接打开背包；设 `SF85_UI=0` 可以完全关掉 UI 层。

---

## 5.5 游戏内 HUD、伤害数字、分辨率与 UI 缩放

### HUD

`res://game/sf85/hud.gd`（`class_name Sf85Hud`）是固定在屏幕上的 `Control`，不挂在 `UIRoot` 下：

- 左上角：角色名、Lv、HP 红条、MP 蓝条、攻击力；
- 左上角面板右侧：FPS；
- 底部：操作提示；
- `spawn_damage(world_pos, amount, kind)` 生成漂浮伤害数字，`kind` 支持 `hit` / `skill` / `player` / `crit`；
- `setup(player, damage_layer, camera)` 由房间调用。

玩家受击：`Sf85Player.take_damage()` 会闪红、触发 0.45s 无敌，并发出 `damaged(amount, world_pos)`；怪物攻击动作结束时调用 `_try_hit_target()`。伤害数字挂在房间的 `DamageLayer(Node2D)` 下，用 `1 / camera.zoom` 抵消相机缩放，所以 720p 和 1080p 下字号一致。

### 分辨率 / 世界放大，UI 不跟

`project.godot` 里：

```ini
[display]
window/stretch/mode="disabled"
window/stretch/aspect="expand"
```

- 窗口变大时，世界由相机 `_update_camera_zoom()` 放大（`BASE_ZOOM=1.4`，按 1152×648 基准计算）；
- HUD 和 `UIRoot` 是独立 `CanvasLayer`，始终按物理像素绘制，不会被拉大；
- UI 自己由 `UIRoot.set_ui_scale(v)` 控制，控制台里可 0.7–1.4 实时调。

> 注意：这条是项目级设置。接入真实项目时要同步 `project.godot`；如果仍用 `canvas_items`，窗口放大时 UI 会跟着一起变大。

### 调试控制台

按 `F1`（或在 `room.gd` 里设 `SF85_UI_CONSOLE=1`）打开。控制台本身不跟 `ui_scale` 缩放，所以调大 UI 时它不会把自己撑出屏幕。

当前分区：

- **主题**：预设、主色、金色、玻璃不透明度、磨砂半径、噪点、圆角、字号缩放；
- **界面/分辨率**：UI 缩放、窗口尺寸（1280×900 / 1600×900 / 1600×1000 / 1920×1080）、全屏/窗口、世界缩放；
- **HUD/伤害数字**：HUD 缩放、显示 HUD、显示伤害数字、数字字号、上浮高度、持续时间、测试伤害数字；
- **操作**：重置全部、关闭控制台（固定在底部，不随滚动消失）。

扩展方式：在 `ui/debug/ui_debug_console.gd` 的 `_build()` 里加一行 `_slider(...)` / `_toggle(...)` / `_option(...)` / `_color(...)` 即可；需要新行类型时照 `UIDebugSlider` 的写法加一个 `Control` 子类。控制台只依赖 `UIRoot` / `Sf85Hud` / `room` 的公开方法，不会反过来改窗口内部状态。

### 相关环境变量

```bash
SF85_UI=0                 # 完全关掉 UI 层
SF85_UI_DEMO=1            # 启动时打开背包
SF85_UI_CONSOLE=1         # 启动时打开控制台
SF85_UI_SCALE=1.1         # 启动时设置 UI 缩放
SF85_HUD_SCALE=1.2        # 启动时设置 HUD 缩放（0.75–1.6）
SF85_UI_SHOT=/tmp/a.png   # 等若干帧后截图并退出
SF85_UI_SHOT_FRAMES=150   # 截图前等待帧数（默认 30）
SF85_DAMAGE_TEST=1        # 在玩家头上生成示例伤害数字
SF85_DEMO=1               # 自动驾驶（走/跳/攻击）
SF85_DUEL=1               # 把玩家挪到第一只怪面前，怪物会主动攻击
```

### 主场景截图

```bash
DISPLAY=:0 godot --path . --rendering-driver opengl3   --resolution 1280x720 res://scenes/sf85_mirkwood.tscn
```

主场景要读 200MB PVF，第一次加载约 1–2 分钟；UI 迭代优先用 `ui_demo.tscn`。

---

## 6. 数据替换（现在是 mock）

`ItemDef` 字段：

```
item_id, item_name, category, slot, item_type, rarity, level, required_job,
icon_img, icon_frame, count, max_stack, weight, value, durability, durability_max,
stats[{label,value,tone}], tags, description, effect, bind_state
```

`ItemDB.inventory_items()` / `warehouse_items()` 现在返回固定数组；以后接真实表时，只要返回 `Array[ItemDef]` 即可，窗口不用改。

图标：`icon_img` 用 NPK 里的图集路径，`icon_frame` 是帧号。当前 mock 用的是：

```
sprite/item/iconweapon.img    132 帧
sprite/item/iconarmor.img     332 帧
sprite/item/iconacc.img        95 帧
sprite/item/iconstackable.img  26 帧
sprite/item/iconmaterial.img   44 帧
sprite/item/iconavatar.img     21 帧
```

所有帧都是 28×28。真实物品表里的 `item/0001tututuitem.img` 在 sf85 包里不存在，别直接拿来当图标路径。

---

## 7. 已知限制 / 下一步

- 数据是 mock；`ItemDB` 只用于演示配色和布局。
- 顶部 `时装 / 宠物` 页签能切，但没有对应 mock 数据，所以是空列表。
- `金库` 的 `转移物品 / 放入` 只改状态文字；真正的背包↔金库逻辑等真实数据/服务层。
- 角色预览依赖 `Sf85Assets`；没传资产时会画剪影并显示「未载入角色资产」。
- 磨砂依赖 `BackBufferCopy`，在 GL Compatibility / OpenGL3 下已验证；Forward+ 下同样可用。
- 物品栏窗口当前 `440×760`；默认缩放 0.9，在 1600×1000 下完整放下；8×6 格全部可见，底部两行货币不再被框截断。
- 每次运行会打印几条 `Unicode parsing error ... Unexpected NUL character`，来自 PVF/字体字符串解码，暂未定位；不影响 UI 绘制，后续查 PVF 读取时一起处理。
- 自测：`godot --headless --path . --script res://tests/test_ui.gd`（56 项检查，当前全绿）。
- 控制台里的 `UI 缩放` 默认 0.9；窗口最小 1280×900，UI 缩放上限 1.4，过低会裁切详情抽屉。
- `SF85_UI_SCALE`、`SF85_DAMAGE_TEST` 主要用于截图/自测，正式流程走控制台。

---

## 8. 为什么用 Godot 原生 UI，而不是 DNF 原图

- DNF 的 UI 是 2008 年的固定像素图，缩放会糊；Godot 的 `Control` + `_draw` 可以矢量式适配任意分辨率。
- 磨砂、透明度、配色、圆角都能用参数统一改，换肤只换一个 `Resource`。
- 文字用系统字体，中文/数值排版比原图更清晰，也方便后续做物品详情、搜索、排序。
- 物品图标仍然用客户端 NPK 里的原图，保留 DNF 的视觉记忆。

---

## 9. 底部主 HUD + 键盘设置窗口（2026-11-15）

- **`game/sf85/hud_bottom.gd`（`Sf85HudBottom`）**：DNF 式底部条，宽 860 / 高 118 / 贴底 6px。
  左 2×3 消耗品格（`1`–`6`）、中 6×2 技能栏（上排 `A S D F G H`、下排 `Q W E R T Y`）、
  技能栏两侧圆形 HP / MP 球、右侧功能按钮（背包 / 键位 / 地图 · 商城 / 菜单）。
  键帽文字全部来自 `DnfKeys.key_label()`，改键后立即刷新；冷却时压暗并显示剩余秒数。
- **`ui/windows/keybind_window.gd`（`KeybindWindow`）**：`F9` 打开，四个页签
  「系统 / 角色 / 技能 / 聊天快捷键」，动作清单来自客户端数据（123 条），
  点键帽录制新键、`Esc` 取消、`Delete` 清空，冲突自动解除旧绑定，改完自动存 `user://keybindings.cfg`。
- **`core/input/dnf_keys.gd`（`DnfKeys`）**：全部键盘输入的唯一入口。语义动作
  `move_* / attack / jump / skill / skill2` 映射到 DNF 动作 id（I01–I08），
  `room.gd` / `player.gd` 只认语义名，键位改动不需要动玩法代码。
- 数据表 `data/dnf_hotkeys.json` 由 `tools/extract_dnf_hotkeys.py` 从
  `Script.pvf:clientonly/hotkeysystem_ver3.co` 导出，可重复生成。
- 自测：`godot --headless --path . --script res://tests/test_dnf_keys.gd`（25 项，当前全绿）。
- 完整说明（版式、默认绑定表、已知缺口）见 `docs/KEYBINDS-HUD-34.md`。

---

## 10. 手柄布局（2026-11-15）

- **`core/input/gamepad_keys.gd`（`GamepadKeys`）**：手柄唯一入口，与键盘共用技能槽/药水槽编号。
  两套预设（`PRESET_DESIGN` 设计稿 / `PRESET_DNF` 客户端原生）× 两种模式（`MODE_2_5D` / `MODE_TOPDOWN`）。
- 2.5D：`Ⓐ Ⓑ Ⓧ Ⓨ` = 技能 1–4，`LB + 面键` = 5–8，`LT + 面键` = 9–12（默认关），`RT` 普攻、`RB` 闪避，
  `▲▼` 药水、`◀▶` 切目标。
- 俯视 45°：技能 5–8 改到十字键直按，药水/目标退到 `LB + 十字键`，其余相同。
- 左摇杆直接挂到 `move_*` 语义动作（玩家逻辑不用改），右摇杆暴露 `look` 向量留给瞄准/选目标。
- 接上手柄后 HUD 自动换手柄字形、技能栏从 6×2 变 4×2；设置窗口第五页「手柄」可切预设/模式/第三排。
- 自测：`godot --headless --path . --script res://tests/test_gamepad.gd`（50 项，当前全绿）。
- 完整说明见 `docs/GAMEPAD-BINDINGS-34.md`，客户端原生映射的取证见
  `docs/research/2026-11-15-dnf-gamepad-defaults.md`。
