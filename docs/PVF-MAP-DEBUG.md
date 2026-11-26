# 地图加载逻辑与调试协议（2026-11-25）

> **先看这一句**：下面写的是**当前实现**，不是已经被证明正确的规则。
> 2026-11-25 的截图里，我把“NPC 贴地/位置正常”当成结论报给你，这个结论**作废**。
> 从这份文档开始，视觉验证由你判断；我只负责说明「这一步在验证什么、看哪里、什么现象算反证」。

---

## 0. 两个必须先承认的事实

### 0.1 地图确实不全

- PVF 的 `list/town.lst` 有 **129 个城镇**。
- 当前原生 `LivePvfContent` 已现场解析 **128 个**城镇（旧 JSON 包只有 4 个，仅对照）：

  | key | id | 中文名 |
  |---|---|---|
  | `town_hendonmyre.twn` | 2 | 赫顿玛尔 |
  | `town_centralpark.twn` | 31 | 中央公园 |
  | `town_metrocenter.twn` | 30 | 魔界营地 |
  | `town_devildom_contact.twn` | 35 | 魔界集结地 |

- 当前 `counts`：`towns=4, dungeons=6, maps=76, tiles=99, anis=450, objects=99, regions=164, npcs=56`。
- 旧 JSON 内容包只传了 4 个 `--town`，所以看起来“地图不全”；现在 `LivePvfContent` 现场解析 `list/town.lst`，装满 128 个有可读地图的城镇。
- 副本同样只编了 6 个，不是全量。

### 0.2 位置没有被逐层验证过

当前所有位置都是按 PVF 字段推算的，至少混合了这些坐标来源：

- `.til` 的 `[pass type]` 行序（从下往上）
- `.map` 的怪物/NPC/物件 `y`（距下沿高度）
- `.map` 的 `[animation]` 的 `(x, y)`（画面系，y 向下）
- `.map` 的 `[town movable area]`（当前代码直接当屏幕矩形用，**没有翻 y**）
- NPK 帧的 `rect.position`（画布原点）
- `.ani` 帧的 `[IMAGE POS]`（相对画布原点）
- `[img pos]`（地砖画布顶部空白）
- `RoomBuilder.y_shift = 120`（装饰层固定偏移）

这些不是同一套坐标。只要有一处方向反了，整层就会“看起来像差了几十像素”。所以下面每一步都要单独验证，不合并。

---

## 1. 端到端加载链

```
analysis/pvf-new/pvf34.sqlite
        │
        │  tools/pvf_new_extract.py（离线，旧路径）
        ▼
assets/pvf/world/{index,towns,dungeons,maps,tiles,anis,objects,regions,npcs}.json
        │
        │  LivePvfContent（运行时直接读 Script.pvf）
        ▼
WorldDirector.enter_town / enter_dungeon
        │
        ▼
RoomBuilder.build
  ├─ Background   [background animation]
  ├─ Tiles        基础地砖 + 扩展地砖
  ├─ Deco         [animation] 墙/门/花草
  ├─ Objects      [passive object] → .obj → .act → .ani
  ├─ Gates        [pathgate pos]
  └─ Actors       [monster] / [NPC]
        │
        ▼
PassGrid（通行网格） + WorldPlayer + Camera2D
```

### 1.1 编译侧步骤

| 步 | 代码 | 输入 | 输出 | 关键规则 |
|---|---|---|---|---|
| C0 | `LivePvfContent.load_index()` | `list/town.lst` | 全量城镇列表 | 现场扫 129 个注册项，过滤无地图/坏图 |
| C1 | `load_id_list()` / `compile_town()` | `list/town.lst` + `.twn` | `towns/<key>.json` | `.twn` 的 `[area]` map 引用统一转 `'map/' + lower(ref)` |
| C2 | `parse_areas()` | `.twn` 的 `[area]` 子树 | areas 数组 | 递归 `[permission]`；类型优先级 `dungeon gate > gate > normal > safe zone > housing > open party list area`；`args` 只收同一 values 列表 |
| C3 | `compile_region()` | `region/*.rgn` | `regions/<key>.json` | `[towns]` 只用于分组/显示，不参与运行时邻接 |
| C4 | `compile_map()` | `.map` | `maps/<key>.json` | 解析 tiles/extended/NPC/monster/objects/anims/pathgate/town_movable；`[import script]` 只填空题 |
| C5 | `compile_tile()` | `.til` | `tiles/<key>.json` | `rows = pass 数 / 14`；`img_pos` 原样存；`pass` 行序保持 PVF 顺序（第 0 行 = 图下沿） |
| C6 | `compile_ani()` / `compile_npc()` | `.ani` / `.npc` | `anis/`、`npcs/` | NPC 的 `[field animation]` 先相对 `.npc`，再试 `npc/` 前缀 |
| C7 | `StringTable` | `list/n_string.lst` + `*.chn.str` | 名字纯文本 | `8=Npc`、`14=Town`、`19=Region`；`<8::name_1915>` 在编译期解析 |
| C8 | 写 `index.json` | 以上 | `towns/towns_by_id/regions/npcs/counts/problems` | 城镇 id：`town.lst` 查不到时，用 `town_movable` 目标 town 众数推断 |

**编译侧第一个要确认的点**：`index.counts.towns` 是不是你以为的数量。不是的话，先改编译参数，不要看画面。

### 1.2 运行时步骤

| 步 | 代码 | 输入 | 输出 | 关键规则 |
|---|---|---|---|---|
| R0 | `WorldDirector._ready()` (`world_director.gd:54`) | `PACK_ROOT` | `PackContent` / `NpkStore` / `RoomBuilder` | 默认城镇取 `index.towns[0]`，可用 `WORLD_TOWN` 覆盖 |
| R1 | `enter_town(key, area)` (`:98`) | 城镇 key | 设置 town/mode | `area=-1` 时用 `_default_area()`，从第一个“有图且有地砖”的 area 开始 |
| R2 | `enter_town_area(i)` (`:119`) | area 下标 | 目标 map 路径 | `_area_usable(i)` 失败时 `_next_area_with_map()` 向后回退，并打日志“area X 缺图，退到 area Y” |
| R3 | `_load_room(map_path)` (`:330`) | map 路径 | `room` / `grid` / 节点 | `content.map_room` → `tiles_for` → `_unload_room` → `builder.build` |
| R4 | `RoomBuilder.build()` (`room_builder.gd:55`) | `MapRoom` + tile defs | `{node, pass, actors}` | 顺序：Background → Tiles → Deco → Objects → Gates → Actors |
| R5 | `PassGrid.build()` (`pass_grid.gd:22`) | tiles | 通行网格 | `cols = tiles*14`，`rows=max(t.rows)`，`height=rows*16`；地砖底边对齐 |
| R6 | `grid.spawn_at()` (`pass_grid.gd:76`) | 边缘参数 | 玩家出生点 | 默认底边中央，`_nearest_walkable()` 找最近可走格 |
| R7 | `_update_camera()` (`world_director.gd:403`) | 玩家 + grid | 相机位置 | 房间比视野矮时贴底；大房间按玩家 y-110 跟随 |
| R8 | 每帧检查 (`:200`) | 玩家位置 | 换图/换 area | `[town movable area]` → `_check_town_movable`；城镇边缘 → `_check_town_edge`；副本边缘 → `_check_dungeon_edge` |

---

## 2. 当前所有位置公式（逐条列出来，方便你指哪条错了）

### 2.1 通行网格

```gdscript
cols = tiles.size() * 14
rows = max(tile.rows)
height = rows * 16.0
y_off = rows - tile.rows          # 不同高度的地砖按底边对齐
for r in tile.rows:
    vy = y_off + (tile.rows - 1 - r)   # PVF 行序 -> 屏幕行序
    cells[vy * cols + ...] = tile.pass_at(c, r)
```

- 输入：`maps/<key>.json` 的 `tiles`、`tiles/<key>.json` 的 `rows/pass`。
- 当前假设：PVF 的 `[pass type]` 第 0 行贴图下沿，所以要翻转。
- 反证：如果可走格覆盖了墙面、或者地面不能走，就是这里或 `pass_at` 的列序错了。

### 2.2 基础地砖

```gdscript
s.position = Vector2(
    i * 224.0 + rect.position.x,
    grid.height - rect.size.y
)
```

- `rect = store.frame_rect(tile.img, tile.frame)`。
- 当前假设：地砖美术的**底边**对齐网格底边；`[img pos]` 是画布顶部空白，所以**不**加进 y。
- 注意：这里没有用 `rect.position.y`，只用了 `rect.size.y`；如果某张图的帧底边不在画布底边，这层就会错。
- 反证：地砖之间出现横向错位/整体悬空/整体压到画面外。

### 2.3 扩展地砖

```gdscript
es.position = Vector2(
    i * 224.0 + erect.position.x,
    grid.height + GROUND_GAP      # GROUND_GAP = 0
)
```

- 当前假设：扩展地砖的**顶边**贴基础地砖下沿，所以从 `grid.height` 往下排。
- 反证：扩展层和基础层之间出现黑缝或重叠。

### 2.4 装饰 `[animation]`

```gdscript
y = d.y + y_shift - d.z           # y_shift = 120
canvas = store.frame_rect(first_frame.img, first_frame.frame).position
anchor = Vector2(d.x, y) + canvas
AniSprite.position = anchor
# AniSprite 内部再加该帧的 [IMAGE POS] (dx, dy)
```

- 当前假设：`[animation]` 的 `(x, y)` 是**画面系**（y 向下），不翻 y；`y_shift=120` 是原客户端 600 高可见画面的固定差值。
- 反证：墙/门整体比地砖高/低 120px，或左右错开一个画布原点。

### 2.5 背景 `[background animation]`

```gdscript
bg_y = frame_rect.position.y + room.background_pos + _bg_dy
x = -1152 + i * frame_width        # 横向平铺
```

- 当前假设：背景层的锚点是帧画布 y + `[background pos]`，不是帧的 `[IMAGE POS].dy`。
- 反证：远景被顶到房间顶、街道上方空一条黑带、背景左右露边。

### 2.6 怪物 / NPC / 物件

```gdscript
bottom = grid.height + tile.img_pos   # tile 取 x 所在列
world_y = bottom - raw_y

# NPC 额外：
holder.position = (x, world_y)
AniSprite.apply_canvas_offset = true
sprite.position = [IMAGE POS] + frame_rect.position
```

- 当前假设：`.map` 的 `raw_y` 是“距该列地砖画布下沿的高度”，画布下沿 = `grid.height + img_pos`。
- 当前假设：NPC 的 `[IMAGE POS]` 要再加 NPK 帧画布原点；装饰层已经加过，所以只给 NPC 开。
- 反证：NPC 站在墙里/半空、名字在头顶但人不在脚下、同一张图里有的 NPC 对有的不对。

### 2.7 门 `[pathgate pos]`

```gdscript
p.y = map_y(room, grid, defs, p.x, p.y)
r.position = p - Vector2(14, 14)
```

- 当前假设：`[pathgate pos]` 的 y 与怪物/NPC 同一套“距下沿高度”。
- 反证：门色块出现在房间顶部/底部之外。

### 2.8 城镇触发区 `[town movable area]`

```gdscript
rect = Rect2(x, y, w, h)          # 当前代码直接用
if rect.has_point(player.position): ...
```

- **当前假设：这 4 个数已经是屏幕坐标（y 向下）。**
- 这是我最不放心的一条：如果它其实和怪物/NPC 一样是“距下沿高度”，那么所有传送区都会上下镜像，表现为“走到门口没反应/在别处触发”。
- 反证：把玩家放到已知门口，触发区不亮；或 `_debug_boxes` 画出的框和可见门口上下相反。

### 2.9 玩家出生 / 相机

```gdscript
spawn = grid.spawn_at("center")   # 底边中央最近可走格
camera.zoom = 648 / VIEW_WORLD_H  # VIEW_WORLD_H = 480
```

- 当前假设：城镇默认从底边中央进入；一屏世界高 480，正好一个房间。
- 反证：玩家出生在墙里/画面外；房间底部被裁掉；人物比例和原版差太多。

---

## 3. 当前已知的高风险点（按怀疑程度排序）

1. **`[town movable area]` 的 y 方向没有转换**。这是“位置不对”最可能直接造成玩法异常的一条。
2. **`map_y` 的 `+ img_pos` 和 `grid.height`**。`img_pos` 是地砖画布顶部空白，但怪物/NPC 的 `raw_y` 到底相对“画布下沿”还是“网格下沿”，没有用第二张图交叉验证过；另外 `map_y` 用的是整间房的 `grid.height`，不是该列地砖自己的底边（混合高度时可能差 `y_off`）。
3. **地砖只用了 `rect.size.y`，没用 `rect.position.y`**。如果帧内容底边不等于画布底边，基础地砖会错。
4. **`x` 落列用 `floor(x / 224)`**。玩家/怪物正好站在块边界时，取的 `img_pos` 可能属于左边那块。
5. **`y_shift=120` 对所有 `[animation]` 一刀切**。不同地图/不同图层是否都该 +120，没有逐图验证。
6. **背景的 `[background pos] + _bg_dy`**。现在只按一张图的观感调过，没做多图回归。
7. **NPC 画布原点只抽查了 4 个 NPC**（Seria/PostBox/Grandis/Birken），其余 52 个没验。
8. **城镇已到 128 个，副本仍走旧路径失败**；UI 覆盖 128 个城镇。

这些点在第 4 节会一项一项拆开验证，不合并改。

---

## 4. 分步调试协议（每步一停，等你反馈）

### 4.0 图片验证的固定格式

以后每张图，我先写这段，再发图：

```
我在验证：<哪个步骤 / 哪条公式>
图：<路径>（town=…, area=…, frames=…，以及用到的 WORLD_* 环境变量）
预期：<对象> 应该出现在 <相对位置/像素/方向>；<尺寸/朝向/层次>
反证：如果看到 <现象>，说明 <哪一步> 错了
本图不看：<背景/装饰/角色/UI 中不参与本次验证的部分>
```

然后**只等你判断**：

```
你的判断：[ ] 对   [ ] 不对
不对的地方：<一句话，指对象或方向即可>
```

我不自己打勾，也不在你说“对”之前继续下一步。你说“不对”后，我只改与这一步相关的一个点，再重新发同一角度的图。

### 4.1 Step 0：只核对数据规模，不看图

**验证什么**：原生 PVF 解析出的城镇是不是你以为的范围。

命令：

```bash
cd /home/sunmingze/dnf_like
python3 - <<'PY'
import json
# 旧命令，仅对照；原生路径看 LivePvfContent.index 或 world_smoke 输出
d = json.load(open('dnf_like/assets/pvf/world/index.json'))
print('counts', d['counts'])
print('towns', [(t.get('id'), t.get('key') or t.get('path')) for t in d['towns']])
PY
```

预期：`towns=4`，和你看到的“地图不全”一致。

**停**：全量已经扩到 128 个；下一步只调赫顿玛尔 area 1 的坐标，确认一组正确值后再抽查其它城镇。

### 4.2 Step 1：只核对一张图的原始数据，不看图

**验证什么**：赫顿玛尔 area 1 的 map/tile/坐标原始值是否自洽。

```bash
python3 - <<'PY'
import json
t = json.load(open('dnf_like/assets/pvf/world/towns/town_hendonmyre.twn.json'))
a = t['areas'][1]
print('area', a)
m = json.load(open('dnf_like/assets/pvf/world/maps/map_hendonmyre_hendon_city.map.json'))
print('tiles', len(m['tiles']), m['tiles'][:3])
import re
for p in m['tiles'][:1]:
    key = re.sub(r'[^a-z0-9._-]+', '_', p.lower())
    print('tile json', key)
    print(json.load(open('dnf_like/assets/pvf/world/tiles/' + key + '.json')))
print('npcs', m['npcs'][:3])
print('town_movable', m['town_movable'][:12])
PY
```

**停**：你确认「area 1 就是你想先调的那张图；数据里的 tile 数/rows/img_pos 和你预期一致」。

### 4.3 Step 2：只验证地砖层

**验证什么**：只看地砖落点，不看装饰/NPC/背景。

命令（先关装饰；背景目前没有开关，会留在图里，作为“本次不看”的部分）：

```bash
cd /home/sunmingze/dnf_like
export DNF_NPK_LATEST="/mnt/d/WeGameApps/rail_apps/地下城与勇士：创新世纪(1)/ImagePacks2"
export XDG_DATA_HOME="$PWD/.tmp_udata"
export GODOT_PROJECT="/mnt/e/godot_proj/dnf_like"
WORLD_NO_DECO=1 WORLD_DEBUG_GRID=1 \
  ./tools/godot.sh --script res://tests/world_shot.gd -- \
  --out=/tmp/step2_tiles.png --town=town_hendonmyre.twn --area=1 --frames=35
```

**我要你看的**：地面砖块之间有没有横向错位、整排有没有悬空/压到画面外；绿色/红色通行格是否盖在可见地面上。

**反证**：砖缝不连续、地面整体高/低一截、可行走格落在墙面上。

**停**：等你判断。若不对，我只查 `_build_tiles()` 或 `map_y()` 中的一条，不同时改。

### 4.4 Step 3：只验证通行网格

**验证什么**：`PassGrid` 的行序翻转是否和地砖画面一致。

- 图同上（`WORLD_DEBUG_GRID=1`）。
- 我要你看的：可走格（通常是绿色）是否只覆盖地面、不覆盖墙面；玩家出生点是否在可走格内。
- 反证：可走区上下颠倒、覆盖整面墙、玩家出生在墙里。

**停**：等你判断。若反了，只改 `PassGrid.build()` 的 `vy` 一行。

### 4.5 Step 4：只验证装饰/背景锚点

**验证什么**：`[animation]` 的 `y_shift=120` 与 NPK 画布原点，是否让墙/门/建筑和地砖对齐。

```bash
WORLD_DEBUG_BOXES=1 ./tools/godot.sh --script res://tests/world_shot.gd -- \
  --out=/tmp/step4_deco.png --town=town_hendonmyre.twn --area=1 --frames=35
```

- 我要你看的：建筑底边是否压在地砖上沿；门/牌坊是否在正确街道位置；`_debug_boxes` 的框是否与可见物件同位。
- 反证：建筑和街道之间黑带、整体高/低 120px、左右差一个画布原点。

**停**：等你判断。若不对，只查 `_build_deco()` 的 `y` 或 `canvas`。

### 4.6 Step 5：只验证 NPC/怪物/门

**验证什么**：`map_y()` 的 `+img_pos`、NPC 的 `frame_rect.position` 是否让角色脚底落在该列地面上。

- 图：`/tmp/step5_actors.png`，用 `WORLD_DEBUG_BOXES=1` 标出原始落点。
- 我要你看的：每个 NPC 的脚底是否在地面；头顶名字是否在立绘上方；怪物/门是否与 NPC 同一套 y。
- 反证：NPC 悬空、陷进地面、名字在脚下、同一张图里有的对有的不对。

**停**：等你判断。若不对，先只改 `map_y()`，不动 NPC 的画布原点；反之亦然。

### 4.7 Step 6：只验证出生点/相机

**验证什么**：`grid.spawn_at("center")` 和 `_update_camera()` 是否把玩家放在可见地面的底部中央。

- 图：普通 `world_shot`，不加诊断层。
- 我要你看的：人物是否在画面底部中央、脚是否踩地、房间底边是否被裁。
- 反证：人物在墙里/画面外、房间底部黑带、人物比例明显不对。

**停**：等你判断。若不对，只调 `spawn_at()` 或 `VIEW_WORLD_H` 其中之一。

### 4.8 Step 7：只验证城镇触发区

**验证什么**：`[town movable area]` 的矩形方向。

- 图：`WORLD_DEBUG_BOXES=1` 下的城镇门口；或你在游戏里走到门口。
- 我要你看的：调试框是否和可见门口重合；走进去是否触发对应 area。
- 反证：框在门口上下镜像、走到门口没反应、在别处触发。

**停**：等你判断。若方向反了，只改 `_rect_groups()` / `_check_town_movable()` 的 y 转换。

### 4.9 Step 8：最后才扩城镇

只有在 Step 2–7 里你确认“这张图的坐标逻辑对”之后，才把 `--town` 扩到全部 129 个；否则只是把同一个错误复制到更多图。

---

## 5. 我不再做的事

1. 不再用“我看图觉得贴地了”当结论。
2. 不再一次改多个坐标公式。
3. 不再在你说“对”之前继续下一步。
4. 不再把“测试通过”当成“视觉正确”；`world_smoke` 只证明能装载，不证明位置对。
5. 不再把“4 个城镇能走”说成“城镇拓扑走通”；现在 128 个已装载，但坐标仍未逐层确认。

---

## 6. 当前进度

- [x] 加载链梳理（本文档）
- [x] Step 0：范围已确认（原生路径 128 个）
- [ ] Step 1：确认第一张调试图的数据
- [ ] Step 2：地砖层
- [ ] Step 3：通行网格
- [ ] Step 4：装饰/背景
- [ ] Step 5：NPC/怪物/门
- [ ] Step 6：出生点/相机
- [ ] Step 7：城镇触发区
- [ ] Step 8：扩城镇

**下一步**：从 Step 2 开始，只调赫顿玛尔 area 1；每一步等你按“验证什么”的判断回“对/不对”再继续。

---

## 7. 调试规范（2026-11-25，用户 m02005 定）

以后每次调新功能，先做“可复查的 dump”，再谈改代码。

### 7.1 先 dump 到独立目录

工具：`tests/dump_twn.gd`。

```bash
export XDG_DATA_HOME=$PWD/.tmp_udata
export GODOT_PROJECT=/mnt/e/godot_proj/dnf_like
./tools/godot.sh --headless --script res://tests/dump_twn.gd -- \
  --town=town/gent.twn --out=/home/sunmingze/dnf_like/data/debug/gent
```

- 输出目录按城镇名区分，例如 `data/debug/gent/`，不要覆盖上一次。
- 每个引用文件同时留两份：`.bin` 是原始字节，`.txt` 是 `PvfNewDoc.to_text()` 的树形文本。
- `report.md` 至少要有：areas、每个引用的文件与解析结果、MISSING、未登记 label、dump 文件清单。

### 7.2 按树逐层核对

1. `.twn` 原始树：`[area]` 数量、每个 area 的 base map、`[phase]`、`[permission]`、`[minimap rect]`、`[dungeon gate]`。
2. 每个 area 的 `.map`：`[tile]`、`[extended tile]`、`[background animation]`、`[background pos]`、`[town movable area]`、`[town movable area with animation]`、`[virtual movable area]`、`[NPC]`、`[animation]`、`[monster]`、`[passive object]`、`[import script]`。
3. 每个 `.til`、`.ani`、`.npc`：字段、子节点、引用的 NPK 路径。
4. 对每个引用记录：原始字符串、所在文件、base_dir、尝试过的候选路径、规范化路径、是否真实存在。
5. 对照当前解析器：`已实现` / `没有逻辑` / `字段对不上` 三栏。**不猜，不擅自跳过。**

### 7.3 找不到的路径

不能标一句 MISSING 就过去。必须写清：

- 原文是什么，相对哪个文件；
- `..`、大小写、`map/` 前缀、斜杠方向分别试过什么；
- 规范化后的路径在 PVF 里是否存在；
- 如果存在，是解析器的路径解析 bug；如果不存在，才是资源缺失。

这类判断在动手前交给用户确认。

### 7.4 图片验证

每张图先写“验证什么、看哪里、什么现象算反证、这张图不看什么”，然后停，等用户判断“对/不对”。不再用“我觉得贴地了”当结论。

---

## 8. gent 审核结果（2026-11-25，未改代码）

数据来源：`data/debug/gent/report.md`、`data/debug/gent/*.txt`。

### 8.1 已确认可用

- `town/gent.twn` 6 个 area 的 base map 都有字节。
- a0 `gent_workshop.map`：14 个 `[tile]` 指向 `Tile/GentTile.til`，扩展层 `Tile/GentTileEx.til`；两者都找到。
- 4 个 NPC（58 zeldin、59 melvin、362 bhan_gent、562 jurgen）的 `.npc` 和 `[field animation]` 都找到。
- `[animation]` 共 65 条；dump 记录 150 条 `[ani]` 引用，其中 48 条 MISSING（12 个唯一文件，见 8.2）。

### 8.2 根因：相对路径没有折叠 `..`

48 条 MISSING 全部长这样：

```text
../../Town/Gent/Animation/Lowwall.ani
../../Town/Gent/Animation/Gent_dock/gent_sign.ani
```

它们来自 `map/cataclysm/town/gent/gent_workshop.map` 和 `gent_dock.map`。按 `..` 折叠后应是：

```text
map/cataclysm/town/gent/animation/lowwall.ani
map/cataclysm/town/gent/animation/gent_dock/gent_sign.ani
```

这两个路径在 PVF 里 **存在**（`archive.has` 为 true）。当前 `_norm()` 不折叠 `..`，`_resolve_rel()` 又只拼未规范化的字符串，所以返回空；受影响的是 `Lowwall`、`Pinetree`、`Guild`、`Roadlamp`、`Gent_dock` 的招牌/墙/灯等装饰。

这不是“资源缺失”，是**解析器的路径 bug**。

**2026-11-25 已修**（只改路径解析）：

- `_norm()` 现在按 `/` 分段折叠 `.` 和 `..`；
- `_resolve_rel()` 改为“先和 base_dir 拼接，再 `_norm()`”，避免先规范化相对路径时把开头的 `..` 当根路径丢掉；
- 重新 dump：`data/debug/gent_after_path/report.md`，150 条 `[ani]` 引用，**MISSING 0**；
- `world_smoke` 657/0、`world_ui` 25/0；
- 截图 `/tmp/gent_after_path.png`（1152×648，785349 B）。这张图只用于确认“缺失的装饰是否回来了”，不证明整体位置正确；当前裁切里肉眼差异很小，但 `tex` 从 60 变 64，说明有新增纹理被装载。

### 8.3 背景不是空的，是没解析

`gent_workshop.map` 的 `[background animation]` 不是空节点，它有两个 `[ani info]`：

```text
[background animation]
    [ani info]
        [filename] Animation/GentFar.ani
        [layer] [distantback]
        [order] [below]
    [ani info]
        [filename] Animation/GentMid.ani
        [layer] [middleback]
        [order] [below]
```

当前 `_compile_map()` 原先只读 `[background pos]`，`background_anims` 一直是空数组。天空黑不能归因于“原图没有背景”，而是这个子树没有逻辑。

**2026-11-25 已接**：

- 解析 `[background animation]` 下的每个 `[ani info]`，取 `[filename]`、`[layer]`、`[order]`；
- 路径用 `_resolve_rel(base_dir, filename)`，`GentFar.ani`/`GentMid.ani` 都解析到 `map/cataclysm/town/gent/animation/`；
- 同时解析 `[far sight scroll]`/`[middle sight scroll]` 到 `room.sight`，Builder 的 `_scroll_factor()` 才会生效；
- 截图 `/tmp/gent_bg.png`（1152×648，994588 B）已出现远景建筑/天空；这张图只证明背景层被装载，不证明背景位置就是原客户端正确位置。

### 8.4 漏掉的城镇传送

`gent_workshop.map` 还有：

```text
[town movable area with animation]
    [movable area]
        [area] 836 152 100 30
        [move town] 38 1
```

当前只解析 `[town movable area]`，不解析 `[town movable area with animation]`；这个通往 town 38 area 1 的传送区没有进入 `town_movable`。

### 8.5 未实现 / 字段对不上清单

- `[phase]`：每个 area 都有两张备选 map（`Gent_afterwar`、`Gent_EndWar`）；当前只用 area 自身 base map，没有按 `[phase]`/`[phase shift]` 选择。
- `[minimap rect]`：gent 的 area 全部没有该字段，`TownDef.neighbor_of()` 没有数据可用；这是数据缺失，不是解析错。
- `[limit map camera move]`、`[top edge]`、`[wide mode camera vertical correction]`：当前相机没有读，可能影响大房间的跟随和上下边界。
- `[tile map]`：扩展层的地图数据已解析进 `extended_map`，但渲染层是否真正使用，需下一步单独验证。
- `[monster]`、`[passive object]`：当前完全没解析；不是这次 gent 的主因，但属于未实现。
- 未登记 label（twn）：`[cutscene images]`、`[wide]`、`[cutscene image change]`、`[entering title change xui]`、`[dungeon what must be cleared]`、`[phase shift]`、`[condition]`、`[phase Index]`、`[odyssey enter level]`。
- 未登记 label（map）：`[tile files]`、`[tile map]`、`[ani info]`、`[filename]`、`[layer]`、`[order]`、`[movable area]`、`[area]`、`[move town]`、`[basic animation]`、`[open animation]`、`[loop animation]`、`[close animation]`、`[animation change area]`、`[draw layer]`、`[top edge]`、`[near sight scroll]`、`[scroll animation]`、`[shadow type]`、`[teleport area option name]`、`[disable area animation]`、`[popup window areas]`、`[window area]`、`[popup window]`、`[level animation]`。
  其中 `[tile files]`/`[tile map]` 已有解析；`[filename]`/`[layer]`/`[order]` 是 `[background animation]` 的子字段；`[movable area]`/`[move town]` 是 `[town movable area with animation]` 的子字段。其余要按“是否影响城镇画面/走位”排序，不一次性全做。

### 8.6 当前状态

- `world_smoke` 657/0、`world_ui` 25/0、`path_util_test` 6/0、`test_logger` 42/0。
- `world_walk` 8/2：副本 `.dgn` 尚未原生解析。
- 已修 `..` 折叠和 `[background animation]`；`[town movable area with animation]`、`[phase]` 仍未改，等用户按图判断先后。

---

## 9. 缓存上限核对（2026-11-25）

用户怀疑“64 是不是把加载卡住了”。先把每一层说清楚，避免把不同单位混在一起：

| 位置 | 常量/上限 | 当前值 | 是什么 |
|---|---|---|---|
| `PackContent` | `MAX_TRANSIENT = 64` | 未被 `LivePvfContent` 用作房间硬上限 | JSON 内容包的房级缓存上限 |
| `LivePvfContent` | `_map_cache` 16、`_ani_cache` 256 | 当前 `transient=2` | 现场解析的房间/动画缓存；HUD 的 `transient` 是 `_map_cache.size()`，不是 64 |
| `LivePvfContent` | `MAX_DEFS = 128` | 当前 `defs=78` | 解析后的 Tile/Ani/Obj 定义数 |
| `NpkStore` | `MAX_TEX = 800` | 当前 `tex=68` | 贴图条数，不是 64 |
| `NpkStore` | `MAX_TEX_BYTES = 64 MB` | 未在 HUD 显示 | 贴图字节预算，按宽×高×4 估算 |
| `NpkStore` | `MAX_IMG = 48` | 当前 `img=46` | 解析过的 `NpkImage` 对象条数，**最接近上限的一项** |
| `WorldDirector` | `CACHE_TEX_KEEP=320`、`CACHE_IMG_KEEP=24` | 换图后 | `_unload_room()` 时压回的水位 |

结论：

- 截图里的 `tex=64`/`68` 是**贴图条数**，不是 64 上限；`MAX_TEX` 是 800。
- `MAX_TRANSIENT=64` 不是当前房间加载卡住的原因；`LivePvfContent` 的 `_map_cache` 自己卡在 16，HUD `transient=2`。
- 真正接近上限的是 `MAX_IMG=48`（gent 背景加载后 `img=46`）。这是**条数**上限，不是字节上限；`NpkImage` 持有原始 `_buf`，所以大图会占内存。
- 背景层新增了 2 个 `.ani` 和对应图片，`img` 从 43/44 级升到 46；如果后续再加背景/大图，先看 `img` 是否顶到 48，不要先怀疑 64。

**未改这些上限**；只记录。若要改成“按字节预算淘汰 Img”，需要单独做，不能和背景解析混在一次改动里。

---

## 10. 2026-11-25 多图体检：明确问题清单（未做位置偏移）

这一轮只做三件事：接 `[town movable area with animation]`、修“明确是解析漏了”的两处、把其余问题收集出来。**所有位置偏移、拼接宽度统一留到最后处理，不在本轮改坐标。**

### 10.1 体检工具

- `dnf_like/tests/audit_towns.gd`：遍历 128 个城镇 / 526 个 area，检查 map、tiles、tile/ani/bg/npc 引用，输出 `data/debug/audit_towns.json`。
- `dnf_like/tests/tile_width_audit.gd`：只查“地砖图不是 224 宽”的拼接问题，输出 `TILE_WIDTH non224=N` + JSON。
- 命令（两条都要真跑）：

```bash
XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
  ./tools/godot.sh --headless --script res://tests/audit_towns.gd
XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
  ./tools/godot.sh --headless --script res://tests/tile_width_audit.gd
```

### 10.2 已修：`[import script]` 的 `(f)/(r)` 变体

- 现象：`town/jelva.twn`、`town/metrocenter.twn`、`town/centralpark.twn` 等大量 gate area 的 `[import script] Common/Gate_Seria.map` 找不到父图，导致 `tiles=0`，运行时回退到别的 area 或黑屏。
- 根因：客户端里父图拆成 `map/common/(f)gate_seria.map` 与 `map/common/(r)gate_seria.map`，字面路径不存在。
- 修法：`live_pvf_content.gd` 新增 `_resolve_import(base_dir, ref)`，先试 `base_dir+ref / map/+ref / ref`，再补 `(f)`/`(r)` 变体；仍找不到才 `import_missing`。
- 结果：audit 的 `no_tiles` 从 49 → 0；`gate_jelva.map` 现在 `tiles=5`、继承到 Gate_Seria 的 14 个 NPC。
- **但**：Gate_Seria 的 5 块地砖全是 `Tile/dummy.til`，`img=""`，所以仍然没有地面；`gate_seria` 自带的 `Seria_Room/backgruond*.ani` 在当前截图里也没有画出来（见 10.5）。这不等于“gate 图已经修好”。

### 10.3 已修：`[NPC]` 不是固定 5 元组

- 现象：`temporarycamp` 等地图的 NPC 出现 id=0、名字变成原始 `<8::name_...>`、位置错位。
- 根因：部分 `[NPC]` 记录在方向前多一个条件标签：
  `100001775 [visible on dungeon if quest clear] [left] 633 136 0`
  原来按固定 5 个一组，整段错位。
- 修法：`_compile_map()` 改成按 `id → 任意个 [..] 条件标签 → [left]/[right]/... 方向 → x y z` 扫描；条件保留在 `rec["condition"]`。
- 结果：`temporarycamp` 的 6 个 NPC 恢复为 100001759/100001764/100001761/100001760/100001775/100001762，id=0 消失。
- 剩余 `missing_npcs` 75 个 area 的 ID（如 3084/3085、400001089/400001090、100000503、400001852）在 `list/npc.lst` 里确实没有对应文件；不是解析错位，记录待确认。

### 10.4 明确问题：地砖宽度不是 224

`RoomBuilder` 当前按固定 `BLOCK_W = 224` 铺每一块地砖；`tile_width_audit.gd` 扫出 3 个非 224 的：

| 城镇 / area | 地图 | 地砖 | NPK 帧宽 |
|---|---|---|---|
| `town/airship.twn` a0 | `map/town/airship/airship_rear.map` | `map/town/airship/tile/1_tile.til` | **1**（dummy） |
| `town/inae.twn` a1 | `commonmap/town/250100_joongcheon/inae/inae_1.map` | `.../waitingroom_tile_0.til` | **218** |
| `town/hendonmyre.twn` a4 | `map/hendonmyre/hendon_pub.map` | `map/hendonmyre/tile/bar06.til` | **240** |

- 这三张图的 `pass` 仍然是 14 列（`420 / 30`），所以逻辑网格和图像宽度本身就不一致；先记录，不在本轮改 224/列数/落点。
- 截图证据：`/tmp/audit_airship.png`（全黑 + 玩家）、`/tmp/audit_inae.png`（黑底 + NPC 浮空）、`/tmp/audit_hendon_pub.png`（能看，但柱子/墙纸重复间距可疑）。
- 其余 219 个唯一地砖图是 224 宽，说明 224 是主流、不是唯一规则。

### 10.5 明确问题：gate 图的“地面/背景”仍未画出来

- `gate_jelva.map` 修 import 后有 5 块 `dummy.til`（`img=""`）+ 14 个 NPC；截图 `/tmp/audit_jelva_gate2.png` 只有 NPC/蓝块，地面全黑。
- Gate_Seria 自带的 `[animation]` 有 23 条，路径都能解析（`Seria_Room/backgruond.ani` 等），`store.frame_rect` 也能拿到 1119×600；但截图里看不到。
- 已试 `WORLD_DECO_Z=1000`，截图仍看不到，说明不是简单的 z 被地砖盖住；具体是没进 `_build_deco`、还是纹理全透明、还是相机范围内没有落点，尚未定位。**先记录，不猜结论。**
- 同类 gate 图（slough / centralpark / metrocenter / battleship / prey / jelva_raid 等）都受这个“dummy 地砖 + 背景/装饰未显示”影响。

### 10.6 明确问题：空字符串引用是“资源缺失”，不是解析错位

- `missing_anims` 87 个 area / 259 条，全部是 `path=""`；`missing_bg` 12 个 area / 24 条，也是 `""`。
- 以 `jelva/2_jelva_waiting.map` 为例：原始 8 条 `[animation]` 的第一条是 `Animation/chn_dragon_zone_light_left.ani`，不是空串；`_resolve_rel` 在 `base_dir`、`map/`、根三个位置都找不到它，才返回 `""`。
- 所以这些是**原始引用指向的文件在 latest 里不存在**（或路径规则还没覆盖），不是五元组错位。记录原始 ref 与尝试路径，待用户确认是否客户端本身也缺。
- `missing_tiles` 仅 `town/stolenlandispins.twn` a1/a2，14 个 `contents/2022/.../maincamp*/til0*.til` 全部 `archive.has=false`；截图 `/tmp/audit_stolen.png` 已确认黑底 + NPC 浮空。
- `map_missing` 仅 `town/defianceofafterglow.twn` a0：`map/contents/2026/defianceofafterglow/town/seria.map` 确实不存在，`(f)/(r)` 也没有。

### 10.7 `[phase]`：只记录，不做

- `town/gent.twn` 的每个 area 都有 `Gent_afterwar` / `Gent_EndWar` 两套；`t` 数据里是任务状态分支。
- 当前 `_parse_areas` 不填 `phase`（audit `phase=0`），只用 area base map。**按用户要求本轮不动**，等任务状态逻辑明确后再做。

### 10.8 movables

- `[town movable area with animation]` 已解析进 `MapRoom.town_movable_anim`，并把 x/y/w/h/town/area 追加进 `town_movable` 复用触发逻辑。
- `movable_gate.gd` 已挂到 `Gates` 层，`basic/open/loop/close` 由 `AniSprite` 播放；`player` 进 `world_player` 组。
- gent a0 数据：`anim_gates=1`、`movable=25`、target=(38,1)，四个 ani 帧数 1/41/1/27。
- 视觉/触发尚未由用户判断；截图 `/tmp/gent_movable.png` 只能说明“没崩、场景其它层还在”，不能说明门动画正确。

### 10.9 本轮验证

- `world_smoke`：657 ok / 0 fail（import/NPC 修后重跑）。
- `world_ui`：25 ok / 0 fail。
- `world_walk`：8 ok / 2 fail（副本 `.dgn` 未接，和本轮无关）。
- audit：`towns=128 areas=526 problems=162`；`KINDS {"map_missing":1,"missing_anims":87,"missing_bg":12,"missing_npcs":75,"missing_tiles":2}`；`no_tiles` 已为 0。

## 11. 调试叠加层：地板块 / 资源落点 / 图层提升

### 11.1 开关

| 键 | 作用 |
|---|---|
| `M` | 城镇列表 |
| `L` | 世界调试面板 |
| `G` | 绿色透明地板块（按实际帧尺寸，不按固定 224） |
| `[` / `]` / `\` | 区域框 / 每张图落点 / 通行网格 |
| `U` | 临时隐藏 HUD、调试面板、城镇列表；再按恢复 |
| `1`–`7` | 把 distantback / middleback / closeback / bottom / normal / close / front 抬到角色下方；`0` 取消 |

- 图层提升只改 `RoomBuilder` 写入的 `meta("layer")` 节点，原 z 存在 `meta("z0")`；每帧 `_apply_raise_z()` 取 `min(player.z_index - 1, 最近 actor 的 z - 1)`，所以既低于角色、也不会盖住 NPC/怪物。
- 取消或换层恢复 `z0`；换房后 `_reapply_raised()` 重新收集。

### 11.2 资源落点日志

每次 `_load_room()` / `_rebuild_room()` 后 `RoomBuilder._log_placements()` 打 DEBUG 级：

```
[MapPlace] kind=<tile|ext_tile|background|deco|object|movable|npc|pathgate|marker>
  src=<PVF 路径> img=<NPK 图> frame=<帧> node=(x,y) canvas=(x,y) off=(dx,dy)
  final=(x,y) actual=(x,y) size=(w,h) z=<z> layer=<层>
```

- `node` = 节点/锚点；`canvas` = NPK 帧画布原点；`off` = `[IMAGE POS]`；`final=node+off`；`actual` = 最终落点（NPC 已加画布原点）。
- 区域切换另打 `[AreaMove] enter ...` / `[MapPlace]` 重打 / `[AreaSpawn] map=... player=...` / `[AreaMove] movable ... target=...`。
- 角色实时坐标在左上角，格式 `角色 x=... y=... cell=(... ) z=... area ...`。
- 全量冒烟日志约 20 MB；测试时用 `WORLD_PLACE_LOG=0` 关掉落点日志。

### 11.3 地板块

`_build_floor_boxes()` 每块地砖画 `Color(0.15,1,0.35,0.10)` 填充 + 亮绿边框 + `T<列> <宽>×<高> <til 文件名>` 标签，z=2400。它直接暴露 218 / 240 / 1px 的非 224 地砖，为后续统一拼接/偏移提供依据。

### 11.4 本轮验证

- `world_smoke`：657 ok / 0 fail（加调试代码后重跑；`WORLD_PLACE_LOG=0`）。
- `world_ui`：37 ok / 0 fail（新增实时坐标、地板块、图层提升且不盖 NPC、`L`/`U`、通行 0/2 断言）。
- 截图：`/tmp/world_debug2.png`（1152×648）——左上角色坐标、右上调试面板、绿色地板块、近背景高亮。
- 注意：地板块是**世界内叠加层**，不是 HUD；`U` 只隐藏 UI，不隐藏地板块。


## 12. 通行语义 / 图层上限 / 城镇角色（2026-11-25 本轮）

### 12.1 `[pass type]`

- **0 = 可走，2 = 阻挡**；`PassGrid` 初始化 `cells.fill(2)`（缺图/缺列=阻挡），`walkable()` 只认 0。
- 行序：`PassGrid.build()` 用 `vy = y_off + r`，`r` 按图像自上而下；**不能**再用 `rows-1-r`。旧实现既反了 0/2 语义又翻了行序，导致出生点在半空、地面上下颠倒。
- 实测 `hendon_city`：`rows=30`，图顶部 3 行全 2、底部 2-3 行全 0；修正后出生 `(1912.0,461.6)`、可走率 57%。

### 12.2 closeback 提升上限

- `WorldDirector._actor_ceiling()` 递归扫 `room_node` 中带 `meta("actor")` 的节点（NPC/怪物/玩家标记），取最小 `z_index`。
- `_apply_raise_z()` 取 `min(player.z_index-1, _raise_ceiling-1)`，并 clamp 到 -4096..4096。
- 实测 hendon_city：NPC 最小 z=270；closeback 提升后 34 个节点 z=269，不再盖住 NPC。
- `world_ui` 的断言按 `_actor_ceiling()` 计算期望；只断言“低于角色”会漏掉盖 NPC 的情况。

### 12.3 城镇角色：鬼剑士五层

- `WorldPlayer.setup_visual(content, store)`：`MOVE_ANI="character/swordman/animation/move.ani"`、`STAY_ANI="character/swordman/animation/stay.ani"`；`BODY_LOOK=0`。
- 用 body 的 AniDef 复制 5 层，按同帧号换图：`skin/sm_body%04d.img` → `pants/sm_pants%04da.img` → `shoes/sm_shoes%04da.img` → `coat/sm_coat%04da.img` → `hair/sm_hair%04da.img`；add 顺序即由里到外。
- 只播 move / stay；移动时 move、静止时 stay；不接攻击、跑步。`AniSprite.setup(..., true, true)` 加 NPK 画布原点。
- 每层缺图就跳过；全缺回退原色块。
- 为什么不走 `.lay`：latest PVF 的 `equipment/character/swordman/avatar/{coat,...}` 只有 `.equ`，`[equipment ani script]` 指向的 `equipment/character/swordman.lay` 在 `PvfNewArchive` 中不存在，`.als` 也为空；现在用同编号 avatar NPK 图直接叠层，先保证城镇可见、可走。
- NPC/挂件坐标不受影响：NPC 仍是独立 `AniSprite`，不走玩家层合并。

### 12.4 本轮验证

- `world_smoke`：657 ok / 0 fail。
- `world_ui`：37 ok / 0 fail。
- `world_walk`：8 ok / 2 fail（副本 `.dgn` 未接，与通行/角色无关）。
- 截图：`/tmp/player_ghostblade.png`、`/tmp/player_layer.png`；角色是 skin 层，需目视判断是否接受。

## 13. `[extended tile]` 复核（2026-11-25）

用户给出的块对应 `map/hendonmyre/hendon.map`（`town_hendonmyre.twn` area0，dungeon gate 101）。

原始：

```
[extended tile]
    [tile files] 0 Tile/hmbrex01.til 1 Tile/hmbrex02.til 2 Tile/hmtileex.til
    [tile map] 0 1 2 2 2 2 2 2 2 2 2 2 2 2 2 2
```

当前 `LivePvfContent._compile_map()` 的解析结果：

- `room.tiles.size() = 16`（基础 `[tile]` 全是 `Hm01`）；
- `room.extended_tiles = [hmbrex01.til, hmbrex02.til, hmtileex.til]`（按 `[tile files]` 索引 0/1/2 排序）；
- `room.extended_map = [0,1,2,2,...]`，长度 16；
- `RoomBuilder._build_tiles()` 实际创建 16 个 `ExtTile` 节点：
  `x = i*224`、`y = grid.height = 480`、`size = 224×120`、`z = -79`。

结论：**这部分已经加载**，不是漏解析。当前画面看不到的原因不是数据缺失，而是位置：扩展地砖从 `grid.height=480` 往下排，而房间高 480、相机可见世界高 480，底边正好卡在屏幕外；这是“位置偏移/相机”问题，按约定留到统一处理，不混进解析结论。

验证命令：

```bash
XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
  ./tools/godot.sh --script res://tests/world_shot.gd -- \
  --out=/tmp/hendon_area0.png --town=town_hendonmyre.twn --area=0 --debug=1 --frames=35
```

日志里会看到 `kind=ext_tile ... node=(0,480) ... size=(224,120) z=-79` 共 16 条。

## 14. 区域移动标记 + 通行全 2 的处理（2026-11-25）

### 14.1 区域移动的坐标（曾误判，现双模式）

`[town movable area]` / `[town movable area with animation]` 的 `x/y/w/h` 不能直接断言是屏幕坐标，也不能直接断言是“底边为 0”。当前保留两种解释，默认 **TOP（raw，顶部为 0）**：

```gdscript
# pass_grid.gd
enum RectYMode { TOP, BOTTOM }
var rect_y_mode: int = RectYMode.TOP

func rect_with_mode(raw: Rect2, mode: int) -> Rect2:
    if mode == RectYMode.BOTTOM:
        return Rect2(raw.position.x, height - raw.position.y - raw.size.y,
                raw.size.x, raw.size.y)
    return raw
```

- `WorldDirector.movable_y_mode`（`"top"` / `"bottom"`）在 `_load_room()` / `_rebuild_room()` 前写入 `RoomBuilder.movable_y_mode`，再同步给 `PassGrid.rect_y_mode`。
- `_check_town_movable()`、`_build_movable_gates()` 用当前模式；`RoomBuilder._debug_boxes` 只画当前模式有效框（品红 `mov`）；2026-11-26 已删除 bottom-up 青框，见 §18。
- 当时的教训：不能只画一种；前一轮只画“翻转后”的框，用户看到传送点在错误的一侧，才知道方向反了。现已验证 raw(top) 正确，青框删除。
- A/B 测试：`tests/movable_y_ab.gd`，对中央公园 area1 的 `town_movable` 目标 `35/0`（魔界营地）分别把玩家放到 raw 中心与 bottom 中心，打印哪种模式命中。实测：
  - `top`: raw_center=(1588,480) 命中，bottom_center=(1588,0) 不命中；
  - `bottom`: 反过来。
- 截图 `/tmp/movable_ab.png`（默认 top，两种框同时画）。

### 14.2 通行“整图全 2”的根因

`_load_room()` 原来只要 `walkable_ratio()==0` 就 `make_all_walkable()`，把整张图解锁。会命中：

- `map/cataclysm/town/stormpass/stormpass.map`
- `map/cataclysm/town/stormpass/d_stormpass_storm.map`
- `contents/2022/stolenlandispins/map/town/stolenlandispins_1.map`
- `contents/2022/stolenlandispins/map/town/stolenlandispins_2.map`

这些图原始 `[pass type]` 全为 2，不是 dummy.til；整间解锁后就会出现“明显不可通过的地方也能走”。

现在改成：

- 只有整张图都是 `dummy.til` 的过渡图才 `make_all_walkable()`；
- 其它全 2 图保持全阻挡，日志写“保持全阻挡（不整间解锁）”；
- `world_smoke` 对上述 4 张已知全阻挡图显式放行（`KNOWN_BLOCKED`），其余 area 仍要求 `walk > 0`。

注意：这四张图现在玩家会停在出生点无法移动；它们不是正常可玩房间，是否需要另做入口/传送，等用户决定。

### 14.3 通行 overlay

`RoomBuilder._debug_grid()` 现在红绿都画：

- 绿 = `walkable()` 为真（pass 0）
- 红 = 阻挡（pass 2 或其它）
- 图例 `grid: 绿=可走 红=阻挡 灰蓝=缺图`

之前只画绿格，看不到“该阻挡却可走”的区域。`world_shot --grid=1` 可直接截图。

### 14.4 当前验证

- `world_smoke`：657 ok / 0 fail（含 4 张已知全阻挡）
- `world_ui`：37 ok / 0 fail（触发区断言改用 `grid.map_rect`）
- `world_walk`：8 ok / 2 fail（副本 `.dgn` 未接）


## 15. 传送区 y 轴 A/B 结论（2026-11-25）

### 15.1 怎么跑

```bash
XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
  ./tools/godot.sh --headless --script res://tests/movable_y_ab.gd
```

输出形如：

```text
== movable y A/B ==
mode=top raw_center=(1588.0, 480.0) bottom_center=(1588.0, 0.0) raw_hit=true bottom_hit=false
mode=bottom raw_center=(1588.0, 480.0) bottom_center=(1588.0, 0.0) raw_hit=false bottom_hit=true
== done ==
```

这只证明**两种模式各自按自己的假设命中**，不证明哪种是游戏真实坐标；真实判断要看截图/客户端。

### 15.2 “偏移不足”的排查记录（相机已排除，未改）

- 曾把 `_update_camera()` 改成实际视口高度；用户指出“zoom 不影响东西的实际位置”，已回退，不再作为本次原因。
- 用户截图里的实际数据：玩家 `x=1388.8, y=195.4`，赫顿玛尔 area1。
- 门/拱门是 `[animation]`：`map/hendonmyre/animation/basilica.ani`，原始 `(1359,166)`，当前 `y = 166 + y_shift(120) = 286`；帧画布 `(-377,-367)`、图高 407，画面上沿 -81、下沿 326。
- 两段 `wall00.ani` 原始 y=219，当前节点 y=339。
- 玩家 y=195.4 与 basilica 下沿 326 差 **130.6px**，接近 `y_shift=120`。
- 因此嫌疑集中在 `RoomBuilder.y_shift`：它只加在 `[animation]` 上，`map_y()`（玩家/NPC）没有；不是相机、不是 `+16`。
- 下一步等用户给“角色下移 / 装饰上移”的方向与像素数，只改对应一处；不再自行改默认。

### 15.3 和通行网格的关系

`PassGrid` 的地板/墙使用 `[pass type]` 行序，与传送区矩形是**两套独立坐标**；修传送框不要动 `PassGrid.build()` 的行序。

## 16. 城镇坐标偏移：new_hendonmyre 的具体值（2026-11-25）

### 16.1 结论

`new_hendonmyre.twn` area0（`map/cataclysm/town/hendonmyre/new_hendon_main.map`）的实测数据：

- `PassGrid`：224×30 格，`height=480`；可走行 `walkY=9..29`（世界 y=144..464）。
- `[NPC]`：raw y=153..171（另有一个 401 的占位），贴着可走区顶部；旧 `map_y` 会算成约 404，压到可走区底部。
- `[town movable area]`：raw y 含 134、483、246、100、241、131。
- 地砖 `img_pos=80`，tile art=(224,333)。
- 注意：`new_hendon_main.map` 里没有 `[background pos]`；`.dgn`（如 `dungeon/act1/lorien.dgn`）反而有 `[background pos] 80`。用户确认 80 没有可靠来源，**物体偏移先继续用 120**。

`y_shift=120` 用于 `[animation]`；2026-11-25 尝试改成 `[background pos]`，但地图本身没有可靠字段（80 来自部分 `.dgn`），用户确认 **先回到固定 120**。120 是否随图变化仍待审计：

| 对象 | 公式 |
|---|---|
| 装饰 `[animation]` | `raw.y + 120 - z`（原样，用户确认门/装饰是对的） |
| NPC | `raw.y + 120`（不再用 `map_y`） |
| PassGrid | 格子世界 y = `120 + row*16`；`walkable_at` 先减 `origin_y` |
| 区域移动（town movable） | `Rect2(x, raw.y + 120, w, h)`（top 模式；用户确认粉色框对） |
| 玩家出生/移动 | `PassGrid.origin_y=120`；相机用 `grid.world_height()=height+120` |

### 16.2 当前默认

- `WorldDirector.start_town = "town/new_hendonmyre.twn"`。
- `RoomBuilder` 常量：`pass_y_offset = 120.0`、`y_shift = 120.0`；`build()` 写入 `PassGrid.origin_y`。`[background pos]` 只作审计数据，不参与物体偏移。
- `PassGrid.rect_y_mode = RectYMode.TOP`（区域移动按顶部起算，再加 `origin_y`）；`WorldDirector.movable_y_mode = "top"`。用户确认粉色 top 框位置对；bottom 只作对照。
- `RoomBuilder._debug_boxes()` 仍同时画 top/bottom 两套框，`active=top` 标在当前使用的那套上；实际触发和粉色框一致。
- 旧 `town/hendonmyre.twn` 只作对照，不是主依据。

### 16.3 验证

- `world_smoke.gd`：657 ok / 0 fail（128 城镇全部 area）。
- `world_ui.gd`：37 ok / 0 fail。
- `world_walk.gd`：8 ok / 2 fail，仍是副本 `.dgn` 未接。
- 截图：
  - `/tmp/newhendon_npc120.png`（1600×1000）：NPC 站在可走区顶部地面，玩家在底部。
  - `/tmp/newhendon_top_active.png`：top 模式；粉色框 = 实际触发框，`active=top`。
  - `/tmp/centralpark_off120.png`：中央公园 area1，NPC 凯蒂站位正常。
- 这些图只验证“和本组公式自洽”，不证明全地图都正确；逐图复核仍按 §15 的停点来。

### 16.4 还没解决

- 用户 2026-11-25 判断：这个 120 可能按图变化（480 小图 / 600 大图 / 更高）；但目前没有找到 map/twn 级可靠字段（`.dgn` 的 `[background pos]` 有 80，不等于城镇图偏移）。已启动 twn+dgn 全量 map 审计，记录未解析字段和缺资源；120 是否分图待审计结果。
- 普通地图仍有“明显不可通过区域没限制住”的案例待逐张确认；已知 4 张原始 pass 全 2 的图，当前只有整张 `dummy.til` 才允许解锁。
- `[extended tile]` 在 hendon area0 位于 `grid.height` 以下，相机可见高 480 时在屏外；是否应该进入相机范围待用户判断。
- `world_walk` 的副本两条仍失败，因为 `LivePvfContent` 还没解析 `.dgn`。

## 14. 全量地图审计（2026-11-25）

- 报告：`docs/PVF-MAP-AUDIT.md`；机读结果：`dnf_like/data/debug/audit_maps.json` / `.md`。
- 审计脚本：`dnf_like/tests/audit_maps.gd`。
- 规模：twn 引用 map 489；dgn 文件 3,961（3,507 个唯一 basename）；按目录约定加载 map 15,700；加载失败 114（全部空文件）。
- 未解析 label 302 个、97,438 次；最高频是 `[player number]` 15,536、`[pvp start area]` 15,534、`[event monster position]` 14,560、`[monster specific AI]` 14,070、`[near sight scroll]` 10,300。
- 已实现：`[monster]`（14,152 张 map 非空，101,467 条）和 `[passive object]`（14,382 张、288,931 条）；`.obj`→base ani、`.mob [waiting motion]` 站立动画已接，见 §17。
- `[background pos]` 分布 0/80/缺失 = 15,532/54/114；120 不是它推出来的，保留固定 120。
- `.dgn` 没有解析器；dgn map 只是按目录约定枚举，不能把“dgn 加载过”当作“dgn 逻辑实现”。


## 17. 怪物 / 被动对象（2026-11-25）

### 17.1 数据

- `[monster]`：一条 label 可含 N 条 8-int 记录（`id,auto,level,x,y,z,rdrop,sdrop`），随后是
  `[fixed|half|ratio]` 与 `[normal|champion|super champion|boss]`；类型前可插
  `[NPC] id 朝向 x y z`。按 token 流切，不能按固定宽度切。
- `[passive object]`：固定 4-int `id x y z`；id → `list/passiveobject.lst` → `.obj`；
  `.obj` 先看 `[basic action]` → `.act` 的 `[BASE ANI]`（含 `[SUB ANI]`），
  没有 `[basic action]` 时看 `[basic motion]` 直接指向 `.ani`。
- 两者都相对各自文件目录解析，仍走 `_resolve_rel` 的多候选 + `..` 折叠。

### 17.2 运行时

- `LivePvfContent`：`monster(id) -> MonsterDef`、`object(obj_path) -> ObjectDef`；`_monster_cache` /
  `_object_cache` 常驻，不参与 `_defs` 的 128 条淘汰。
- `MapRoom.monsters` / `MapRoom.objects` 由 `_compile_map()` 填充；`[import script]` 合并逻辑仍只填空字段。
- `RoomBuilder._build_actors()`：怪物有 `.mob waiting motion` 时用 `AniSprite`（加 NPK 画布原点）并显示名字；
  缺动画回退红块 `M<id>`。`_build_objects()` 早就按 `d.ani` 渲染，现在终于有 `ani` 值。
- 测试：`tests/world_entities.gd` 12 项（固定 map `map/astraythief/17655(2,1)normal.map`，13 怪 / 17 对象），
  `world_smoke 657`、`world_ui 37`、`world_walk 8/2`。
- 视觉：`/tmp/entities_astray.png`（1600×1000，用 `world_shot --map=...`）；只说明“解析后有图/有名字”，
  不代表位置偏移已确认。

### 17.3 未做

- `[special passive object]` 3,581 次、`[event monster position]`、`[monster specific AI]`、`[basic action]` 等
  map 字段仍未消费；`pass_type` 只存不参与碰撞；怪物不移动/不攻击。
- `.dgn` 仍未解析；dgn 的 map 是按目录约定枚举的。

## 18. 图层与传送框最终结论（2026-11-26）

### 18.1 传送区 y 轴：raw(top) 是对的

- 2026-11-25 的结论：`[town movable area]` 的 `x/y/w/h` 按 raw（顶部 0、向下）解释时，粉色框
  与实际触发一致；之前把 y 当“底边起、向上”翻成 `height - y - h` 的青色框只是对照实验，后来
  默认改回 `PassGrid.RectYMode.TOP`，实际触发和粉框重合。
- 2026-11-26 用户确认 bottom-up 已不需要：`RoomBuilder._debug_boxes()` 只画当前模式的有效框
  （品红），青色 `mov(bottom)` 框已删除；`town_movable_anim` 的橙色 bottom 框也删除。
- 结论记录即可，不要重新引入 bottom-up 作为默认；`movable_y_mode="top"` 保留。

### 18.2 数字键与 layer 对应

数字键 `1..7` 与 `WorldDebugUI.LAYERS`（= `LayerZ.NAMES`）一一对应：

| 键 | layer | 中文 | 基础 z |
|---|---|---|---|
| 1 | distantback | 远背景 | -70 |
| 2 | middleback | 中背景 | -65 |
| 3 | closeback | 近背景 | -35 |
| 4 | bottom | 底部 | -50 |
| 5 | normal | 普通 | -40 |
| 6 | close | 贴近 | -30 |
| 7 | front | 前景 | +20 |

用户 2026-11-26 确认：按 `3` 提升 closeback 的效果是对的。

### 18.2b 区域偏移与移动区偏移拆开（2026-11-26）

- `PassGrid.origin_y` 固定 120，只用于 `[town movable area]`、传送门、副本/区域框。
- `PassGrid.move_y_offset` 只给通行网格/出生点/相机高度；调试面板“移动范围 Y”只改它。
- 两者相加只发生在网格坐标换算里，`grid.map_rect()` 永远只用 `origin_y`；不要再把 `movable_y_offset` 合进 `origin_y`。

### 18.2c area/virtual 并集（2026-11-26）

- `PassGrid.walk_rects` 收集 `[town movable area]`、`[town movable area with animation]`、`[virtual movable area]`，按 area 坐标（`RectYMode.TOP + origin_y`）转世界矩形。
- `walkable_at()` 先判这些矩形，再判地砖 `[pass type]`；只补可走性，不改变传送触发/门的位置。
- `virtual` 是补边角的数据源，调试框也走 `grid.rect_with_mode()`，不再直接画 raw。

### 18.3 z 范围纪律

- 图层 z 统一由 `game/world/build/layer_z.gd` 的 `LayerZ` 表给出；基础层和地砖/背景都限制在
  `[-100, 100]` 内，手填常量，不做归一化、不按房间高度/相机/角色位置换算。
- 2026-11-26 根据用户截图再调：`closeback -35`，顺序为 `distantback < middleback < bottom < normal <
  closeback < close < front`；closeback 的建筑要盖住 normal 的城门墙，且仍在地砖之上。
- 非动画基础层也在此表：地砖 -50、扩展地砖 -79、远景背景 -95、背景 -90。
- 临时图层提升只把匹配层设到 `LayerZ.Z_RAISE = 95`，再取 `min(95, 最近 actor - 1)` 并 clamp 到
  `[-100,100]`；不再用 `player.z-1` / 4096 这类大范围归一化。
- 若要新增/调层，直接改 `LayerZ.Z_BY_NAME` 的手填值，保持相邻层有间隔即可。

## 19. wahrheit 卡顿排查（2026-11-26）

- 目标文件：`commonmap/town/220113_110levelexpansion/wahrheit/wahrheit.map`。
- 数据：9 tiles、21 `[animation]`、1 background、4 NPC；32 张唯一纹理，约 35MB。
- 卡顿源不是磁盘/缓存命中，而是 `NpkImage._dds_frame()` 在 GDScript 里逐像素解 DXT。
- 修复前：`RoomBuilder.build()` 3,073ms；21 个动画全帧解码 49,147ms；`Cloud.img` 16,545ms（单帧最差 563ms）、`Gear_Big.img` 16,191ms（560ms）。
- 修复：`_dds_frame()` 先用 `Image.load_dds_from_buffer()`；DPX 压缩图先 `decompress()`，再 `convert(FORMAT_RGBA8)`，按帧矩形裁剪。
- 修复后：build 282ms；全帧 471ms；Cloud 116ms（34ms）、Gear_Big 84ms（29ms）。
- 复现：
  `XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like ./tools/godot.sh --headless --script /tmp/wahrheit_probe.gd`
  `... --script /tmp/wahrheit_anim_cost.gd`
- 截图：`/tmp/wahrheit_native.png`（1600×1000）。

## 20. 只走 area 调试模式（2026-11-26）

- 目的：验证“实际移动范围是不是只由 area/virtual 组成，和地砖 0/2 无关”。
- 开关：调试面板 `只走area` 按钮；`world_shot --walk=area`；`WorldDirector.area_walk_only` / `PassGrid.walk_rects_only`。
- 行为：`walkable_at()` 只命中 `walk_rects`（`town_movable` / `town_movable_anim` / `virtual_movable`），完全忽略地砖 `[pass type]`；触发/传送逻辑不变。
- 验证：`world_ui` 53/0，含按钮存在、开关生效、网格外不可走、恢复模式。
- 截图：`/tmp/newhendon_areaonly.png`，HUD 显示 `移动=只走area`，绿色网格只剩 area 矩形覆盖处。
