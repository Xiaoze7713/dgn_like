# 把 DNF 客户端资产迁到 Godot 4 —— 方案与取舍

> 2026-11-05。所有资产统计口径来自本机实扫（`/mnt/e/dnf-sf/sf115/人造神客户端/`，只读），
> Godot 侧结论标注了出处（官方文档）或「需实测」。格式细节见
> [`docs/NPK-FRAME-BYTES.md`](NPK-FRAME-BYTES.md)，行业对比见
> [`docs/NPK-ASSET-PIPELINE-VS-MODERN.md`](NPK-ASSET-PIPELINE-VS-MODERN.md)。

---

## 0. 先划清边界：你要迁的其实是四坨东西，不是一个

| 目录 / 文件 | 实测体积 | 内容 | 迁移难度 |
| --- | --- | --- | --- |
| `ImagePacks2/` | **28.53 GB**，4,730 个 `.NPK`，211,456 个 `.img`，**28,777,699 帧** | 所有精灵/动画/UI/图标 | ★★ 格式已 100% 破完，工程量大但无未知 |
| `SoundPacks/` | **1.72 GB**，152 个有效 `.NPK`，**61,883 个 `.ogg`** | 音效，ogg **未压缩存储**（明文 `OggS` 头） | ★ 直接能读 |
| `Music/` + `audio.xml` | **2.47 GB / 997 个 ogg** + 2 MB 映射表 | BGM + 事件 ID → 文件映射 | ★ |
| **`Script.pvf`** | **923 MB** | 技能/怪物/物品/地图/任务的全部数值与脚本 | ★★★★★ **真正的瓶颈** |
| `Fonts/` `Video/` | 66 MB ttf + 80 MB avi | 字体、过场 | ★ |

**关键判断：图像是"量大但已解完"，PVF 是"体量小但没开始"。**
`Script.pvf` 的头部是加密/压缩的（前 64 字节无明文 magic），本机有
`/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/pvfUtility.exe` 可以尝试导出。
**如果只是做美术/表现层迁移，PVF 可以最后再说；如果要复刻玩法，PVF 就是主要工作量。**

另有一条数据质量警告：SoundPacks 里有 **14 个文件根本不是 NPK**（`magic` 分别是
`function procSet`、`MZ\x90\x00`（PE 可执行）、`\xfa\xfaRIQS...TRAP`）。
这是私服客户端被改过的痕迹。**迁移前先做一次完整性体检**，别把可疑二进制带进新工程。

---

## 1. 三条路线，先选对

| | A. 运行时直读 NPK | B. 离线全量烘焙 | C. 混合（推荐） |
| --- | --- | --- | --- |
| 做法 | Godot 里实现 NPK/IMG 解码器，`FileAccess` 随机读 + inflate + `ImageTexture` | 全部转成 PNG + `SpriteFrames`/`.tres` + 导入管线 | 先 A 跑通玩法，逐步把热路径换成 B |
| 启动成本 | 低（几天出画面） | 高（要在磁盘上造 21 万资源） | 低 |
| VRAM 压缩 | ✗ 运行时只能未压缩（除非 `PortableCompressedTexture2D`） | ✓ 导入管线可选 BC7/ASTC/UASTC | ✓ |
| 编辑器 | 不污染工程 | **21 万资源会把编辑器拖死** | 可控 |
| 热更 | 换 NPK 就行（和现在一样） | 要重新烘焙 + 重打包 | 分层 |
| 28.5 GB 原样可用 | ✓ | ✗ 需要额外磁盘 | ✓ |

**为什么推荐 C**：Godot 的 VRAM 压缩**只发生在导入管线里**
（[Importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)），
运行时生成的纹理默认是 4B/px 未压缩。但全量烘焙 21 万资源既不现实也没必要——
先算清楚"必须常驻"的到底有多少。

### 为什么"全量常驻"是伪命题（实测）

| 项 | 实测值 |
| --- | --- |
| 平均每帧画布 | **28,634 像素**（约 169×169） |
| 全部 2,877 万帧常驻 VRAM（ARGB8888） | **≈ 3.3 TB** |
| 同上，换 BC7（1B/px） | **≈ 0.82 TB** |
| 帧尺寸分布 | ≤64: 35%，65–128: 24%，129–256: 21%，257–512: 14%，>512: 4%，最大 1368×1113 |

**3.3 TB 说明：无论如何都必须流式加载 + LRU 淘汰**，这不是优化项而是前置条件。
BC7 把 3.3TB 变 0.82TB 也仍然是"绝不能全驻留"，所以 VRAM 压缩的收益体现在
**同一场景能塞多少内容**，不是"能不能装下"。

### 运行时能不能也拿到压缩纹理？能调用，但别指望它在发行版里工作

`PortableCompressedTexture2D` 确实存在，可以**在代码里创建**压缩纹理（不用导入管线）。
签名是 `create_from_image(image, compression_mode, normal_map=false, lossy_quality=0.8)`，
模式枚举是 `LOSSLESS=0, LOSSY=1, BASIS_UNIVERSAL=2, S3TC=3, ETC2=4, BPTC=5, ASTC=6` ——
**所以它确实能生成 BC1/BC7 级别的显存压缩纹理。**

但有两个硬约束让它靠不住：

1. **官方推荐口径**：「For 2D usage (compressed on disk, uncompressed on VRAM), the lossy and
   lossless modes are recommended」（[类文档](https://docs.godotengine.org/en/stable/classes/class_portablecompressedtexture2d.html)）。
   也就是说 2D 场景官方只背书 disk 压缩 + VRAM 未压缩这条路，省 RAM 不省 VRAM。
2. **编码器在导出模板里可能不存在**：S3TC 编码器在 `modules/cvtt`，其 `config.py` 是
   `return env.editor_build` —— 只在**编辑器构建**里编译。所以发行版里
   `Image.compress(COMPRESS_S3TC)` 预计返回 `ERR_UNAVAILABLE`（BPTC/ASTC/ETC2 需实测）。

**结论：压缩必须在构建期做，不要在运行时做。** 阶段 0 真想用它，只用 `LOSSLESS`/`LOSSY`
来降低常驻 RAM，别指望省 VRAM。

### KTX2 看起来是银弹，其实有个致命细节

4.3+ 有 `ResourceFormatKTX` 注册了 `ktx`/`ktx2` 扩展名，`ResourceLoader.load("res://x.ktx2")`
能直接拿到 `ImageTexture`（经 libktx 在加载时转码），也能从 `.pck` 里读。听起来正好是
"构建期压成 KTX2、运行时零 CPU 转码"——**但是**：`modules/ktx/texture_loader_ktx.cpp` 里，
如果 KTX2 带 `KHR_DF_TRANSFER_SRGB`，源码会直接把目标格式设成 `KTX_TTF_RGBA32`
（注释就写着 `// TODO srgb native support`），**转码成未压缩 RGBA8**。

DNF 的美术是 sRGB 的，所以**走 KTX2 等于零显存压缩**——这是最容易踩的坑，比 BC7 画质问题更隐蔽
（因为看起来"压缩成功了"，实际显存一分没省）。

**正确路径只有一条：走导入管线转 `.ctex`（即 Import 面板里的 VRAM Compressed 设置）。**

---

## 2. 阶段 0：用纯 GDScript 跑通（1 周内可验证）

好消息：**不需要 GDExtension 就能起步**。Godot 4 内置了这些：
`FileAccess.seek/get_buffer`、`PackedByteArray.decompress(n, PackedByteArray.COMPRESSION_DEFLATE)`（就是 zlib）、
`Image.create_from_data(w, h, false, format, data)`、`ImageTexture.create_from_image(img)`。

```gdscript
# 骨架：从 NPK 直接取一帧画到屏幕上
const KEY := "puchikon@neople dungeon and fighter " + ("DNF".repeat(256)).substr(0, 255) + "\u0000"

func _name_id(raw: PackedByteArray) -> String:
    var out := PackedByteArray(); out.resize(256)
    for i in 256: out[i] = raw[i] ^ KEY.unicode_at(i)
    return out.get_string_from_utf8()   # 实际按 GBK 解，中文名需转换

func _load_frame(path: String, img_idx: int) -> Image:
    var f := FileAccess.open(path, FileAccess.READ)
    f.seek(16); var n := f.get_32()
    f.seek(20 + img_idx * 264)
    var off := f.get_32(); var size := f.get_32()
    f.seek(off); var raw := f.get_buffer(size)          # 整个 .img
    # IMG: 32B 头(16B magic + tableLength + 0 + version + frameCount) + 帧记录 + 帧体
    ...
    var px := body.decompress(w * h * 4, PackedByteArray.COMPRESSION_DEFLATE)
    return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px)
```

三个必须知道的点（都已经在格式文档里验证过）：

1. **8888 像素是 B,G,R,A**。若直接塞进 `FORMAT_RGBA8`，红蓝会互换。
   阶段 0 最省事的做法不是 CPU 逐像素交换（GDScript 里太慢），而是
   **在 `CanvasItem` 着色器里做 `COLOR.rgb = COLOR.bgr;`**——零 CPU 成本。
   代价是这些精灵要走自定义材质，和其他材质的精灵不合批。**阶段 1 烘焙时再在离线端交换掉。**
2. **DXT 帧可以直接喂给 GPU**：`type ∈ {0x12,0x13,0x14}` 用
   `Image.FORMAT_DXT1/DXT3/DXT5`，`Image.create_from_data` 不用 CPU 解码。
   v5 的 DDS 字节流同理。这部分只占 ~3%，但省下的解码时间很可观。
3. **未压缩帧的 `length` 字段是脏的**，必须按 `w*h*bpp` 推进游标，否则后面的帧全错位。
   全语料有 52 例（独立复现），不能用 `length` 走帧体。

---

## 3. 阶段 1：离线烘焙（关键设计）

### 3.1 烘焙单位 = 一个 `.img` = 一个动画

平均每个 `.img` **136 帧 / 134.9 KB**。这个粒度天然适合做"一张图集 + 一张动画表"。

```
sprite/character/swordman/.../sm_body0000.img
   →  atlas/sm_body0000.png        (一张图，Region 由 JSON 描述)
   →  anim/sm_body0000.json        (帧序 + 每帧 region + (x,y) 偏移 + duration)
```

Godot 侧的对接方式二选一：

- **官方 `TextureAtlas` 导入类型**（Import 面板里可把图片导入成 atlas，
  "Can be used to reduce memory usage for animated 2D sprites. Only supported in 2D"）——
  需要一个描述各区域的 JSON 元数据文件，正好由烘焙器生成。**需实测该 JSON 的确切 schema。**
- **自写 `ResourceFormatLoader`** 读自己的 `.dnanim` 二进制，运行时拼 `AtlasTexture`。
  更可控，但多写一层。（4.3+ 的 `_load()` 在 XML 里标了 `qualifiers="virtual"`，
  **GDScript 可以直接覆写**，不必写 GDExtension。）

### 3.1.1 一个必须提前决定的细节：每帧的 `(x, y)` 往哪放

DNF 每帧都带 `x, y` 锚点偏移，而 **`SpriteFrames` 没有 per-frame offset** ——
`add_frame(anim, texture, duration, at_position)` 只有纹理和时长。所以三条路：

| 做法 | 说明 | 评价 |
| --- | --- | --- |
| ① 每帧一个 `AtlasTexture` + 逐帧改 `AnimatedSprite2D.offset` | 用 `frame_changed` 信号驱动 | **最慢**，等于每帧一次属性写 + 破坏 `SpriteFrames` 的纯粹性 |
| ② **把 `(x,y)` 烘进统一的帧画布** | 烘焙时把每帧贴到"动画级公共画布"的对应位置，运行时偏移恒为 0 | **推荐**，零运行时成本；代价是画布变大（先算过：帧已裁到内容边界，公共画布扩张需实测） |
| ③ 自写 `Node2D`，直接 `RenderingServer.canvas_item_add_texture_rect_region` | 完全自己控 | 最灵活，但放弃 `AnimatedSprite2D` 的便利 |

选 ② 的话，`AnimatedSprite2D` 记得把 **`centered` 设为 `false`**（默认 `true`，
像素画会出现半像素采样变形），并把 `texture_filter` 设成 `TEXTURE_FILTER_NEAREST`
（项目级默认是 Linear，`rendering/textures/canvas_textures/default_texture_filter` 改成 1）。
需要像素吸附就开 `rendering/2d/snap/snap_2d_transforms_to_pixel`，
但**不要**和 `snap_2d_vertices_to_pixel` 同时开（官方不建议，二者同开会互相打架）。

**不要**生成 21 万个 `.tres`。编辑器扫 21 万资源会卡到不可用，`.godot/imported/` 也会爆。
正确做法是"一个 `.img` → 2 个文件"，并且**先做引用分析只烘焙用到的**。

### 3.2 引用分析：这是省 80% 工作量的那一步

28.5 GB / 21 万 img 里，一个单机版/私服实际用到的可能是 10–30%。
`Script.pvf` 里的技能/怪物配置就是引用清单。**先解析 PVF 拿到引用表，再决定烘焙范围**——
即使 PVF 解析只做到"能导出字符串表"这种程度，也足够做引用统计。

### 3.3 压缩策略：必须按 alpha 分类，不能一刀切

我按帧的 alpha 分布扫了 5,737 帧，结果很关键：

| 类别 | 判据（半透明像素占比） | 占帧数 | 典型内容 | 建议导入设置 |
| --- | --- | --- | --- | --- |
| **硬边** | < 1% | **79.4%** | 角色、怪物、UI、图标（像素画，alpha 基本只有 0/255） | **Lossless WebP**，或 8-bit 索引 + 调色板 |
| 混合 | 1–10% | 2.3% | 带一点柔边的贴图 | VRAM Compressed (High Quality) 可接受 |
| **柔边** | > 10% | **18.3%** | 光效、爆炸、魔法阵、渐变阴影 | **BC7 / ASTC 4×4**，压缩率极高且几乎无损 |

**Godot 官方对像素画的态度很明确**：
"VRAM Compressed ... should be avoided for 2D as it exhibits noticeable artifacts,
especially for lower-resolution textures"、"Even in 3D, 'pixel art' textures should
have VRAM compression disabled"（[Importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)）。
所以**79.4% 的硬边帧不要硬上 BC7**。

但像素画有一个**零画质损失的 4 倍方案**，而且正是 DNF 自己 v4/v6 干的事：

> **8-bit 索引纹理 + 调色板 LUT**。把 RGBA 量化成 ≤256 色 → `FORMAT_R8` 上传（1B/px），
> 调色板做成 256×1 的 RGBA8 贴图，在 `CanvasItem` 着色器里 `texture(palette, vec2(idx, 0.5))`。

- 显存 4× 降、画质**完全无损**（只要调色板 ≤256 色，DNF 的像素画基本都满足）
- 代价：需要自定义材质（和内置材质不合批，但同类精灵仍可合批）
- 这条路比 BC7 更适合 79.4% 的硬边帧，**建议在 PoC 里就试掉**

另外：**`Compress > High Quality` 只在 Forward+ 和 Mobile 渲染器生效，Compatibility 渲染器永远关闭**
（同上文档）。如果要上 Web/低端设备，就得放弃 BPTC/ASTC —— 这是**渲染器选择上的硬约束**，
要在项目立项时决定。

### 3.3.1 导入设置的精确名字（照抄，别猜）

`compress/mode` 的枚举**只有 5 个值**，没有 "VRAM Compressed (BC7)" 这种复合选项：

```
Lossless(0)  Lossy(1)  VRAM Compressed(2)  VRAM Uncompressed(3)  Basis Universal(4)
```

真正决定块压缩格式的是另一个开关：

| `compress/high_quality` | 桌面 | 移动 / Web |
| --- | --- | --- |
| `false`（默认） | **S3TC**：不透明用 BC1/DXT1，带 alpha 或 normal_map 用 BC3/DXT5，法线用 RGTC | ETC2 |
| `true` | **BPTC**：SDR 用 BC7，HDR 用 BC6H | **ASTC** |

其他和像素画相关的默认值：`compress/lossy_quality=0.7`、`mipmaps/generate=false`（非 3D 预设）、
`process/fix_alpha_border=true`（**保留它**，否则图集边缘采样会出血）。

`Basis Universal` 在 4.3/4.4/4.5 里**只用 UASTC**（源码 `params.m_uastc = true`，无 ETC1S 选项），
而且它是"转码"路线、有轻微质量损失——对 DNF 这类像素画不是首选。

### 3.4 图集体积控制

- 单张图集别超过 **4096×4096**（移动端上限）。
- 大动画（如 500×500 × 242 帧 ≈ 60M 像素）**一张图塞不下**（4B/px 就是 240 MB）。
  这类动画必须**分页 + 帧窗口流式**：只保留当前帧前后 N 帧的页，其余淘汰。
- DNF 的帧本身已经裁到内容边界（实测 trim_ratio = 0.997，画布基本没有多余透明边），
  所以"再裁一遍"这条优化不成立——省不到东西。

---

## 4. 阶段 2：音效与数据

- **ogg 直接可用**：Godot 4 原生 `AudioStreamOggVorbis`。61,883 个音效 + 997 个 BGM 直接复制成文件即可，
  NPK 外壳没有保留价值（`OggS` 明文存储，不需要解码）。
- **`audio.xml` 就是事件表**：`<EFFECT ID="SM_ATK_01" FILE="sounds\char\swordman\sm_atk_01.ogg"/>`，
  解析成 `Dictionary[String, String]` 即可，2 MB 一次性载入。
- **`Script.pvf`（923 MB）**：单独立项。本机有 `pvfUtility.exe` 可尝试导出；
  导出后建议不要原样塞进 Godot，而是**转成 JSON/`.tres`/SQLite**，按需加载。
  这是唯一一个"没有捷径、只能啃"的部分。
- **`Video/` 的 avi（80 MB）**：已核实 —— Godot 4 的 `VideoStreamPlayer` 只原生支持
  **Ogg Theora（`.ogv`，`VideoStreamTheora`）**，其他格式必须靠 GDExtension 插件
  （[VideoStreamPlayer](https://docs.godotengine.org/en/stable/classes/class_videostreamplayer.html)）。
  所以 avi 的处理办法是确定的：**用 ffmpeg 批量转 `.ogv`**（`ffmpeg -i x.avi -c:v libtheora -q:v 7 x.ogv`）。
  DNF 的 avi 只有 17 个 / 80 MB，转码成本可以忽略，不建议为此引入插件。

---

## 5. 阶段 3：打包与热更

| 需求 | Godot 做法 | 注意 |
| --- | --- | --- |
| 分片打包 | 多个 `.pck`，`PCKPacker.pck_start(path, alignment=32, key, encrypt_directory=false)` + `add_file(target, source)` + `flush()` | 按大区/版本切，单包别超几百 MB；`add_file` 是立即写入，`res://` 前缀自动剥离 |
| 补丁覆盖 | `ProjectSettings.load_resource_pack("patch.pck", true)`（`replace_files=true`） | **后加载覆盖先加载（顺序敏感）**；语义与 NPK 的 `!` 前缀补丁一致，粒度仍是整个文件 |
| 删除文件（补丁） | `PCKPacker.add_file_removal(target_path)`（文档注明"mainly used for patches"） | NPK 做不到这个，这是 Godot **比原方案强**的一点 |
| 真正的增量 | 自建：CDN 上放 FastCDC 分块 + zstd，客户端组包 | Godot 没有内建 delta 更新 |
| 完整性 | 自建 manifest + per-chunk SHA-256 | `.pck` 本身只有可选的整包加密/校验 |

**注意**：`load_resource_pack(..., true)` 能解决"补丁覆盖"，但解决不了"只下一次改动"。
如果目标是省流量，仍然要自己做内容分块，`replace_files` 那套只适合"整包覆盖"。
另外挂载后 `DirAccess` **不会列出**新增文件，所以资源清单要自己维护（或直接按约定路径去 `load`）。

---

## 6. 该拥抱的新技术（按收益排序）

| # | 技术 | 替代掉的做法 | 收益 | 代价 |
| --- | --- | --- | --- | --- |
| 1 | **按动画的图集 + 合批** | 每帧一个纹理 | 66% 的帧 ≤256px，各自一个纹理时 draw call 爆炸；合批后一屏几十次 | 烘焙器工作量 |
| 2 | **8-bit 索引 + 调色板**（硬边像素画） | 4B/px 未压缩 | 显存 **4×**、**零画质损失** | 自定义材质 |
| 3 | **BC7/ASTC**（只给柔边/光效） | 4B/px 未压缩 | 显存 4×，光效类几乎无损 | Compatibility 渲染器不可用 |
| 4 | **异步流式 + 帧窗口** | 一次性载入整个 img | 3.3 TB → 几百 MB 常驻，进图不卡 | **Godot 没有 LRU，得自己写** |
| 5 | **shader 替代叠图特效** | 逐帧画好的闪光/描边/溶解 | DNF 大量特效是"多张图叠加 + 变色"，用 `CanvasItem` shader 可实时做，帧数直接减 | 要逐个核对观感 |
| 6 | **骨骼动画（Bone2D/Spine）** | 逐帧 | 只用于**新内容**；老资产 2877 万帧不要重做 | 美术重制成本 |
| 7 | **TileMapLayer 做地图背景** | 整张大图 | 城镇/地牢背景可以瓦片化，显存和流式都更好 | 需要 PVF 的地图数据 |

### 关于第 1 项：合批到底靠什么（源码级）

2D 合批（`RendererCanvasRenderRD`）在下列任一变化时**打断并开新批次**：

```
final_clip_owner 变 / material 变 / use_lighting 变 / Command 类型变
/ has_blend 变 / 调制色变 / tex_info 变(纹理 + filter + repeat + msdf + linear 色彩)
```

所以能让它合批的写法是：**同 CanvasLayer + 连续绘制 + 同一张纹理（且同 filter/repeat）
+ 同 material + 同 blend + 同受光状态**。`per-instance` 的 transform/modulate **不**打断合批。

反过来，**`z_index`、`y_sort_enabled`、`CanvasGroup`、`clip_children` 都会改绘制顺序 → 直接切段**。
DNF 的 UI 大量靠 z 序叠层，迁移时要把"层级"尽量压成 `CanvasLayer` 分组 + 组内连续绘制，
而不是每层一个 `z_index`。可调 `rendering/2d/batching/item_buffer_size`（默认 16384）。

### 关于第 4 项：为什么必须自己写缓存

`core/io/resource.cpp` 里的 `ResourceCache` 是 `HashMap<String, Resource *>`，存**裸指针**，
`Resource::~Resource()` 把自己从表里删。也就是说：

- **没有容量上限，也没有淘汰策略** —— 不是 LRU，也不是"永不释放"；
- 行为是"最后一个引用丢掉就销毁"，所以真正的策略必须由你在资源句柄上做（保活/丢弃）。

配套 API：`load_threaded_request(path, type_hint, use_sub_threads, cache_mode)`、
`load_threaded_get_status(path, progress)`（`INVALID=0/IN_PROGRESS=1/FAILED=2/LOADED=3`，跨帧轮询）、
`load_threaded_get(path)`（未完成会阻塞）。`CacheMode` 有 `IGNORE=0/REUSE=1/REPLACE=2/IGNORE_DEEP=3/REPLACE_DEEP=4`。

**不要拥抱的**：`VRAM Compressed` 默认档（S3TC/BC1）压像素画——BC1 只有 1-bit alpha，
DNF 的描边和半透明边缘会直接烂掉。

---

## 7. 明确不要做的八件事

1. **不要把 21 万 img / 2,877 万帧全量导入 Godot 工程**。编辑器扫不动，`.godot/imported/` 会爆。
2. **不要一开始就啃 `Script.pvf`**。先用阶段 0 的运行时读取器把玩法原型跑起来，PVF 按需增量解析。
3. **不要用 Compatibility 渲染器**（如果你要用 BPTC/ASTC）。
4. **不要给硬边像素画开 mipmap 或线性过滤**（`texture_filter = NEAREST`）。
5. **不要相信 NPK 里的 `length` 字段**（52 例脏数据），一律按 `w*h*bpp` 算。
6. **不要把 SoundPacks 里那 14 个被替换成 PE/脚本的假 NPK 带进新工程**。
7. **不要把 KTX2 当成省显存方案**：sRGB 的 KTX2 会被强制转码成未压缩 RGBA32，等于**零压缩**。
   要 VRAM 压缩就走导入管线（`.ctex`），不要绕道 KTX2。
8. **不要在运行时调 `Image.compress()` 指望它压出 S3TC**：cvtt 编码器只在编辑器构建里编，
   导出模板里预计 `ERR_UNAVAILABLE`。压缩属于构建期工作。

---

## 8. 建议的推进顺序（含验收标准）

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| **P0（3–5 天）** | GDScript NPK 读取器 + `AnimatedSprite2D` 播放一个怪物动画 | 屏幕上动起来，颜色正确（红蓝不换） |
| **P1（1 周）** | 帧窗口 LRU 缓存 + 多动画切换（待机/走路/攻击） | 常驻显存 < 300 MB，切动作不卡顿 |
| **P2（2 周）** | 烘焙器：引用分析 → 图集 + 动画表 → `TextureAtlas`/自定义 loader | 同一动画从"运行时解包"换成"烘焙资源"，观感一致 |
| **P3（1 周）** | 压缩策略验证：索引调色板 vs BC7 vs 无损，做 3 组对照 | 有数据决定 79.4% 硬边帧走哪条路 |
| **P4** | 音频（ogg + audio.xml）、pck 分片、补丁 | 音效全通、热更可用 |
| **P5** | `Script.pvf` 解析 + 玩法层 | 单独评估，不要和资产管线绑在一起 |

---

## 9. 复现与工具

- 资产统计脚本（纯 stdlib + numpy）：`/tmp/byteacct.py`、`/tmp/dup.py`、`/tmp/nameacct.py`、
  `/tmp/packstats.py`（未入库）
- NPK/IMG 解码器（已验证 4,730 包）：`tools/npk_parser.py`；逐字节讲解工具：`tools/npk_hexwalk.py`；
  V1 老格式：`tools/npk_v1_walk.py`
- 迁移时直接把这些 Python 逻辑改写成 GDExtension C++ 即可，规格层面没有未知项
