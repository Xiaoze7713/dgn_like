# utils/npk —— 运行时读 NPK（不落地任何中间文件）

把「NPK 里的 `.img`」变成 Godot 的 `Texture2D`，全程在内存里。世界运行时用 `NpkStore.open_live(ImagePacks2)`：直接扫目录名、按路径猜包名，不再依赖离线生成的 `assets/npk-index-latest.bin`。

```
PVF 里的一条资源路径
      │  character/swordman/equipment/avatar/skin/sm_body0001.img
      ▼
NpkIndex   查索引（FNV-1a 64 哈希二分）→ 包名 + offset + size
      ▼
NpkStore   打开该 .npk（LRU 12 个句柄）→ FileAccess.seek → 读 264B 索引项 → 读数据
      ▼
NpkImage   解 IMG 容器（v2/v4/v5/v6、ARGB1555/4444/8888/索引/DXT）→ Image
      ▼
ImageTexture（LRU 800 张）
```

## 文件

| 文件 | 作用 |
| --- | --- |
| `npk_index.gd` | 旧的离线索引读取；`from_dir()` 可全量扫 `ImagePacks2`（太慢，仅测试用） |
| `npk_live_index.gd` | `NpkLiveIndex`：只列 `.npk` 文件名，按路径段猜候选包，命中后只读该包表 |
| `npk_image.gd` | 纯 GDScript 的 IMG 解码器（等价于 `tools/npk_parser.py` 的帧解码部分） |
| `npk_store.gd` | 门面：包句柄 LRU、Img 解析缓存、贴图缓存、`texture(img, frame)` |

## 运行时动态索引（world 使用）

```gdscript
var store := NpkStore.new("/mnt/d/dnf_latest/ImagePacks2")
store.open_live()          # 不读任何 .bin；NpkLiveIndex 按需读包表
```

`NpkLiveIndex.find()` 把 `map/npc/origin_seria.img` 变成候选
`sprite_map_npc.npk` → `sprite_map.npk`，只读命中的包的 264 B 表。实测首次候选命中 22–27 ms；
全量扫 16,392 个包要 114 s，所以**不要**在启动时全量扫。

## 离线索引（旧路径，仅供兼容）

```bash
python3 tools/mk_npk_index.py \
  --pack-dir "/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2" \
  --out "analysis/sf85/npk-index.jsonl.gz" \
  --bin "client/assets/npk-index.bin"
```

- **.bin 布局（小端）**：`"NPKIDX02"`(8) + `u32 count` + `u32 0` +
  `record[count]`（20 B：`u64 hash, u16 pack_id, u16 pad, u32 offset, u32 size`）+
  `u16 pack_count` + 每包 `u16 len + utf-8 相对路径`。
- record 按 hash 升序；hash = FNV-1a 64，对小写 UTF-8 路径。
- sf85 实测：4,085 个包 / 137,471 条 img / 索引 2.9 MB / 扫描 10 s。
- 全表只有 9 条路径含非 ASCII（GBK 老文件名），用 UTF-8 路径查不到，属已知限制。

## 包目录怎么找（Windows / Linux 差异）

`NpkStore._resolve_dir()` 依次：

1. `Sf85Assets.open(..., npk_dir)` 显式传入
2. 环境变量 `DNF_NPK_DIR`
3. 项目设置 `npk/base_dir`（`project.godot` 里加 `npk/base_dir="E:/dnf-sf/sf85/老牛DNF客户端/ImagePacks2"`）
4. 平台默认：`/mnt/e/dnf-sf/...`（WSL）、`E:/dnf-sf/...`（Windows）

索引里只存**相对包名**（如 `Sprite_character_swordman.NPK`），所以同一份
`npk-index.bin` 在 Windows 和 WSL 都能用，只要包目录指对。

## API

```gdscript
var store := NpkStore.new()                 # 可选：NpkStore.new("D:/dnf/ImagePacks2")
store.open("res://assets/npk-index.bin")

var tex := store.texture("character/swordman/animation/move.img", 3)
var rect := store.frame_rect("...move.img", 3)   # Rect2i：该帧内容在画布里的落位
print(store.stats())    # {count, packs, open_packs, cached_tex, cached_img, hits, misses, ...}
store.trim(320, 24)     # 换图后显式裁剪：最多保留 320 张纹理、24 张解码 Img
```

`texture()` 的路径**可以不带 `sprite/` 前缀**（PVF 里就不带），内部会自动补；
大小写也做了归一（索引里是小写）。

`frame_rect()` 返回的 `Rect2i.position` 是该帧在原始画布中的原点。**NPC 必须加上它**：
NPC 的 `.ani` 帧 `[IMAGE POS]` 只是相对偏移，漏掉画布原点会整体浮空（见
`game/world/build/ani_sprite.gd` 的 `apply_canvas_offset`）。装饰/背景已经在
`RoomBuilder` 里加过画布原点，不能再加，否则二次偏移。

缓存：`_tex` 上限 800 + 总字节 `MAX_TEX_BYTES=64 MB`、`_img` 上限 48、包句柄 12；命中会把 key
移到队尾，淘汰从队首（最久未用）开始；`trim(keep_tex, keep_img)` 再从队首裁。
本项目换房间时在 `WorldDirector._unload_room()` 调 `trim(320, 24)`。

v5 的 DDS 记录：`dds_table[i].full_length` 是**压缩后**字节数（`_read_bodies` 用它切片），
`length` 才是解压后的字节数；`decompress` 的输出缓冲必须用 `length`，用 `full_length*4`
会让大图报 `decompress err != 1` 并退化成占位图。

## 性能（sf85 / 137k 条索引）

| 项 | 实测 |
| --- | --- |
| 索引加载 | 14 ms |
| 单帧解码（ARGB1555/8888/索引） | 1~3 ms |
| 13 帧混合解码 | 26 ms |
| 整场景首次进入（PVF 打开 + 6 角色 + 27 张贴图） | **3.6 s** |

首次进入的大头是 PVF 打开（30 MB 目录树解密）与 `.ani` 解析，不是 NPK。

## 正确性

`tests/test_npk_store.gd` 对 13 帧打 md5，`tools/verify_npk_gd.py` 用 Python
`tools/npk_parser.py` 解同样帧对比 —— **13/13 完全一致**（覆盖 v2/v4、
ARGB8888/1555、索引调色板、zlib、`map/` 图）。

## 已知限制

- v5（DDS 共享贴图）路径**没在 sf85 上实测过**（抽样 400 张：v2 374 / v4 26 / v5 0），
  代码保留，110 版客户端才会用到。
- 9 条非 ASCII 文件名查不到（见上）。
- 索引需要离线重建一次（换客户端版本时要重跑 `mk_npk_index.py`）。


## DDS 回归（2026-11-25）

- `tests/npk_dds.gd`：直接读 `Map/Act8/background/far.img`（DXT1）与
  `Map/LuftHafen/middle.img`，断言纹理尺寸 556×489 / 895×297。
- DDS 头的 fourCC 在偏移 **84**（不是 20）。读错时 DXT1/DXT5 全部退化为 1×1
  占位图，表现是背景/中景整层黑掉；这个回归用例专门守这个点。
- `tests/npk_dxt.gd`（14 项）：合成 DXT1/DXT3/DXT5 块 + 未压缩 DDS，守护
  - DXT1：`c0 <= c1` 且颜色索引 3 → alpha 0；`c0 > c1` 时索引 3 仍不透明；
  - DXT3：每像素 4bit alpha（0x7 → 119）；
  - DXT5：alpha 标准表（`a0 > a1` 用 `/7`，`a0 <= a1` 用 `/5` + 0/255）；
  - DXT3/DXT5 的颜色块在 `p+8`（不是 `p`），否则颜色会从 alpha 块读，整张图颜色错乱；
  - 未压缩 DDS 要先跳过 128B 头，按 bits + mask 解，不能把 DDS 头当像素。
- 与 JS NPK Inspector 做过逐像素对照（`tools/npk_inspector/core/npk_core.js`）：
  `Map/Gent_afterwar/GentTile.img`（DXT5）与 `Map/Act8/background/far.img`（DXT1）
  的 RGBA SHA-256 完全一致。

## DDS 必须走引擎原生解码（2026-11-26）

- v5 共享贴图是 `DDS ` 头 + DXT 负载，**不要**再用 GDScript 的 `_dxt()` 逐像素解大图。
- `npk_image.gd::_dds_frame()` 现在先试 `Image.load_dds_from_buffer(blob)`；压缩格式要先 `decompress()` 再 `convert(FORMAT_RGBA8)`，最后按帧 `left/up/right/down` 裁剪。
- GDScript `_decode_dds/_dxt` 仅保留为原生解码失败时的兜底。
- 证据：`wahrheit` 的 `Cloud.img` 逐像素单帧 563ms，原生 34ms；整图 21 个动画全帧 49.1s → 0.47s，房间 build 3.07s → 0.28s。 
- 回归：`tests/npk_dds.gd`（6 项）覆盖 Cloud/Gear_Big/Barrier/Bottom_Close 的尺寸。
