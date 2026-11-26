# NPK Inspector

DNF ImagePacks / SoundPacks 查看器。**单文件 HTML，双击即用**，不装 Python、不联网、文件不上传。

对标并扩展了 DNF_Extractor：除了「解包 / 预览 / 播放」，重点做了两块展板——

- **图集 · 切图展板**：v5 共享大图（DDS）整张贴出来，每一帧的裁剪矩形按颜色画在大图上；
  可以「▶ 逐帧看裁剪」跟着播放顺序一个个亮起来；下面按去重后的裁剪块列出「哪块被几帧共用」。
- **结构展板**：NPK 索引 → IMG 头 → 字节分区条（头 / 记录 / 调色板 / DDS 表 / DDS 数据 / 帧体）→
  帧记录表 → 十六进制，点行/点色块都能跳到对应字节并高亮。
- **拼装 · 导出**：一个 IMG 只是「一层」。把当前 IMG 当底层，再叠上衣/武器/特效层，
  按 x/y 对齐后整段播放；可以导出**精灵表 PNG + 每帧坐标 JSON**（Godot 直接切）或**透明 APNG 动图**。

> 为什么素材看起来是散的、alpha 是谁抠的、怎么自己做一套分层资产：
> 见 [../../docs/NPK-ASSET-PIPELINE.md](../../docs/NPK-ASSET-PIPELINE.md)。

## 打开方式

直接双击 `dist/NpkInspector.html`（Chrome / Edge 均可）。内置了一份 11 条目的示例包，
打开就能看到 v1 / v2 / v4 / v5 / OGG 各是什么样。

- `打开 NPK`：选一个 `.NPK`
- `打开文件夹`：选 `ImagePacks2` 目录，列出里面所有 NPK 供搜索选择
- 也可以把 `.npk` / `.img` / `.ogg` 直接拖进窗口，或拖整个文件夹
- URL 参数（方便做演示/截图）：`?entry=条目名&tab=preview|atlas|structure|audio&frame=7&zoom=fit&play=1&demo=0`

## 支持范围

| 版本 | 状态 | 说明 |
| --- | --- | --- |
| v1 | ✅ | `Neople Image File\0` + 36B/8B 记录与帧体交替排列 |
| v2 | ✅ | 常规格式，sf85/sf110 客户端主力 |
| v4 | ✅ | 调色板索引；**未压缩 0x0E 帧是 ARGB1555（不是索引）**，见下 |
| v5 | ✅ | 扩展头 + DDS 表（DXT1/3/5、raw1555、8888），共享大图裁剪 |
| v6 | ⚠️ | 解析路径已按文档实现，但手上没有 v6 样本，未对拍 |
| OGG | ✅ | 元信息 + 波形 + 播放 + Ogg 页表；浏览器解不了的 ogg 仍可看页表和导出 |

## 和 Python 参考实现逐字节对拍

`core/npk_core.js` 是独立实现，不是移植。对拍脚本把 Python `tools/npk_parser.py` 的结果
（索引、每帧字段、每帧 RGBA 的 SHA-256、DDS 元数据、OGG 头）导成 `test/expected.json`，
再由 `test/test_core.mjs` 在 Node 里跑同一批数据：

```bash
node tools/npk_inspector/test/test_core.mjs     # 743 通过, 0 失败
```

覆盖：3 个 NPK 的索引逐条、6 个 IMG（v1/v2/v4/v5，含 235 帧 DXT1 图集）每帧像素哈希、
60 张 v4 头像（10,920 帧）体长对齐、2 个 ogg。

### v4 的一个坑（Python 参考实现也踩了）

v4 的 `type=0x0E` 帧：

- `compressed=6`（zlib）：解压后是**调色板索引**，1 B/px；
- `compressed=5`（raw）：**没有压缩，仍是 ARGB1555**，2 B/px。

按这个规则，60 张 v4 头像的帧体长度与文件尾 60/60 精确对齐；按「raw 也 1B/px」解析会从
第 14 帧起错位，zlib 报 `unknown compression method`。实现见 `bppFor()`。

## 目录

```
core/npk_core.js        解析核心（UMD，Node 与浏览器共用）
web/index.html          开发版页面（引外部 js/css）
web/style.css
web/app.js              UI 逻辑
web/demo_data.js        内置示例包（生成物，勿手改）
test/make_demo.py       从真实客户端抽 11 个条目拼示例包
test/export_expected.py 导出 Python 参考结果
test/test_core.mjs      对拍测试
test/shot.mjs           无头浏览器 CDP 截图（优先 Chrome，回退 Edge；验收 UI 用）
test/cleanup.mjs        清掉残留的无头浏览器进程与 profile
build.py                把 css/js/demo 内联成单文件 dist/NpkInspector.html
```

## 重新构建

```bash
python3 tools/npk_inspector/test/make_demo.py   # 需要本机有 sf85/sf115 客户端
python3 tools/npk_inspector/build.py            # -> dist/NpkInspector.html（约 940 KB）
```

`make_demo.py` 的路径写死在文件顶部，换客户端目录时改那几行即可。

## 验收截图

`test/shot.mjs` 用无头浏览器的 CDP 直接抓页面（浏览器写系统 Temp 会被拒，所以截图由 Node 写回工作区）。
**优先用 Chrome**（`C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`），找不到才回退 Edge——
之前用 Edge 调这个工具时，Windows 侧留过一堆 msedge 进程；脚本现在每次用唯一 profile，跑完关闭并清目录：

```bash
python3 -m http.server 8766 --directory tools/npk_inspector &
node tools/npk_inspector/test/shot.mjs \
  --url 'http://localhost:8766/web/index.html?entry=ch_monsterface&tab=atlas' \
  --out .tmp_shot/atlas.png --w 1400 --h 900 --wait 1800
```

要是中途崩过、担心有残留：`node tools/npk_inspector/test/cleanup.mjs`
（只处理命令行带 `tmp_bprof_` / `tmp_edgeprof_` 的浏览器进程，不动你自己开着的窗口）。

## 已知限制

- 整个 NPK 一次读进内存：183 MB 的包实测解析 18 ms、预览正常；500 MB 以上会比较吃内存。
- ANI（动作配置）还没接进来——目前只到 IMG 级；「这一帧在动作里什么时候出现」需要再解析 `.ani`。
- v5 的合成/混合模式（普通 / 加法）不在 IMG 里，黑底素材在预览里会显示成黑块，这是字节原样。

## DXT3/DXT5 颜色块别画成黑（2026-11-15 修）

`decodeDxt()` 里 DXT3/DXT5 一度用了 `[p0, p1, 均值, 黑]` 这套调色板，于是颜色索引是 3 的像素
被画成纯黑 —— 在 `sprite/map/cutscene/the_mine_of_abyss.img`（v5 共享贴图 + `0x14` DXT5）
上表现为「整张图撒了一层不规则黑斑」。正确做法：**DXT3/5 的颜色块与 DXT1 相同，始终 4 色插值**，
只有 alpha 通道的来源不同。已在 `core/npk_core.js` 修正，并与 Pillow 对拍
（480,000 像素逐点差 ≤ 1）。`tools/npk_parser.py` 的 DXT5 alpha 插值表同时修了索引偏移。
