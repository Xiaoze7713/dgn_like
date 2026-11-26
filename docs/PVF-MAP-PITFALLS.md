# PVF 地图加载 · 踩坑与定论（2026-11-18，2026-11-25 增量见 §7）

> **这份文件是干什么的**：把 2026-11-18 一天里踩过的坑，按「现象 / 根因 / 正确做法 / 证据」记下来，下次做同类工作前先扫一遍，别重犯。
>
> **配套文档**：`docs/PVF-MAP-LOADING.md`（规则与架构，正面描述）、`docs/PVF-NEW-STK-CHR-SPEC.md`（.stk/.chr 格式）。本文只记**错在哪、为什么错、怎么验证**。
>
> **工程根**：PVF 内容包与脚本在 `/home/sunmingze/dnf_like`；Godot 工程在 `client/`（下文 `game/...`、`assets/...` 都是相对 Godot 工程根）。

---

## 0. 一句话总结今天最贵的三个坑

| 坑 | 现象 | 根因（一句话） |
|---|---|---|
| **z_index 越界** | 背景一加，所有装饰地砖全消失 | Godot `z_index` 合法区间 `[-4096, 4096]`，写 `-6000` 被**静默拒绝**并回落 0，盖住整层 |
| **两套坐标系混用** | 建筑和街道之间一条黑带；树浮空 | `[animation]` 用画面系（y 向下、加画布原点），地砖/怪物/NPC 用「距下沿高度」翻 y，两者不能混 |
| **`[img pos]` 当成向下偏移** | 副本里怪浮在半空、地砖整体偏低 120px | 不变式是 `画布高 == 行数×16 + [img pos]`，`img_pos` 是**画布顶部空白**，不是往下推 |

---

## 1. 格式层（PVF binary → token → 内容包）

### 1.1 token 是 5 字节定长，字符串两个池

- **现象**：解析出来的值全是数字/乱码。
- **根因**：token = `[1B type][4B int32]`，`type` 有 7 种含义（0 int / 2 float32 / 3 换行+字符串 / 5 `{` / 6 反引号串 / 7 `}` / 8 值串）；字符串不是内联，是 `v>>1` 去 `strW`（UTF-16LE，双 NUL）取。
- **正确做法**：`tools/pvf_script.py` 的 `StringPool.resolve()`；本版 `strA.bin` 是 **0 字节**，`v & 1` 恒为奇。
- **坑**：mmap 后必须持有文件句柄，否则 `OSError: [Errno 9] Bad file descriptor`。

### 1.2 `.stk` 能成树，`.chr` 不能

- **现象**：拿 `.stk` 的解析器去解析 `.chr`，整份文件被吞成一层。
- **根因**：`.chr` **没有 `{`/`}`，也没有 `[/growtype]`**，是平铺 token 流；嵌套关系只由「标签名 + 出现顺序」隐式表达。
- **正确做法**：`.stk` 走两遍建树（`[x]...[/x]` 配对）；`.chr` 走状态机：区域只认 `[initial value]` / `[growtype N]` / `[awakening N]` 三个正则，容器由「文件里存在 `[/同名]`」动态推导，`TAIL_RE` 命中时强制关区域。见 `tools/chr_scan.py`。

### 1.3 `[/x]` 被当成孩子

- **现象**：结构里每个容器下面都多一层 `[/show skill]` 子节点。
- **根因**：规范化标签时先把方括号剥掉了，于是关闭标签变成 `/show skill`，代码却判 `startswith("[/")`。
- **正确做法**：统一判 `pairs[i].label.startswith("/")`，`close_set` 用 `{p.label[1:] for p in pairs if p.label.startswith("/")}`。

### 1.4 别用「无值 + 后面还有标签」猜区域

- **现象**：`[CHARACTER ATTACK TYPE]` 把后面整块吞进去。
- **正确做法**：区域**只**由显式的区域正则判定；不猜。

### 1.5 引用路径有两种基准

- **现象**：`.skl` 里的 `Character/Swordman/Effect/...` 被判成缺失（2,367 条误报）。
- **根因**：`.als` 的 `../Effect/...` 是**相对自身目录**；`.skl` 的是**相对 PVF 根**。
- **正确做法**：`resolve_rel()` 依次试 `base_dir/rel` → `root/rel`，命中即止并记录用的是哪种。见 `tools/pvf_world/build_pack.py`。

### 1.6 其它已定结论（别再推翻）

| 结论 | 证据 |
|---|---|
| `.als` 是 `.ani` 的**同名旁挂**，没有任何文件显式引用它 | 2,318 个 `.als`，被引用 0 |
| `.atk` **只被 `.chr` 引用** | 566 个中 548 个被 chr 引用，孤儿 18 |
| `.img` 一律归 NPK（ImagePacks2），PVF 里查不到，**不能算 missing** | `[body image path]` 带 `%04d` 模板 |
| `[grade]` 不是品质等级 | grade=4 ↔ `[avatar emblem]` 12,210（rarity 恒 6）、84/57 ↔ recipe、50 ↔ booster |
| `.chr` 的 `[skill]` 是**三元组** | 643 条里 437 条 X == skl `[required level]`；旧文档的「二元组」是旧版 |

---

## 2. 内容包编译层（Python → JSON）

### 2.1 `[maze info]` 是没有子节点的段标记

- **现象**：`maze_info.children` 永远为空，拿不到 `[size]/[greed]/[map specification]`。
- **根因**：它们是 `[maze info]` 的**同级兄弟**，不是子节点。
- **正确做法**：按出现顺序切段（遇到 `[maze info]` 开新段）。mirkwood.dgn 有 4 段。

### 2.2 `[greed]` 是多行字符串

- **现象**：`.strip()` 只去掉首尾，中间残留 `\r\n` 和行首空格，网格全错。
- **正确做法**：`re.split(r"[\r\n]+", text)` 逐行 strip，去掉行内空格后**每 2 字符一格**。

### 2.3 一个 `[monster]` 标签里塞 N 只怪

- **现象**：一张图几十只怪只解析出 1 只。
- **正确做法**：流式切：`8×int` + `[fixed|half|ratio]` + 类型 token，类型前可插 `[NPC] id 朝向 x y z`。

### 2.4 `[extended tile]` 的 `[tile files]` 是「序号 + 路径」交替

- **现象**：只解析出 1 块扩展地砖。
- **根因**：`node_strs()` 只取字符串值，丢掉了前面的序号。
- **正确做法**：逐对读成 `by_idx`，再把 `[tile map]`（每列用第几块）读成 `extended_map`。

### 2.5 `[import script]` 是继承，父图可能已经不存在

- **现象**：中央公园 area 0 装进去是空房间。
- **根因**：`gate_centralpark.map` 只有一行 `[import script] Common/Gate_Seria.map`，而这张父图在 latest 里**已被删**。
- **正确做法**：父图字段**只填空题图里为空的键**（跳过 path/import）；找不到父图记 `import_missing`；运行时再兜一层「图里必须有地砖」（`_area_usable()`）。
- **2026-11-25 补充**：latest 里并不是完全没有这张图，而是只剩 `map/common/(f)gate_seria.map` 和 `(r)gate_seria.map` 两个变体；`Common/Gate_Seria.map` 这个精确名不存在。当前没有猜 `(f)/(r)`，所以 centralpark/metrocenter 的 gate area 仍判空并回退 a1。

### 2.6 其它

| 坑 | 正确做法 |
|---|---|
| `.twn` area 的 map 引用不带 `map/` 前缀 | `'map/' + ref.lower()` |
| `[minimap rect]` 是 `x0 y0 x1 y1` | 转 `Rect2(x0, y0, x1-x0, y1-y0)` |
| `sight` 存成了原始标签名 | JSON 键统一成 `far/middle/near`，否则视差取不到值 |
| index 里的 dungeon `id` 是 basename 字符串 | 另存 `registry_id`（来自 `dungeon/tutorial/dungeon.lst`），别 `int()` 它 |
| `[passive object]` 输出成裸数组 | 输出 dict，否则 GDScript 端 `var d: Dictionary = m` 直接抛错 |
| `.obj → .act → .ani` 找不到 `[BASE ANI]` | 它在 `[MOTION]` 子节点里，必须 DFS（`find_deep`） |
| 内容包 key | `re.sub(r"[^a-z0-9._-]+", "_", path.lower())`，Python 与 GDScript **两边必须同一正则** |

---

## 3. 运行时坐标与图层（Godot）

### 3.1 两套坐标系，别混

| 数据 | 轴的方向 | 公式 |
|---|---|---|
| `.til` 的 `[pass type]` 数组 | **第 0 行 = 地砖下沿**，往上走 | `world_row = rows - 1 - index` |
| `.map` 的怪物/NPC/物件/`[pathgate pos]` 的 y | **距下沿的高度** | `screen_y = 网格高 − y` |
| `.map` 的 `[animation]` 的 (x, y) | **画面系，y 向下** | `screen = (x, y) + 画布原点 rect.position + [IMAGE POS]` |
| `[background pos]` | 背景层额外的垂直偏移 | `bg_y = rect.position.y + background_pos + [IMAGE POS].dy` |

- **证据**：`handon` 的 `hmwall02.img`（画布 y=288、图高 134）+ 地图 y=219 + `[IMAGE POS]` dy=-419 → 88..222，**底边正好压在人行道上沿 222**；同一图的 `hmbrLtile01` 顶边也是 222。
- **教训**：我一开始只算 `地图 y + [IMAGE POS]`，漏了画布原点，整排墙被推到画面外（-200）。

### 3.2 `[animation]` 是 5 元组，第三个数字是 z

`(ani 路径, 图层 token, x, y, z)`。z 是**离地高度**（多为 0，但不是全 0，例：`hmbgbox2.ani [closeback] 154 173 28`），有效 y = `y + y_shift - z`。

### 3.3 `[img pos]` 是画布**顶部**空白（今天的第二个大坑）

```
画布高 == 行数×16 + [img pos]
```

| 图 | 行数×16 | `[img pos]` | 画布高 |
|---|---|---|---|
| `hmtile.img` | 480 | 0 | 480 |
| `central_tile.img` | 480 | 80 | 560 |
| `darkentrance tile.img` | 480 | 120 | 600 |
| `point.img`（科勒） | 480 | 120 | 600 |

- **错误公式**：`网格高 + img_pos − 图高`（等于把美术往下推 `img_pos`）。
- **正确公式**：`网格高 − 图高`（画布底边对齐网格底边）。
- **表现**：城镇 `img_pos = 0`，看不出差别；副本 `img_pos = 120`，地砖整体低 120px，怪浮在半空。
- **验证**：改前改后城镇截图 sha256 完全相同（`0be958ca…`），副本整体上移 120px。

### 3.4 相机：房间比视野矮时要**贴底**

- **现象**：整个场景凭空高 84px，画面底部一条黑带。
- **根因**：房间 480、视口 648，按「居中」算相机 → 下方多出 `(648-480)/2 = 84`；而 `clampf(y, half.y, grid.height-half.y)` 在 480 高时是**空区间**，夹出来的是错值。
- **正确做法**：房间高 ≤ 视口高时 `camera.y = grid.height - VIEW.y * 0.5`。

### 3.5 `[animation]` 整体偏移 = 120（固定值）

- 这一层是按「原客户端 600 高的可见画面」摆的，比画布原点公式低 **120px**（用户 2026-11-18 定的固定值，和 480 同一套基准）。写在 `RoomBuilder.y_shift`，环境变量 `WORLD_YSHIFT` 可覆盖。
- **不要把可调参数当默认值**：这里一旦改成"实验值/靠环境变量调"，下次就没人知道真值是多少。

### 3.6 视差：只能由**来源**决定，不能靠图层名猜

- **现象**：贴身的花草（`[closeback]`）跟着镜头漂移。
- **根因**：`_scroll_factor()` 用 `layer.contains("back")` 判断要不要做视差，而 `closeback` 里含 `"back"`。
- **正确做法**：`_scroll_factor(layer, room, is_background)` —— `[background animation]` 传 `true`（用 `far/middle sight scroll`），`[animation]` 传 `false`（恒 1.0，钉死在世界坐标）。
- **教训**（用户当场纠正）：不要用"全关/全开"来绕过单点问题。

### 3.7 z 分层（100 以内够用）

```
背景 distant/middle  -95 / -90
地砖 / 扩展地砖       -50 / -79
[distantback] -70  [middleback] -65  [bottom] -50  [normal] -40
[closeback]   -35  [close]       -30  [front]   20
角色按 y 0..480
```

判 `*back` 之前要**先判**，因为 `middleback` / `closeback` 字符串里都含 `close`/`middle`，顺序反了就全归一类。

### 3.8 地砖 `[IMAGE]` 的帧号必须走混合 values

`[IMAGE]` 的值是“路径 + 帧号”，`strings()` 会把帧号丢掉，导致 `.til` 里写的 frame 全部变成 0。
gent 的 `imperial_palace_tile00..04.til` 共用 `Imperial_Palace_Tile.img` 的 5 帧，曾全部铺成 00；
修复后渲染日志里能看到 `frame=0..4` 且纹理哈希各不相同。回归：`tests/tile_frames.gd`。

### 3.9 NPC 立绘：`[IMAGE POS]` 之外还要加 NPK 帧画布原点

- **现象**：NPC 名字标签位置差不多，但立绘整体浮空；有的 NPC 又刚好贴地，看起来像“部分动画坏了”。
- **根因**：`.ani` 帧的 `[IMAGE POS]` 是相对 **NPC 画布原点** 的偏移，而画布原点在 NPK 帧的 `rect.position` 里。`NpkStore.texture()` 只返回贴图，把 rect 丢了；`AniSprite` 只加了 `[IMAGE POS]`，所以凡是帧画布原点不为 0 的 NPC 都会偏。
- **证据（holder 为 `map_y` 后的世界坐标，bottom = sprite.pos.dy + 纹理高）**：

  | NPC | NPK 帧 rect | 纹理 | `[IMAGE POS]` | 只加 pos 的 bottom | 加 rect 后 bottom |
  |---|---|---|---|---|---|
  | Seria | `(28,50)` | 51×116 | `(-53,-163)` | -47 | **+3** |
  | PostBox | `(1,1)` | 94×83 | `(-45,-74)` | +9 | **+10** |
  | Grandis | `(203,195)` | 86×127 | `(-259,-315)` | -188 | **+7** |
  | Birken | `(221,187)` | 59×149 | `(-249,-334)` | -185 | **+2** |

- **正确做法**：`AniSprite` 加 `apply_canvas_offset`，只给 NPC 传 `true`：`setup(npc.ani, store, Vector2.ZERO, true, true)` → `_apply()` 里 `fpos += store.frame_rect(img, frame).position`。
- **不要全局改**：装饰层 `[animation]` 在 `RoomBuilder` 里已经加过画布原点，`AniSprite` 再全局加会二次偏移。默认 `false`，谁需要谁开。
- **名字标签**：按首帧 `art_top = first.dy + first_canvas.y` 放在立绘上方；`display_name()` 过滤 `Animation/xxx.ani` 这种被误填进 `[field name]` 的假名字（Storage 就是）。

---

## 4. Godot 引擎层坑

| 现象 | 根因 | 正确做法 |
|---|---|---|
| `--script` 模式里 `class_name` 解析不到（`Nonexistent function 'build' in base 'Nil'`） | 全局类缓存没刷新 | 先跑 `./tools/godot.sh --headless --editor --quit`，再确认 `.godot/global_script_class_cache.cfg` 里有新类 |
| 背景一加，装饰全消失 | `z_index` 超出 `[-4096, 4096]` 被静默拒绝并回落 0 | 用绝对小值（见 §3.7）；怀疑时做像素 diff |
| `The variable type is being inferred from a Variant value` | `Dictionary.get()` 返回 Variant | 显式声明：`var far: int = int(room.sight.get("far", -1))` |
| `Invalid call. Nonexistent 'int' constructor` | 字段存在但没写值 → JSON `null` | `_int_or(v, dflt)` 守卫 |
| `Invalid access to property or key 'left' on a base object of type 'Dictionary'` | 空字典取键 | `is_empty()` + `has()` 守卫 |
| `PackContent.town()` 传路径返回 null | 它收的是**文件 key**（`town_hedonmyre.twn`） | 先 `key_of()`；`map_room()/tile()` 内部自己转 |
| 按 F5/F7/F8 游戏直接退出 | F 键是 **Godot 编辑器**的运行/单步/停止快捷键 | 游戏内调试键一律用符号键（`, . / [ ] \ ; Home`） |
| 画面大片引擎灰、像缺图 | PVF 的 `.map` 不定义背景色 | `RenderingServer.set_default_clear_color(Color(0.05, 0.04, 0.06))`，把"没画"和"没底"区分开 |
| 改完内容包还是旧画面 | 内容包是**离线编译**的静态 JSON | 重跑 `build_pack.py` 并重启游戏 |
| `decompress: Condition "err != 1" ...` 背景局部缺失 | v5 DDS 记录里 `full_length` 是**压缩后**长度，`length` 才是**解压后** DDS 字节数；原代码拿 `full_length*4+64` 当解压上限 | `_dds_frame()` 优先用 `rec["length"]`，没有才回退 `full_length*4+64`；实测 `back_far.img` `full=6686 len=78648`，改后解压成功 |

---

## 5. 工作方式（这一天被用户明确批评过的点，务必记住）

1. **一次只改一个点，改之前先能说清"哪个数据/哪条公式错了"**。用户原话：「你能不要一次改一堆么，有目的改，如果现阶段代码写的不对就改代码，而不是全不动或者全动」。
2. **不要用"全局开关"掩盖单点 bug**。给 `[closeback]` 修漂移，不是"把整个视差关掉"。
3. **不要反复质疑用户给的数值**。用户是"看着原版"给的判断（比如 120px、600 高可见范围、树很大很正常）；我的视觉判断力不如他，应该先用数据把公式摆出来、再用截图验证，而不是猜。
4. **别把调试交互做在会被编辑器抢走的键上**（F 键），也别只留环境变量——用户要能"按一下就看见"。
5. **视觉问题要两条腿走**：一条是数据（帧矩形、画布高、img_pos、公式），一条是截图。只有截图会瞎猜，只有数据会过度自信。
6. **报结论要给可复查的命令**，别只说"改好了"。

---

## 6. 2026-11-25 增量：NPC / 跨城 / 释放

### 6.1 NPC 编译路径要补 `npc/` 前缀

- **现象**：`.npc` 里明明写了 `[field animation] Animation/origin_seria.ani`，按 `.npc` 目录拼却找不到。
- **根因**：PVF 的 NPC 动画实际在 `npc/animation/...`；`.npc` 的引用不带 `npc/`，`Animation/...` 直接拼会 miss。
- **正确做法**：`compile_npc()` 先试 `.npc` 自身目录 + ref，再试 `npc/` + ref；命中后把 `.ani` 编进同一个 `ctx`，运行时 `NpcDef.ani` 直接可用。
- **NPC 名**：`[name]` 是全名（赛丽亚·克鲁敏），`[field name]` 是场景短名（赛丽亚）；`display_name()` 优先短名。

### 6.2 `.twn` 的 area 类型在 `[permission]` 里

- **现象**：centralpark 4 个 area 全变 `normal`，`minimap=None`，`dungeon_gate_ids=[]`。
- **根因**：latest 把 `[gate] 565 234`、`[dungeon gate] 39`、`[minimap rect]` 塞在 `[permission]` 子树；旧 `parse_areas()` 只读 `[area]` 的直接 values。
- **正确做法**：扫 area 子树每个 values 列表，按 `dungeon gate > gate > normal > safe zone > housing > open party list area` 选类型；`args` 只收同一 values 列表里的后续值，别把兄弟 `[need level] 82` 收进来。`[phase]` 只记录，base map 用 area 自身第 2 个值。

### 6.3 跨城：`town_movable` 的 `targetTown` 不能丢

- **现象**：走到中央公园的传送区只在本城切 area，去不了魔界营地。
- **根因**：旧 `_check_town_movable()` 只读第 6 个值 `target_area`，忽略第 5 个 `target_town`。
- **正确做法**：六元组 `(x, y, w, h, targetTown, targetArea)`：
  - `targetTown > 0` 且 != 当前 `town_id` → `content.town_key_by_id(targetTown)` 跨城；
  - `targetTown == -1 && targetArea == -1` → 进副本（取当前 area 的 gate）；
  - `targetTown == -2 && targetArea == -2` → 打开城镇列表；
  - 其余同城切 `targetArea`。
- **城镇 id**：`new_*` 查 `list/town.lst`；旧 `hendonmyre` 不在表里，用所有 area 的 `town_movable` 目标众数推断。不要把 key 当 id。
- **防重弹**：`-2/-2` 的触发区会让玩家站在里面每 0.35s 重开列表；打开时把矩形存进 `_suppress_movable`，玩家离开再清。

### 6.4 原生 PVF/NPK（2026-11-25）

- **运行时不再读** `assets/pvf/world/*.json` 和 `assets/npk-index-latest.bin`；`WorldDirector` 用 `LivePvfContent` 直读 `/mnt/d/dnf_latest/Script.pvf`，`NpkStore.open_live("/mnt/d/dnf_latest/ImagePacks2")` 按路径猜包名。
- **PVF 格式**：外层 AES 段解密后还不是 `nkpi`，要用 `iNfO` 流密码再解 0x30 B；`sk.dat` 是 82 把链密钥；`DNF.exe` 里找 PEM 必须用字节 `find`（`get_string_from_ascii` 会在 NUL 截断）。
- **DDS**：`dds_table.full_length` 是压缩后长度，`length` 才是解压后长度；`decompress` 的 want 用 `length`。
- **NPK 全量扫太慢**：16,392 个包 / 356,895 条要 114 s；`NpkLiveIndex` 只按路径段猜候选包（`sprite_map_npc.npk` → `sprite_map.npk`）。
- **释放**：`NpkStore` 贴图缓存按 800 条 + 64 MB LRU；`LivePvfContent` map LRU 16、ani LRU 256；`_unload_room()` 里 trim。

### 6.5 懒加载与释放：缓存要能裁

- **现象**：换几次城后 `PackContent` / `NpkStore` 只涨不落，旧的房间贴图还占着。
- **正确做法**：
  - `LivePvfContent` 永久缓存 index/towns/dungeons/regions/npcs，地图 LRU 16、ANI LRU 256；
  - `NpkStore` 贴图 800 条 + 64 MB 字节预算，命中移队尾、淘汰队首；
  - `_unload_room()` 直接 `free()` 旧节点（不要只 `queue_free` 等下一帧），并 `trim(320,24)` + `trim_cache(40,80)`；
  - 验收断言：卸载后 `transient <= 40`、`cached_tex <= 320`（见 `tests/world_ui.gd`）。

### 6.6 相对路径与背景层（2026-11-25）

- **相对路径 `..` 必须先拼接、后折叠**：gent 的 `../../Town/Gent/Animation/Lowwall.ani` 是相对 `map/cataclysm/town/gent/` 的；先 `_norm(rel)` 会把开头的 `..` 当根路径丢掉，48 条引用全部误报 MISSING。正确顺序是 `_norm(base_dir + raw)`，`_resolve_rel()` 已按这个改。
- **`[background animation]` 的文件不在 values 里**：它下面每个 `[ani info]` 才有 `[filename]`/`[layer]`/`[order]`。只读 `[background pos]` 会让 `background_anims` 永远为空，表现是天空黑。
- **背景视差**：同时读 `[far sight scroll]`/`[middle sight scroll]` 到 `room.sight`，否则 Builder 里 `_scroll_factor()` 永远返回 1.0。
- **`gate_hendon` 这类图没有背景数据**，天空黑是数据本身；gent 的 `[background animation]` 有两个 `[ani info]`，接完就能出远景。
- 缓存单位别混：`MAX_TEX=800` 是条数，`MAX_TEX_BYTES=64 MB` 是字节，`MAX_IMG=48` 是 Img 条数；`MAX_TRANSIENT=64` 不是 `LivePvfContent` 的房间硬上限（`_map_cache` 是 16）。详见 `game/world/README.md` 的“缓存数字别混”。

## 7. 快速复查清单

```bash
# 1) 原生路径：不需要重编内容包，直接读 Script.pvf / ImagePacks2
#    路径常量在 game/world/flow/world_director.gd 顶部
#    （旧 build_pack.py 只用于对照 token 解析）

# 2) 逻辑冒烟（657 项：128 城镇全部 area 装载）
cd client/
XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=$PWD \
  /home/sunmingze/dnf_like/tools/godot.sh --headless --script res://tests/world_smoke.gd
#  手感：res://tests/world_walk.gd（城镇 8 通过；副本 2 失败，待接 .dgn）
#  UI/跨城/释放：res://tests/world_ui.gd（25 项）

# 3) 视觉验证（非 headless，WSLg）
DNF_NPK_LATEST="/mnt/d/WeGameApps/rail_apps/地下城与勇士：创新世纪(1)/ImagePacks2" \
XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=$PWD \
  /home/sunmingze/dnf_like/tools/godot.sh --script res://tests/world_shot.gd \
  -- --out=/tmp/a.png --town=town_hendonmyre.twn --area=1
#  城镇列表：加 --ui=1；副本：--dungeon=dungeon/act2/darkentrance.dgn --cell=0,1

# 4) 在游戏里：M 城镇列表 / 点行传送 / 走 town_movable 跨城 / E 进副本 / Esc 回城 / , . 微调装饰 y / [ ] \ 诊断层
```

> **注意**：世界运行时用的是 `WorldDirector.NPK_DIR`（latest 客户端），不是 `project.godot` 的 `npk/latest_dir`；
> 改客户端目录要改常量。`NpkStore.new()` 不带参数时仍会回退 sf85 旧目录，别在 world 里这样用。

### 6.7 原生加载器半成品核对（2026-11-25）

- `[import script]` 的 `Common/Gate_Seria.map` 是 `(f)/(r)` 变体，不是字面路径；`_resolve_import()` 已补。修完后 audit 的 `no_tiles` 从 49 降到 0，但 gate 图仍是 `dummy.til`（`img=""`），地面/背景仍黑。
- `[NPC]` 不是固定 5 元组：条件标签（`[visible on dungeon if quest clear]`）插在方向前，必须按 `id → 条件标签 → 方向 → x y z` 扫。修完后 `temporarycamp` 的 id=0 消失；剩余缺失 NPC 是 `npc.lst` 里确实没有的 ID，不要再当解析错位。
- `RoomBuilder` 的 `BLOCK_W=224` 只覆盖主流地砖；实际存在 240（`bar06`）、218（inae waitingroom）、1（airship dummy）。这是“拼接”类问题的明确来源之一，统一位置时要一起处理。
- `[phase]` 仍是未实现；audit 里 `phase=0`，不要用它判断地图缺失。
- 空 `anim`/`bg` path 是资源找不到，不是五元组错位；`jelva/2_jelva_waiting.map` 第一条原始 ref 是 `Animation/chn_dragon_zone_light_left.ani`，三个候选路径都不存在。


## 6.8 通行 0/2、行序、图层提升上限（2026-11-25）

- `[pass type]` 的 **0 可走、2 阻挡**；`PassGrid` 缺图/缺列初始化成 2，`walkable()` 只认 0。旧实现按“0=阻挡”写，和原版 `sf85/room.gd:347` 相反。
- 同一个错误里还有行序：`PassGrid.build()` 原先把 PVF 行序翻成 `rows-1-r`，导致地面上下颠倒、出生点在半空；现在用 `vy = y_off + r`，按图像自上而下。
- 实证：`hendon_city` 图顶部 3 行全 2、底部 2-3 行全 0；修正后出生 `(1912.0,461.6)`、可走率 57%；`world_walk` 仍能向右 dx=147.3、向上 dy=-73.7。
- 图层提升 `closeback` 的 z 上限 = `min(player.z-1, 房间内带 meta("actor") 的最小 z - 1)`；不要只按玩家 z 算，否则会盖住 NPC/怪物。hendon_city 实测 NPC 最小 z=270、提升后 269。
- 角色层：`move.ani` / `stay.ani` 只给 body；五个 avatar NPK 图同帧号可叠层（skin/pants/shoes/coat/hair），但 `.equ` 引用的 `equipment/character/swordman.lay` 在 latest PVF 中不存在，不能按旧 `.lay` 合并。


## 6.8 DDS fourCC 偏移导致背景整层黑（2026-11-25）

- 现象：`lufthafen` 的 `lufthafent_market.map` 原始 `[background animation]` 有
  `far2.ani` / `middle.ani`，解析出的 `background_anims=2`、路径也都存在，但画面上半屏是黑的。
- 根因：`utils/npk/npk_image.gd` 的 `_decode_dds()` 把 fourCC 读在偏移 `20..24`，
  实际 DDS 头 fourCC 在 **84..88**（magic 0、dwSize 4、flags 8、height 12、width 16、
  pitch 20、mip 28、ddspf 76、fourCC 84）。DXT1/DXT5 因此全部识别失败，
  `_decode_dds()` 返回空，`_dds_frame()` 退化成 `_placeholder()` 的 1×1 透明图。
- 证据：修复前 `store.texture("Map/Act8/background/far.img", 0)` 是 `(1,1)`；
  修复后 `(556,489)`；截图 `/tmp/lufthafen_market2.png` 顶部非黑像素从 34.8% 变 64.8%。
- 修复：`fourcc := blob.slice(84, 88)`；同时接受 `DXT2/4`（按 DXT3/5 解）。
- 回归：`tests/npk_dds.gd`（2 项）；`world_smoke 657`、`world_ui 37`、`world_entities 12`。
- 全量背景扫描（128 城镇、489 张唯一 map）：`background_anims` 共 413 条，修复后
  `tex-1x1` 为 **0**；剩余 25 条是数据问题，不是解析/缓存：
  - 24 条空路径：`contents/2022/noblessecode/map/town/rokeren/27..38.map` 引用了
    `Animation/far.ani` / `middle.ani`，PVF 里只有同目录的 `Back_Far/Back_Middle`；
    后者能正常解析。
  - 1 条缺 NPK：`commonmap/town/220113_dungeonandlife/dungeonandlife_main.map` 的
    `Animation/D_L/bg_1.ani` 指向 `Contents/2021/D_L/bg.img`，`NpkLiveIndex.find` 未命中。

## 6.9 DXT3/DXT5 颜色从 alpha 块读、DXT1/5 alpha 公式错（2026-11-26）

- 现象：修完 DDS fourCC 后，背景能出图了，但仍有一批资源图颜色不对；部分 DXT3/DXT5
  贴图整块颜色错乱，DXT1 透贴边缘变黑边，DXT5 半透明边缘发硬。
- 根因（对照 `tools/npk_inspector/core/npk_core.js` 才暴露）：
  1. `_dxt()` 不管 mode 都从 `src[p]` 读颜色端点 c0/c1；DXT3/DXT5 的 alpha 块在前
     8 字节，颜色块在 `p+8`，所以颜色是从 alpha 块读出来的。
  2. DXT1 的 `c0<=c1` 表里索引 3 是透明；原代码 alpha 恒 255（黑边）。
  3. DXT5 alpha 表原代码用 `/6` 且索引偏移错；标准是 `a0>a1` 用 `/7`、`a0<=a1`
     用 `/5` 并补 0/255。
  4. 未压缩 DDS（`blob[:4]=="DDS "`、无 DXT fourCC）原代码没跳过 128B 头，
     直接把头当像素；应按 bits + masks 解。
- 修复：颜色块 `cbase = p if mode==1 else p+8`；DXT1 透明；DXT5 标准 alpha 表；
  颜色插值用 `round` 对齐 JS；新增 `_dds_uncompressed()`。
- 证据：`Map/Gent_afterwar/GentTile.img`（DXT5）与 `Map/Act8/background/far.img`
  （DXT1）的 RGBA SHA-256 与 JS NPK Inspector 完全一致。
- 回归：`tests/npk_dxt.gd`（14 项）；`npk_dds 2`；`world_ui 37`；`world_entities 12`。
- 批量扫描：128 城镇 489 图引用到的 4,343 个 IMG/帧，4,338 个可解码；
  18 个异常中 13 个是原始 1×1 空帧，5 个是 `NpkLiveIndex` 未命中的缺图，
  不是 DXT 解码失败（详见 `dnf_like/data/debug/npk_scan.log` 的运行输出；
  `SeriaGate_Library` 的大小写路径重复出现，所以 18 条里有重复项）。

## 6.10 大 DDS 逐像素解码卡主线程（2026-11-26，wahrheit）

- 现象：进 `commonmap/town/220113_110levelexpansion/wahrheit/wahrheit.map` 卡顿，动画播放时主进程一阵一阵停，渲染掉帧。
- 根因：`NpkImage._dds_frame()` 先解 DDS 成 RGBA，再走 `_dxt()` 逐像素解 DXT，GDScript 每帧 100–560ms；`wahrheit` 有 21 个动画（Cloud/Gear_Big/Barrier 等大图），全帧合计 49.1s。
- 修复：`npk_image.gd::_dds_frame()` 改为 `Image.load_dds_from_buffer(blob)` 原生解码；压缩格式先 `decompress()` 再 `convert(FORMAT_RGBA8)`，按帧 `left/up/right/down` 裁剪。GDScript 仅兜底。
- 证据：同一探针，全帧 49,147ms → 471ms；单帧最差 563ms → 34ms；`RoomBuilder.build()` 3,073ms → 282ms。
- 回归：`tests/npk_dds.gd` 6 项（Cloud/Gear_Big/Barrier/Bottom_Close 尺寸）。
