# NPK / IMG 文件格式：逐字节解剖（本地语料实测版）

> 目标：把 DNF 的 `.NPK` 容器和里面的 `.img` 精灵表拆到**字节级**——
> 「文件头是什么、后面接什么、每段多少字节、实际长什么样」。
> 所有数字和 hexdump 都来自本机语料
> `/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2/`（4,730 个 .NPK，27 GB），
> 可用 `tools/npk_hexwalk.py` 与 `tools/npk_parser.py` 一条命令复现。
>
> 字段语义的完整清单见 [`docs/NPK-FORMAT.md`](NPK-FORMAT.md)；
> 本文负责「**实际字节组成**」，那篇负责「解码规则」。
> 语料全量校验（4,730 个包逐字节）见 [`analysis/npk/verify/corpus-verify.md`](../analysis/npk/verify/corpus-verify.md)。

---

## 0. 一句话总览

```
┌──────────────────────────── .NPK ────────────────────────────┐
│ 0x00  16B  "NeoplePack_Bill\0"                                │
│ 0x10  u32  条目数 n                                           │
│ 0x14  n × 264B  索引项：i32 offset + i32 size + 256B XOR 名   │
│ ...   32B  SHA-256(头+索引前 len/17*17 字节)                  │
│ data  数据区：n 个条目首尾相接，每个是一个完整 .img 文件      │
└──────────────────────────────────────────────────────────────┘
                              ↓ 取一个条目
┌──────────────────────────── .img ─────────────────────────────┐
│ 0x00  32B  "Neople Img File\0" + tableLength + 0 + ver + 帧数 │
│ 0x20  ?    版本扩展头（v2 没有；v4/v5/v6 有）                 │
│ ...   Σ 帧记录（每帧 36B；指向帧 8B；v5 共享贴图帧 64B）      │
│ ...   帧体（先 v5 的 DDS 表裸数据，再各内联帧体）             │
└──────────────────────────────────────────────────────────────┘

旧版（本语料 105 个条目）是另一套头，没有 tableLength：
  "Neople Image File\0"(18B) + 6B 零 + version(1) + 帧数
  然后 [36B 记录][帧体] 交替排列（§4.4）
```

**两种文件、两层结构；没有压缩、没有加密（除了文件名 XOR）**。
压缩只发生在单个帧的像素数据里（zlib）或 v5 的 DDS 表里（zlib 压缩的 DXT/裸像素）。

---

## 1. 一个 388 字节的完整 NPK（最佳入门样本）

文件：`ImagePacks2/sprite_interface_dot.NPK`，388 字节，1 个条目。
它小到可以整文件贴出来，而所有结构都在。

### 1.1 字节地图

| 区间 | 长度 | 内容 |
| --- | --- | --- |
| `0x000–0x00F` | 16 | magic `"NeoplePack_Bill\0"` |
| `0x010–0x013` | 4 | 条目数 `n = 1`（u32 LE） |
| `0x014–0x01B` | 8 | 索引项 #0：`offset=0x13C`、`size=0x48`（i32 LE ×2） |
| `0x01C–0x11B` | 256 | 索引项 #0：文件名密文（256B XOR） |
| `0x11C–0x13B` | 32 | SHA-256 校验值 |
| `0x13C–0x15B` | 32 | ↓ 数据区开始：IMG 前 32 字节头 |
| `0x15C–0x17F` | 36 | IMG 帧记录 #0 |
| `0x180–0x183` | 4 | IMG 帧体（1×2 的 ARGB1555 = 2×2B） |
| 合计 | 388 | `0x184`；与 `offset+size` 完全吻合 |

### 1.2 实际 hexdump

**文件头（20 字节）**：

```
0x00000000  4e 65 6f 70 6c 65 50 61 63 6b 5f 42 69 6c 6c 00  NeoplePack_Bill.
0x00000010  01 00 00 00                                      ....
```

- `4e 65 6f 70 6c 65 50 61 63 6b 5f 42 69 6c 6c 00`
  = `"NeoplePack_Bill"` + `\0`，正好 16 字节，**没有版本号、没有头长度字段**。
- `01 00 00 00` = 小端 u32 `1` = 后面有 1 个索引项。
  → 头之后紧接 `n × 264` 字节索引区，第 0 项从 `0x14` 开始。

**索引项 #0（264 字节）的前 48 字节**：

```
0x00000014  3c 01 00 00 48 00 00 00 03 05 11 01 1d 0e 40 07  <...H.........@.
0x00000024  2e 1a 00 1d 16 0d 06 45 4b 11 01 13 4a 18 06 49  .......EK...J..I
0x00000034  15 0b 00 4f 12 47 0e 05 13 65 72 20 44 4e 46 44  ...O.G...er DNFD
```

| 偏移 | 字节 | 含义 |
| --- | --- | --- |
| `+0x00` | `3c 01 00 00` | i32 `offset = 0x13C`（数据在文件中的绝对位置） |
| `+0x04` | `48 00 00 00` | i32 `size = 72`（该 .img 的字节数） |
| `+0x08` | `03 05 11 01 1d 0e 40 07 …` | 256B 文件名密文 |

**解密后的文件名**：`sprite/interface/dot/whitedot.img`（33 字节，见 §2）。
注意密文从 `0x3D` 起是 `65 72 20 44 4e 46 44`（`er DNFD`）——这是密钥尾部的残留：
名字只有 33 字节，后面 223 字节明文全 0，密文就等于密钥本身
（所以能直接看到 `…fighter ` 和循环的 `DNFDNFD…`）。

**SHA-256（32 字节）**：

```
0x0000011C  b6 a4 8a bd 45 4c e9 d8 e4 e6 1c 43 db 2e e1 0a  ...
```

校验对象 = **文件开头 `20 + n×264` 字节中前 `(len // 17) × 17` 字节**。
本例 `20+264 = 284`，`284 // 17 × 17 = 272 (0x110)`：
对 `[0, 0x110)` 做 SHA-256 正好等于上面 32 字节（`tools/npk_hexwalk.py` 每次都会现场重算）。
4,730 个包全量验证通过率 100%。

**数据区（IMG，从 0x13C 开始，72 字节）**：

```
0x0000013C  4e 65 6f 70 6c 65 20 49 6d 67 20 46 69 6c 65 00  Neople Img File.
0x0000014C  24 00 00 00 00 00 00 00 02 00 00 00 01 00 00 00  $...............
0x0000015C  0e 00 00 00 05 00 00 00 01 00 00 00 02 00 00 00  ................
0x0000016C  08 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00  ................
0x0000017C  02 00 00 00                                      ....
0x00000180  00 fc ff ff                                      ....
```

逐字段：

| 偏移 | 字节 | 字段 | 值 |
| --- | --- | --- | --- |
| `+0x00` | 16B | magic | `"Neople Img File\0"` |
| `+0x10` | `24 00 00 00` | u32 `tableLength` | **36** = 帧记录区总字节数（§5） |
| `+0x14` | `00 00 00 00` | u32 占位 | 0 |
| `+0x18` | `02 00 00 00` | u32 `version` | 2 |
| `+0x1C` | `01 00 00 00` | u32 `frameCount` | 1 |
| v2 无扩展头，帧记录从 `+0x20` 起 | | | |
| `+0x20` | `0e 00 00 00` | i32 `type` | `0x0E` = ARGB1555 |
| `+0x24` | `05 00 00 00` | i32 `compressed` | `0x05` = 未压缩 |
| `+0x28` | `01 00 00 00` | i32 `width` | 1 |
| `+0x2C` | `02 00 00 00` | i32 `height` | 2 |
| `+0x30` | `08 00 00 00` | i32 `length` | 8 ← **脏数据，见 §11** |
| `+0x34` | `00 00 00 00` | i32 `x` | 0 |
| `+0x38` | `00 00 00 00` | i32 `y` | 0 |
| `+0x3C` | `01 00 00 00` | i32 `frameWidth` | 1 |
| `+0x40` | `02 00 00 00` | i32 `frameHeight` | 2 |
| `+0x44` | `00 fc ff ff` | 帧体 | 2 个 ARGB1555 像素 = 4 字节 |

帧体解码：`00 fc` → u16 LE `0xFC00` → A=1, R=31, G=0, B=0 = 不透明纯红；
`ff ff` → `0xFFFF` = 不透明白。两个像素共 4 字节。
而记录里 `length` 写的是 **8**（= 2 像素 × 4B，把 ARGB8888 的字节数套在了 1555 上）——
**未压缩帧的 `length` 字段不可信，必须用 `w × h × bpp` 反算**，否则后面所有帧的帧体都会错位。

---

## 2. 文件名为什么是 256 字节密文

- 名字区固定 256 字节，逐字节 XOR，密钥 256 字节：

  ```python
  key = (b"puchikon@neople dungeon and fighter " + b"DNF" * 256)[:255] + b"\x00"
  ```

  即：36 字节前缀 `"puchikon@neople dungeon and fighter "`（注意 fighter 后面有一个空格），
  之后用 `"DNF"` 循环填充到第 255 字节，第 256 字节固定 `\0`。

- 解密后从第一个 `\0` 截断，再按 **GBK/CP936** 解码（包里确实有中文名）。

前 8 字节手算对照（本例）：

| 位置 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 明文 | `s` | `p` | `r` | `i` | `t` | `e` | `/` | `i` |
| 明文 hex | `73` | `70` | `72` | `69` | `74` | `65` | `2f` | `69` |
| 密钥 hex | `70` | `75` | `63` | `68` | `69` | `6b` | `6f` | `6e` |
| XOR = 密文 | `03` | `05` | `11` | `01` | `1d` | `0e` | `40` | `07` |

和 §1.2 的 hexdump 完全一致。

> 独立复核：4,730 个包 211,456 个条目里 99.96% 解密后可读；
> 备选密钥「前缀周期重复」可读率只有 3.58% —— 反证了 `DNF` 填充是正确的。
> 剩余 76 条「不可读」的名字其实是补丁作者乱填的（控制字符/无扩展名），不是密钥错。

---

## 3. 换一个包：2 个条目 + v5

文件：`!` + 94 个空格 + `sprite_common_digit_tp.NPK`，4705 字节（语料里文件名带大量前导空格，
shell 里要用引号，程序里用 `os.listdir()` 枚举）。

```
0x0000  4e 65 6f 70 6c 65 50 61 63 6b 5f 42 69 6c 6c 00   magic
0x0010  02 00 00 00                                       n = 2
0x0014  [264B 索引项 #0]  offset=0x244  size=1308  "sprite/common/digit/tp/tp.img"
0x011C  [264B 索引项 #1]  offset=0x760  size=2817  "sprite/common/digit/red_systemfont.img"
0x0224  [32B SHA-256]     对 [0, 0x220) 即 544 字节计算
0x0244  [1308B]  tp.img            （v2，15 帧，ARGB8888+zlib）
0x0760  [2817B]  red_systemfont.img（v5，11 帧，全部走共享 DDS 表）
0x1261  文件结束
```

- `20 + 2×264 = 548`，`548 // 17 × 17 = 544` —— 校验范围随条目数变化，不是固定值。
- 两条数据首尾相接：`0x244 + 1308 = 0x760`，`0x760 + 2817 = 0x1261` = 文件大小。

---

## 4. IMG 头 & 版本扩展头

### 4.1 公共 32 字节

| 偏移 | 类型 | 字段 | 说明 |
| --- | --- | --- | --- |
| 0 | 16B | magic | `"Neople Img File\0"` |
| 16 | u32 | `tableLength` | **帧记录区总字节数**（§5，本次实测确认） |
| 20 | u32 | 占位 | 通常 0（11 个坏 img 里是垃圾值） |
| 24 | u32 | `version` | 2 / 4 / 5 / 6 |
| 28 | u32 | `frameCount` | 帧数 |

### 4.2 各版本追加的扩展头

| 版本 | 扩展头（紧跟 32B 头） | 长度 |
| --- | --- | --- |
| v2 | 无 | 0 |
| v4 | `i32 colorNum` + `colorNum × 4B` 调色板 | 4 + 4k |
| v5 | `i32 ddsCount` + `i32 imgLength` + `i32 colorNum` + `colorNum×4B` 调色板 + `ddsCount × 28B` DDS 记录 | 12 + 4k + 28m |
| v6 | `i32 paletteCount` + `paletteCount × (i32 colorNum + colorNum×4B)` | 4 + Σ(4+4k) |

**v5 实例**（`red_systemfont.img`，条目在 NPK 里 `offset=0x760`）：

```
0x00000760  4e 65 6f 70 6c 65 20 49 6d 67 20 46 69 6c 65 00  "Neople Img File\0"
0x00000770  c0 02 00 00 00 00 00 00 05 00 00 00 0b 00 00 00  tableLength=704, 0, version=5, frameCount=11
0x00000780  0b 00 00 00 01 0b 00 00 00 00 00 00 01 00 00 00  ddsCount=11, imgLength=2817, colorNum=0
0x0000078C  ... 11 × 28B DDS 记录（308 字节）...
0x000008C0  帧记录区开始（11 × 64B = 704 字节）
0x00000B80  DDS 裸数据区开始
0x00001261  IMG 结束（文件结束）
```

偏移账（都相对 IMG 起点，十进制）：

```
32 (头) + 12 (ddsCount/imgLength/colorNum) + 308 (11×28 DDS 记录) = 352 = 0x160
352 + 704 (帧记录) = 1056 = 0x420  ← DDS 数据起点
1056 + 1761 (11 条 DDS 压缩数据) = 2817 = 0xB01 ← 恰好 = 条目 size ✓
```

### 4.3 v5 的 28B DDS 记录

| # | 类型 | 字段 | 实测值（rec0） | 含义 |
| --- | --- | --- | --- | --- |
| 0 | i32 | `title` | 1 | 恒 1 |
| 1 | i32 | `pixelFormat` | 14 (0x0E) | 帧类型码同款：0x0E/0x10/0x12/0x13/0x14 |
| 2 | i32 | `index` | 0 | 恒 0 |
| 3 | i32 | `fullLength` | 33 | **盘上字节数**（压缩后） |
| 4 | i32 | `length` | 140 | **解压后字节数** = 7×10×2 |
| 5 | i32 | `width` | 7 | 贴图宽 |
| 6 | i32 | `height` | 10 | 贴图高 |

`fullLength=33` 的 33 字节内容以 `78 9c` 开头 —— 是 **zlib 流**；解压得到 140 字节裸 ARGB1555。
即 **v5 的 DDS 表项 = zlib( 裸像素 或 128B DDS 头 + DXT 负载 )**。
本 img 的 11 条全部是 zlib 压缩，其中 rec10 是 `0x10` ARGB8888：`fullLength=1392 → length=13500 = 75×45×4`。

### 4.4 旧版 v1：`Neople Image File\0`（另一套头，没有 tableLength）

本语料里有 **105 个条目**（来自老客户端的地图/特效文件，通常躺在补丁包里）用的是更早的格式：

| 偏移 | 长度 | 内容 | 实测（`blast1.img`） |
| --- | --- | --- | --- |
| 0x00 | 18 | magic `"Neople Image File\0"` | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00` |
| 0x12 | 6 | 零填充 | `00 00 00 00 00 00` |
| 0x18 | u32 | `version` | `01 00 00 00` = 1 |
| 0x1C | u32 | `frameCount` | `0f 00 00 00` = 15 |
| 0x20 | — | 帧记录开始（**无** `tableLength`、**无**记录区） | `10 00 00 00` = 0x10 |

最大的区别在帧体布局：v1 **没有把记录集中在前、数据集中在后**，而是
**每条记录后面紧跟它自己的帧体**，一条一条交替到文件结束：

```
0x0020  10 00 00 00 | 06 00 00 00 | 5c 00 00 00 | 2f 00 00 00   type=0x10 cmp=zlib w=92 h=47
0x0030  3d 0f 00 00 | 87 00 00 00 | e5 01 00 00 | 77 01 00 00   length=3901 x=135 y=485 fw=375
0x0040  58 02 00 00 | 78 9c ed 9a 77 58 ...                        fh=600；紧随其后就是 zlib 流
```

也就是：**36B 记录 + `length` 字节帧体**，然后下一条记录。指向帧同样只占 **8B**
（`type=0x11` + `linkTo`），没有帧体。

本地验证：105 个 v1 条目全部按「32B 头 + [36B/8B 记录][帧体] 交替」走到条目末尾**精确对齐**（105/105）；
其中 `blast1.img`（446,868B）与 `zombie.img`（22,930B）已导出 PNG 确认可解码
（见 `analysis/npk/unpack-demo/v1_blast1_000.png`、`v1_zombie_000.png`）。

> 公开资料里 v1 的「首帧偏移」有 30 / 32 两种说法，本语料实测**记录从 0x20（32）开始**。
> 复现：`python3 tools/npk_v1_walk.py verify`（输出「v1 条目 105 个，按模型精确走完 105 个（100%）」）、
> `python3 tools/npk_v1_walk.py dump "<pack.npk>" "<条目名>" --out DIR --frames 0-2`。
> 另注意：v1 的未压缩帧 `length` 同样有脏数据（`auramaster.img` 1×1 ARGB1555 写 4，实际 2B），
> 规则与 v2 相同：未压缩帧按 `w×h×bpp` 走，压缩帧按 `length` 走。

---

## 5. 帧记录：三种尺寸混排

记录区紧跟在 32B 头之后（v2 即 `+0x20`；v4/v5/v6 还要跳过扩展头），每条记录**不写自身长度**，靠 `type` 决定读多少：

| 情况 | 尺寸 | 布局 |
| --- | --- | --- |
| 普通帧 | **36B** | 9 × i32：`type, compressed, width, height, length, x, y, frameWidth, frameHeight` |
| 指向帧 | **8B** | `type`（恒 `0x11`）+ `linkTo`（目标帧号） |
| v5 共享贴图帧 | **64B** | 36B 普通帧 + 7 × i32：`保留(0), ddsIndex, leftCut, upCut, rightCut, downCut, rotate` |

**三种混排的真实样本**：`sprite_monster_skillhuntress.NPK` 的 `skillhuntress.img`，
36 帧 = 35 个普通帧 + 1 个指向帧（#27）：

```
0x000003EC  11 00 00 00 1a 00 00 00                          ← 指向帧 8B：type=0x11, linkTo=26
0x000003F4  0e 00 00 00 06 00 00 00 43 00 00 00 71 00 00 00  ← 下一条普通帧 36B 的开头
...
首帧记录（36B，0x000002A74A）：
  0e 00 00 00  type=0x0E(ARGB1555)   06 00 00 00  compressed=0x06(zlib)
  43 00 00 00  w=67                 71 00 00 00  h=113
  54 07 00 00  length=1876           36 00 00 00  x=54
  32 00 00 00  y=50                 c8 00 00 00  frameWidth=200
  c8 00 00 00  frameHeight=200
```

这个 img 的 `tableLength = 1268 = 35×36 + 1×8` —— 正好是记录区总字节数。

**v5 的 64B 记录实例**（`red_systemfont.img` 帧 0，IMG 内偏移 `0x8C0`）：

```
0e 00 00 00 | 07 00 00 00 | 07 00 00 00 | 0a 00 00 00 |   type=0x0E cmp=0x07 w=7 h=10
00 00 00 00 | 00 00 00 00 | 00 00 00 00 | 07 00 00 00 |   length=0 x=0 y=0 fw=7
0a 00 00 00 | 00 00 00 00 | 00 00 00 00 | 00 00 00 00 |   fh=10 保留=0 ddsIndex=0 left=0
00 00 00 00 | 0a 00 00 00 | 00 00 00 00 |               up=0 right=7 down=10 rotate=0
```

后 28 字节的字段名按公开实现（hooy `Version5Img`、PyDnfEx `SpriteZlibImage`、godof）为
`保留, ddsIndex, left, top, right, bottom, rotate`；`rotate=1` 表示该贴图逆时针转 90° 使用
（本语料绝大多数为 0）。另外**判断「是不是 DDS 帧」要看 `compressed == 0x07`**，
不要按像素格式码判断——本文件里 0x10 的帧同样是 DDS 帧。

- `compressed = 0x07`：像素不在帧体区，去 DDS 表第 `ddsIndex` 条取；
- `width/height`（7×10）是**裁剪后**的尺寸，`left/up/right/down` 是（闭合）裁剪矩形；
  这里 7×10 就是 DDS 全尺寸，所以裁剪矩形是 `[0,0)-[7,10)`。
- 第 10 帧：`w=75 h=45 x=1 y=5`，裁剪同样覆盖整个 75×45 贴图。

### 5.1 `tableLength` 到底是什么意思（本次查明）

**= 帧记录区总字节数**（从扩展头之后到帧体/ DDS 数据起点，**不含** 32B 头和扩展头）。
四组证据：

| img | tableLength | 记录区实测 | 构成 |
| --- | --- | --- | --- |
| `whitedot.img`（v2，1 帧） | 36 | 36 | 1×36B |
| `skillhuntress.img`（v2，36 帧） | 1268 | 1268 | 35×36 + 1×8 |
| `00.img`（v2，10000 帧） | 85208 | 85208 | 大量 8B 指向帧 |
| `red_systemfont.img`（v5，11 帧） | 704 | 704 | 11×64B |

所以不要写成 `frameCount × 36`：全语料只有 95.74% 的 img 满足 `tableLength == fc×36`，
差额全部来自 8B 指向帧（`tableLength == 36·fc − 28·指向帧数`，抽样 300/300 成立；
剩余不吻合的少数是坏包）。官方解码器根本不用这个字段，但它是**免费的自我校验**。

---

## 6. 帧体：顺序、压缩、对齐

### 6.1 帧体在文件里的顺序（容易踩坑）

```
帧记录区 → [v5: 全部 DDS 表数据（按 DDS 记录顺序）] → 各非指向帧的帧体（按帧号顺序）
```

- v2/v4/v6：`记录区` 后直接就是各帧体。
- v5：先把 DDS 表里的数据**全部**铺完，再放 `compressed != 0x07` 的普通帧体。
  本例 `red_systemfont.img` 11 帧全走 DDS，所以 DDS 数据铺完就到 IMG 尾。

### 6.2 三种压缩标志

| `compressed` | 含义 | 盘上内容 |
| --- | --- | --- |
| `0x05` | 未压缩 | 裸像素 `w × h × bpp` 字节 |
| `0x06` | zlib | `78 9c / 78 01 / 78 da` 开头的 zlib 流，解压后 = `w × h × bpp` |
| `0x07` | 像素在 v5 DDS 表 | 本帧帧体 0 字节（`length = 0`），去 DDS 表取，可能还要按裁剪矩形裁 |

`bpp`：0x0E/0x0F = 2（v4/v6 的 0x0E 是 1B 调色板下标），0x10 = 4，0x11 = 0（指向帧），0x12/0x13/0x14 见 §8（DXT 尺寸按块算）。

**zlib 帧实际字节**（`skillhuntress.img` 帧 0，记录后紧跟）：

```
0x0002AC3E  78 9c ed 9a bf 4e e3 4c 14 c5 79 0b 1e 81 06 29  x....N.L..y....)
```

前 2 字节 `78 9c` 是 zlib 默认头；解压后 15,142 字节 = 67×113×2（ARGB1555）。
全语料抽样压缩帧 99.63% 以 `0x78` 开头。

### 6.3 对齐检查（判断解析是否正确的快捷方式）

`32B 头 + 扩展头 + Σ记录 + ΣDDS数据 + Σ帧体 == 条目 size`。每个样本都应精确相等：

- `whitedot.img`：32 + 36 + 4 = 72 ✓
- `skillhuntress.img`：32 + 1268 + 帧体总和 = 条目 size ✓
- `red_systemfont.img`：32+320+704+1761 = 2817 ✓

抽样 300 个 img：299 个精确对齐，1 个差 104 字节（老包，含截断帧）。
出现偏差通常意味着：把 8B 指向帧当成了 36B、把脏 `length` 当真、或漏了 v5 的 DDS 前置数据。

---

## 7. 像素通道序（**ARGB8888 是 B,G,R,A**，此处纠正旧文档）

| 格式 | 每像素 | 字节序 | 解释 |
| --- | --- | --- | --- |
| ARGB8888（0x10） | 4B | **B,G,R,A** | 小端 u32 = `0xAARRGGBB`（D3D9 `D3DFMT_A8R8G8B8`） |
| ARGB1555（0x0E，v2/v5） | 2B 小端 | 位 15=A，14–10=R，9–5=G，4–0=B | `A1R5G5B5` |
| ARGB4444（0x0F） | 2B 小端 | 位 15–12=A，11–8=R，7–4=G，3–0=B | `A4R4G4B4` |
| 索引（0x0E，v4/v6） | 1B | 调色板下标 | 调色板 4B/项，**顺序是 R,G,B,A**（与 8888 像素红蓝互换，见下） |
| DXT1/3/5（0x12/0x13/0x14） | 块压缩 | 标准 DXT | 见 §8 |

展开公式：5 位 `(v<<3)|(v>>2)`；4 位 `v*17`。

**证据（都是「颜色一换就荒谬」的图，可复现）**：

1. HUD 球：`sprite_interface2_hud.NPK` → `sprite/interface2/hud/hp_vessel.img`（HP）、
   `mp_vessel.img`（MP）。按 `B,G,R,A` 解 = HP 红球 / MP 蓝球；按 `R,G,B,A` 解 = HP 蓝球 / MP 红球。
   对比图：`analysis/npk/unpack-demo/compare_8888_hp_mp.png`。
2. 皮肤模型：`avatar/skin/sm_body0000.img`。`B,G,R,A` = 正常肤色人体；
   `R,G,B,A` = 通体发蓝。对比图：`analysis/npk/unpack-demo/compare_8888_skin.png`。
3. 红字：`red_systemfont.img` 帧 10（v5 DDS，8888）原始像素 `0f 3d bb ff`，
   按 `B,G,R,A` = `#BB3D0F` 橙红（与文件名吻合），按 `R,G,B,A` = 蓝紫。

> 旧版 `docs/NPK-FORMAT.md` §7 曾把 8888 写成 `R,G,B,A`，用的证据其实是
> `red_systemfont.img` **帧 0** 的 `(255,49,49)` —— 那是 **ARGB1555** 帧（原生 `0xFCC6`），
> 证明的是 1555 的位序，不是 4 字节通道序。已在本次复核中改正。

**公开实现交叉核对**（详情与 URL 见 [`analysis/npk/web/web-research.md`](../analysis/npk/web/web-research.md)）：
6 个相互独立的实现都把 0x10 当 BGRA 读——hooy/npk-api 的 `Argb8888Codec`（band 偏移 `{2,1,0,3}`）、
KiraMaple/DNFExtractor（`png[0]=src[2]`）、sjy0727/DNFToolKit（`readBgra`）、HsOjo/PyDnfEx（`Format8888`）、
dof-dev/godof（`Formatter8888`）、NeroBlackstone 的 TS 解码器。本机实测与之一致。

**调色板却是 R,G,B,A（注意：和 8888 像素相反！）**。本语料 v4/v6 只在**另一个老客户端**
（`/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2`，4,085 个包，v2 124,407 / v4 13,047）里出现，
sf115 里恰好为 0。用「同一张图在 sf85 是 v4 索引、在 sf115 是 v2 8888」的 19 组样本做颜色比对
（把 sf115 的像素颜色集合与 sf85 调色板两种解释做 ±8 命中统计）：
**R,G,B,A 命中 167,188 像素 vs B,G,R,A 命中 136,619 像素**，单文件最大差距 30 倍
（`sg_club4100a.img`：3,675 vs 116）——本地实测也判定调色板是 **R,G,B,A**。
公开实现（hooy `PaletteSource`、PyDnfEx `ColorBoard`、godof `v4.go`、CSDN IMG V4 原文
「调色板使用 ABGR8888 方式存储…与 IMGV2 里的 ARGB8888 红蓝通道互换」）与此一致。
v6 的「帧 → 用哪块调色板」绑定规则公开资料没写清，仍未证实。

---

## 8. 类型码 / 压缩码速查

| `type` | 名称 | 每像素/解码方式 |
| --- | --- | --- |
| `0x0E` | ARGB1555（v2/v5）/ 调色板索引（v4/v6） | 2B 或 1B |
| `0x0F` | ARGB4444 | 2B |
| `0x10` | ARGB8888 | 4B，B,G,R,A |
| `0x11` | REFERENCE（指向帧） | 8B 记录，无帧体 |
| `0x12` | DXT1 | 8B/16 像素块 |
| `0x13` | DXT3 | 16B/16 像素块 |
| `0x14` | DXT5 | 16B/16 像素块 |

本语料分布（抽样 34,962 帧）：`0x10` 34,039 / `0x0E` 418 / `0x11` 293 / `0x12` 212；
v2/v4/v6 的 `0x12–0x14` 在全量普查里未出现（只在 v5 的 DDS 表里）。

---

## 9. 全语料统计数据（独立复核，4,730 个包 / 211,456 个条目）

来自 [`analysis/npk/verify/corpus-verify.md`](../analysis/npk/verify/corpus-verify.md)（自写脚本，未复用解析器）：

| 项 | 结果 |
| --- | --- |
| magic `NeoplePack_Bill\0` | 4,730 / 4,730（100%） |
| 文件大小 == `20+n×264+32+Σsize` | 4,727 / 4,730（99.94%） |
| 条目总数 | 211,456 |
| 每包条目数 min/median/max | 1 / 6 / 3,604 |
| 索引 offset/size 合法 | 211,456 / 211,456（100%） |
| 数据区连续（无空洞） | 4,729 / 4,730 |
| 文件名解密可读 | 211,380 / 211,456（99.96%） |
| 后缀分布 | `.img` 207,779 / `.ogg` **0** / `.com` 3,601 / 无扩展名 75 / `.zmg` 1 |
| SHA-256 校验 | 4,730 / 4,730（100%） |
| 以 `Neople Img File\0` 开头的条目（v2/v5） | **211,351**（`.img` 207,674 + `.com` 3,601 + 无扩展名 75 + `.zmg` 1） |
| 21 个「只有 16 字节」的截断存根 | 前 16B 仍是 `Neople Img File\0`，头里全是垃圾值 |
| 以 `Neople Image File\0` 开头的条目（v1） | **105**（全部 `version=1`，§4.4） |
| 未知 magic | **0** —— 211,456 / 211,456 条目 100% 是 IMG 数据 |
| version 分布（广义 IMG 口径） | v1 105 / v2 ≈211,326 / v5 4（含 21 个坏头）；sf115 里 **v4 = 0、v6 = 0**（v4 在老客户端 sf85 里有 13,047 个） |
| 帧总数 | **28,777,699** = v2/v5 28,775,245 + v1 2,454（声明值合计 101,891,024 里含 11 个 16B 坏头各声明 6,646,889 帧，剔除后即上式） |
| `tableLength == fc×36` | 94.12%（差值 = 8B 指向帧；`36·fc − 28·指向帧数` 抽样 191/191 成立） |
| 抽样布局精确对齐 | 299 / 300 |
| 包内重名条目 | 11 个包有同名条目 |

两个反直觉事实：

- 语料里 **没有一个 .ogg**（音频容器格式支持，但这个客户端全是贴图）；
- **后缀不可信**：`.com` 3,601 个 + 无扩展名 75 个 + `.zmg` 1 个条目，开头**全部**是
  `Neople Img File\0`，其实都是 IMG，只是补丁作者把名字写成了别的后缀；
  反过来还有 105 个 `.img` 后缀的条目开头不是 IMG magic（被改坏的/占位）。
  判断类型一律用 magic，不要看后缀。

---

## 10. 解包演示：真的把图导出来

命令（`tools/npk_parser.py`，无需额外依赖）：

```bash
python3 tools/npk_parser.py dump \
    "sprite_interface_dot.NPK" \
    sprite/interface/dot/whitedot.img \
    --out analysis/npk/unpack-demo/whitedot
# -> whitedot_000.png（1×2，需要放大 200 倍才看得见）
```

导出的 PNG（都在 `analysis/npk/unpack-demo/`）：

| 文件 | 内容 |
| --- | --- |
| `icons1021/00_00*.png` | `1021图标↑↑↑↑↑↑↑↑↑↑.NPK` 的 28×28 图标 12 帧（v2 / ARGB1555 / zlib） |
| `red_systemfont/red_systemfont_*.png` | v5 共享 DDS 表裁剪出的红字数字（0–9 + 大号 "48"） |
| `swordman_skin/sm_body0000_*.png` | 剑士皮肤模型（v2 / ARGB8888 / zlib，修正通道序前的版本） |
| `sm_body0000_000_BGRA.png` | 同上，**修正通道序后**（正确肤色） |
| `hud_hp_fixed.png` / `hud_mp_fixed.png` | HP 红球 / MP 蓝球（8888 通道序的决定性证据） |
| `compare_8888_hp_mp.png` | 2×2 对比：`B,G,R,A`（HP 红 / MP 蓝，正确）vs `R,G,B,A`（反色，错误） |
| `compare_8888_skin.png` | 皮肤模型两种通道序对比：肤色 vs 蓝人 |
| `hud_hp_BGRA.png`（对） / `hud_hp_RGBA.png`（错） | 同一帧两种通道序对比：红球 vs 蓝球 |
| `damagefont/16th_damagefont_*.png` | 伤害数字字体（v2 / ARGB8888 / zlib） |
| `seria1555/00stand_000.png` | 赛丽亚立绘（v2 / ARGB1555：肤色、红帽都正确） |
| `v1_blast/blast1_000..002.png` | **旧版 v1** 格式的爆炸特效帧（92×47，ARGB8888）——证明 §4.4 的交替布局可解 |
| `v1_zombie/zombie_000.png`、`_005.png` | **旧版 v1** 格式的僵尸（47×107 / 75×88，ARGB1555）——肤色、裤子颜色正常 |
| `v4_club/sg_club4100a_000.png` | **v4 索引格式**真实样本（老客户端 sf85，调色板按下标查表） |
| `compare_v4_vs_v2.png` | 同一把武器：v4 索引（sf85，调色板 `R,G,B,A`）vs v2 8888（sf115，字节 `B,G,R,A`），**两版颜色完全一致**——跨客户端交叉验证通道序 |

---

## 11. 语料里的脏数据与陷阱（都会让解码器错位/崩）

1. **未压缩帧的 `length` 不可信**：如 `whitedot.img` 1×2 ARGB1555 写 `length=8`（实际 4B）；
   `goblin acc2.img` 1×1 写 4（实际 2B）。必须以 `w×h×bpp` 为准，否则后面帧体全错位。
2. **8B 指向帧**：`type == 0x11` 时记录只有 8 字节（`linkTo` 目标帧），按 36B 读会连累后续所有帧。
3. **v5 的 64B 记录**：只有 `version == 5` 且（`compressed == 0x07` 或 `type ∈ {0x12,0x13,0x14}`）才是 64B。
4. **截断帧**：少数包声明 N 字节、实际只给 N−4。整包报错不如「尽力解压 + 标记」。
5. **坏包 / 占位条目**：3 个包文件大小与索引不符；1 个包（`*priest_atequipment_weapon_axe.npk`）数据区有重叠。
   最典型的是 **11 个 16 字节的「只有头」条目**：`version = 0x4620C0D5`（1,176,528,749）、
   `tableLength = 1,886,348,622`、`frameCount = 6,646,889` —— 全是垃圾值，条目 size 只有 16。
   它们单条就能把「帧总数」撑大 664 万（11 条共 7,311 万帧），必须靠
   「条目 size < 32」/「记录区超出条目」筛掉，不能信 `version` 和 `frameCount`。
6. **后缀不可信**：`.com`（3,601 个）、无扩展名（75 个）、`.zmg`（1 个）条目开头全是
   `Neople Img File\0`，其实都是 IMG；105 个 `.img` 后缀的条目反而没有 IMG magic。用 magic 判断。
7. **文件名前导空格**：`sprite_*` 前面可能有几十个空格，shell 展开/`ls` 复制都会出错；
   程序里用 `os.listdir()` 拿原始名字，或直接用 `npk_parser.resolve_npk()`。
8. **同包重名**：11 个包内存在同名条目（补丁作者合并时产生），按名字索引时取第一条。
9. **旧版 v1 的 magic 不同**：`"Neople Image File\0"`（少个 `g`），头里**没有 `tableLength`**，
   帧体与记录交替排列（§4.4）。按 v2 的方式解析 v1 会整包读飞，反过来也一样。
10. **调色板与 8888 像素的红蓝顺序相反**：调色板 4B = R,G,B,A，像素 4B = B,G,R,A。
    写 v4 解码器时这两处别共用同一个通道交换函数。

---

## 12. 复现与工具

| 工具 | 用途 |
| --- | --- |
| `tools/npk_hexwalk.py` | 独立实现（0 依赖）：逐字段注解 NPK + IMG + 帧表 + 帧体，现场重算 SHA-256、校验 `tableLength`、校验对齐；`--entry/--img/--all-entries/--frame-limit` |
| `tools/npk_parser.py` | 完整解析/导出：`list / find / info / dump / census / bench / slice / samples / selftest / pack` |
| `tools/npk_corpus_verify.py` | 独立全量校验（4,730 包），产出 `analysis/npk/verify/*` |
| `tools/npk_v1_walk.py` | 旧版 v1 专用：`verify`（全语料 105/105 精确对齐）/ `list` / `dump`（导 PNG） |

```bash
# 逐字节解剖：整个包 + 每一个条目
python3 tools/npk_hexwalk.py "sprite_interface_dot.NPK" --all-entries
# 只看某个 IMG（含 64B 记录、DDS 表、帧体）
python3 tools/npk_hexwalk.py "!                                                                             sprite_common_digit_tp.NPK" \
    --all-entries --img sprite/common/digit/red_systemfont.img
# 导出 PNG
python3 tools/npk_parser.py dump "<npk>" "<img>" --out OUTDIR --frames 0-7
# 旧版 v1：全语料校验 + 导出
python3 tools/npk_v1_walk.py verify
python3 tools/npk_v1_walk.py dump "!!!!!!!!!!!!!!!!!!整合的NPK.NPK" \
    sprite/common/commoneffect/blast1.img --out analysis/npk/unpack-demo/v1_blast --frames 0-2
# 自检（环检测 / v4 / v6 / 1555 / 4444 / DXT1/3/5 / NPK 打包往返）
python3 tools/npk_parser.py selftest
```

本文所有 hexdump 的完整输出存于 `analysis/npk/hexwalk/`：
`tiny_*.txt`、`sprite_1021_00.img.txt`、`sprite_common_digit_red_systemfont.img.txt`、`skillhuntress.txt`。
