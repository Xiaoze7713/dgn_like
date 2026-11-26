# Godot 4 可行性评估（DNF-like 单机 2D 横版动作游戏）

> 评估对象：用 **Godot 4 当前稳定版** 承接本项目的「数据驱动 + 2D 横版动作 + 复用 NPK 原图」。
> 评估时间：2026-10-26。文档中所有版本号、API 名、平台限制均来自官方文档/官方仓库，实测数据来自本机真跑（见 §2）。
> 对应路线图：`docs/ROADMAP.md` 的 **P2.1 端形态与引擎决策**、P2.2/P2.3/P2.4。

---

## 0. 结论先行

**结论：有条件推荐（Recommended with conditions）。**

Godot 4 能把这个项目做出来，而且是当前选项里最省事的一个：2D 横版所需的帧动画、判定盒、房间切换、粒子、复杂 Control UI 全部是引擎一等公民；导出 Win/Linux 一条命令；引擎 MIT、无版税；与本项目「先单机、后留联机接口、素材先复用原图」的取向一致。

但**三个前提条件必须先接受**，否则会在第 2 个月撞墙：

| # | 前提条件 | 为什么是硬条件 |
|---|---|---|
| C1 | **不要把 100 万帧动画当「资源」导入编辑器**，而是自建运行时管线：NPK 解码 →（离线）按 `.img` 打包图集 →（运行时）数据驱动 `Sprite2D.region_rect` | 实测：2,000 张 64×64 PNG 导入 2.9s，5,000 张 32s，20,000 张超过 5 分钟未跑完（严重超线性）。1,058,561 个 `.ani` / 百万级帧按「一帧一文件」导入不可行 |
| C2 | **数据层不走「一文件一 JSON」**，P0.8 直接产出分域二进制/紧凑格式 + 索引，启动按需加载 | 实测：单个 68MB JSON 解析 1,029ms、峰值静态内存 +788MB；10 万个小 JSON 逐个读+解析 ≈1.9s。全量 10.2 万装备 + 3,549 怪 + 4,592 地图不该在启动时全量进内存 |
| C3 | **Web 不作为主目标**（首发 Windows + Linux；Web 只当 demo/试玩） | Web 导出仅 WebGL 2.0 / Compatibility 渲染器、默认单线程、不支持 C#；WASM 内存上限 2GB 的问题在 iOS Safari 上仍未关闭（[#70621](https://github.com/godotengine/godot/issues/70621)，2022 至今 open） |

如果 C1–C3 可以接受（对本项目来说**本来就是这么设计的**），则 Godot 4 是首选；否则见 §11 的次选方案。

**版本口径**：本文所有结论基于 **Godot 4.7.2-stable（2026-08-18 发布）**——当前最新稳定版（[官方发布记录](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)、[维护版本公告](https://godotengine.org/article/maintenance-release-godot-4-7-2/)）。4.8 处于 beta 1 特性冻结（[2026-10-15](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/)），**不用于本项目**。3.6.3（2026-08-22）是 3.x LTS 维护版，仅作对照。

---

## 1. 评估口径

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7.2-stable.official.ed1daf0bf（Linux x86_64，官方二进制，140MB） |
| 运行方式 | `--headless`（无 GPU 渲染），`gl_compatibility` 项目 |
| 机器 | 16 核 / 31GB RAM / Linux |
| 实测覆盖 | 数据解析、二进制序列化、小文件遍历、纹理解码与实例化、节点实例化、TileMapLayer 写入、PNG 导入 |
| **未覆盖** | **GPU 渲染相关指标**（draw call、填充率、粒子上限）——headless 无渲染，这部分只能引官方文档 + 经验预算，§7 中标注为「预算」而非「实测」 |

> 说明：`OS.get_static_memory_usage()` 只统计引擎静态内存（不含 GPU 显存、不含 OS 层缓存）；所有「内存」数字都是这个口径的差值。

---

## 2. 实测数据（Godot 4.7.2，本机真跑）

测试脚本思路（可复现，脚本本身未入库，因本任务只允许写本文件）：

```gdscript
# bench.gd —— godot --headless --path . --script res://bench.gd
extends SceneTree
func _initialize() -> void:
    var t := Time.get_ticks_usec()
    var txt := FileAccess.get_file_as_string("res://data/equip_all.json")   # 68.0MB / 102,330 条
    print("read_ms=", (Time.get_ticks_usec()-t)/1000.0)
    t = Time.get_ticks_usec()
    var arr = JSON.parse_string(txt)
    print("parse_ms=", (Time.get_ticks_usec()-t)/1000.0, " mem_mb=", OS.get_static_memory_usage()/1048576.0)
    var bin := var_to_bytes(arr)          # 对比：Godot 原生 Variant 二进制
    ...
```

### 2.1 数据加载

| 场景 | 实测 | 外推 / 备注 |
|---|---|---|
| 68.0MB JSON（102,330 条装备记录，字段贴近 `.equ`）解析 | **1,029 ms**，解析后静态内存 **+788 MB** | JSON→Variant 的内存放大 ≈ **11×** 文件体积 |
| 同数据再 `JSON.stringify` | 1,288 ms，输出 56.7MB | 只用于离线导出，不要放运行时 |
| 同数据 `var_to_bytes`（Godot 原生二进制） | 序列化 555 ms，产物 **92.5 MB**；`bytes_to_var` 反序列化 **405 ms**（读取仅 10 ms） | **比 JSON 快 2.5×**，但产物比压缩过的 JSON 大 —— 需要自建紧凑格式或 gzip |
| 10 万个小 JSON 文件（每文件 ~661B） | 20,000 个 **376 ms**（0.019 ms/个） | 10 万 ≈ **1.9 s**（热缓存）；冷盘更慢 |
| 小型注册表（skill 4,005 / monster 3,549 / map 4,592 / dungeon 591 条） | 单表 40–304 KB | 这类表**全量常驻内存毫无压力** |

### 2.2 纹理 / 动画 / 场景

| 场景 | 实测 | 含义 |
|---|---|---|
| PNG 读盘 + 解码 + `ImageTexture`（64×64），2,000 张 | **62.3 ms**（0.031 ms/张），静态内存 +58 MB | 运行时解码管线完全够快：1,000 帧 ≈ 31 ms |
| 其中：只读盘 / 只解码 | 12.1 ms（0.006）/ 47.7 ms（0.024） | 瓶颈在解码，可多线程（`WorkerThreadPool` 存在） |
| 加载已导入的 `.ctex` | 0.046 ms/张（500 张 23.1 ms） | 走资源系统更快，但前提是「已导入」 |
| 2,000 个 `AnimatedSprite2D`（共享同一 `SpriteFrames`，3 动画 × 100 帧）实例化 | **3.3 ms**，内存 +5.0 MB | **实例化不贵**，贵的是「把每一帧都变成资源/纹理」 |
| 2,000 个精灵每帧改 `frame` / `position` | 0.15 ms / 0.14 ms 每帧 | 脚本侧每帧开销可忽略（瓶颈在渲染，见 §7） |
| `TileMapLayer.set_cell` 20,000 格 | 2.2 ms | 地图规模不是问题 |
| 2,000 张 64×64 PNG 导入（`--import`） | 冷 2.94 s / 热缓存 2.11 s，`.godot` 17 MB | ≈1.0–1.5 ms/张 |
| 5,000 张同上 | 冷 **32.2 s** / 热 2.11 s，41 MB | **超线性**：2.5 倍文件量 → 11 倍时间 |
| 20,000 张同上 | **>5 分钟未完成**（被手动终止，内存 800 MB+） | 每张约 15ms+，且不再随规模线性 |
| 把 10 万个 JSON 小文件塞进 `res://` | 项目 `--import` 启动时间 2.9 s → **13.7 s** | 文件系统扫描成本；**数据目录不要放进 `res://`** |

**结论**：Godot 的运行时开销（解码、实例化、脚本更新、TileMap）都不是瓶颈；**唯一会爆炸的是「工程里有几十万个文件 / 几百万个资源」**。而 DNF 的数据形态恰好就是「几十万个文件」——所以管线设计（C1/C2）比引擎选型更决定成败。

---

## 3. 2D 能力逐项核对

### 3.1 帧动画：引擎原生够用，但**不要**按 DNF 的规模用

- 引擎提供 `SpriteFrames` + `AnimatedSprite2D`（一帧一个 `Texture2D` 引用）与 `Sprite2D` + `AnimationPlayer`（`hframes`/`vframes` 切图集）两套方案（[2D sprite animation](https://docs.godotengine.org/en/4.7/tutorials/2d/2d_sprite_animation.html)）。
- 实测 2,000 个 `AnimatedSprite2D` 只花 3.3 ms，说明**节点本身便宜**；真正的成本是「每个动画都变成一份 `SpriteFrames` 资源 + 每帧一份纹理」。全库 1,058,561 个 `.ani`，若每个 `.ani` 一个 `SpriteFrames`，光资源对象就是百万级。
- **建议**：自写 `DnfAnimator`（约 200 行）：
  - 数据来自 P0.5 解码出的帧表（图集名、帧矩形、偏移、时长、事件）；
  - 节点用 `Sprite2D`（`region_enabled = true`，实测属性存在）+ 直接换 `region_rect`，纹理指向图集；
  - 状态机由 `.act`/`.als`/`.skl` 驱动，不由编辑器里的动画资源驱动。
  
  这就是 DNF 原本的结构，Godot 只是提供渲染与时间步。

### 3.2 事件帧（攻击盒、音效、位移、无敌帧）

Godot 原生的「事件帧」是 `AnimationPlayer` 的 **Call Method Track**（[track types](https://docs.godotengine.org/en/4.7/tutorials/animation/animation_track_types.html)）：在时间轴指定时刻调用一个方法，可带参数；注意官方说明「编辑器里预览动画时事件不会执行」（安全考虑）。

- 对 DNF 这种「每帧都可能有事件」的动画，**Call Method Track 不是最合适的载体**：它绑在 `Animation` 资源上，而我们的动画来自二进制 ANI。
- **建议**：帧事件直接写在 ANI 帧表里，`DnfAnimator` 在切帧时同步派发（`frame_changed(frame)` → 查该帧的事件列表）。好处：数据与引擎解耦、可回放、可批量校验，也天然适配将来联机的确定性重放。

### 3.3 判定盒（攻击盒 / 受击盒）

- 引擎选项：`Area2D` + `CollisionShape2D`（物理引擎参与）、或纯手算 `Rect2`/`ConvexPolygonShape2D` 相交。
- **建议不用 `Area2D` 做逐帧攻击盒**，理由：
  1. 攻击盒是「帧内瞬时存在」的判定，`Area2D` 的 `monitoring` 开关会牵动物理服务器，且判定结果受物理 tick 影响，回放/联机难复现；
  2. DNF 的判定本质是「矩形/多边形列表 × 目标受击盒」的朴素相交，自己算更快也更可控；
  3. 官方也提示物理对象多时物理会成为瓶颈（[CPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html)）。
- 物理只保留：地形碰撞（`CharacterBody2D` + `CollisionShape2D`）、可破坏物、掉落物拾取半径。
- 4.7 新增 `CollisionShape2D.one_way_collision_direction`，横版单向平台不用再改形状（[4.7 发布说明](https://godotengine.org/releases/4.7/)）。

### 3.4 房间地图（TileMapLayer / 非 tile 地图）

- `TileMap` 已废弃，官方要求改用多个 `TileMapLayer`（[类文档明确 deprecated](https://docs.godotengine.org/en/4.7/classes/class_tilemap.html)、[using tilemaps](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html)）。实测 20,000 格写入 2.2 ms，性能没问题。
- **但 DNF 的地图不是 tile 地图**：`.map` 是「背景图 + 前/后景层 + 物件 + 门/传送 + 出生点」，房间是整块背景图。
- **建议**：房间 = `Node2D` 场景，包含
  - 背景 `Sprite2D`（大图，必要时按房间切块 + `Parallax2D`）；
  - 手工摆放的碰撞 `CollisionPolygon2D`；
  - 门/传送点 `Area2D`；
  - `TileMapLayer` **只在真的需要网格化时**（例如可破坏地形、格状机关）使用。
  
  即「TileMapLayer 是可选工具，不是房间的地基」。

### 3.5 粒子

- `GPUParticles2D`（GPU，性能好）与 `CPUParticles2D`（CPU，可控性/可读性好）。
- 注意：**2D 物理插值目前只支持 `CPUParticles2D`**，`GPUParticles2D` 尚未插值（[2D and 3D physics interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html)）。如果逻辑跑 60Hz 而显示器 120/144Hz，粒子会看出抖动差异——需要在项目里统一策略（要么粒子也用 CPU 版，要么接受）。
- DNF 的特效大量是「序列帧 + 混合模式」，这与粒子是两条路：**序列帧特效走 `DnfAnimator` 同一个管线**即可（复用图集/帧表），粒子只用于火花、烟尘、拖尾。

### 3.6 Control UI（背包 / 技能树 / 城镇 NPC 窗口）

- `Control` + `Container`（`GridContainer`/`VBoxContainer`/`MarginContainer`/`ScrollContainer`）+ `Theme` + `StyleBoxTexture`（九宫格）足以复刻 DNF 的窗口外观；`NinePatchRect`、`TextureProgressBar`、`ItemList`、`Tree` 都有（已在 4.7.2 上逐一验证类存在）。
- 4.7 新增 `Control.offset_transform_*`（类似 CSS transform，容器重排不会吃掉子节点变换），做「技能树缩放/拖拽」「窗口弹入动画」方便很多（[4.7 发布说明](https://godotengine.org/releases/4.7/)）。
- **坑**：
  - 背包格子若「一个格子一个 `Control`」，2,000 格就是 2,000 个控件，布局/排序开销会显现。建议背包用 `GridContainer` + 每格一个轻量 `Control`（只画图标与数字）或干脆自绘（`_draw` / `ItemList` 单 CanvasItem）；列表类（拍卖、邮件）必须做虚拟化（只实例化可见行）。
  - 中文字体：DNF 原字体有版权风险，建议打包开源中文字体（如思源黑体 SIL OFL），或 `SystemFont` 回退；字体文件会进包体，注意子集化。
- 结论：UI 是**工作量问题，不是能力问题**。原版 `.ui`（378 个）能给出布局参数，但不能直接导入，需要一层「.ui → Godot 场景/Theme」的转换器或手工复刻。

### 3.7 遮挡排序

`Node2D.y_sort_enabled`（实测存在）按 Y 排序子节点，正好对应横版「脚底越靠下越靠前」。注意 `TileMapLayer` 有 `y_sort_enabled` 与「按 Y 分组 tile」的选项（[using tilemaps](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html)）。

---

## 4. 数据驱动

### 4.1 加载性能（见 §2.1 实测）

选型建议，按优先级：

1. **分域 + 分片**：装备/技能/怪物/地图/任务各自一份，且按 ID 区间或首字母分片（例如 `item_00.bin` … `item_ff.bin`），按需加载。DNF 的 10.2 万装备里，一个角色一次只会用到几百件。
2. **二进制 > JSON**：`var_to_bytes` 比 `JSON.parse_string` 快 2.5×（实测 405ms vs 1,029ms / 68MB）。但原生 `var_to_bytes` 产物偏大（92.5MB > 68MB 文本），生产环境建议：
   - 自建紧凑格式（字段字典 + 列式 `PackedInt32Array`/`PackedFloat32Array`），或
   - `var_to_bytes` 产物再走 `FileAccess.open_compressed()`（引擎自带 zstd/gzip）。
3. **JSON 只用于「人可读的中间产物」**（P0.8 的输出、调试用），不进最终包。
4. **64 位 ID 用字符串**：Godot 的 JSON 把数字一律按 `String.to_float` 解析为浮点（[JSON 类文档](https://docs.godotengine.org/en/4.7/classes/class_json.html)），超过 2^53 的整数会丢精度。DNF 的 hash/UID 类字段要注意。
5. **热重载**：引擎对「脚本/资源」有编辑器内热重载，但**对 JSON/二进制数据没有**。做法：开发期加一个 `F5 重载数据` 钩子（重新读文件 + `ResourceLoader.CACHE_MODE_IGNORE` 或自建缓存失效），成本几十行。

### 4.2 自定义资源格式

- `Resource` + `ResourceSaver`/`ResourceLoader` 可以做 `.tres`/`.res`（文本/二进制），支持 `@export`、`class_name`、编辑器内编辑（[resources 文档](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)）。
- 但**不适合放 10 万条记录**：每个 `Resource` 都是一个对象、都要走导入/缓存，实测导入成本随文件数超线性。**适合放「几十~几百条」的设计配置**（如职业定义、伤害类型表、UI 主题）。
- 结论：**大表用自定义二进制 + 索引；小表可以用 JSON 或 `Resource`**；两者都不要放进 `res://` 的海量小文件结构里。

---

## 5. 导出平台

| 平台 | 状态 | 关键限制 | 本项目判断 |
|---|---|---|---|
| **Windows** | 一等公民 | 无 | **首发目标** |
| **Linux** | 一等公民 | 无 | **首发目标**（开发机即 Linux，验证最方便） |
| **Web** | 可用但受限 | 仅 WebGL 2.0 / Compatibility 渲染器，**不支持 WebGPU**；**C# 项目不能导出 Web**；自 4.3 起默认单线程（多线程需 COOP/COEP 跨源隔离）；音频默认 Web Audio「Sample」模式，`AudioEffect`/混响/多普勒/程序化音频不支持；标签页失焦即暂停；WASM 内存上限 2GB 在 iOS Safari 上会 OOM（[#70621](https://github.com/godotengine/godot/issues/70621) 仍未关闭；[#104422](https://github.com/godotengine/godot/issues/104422) 记录了 web 构建 400MB 堆导致 WebGL context lost） | **只做 demo**，且要裁剪数据/图集；不要承诺「浏览器里完整体验」 |
| **Android** | 可用 | 桌面端导出需 OpenJDK 17 + Android SDK（默认走「预编译 APK 模板」，Gradle 构建是可选项）；C# 自 4.2 起可导出但**实验性且有限制** | 二期可选（横版动作 + 触屏操作需要重做 UI） |
| **iOS** | 可用 | **必须在 macOS + Xcode 上导出**；C# 实验性 | 本项目暂不考虑 |

引用：[Exporting for the Web](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)、[Exporting for Android](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)、[Exporting for iOS](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html)。

**包体**：Web 侧 `.wasm` + `.pck` 需要服务器 gzip/brotli（官方文档明确建议）；DNF 素材若全量打包，`.pck` 会到几十 GB——所以**任何平台都必须做「按需素材包/图集分片」**，这又回到 C1。

---

## 6. GDScript vs C#

| 维度 | GDScript | C# |
|---|---|---|
| 性能 | 官方 FAQ：脚本语言通常不是瓶颈，**「C# 与 GDScript 在同一数量级，C++ 更快」**（[FAQ](https://docs.godotengine.org/en/4.7/about/faq.html)）；静态类型可让常用操作走优化过的 opcode（[static typing](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html)） | 略快，但差距在同一数量级；真正的热点仍需 C++/GDExtension |
| 工具链 | 开箱即用，无外部依赖 | 需要 .NET SDK（**Godot 4.5 起要求 .NET 8+**，导出 Android 需 .NET 9+），且要用 .NET 版编辑器 |
| 平台 | 全平台 | **桌面（Linux/Windows/macOS）自 4.0 支持；Web 不支持；Android/iOS 自 4.2 起实验性**（[C# basics](https://docs.godotengine.org/en/4.7/tutorials/scripting/c_sharp/c_sharp_basics.html)） |
| 常见坑 | 动态类型错误在运行时才暴露 | `Position.X = 100` 报 CS1612（结构体属性不能就地改字段）；`CallDeferred("AddChild")` 不认 PascalCase（引擎 API 是 snake_case）；每帧 GC 压力 |
| 生态 | 官方主推，教程/插件示例以 GDScript 为主 | 生态较小，第三方插件常只有 GDScript 版 |

**本项目取舍：GDScript（强类型写法）为主。** 理由：

1. 本项目是**数据驱动**的重逻辑游戏，热点在「解析 + 判定 + 动画切帧」，这些在 GDScript 里都够（实测 2,000 精灵每帧更新 0.15ms）；
2. 单人/小团队 + 边学边做，C# 的 .NET 工具链是纯负担，且**彻底断掉 Web 这条路**；
3. 真出现热点（ANI 解码、图集打包、海量数据校验），放到**离线 Python 工具**（已有数据管线）或 **GDExtension（C++）** 里，而不是把整个项目迁到 C#；
4. 如果将来联机要用成熟的 C# 网络库（LiteNetLib 等），那也是「服务端独立进程」的事，不影响客户端语言。

---

## 7. 性能上限与优化

### 7.1 官方口径

- 节点成本：`_process`/`_physics_process` 会遍历整棵树，「节点数的上限**取决于平台，从几千到几万**」；且**每个节点在渲染器里单独处理**，所以「更少的节点、每个节点装更多内容」更快（[CPU optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html)）。
- Godot 有 2D batching（合批）来减少 draw call 瓶颈（同上文档）。
- 物理对象多时物理 tick 会成为瓶颈，建议「视野外移除/回收物理对象」——正好对应 DNF 的「房间即战斗单元」。

### 7.2 本项目的预算（基于实测 + 文档，非实测渲染）

一个 DNF 房间同屏典型量：

| 项 | 数量 | 判断 |
|---|---|---|
| 玩家 + 宠物 + 召唤物 | 1–5 个角色 × 6–10 个部件 = **~50 个 `Sprite2D`** | 无压力 |
| 怪物 | 20–30 只 × 3–8 部件 = **~200 个 `Sprite2D`** | 无压力 |
| 特效（序列帧） | 50–200 个 | 无压力（同一管线） |
| 粒子发射器 | 10–30 个 | 用 `GPUParticles2D`，注意插值差异 |
| 掉落物 / 地面物品 | 30–100 个 | 无压力 |
| 合计 CanvasItem | **~500** | 远低于「几千到几万」的节点上限 |

**真正的瓶颈是纹理切换（draw call）与显存，而不是节点数。** 优化手段，按收益排序：

1. **图集化**：同一角色的所有帧打进 1–2 张图集，同屏所有怪物共用图集 → 合批生效。这是 DNF 客户端本来的做法（`.img` 即图集）。
2. **`Sprite2D.region_rect` 切换帧**，不要每帧新建 `AtlasTexture`（每帧一个资源对象会累积）。
3. **共享 `SpriteFrames`/材质**：不要给每个实例 clone 一份。
4. **视野外从场景树移除**（`remove_child`）而不是 `visible = false` —— 官方明确说前者更快。
5. 大量同图不同变换（如掉落物、子弹）可上 `MultiMeshInstance2D`。
6. UI 列表虚拟化（只实例化可见行）。
7. 逻辑与表现分离：逻辑 60Hz 固定 tick，表现层可用 2D 物理插值（`physics_interpolation`）平滑到高刷屏。

### 7.3 显存预算（用于「图集怎么切」的决策）

一张 2048×2048 RGBA8 图集 = **16MB** 显存（无 mipmap）。同屏 20 张 = 320MB。所以：

- 桌面目标：常驻图集 ≤ 32 张（512MB）；
- Web 目标：常驻 ≤ 12 张（192MB），且注意 WASM 2GB 上限；
- 因此图集必须**按角色/按副本分包，按房间换入换出**，而不是「全量常驻」。

---

## 8. 对接 DNF 素材管线（NPK / ANI / 坐标）

### 8.1 三条可行路线

| 路线 | 做法 | 优点 | 缺点 | 建议 |
|---|---|---|---|---|
| A. 离线图集（推荐） | Python（P0.6）解 NPK → 按 `.img` 打包成 2048² 图集 PNG + 帧表 JSON/二进制 → Godot 直接用 `Sprite2D.region_rect` | 运行时零解码成本；可复用现有 Python 管线；可做像素级检查 | 需要一次全量离线处理（33GB 源） | **主线** |
| B. 运行时解码 | `FileAccess` 读 NPK → 解密 → `Image.load_dds_from_buffer` / `load_png_from_buffer`（实测都存在）→ `ImageTexture` | 无需离线步骤，改数据即时生效 | 每帧 0.024ms 解码（可多线程）；需要移植 NPK 解密到 GDScript 或 GDExtension | 调试期用；或用于「冷门素材按需加载」 |
| C. 混合 | 常用（首切片：鬼剑士 + 洛兰）走 A，其余走 B | 兼顾体积与工作量 | 两条管线都要维护 | 现实选择 |

补充实测：**运行时 DDS 解码是原生支持的**（`Image.load_dds_from_buffer` 在 4.7.2 存在），这对 NPK 里大量 DXT 压缩帧很关键——不需要自己写 DXT 解码器。

### 8.2 像素对齐

- 项目设置里已有现成开关（4.7.2 实测存在）：`rendering/2d/snap/snap_2d_transforms_to_pixel`、`rendering/2d/snap/snap_2d_vertices_to_pixel`（默认 `false`）。
- 纹理过滤：`rendering/textures/canvas_textures/default_texture_filter`，可选 `Nearest/Linear/Linear Mipmap/Nearest Mipmap`（默认 Linear）→ 像素风设 **Nearest**，且导入时不要开 mipmap。
- 缩放：`display/window/stretch/scale_mode` 支持 `fractional` / **`integer`**（像素整数倍缩放，避免半像素模糊）。
- 图集打包务必**整数对齐 + 无边缘渗色**（padding 至少 1px，或 `Nearest` + 不采样边缘）。
- DNF 原图本身可能有半像素偏移（美术当年手工对齐），**以「脚底/受击点」为锚点统一校正**，不要逐帧手调。

### 8.3 Y 轴向下

- Godot 的 2D 坐标是 **Y 向下为正**：官方文档原文「In Godot, going right and down are positive directions.」（[Introduction to 2D](https://docs.godotengine.org/en/4.7/tutorials/2d/introduction_to_2d.html)）。
- DNF 的 ANI 坐标系到底 Y 向上还是向下，要等 **P0.5 ANI 解码**给出结论（`[IMAGE POS]` 的语义 + 实测帧偏置）。**但这不构成风险**：无论哪种约定，转换都是**导入器里的一个函数**（`to_godot(pos) = Vector2(x, sign * y)`），逐帧表转换一次，运行时零成本。真正需要注意的只有：
  - 图集帧的锚点（origin）与 `Sprite2D.offset`/`centered` 的对应关系；
  - 攻击盒矩形与角色锚点同源变换（同一个函数，避免两套坐标系）。
- 结论：**Y 轴转换成本 ≈ 0**，属于管线里的一个常量，不是选型风险。

### 8.4 其他对接点

- **`.act` / `.als` / `.skl`** → 状态机与技能的事件/帧表；建议在 P0.8 导出成「一个动作 = 一串帧号 + 一串事件」的扁平结构，Godot 侧零解析。
- **`.nut`（Squirrel）**：不要试图在 Godot 里跑 Squirrel VM（ROADMAP G2 已判定）。用「数据驱动 + 少量 GDScript 钩子」替代。
- **音频**：DNF 的 `.ogg` 可直接用；Web 侧音频受「Sample 模式」限制（无 `AudioEffect`）。

---

## 9. 社区与插件生态

### 9.1 文档与工具链

- 官方文档质量在开源引擎里属第一梯队，且**版本化**（`/en/4.7/`），API 变更都有迁移说明。
- 4.7 把 Asset Library 换成了 **Asset Store**（带评分与后台线程）（[4.7 发布说明](https://godotengine.org/releases/4.7/)），找插件更容易。
- 编辑器对大项目的加载在 4.4 有过专项修复（[PR #95678](https://github.com/godotengine/godot/pull/95678)，2024-09 合入），但**「几十万个资源」仍然是负担**——所以本项目要把数据放在 `res://` 之外（§2.2 实测：10 万小文件让 `--import` 从 2.9s 变 13.7s）。

### 9.2 插件现状（对本项目）

| 需求 | 现成方案 | 判断 |
|---|---|---|
| 对话系统 | **Dialogic 2**（最新 `2.0-alpha-20`，2026-07-21，明确修了 Godot 4.7 兼容） | 可用，但仍是 **alpha**、单人维护、更新节奏慢。对话是 DNF 的轻量需求，**建议自己写 200 行数据驱动对话框**，插件只作参考 |
| 任务系统 | 无官方；GDQuest 的 [godot-open-rpg](https://github.com/gdquest-demos/godot-open-rpg)（MIT，3k stars，2026-10 仍在更新）可参考架构 | **自己写**；任务本质是「条件→状态→奖励」的数据表，插件反而约束设计 |
| 背包 / 装备 / 技能树 | 无通用方案（各家差异太大） | **自己写**（`Control` + `Theme`，见 §3.6） |
| 存档 | 引擎自带 `FileAccess` + `var_to_bytes`/`JSON` | 自己写，注意版本迁移 |
| SQLite（可选） | `godot-sqlite`（GDExtension） | **不建议**：Web 需开 extension 支持、移动端要额外打包；本项目用「二进制 + 内存索引」足够 |
| 联机（远期） | ENet（内置 `MultiplayerAPI`）、或自建 | 内置够用；**逻辑层要自己保证确定性**（固定 tick + 输入缓冲），别指望引擎帮你 rollback |

### 9.3 已知坑清单（真踩过/官方确认）

1. **海量小文件**：导入超线性（实测 2k→2.9s，5k→32s，20k→>5min）+ 编辑器扫描变慢。
2. **Web 内存**：WASM 2GB 上限，iOS Safari 直接 OOM（[#70621](https://github.com/godotengine/godot/issues/70621)）；web 构建默认堆就可能 400MB 级（[#104422](https://github.com/godotengine/godot/issues/104422)）。
3. **Web 无 C#**：官方明确。选 C# 就等于放弃 Web。
4. **图集导入默认最大宽度 2048**（[PR #87145](https://github.com/godotengine/godot/pull/87145) 之后可配置），做整屏背景图时要注意切块。
5. **`GPUParticles2D` 不参与 2D 物理插值**（见 §3.5）。
6. **JSON 数字 → float**（64 位 ID 丢精度）。
7. **`Area2D` 做逐帧判定**会把物理 tick 与判定耦合，破坏回放/联机确定性。
8. **编辑器预览不执行 Call Method Track**（调试时别以为事件丢了）。
9. **中文字体版权**：别打包 DNF 原字体。

---

## 10. 风险与规避（5 条）

| # | 风险 | 触发条件 | 影响 | 规避方案 |
|---|---|---|---|---|
| **R1** | **素材体量把工程压垮**：百万级帧、33GB NPK、每帧一纹理 | 直接按「一帧一文件/一资源」导入 | 导入数小时~数天、编辑器卡死、显存爆 | ① 按 `.img` 离线打包图集（§8.1 A）；② 数据/素材目录不放 `res://`；③ 图集按角色/副本分包 + 运行时换入；④ 首切片只处理鬼剑士 + 洛兰，验证管线再放量 |
| **R2** | **Web 目标不可行或体验崩坏** | 承诺「浏览器可玩」或选 C# | 返工/砍平台 | ① Web 只做 demo，明确裁剪范围；② 主目标 Win+Linux；③ 若 Web 是硬需求，改用 GDScript + `--headless` 尺寸预算 + 单场景 demo，且预研 iOS Safari OOM |
| **R3** | **启动/切换场景卡顿**：全量数据加载 1s+、内存 788MB | 启动时一次性 `JSON.parse_string` 全库 | 首屏黑屏、低配机 OOM | ① P0.8 产出分域二进制/紧凑格式；② 懒加载 + 预加载白名单；③ 后台线程加载（`WorkerThreadPool`/`ResourceLoader.load_threaded_*`）；④ 启动预算：≤300ms 进主菜单 |
| **R4** | **手感做不出来**（帧精确、判定顺序、受击/浮空/倒地、输入缓冲） | 直接拿引擎的物理/动画当游戏逻辑 | 动作「发飘」，不像 DNF | ① 逻辑固定 60Hz tick，输入进缓冲队列；② `DnfAnimator` 自己切帧、自己派发事件；③ 判定自己算（§3.3）；④ P3.2/P3.4 先做「可回放日志」（录输入 → 重放，验证确定性），为联机留接口 |
| **R5** | **工程规模反噬**（编辑器慢、git 膨胀、CI 慢） | 把 `.godot/`、素材、大图提交进仓库 | 协作困难 | ① `.gitignore` 排除 `.godot/`、`import/`、`*.tmp`；② 素材用 LFS 或独立 manifest + 下载脚本；③ 按切片拆分支/子项目；④ CI 只跑 `--headless` 单测（脚本、数据校验） |

---

## 11. 次选方案

| 方案 | 适合前提 | 优势 | 代价 / 为什么不首选 |
|---|---|---|---|
| **Unity 6 (2D + Addressables + C#)** | 团队有 Unity 经验 / 明确要 Web + 移动 + 商业化发行 | 生态最全、资源商店、Addressables 天生处理「海量资源按需加载」、C# 工具链成熟 | 闭源 + 授权条款风险（近年定价风波）、包体大、编辑器重、2D 像素管线默认不如 Godot 直接；本项目「边学边做、单机、复用原图」没有决定性收益 |
| **自研 Web（TypeScript + PixiJS/Phaser + WebGL2）** | Web 分发是核心诉求 / 团队前端强 | UI 用 DOM 做背包/技能树极快；分发零安装；调试方便 | 33GB 素材的流式加载要自建；原生性能与手柄/全屏体验弱；物理/动画/音频都要拼装；后期做联机反而更简单——但整体工程量比 Godot 大 |
| **Godot 3.6 LTS** | 必须 Web + C# | 3.x 的 C# 可以导出 Web | 2D 渲染/工具链落后一个时代、4.x 才是主线（3.6.3 是维护版）、新特性（TileMapLayer/2D 物理插值）都没有 → **不建议新项目** |
| **Defold** | 2D 移动/Web 小包体 | 包体极小、2D 打磨好 | 生态与工具链弱于 Godot，UI 系统更原始，中文资料少 |

**建议**：以 Godot 4.7.x 为主线；如果未来确定「Web 优先 + 团队 C# 强」，再评估 Unity 6 / TS 自研——但那时的数据管线（P0.5–P0.8）依旧可复用，迁移成本主要在表现层。

---

## 12. 落地清单（把结论变成 P2/P3 的具体动作）

| 动作 | 对应路线图 | 产出 |
|---|---|---|
| 建 Godot 4.7.2 工程骨架：固定 60Hz、Nearest 过滤、整数缩放、`res://` 只放代码与场景 | P2.4 | `game/` 工程 |
| 写 `DnfAnimator`（帧表驱动 + 事件派发 + `region_rect` 切帧） | P3.2 | 组件 + 单测 |
| 写「ANI 帧表 → Godot 数据」转换器（含 Y 轴/锚点/攻击盒变换） | P0.5 → P2.3 | Python 脚本 + schema |
| 写「NPK → 图集 + 帧表」打包器 | P0.6 → P2.3 | 离线工具 |
| 数据层：分域二进制 + 索引 + 懒加载 + 热重载钩子 | P0.8 → P2.2 | `data-json/` 的二进制版 |
| 判定系统：`Rect2`/凸多边形相交 + 帧事件 + 可回放日志 | P3.4 | 模块 + 回放测试 |
| UI 原型：背包（虚拟化）+ 技能树（自绘）+ 对话框（自写） | P3.8/P3.6 | 3 个场景 |
| 平台验证：Win + Linux 导出，跑通首切片 | P3.9 | 构建脚本 |

**验收口径（M2 之前必须成立）**：
1. 鬼剑士在洛兰房间跑跳、播 3 个动作，60fps 稳定（1,000 帧图集，常驻显存 <100MB）；
2. 一帧攻击盒判定与 ANI 数据一致（录放对比）；
3. 启动到可操作 ≤ 2s，常驻内存 ≤ 300MB；
4. Win/Linux 各一份可执行包。

---

## 13. 参考来源

**版本 / 发布**
- [Godot 4.7.2-stable release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)（2026-08-18）
- [Maintenance release: Godot 4.7.2](https://godotengine.org/article/maintenance-release-godot-4-7-2/)
- [Dev snapshot: Godot 4.8 beta 1](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/)（2026-10-15）
- [Godot 4.7 release notes](https://godotengine.org/releases/4.7/)（Control offset transform / Asset Store / one_way_collision_direction）
- [Release support timeline](https://docs.godotengine.org/en/4.7/about/release_policy.html)
- [License (MIT)](https://godotengine.org/license/)

**2D / 动画 / UI**
- [2D sprite animation](https://docs.godotengine.org/en/4.7/tutorials/2d/2d_sprite_animation.html)
- [Animation track types（Call Method Track）](https://docs.godotengine.org/en/4.7/tutorials/animation/animation_track_types.html)
- [Using TileMaps / TileMapLayer](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html) ・ [TileMap 已废弃](https://docs.godotengine.org/en/4.7/classes/class_tilemap.html)
- [Introduction to 2D（Y 向下为正）](https://docs.godotengine.org/en/4.7/tutorials/2d/introduction_to_2d.html)
- [2D and 3D physics interpolation](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html)

**性能 / 数据**
- [CPU optimization（节点成本、2D batching、物理）](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html)
- [General optimization](https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html)
- [Resources](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html) ・ [JSON 类（数字按 float 解析）](https://docs.godotengine.org/en/4.7/classes/class_json.html)
- [Static typing（性能说明）](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html) ・ [FAQ：C# 与 GDScript 同数量级](https://docs.godotengine.org/en/4.7/about/faq.html)
- [Importing images（压缩/过滤）](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)

**导出平台**
- [Exporting for the Web](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)
- [Exporting for Android](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html) ・ [Exporting for iOS](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html)
- [C# basics（平台支持、.NET 版本要求、坑）](https://docs.godotengine.org/en/4.7/tutorials/scripting/c_sharp/c_sharp_basics.html)

**已知问题 / 社区**
- [#70621 WebAssembly 2GB 内存上限（iOS Safari OOM，仍 open）](https://github.com/godotengine/godot/issues/70621)
- [#104422 Web 构建 400MB 堆导致 WebGL context lost](https://github.com/godotengine/godot/issues/104422)
- [PR #87145 图集导入最大宽度可配置（默认 2048）](https://github.com/godotengine/godot/pull/87145)
- [PR #95678 大项目编辑器加载优化（4.4 合入）](https://github.com/godotengine/godot/pull/95678)
- [Dialogic 2 releases（2.0-alpha-20，2026-07-21）](https://github.com/dialogic-godot/dialogic/releases)
- [gdquest-demos/godot-open-rpg（任务系统参考，MIT）](https://github.com/gdquest-demos/godot-open-rpg)

---

*评估者：godot-scout（团队 dnf-like，任务 t4）。实测环境与脚本思路见 §1–§2；headless 无法覆盖渲染指标，相关结论按「预算」标注。*
