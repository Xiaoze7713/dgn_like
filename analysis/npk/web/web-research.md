# DNF .NPK / .img 公开资料调研

调研日期：2026-11-04　调研人：web-researcher（Lead 的队友）
范围：公开源码、博客、文档；**本机实测结论单独标注**，与公开资料严格区分。
每条结论后附来源 URL；查不到原文的标「未证实」。写入范围仅 `analysis/npk/web/`。

---

## 0. 结论速览（TL;DR）

1. **ARGB8888（帧类型 0x10）在 .img 帧体里是 B,G,R,A**（小端 u32 = `0xAARRGGBB`，即 D3D9 的 `D3DFMT_A8R8G8B8`）。6 个相互独立的公开实现全部按 BGRA 读：hooy/npk-api 的 `Argb8888Codec`、KiraMaple/DNFExtractor 的 `Extractor.cpp`、sjy0727/DNFToolKit 的 `ColorHelper.readBgra`、HsOjo/PyDnfEx 的 `Format8888`、dof-dev/godof 的 `Formatter8888`、NeroBlackstone 的 TS 解码器；CSDN 原始系列文章还明确写了「IMGV4 调色板是 R,G,B,A，**与 IMGV2 的 ARGB8888 红蓝互换**」。→ **与本地实测一致**（HP 血球红球 / MP 血球蓝球 / `sm_body0000` 肤色人体）。
2. **ARGB1555 = A1R5G5B5 小端**（bit15=A，14:10=R，9:5=G，4:0=B）；**ARGB4444 = A4R4G4B4 小端**（bit15:12=A，11:8=R，7:4=G，3:0=B）。所有来源一致。
3. **v5 帧记录**：普通点阵帧 **36B**；DDS/共享贴图引用帧 **64B**（= 36B 基础 + 28B 扩展：保留、引用 DDS 序号、左/上/右/下裁切、旋转）；指向（LINK）帧 **8B**。DDS 索引项 **28B**（保留/像素格式/序号/压缩后大小/解压后大小/宽/高）。
4. **文件名 XOR 密钥末字节 = `0x00`**；密钥 = `"puchikon@neople dungeon and fighter "`（注意 fighter 后**有一个空格**，共 36 字节）+ `"DNF"×73`（219 字节）+ `0x00` = 256 字节。→ 与本地实测一致（"末位是空格"的说法不成立）。
5. **表头 u32（tableLength）= 帧记录区总字节数**（Σ 每帧 8/36/64），**不含 32B 头、不含调色板 / DDS 表 / 版本扩展头**。PyDnfEx 注释与 godof 的 `offset = imagesSize + 32` 都这么说；本机抽样 4000 个 IMG 实测 `T == Σ帧记录` **100% 成立**（v2 1852/1852、v4 2148/2148）。pacexy/npk-parser 把 T 直接当数据起点，实测会**早 32 字节**，属实现缺陷。
6. **校验 32B**：紧接索引表之后、数据区之前；SHA-256 的输入是 **magic + count + 索引表** 这些字节的前 `floor(len/17)*17` 字节。hooy 与 PyDnfEx 的保存逻辑都这样写；CSDN 原文亦同。→ 与本地实测一致。

---

## 1. 来源清单

| # | 来源 | URL | 类型 / 可读性 | 覆盖内容 |
|---|------|-----|--------------|----------|
| S1 | hooy 博客《揭开 NPK 文件数据结构》 | https://hooyantsing.github.io/0x000D-揭秘NPK文件数据结构/ | 中文博客；已抓取全文 | NPK 容器 + IMG V2 全字段 |
| S2 | hooy/npk-api（Java） | https://github.com/hooyantsing/npk-api | 源码；已逐文件读 | NPK、IMG v1/v2/v3/v4/v5/v6 读写、像素编解码、DDS 表 |
| S3 | pacexy/npk-parser（Python） | https://github.com/pacexy/npk-parser | 源码；已读 | NPK + IMG v1/v2/v4/v5/v6 解析 |
| S4 | KiraMaple/DNFExtractor（C++/MFC，2015） | https://github.com/KiraMaple/DNFExtractor | 源码；已读 `Extractor.cpp` | NPK 索引、ARGB1555/4444/8888→PNG 转换 |
| S5 | sjy0727/DNFToolKit（Java） | https://github.com/sjy0727/DNFToolKit | 源码；已读 `ColorHelper`/`V2Handle`/`NpkCoder`/枚举 | NPK + IMG v2 像素转换、颜色/压缩枚举 |
| S6 | HsOjo/PyDnfEx（Python 库，PyPI: PyDnfEx 0.1.0） | https://github.com/HsOjo/PyDnfEx ・ https://pypi.org/project/PyDnfEx/ | 已下 wheel 读源码 | NPK 读写、IMG v1/v2/v4/v5/v6、ColorBoard、DDS sprite、像素格式 |
| S7 | dof-dev/godof（Go，现代实现） | https://github.com/dof-dev/godof | 源码；已读 `npk/` | NPK、IMG v1/v2/v4/v5、formatter、v5 Sprite |
| S8 | NeroBlackstone/dfo-npk-extractor-bun（TypeScript） | https://github.com/NeroBlackstone/dfo-npk-extractor-bun | 源码 + `docs/npk-format.md`；已读 | NPK、IMG v1/v2/v4/v5 字段文档与实现 |
| S9 | CSDN 系列《关于DNF的多媒体包NPK文件的那些事儿》1–10，作者 u010274704 | 1) https://blog.csdn.net/u010274704/article/details/77319001 2/3) …/77413110 4) …/77967047 5) …/78113351 6) …/78126106（IMGV4） 7) …/78195956（IMGV5） 8) …/78201233 9) …/78641542（IMGV6） 10) …/79762513 | 中文逆向系列；本次读 hooy 仓库 `doc/` 内的 HTML 副本（原文同样 URL） | NPK 结构、IMG V1/V2/V4/V5/V6 全字段、DDS |
| S10 | langresser/dnfextrator（C++） | https://github.com/langresser/dnfextrator | 源码；已读 `extradnf.cpp` | NPK 头/索引、密钥、IMG 头/索引 |
| S11 | cyphen156《NPK Importer #1》（韩文，Unity 导入器开发记录） | https://cyphen156.tistory.com/522 | 韩文博客；已抓取正文 | 对 12,989 个 NPK / 314,349 个 IMG 的版本与格式统计；引用 KiraMaple、godof |
| S12 | progamercity《Dungeon Fighter Online NPK/IMG file structure》 | https://progamercity.net/game-files/2856-dungeon-fighter-online-npk-img-file-structure.html | 英文；**Cloudflare 拦截，未证实** | （未能取证） |
| S13 | DeepWiki · DNFToolKit NPK File Format | https://deepwiki.com/sjy0727/DNFToolKit/4.1-npk-file-format | 英文；**Vercel 安全页拦截，未证实** | （未能取证） |
| S14 | HsOjo/OjoDnfExtractor（PyQt6 GUI） | https://github.com/HsOjo/OjoDnfExtractor | 源码；已读 | GUI 外壳，解析内核是 S6 的 PyDnfEx |

> 说明：CSDN 站点有反爬，本次读的是 hooy 仓库 `doc/` 下保存的 1–10 篇 HTML 副本（内容与原文一致，URL 仍给 CSDN 原文）。

---

## 2. 各来源字段表摘录

### 2.1 NPK 容器

| 字段 | 偏移/长度 | 公开说法 | 主要来源 |
|------|-----------|----------|----------|
| 魔数 | 0，16B | `"NeoplePack_Bill\0"`（`NeoplePack_Bill` 15 字符 + `0x00`） | S1、S2（`NpkFile.NPK_MAGIC`）、S3、S6（`hard_code.NPK_MAGIC`）、S7（`npk/consts.go`）、S10 |
| 条目数 | 16，u32 | `img_count` / `album_count` | 同上 |
| 索引项 | 20 起，n×264B | `i32 offset` + `i32 size` + `256B XOR 文件名` | S1、S2（`INDEX_ENTRY_SIZE=264`）、S3、S4、S6（`File.open` 读 `<2i`+256B）、S7、S8、S10 |
| 校验 | 索引表之后 32B | SHA-256，见 2.3 | S1、S2、S6、S9-4 |
| 数据区 | `52 + 264n` 起 | 各 .img 原样存放；offset 相对整个 NPK | S6（`NPK.save` 里 `offset = 52 + count*264` 注释 `magic(16)+count(4)+info(264*n)+hash(32)`）、S7 |

补充实现细节：
- 文件名解密后按 `euc_kr` 解码（韩文路径），再截到第一个 `\0`：PyDnfEx `File.open`、godof `npk/file.go`（`utils.Decode(nameData, "euc_kr")`）都这样做。→ https://github.com/HsOjo/PyDnfEx 、 https://github.com/dof-dev/godof
- PyDnfEx 保存时按内容 MD5 去重，多个索引项可指向同一数据块（S6 `_callback_save_files_group_by_md5`）。

### 2.2 文件名 XOR 密钥（256B）

| 来源 | 构造方式 |
|------|----------|
| S2 `NpkFile.buildNameKey()` | base = `"puchikon@neople dungeon and fighter DNF"`，再用 `"DNF"` 循环填到下标 255，`key[255]='\0'`（等价 36B base + 219B "DNF" + 1B `\0`） |
| S3 `config.py` | `KEY = b'puchikon@neople dungeon and fighter ' + b'DNF'*73 + b'\x00'` |
| S4 `Extractor.cpp` | 常量串 `"puchikon@neople dungeon and fighter DNFDNF…DNF"`（fighter 后有空格） |
| S6 `hard_code.py` | `bytes('puchikon@neople dungeon and fighter %s\x00' % ('DNF'*73), 'ascii')` |
| S7 `npk/consts.go` | base + 73×"DNF"（字符串转义里多写了一个 `\x00` 字面量，但按 256B 截取使用） |
| S10 `extradnf.cpp` | `decord_flag[256] = "puchikon@neople dungeon and fighter DNF"`，从 `len` 起按 `D,N,F` 循环填充，`decord_flag[255]=0` |

**结论**：256B 密钥 = 36B 明文前缀（fighter 后 1 个空格）+ 219B `"DNF"` + 末字节 `0x00`；文件名按 256B 定长 XOR，明文不足补 `0x00`。

### 2.3 32B 校验（SHA-256）

- S1 博客：把「魔数 + IMG 数量 + IMG 索引表」的**总字节数除以 17 向下取整再乘 17** 记为 limit，对文件 `0..limit` 取 SHA-256，32B 结果紧跟索引表；校验不符时游戏视为无效 NPK。
- S2 `NpkFile.computeHash(byte[] data)`：`int len = data.length / 17 * 17;` 对 `data[0..len)` 做 SHA-256；调用方传入的是「文件头 + 索引表」拼接字节。
- S6 `NPK.save`：`io.write(hashlib.sha256(header_data[:len(header_data)//17*17]).digest())`，`header_data` = magic+count+全部 264B 索引项，写在 `52+264n` 位置。→ https://github.com/HsOjo/PyDnfEx
- S7（godof）**不读也不校验**这 32B（`npk/npk.go` 读完索引就直接用），但数据偏移仍按 `52+264n` 计算。

### 2.4 IMG 头（v2/v4/v5/v6 共用 32B）

| 字段 | 偏移 | 公开说法 |
|------|------|----------|
| 魔数 | 0，16B | `"Neople Img File\0"`（S1/S2/S3/S6/S7/S8；v1 是 `"Neople Image File"`，17B 无 `\0`） |
| 索引表大小 tableLength | 16，u32 | 「索引表所占空间，不含颜色板」（S9-6）；PyDnfEx 注释 `images_size without version,count,extra(color_board,sprites)...`（S6 `img/version/factory.py`）；hooy 注释 `unused, can be recalculated`，保存时写 Σ 帧记录（S2 `AbstractImg`） |
| 保留 | 20，u32 | 恒 0（S1/S2/S6/S7/S8） |
| 版本号 | 24，u32 | 1/2/4/5/6（V3 不存在：S11 扫描 31 万个 IMG，V3 计数 0） |
| 帧表项数 | 28，u32 | `imageCount` |

版本附加头（均位于 32B 头之后、帧表之前）：
- **v4**：`i32 colorCount` + `colorCount × 4B` 调色板（S2 `Version4Img`、S6 `IMGv4`、S7 `newColorBoard`、S9-6）。
- **v5**：`i32 ddsCount` + `i32 imgLength`（整个 IMG 字节数）+ 调色板（`i32 colorNum` + `colorNum×4B`，绝大多数为 0）+ `ddsCount × 28B` DDS 索引项（S2 `Version5Img`、S6 `IMGv5`、S7 `ImgV5.onOpen`、S9-7）。
- **v6**：`i32 colorBoardCount` + 每块 `i32 colorCount + colorCount×4B`（多调色板；S2 `Version6Img`、S6 `IMGv6`、S9-9）。**帧与具体调色板的绑定方式资料未写清，标「未证实」**。
- v1：`"Neople Image File"` + 若干填充字节；各实现给出的首帧偏移不完全一致（30 / 32），本机无 v1 样本、未验证 → 标「未证实」。

### 2.5 帧记录

| 帧种类 | 长度 | 字段（顺序） | 来源 |
|--------|------|--------------|------|
| 普通点阵帧 | 36B | `type, compressed, width, height, length, x, y, frameWidth, frameHeight`（9×i32） | S1、S2、S3、S6、S7、S8、S9-7、S10 |
| 指向帧 LINK | 8B | `type=0x11`, `targetIndex`（2×i32） | S1、S2、S3、S6（`ImageLink.open`）、S7 |
| v5 DDS/共享贴图帧 | 64B | 36B 基础（其中 `length` 字段恒 0）+ `i32 保留` + `i32 ddsIndex` + `i32 leftCut` + `i32 topCut` + `i32 rightCut` + `i32 downCut` + `i32 rotate` | S2 `Version5Img`（64B 注释）、S6 `SpriteZlibImage.open`（36B + 7×i32 = 64B）、S7 `NewZlibSpriteImage`、S9-7（64B 表：颜色系统/压缩状态/宽/高/保留(=原图片大小)/x/y/帧域宽/帧域高/保留/引用 DDS 序号/左/上/右/下/保留） |

要点：
- **不能靠颜色系统区分 v5 的 DDS 引用帧**：CSDN 说「首字节 > 0x11 是 DDS 引用型」，但 S2 `Version5Img` 明确注释「DDS 引用帧的颜色系统取自被引用纹理，真实文件里大量是 0x10」；**应按压缩状态 = 7 判断**。→ https://github.com/hooyantsing/npk-api/blob/main/src/main/java/xyz/hooy/npkapi/Version5Img.java
- 数据区顺序（v5）：先 DDS/sprite 数据（ZLIB 压缩，按 DDS 表顺序），再普通点阵帧像素数据（按帧表顺序）；LINK 帧与 DDS 引用帧自身无数据块（S2、S6 `IMGv5._callback_before_count_image_offset`、S7 `ImgV5.onOpen` 的 offset 累加顺序）。
- 36B 帧的 `length`：v2 下 PyDnfEx 会用 `w*h*像素大小` 覆盖它（`Image.open(fix_size=True)`），S5 `V2Handle` 也把未压缩帧长度重设为 `w*h*bpp`；即该字段在未压缩帧里不可靠。

### 2.6 类型码与压缩标志

| 值 | 含义 | 来源 |
|----|------|------|
| 0x0E | IMG v2：ARGB1555；v4/v6：调色板索引（1B/像素） | S2 `Frame.TYPE_ARGB1555 / TYPE_INDEXED`、S6、S7、S8、S9-6、S11 |
| 0x0F | ARGB4444 | 同 |
| 0x10 | ARGB8888 | 同 |
| 0x11 | 指向帧（LINK） | 同 |
| 0x12 / 0x13 / 0x14 | DXT1 / DXT3 / DXT5（旧文献写作 FXT1/3/5，同一组格式） | S1、S2 `TYPE_FXT1/3/5`、S9-7、S11 |
| 压缩 0x05 | 未压缩 | S1、S2、S5 `CompressMode.NONE`、S6、S7、S8 |
| 压缩 0x06 | ZLIB | 同 |
| 压缩 0x07 | ZLIB，压缩后内容是 DDS（v5 共享贴图） | S2 `COMPRESSED_DDS`、S6 `IMAGE_EXTRA_ZLIB_SPRITE`、S9-7、S11「ZLIB_SPRITE」 |

### 2.7 像素格式（公开实现逐行对照）

- **ARGB8888**：文件字节序 `B,G,R,A`。
  - S2 `Argb8888Codec`：注释「8 bit Blue + 8 bit Green + 8 bit Red + 8 bit Alpha（BGRA 字节序）」，解码 band 偏移 `{2,1,0,3}`，编码写 `B,G,R,A` → https://github.com/hooyantsing/npk-api/blob/main/src/main/java/xyz/hooy/npkapi/codec/Argb8888Codec.java
  - S4 `Extractor.cpp`：`png[0]=src[2]`(R)、`png[1]=src[1]`(G)、`png[2]=src[0]`(B)、`png[3]=src[3]`(A) → 源字节 `B,G,R,A`。
  - S5 `ColorHelper.readBgra`：`b=bs[0], g=bs[1], r=bs[2], a=bs[3]` → 方法名直接叫 readBgra。
  - S6 `Format8888.callback_to_raw`：读 `[b,g,r,a]`，写 `r,g,b,a`。
  - S7 `Formatter8888.ToRaw`：读 `b,g,r,a` → 输出 `r,g,b,a`。
  - S8 `img_decoder.ts`：ARGB_8888 原样返回（其输出缓冲约定为 BGRA），1555/4444 解码写 `dst[0]=B, dst[2]=R`。
  - S9-6 原文：「IMGV4 的调色板数据使用的 ABGR8888 方式存储，即在数据流中的顺序为 R、G、B、A，**这点与 IMGV2 里的 ARGB8888 颜色存储方式是有区别的，相当于其中的红蓝通道互换**」。
- **ARGB1555**：`A1R5G5B5` 小端。低字节 `= (G&7)<<5 | B`，高字节 `= (A<<7) | (R<<2) | (G>>3)`，5bit→8bit 用 `v<<3|v>>2`。
  - S2 `Argb1555Codec`（BITMASKS `{0x7C00,0x03E0,0x001F,0x8000}`）、S5、S6 `Color.from_1555`、S7 `Formatter1555`、S4（`red=(byte1&127)>>2`、`alpha=byte1>>7`）。
- **ARGB4444**：`A4R4G4B4` 小端。低字节 `= G<<4 | B`，高字节 `= A<<4 | R`。
  - S2 `Argb4444Codec`（BITMASKS `{0x0F00,0x00F0,0x000F,0xF000}`）、S5、S6 `Color.from_4444`、S7 `Formatter4444`、S4。
- **v4/v5/v6 调色板**：每项 4B，顺序 **R,G,B,A**。
  - S2 `PaletteSource`（类注释「颜色以 RGBA 顺序存储」，toBytes/fromBytes 都是 R,G,B,A）；
  - S6 `ColorBoard`（读 4B 原样，`to_raw_indexes` 直接把 4B 写进 RGBA 缓冲，而 RGBA 缓冲由 `Format8888` 输出 R,G,B,A 定义）→ https://github.com/HsOjo/PyDnfEx
  - S7 `newColorBoard`（显式读 `r,g,b,a`）→ https://github.com/dof-dev/godof/blob/main/npk/img/v4.go
  - S9-6（明确写 R,G,B,A，与 v2 的 ARGB8888 红蓝互换）。
  - 反例：S8 `docs/npk-format.md` 把 v4 调色板写作「BGRA 颜色」，但其代码只是把 4 字节原样拷贝，未做通道交换 → 属文档标注错误，见 §4.3。
- **数据索引**：v4/v6 的 0x0E 帧经 ZLIB 解压后是 1B/像素的调色板索引（S2 `IndexedCodec`、S6 `to_raw_indexes`、S7 `FormatToRawIndexes`、S9-6、S11）。

### 2.8 v5 的 28B DDS 索引项

| 偏移内 | 字段 | 说明 | 来源 |
|--------|------|------|------|
| 0 | `keep` / `title` | 一般 =1 | S2、S6、S7、S9-7 |
| 4 | `pixelFormat` | 0x12 DXT1 / 0x13 DXT3 / 0x14 DXT5 | 同 |
| 8 | `index` | DDS 序号 | 同 |
| 12 | `dataSize` | 文件内 ZLIB 压缩后字节数（= 该 DDS 数据块在 IMG 中的大小） | S2 `compressedSize`、S6 `data_size`、S7 `dataSize` |
| 16 | `rawSize` | 解压后 DDS 字节数（压缩前大小） | S2 `rawSize`、S6 `raw_size`、S7 `rawSize` |
| 20 | `width` | DDS 宽（一般 4 的倍数） | 同 |
| 24 | `height` | DDS 高 | 同 |

> S9-7 的表把 12/16 两个字段的「压缩前/后」措辞写得互相矛盾（把文件内大小叫「压缩前」），以 S2/S6/S7 实现为准。

---

## 3. 公开说法 vs 本地实测 对照表

「本地实测」= Lead 在 85 级客户端语料上的结论；括号内为我本次只读复测的结果。

| # | 字段/结论 | 本地实测 | 公开资料主流说法 | 判定 |
|---|-----------|----------|------------------|------|
| 1 | NPK 魔数/索引项 | `NeoplePack_Bill\0` 16B；n×264B（offset4+size4+name256） | 完全相同（S1/S2/S3/S6/S7/S8/S10） | **一致** |
| 2 | 文件名密钥末位 | `0x00`；fighter 后有 1 个空格 | 完全相同：36B 前缀 + `DNF`×73 + `\0`（S2/S3/S4/S6/S7/S10） | **一致**（"末位是空格"不成立） |
| 3 | 校验算法 | 32B，SHA-256 取 magic+count+索引表 的前 `len/17*17` 字节 | 完全相同（S1/S2/S6/S9-4） | **一致** |
| 4 | IMG 头 | 32B：magic16 + tableLength + 0 + version + frameCount | 完全相同（S1/S2/S6/S7/S8） | **一致** |
| 5 | tableLength 语义 | = Σ 帧记录（8/36/64），不含 32B 头、不含调色板/DDS 表；本机 4000 个 IMG 100% 成立 | S6 注释、S7 `offset=imagesSize+32`、S9-6「不含颜色板」一致；**S3 把 T 直接当数据起点（会早 32B）** | **一致（多数）**；S3 实现有缺陷 |
| 6 | v2 帧记录 36B | 是 | 一致（S1/S2/S3/S6/S7/S8/S10） | **一致** |
| 7 | 指向帧 8B | 是 | 一致（S1/S2/S6/S7/S8） | **一致** |
| 8 | v5 普通点阵帧 36B / DDS 引用帧 64B | 36B / 64B | 一致（S2 64B 注释、S6 36+28、S7 36+7×i32、S9-7 64B 表、S3 15×i32+type） | **一致** |
| 9 | v5 28B DDS 记录 | 有，字段如 §2.8 | 一致（S2/S6/S7/S9-7） | **一致** |
| 10 | 类型码 0x0E/0x0F/0x10/0x11/0x12/0x13/0x14 | 是 | 一致（S1/S2/S5/S6/S7/S8/S9） | **一致** |
| 11 | 压缩标志 0x05/0x06/0x07 | 是 | 一致（S1/S2/S5/S6/S7/S8/S9-7） | **一致** |
| 12 | **ARGB8888 通道序** | **B,G,R,A**（HP 红球/MP 蓝球/肤色） | **全部实现都是 B,G,R,A**（S2/S4/S5/S6/S7/S8；S3 亦隐含 BGRA）；S9-6 明确写「与 v4 调色板 R,G,B,A 红蓝互换」 | **一致**（此前 docs 里 R,G,B,A 的说法应废弃，见 §4.1） |
| 13 | ARGB1555 位布局 | —（本次未复测） | A1R5G5B5 小端（S2/S4/S5/S6/S7 全部一致） | **公开资料一致**，可采纳 |
| 14 | ARGB4444 位布局 | —（本次未复测） | A4R4G4B4 小端（S2/S4/S5/S6/S7 全部一致） | **公开资料一致**，可采纳 |
| 15 | v4/v6 调色板 4B 顺序 | 未实测（Lead 记录为 0 个 v4/v6；我抽样前 500 包 4000 个 IMG 中 v4 有 2148 个，但样本只有时装、目视不足以判定 R/B） | **R,G,B,A**（S2 PaletteSource、S6 ColorBoard、S7 v4.go、S9-6 明确）；S8 文档写「BGRA」但与代码/其他来源冲突 | **一致（R,G,B,A）**；S8 文档标注错误 |
| 16 | v5 数据区顺序 | 先 DDS/sprite，后点阵帧 | 一致（S2、S6、S7、S9-7） | **一致** |
| 17 | 版本存在性 | 有 v2/v4（本次抽样）；Lead 之前记录 v4/v6=0 | S11 全量扫描 12,989 NPK / 314,349 IMG：V1 1614、V2 54370、V4 130285、V5 99632、V6 28448，**V3=0** | **一致（V3 不存在）**；v4/v6 是否存在于本机语料取决于语料子集，建议 Lead 复核 |
| 18 | v5 用「颜色系统」判定 DDS 引用帧 | 用压缩标志 0x07 判定 | S2 注释明确「不能按颜色系统区分」；S9-7 的「首字节>0x11」规则在真实数据里会漏判 | **公开资料修正了旧文档**，与本地一致 |

---

## 4. 结论：哪些说法应被修正

### 4.1 本仓库旧结论（`docs/NPK-FORMAT.md` §7）的 ARGB8888 = R,G,B,A 应废弃
- 公开资料 6 个独立实现 + CSDN 原文全部是 **B,G,R,A**。
- 旧结论的证据（`red_systemfont` 帧 0 只有 `(255,49,49)`）实际走的是 **v5 共享 DDS 裁剪路径**：DDS 解码时通道序由 DDS 头里的 RGBA mask 决定（`03d.ts`/`DdsCodec` 一类实现），与裸 0x10 帧体的字节序无关，因此不能用来推断 0x10 帧体。
- 建议：`docs/NPK-FORMAT.md` 改成「0x10 帧体 = 小端 u32 `0xAARRGGBB`，字节序 B,G,R,A（D3DFMT_A8R8G8B8）；`ARGB1555/4444` 见 §2.7；DDS 纹理按其头内 mask 解码」。

### 4.2 pacexy/npk-parser 的数据区偏移公式有 bug（公开实现待修正）
- `utils.calc_texture_offset` 返回 `offset + index_table_size + Σ 前序帧 size`，把 tableLength 当作「含 32B 头」的偏移。
- 实测 tableLength = Σ 帧记录（不含 32B 头），godof/PyDnfEx 用 `imagesSize + 32`、`spriteEntriesStart + imagesSize`。→ pacexy 的数据起点会早 32 字节。
- 参考：https://github.com/pacexy/npk-parser/blob/master/utils.py ・ https://github.com/dof-dev/godof/blob/main/npk/img/v2.go

### 4.3 NeroBlackstone 文档把 v4 调色板写成「BGRA 颜色」是错的（实现正确、文档错）
- 其 `ver4.ts` 只是把 4 字节原样拷进 ARGB_8888 输出缓冲，没有交换通道；按其余 4 个来源（含 CSDN 原文）应为 **R,G,B,A**。
- 参考：https://github.com/NeroBlackstone/dfo-npk-extractor-bun/blob/main/docs/npk-format.md

### 4.4 CSDN IMGV5 文档把 64B 帧最后一个 i32 写作「保留（为零）」
- 现代实现（S2 `Version5Img`、S6 `SpriteZlibImage`、S7）把它读作 **rotate**（图集旋转，1=逆时针 90°；S6 注释写 horizontal/vertical），S11 也确认「V5 帧存在 rotate 值」。
- 2017 年的文章可能写作时该字段恒 0；应按 rotate 保留。
- 参考：https://blog.csdn.net/u010274704/article/details/78195956 ・ https://github.com/hooyantsing/npk-api/blob/main/src/main/java/xyz/hooy/npkapi/Version5Img.java

### 4.5 「v5 用颜色系统首字节 > 0x11 判断 DDS 引用帧」不可靠
- 应按 **压缩状态 = 7** 判断；DDS 引用帧的颜色系统来自被引用纹理（常见 0x10）。S2 注释已指出，本地实测亦同。
- 参考：https://github.com/hooyantsing/npk-api/blob/main/src/main/java/xyz/hooy/npkapi/Version5Img.java

### 4.6 待进一步验证（「未证实」清单）
- progamercity 英文页（Cloudflare 拦截）、DeepWiki 的 DNFToolKit 页（Vercel 拦截）：未能取证，不引用其内容。
- 韩文资料（S11）没有字段级逆向表，只有使用报告 + 全量版本/格式统计；其引用的字段级来源是 KiraMaple 与 godof，故不作为独立字段依据。
- v1（`"Neople Image File"`）首帧偏移各实现说法不一（30 / 32），本机无样本 → 未证实。
- v6 多调色板时「帧 → 调色板」的绑定规则，资料未写清 → 未证实（S2/S6 都默认用第 0 块或靠额外字段，未在文档中说明）。
- 文件名按 `euc_kr` 解码（S6/S7）：本机未验证，建议 Lead 抽查含中文/韩文名的路径。

---

## 5. 附：本次只读探针（不改动 /mnt/e，只读）

1. **tableLength 语义**：对 `dnf85/ImagePacks2` 前 500 个包抽样 4000 个 IMG（`tools/npk_parser.py` 只读解析）：
   - 版本分布：v2 1852、v4 2148；
   - `table_length == Σ Frame._consumed` 在 1852/1852 与 2148/2148 全部成立；
   - 例：`sprite(ex).NPK` 的 `sprite/interface/base.img` T=S=10944；`sprite_character_demoniclancer_equipment_avatar_belt.NPK` 的 `dl_belt0100a.img` T=S=6328、frameStart=52（v4，36+4×4）。
2. **0x10 帧体字节序**：v2 的 `sprite/character/common/aura/2015 red back_normal.img` 帧 0 平均 RGB（按原字节当 RGBA 读 + alpha 加权）为 `(136.3,136.3,254.6)`（蓝），R/B 交换后 `(254.6,136.3,136.3)`（红）；`2015 blue back_normal.img` 原读 `(254.5,248.8,174.3)`（黄），交换后 `(174.3,248.8,254.5)`（青）。→ 裸 0x10 帧体是 **BGRA**，与公开实现一致。
3. **v4 调色板顺序**：`dl_belt0500c.img`（35 色，31×55）按 R,G,B,A 与 B,G,R,A 各渲染一版（`/tmp/npkres/v4_dl_belt0500c_rgba.png` / `_bgra.png`），前者是暖金色饰边、后者偏青白；单张时装图不足以判定，故采用公开资料共识（R,G,B,A）。
4. 全语料搜 `sm_body16800` / `body16800` 命中 0（当前挂载语料与 Lead 10-26 生成样例时不同）；`sm_body0000` 类样本建议 Lead 复核时直接复现。
