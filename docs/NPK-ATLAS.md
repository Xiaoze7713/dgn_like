# NPK → 图集管线（P0.6 收尾）

> 上游：`docs/NPK-FORMAT.md`（NPK/IMG 二进制格式，t6 产出）、`docs/GODOT-EVAL.md` C1/C2。
> 本文只讲**怎么把 20 万个 `.img` 变成 Godot 能直接吃的页纹理 + 帧矩形表**。

---

## 0. 为什么必须先做图集

`docs/GODOT-EVAL.md` C1 的实测结论是硬约束：

| 做法 | 实测 |
| --- | --- |
| 2,000 张 64×64 PNG 当资源导入编辑器 | 2.9 s |
| 5,000 张 | 32 s |
| 20,000 张 | > 5 分钟 |
| 1,058,561 个 `.ani`（每个含多帧） | 不可行 |

本库有 **207,626 个 `.img` / 28,775,224 帧**（t6 全量 census）。所以路线只有一条：

```
NPK（33 GB，磁盘）
  └─[离线] npk_parser 解码 → npk_atlas 按 .img 打包 → 页 PNG + 帧矩形表（export/atlas）
                                    └─[运行时] 只读 manifest + 按需加载页 + region_rect 渲染
```

引擎侧**不导入 png 为资源**，用 `Image.load_png_from_buffer()` 从磁盘直接读，
`Sprite2D.texture = 页纹理`、`Sprite2D.region_rect = 帧矩形`。

---

## 1. 命令

```bash
# 主产物（推荐：页尺寸自适应，显存省 8 倍）
python3 tools/npk_atlas.py build --adaptive

# 严格 2048×2048 页的版本（对照/合规用）
python3 tools/npk_atlas.py build --out export/atlas_2048

# 先试跑
python3 tools/npk_atlas.py build --limit 8 --out /tmp/atlas8

# 四根抽样解码成功率（monster / character / equipment / map）
python3 tools/npk_atlas.py check --n 200

# 统计页数 / 体积 / 源像素格式分布
python3 tools/npk_atlas.py stats

# 回读校验：manifest → rects 字节区间 → 页 PNG 头
python3 tools/npk_atlas.py verify

# 小批实测（12 只怪 + 剑士技能特效）
python3 tools/npk_atlas.py batch --monsters 12 --skills 20 --json /tmp/batch.json
```

输入清单默认读 `export/_meta/slice_manifest.json`（t12 的切片清单，171 张 `.img`）。
换清单用 `--img-list`，每行 `NPK 文件名<TAB>img 路径` 或只有 `img 路径`。

`build` 的默认参数：`--page-size 2048`、`--out export/atlas`、`--manifest export/_meta/slice_manifest.json`。

---

## 2. 目录结构

```
export/atlas/                         ← 主产物（--adaptive）
  manifest.jsonl                      一行一个 .img（171 行，75.5 KB）
  rects.jsonl                         全部帧矩形，按 .img 顺序连续排列（1.83 MB）
  character/common/skillicon.img.p0.png
  monster/lugaru/casting.img.p0.png
  monster/lugaru/casting.img.p1.png   ← 该 img 溢出一页
  ...
export/atlas_2048/                     ← 同结构，页固定 2048×2048
```

页文件名规则：`<img 路径>.p<N>.png`，**保留 img 的目录层级**（便于人肉排查），
路径里的 `<>:"|?*` 与控制字符替换成 `_`。
对应关系不靠文件名推导——引擎只信 `manifest.jsonl` 里的 `pages[].file`。

---

## 3. 矩形表 schema（`rects.jsonl`）

每行一帧，字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `frame_index` | int | 帧号，0..frame_count-1，**连续不缺号** |
| `w` / `h` | int | 帧像素尺寸（= 帧头 width/height） |
| `x` / `y` | int | 帧在页内的左上角（**页内像素坐标**） |
| `atlas_page` | int | 页号，对应 manifest 的 `pages[atlas_page]`；空帧为 -1 |
| `pivot_x` / `pivot_y` | int | **帧头 (x, y)，即相对角色原点的偏移**，见 §4 |
| `is_reference` | bool | 原记录是不是 `0x11` 指向帧 |
| `ref_target` | int | 解引用后的最终帧号（非指向帧 = 自己） |
| `rotated` | bool | 恒 false（DNF 帧不旋转，装箱也不旋转） |
| `canvas_w` / `canvas_h` | int | 帧头 frameWidth/frameHeight，**编辑器画布尺寸，不参与渲染** |
| `empty` | bool | 空帧（0×0 / 环降级），不要画 |
| `source_format` | str | `argb8888` / `argb1555` / `argb4444` / `indexed` / `dds-argb1555` / `dds-argb8888` / `dxt1` / `dxt3` / `dxt5` / `reference` |

真实两行（`export/atlas/rects.jsonl`）：

```json
{"frame_index":0,"w":28,"h":28,"pivot_x":0,"pivot_y":0,"atlas_page":0,"x":0,"y":0,"empty":false,"is_reference":false,"ref_target":0,"rotated":false,"canvas_w":28,"canvas_h":28,"source_format":"argb8888"}
{"frame_index":347,"w":28,"h":28,"pivot_x":0,"pivot_y":0,"atlas_page":0,"x":644,"y":252,"empty":false,"is_reference":true,"ref_target":346,"rotated":false,"canvas_w":0,"canvas_h":0,"source_format":"reference"}
```

注意第二条：**指向帧不占图集面积**，它的 `x/y/w/h/atlas_page` 直接复制自
`ref_target=346` 那一行，`is_reference:true` 只是告诉引擎“这帧是引用”，
渲染时按 `ref_target` 的矩形取图即可（两个字段值本来就一样，抄过去是为了让引擎
不必再查一次表）。

### manifest（`manifest.jsonl`）

```json
{"img_path":"character/common/skillicon.img","entry":"sprite/character/common/skillicon.img",
 "npk":"sprite_character_common.NPK","version":2,"frame_count":127,"page_size":512,
 "pages":[{"page":0,"file":"character/common/skillicon.img.p0.png","w":512,"h":512,
           "frames":127,"bytes":147254}],
 "page_count":1,"references":0,"cycles":0,"cycle_detected":false,"cycle_frames":[],
 "warnings":[],"decoded":true,"rect_offset":0,"rect_length":26577,"rect_count":127}
```

| 字段 | 说明 |
| --- | --- |
| `img_path` | PVF 里的原路径（去掉 `sprite/` 前缀，和 `.ani`/`.act` 里的写法一致） |
| `entry` | NPK 条目全名（`sprite/...`），排查用 |
| `npk` | 所在 NPK 文件名（同名 img 可能散在多个包，见 §11） |
| `version` | IMG 版本（实测只有 2 和 5） |
| `pages[]` | 页清单：`file` 相对 `export/atlas/`，`w/h` 页尺寸，`bytes` 文件大小 |
| `rect_offset` / `rect_length` | **在 `rects.jsonl` 里的字节区间**，引擎 seek 后按 `\n` 切 |
| `rect_count` | 矩形数 = frame_count |
| `decoded` | true = 解出；false = 整张降级 |
| `warnings[]` | 前 8 条非致命警告（帧解码失败、截断抢救等） |

**引擎加载姿势**（一条 img 的完整信息 = 1 行 manifest + 一段 rects）：

```gdscript
# 只读，不解析整个 rects.jsonl
var man := FileAccess.open("export/atlas/manifest.jsonl", FileAccess.READ)
var rec := JSON.parse_string(man.get_line(idx))          # idx 来自预建索引
var rf := FileAccess.open("export/atlas/rects.jsonl", FileAccess.READ)
rf.seek(rec.rect_offset)
for i in rec.rect_count:
    var r := JSON.parse_string(rf.get_line())
```

---

## 4. 坐标：pivot 怎么用（写错会整体偏移）

`docs/NPK-FORMAT.md` §5.1 的结论，用 `attack1.ani` + `sm_body0000.img` 8 帧叠图验证过：

```
帧在角色坐标系的左上角 = 帧头 (x, y)              → 矩形表的 pivot_x / pivot_y
最终绘制位置           = ( ani.x + pivot_x,  ani.y + pivot_y )
```

- 两套坐标**同源**（都以角色原点为 0），**直接相加**，不需要减半宽半高；
- `canvas_w/canvas_h`（帧头 frameWidth/frameHeight）是编辑器画布，**渲染时忽略**；
  如果拿它去居中，`attack1` 的人物会整体上浮 250 px（实测）；
- 证据图：`analysis/npk/compose_ani_img_offset.png`（8 帧叠合，脚落在原点 y≈325、
  水平中心 192.5 ≈ 锚点 200）。

引擎侧伪码：

```gdscript
func frame_rect(rec, r) -> Rect2:
    return Rect2(r.x, r.y, r.w, r.h)

# 画一帧（ani_x/ani_y 来自 .ani 的 [IMAGE POS]，face 是朝向 ±1）
sprite.texture = pages[rec.pages[r.atlas_page].file]
sprite.region_enabled = true
sprite.region_rect = frame_rect(rec, r)
sprite.position = Vector2(face * (ani_x + r.pivot_x), ani_y + r.pivot_y) + actor.position
sprite.offset = Vector2(r.w, r.h) * 0.5 * Vector2(-1, -1)   # region 以左上角贴，抵消掉
```

> 具体 offset 写法取决于 `Sprite2D.centered`；本管线只保证 **`pivot_x/pivot_y` +
> 页内 `x/y` 是充足信息**，其余是引擎侧的摆放约定。

---

## 5. 打包算法

`ImagePacker`：

1. 逐帧 `img.frame_image(i)` → `(w, h, x, y, rgba)`；**指向帧在此已被解引用**；
   环/越界帧（`resolved < 0`）直接记空帧，不占面积。
2. 帧按高度倒序（大块先放）。
3. 每页一个 `MaxRects` 装箱器，放置用 **Bottom-Left**（先最靠上、再最靠左）。
   - 一开始用的是 best-short-side-fit，实测对 `skillicon.img`（127 个 28×28 图标）
     会把图标沿左边**一列竖着铺到底**再横铺一行——因为 28 宽的窄条 residual 更小，
     BSSF 就选它。改成 BL 后是按行铺开的正常图集。
4. 放不下就开新页；同一张 `.img` 的所有页共用一个页尺寸。
5. `--adaptive`：页尺寸 = `clamp(next_pow2(sqrt(帧面积和 × 1.25)), 64, 2048)`；
   若单帧超过它，抬到 `next_pow2(最大边长)`（上限 8192）。

`--adaptive` 是**显存优化**，不是体积优化（空像素 zlib 压得很好）：

| 构建 | 页数 | PNG 体积 | **显存（w×h×4）** | 页尺寸分布 |
| --- | --- | --- | --- | --- |
| `export/atlas`（adaptive） | 173 | 19.83 MB | **338 MB** | 512:57 / 256:48 / 1024:39 / 128:17 / 2048:7 |
| `export/atlas_2048`（固定 2048） | 171 | 22.57 MB | **2,736 MB** | 2048×2048:171 |

同一批 171 张图，**8 倍显存差**。171 张就 2.7 GB，全量（20 万张）按固定 2048 页是
不可加载的；adaptive 版把“页尺寸”降到内容量级，是小图占比高时的正确默认。

---

## 6. 实测：切片 171 张

```
python3 tools/npk_atlas.py build --adaptive
# 打包 171 张 img（失败 0）：9043 帧、173 页、19.83 MB -> export/atlas
# manifest 75.5 KB / rects 1.83 MB / 用时 5.4 s
```

- 171 张全部解码成功（0 失败）；
- 9,043 帧，指向帧 26 帧（已复用目标矩形），含环 img **0**；
- 169 张 img 单页，2 张需要 2 页（`monster/lugaru/casting.img` 等）；
- `verify` 全部通过（矩形数 = 帧数、矩形不越界、页 PNG 头尺寸与 manifest 一致）。

抽样 `character/common/skillicon.img`（adaptive 页 512×512，127 个技能图标）人眼确认正常。

---

## 7. 抽样验收：四个根 × 50

```
python3 tools/npk_atlas.py check --n 200
# 抽样 200 张（monster=50/character=50/equipment=50/map=50）：
#   成功 197、失败 3、成功率 98.5%，10578 帧，8.1s
```

| 失败样本 | 原因 | 归类（对照 NPK-FORMAT §11.1） |
| --- | --- | --- |
| `sprite/character/swordman/equipment/avatar/skin/sm_body0148.img` | 条目查不到（模板名 `sm_body%04d.img` 未展开命中） | 模板名 |
| `sprite/character/mage/equipment/weapon/spear/mg_avatar3200a.img` | `IMG 数据太短（16 字节，至少 32）` | 16 字节空壳 |
| `sprite/character/swordman/equipment/weapon/lswd/lswd6000c.img` | `帧 0 zlib 解压失败：incorrect header check` | 截断/坏流 |

98.5% ≥ 95% 达标，且 3 个失败都是**已知脏数据类**、都已降级不崩。

> 注：根分类必须**先判 `equipment` 再判 `character`**——装备图大多住在
> `sprite/character/<job>/equipment/...`，先判 character 会让 equipment 永远抽到 0 张
> （第一版就是这么错的，`check` 只凑出 150 张）。

---

## 8. 小批实测：12 只怪 + 剑士技能

“一只怪”在 PVF 里不是一张 `.img`，而是 `sprite/monster/<怪名>/...` 一整个目录
（本体动作 + 各种特效、粒子）。所以 `batch` 按目录分组，统计目录内 `.img` 数量，
取每个目录的一个代表 `.img` 实测，再按目录文件数外推。

```
python3 tools/npk_atlas.py batch --monsters 12 --skills 20
```

| 组 | 目录/图片 | 实测 img | 帧 | 页 | PNG | 外推 |
| --- | --- | --- | --- | --- | --- | --- |
| 12 只怪 | 12 个目录，共 234 个 `.img`（77/38/30/20/12/11/8/8/8/8/7/7） | 12 | 577 | 20 | 18.56 MB | **429 MB** |
| 剑士技能特效 | `character/swordman/effect/*.img` | 20 | 337 | 23 | 3.98 MB | 3.98 MB |
| 合计 | | 32 | 914 | 43 | 22.53 MB | **433 MB** |

- 单个样本均值：577 帧 / 12 ≈ **48 帧/张**、1.55 MB/张（固定 2048 页口径）；
- 外推口径：12 只怪 ≈ 234 张 img × 1.83 MB ≈ 429 MB（固定 2048 页）；
  同样内容的 adaptive 版是 22.50 MB 实测 / 外推 427.89 MB——**PNG 体积接近，
  但显存从 688 MB 降到 661 MB**（这批样本本身都是大图，节省不明显，
  碎图多的 UI/图标类才有 8 倍收益，见 §5 表）。

---

## 9. 全量估算（20 万张）

以切片 171 张的实测均值（52.9 帧/img、0.116 MB PNG/img、1.98 MB 显存/img）外推到
t6 全量 census 的 **207,626 个 `.img` / 28,775,224 帧**：

| 项 | 估算 | 依据 |
| --- | --- | --- |
| 页数 | **≈ 210,000 页**（1.01 页/img） | 171 img → 173 页 |
| 页 PNG 总量 | **≈ 24 GB** | 19.83 MB / 171 × 207,626 |
| 全量显存（若一次装） | **≈ 400 GB** | 338 MB / 171 × 207,626 |
| 矩形表（当前 JSONL） | **≈ 5.7 GB** | 207 B/帧 × 28.78 M 帧 |
| 矩形表（二进制） | ≈ 350–460 MB | 12–16 B/帧，**待做** |

结论：

1. **不可能一次性装显存**，运行时必须按需加载（只装当前场景/角色要用的 img 的页），
   配合 LRU 卸载。`manifest.rect_offset` 就是为“按需 seek”设计的。
2. **矩形表 JSONL 在 20 万张规模下太重**（5.7 GB）。P1 建议加一种紧凑二进制格式
   （每帧 `<iiiihhBB`：x,y,w,h,pivot_x,pivot_y,page,flags = 16 B），
   体积降到 ~460 MB，且引擎侧不用解析 JSON。当前 JSONL 对切片规模（1.83 MB）完全够用。
3. 页 PNG 24 GB 里绝大部分是**当前关卡用不到**的；切片是按需解出来的，不要求预生成全量。

---

## 10. 源像素格式分布

切片 171 张 / 9,043 帧（`stats` 扫 rects）：

| source_format | 帧数 | 说明 |
| --- | --- | --- |
| `argb8888` | 8,347 | 主流 |
| `argb1555` | 548 | 特效 |
| `argb4444` | 122 | 罕见 |
| `reference` | 26 | 指向帧 |

全量口径（t6 census，27.8 M 帧抽样/全量统计）：`0x10` ARGB8888 27,829,633、
`0x0E` ARGB1555 562,834、`0x11` REFERENCE 338,595、`0x0F` ARGB4444 22,014、
`0x12` DXT1 212。→ **ARGB8888 占 99% 以上**。

### DDS（v5）

全库只有 4 个 v5 `.img`，DDS 表格式实测：

| img | 帧 | DDS 记录 | pixel_format | 解码路径 |
| --- | --- | --- | --- | --- |
| `sprite/common/digit/red_systemfont.img` | 11 | 11 | 14→ARGB1555 ×10、16→ARGB8888 ×1 | 裸像素 zlib |
| `sprite/interface2/raid/raid_channel_cn.img` | 69 | 1 | 16→ARGB8888 ×48 | 裸像素 zlib |
| `sprite/monster/ch_monsterface.img` | 235 | 4 | 18→DXT1 ×212 | DDS 头 + DXT1 |
| `sprite/common/digit/tp/tp.img` | 15 | 0 | —（该包内是 v2） | — |

**DXT3（0x13）/ DXT5（0x14）在语料里 0 样本**，只有 `selftest` 与 `analysis/npk/dxt3_alpha_steps.png`
`dxt5_alpha_steps.png` 的合成用例覆盖。

---

## 11. 指向帧 / 环检测

### 实测

- 切片 171 张：指向帧 26 帧，**含环 img 0 张**。
- 扩大扫描（随机 1,000 个 NPK，`parse_bodies=False` 只解记录 + 解引用）：

```
扫描包 1000 / img 41411 / 帧 5555828 / 指向帧 45040 / 含环 img 0 / 读取失败 18 / 91.9s
```

**41,411 张 img、45,040 个指向帧，0 环**。官方数据不带环，环只可能来自
私服手改的 img（`1A冥灵之塔补丁.NPK` 这类）。18 个读取失败是 §7 的脏数据类。

### 降级策略

`npk_parser.Img(data, cycle_policy=...)`：

| 策略 | 行为 | 用在哪 |
| --- | --- | --- |
| `raise`（默认） | 环/超深链抛 `NpkError` | 单张排查、selftest |
| `degrade` | 记 `img.cycles=[{frame, cycle_to}]`，`resolved[frame] = -1`，不抛 | `npk_atlas` 打包 |

`degrade` 下被打包成：`empty: true`、`w=h=0`、`atlas_page=-1`、不占图集面积；
manifest 里 `cycle_detected: true` + `cycles` 计数 + `cycle_frames` 帧号列表。
引擎看到 `empty` 就跳过该帧（画个透明占位），不崩。

### 三个人工确认（合成用例，语料无真实环）

语料 0 环 ⇒ 无法拿真实样本抽查，改用**构造出来的 img** 确认检测有效
（`self_loop` / `two_cycle` / `three_cycle`，以及一条正常链 `chain_ok` 作对照）：

| 用例 | 结构 | `cycle_policy="raise"` | `degrade` 结果 | 打包结果 |
| --- | --- | --- | --- | --- |
| `self_loop` | 帧0 → 0 | `NpkError: 指向帧存在有向环：帧 0 -> 0 -> ... -> 0` | `cycles=[{0,0}]`, `resolved=[-1]` | 1 矩形、**1 空帧**、0 页 |
| `two_cycle` | 0→1→0 | `NpkError: ... 帧 0 -> 1 -> ... -> 0` | `cycles=[{0,0},{1,1}]`, `resolved=[-1,-1]` | 2 矩形、**2 空帧**、0 页 |
| `three_cycle` | 0→1→2→0 | `NpkError: ... 帧 0 -> 1 -> ... -> 0` | 3 条 cycles，`resolved=[-1,-1,-1]` | 3 矩形、**3 空帧**、0 页 |
| `chain_ok` | 0→1→2(实体) | 无异常 | `resolved=[2,2,2]` | 3 矩形、0 空帧、1 页 |

复现命令（构造 img，不依赖语料）：

```
$ python3 tools/npk_atlas.py cycledemo
self_loop    raise   -> 指向帧存在有向环：帧 0 -> 0 -> ... -> 0
             degrade -> cycles=1 resolved=[-1] | 打包：1 矩形、1 空帧、0 页
two_cycle    raise   -> 指向帧存在有向环：帧 0 -> 1 -> ... -> 0
             degrade -> cycles=2 resolved=[-1, -1] | 打包：2 矩形、2 空帧、0 页
three_cycle  raise   -> 指向帧存在有向环：帧 0 -> 1 -> ... -> 0
             degrade -> cycles=3 resolved=[-1, -1, -1] | 打包：3 矩形、3 空帧、0 页
             chain_ok -> cycles=0 resolved=[2, 2, 2]
# 环检测自证：通过（3/3 环捕获、降级为空帧）
```

`python3 tools/npk_parser.py selftest` 里另有“环检测报错 / 指向链 0→1→2”两项同类断言。

---

## 12. 已知问题与待验证

1. **同名 `.img` 散在多个 NPK**：`sprite/monster/ch_monsterface.img` 在 4 个包里
   （v2 216 帧 / v5 235 帧 / v2 215 帧 / v2 212 帧），`red_systemfont.img` 在 3 个包里。
   本管线按清单里指定的 NPK 取；**运行时以客户端实际加载顺序为准**（后加载覆盖），
   待验证：原版客户端的覆盖规则（按包名排序？按加载表？）。
2. **矩形表体积**：JSONL 207 B/帧，全量 5.7 GB。需要二进制格式（§9）。
3. **页数上限**：`--page-size 2048` 时单页 16 MB 显存；一张 300 帧的 400×400 特效
   全部装进 2048 页没问题，但**超长序列（>2,000 帧 img）会开多页**，引擎要支持
   一帧一页的多纹理切换（矩形表已带 `atlas_page`，天然支持）。
4. **v4/v6 未在真实语料出现**（0 个），调色板路径只有合成验证；若接入别的客户端
   版本需要重新抽查。
5. **`--adaptive` 的页尺寸不是 2 的幂上限整除**：Godot 对非 2 的幂纹理在
   Compatibility 渲染器下可用，但 mipmap/循环模式受限；本管线只用最近邻 + 无 mipmap，
   不影响。若将来要 mipmap，需强制 2 的幂（当前实现已经是 2 的幂）。
6. **`.img` 与 `.ani` 的帧数不一致**：`.ani` 的帧数可能小于 `.img`（动画只取前 N 帧），
   也可能引用 `[SUB ANI]`/`[ADD ANIMATION]` 的另一张 img。图集按 `.img` 全帧打包
   （宁多勿缺），由 `.ani` 侧决定用哪几帧——这条对 P3 动画播放器是硬要求。

---

## 13. 附：产物清点

| 路径 | 内容 |
| --- | --- |
| `tools/npk_atlas.py` | 本管线（MaxRects BL 装箱 / 页 PNG / manifest+rects / check / stats / verify / batch） |
| `tools/npk_parser.py` | 上游解码器（t6），本管线只 import 不重写；新增 `cycle_policy="degrade"` |
| `export/atlas/` | 171 img → 173 页、19.83 MB、rects 1.83 MB（adaptive，主产物） |
| `export/atlas_2048/` | 同内容固定 2048×2048 页、22.57 MB（对照） |
| `docs/NPK-ATLAS.md` | 本文 |
