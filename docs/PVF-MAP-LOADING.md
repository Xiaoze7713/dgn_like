# 地图加载层（latest PVF → Godot 运行时）

> 数据源：`latest` 国服客户端（`Script.pvf` 6,288,780 条目，抽取进 `analysis/pvf-new/pvf34.sqlite`）。
> 2026-11-25 起运行时改为 `LivePvfContent` 直接读原生 `Script.pvf` 与 `ImagePacks2`；§4 的 JSON 内容包只保留为旧对照。
> 验证状态（2026-11-25 原生路径）：128 城镇（129 个注册项里 1 个没有可读地图，另有 1 张地图数据损坏被过滤）；`world_smoke` 657 ok / 0 fail；`world_ui` 24 ok / 0 fail；`world_walk` 城镇 8 ok / 2 fail（副本 `.dgn` 尚未接原生解析）。

---

## 1. 结论速览（先读这段）

1. **引用链只有一条**：`.twn`（城镇）→ `[dungeon gate] id` → `dungeon/tutorial/dungeon.lst`（全局副本表，1277 条）→ `.dgn`（副本）→ `[map specification]` → `.map`（房间）→ `[tile]` → `.til`（地砖）→ `[IMAGE]` → ImagePacks2 的 NPK。
2. **坐标是「从下往上」的**（这是最初踩坑最多的地方）：
   - `.til [pass type]` 的第 0 行贴着地砖图像的**下沿**，行号越大越往上；
   - `.map` 里怪物 / NPC / 物件 / `[pathgate pos]` 的 `y` 也是「距房间下沿的高度」。
   - 换算成 Godot 世界坐标：`world_y = (网格高 + [img pos]) - raw_y`。
3. **房间尺寸不是字段，是推导的**：每块地砖 `224 × 480`（14 列 × 30 行，格 16px）；房间宽 = 地砖数 × 224。
4. **进副本不是随机生成**：`[map specification]` 同一格可以挂多个地图 id，客户端从候选里挑一个 →「每次房间不一样」。
5. **`[import script]` 是真实的继承机制**：子图只需写差异字段，父图字段按「子图为空才填」合并。

---

## 2. 五种文件各自的解析规则（latest 实测）

### 2.1 `.twn`（城镇，317 个）

```
[name] <14::name_18320>
[sub name] <14::...>
[dungeon what must be cleared] -1
[cutscene images] [normal] <img> <frame> [wide] <img> <frame>
[area] 0 `HendonMyre/Hendon.map` [minimap rect] 175 201 325 230 [/minimap rect] `[dungeon gate]` 101
[area] 1 `HendonMyre/Hendon_City.map` [minimap rect] 209 245 363 270 [/minimap rect] `[normal]`
[area] 5 `Town/CentralPark/Gate_CentralPark.map` `[gate]` 565 234
[area] 7 `Town/CentralPark/Portal.map` `[permission]` `[dungeon gate]` 7  `[need level]` 82
[area] 9 ... `[permission]` `[use private store]` 0 `[gate|normal]` ...
```

- `[area]` 的 `map` 路径**不带 `map/` 前缀**，一律解析成 `'map/' + lower(ref)`。
- 类型 token 实测只有 6 种：`[normal]` / `[gate] x y`（城镇出口坐标）/ `[dungeon gate] N` / `[safe zone]` / `[housing]` / `[open party list area]`。
- `[minimap rect]` 是 **x0 y0 x1 y1**（不是 w/h）——官方注释与实测 rect 尺寸都支持这一点。
- 其它可选字段：`[need level]`、`[need quest]`、`[odyssey enter level]`、`[invisible map open effect]`。
- **latest 的 area 类型常嵌在 `[permission]` 子树里**（同层还可能有 `[need level]`、`[open party list area]`、`[extra dungeon gate]`），不能只读 `[area]` 的直接 values。当前 `parse_areas()` 扫 area 子树里的每个 values 列表，按优先级 `dungeon gate(5) > gate(4) > normal(3) > safe zone(2) > housing(1) > open party list area(0)` 选类型。
- `gate` 的 `args` 只收**同一 values 列表**里的后续值：`[gate] 565 234` 不会把兄弟标签 `[need level] 82` 的 82 收进来；`[dungeon gate] 39` 同理。`[phase]` 只记录，不参与 base map 选择。

### 2.2 `dungeon/tutorial/dungeon.lst`（副本注册表）

```
1 `Act1/Lorien.dgn`
101 `Act9/KohlePowerStation.dgn`
```

- 解析基址要按 **`dungeon/`** 拼（不是 lst 所在目录）：`dungeon/act1/lorien.dgn` 存在，`dungeon/tutorial/act1/lorien.dgn` 不存在。
- 规则：依次试 `lst_dir/ref`、`lst_dir.parent/ref`、`根/ref`。
- latest **没有** `map/map.lst` / `worldmap/*.lst` / `town/*.lst`，这张表是唯一的副本入口。

### 2.3 `.dgn`（副本，7,500 个）

```
[background pos] 80
[minimum required level] 17   [basis level] 20   [experience increasing point] 1.55
[pathgate object] 6065 6066 …
[maze info]
  [size] 3 1
  [greed] BBFFEE
  [map specification] map 0 0 91021   map 1 0 91022   map 2 0 91023
  [start map] 0 0   [boss map] 2 0
```

- **`[maze info]` 是无子节点的段标记**：`[size]/[greed]/[map specification]/[start map]/[boss map]` 是它的**同级兄弟**，必须按出现顺序切段（mirkwood 有 4 段）。
- `[map specification]` 格式：`<类型> <x> <y> <id> [<id> …]`；类型 ∈ `map` / `boss` / `layered`；**同一格多 id = 候选房间**。
- `[boss map specification]` 在 latest 里表现为 `boss 0 0 57981`（同一套解析）。
- `[greed]` 是多行字符串（`'AAIIJJEE\r\n BBHHGGAA'`），按行切 → 每 2 字符一格。15 token 位掩码：
  `BB 右 · EE 左 · CC 上 · II 下 · DD 右上 · GG 左上 · JJ 右下 · MM 左下 · NN 左下右 · HH 左上右 · LL 上下右 · KK 上下 · FF 左右 · PP 十字 · AA 不可通过`。
- `[start map]` / `[boss map]` 可以是多对：`[start map] 0 0 1 0`。

### 2.4 `.map`（房间，49,170 个；`map/` 下 34,610）

```
[type] `[normal]`            [greed] NN FF          [dungeon] 3
[tile] Tile/ForestOver_00.til …(N 个，从左到右平铺)
[extended tile] [tile files] 0 Tile/...  [tile map] 8 …
[pathgate pos] 14 246  1776 258  896 169  896 348      ← 左/右/上/下 四组 x,y
[monster] 10×N 元记录（见下）
[NPC] id `[left]` x y z …
[passive object] id x y z …
[animation] ani 图层token x y z …
[background animation] [ani info] filename/layer/order …
[town movable area] x y w h townIdx areaIdx ×N
[virtual movable area] x y w h ×N
[teleport area option] 名称 x y w h
[import script] Common/Gate_Seria.map
```

- `[monster]`：**一个标签塞 N 条记录**，记录 = `8×int`（含 id/等级/x/y/z/掉落次数）+ `[fixed|half|ratio]` + `[normal|champion|super champion|boss]`，类型 token 前可插 `[NPC] id 朝向 x y z`。只能流式切 token。
- `[tile]` 的路径相对**该 map 所在目录**；解析顺序 `map目录/相对 → 'map/'+相对 → 根`。
- `[town movable area]` 六元组，`townIdx == -1 && areaIdx == -1` = **副本开始点**（官方语义）。
- `[import script]`：父图字段只填本图为空的键，递归合并（有环保护）。`gate_centralpark.map` / `gate_metrocenter.map` 只有这一行。父图字面路径 `Common/Gate_Seria.map` 不存在，实际拆成 `map/common/(f)gate_seria.map` 和 `(r)` 两个变体；`LivePvfContent._resolve_import()` 现在会补这两个变体，所以 gate area 能拿到 5 块 `dummy.til` + 14 个 NPC。`dummy.til` 没有 `[IMAGE]`，地面仍不可见；Hendon 的 `gate_hendon.map` 同理。

### 2.5 `.til`（地砖，141,884 个）

```
[IMAGE] Map/Town/Evildom/CentralPark/Central_tile.img 0
[img pos] 80
[pass type] 2 2 2 … (420 个)
```

- 尺寸：`[pass type]` 值总数 = 14 × 行数；420 = 14×30、140 = 14×10、154 = 14×11 ⇒ **列数恒为 14**，格 16px，块宽 224。
- `[img pos]`：地砖图相对网格的**垂直偏移**，`画图 y = 网格高 + img_pos - 图片高`。
- `[pass type]` 取值：`2` 可走、`0` 阻挡、`3` 语义未定（极少数）。
- 扩展地砖多一个 `[tile type] `[extended]``，是「地砖下方那一层」，不是第二行。

---

## 3. 坐标系统（最重要的一节）

以 `map/kohlepowerstation/18002(2,0)n.map` 为例（`point_4.til`，img_pos 120，NPK 帧 `224×254 @ y=346`，画布 600）：

| 量 | 值 | 说明 |
|---|---|---|
| 网格 | 14 列 × 30 行，格 16px | 块 224×480 |
| 图片 | `rect = (0, 346, 224, 254)` | NPK 帧内容的位置 |
| 画图 y | `480 + 120 - 254 = 346` | 与 `rect.y` 一致 ⇒ 美术底边 = 网格底 + img_pos |
| `[pass type]` | 数组第 0..13 行 = 2，14..29 行 = 0 | **第 0 行贴底** ⇒ 可走区在画面下半部 |
| 怪物 y | 196 / 223 / 278 / 282 | 距下沿的高度 ⇒ 世界 y = `600 - 196` … |

三张图交叉验证（都用同一套规则）：

| 地砖 | 帧 rect | img_pos | 可走行（数组序） | 结论 |
|---|---|---|---|---|
| `hmtile.img`（赫顿玛尔） | (0,342,224,138) | 0 | 0..11 | 可走贴底 |
| `Central_tile.img`（中央公园） | (0,276,224,284) | 80 | 0..5 | 可走贴底 |
| `point.img`（科勒电站） | (0,346,224,254) | 120 | 0..13 | 可走贴底 |

⇒ 伪造/对接数据时必记：**行序翻转** + **y 翻转**，两处都是「0 = 最下沿」。

---

## 4. 旧内容包（离线编译，仅对照）

> 世界运行时**不再读这些 JSON**；本节保留用于核对 token 解析结果。

```bash
# 指定城镇 + 副本（副本可用 path 或注册表 id）
python3 tools/pvf_world/build_pack.py --town hendonmyre --town centralpark \
    --town metrocenter --town devildom_contact \
    --dungeon dungeon/act1/lorien.dgn --out /mnt/e/godot_proj/dnf_like/assets/pvf/world
# 只验证解析不写盘
python3 tools/pvf_world/build_pack.py --town hendonmyre --dry-run
```

实测统计（4 城镇 + 6 副本）：`towns=4, dungeons=6, maps=76, tiles=99, anis=450, objects=99, regions=164, npcs=56`；`problems` 仍会报 `副本 id 39/48 不在注册表`（这是副本注册表本身没有这两个 id，不是城镇解析失败）。

产物（默认 `assets/pvf/world`）：

```
index.json                 {towns:[…], towns_by_id, dungeons:[…registry_id…], regions, npcs, counts, ref_stats, problems}
towns/<key>.json           {path,id,name_text,sub_name_text,areas:[{index,map,type,args,minimap}],dungeon_gate_ids}
dungeons/<key>.json        {path,id,name,min_level,mazes:[{size,greed,cells,start,boss}],meta}
maps/<key>.json            {path,type,tiles[],pathgate[8],monsters[],npcs[],objects[],town_movable…}
tiles/<key>.json           {path,img,frame,img_pos,rows,pass[420]}
regions/<key>.json         {path,key,name_text,towns,town_keys,minimap}
npcs/<key>.json            {id,path,name,field_name,role,ani,face}
```

- 城镇 key 仍是 `key_of(path)`，例如 `town_hendonmyre.twn`、`town_centralpark.twn`、`town_metrocenter.twn`、`town_devildom_contact.twn`，不是裸名。
- 城镇 id：`new_*` 直接查 `list/town.lst`；旧 `hendonmyre` 不在表里，按它所有 area map 的 `[town movable area]` 目标 town（排除 `-1/-2`）取众数推断为 `2`。运行时跨城靠 `towns_by_id`，不要拿 key 猜 id。
- NPC 名来自 `list/n_string.lst` 的 `8=Npc` 表（`files` 表 dtype=3，UTF-16LE，`key>value`）；`<8::name_1915>` 编译时解析成纯文本，运行时不再查字符串表。

- `key = re.sub(r"[^a-z0-9._-]+", "_", path.lower())` —— **GDScript 侧必须用同一正则**（`PackContent.KEY_PATTERN`）。
- 地图 id → 文件两条约定并存，按此顺序兜：
  1. `map/<副本 basename>/<id>(x,y)<role>.map`（role ∈ start/normal/boss/s/n/b）；
  2. 文件名里含该 id（`55605_1776(1,0).map`）；
  3. 兜底 `map/<副本 basename>/` 里的任意一张（`approx: true`）。
  实测 301 个 .dgn / 4303 条 spec：按文件名命中 73.5%，按目录+坐标 44.6%，其余落兜底。
- `ref_stats` 会打印 `dir_xy / id / dir_any / miss` 计数，`problems` 非空就是解析失败。

---

## 5. 运行时结构（`/mnt/e/godot_proj/dnf_like`）

```
game/world/
  content/live_pvf_content.gd LivePvfContent —— 直接读 Script.pvf，按需解析 twn/map/til/ani/npc，LRU 缓存
  model/tile_def.gd          TileDef      —— 一块地砖（COLS=14、CELL=16、pass_at）
  model/map_room.gd          MapRoom      —— 一张 .map（tiles/gates/monsters/npcs/objects…）
  model/npc_def.gd           NpcDef       —— 一个 .npc（name/field_name/role/ani/face）
  model/monster_def.gd       MonsterDef   —— 一个 .mob（name/stay_ani/move_ani）
  model/object_def.gd        ObjectDef    —— 一个 .obj（layer/pass_type/basic_action/base ani）
  model/region_def.gd        RegionDef    —— 一个 .rgn（name/towns/town_keys）
  model/town_def.gd          TownDef      —— 一个 .twn（areas、dungeon_entrances、neighbor_of）
  model/dungeon_def.gd       DungeonDef   —— 一个 .dgn（maze 的 cells、"x,y" 索引、start_cell）
  model/greed_grid.gd        GreedGrid    —— [greed] 位掩码图（step/neighbors）
  build/pass_grid.gd         PassGrid     —— 通行网格 + 滑动移动（行序翻转在这里）
  build/ani_sprite.gd        AniSprite    —— .ani 帧轮播（NPC 用 apply_canvas_offset=true）
  build/room_builder.gd      RoomBuilder  —— 房间 → 节点（地砖/门/NPC/角色标记，y 翻转在这里）
  actor/world_player.gd      WorldPlayer  —— 玩家占位（速度 = chr move speed × 0.26）
  ui/world_font.gd           WorldFont    —— 中文 SystemFont
  ui/town_list_ui.gd         TownListUI   —— 城镇列表（M 开关、点行传送）
  flow/world_director.gd     WorldDirector—— 装载/卸载/换图/回城/跨城/相机/HUD/列表
scenes/world.tscn            （主场景，只有 WorldDirector）
tests/world_smoke.gd         全部城镇/房间的装载冒烟（657 项）
tests/world_walk.gd          输入驱动的走动/换房/回城（8/2；副本待接）
tests/world_ui.gd            M 列表/点击传送/跨城/释放（25 项）
```

要点：

- **装载**：`enter_town(key[,area])` / `enter_dungeon(key)` / `enter_dungeon_by_id(registry_id)` / `enter_town_area(i)` / `return_to_town()`。
- **换图**：城镇靠 `[town movable area]` 六元组（走到矩形内即切 area）：
  - `targetTown > 0` 且不等于当前城镇 → 跨城，`content.town_key_by_id(target_town)` 解析；
  - 同城 → 切 `target_area`；
  - `-1/-1` → 取当前 area 的 `[dungeon gate]` 进副本；
  - `-2/-2` → 打开城镇列表（不是移动）。触发后 `_suppress_movable` 记下矩形，玩家不离开就不重复弹。
- **城镇列表 UI**：`M` 打开/关闭，`Esc` 关闭；按 `region_name` 分组，当前城镇带 `●`；点击行 `town_selected(key)` → `enter_town(key)`。打开时暂停玩家，关闭/传送后恢复。
- **卸载**：`_unload_room()` 立即 `free()` 旧节点（不留在队列里），清 `grid/room/room_node/_parallax_nodes`，并 `NpkStore.trim(320,24)`、`LivePvfContent.trim_cache(40,80)`。
- **缓存**：`LivePvfContent` 永久缓存 index/towns/dungeons/regions/npcs；`_map_cache` LRU 16、`_ani_cache` LRU 256、`_defs` 上限 128。`NpkStore` 按 800 tex + 64 MB 预算 LRU，切图后裁到 320/24。
- **回城**：`return_to_town()` 用 `last_town_key/last_town_area`，回城后停在进副本前的 area。
- **NPK 目录**：`DNF_NPK_LATEST` 环境变量 → 项目设置 `npk/latest_dir` → 硬编码 latest 路径；索引 `assets/npk-index-latest.bin`。
- **NPC**：`RoomBuilder._build_actors()` 用 `content.has_npc(id)` 查定义；有 `[field animation]` 就 `AniSprite.setup(npc.ani, store, Vector2.ZERO, true, true)`，第五个参数把 NPK 帧画布原点算进去；没有动画才回退 `_marker` 色块。名字用 `NpcDef.display_name()`（`field_name` 优先，过滤 `Animation/*.ani` 假名）。
- **回退**：`_area_usable(i)` 要求内容包有图且 `tile_count() > 0`（`[import script]` 父图缺失时自动跳下一个 area）；整张图 pass 全 0 时 `PassGrid.make_all_walkable()` 兜底。

---

## 6. 已验证 / 已知粗糙处

已验证（2026-11-18，2026-11-25 增量）：

- hendonmyre 10 个 area、centralpark 4、metrocenter 3、devildom_contact 3 全部装载；6 个副本逐格装载：kohle 15 间、grakkarakburning 7、lorieninside 6、darkentrance 10、grakkarak 7、lorien 6；`return_to_town()` 6/6。
- 2026-11-25：原生路径 NPC 立绘落地（`.npc` 现场解析，含 Seria/Delilah/PostBox 等）；`M` 城镇列表可传送 128 个城镇；`town_movable` 跨城 `targetTown` 打通；切图立即释放旧房间并裁剪缓存。测试 `world_smoke 657 / world_ui 25` 全绿；`world_walk` 城镇 8/2（副本待接）。
- 截图：`/tmp/w_town2.png`（2026-11-18，NPC 蓝块）、`/tmp/w_dgn3.png`（科勒电站）；2026-11-25 新图 `/tmp/hendon_npc2.png`、`/tmp/hendon_gate2.png`（NPC 贴地）、`/tmp/town_ui2.png`（城镇列表）、`/tmp/devildom3.png`（魔界集结地，无 DDS 错误）。

待办与粗糙处：

- `grakkarakburning` 的 7 格全部落到同一张 `map/grakkarakburning/1202.map`（spec 里的 id 没命中具体文件，走了 `dir_any` 兜底）。
- `gate_centralpark.map` / `gate_metrocenter.map` 的父图 `Common/Gate_Seria.map` 是 `(f)/(r)` 变体；`_resolve_import()` 已能解析，不再回退 a1。
- `gate_hendon.map`（Seria 城门）能进，但 4 块 `dummy.til` 无可见地砖、背景黑；NPC 和名字正常。gate 系地图的 `dummy.til` 地面/背景仍是未解决项。
- 2026-11-25 已接 `[background animation]`（`[ani info]/[filename]/[layer]/[order]`）和 `[far/middle sight scroll]`；gent 已能出远景，`gate_hendon` 这类本身没有背景数据的图仍是黑底。门对象美术、右上角小地图未做。
- `.til` 里 `[pass type] = 3` 的语义未定；`[extended tile]` 的绘制顺序未接。
- 赫顿玛尔（旧 id 2）不在 `region/arad.rgn` 的 towns 列表里，UI 暂时归“其他地区”；若要归到阿拉德，需要单独做 id 映射。
- 城镇列表 UI 目前只列 index 里的城镇，不显示副本入口/传送点；`-2/-2` 只负责开列表。
