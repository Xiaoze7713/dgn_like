# 落地说明 02：Godot 学习流程（从零到能写垂直切片）

> 目标：把「熟悉 Godot」变成一条**有验收标准的 7 关路线**，每关产物都是 `src/game/` 里真会用到的代码，而不是教程 Demo。
> 前提已就绪：引擎/渲染/导出/中文全部实测通过（`docs/GODOT-ENV.md`），技术选型已定（`docs/GODOT-EVAL.md`）。
> 对应路线图：M2「能动」= `docs/ROADMAP.md` 的 **P2.4 / P3.1 / P3.2**。现状：`src/game` 尚未创建，本流程 L0 就从建它开始。

---

## 0. 结论先行

1. **不要「学完 Godot 再开工」。** 这个项目的技术面很窄（2D 横版 + 数据驱动 + 自建动画管线），Godot 九成功能你一生都用不到。目标不是「熟悉引擎」，而是 **6 个工作日内能自己写出「角色在地图上跑跳 + 播对动画」**（= M2），之后边做边学。
2. **最短路径 L0→L4，约 6 天 × 90 分钟。** 想更完整再补 L5→L7，总共约 3 周。L0–L2 是不可跳过的地基，**L3 起每一关直接映射到 P3.x 任务**，写出来的代码进 `src/game`，不丢。
3. **先接受三个反直觉的决定**（能省一个月）：
   - **动画不做「一帧一资源」**：106 万个 `.ani`、千万级帧进导入器必然爆死（实测 2,000 张 PNG 导入 2.9s、20,000 张 > 5 分钟，见 `GODOT-EVAL.md` §2.2）。学习期就用 `Sprite2D + region_rect` 手摇帧表 —— **L3 练的就是这个**。
   - **判定盒不用 `Area2D` 自动检测**：DNF 的盒是 `.ani` 里 6×i32 的数值，必须在脚本里算 `Rect2` 相交（`analysis/15-WEAPON-ATKBOX.md`）。习惯从 L5 就建立。
   - **`AnimatedSprite2D` / `AnimationPlayer` 要会，但不做角色主链路**：它们只用于 UI、特效、≤ 几百帧的场合。

**「够用了」的自测题**（能脱口而出就过关，答不上就重看对应关卡）：

- 场景和节点是什么关系？为什么说「场景就是可复用节点树」？
- `_ready` / `_process` / `_physics_process` 三者执行顺序与各自该放什么？
- 移动逻辑为什么必须放 `_physics_process` 且乘 `delta`（或不用乘）？
- 信号和直接调方法，什么时候用哪个？
- `Sprite2D` 的 `region_enabled` / `region_rect` / `centered` 各自控制什么？
- 角色朝左时，攻击盒的 x 怎么算？
- `queue_free()` 之后还能访问那个节点吗？
- `.tres` 资源和 `.tscn` 场景，分别适合装什么？

---

## 1. 本机环境速查

```bash
cd /home/sunmingze/dnf_like

tools/godot.sh --version                                  # 4.7.2.stable.official.ed1daf0bf
tools/godot.sh --editor                                   # 打开编辑器（WSLg 窗口）
tools/godot.sh                                            # 跑 src/game（不存在则回退 tools/smoke）
GODOT_PROJECT=src/game tools/godot.sh                     # 显式指定工程
tools/godot.sh --headless --quit                          # 无窗口冒烟，退出码即结论
tools/godot.sh --write-movie /tmp/f.png --quit-after 6    # 导出 PNG 序列（视觉验证）
tools/godot.sh --export-windows                           # 出 Windows exe
```

几条硬性环境结论（来自 `GODOT-ENV.md`，别再试错）：

| 事项 | 结论 |
|---|---|
| 项目放哪 | **`src/game`（ext4）**。别放 `/mnt/c`：1,000 张图导入 3.72s vs 18.73s |
| 渲染后端 | 固定 **Compatibility（`gl_compatibility`）**。WSL2 无 Vulkan，不是妥协，2D 本来就该用它 |
| 编辑器 | 开在 WSLg（`DISPLAY=:0`）。**建议**：编辑器只用来摆场景，写代码用外部编辑器 + LSP（VSCode `godot-tools`），见 [外接编辑器](https://docs.godotengine.org/zh-cn/4.x/tutorials/editor/external_editor.html) |
| 画面验证 | `--headless` 不出图，**画面一律用 `--write-movie` 导 PNG 看**（与 `tools/smoke` 同一习惯） |
| 中文字体 | 系统回退能显示；发行版仍要打包字体（`GODOT-ENV.md` §6） |

---

## 2. 学习地图：学什么 / 学到什么程度 / 什么跳过

| 模块 | 学到什么程度就够 | 用在哪 | 细则 |
|---|---|---|---|
| 节点 / 场景 / 场景树 / 实例化 | 知道「什么该拆成一个场景」 | 一切 | 必须会，L1 |
| GDScript 4 | 类型标注、`@export`/`@onready`、`enum`/`match`、`Callable`、静态类型 | 一切 | 会读会写，不必背完 |
| 信号 | 能用一个 `signal` 解耦「动画结束 → 状态机切换」 | L3/L4 | 必须会 |
| `Node2D` + 坐标系 + `CanvasLayer` | 画对层级、UI 不跟世界滚动 | L6 | 必须会 |
| `CharacterBody2D` + `move_and_slide` + 碰撞层/掩码 | 手感参数全部 `@export` 可调 | P3.1 | L2，必须会 |
| `InputMap` | 键位可在设置里改，代码里只用 action 名 | L2/L4 | 必须会 |
| `TileMapLayer` | 能用图块拼地面、单向平台 | P3.9 | 会到「能拼图」即可 |
| `Control` 锚点/容器/Theme | HUD 换分辨率不变形 | P2.4 | L6 |
| `Resource` + `.tres` | 技能/攻击盒/怪物表能数据驱动 | P3.6 | L7，**本项目的关键习惯** |
| `Camera2D` limit/zoom/震屏 | 相机在关卡边界停住 | L6 | 简单但必踩 |
| 调试三件套 | `print` / 断点 / 远程检查器 + Profiler | 全程 | 卡住就用它，别猜 |

**明确跳过、别看**（都没进 P3 验收表，看了就是浪费时间）：

3D 一切、着色器（只知道「像素图靠 `texture_filter` 关掉平滑」即可）、`Navigation` 寻路、XR、C#/.NET、GDExtension/C++、移动端导出、网络同步、`AnimationTree` 状态机、`Skeleton2D` 骨骼、2D 灯光与法线贴图、`CSG`。

理由一句话：**这套东西对「2D 横版 + 数据驱动」没有一分钱价值**，而 DNF-like 的难点全在动画管线、判定盒、手感参数上。

---

## 3. 七关路线

每关格式：**目标 / 读什么 / 写什么 / 验收 / 时长 / 对应任务**。纪律：每关都**从空场景自己搭**，不许打开教程成品工程抄。

### L0 · 环境与编辑器肌肉记忆（0.5 天 · 30–60 分钟）

- **读**：[初识 Godot 界面](https://docs.godotengine.org/zh-cn/4.x/getting_started/introduction/first_look_at_the_editor.html)、[命令行教程](https://docs.godotengine.org/zh-cn/4.x/tutorials/editor/command_line_tutorial.html)
- **写**：建 `src/game`，手写 `project.godot`（参数见下），加一个 `Node2D` → `Sprite2D` + `Label`，用 `tools/godot.sh` 跑起来，再 `--write-movie` 出图。
- **验收**：`tools/godot.sh --headless --quit` 退出码 0；`/tmp/f*.png` 里有画面（不是黑屏）；中文不小方块。
- 起手 `project.godot` 关键段（照抄，`config_version=5` 是 4.x 的格式版本）：

```ini
config_version=5

[application]
config/name="dnf_like"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/canvas_textures/default_texture_filter=0
```

> **L0 要顺手定一件事**：基准分辨率。`1280×720 + canvas_items + expand` 建议作为起点（UI 清晰、宽屏不拉伸），角色在屏幕上的占比靠 `Camera2D.zoom` 调（想还原 DNF 那种「角色占屏高 1/6」的观感，zoom 大约 1.3–1.6，拿一张原版截图目测校准）。这条属于 `ROADMAP.md` Q5/Q6 的范围，先按默认建议走，切片做完再回看。

### L1 · 节点、场景、信号、脚本（1 天）

- **读**：[关键概念概述](https://docs.godotengine.org/zh-cn/4.x/getting_started/introduction/key_concepts_overview.html) → [渐进式教程](https://docs.godotengine.org/zh-cn/4.x/getting_started/step_by_step/index.html)（节点与场景 / 创建实例 / 第一个脚本 / 使用信号，共 4 页）
- **写**：单页面小游戏，≤ 40 行：精灵跟随鼠标 → 点击计分 → `Label` 显示 → 计分到 10 发一个自定义信号让对方变色。
- **验收**：能讲清「场景 = 可复用节点树 + 挂在根上的脚本」；能讲清 `$Path` 与 `%UniqueName`（场景内唯一名）的区别；信号只在编辑器里连过一次。
- **对应**：后续所有关卡的地基。

### L2 · 2D 移动与碰撞（2 天）

- **读**：[2D 简介](https://docs.godotengine.org/zh-cn/4.x/tutorials/2d/index.html)、[视口/画布变换](https://docs.godotengine.org/zh-cn/4.x/tutorials/2d/2d_transforms.html)、[使用 CharacterBody2D](https://docs.godotengine.org/zh-cn/4.x/tutorials/physics/using_character_body_2d.html)、[输入示例](https://docs.godotengine.org/zh-cn/4.x/tutorials/inputs/input_examples.html)
- **写**：`CharacterBody2D` 角色（重力、跳跃、土狼时间、减速度、面朝方向）+ `StaticBody2D` 地面 + `TileMapLayer` 地面补一段；输入全部走 `InputMap`：`move_left` / `move_right` / `jump` / `attack` / `skill1`。
- **验收**：跑跳不穿墙、不粘墙、平台边缘不抖；**跳跃高度、滞空、加速度全部 `@export` 在一个分组里可调**，改完立刻能感觉出手感差异。这就是 **P3.1** 的验收标准。
- **坑**：`move_and_slide()` 读的是 `velocity`；`is_on_floor()` 只在 move 之后准确；移动放 `_physics_process`（固定 60Hz），别放 `_process`。

### L3 · 帧动画与图集（2 天 · **本项目最重要的一关**）

- **读**：[2D 精灵动画](https://docs.godotengine.org/zh-cn/4.x/tutorials/2d/2d_sprite_animation.html)（知道官方三条路：逐图 / 精灵表 / AnimationPlayer，然后**选第四条**）+ 本仓库 `docs/GUIDE-MOVE-ANIM.md` + `export/ani/*.jsonl` 的帧表
- **写**：`FrameAnimator`（`RefCounted` 或 `Node`）：输入「帧矩形数组 + 每帧毫秒」→ 每帧改 `Sprite2D.region_rect`；支持循环 / 一次性 / 停帧；发 `frame_changed(idx, flag)` 信号。
- **验收**（三条缺一不可）：
  1. `stay`(6 帧/120ms) → `move`(8 帧/100ms) → `dash`(8 帧/100ms) 切换，**帧节奏与 `total_ms` 对齐**（打日志对时间，误差 < 1 帧）；
  2. 三套动画共用**同一张图集**，切动画不换纹理、不重载；
  3. `jump.ani` 的 50–10000ms 变长帧能正确表达（靠「停帧」不是「10 秒长动画」）。
- **对应**：**P3.2**。
- **为什么不直接 `AnimatedSprite2D`**：

| | `AnimatedSprite2D` + `SpriteFrames` | 自建 `FrameAnimator` |
|---|---|---|
| 帧数据来源 | 编辑器里手点 / 导入 | 数据文件（`.ani` 帧表） |
| 规模上限 | 几百帧舒适 | 上万帧无压力（只存矩形+时长） |
| 换皮换帧表 | 重建 `SpriteFrames` | 换两个数组 |
| 事件帧（flag） | 只能靠 `animation_finished` | 每帧可发信号（对齐 `flagIndex`） |

最小骨架（可直接抄，注意 `maxf` 防 0 时长死循环）：

```gdscript
class_name FrameAnimator
extends RefCounted

signal frame_changed(idx: int, flag: int)

var _rects: Array[Rect2i] = []
var _durs: PackedInt32Array = []
var _loop := true
var _i := 0
var _t := 0.0  # 毫秒

func play(rects: Array[Rect2i], durs: PackedInt32Array, loop: bool) -> void:
	_rects = rects; _durs = durs; _loop = loop
	_i = 0; _t = 0.0
	frame_changed.emit(0, 0)

## 返回 -1 = 本帧未切换；否则返回新帧号
func advance(delta_ms: float) -> int:
	var prev := _i
	_t += delta_ms
	while _i < _rects.size() and _t >= maxf(float(_durs[_i]), 0.001):
		_t -= maxf(float(_durs[_i]), 0.001)
		_i += 1
		if _i >= _rects.size():
			if _loop:
				_i = 0
			else:
				_i = _rects.size() - 1
				_t = 0.0
				break
	return -1 if _i == prev else _i
```

### L4 · 输入 → 动作状态机（2–3 天）

- **读**：[GDScript 基础](https://docs.godotengine.org/zh-cn/4.x/tutorials/scripting/gdscript/gdscript_basics.html)（`enum` / `match` / 字典 / `Callable` 部分）
- **写**：`enum State { IDLE, RUN, JUMP, ATTACK1, ATTACK2, ATTACK3 }` + 显式切换表（`from → [to...]` 字典，非法转换直接拒绝并打日志）+ **帧事件**（第 2 帧发「命中窗口开」）+ 前摇/后摇/可取消窗口（attack1 播到 30% 后可被 attack2 打断）。
- **验收**：连按 Z 出三段连击；攻击中按空格跳不了；落地可取消攻击；开着「状态日志」能一眼看懂每次切换是谁发起的。
- **对应**：**P3.3** 的预演。

### L5 · 判定盒与伤害（2 天）

- **读**：官方没有对应章节（官方只有 `Area2D` 那套），改读 `analysis/04-combat.md` + `analysis/15-WEAPON-ATKBOX.md` + `docs/ANI-FORMAT.md` 的 `0x0E/0x0F` 尾块
- **写**：`Hitbox`：相对坐标 `Rect2i` + `facing` 翻转 + 每帧 AABB 相交；「一次挥击 → 命中集合」去重；伤害浮字；击退方向。
- **验收**：命中帧号与 `.ani` 的帧号一致（打日志比对）；角色左右翻转后判定**对称**；三个怪叠在一起只结算一次；**同一套盒数据不改代码就能换**。
- **对应**：**P3.4**。
- 关键两行（`facing = -1` 时 x 要镜像并减去宽度）：

```gdscript
## 数据盒 → 世界盒。b = Rect2i(相对x, 相对y, 宽, 高)
func to_world(b: Rect2i, facing: int, origin: Vector2i) -> Rect2i:
	var x := b.position.x if facing > 0 else -(b.position.x + b.size.x)
	return Rect2i(origin + Vector2i(x, b.position.y), b.size)
```

> 数据里是 `(相对X, 相对Y, 相对Z, 宽, 高, 深)` 六元组；2D 阶段丢掉 Z（或留作图层深度），别硬套 3D 语义。

### L6 · 场景组织、相机、UI（1–2 天）

- **读**：[用户界面](https://docs.godotengine.org/zh-cn/4.x/tutorials/ui/index.html)、[多分辨率](https://docs.godotengine.org/zh-cn/4.x/tutorials/rendering/multiple_resolutions.html)、[画布层](https://docs.godotengine.org/zh-cn/4.x/tutorials/2d/canvas_layers.html)
- **写**：`Main` 场景（世界 / HUD / 相机三层）+ `Camera2D`（`limit_*` 夹边界 + 平滑跟随 + 震屏）+ `CanvasLayer` HUD（血条、蓝条、技能栏）+ `Control` 锚点布局。
- **验收**：窗口 1280×720 与 2560×1440 下 UI 不跑位、不模糊；相机在关卡左右边界停住；震屏只晃世界不晃 UI。
- **对应**：**P2.4**（客户端骨架）。

### L7 · 数据驱动与存档（1–2 天）

- **读**：[资源](https://docs.godotengine.org/zh-cn/4.x/tutorials/scripting/resources.html)、[保存游戏](https://docs.godotengine.org/zh-cn/4.x/tutorials/io/saving_games.html)
- **写**：`SkillDef` / `HitboxDef` 做成 `Resource`（`.tres`）+ `ResourceLoader.load_threaded_request` 异步预载；存档走 JSON（带 `version` 字段），**不用** `var_to_bytes` 存进度。
- **验收**：改 `.tres` 里的伤害数字，**不改一行代码**，游戏里生效；存档跨版本读不崩（旧版本号走迁移分支）。
- **对应**：**P3.6 / P3.10**。
- 为什么不 `var_to_bytes` 存档：二进制不可 diff、不可手改、跨版本必炸；它是给「离线导数据」用的（`GODOT-EVAL.md` §2.1 里那种 405ms 反序列化的场景）。

### L8（可选）· 关卡与深度（1–2 天）

`TileMapLayer` 拼地图 + `y_sort_enabled` 做深度排序 + 视差背景 + 房间切换。切片阶段够用就行，`Navigation` 不要碰（横版用不上寻路）。

---

## 4. 验收怎么自动化（可被团队/agent 复跑）

每关的验收都写成 `src/game/tests/` 下的 `SceneTree` 脚本，**不依赖窗口**：

```gdscript
# tests/test_frame_animator.gd
extends SceneTree

func _initialize() -> void:
	var a := FrameAnimator.new()
	a.play([Rect2i(0, 0, 64, 64), Rect2i(64, 0, 64, 64)], PackedInt32Array([120, 120]), true)
	assert(a.advance(119.0) == -1)      # 未到时长，不换帧
	assert(a.advance(1.0) == 1)         # 累计 120ms，换到第 2 帧
	assert(a.advance(120.0) == 0)       # 循环回第 1 帧
	print("PASS test_frame_animator")
	quit(0)
```

```bash
tools/godot.sh --headless --path src/game --editor --quit        # 首次：生成 .godot/ 类缓存
tools/godot.sh --headless --path src/game --script res://tests/test_frame_animator.gd
echo "exit=$?"     # 0 = 过，非 0 = 挂
```

> **实测（本机 4.7.2）**：上面这段 `FrameAnimator` 用例真跑过，输出 `s1=-1 / s2=1 / s3=0`。
> **坑**：`class_name` 是全局注册，靠 `.godot/global_script_class_cache.cfg`；`--script` 模式下若项目**从没被导入过**，会报 `Identifier "FrameAnimator" not declared in the current scope`。
> 所以首次必须先 `--editor --quit` 扫一遍项目（本仓库 `tools/smoke` 里已有 `.godot/`，所以没撞过这个坑）。

三条纪律：

1. **逻辑断言放 headless**（快、可 CI）；**画面用 `--write-movie` 出 PNG 人眼看**。两者分开，别混。
2. 每个 P3.x 任务合并前，必须有一条这样的测试 + 一张 PNG。
3. `assert()` 在 release 导出里会被剪掉，长期用例改成显式 `if + push_error + quit(1)`。

---

## 5. 每天 90 分钟怎么排

| 时间 | 做什么 | 纪律 |
|---|---|---|
| 前 30 分钟 | 读「当关列出的那几页」，只读那几页 | **不许扩散点到 3D/教程视频** |
| 中间 50 分钟 | 从空场景自己搭当关产物 | **不许打开教程成品工程抄**；卡住就 `print` + 断点 |
| 后 10 分钟 | 写 3 行笔记进 `docs/notes/godot-YYYYMMDD.md`，提交 | 笔记只记「我踩的坑 + 我做的决定」 |

**「学废了」的三个信号**：开始找插件、开始找模板、开始看视频。出现任一，立刻回到「**从空场景重写一遍**」。

---

## 6. 这 12 个坑，本项目一定会撞

| # | 坑 | 现象 | 正确做法 |
|---|---|---|---|
| 1 | 移动写在 `_process` | 手感随帧率变、低帧穿墙 | 移动/判定放 `_physics_process` |
| 2 | 忘了乘 `delta` | 速度随帧率变 | 位移 = `速度 × delta`；`move_and_slide()` 内部已处理，别再乘 |
| 3 | 硬路径 `get_node("../../X")` | 调结构就崩 | `%UniqueName` 或 `@export var target: NodePath` |
| 4 | 把海量 `.ani`/PNG 拖进 FileSystem | 编辑器卡死、导入几分钟 | 走数据管线（`GODOT-EVAL.md` C1/C2） |
| 5 | `region_rect` 不生效 | 显示整张图集 | 先 `region_enabled = true` |
| 6 | 像素图模糊 | 精灵发虚 | `textures/canvas_textures/default_texture_filter=0`（L0 已设） |
| 7 | Y 轴方向搞反 | 跳跃往地里钻 | 2D 里 **Y 向下**，跳跃 = `velocity.y -= jump_force` |
| 8 | `queue_free()` 后还访问 | 崩溃 / 空引用 | `is_instance_valid()` 或延迟到下一帧 |
| 9 | 用场景继承堆职业 | 一处改动全崩 | 优先「组合 + `@export` 注入」 |
| 10 | 在 `--headless` 里测画面 | 永远黑屏 | 画面用 `--write-movie` |
| 11 | 信号用 3.x 字符串写法 | 报错/静默失败 | 4.x 传 `Callable`：`sig.connect(_on_sig)` |
| 12 | 拿 `AnimationPlayer` 当动画主链路 | 数据进不了编辑器，规模卡死 | 主链路走 `FrameAnimator`，`AnimationPlayer` 只做 UI/特效 |

---

## 7. 三周日历（可裁剪）

`★` = 最短路径必需；`·` = 有余力再补。

| 天 | 关卡 | 当日产出 |
|---|---|---|
| D1 | ★ L0 | `src/game/project.godot` 建好，能出图，中文正常 |
| D2–D3 | ★ L1 | 节点/场景/信号的小游戏 + 说清关键概念 |
| D4–D5 | ★ L2 | 角色跑跳 + TileMapLayer 地面（= P3.1 验收） |
| D6–D7 | ★ L3 | `FrameAnimator` + 三动画切换（= P3.2 核心） |
| D8–D10 | ★ L4 | 状态机 + 三段连击 + 帧事件（= P3.3 预演） |
| D11–D12 | ★ L5 | 判定盒 + 伤害 + 击退（= P3.4） |
| D13–D14 | · L6 | Main 场景 + 相机 + HUD（= P2.4） |
| D15–D16 | · L7 | `.tres` 数据驱动 + 存档（= P3.6/P3.10） |
| D17–D21 | 缓冲 | 补漏；把 L1–L3 的代码整理进 `src/game` 真结构 |

只想要「能动」→ 做到 **D10 停**，直接进 M2 里程碑。剩下的在 P3 里按需补。

---

## 8. 学完拥有什么（对齐里程碑）

| 关卡 | 产出的真代码 | 解锁任务 |
|---|---|---|
| L0 | `src/game/project.godot` + 目录结构 | 一切 |
| L1 | 场景/信号的使用习惯 | 一切 |
| L2 | `player.gd`（移动/跳跃参数化） | **P3.1** 角色移动/跳跃/地形碰撞 |
| L3 | `frame_animator.gd` + 帧表加载 | **P3.2** 动画状态机 |
| L4 | `player_state.gd`（状态机 + 帧事件） | **P3.3** 普攻与连击 |
| L5 | `hitbox.gd` / `damage.gd` | **P3.4** 判定盒与伤害结算 |
| L6 | `main.tscn` / `camera.gd` / `hud.tscn` | **P2.4** 客户端骨架 |
| L7 | `skill_def.gd` + `save_system.gd` | **P3.6 / P3.10** |

---

## 9. 参考资料（全部已验 HTTP 200）

官方手册（简体中文 4.x，与 4.7.2 同大版本）：

- 入门：[关键概念](https://docs.godotengine.org/zh-cn/4.x/getting_started/introduction/key_concepts_overview.html) · [渐进式教程](https://docs.godotengine.org/zh-cn/4.x/getting_started/step_by_step/index.html) · [第一个 2D 游戏](https://docs.godotengine.org/zh-cn/4.x/getting_started/first_2d_game/index.html)
- 2D：[2D 总览](https://docs.godotengine.org/zh-cn/4.x/tutorials/2d/index.html) · [变换](https://docs.godotengine.org/zh-cn/4.x/tutorials/2d/2d_transforms.html) · [精灵动画](https://docs.godotengine.org/zh-cn/4.x/tutorials/2d/2d_sprite_animation.html)
- 物理：[CharacterBody2D](https://docs.godotengine.org/zh-cn/4.x/tutorials/physics/using_character_body_2d.html)
- 脚本：[GDScript 基础](https://docs.godotengine.org/zh-cn/4.x/tutorials/scripting/gdscript/gdscript_basics.html) · [资源](https://docs.godotengine.org/zh-cn/4.x/tutorials/scripting/resources.html) · [存档](https://docs.godotengine.org/zh-cn/4.x/tutorials/io/saving_games.html)
- 其它：[输入示例](https://docs.godotengine.org/zh-cn/4.x/tutorials/inputs/input_examples.html) · [多分辨率](https://docs.godotengine.org/zh-cn/4.x/tutorials/rendering/multiple_resolutions.html) · [UI](https://docs.godotengine.org/zh-cn/4.x/tutorials/ui/index.html) · [命令行](https://docs.godotengine.org/zh-cn/4.x/tutorials/editor/command_line_tutorial.html) · [导出](https://docs.godotengine.org/zh-cn/4.x/tutorials/export/index.html) · [最佳实践](https://docs.godotengine.org/zh-cn/4.x/tutorials/best_practices/index.html) · [性能](https://docs.godotengine.org/zh-cn/4.x/tutorials/performance/index.html)

本仓库内（比官方更贴本项目，优先读）：

- `docs/GODOT-ENV.md` — 本机环境实测（渲染/导出/中文/字体）
- `docs/GODOT-EVAL.md` — 引擎可行性、导入与内存的实测数字、三硬条件 C1–C3
- `docs/GUIDE-MOVE-ANIM.md` — 输入→状态→帧表→图集矩形 这条管线的实测数据（L3 直接照它写）
- `docs/ANI-FORMAT.md`、`analysis/15-WEAPON-ATKBOX.md` — 判定盒与 flag 帧的来源（L4/L5 要用）

**编辑器快捷键只要记 6 个**：`F1` 内置类参考（**最常用**，用类名/方法名直接搜）、`Ctrl+点击` 跳定义、`Ctrl+Shift+F` 全项目搜索、`F5` 跑项目、`F6` 跑当前场景、`F8` 断点。

**不看的清单**（省时间）：任何「Godot 4 完整教程 20 小时」视频、任何 3D 内容、任何「30 天做 MMO」类文章、插件市场。卡住时查官方手册 + 在本仓库 `grep`，比视频快一个数量级。
