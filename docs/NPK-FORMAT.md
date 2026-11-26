# DNF `NPK` / `IMG` 二进制格式规范（逆向 + 实测）

> 状态：**已验证**（v2 / v4 / v5 有真实样本；v6 仍只有合成样本）。
> 2026-11 复核补充：sf115 语料里有 **105 个旧版 v1** 条目（另一套头，见 §4.5 / [`NPK-FRAME-BYTES.md`](NPK-FRAME-BYTES.md) §4.4）；
> **v4 真实样本**在另一个老客户端 `/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2`（13,047 个）里，已用它验证调色板通道序。
> 实现：`tools/npk_parser.py`（纯 Python：`struct` + `zlib`，`numpy` 仅用于加速 DXT 与像素转换，可选）。
> 数据基础：`/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2/`（4,730 个 `.NPK`），全量枚举 + 抽样逐字节核对。
> 本文每条结论都附「证据」：路径 / 十六进制 / 统计数字。标「待验证」的不要当结论用。
> 样例图：`analysis/npk/`（35 张 PNG + `MANIFEST.md`），生成命令见 §10。

---

## 1. 一句话概览

- **`.NPK` = 归档容器**：文件名 → (偏移, 长度) 的索引 + 校验位，里面装 `.img` 和 `.ogg`。
- **`.img` = 精灵表**：一堆**帧记录**（尺寸/偏移/压缩方式）+ 帧像素数据；v4/v6 带调色板，v5 带共享 DDS 贴图。
- 与 `.ani` 的接线：`.ani` 用 `(img 路径, img 内帧号)` 引用 `.img`（见 `docs/ANI-FORMAT.md`），
  本工具负责把那个 `img 内帧号` 解成像素。

```
ImagePacks2/*.NPK
└── "NeoplePack_Bill\0" + 条目数
    + 条目数 × 264B 索引（offset, size, 256B XOR 文件名）
    + 32B SHA-256 校验
    + img/ogg 数据区
        └── "Neople Img File\0" + ... + 帧记录[] + (v4/v6 调色板) + (v5 DDS 表) + 帧数据[]
```

---

## 2. 语料实测（sf115「人造神客户端」）

| 项目 | 数值 |
| --- | --- |
| `.NPK` 文件数 | **4,730**（同目录另有 7 个非 npk 文件；任务书写的 4,892 与实际不符） |
| 条目总数 | **211,456**（后缀：`.img` 207,779 / `.com` 3,601 / 无扩展名 75 / `.zmg` 1） |
| 按 magic 统计的 IMG 条目 | **211,341**（`.com`/无扩展名的条目开头也是 `Neople Img File\0`，其实是 IMG 改了后缀） |
| 帧总数 | **约 2,877 万**（IMG 头 `frameCount` 声明值合计，剔除 11 个 16 字节坏头后；详见 §11.1） |
| 坏包 | magic 0；文件大小与索引全等 4,727/4,730（3 个反例差 38B/负） |
| 全量枚举耗时 | 36 s（只读索引） |
| 全量普查耗时 | **877 s**（`census --no-bodies`，读头+帧记录，共 4,730 包） |
| 解不出的条目 | **153 个（0.074%）**，全是历史脏数据/占位条目（见 §11.1） |

IMG 版本分布（全量）：

| 版本 | 数量 | 备注 |
| --- | --- | --- |
| v2 | **≈211,326** | 绝对主力：UI、图标、角色、怪物、特效（含 3,677 个非 `.img` 后缀条目与 21 个 16B 截断存根，按 magic 统计） |
| v5 | **4** | `sprite/common/digit/red_systemfont.img`、`red_systemfont.img`（另一包里的副本）、`sprite/interface2/raid/raid_channel_cn.img`、`sprite/monster/ch_monsterface.img`（在 `1A冥灵之塔补丁.NPK`） |
| v1 | **105** | 旧版 `"Neople Image File\0"`，无 tableLength、记录与帧体交替（§4.5） |
| v4 | **0**（sf115）/ **13,047**（老客户端 sf85） | sf115 没有；用 sf85 真实样本验证了调色板通道序 = R,G,B,A |
| v6 | **0** | 两个语料都没有；代码路径用合成样本验证（§10 的 `v6_multi_palette.png`） |

帧类型分布（全量 `census` 实测，见 §6 类型码表）：

| 类型 | 帧数 | 说明 |
| --- | --- | --- |
| `0x10` ARGB8888 | **27,829,633** | 主力 |
| `0x0E` ARGB1555/索引 | **562,834**(v2) + 42(v5) | v2 全按 1555 解 |
| `0x11` 指向帧 | **338,595** | 12% 的帧是引用，必须解引用 |
| `0x0F` ARGB4444 | **22,014** | |
| `0x12` FXT1 | **212** | 只在 v5、走共享 DDS 表 |
| `0x06` | 789 | 疑为历史遗留类型码，能正常按 36B 记录读出，像素解码未单独验证（待验证） |

压缩标志分布：`0x06` zlib 28,186,885、`0x05` 未压缩 228,385、`0`（指向帧）338,596。
指向帧 `compressed` 恒为 0。**

> 注：`census` 结果里有极少数帧读出溢出值（如 `0x-43E797C4`），来自个别记录错位的包；
> `census` 会把它们计入失败项一起报出来，不影响正常包。

**文件名有大量前导空格**（例：`'!' + 94 个空格 + '国服菜单.NPK'`），必须用 `os.listdir`/`glob` 枚举，
不要指望 shell 展开或按名字拼路径 —— `npk_parser.py` 的 `resolve_npk()` 就是为此做的模糊匹配。

---

## 3. NPK 容器

| 偏移 | 类型 | 内容 |
| --- | --- | --- |
| 0 | 16B | magic `"NeoplePack_Bill\0"` |
| 16 | u32 | 条目数 `n` |
| 20 | n × 264B | 索引表 |
| 20 + n*264 | 32B | SHA-256 校验 |
| 之后 | — | 各条目数据区（偏移/长度由索引表给） |

索引表每条 **264 字节**：

| 偏移 | 类型 | 内容 |
| --- | --- | --- |
| +0 | i32 | 数据偏移 |
| +4 | i32 | 数据长度 |
| +8 | 256B | **XOR 加密的文件名**（尾部补 `\0`） |

文件名密钥 256 字节：

```
"puchikon@neople dungeon and fighter " + "DNF" 重复填充
```

最后一位是 `\0`（而不是某些文档写的空格）；解密后按 `\0` 截断再 `trim()`。
参考实现 `npk-api-main/.../ListableImgAccess.java` 的 `IMG_NAME_KEY` 末位也是 `\0`。

**校验位**：对这 32 字节之前的全部字节（"头 + 索引表"）取前 `len/17*17` 个字节做 SHA-256。
校验不符时原版客户端不读该包 —— 我方 `Npk(path, verify=True)` 会给出 `verify_ok`。

`.ogg` 音频与 `.img` 混在同一个 NPK 里，按文件名后缀区分即可。

---

## 4. IMG 头

所有版本共用的前 32 字节：

| 偏移 | 类型 | 内容 |
| --- | --- | --- |
| 0 | 16B | magic `"Neople Img File\0"` |
| 16 | u32 | `tableLength` = **帧记录区总字节数**（32B 头/v4·v5·v6 扩展头之后 → 帧体起点；v2 即 +0x20 起。实测三例：36 / 85208 / 704 全部精确吻合） |
| 20 | u32 | 占位 0 |
| 24 | u32 | `version` |
| 28 | u32 | `frameCount` |

随后按版本追加：

| 版本 | 追加内容 |
| --- | --- |
| v2 | 无 |
| v4 | `i32 colorNum` + `colorNum × 4B` 调色板 |
| v5 | `i32 ddsCount` + `i32 imgLength`(未用) + `i32 colorNum` + `colorNum × 4B` 调色板 + `ddsCount × 28B` DDS 记录 |
| v6 | `i32 paletteCount` + `paletteCount × (i32 colorNum + colorNum × 4B)`（多调色板） |

调色板条目 **4 字节/项**，通道序 **R,G,B,A**（与 8888 像素的 `B,G,R,A` **正好红蓝互换**，非常容易写错）。
证据：① sf85 客户端 19 组「同一张图 sf85 是 v4 索引、sf115 是 v2 8888」的像素颜色比对，R,G,B,A 命中 167,188 vs B,G,R,A 136,619（单文件最大 30 倍差距）；
② 公开实现一致（hooy `PaletteSource`、PyDnfEx `ColorBoard`、godof `v4.go`、CSDN IMG V4 原文「ABGR8888…与 IMGV2 的 ARGB8888 红蓝通道互换」）。详见 §7 与 [`NPK-FRAME-BYTES.md`](NPK-FRAME-BYTES.md) §7。

### 4.5 v1（旧版）：`"Neople Image File\0"`，没有 tableLength

本语料 105 个条目：18B magic + 6B 零 + u32 version(=1) + u32 frameCount，
记录起点固定 `0x20`；帧体**不集中在后面**，而是每条记录后紧跟自己的帧体
（`[36B/8B 记录][帧体]` 交替到文件末尾）。105/105 条目按此走完精确对齐。
逐字节样本见 [`NPK-FRAME-BYTES.md`](NPK-FRAME-BYTES.md) §4.4。

> ⚠️ 参考实现 `Version4ImgAccess.readHeader` 的读调色板循环写错（`i++` 却在循环体里读 `i, i+1, i+2, i+3`），
> 会越读越远。按「每次前进 4 字节」实现即可 —— 本工具如此，且 v4 合成样本往返一致。

### 4.6 v5 的 DDS 记录（28 字节）

| # | 字段 | 含义（实测） |
| --- | --- | --- |
| 0 | `title` | 恒为 1（未见其他值） |
| 1 | `pixelFormat` | 帧类型码同款：`0x10` ARGB8888 / `0x0E` ARGB1555 / `0x12` DXT1 |
| 2 | `index` | 恒为 0 |
| 3 | `fullLength` | **盘上压缩字节数**（zlib 压缩后长度） |
| 4 | `length` | **解压后字节数** |
| 5 | `width` | 贴图宽 |
| 6 | `height` | 贴图高 |

证据（`red_systemfont.img`）：`rec0 = (1, 14, 0, 33, 140, 7, 10)` → 33B zlib 解出 140B = 7×10×2（ARGB1555）✓
证据（`raid_channel_cn.img`）：`rec0 = (1, 16, 0, 135786, 278528, 544, 128)` → 278528 = 544×128×4（ARGB8888）✓
证据（`ch_monsterface.img`）：`rec1 = (1, 18, 0, 327, 8320, 128, 128)` → 8320 = 128×128/2 + **128** = DXT1 负载 + **DDS 头** ✓

**关键**：DDS 表里存的**不是** `"DDS "` 文件字面量 —— 解压后：

- 压缩纹理（DXT1/3/5）：`128 字节标准 DDS 头 + DXT 负载`；
- 未压缩（ARGB1555/8888）：**裸像素**，无头（140 = 7×10×2 恰好，没有 +128）。

所以解码器要「先看 `blob[:4] == b"DDS "`，是则走 DDS 路径，否则按裸像素处理」。
`npk_parser.py: _decode_dds_or_raw()` 就是这么写的。

### 4.7 v5 数据区布局（实测对齐）

```
[32B 头][v5 扩展头][帧记录 × n][DDS 裸数据 × ddsCount][非 reference 帧的帧体...]
```

证据（`raid_channel_cn.img`，文件长 211,408）：
记录区 72 → 3900（69 帧），DDS blob 135,786B，21 个内联帧帧体合计 71,722B，
`3900 + 135786 + 71722 = 211408` ✓ 字节完全对齐。

---

## 5. 帧记录

三种长度，**由 `compressed` 字段与版本决定**：

| 形态 | 长度 | 字段 |
| --- | --- | --- |
| 指向帧 | **8B** | `type, linkTo`（2 × i32） |
| 普通帧 | **36B** | `type, compressed, width, height, length, x, y, frameWidth, frameHeight`（9 × i32） |
| v5 共享贴图帧 | **64B** | 上面 9 个 + `skip(4)` + `ddsIndex, leftCut, upCut, rightCut, downCut` + `skip(4)` |

**v5 的分流规则（本工具的实测更正，参考实现这里是错的）**：

- `type == 0x11` → 8B 指向帧；
- `compressed == 0x07` **或** `type ∈ {0x12,0x13,0x14}` → **64B** 共享贴图帧；
- 否则 → 36B 普通帧（`compressed` 为 `0x05` 未压缩 / `0x06` zlib）。

原因：v5 里 `compressed = 0x07` 表示「像素在 DDS 表里，本帧只给裁剪矩形」，
参考实现按「v5 一律 64B / v2 一律 36B」写会错位。用上述规则，4/4 个 v5 文件字节完全对齐。

**字段语义**：

- `width/height`：本帧实际像素尺寸（= 裁剪后的尺寸）。
- `x/y`：帧矩形在**角色原点坐标系**里的左上角（见 §5.1，**不是**画布内的相对位置）。
- `frameWidth/frameHeight`：**画布**尺寸（`500×500` 这种大方框），只用于素材工具/剪裁边界，**不参与渲染定位**。
- `length`：帧体字节数（普通帧）；共享贴图帧里为 0。
- `ddsIndex/leftCut/upCut/rightCut/downCut`：贴图下标 + 裁剪矩形 `[left,right) × [up,down)`。

**帧数据顺序**：先全部帧记录 → 再 v5 的 DDS 裸数据 → 再各非 reference 帧体（顺序 = 帧序，跳过 0x11）。

### 5.1 坐标系：`.img` 帧的 x/y 与 `.ani` 的 `[IMAGE POS]` 如何叠加（**已验证**）

**结论：两者的坐标系相同（原点都是角色原点），直接相加。**

```
draw_top_left = (ani_frame.x + img_frame.x, ani_frame.y + img_frame.y)
draw_size     = (img_frame.width, img_frame.height)
```

`frameWidth/frameHeight` **不参与**这个计算。

验证方法（可复现）：取 `export/text/character/swordman/animation/attack1.ani.bin`
（10 帧有图，`[IMAGE POS]` 恒为 `(-232,-333)`，3 个 damage_box），
配 `sprite_character_swordman_equipment_avatar_skin.NPK` 里的
`sprite/character/swordman/equipment/avatar/skin/sm_body0000.img`（242 帧，画布 `500×500`；
帧 0 = `71×107 @ (189,231)`），把前 8 帧按上式叠到同一张画布上：

- 结果人物逐帧连贯、刀刃/躯干对齐（图见 `analysis/npk/compose_ani_img_offset.png`）；
- **脚落在原点**：帧 0 的 `y_bottom = ani.y + img.y + h = -333 + 231 + 107 = 5`（≈ 0，即地面锚点）；
  水平居中：`x_center = -232 + 189 + 71/2 = -7.5`（≈ 0）。
- **反证**：若按「画布中心定位」写 `ani.x + img.x - frameWidth/2`，人物整体上浮 250px、脚离地 245px，
  8 帧叠起来完全散架。⇒ 画布中心定位是错的。

**对下游（图集/渲染）的含义**：

- 打包 atlas 时每条矩形至少保留 `(img路径, 帧号, w, h, x, y)`；`x/y` 是**角色原点相对偏移**，不是画布内偏移，
  因此**不要**在打包时减掉 `frameWidth/2` 之类的「居中修正」。
- pivot 概念在这里退化为「偏移量本身就是 pivot 信息」：渲染时把 `(ani.x + img.x, ani.y + img.y)` 当作
  精灵左上角贴到角色原点上即可，不需要额外的锚点字段。
- 若 t11 需要统一 pivot（例如给 Godot 的 `Sprite2D.offset`），等价换算是
  `offset = (w/2 - (ani.x + img.x), h/2 - (ani.y + img.y))`（把左上角换成中心锚点）。

---

## 6. 帧类型码与压缩标志

类型码（`npk-api-main/.../Frame.java:5-12`，与实测一致）：

| 码 | 名称 | 说明 |
| --- | --- | --- |
| `0x0E` | INDEXED / ARGB1555 | **同值双义**：v2/v5 → ARGB1555；v4/v6 → 调色板索引 |
| `0x0F` | ARGB4444 | |
| `0x10` | ARGB8888 | 本地语料最常见 |
| `0x11` | REFERENCE | 指向帧（8B） |
| `0x12` | FXT1 | DXT1 |
| `0x13` | FXT2 | DXT3 |
| `0x14` | FXT3 | DXT5 |

压缩标志：`0x05` = 未压缩；`0x06` = zlib（数据以 `78 01/9c/da` 开头）；
**`0x07` = 像素在 v5 的 DDS 表里（本帧无帧体）** —— 这一条是参考实现没写的。

---

## 7. 像素布局（**ARGB8888 是 B,G,R,A —— 别凭直觉写 R,G,B,A**）

全部经正样本核对（2026-11 复核，旧版本节曾把 8888 写成 R,G,B,A，**已纠正**）：

| 格式 | 每像素 | 字节/位序 |
| --- | --- | --- |
| ARGB8888 | 4B | **内存顺序 B,G,R,A**（D3D9 `D3DFMT_A8R8G8B8`，小端 u32 = `0xAARRGGBB`） |
| ARGB1555 | 2B 小端 | 16 位值：bit15=A，14-10=R(5)，9-5=G(5)，4-0=B(5)（`A1R5G5B5`） |
| ARGB4444 | 2B 小端 | 16 位值：15-12=A，11-8=R，7-4=G，3-0=B（`A4R4G4B4`） |
| INDEXED | 1B | 调色板下标（v4/v6；调色板 4B/项 = **R,G,B,A**，与 8888 像素相反） |

5 位 → 8 位展开：`(v << 3) | (v >> 2)`；4 位 → 8 位：`v * 17`。

**ARGB8888 = B,G,R,A 的证据（三组，都是"红/蓝一换就荒谬"的图）**：

1. HUD 血球/魔球：`sprite_interface2_hud.NPK` 的
   `sprite/interface2/hud/hp_vessel.img`（HP，121 帧全 0x10）与 `mp_vessel.img`（MP）。
   按 B,G,R,A 解 → HP 红球、MP 蓝球；按 R,G,B,A 解 → HP 蓝球、MP 红球。
   见 `analysis/npk/unpack-demo/hud_hp_fixed.png` / `hud_mp_fixed.png`。
2. 裸体皮肤模型：`sprite_character_swordman_equipment_avatar_skin.NPK` 的
   `sprite/character/swordman/equipment/avatar/skin/sm_body0000.img`。
   按 B,G,R,A 解 = 正常肤色的人体；按 R,G,B,A 解 = 通体发蓝。
   见 `analysis/npk/unpack-demo/sm_body0000_000_BGRA.png`（对）与 `sm_body0000_000.png`（错，蓝人）。
3. `red_systemfont.img`（v5）帧 10 的 8888 DDS：字节 `0f 3d bb ff` →
   B,G,R,A = `#BB3D0F` 橙红（与"red_systemfont"吻合）；R,G,B,A = 蓝紫（不吻合）。
   见 `analysis/npk/v5_argb8888_digit_010.png`（红 48）。

> ⚠️ 旧版本节曾用 `red_systemfont.img` **帧 0** 的 `(255,49,49)` 当 8888 的证据 ——
> 那其实是 **ARGB1555（0x0E）** 帧（原生值 `0xFCC6`，按 `A1R5G5B5` 展成 255,49,49），
> 与 4 字节通道序无关。这是最初判断反了的根因：1555 的位序是对的，被误当成 8888 的证据。

**为什么容易搞反**：DNF 是 D3D9 游戏，`D3DFMT_A8R8G8B8` 在 x86 小端内存里的字节序天然是
`B,G,R,A`；而 16 位格式 `A1R5G5B5/A4R4G4B4` 是按"16 位字"解释的，bit15 才是 A。
两者不是同一套直觉，必须分开验。

**修正方式**：解 8888 时把每像素的 byte0 与 byte2 互换（alpha 始终在第 4 字节）。
`tools/npk_parser.py: _to_rgba8888()` 已按此修正。


## 8. v5 的 DDS 与 DXT 解码

解压后的 blob 若是压缩纹理，就是**标准 128 字节 DDS 头**：

| 偏移 | 字段 |
| --- | --- |
| 0 | `"DDS "` |
| 4 | `dwSize`（=124） |
| 12 | `height` |
| 16 | `width` |
| 76 | `ddspf.dwSize`（=32） |
| 80 | `ddspf.dwFlags` |
| **84** | `ddspf.dwFourCC`（`DXT1`/`DXT3`/`DXT5`/`DX10`） |
| 88 | `dwRGBBitCount` + 4 个 mask（未压缩时用） |
| 128 | 负载起点（`DX10` 再跳 20 字节） |

- **DXT1**：8B/块 = `u16 c0, u16 c1, u32 索引`；`c0 > c1` → 4 色插值，`c0 <= c1` → 3 色 + 透明。
- **DXT3**：8B alpha（每像素 4 位）+ 8B DXT1 颜色块（透明模式退化）。
- **DXT5**：`u8 a0, u8 a1, 48 位 alpha 索引` + DXT1 颜色块；`a0 > a1` 走 8 级 7 插值，
  `a0 <= a1` 走 6 级 5 插值 + `0/255` 两端。
- RGB565 展开：R/B 5 位 `(v<<3)|(v>>2)`，G 6 位 `(v<<2)|(v>>4)`。

⚠️ **两个容易踩的坑（2026-11-15 修）**

1. **DXT3/DXT5 的颜色块也是 4 色插值**（`(2·p0+p1)/3`、`(p0+2·p1)/3`），
   不是「`p0`、`p1`、均值、黑」。只有 DXT1 在 `c0 <= c1` 时才退化成 3 色 + 透明。
   把 DXT3/5 的颜色索引 3 当黑色画，效果就是图上撒了一层不规则黑斑
   （实例：`sprite/map/cutscene/the_mine_of_abyss.img`，v5 + `0x14` FXT3/DXT5）。
2. **DXT5 alpha 插值表的索引要对齐**：`a0 > a1` 时
   `alpha[i] = ((8-i)·a0 + (i-1)·a1) / 7`（i = 2…7），`a0 <= a1` 时
   `alpha[i] = ((6-i)·a0 + (i-1)·a1) / 5`（i = 2…5，再加 0 与 255）。
   用成 `(7-i)/(5-i)` 会让 alpha 整体偏移一档（肉眼多半看不出来，但和 Pillow 对不上）。

对拍基准：把 IMG 里的 DDS blob 原样落盘成 `.dds`，Pillow 能直接读 DXT1/3/5；
本仓库两个实现（`tools/npk_parser.py`、`tools/npk_inspector/core/npk_core.js`）
都已对齐到「与 Pillow 逐像素差 ≤ 1」（该图 480,000 像素，`>2` 的像素数 0）。

**块内顺序**：一个 4×4 块解出来后，要按「块行优先 → 块内 4 行」重排成位图，
本工具用 `reshape(bh,bw,4,4,4).transpose(0,2,1,3,4)` 一次搞定。

---

## 9. 指向帧（reference frame）

- 8 字节记录：`type = 0x11`，`linkTo = 目标帧号`。
- 语义：本帧**没有自己的像素**，渲染时用目标帧的像素（以及目标帧的 `x/y`？—— 待验证：
  本工具沿用目标帧的 size/x/y，因为 0x11 记录里没有这些字段）。
- **官方数据最大 link 深度 = 2**（`doc/5-…html`）。全量语料里 34.2 万个指向帧，绝大多数深度 1。
- **有向环**（含自指）会让原版客户端无限递归闪退。本工具用
  `visited 集合 + max_depth=64`，遇到环抛 `NpkError("指向帧存在有向环：帧 %d -> %d -> ...")`，
  绝不挂死 —— `selftest` 里就有 3 帧环样本（`0→1, 1→0, 2→2`）验证这一点。
- 环检测的产物还有 `Img.resolved`：把每个帧解析成「最终实体帧」的下标数组，下游直接查表。

---

## 10. 工具用法

```bash
# 列出包里所有条目（名字/偏移/大小）
python3 tools/npk_parser.py list "<npk 路径或文件名片段>"

# 全目录模糊找 img（只看索引，不读像素，很快）
python3 tools/npk_parser.py find "swordman/avatar"

# 看一个 img 的头 + 逐帧字段（版本/调色板/DDS 表逐行）
python3 tools/npk_parser.py info "<npk>" "sprite/.../x.img"

# 导出帧为 PNG（--frames 0-5,8 支持区间与列表）
python3 tools/npk_parser.py dump "<npk>" "sprite/.../x.img" --out /tmp/out --frames 0-3 --verbose

# 全量普查（版本/帧类型/指向帧计数）—— --no-bodies 只解头与记录，快
python3 tools/npk_parser.py census --no-bodies

# 吞吐压测（--mode meta|first|all）
python3 tools/npk_parser.py bench --n 200 --mode first

# 自检（环检测 / v4 / v6 / 1555 / 4444 / DXT1/3/5 / NPK 打包往返）
python3 tools/npk_parser.py selftest

# 按切片清单批量抽图（给图集管线 t11 用；默认读 export/_meta/slice_manifest.json，
# 产物写 export/atlas/slice，同时生成 slice-report.json）
python3 tools/npk_parser.py slice
python3 tools/npk_parser.py slice --limit 5 --out /tmp/try   # 先试 5 张

# 重新生成 analysis/npk 的样例与 MANIFEST.md
python3 tools/npk_parser.py samples

# 反向：把一批导出的 PNG 目录打回 NPK（保留 sprite/... 相对路径）
#   目录结构：<src>/sprite/xxx/yyy.img/000.png,001.png,...
python3 tools/npk_parser.py pack --out /tmp/t.npk <src>
```

`<npk>` 位置既可以给完整路径，也可以给**文件名片段**（工具会自己到 `--pack-dir`
里用 `listdir` 匹配——目录里有 4,730 个前导空格的名字，shell 展开不可靠）。
`--pack-dir` 默认就是语料目录，可全局覆盖。

**性能实测**（单进程，纯 Python + numpy，200 个随机 img）：

| 口径 | 吞吐 |
| --- | --- |
| `meta`：只解头 + 帧记录 | **257 img/s**（22,918 帧/s，中位 1.9ms / p95 5.3ms） |
| `first`：每 img 解首帧 | **159 img/s**（中位 2.2ms / p95 17.5ms） |
| `all`：解全部帧（平均 89 帧/img） | **18 img/s**（1,576 帧/s，中位 3.6ms / p95 219ms） |

### 10.1 验收自测结果（本机实测，可复跑）

| 项目 | 命令 | 结果 |
| --- | --- | --- |
| 全量枚举 | `census --no-bodies` | **4,730 / 4,730 包**，无崩溃，757–877 s，坏条目 153（0.074%） |
| 随机 200 抽样（**解全部帧**） | 见下 | **199 / 200 = 99.5%**，11,010 帧；唯一失败是 1 个 16 字节的空壳条目 |
| 首切片闭包 | `slice --out /tmp/x` | **171 / 171 = 100%**，9,043 帧，5.0 s，47 MB |
| 自检 | `selftest` | 10 / 10 通过（含环检测报错、v4/v6 调色板、DXT1/3/5、NPK 往返） |
| 吞吐 | `bench --mode meta / first` | 257 / 159 img/s，均 ≥100 |
| 样例图 | `samples` | `analysis/npk/` **36 张 PNG + MANIFEST.md** |

随机抽样脚本（等价于 `bench --mode all`，但统计成功率而不是耗时）：

```python
import sys, os, random
sys.path.insert(0, "tools"); import npk_parser as P
rng = random.Random(7)
files = [f for f in sorted(os.listdir(P.DEFAULT_PACK_DIR)) if f.lower().endswith(".npk")]
rng.shuffle(files); ok = fail = frames = 0
for fn in files:
    if ok + fail >= 200: break
    npk = P.Npk(os.path.join(P.DEFAULT_PACK_DIR, fn))
    idxs = [i for i, e in enumerate(npk.entries) if e.name.lower().endswith(".img")]
    if not idxs: continue
    try:
        d = npk.read_index(rng.choice(idxs))
        if not d.startswith(P.IMG_MAGIC): continue
        img = P.Img(d)
        for j in range(img.frame_count): img.frame_image(j)
        frames += img.frame_count; ok += 1
    except Exception: fail += 1
print(ok, fail, frames)
```

验收要的 ≥100 img/s 在 `meta` / `first` 口径下达标；`all` 口径被少数巨图（450MB 级动画包）拖尾。
真正的瓶颈是 8 位像素转换（纯 Python 逐像素），必要时可对 ARGB1555/4444 做 numpy 向量化再提一档。

---

## 11. 已知偏差与待验证

| 项 | 状态 |
| --- | --- |
| 参考实现的 v5 帧记录分流 | ❌ 错（按版本定长）→ 本文按 `compressed` 分流，已字节对齐验证 |
| 参考实现 v4 调色板读取循环 | ❌ 错（步进 1 而非 4）→ 已改正 |
| `tableLength` 字段语义 | ✅ 已查明 = 帧记录区总字节数（见 §4；三例字节级吻合） |
| v5 `imgLength` 字段语义 | 待验证（本工具不依赖它） |
| 指向帧是否继承目标帧的 `x/y` | 待验证（0x11 无此字段，按继承处理） |
| v4 真实样本 | ✅ sf85 老客户端 13,047 个；调色板通道序 R,G,B,A 已用 19 组跨客户端同图比对验证 |
| v6 真实样本 | 仍为 0（两个语料都没有），仅合成样本 |
| v1 真实样本 | ✅ sf115 105 个，布局 105/105 精确走通；像素解码已导出 PNG 验证 |
| v5 64B 记录后 28B 的字段名 | 公开实现为 `保留, ddsIndex, left, top, right, bottom, rotate`（末位是 rotate 不是保留） |
| `0x12/0x13/0x14` 在 v2 里的存在性 | 全量普查未见（只在 v5 出现） |
| 像素格式 `0x06` 等异常类型码 | 789 帧，能按 36B 记录读出；像素布局未单独验证 |
| 未压缩帧的 `length` 字段 | ❌ 不可信（见下「语料脏数据」）→ 已改为按 `w*h*bpp` 计算 |
| 截断帧 | 存在于少数包（声明 N、实给 N-4），已降级为「尽力解压 + `truncated` 标记」 |

### 11.1 语料脏数据清单（都会让「照规范写」的解码器崩掉，必须在实现里兜住）

实测出来的四类「规范外」情况，前两类**不是**解码器 bug，是数据本身不干净：

| 现象 | 例子 | 处理 |
| --- | --- | --- |
| 未压缩帧 `length` 写错 | `sprite_monster_goblin_equipment.NPK` / `monster/goblin/equipment/acc2.img`：两个 `1×1` 帧写 `length=4`，实际 `1×1×2B = 2` 字节 | **几何优先**：`compressed=0x05` 时体长 = `w*h*bpp`，忽略 `length`。否则后面 17 帧全部错位 4 字节 |
| 同一条目名在一个包里出现多次 | `sprite/worldmap.NPK` 里 `sprite/worldmap/lorien.img` 出现 2 次；`selectdungeon02.img` 也是 | `index_of` 在「匹配到多条但名字相同」时取第一条，只有名字不同才报歧义 |
| 装扮用模板名 | PVF 里剑士身体是 `character/swordman/equipment/avatar/skin/sm_body%04d.img`（`%04d` = 玩家装扮 id），语料里**没有**这个字面条目 | `Npk.expand_pattern()` 展开（剑士 52 个 id），`index_of` 自动回退到最小 id |
| 尾帧被截断 | `sprite_character_demoniclancer/...`、`.../wavespinarea/1-dodge.img` 等 | 读多少算多少，`zlib.decompressobj()` 抢救已解出的部分，帧上打 `truncated=True` |

第五类：**像素数据比几何尺寸短**（少几十到 70 字节），已改为**补零**而不是抛错
（`_to_rgba8888/1555/4444/indexed` 全部 pad 到 `need`）。典型：
`.../fighter/.../fm_body0121.img`（163 帧里 1 帧少 70 字节）。

这五类加起来影响 **0.074%** 的条目（153 / 207,779），且都不在首切片闭包里
（`export/_meta/slice_manifest.json` 的 171 张：**171/171 全绿**）。

> 说明：本工具对 `/mnt/e` 下的 NPK **只读**，不写回原目录。
