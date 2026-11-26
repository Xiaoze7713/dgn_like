# PVF 格式：真实字节组成（Script.pvf）

> 配套文档：[PVF-DECONSTRUCTION-PLAN.md](PVF-DECONSTRUCTION-PLAN.md)（拆解路线与优先级）、
> [NPK-FRAME-BYTES.md](NPK-FRAME-BYTES.md)（另一套容器，别混）。
> 本文全部数字来自本机真实文件与 `tools/pvf_unpack.py` 实测，可逐条复现（见 §10）。

## 0. 三层结构

```
 Script.pvf
 ├─ L0 容器       56B 头 + 加密目录树 + 逐文件密文       ← §1 §2 §3
 └─ L1 文件体     按扩展名分三种编码
     ├─ Document  [TAG] 节点树（.chr/.mob/.act/.lst/.als/.equ/…）  ← §4
     ├─ Animation 二进制帧表（.ani）                                ← §5
     └─ Text      行文本（.str/.nut）                               ← §6
```

关键点：**PVF 没有文件头魔数**，也不按文件名分块存储；一切结构都来自那棵加密目录树。
所以"能不能解"只取决于能不能解开目录树。

## 1. 文件头：56 字节，定长

以 `sf110.08/客户端/客户端神话8.0/Script.pvf`（692,629,849 B）为例，真实前 72 字节：

```
00000000  24 00 00 00 66 61 30 38 62 66 37 31 2d 34 33 39  $...fa08bf71-439
00000010  35 2d 36 61 34 62 2d 61 33 65 33 2d 32 36 31 37  5-6a4b-a3e3-2617
00000020  63 39 66 65 65 31 31 36 4b d1 00 00 04 1e 78 06  c9fee116K.....x.
00000030  84 7b d8 01 d1 ab 10 00 15 f0 7f 80 55 f8 7f 80  .{..........U...
00000040  de b0 67 5c ce a7 73 8c                          ..g\..s.
```

| 偏移 | 长度 | 类型 | 实际值 | 含义 |
| --- | --- | --- | --- | --- |
| `0x00` | 4 | i32 | `0x24` = 36 | GUID 字符串长度，**恒为 0x24**，可用作唯一判据 |
| `0x04` | 36 | ASCII | `fa08bf71-4395-6a4b-a3e3-2617c9fee116` | 档标识；本机四份 PVF **完全相同**（是常量，不区分版本） |
| `0x28` | 4 | i32 | 53579 | fileVersion（sf85=66282，sf110/sf115=53579） |
| `0x2C` | 4 | i32 | 108,535,300 | **目录树字节数** |
| `0x30` | 4 | i32 | `0x01d87b84` | 目录树 CRC32，同时是解密密钥 |
| `0x34` | 4 | i32 | 1,092,561 | 文件条目数 |

`0x38` 起就是目录树密文，**立刻接着**，没有对齐填充。
注意 `0x38 + 0x38`：头 56 字节正好 0x38，目录树从 0x38 开始 —— 这是最常见的偏移错误来源。

> 另有一份 `sf115/人造神客户端/Script.pvf` 头是 `f1 34 c5 e2 97 6e b6 ec…`（GUID 段被异或），
> 但实测**从 0x1000 起与 `sf115/Script.pvf` 逐字节相同** → 只是头部 4KB 被包了一层保护，正文是同一份数据。

## 2. 目录树：整块解密，然后是按条排列的记录

### 2.1 解密算法（一个公式搞定整棵树）

```
key = PASSWORD_PVF ^ dir_tree_checksum        # PASSWORD_PVF = 0x81A79011
for each u32 v in tree:  v = ror32(v ^ key, 6)   # 循环右移 6 位
```

即 `(x >> 6) | (x << 26)`，按 4 字节为单位，长度截到 `len // 4 * 4`。

真实前 64 字节（`0x38..0x78`）**密文**：

```
15 f0 7f 80 55 f8 7f 80 de b0 67 5c ce a7 73 8c
ce 72 22 99 0e 30 e4 dc c8 f3 64 d9 0e 30 26 59
0c 30 f4 dd 0e b7 a5 58 89 f0 24 5a 4e e0 26 1d
4e b2 a6 1b 49 a0 24 98 4f a0 e7 db cf b0 67 dd
```

解密后立刻是人能读的路径：

```
00000000  6e 00 00 00 4f 00 00 00 6d 61 70 2f 31 31 30 6c  n...O...map/110l
00000010  65 76 65 6c 6e 6f 72 6d 61 6c 64 75 6e 67 65 6f  evelnormaldungeo
00000020  6e 2f 76 65 72 69 63 6f 6c 6c 69 73 2f 64 75 6e  n/vericollis/dun
00000030  67 65 6f 6e 2f 6d 61 70 2f 61 6e 69 6d 61 74 69  geon/map/animati
00000040  6f 6e 2f 6e 6f 72 6d 61 6c 5f 73 74 61 74 75 65  on/normal_statue
00000050  5f 30 31 2e 61 6e 69 80 00 00 00 b0 8b 11 88 00  _01.ani.........
```

### 2.2 每条记录：`20 + pathLen` 字节，变长

```
u32  fileNumber     ← 条目序号（从 0/1 递增，实测不连续，别当前提）
i32  pathLen
u8   path[pathLen]  ← 'map/110level...ani'，ASCII（中文名可能用 GBK）
i32  fileLength     ← 明文长度（不是存储长度）
u32  fileCrc32      ← 解密密钥（**不是校验和**，见 §3.1）
i32  relativeOffset ← 相对数据区起点
```

上例逐字节对账：

| 偏移 | 字节 | 字段 | 值 |
| --- | --- | --- | --- |
| 0x000 | `6e 00 00 00` | fileNumber | 110 |
| 0x004 | `4f 00 00 00` | pathLen | 79 |
| 0x008 | `6d 61 70 …` | path | `map/110levelnormaldungeon/vericollis/dungeon/map/animation/normal_statue_01.ani` |
| 0x057 | `80 00 00 00` | fileLength | 128 |
| 0x05B | `b0 8b 11 88` | fileCrc32 | 0x88118bb0 |
| 0x05F | `00 00 00 00` | relativeOffset | 0 |
| 0x063 | — | 下一条开始（0x063 = 8 + 79 + 12 = 99 = pathLen + 20 ✓） |

### 2.3 绝对偏移与"数据区起点"

```
data_start = 56 + dirTreeLength
abs_offset = data_start + relativeOffset          # 本条 = 0x6781E3C + 0
```

`data_start` 实测 `0x6781E3C` = 108,535,356 = 56 + 108,535,300 ✓，且与所有条目的 `abs + 4 对齐长度` 首尾相连（全包连续）。

### 2.4 一个坑：目录树末尾多 2 字节

三份语料都是 `消耗字节 = dirTreeLength - 2`：

| PVF | dirTreeLength | 逐条解析消耗 | 余量 |
| --- | --- | --- | --- |
| sf110.08 | 108,535,300 | 108,535,299 | 1 |
| sf115 | 141,585,212 | 141,585,210 | 2 |
| sf85 | 30,466,556 | 30,466,554 | 2 |

所以**不要**用「消耗 == dirTreeLength」当验收条件，要用「条目数 == numFilesInDirTree + 数据区首尾连续」。

## 3. 文件体：定长对齐 + 同一个解密公式

### 3.1 长度与密钥

```
stored_len = (fileLength + 3) & 0xFFFFFFFC       # 向 4 字节对齐
key        = PASSWORD_PVF ^ fileCrc32            # 每文件不同
plaintext  = decrypt(密文[0:stored_len], fileCrc32)[0:fileLength]   # 尾部对齐字节丢弃
```

**`fileCrc32` 是密钥不是校验**：对 3000 个条目用 `zlib.crc32(明文)` 比对，命中 **0/3000**；用密文算也不符。
（这是最容易被误导的一点——字段名叫 CRC32，实际只参与异或。）

### 3.2 密钥公式是同一个

容器目录树与每个文件体用的是同一套 `v = ror32(v ^ 0x81A79011 ^ crc, 6)`，只是 `crc` 换成各自的
`dirTreeChecksum` / `fileCrc32`。所以解包器只需要一个 20 行函数。

## 4. Document 编码：`[TAG]` 文本的二进制形态

PVF 里 90% 的"脚本"（`.chr/.mob/.skl/.act/.equ/.stk/.lst/.als/…`）都是这一种编码。
解出来是缩进文本，看着像 INI，实际是**节点树**：

```
[width]
    40
    10
```

### 4.1 结构

```
i16  magic        ← 实测恒为 b0 d0（小端 = 0xD0B0 = 53424）
然后是一条接一条的 5 字节记录，直到文件末尾：
  i8   type       ← 见下表
  i32  index      ← 含义随 type 变
```

| type | 名称 | index 的含义 | 渲染成 |
| --- | --- | --- | --- |
| 2 | Int | 值本身 | `40` |
| 3 | IntEx | 值本身（大整数） | `400` |
| 4 | Float | 按位重解释为 f32 | `180.0` |
| 5 | Section | 字符串表下标 | `[width]` / `[/width]` |
| 6 | Command | 字符串表下标 | 原样 |
| 7 | String | 字符串表下标 | 值文本 |
| 8 | CommandSeparator | 字符串表下标 | 分隔符 |
| 9 | StringLinkIndex | 间接下标 | 二级查表 |
| 10 | StringLink | `→ key` 再查 `n_string` 映射 | 本地化文本 |

`Section` 的 index 指向字符串表，表里存的**带方括号**：`'[job]'`、`'[growtype name]'`、`'[use animation]'`。
去掉 `[`/`]` 后：不以 `/` 开头 = 开标签（压栈），以 `/` 开头 = 闭标签（弹栈）。

### 4.2 真实字节：`npc/npc.lst`（ID→路径注册表，5,862 B）

```
00000000  b0 d0 02 01 00 00 00 07 d1 c4 0d 00 02 02 00 00  ................
00000010  00 07 d2 c4 0d 00 02 03 00 00 00 07 d3 c4 0d 00  ................
```

| 偏移 | 字节 | 解释 |
| --- | --- | --- |
| 0x000 | `b0 d0` | magic |
| 0x002 | `02 01 00 00 00` | type=2(Int) 值=1 → 渲染 `1` |
| 0x007 | `07 d1 c4 0d 00` | type=7(String) 下标=0x0DC4D1 → `1_new/linus.npc` |
| 0x00C | `02 02 00 00 00` | Int 2 |
| 0x011 | `07 d2 c4 0d 00` | String → `1_new/seria.npc` |

**`.lst` 就是这样一张「ID, 路径」交替的平表** —— 这就是 §3.1 的 `ID → 路径` registry，
也是复刻时"技能 181 对应哪个文件"的唯一权威来源。

### 4.3 真实字节：`character/swordman/swordman.chr`（5,552 B）

```
00000000  b0 d0 05 00 1d 00 00 07 c6 0e 00 00 05 01 1d 00  ................
00000010  00 07 ba ad 06 00 07 5f ad 06 00 07 60 ad 06 00  ...._....`....
```

| 偏移 | 字节 | 解释 |
| --- | --- | --- |
| 0x000 | `b0 d0` | magic |
| 0x002 | `05 00 1d 00 00` | Section 下标 0x1D00 → `[job]` 开标签 |
| 0x007 | `07 c6 0e 00 00` | String 下标 0x0EC6 → `swordman` |
| 0x00C | `05 01 1d 00 00` | Section 下标 0x1D01 → `[/job]` 闭标签 |
| 0x011 | `07 ba ad 06 00` | String 下标 0x06ADBA → 值 |

渲染结果（sf110.08，繁体）：

```
[job]
    [swordman]
[growtype name]
    鬼劍士
    劍魂
    鬼泣
    狂戰士
    阿修羅
    //(后續確認)劍魔
[width]
    40
    10
[hp max]
    180.0
```

> 注意 `[growtype name]` 的值是 **type=7 String**（直接查字符串表），不是 StringLink；
> 所以"名字在哪"取决于字符串表编码，见 §8。

## 5. Animation 编码：`.ani` 二进制帧表

### 5.0 两个字段的真正含义（易错，务必先读）

官方注释里 `[IMAGE]` 的写法是 `[IMAGE] <图像路径> <帧编号>`，但**二进制里存的是**
`u16 imgId`（资源路径表的**下标**）+ `u16 imgParam`，二者的语义是：

| 字段 | 含义 | 陷阱 |
| --- | --- | --- |
| `imgId` | 下标 → 资源表里的 `.img` 路径（不是帧号！） | 把它当帧号会整段错位 |
| `imgParam` | **帧编号 = 目标 `.img` 里的第几帧** | 不是"文件编号"，也不是"参数" |

所以一帧的解析是：`path = sprites[imgId]`，`img = path 这张图`，`frame = imgParam`。

**`%04d` 模板路径**（如 `character/swordman/equipment/avatar/skin/sm_body%04d.img`）：
`%04d` 是**外观 id**（由装备/换装决定，`.ani` 里根本没有这个值），`imgParam` 仍然是帧号。
实测依据：`move.ani` 的 `imgParam` 是 180..187，对应 `sm_body0180.img`（243 帧）的 180..187 帧，
八帧连起来正好是走路循环；而 `sm_body0181.img` 这类文件在本客户端**根本不存在**
（若把 `imgParam` 当文件号，7/8 帧会找不到图）。

> 早期把 `imgParam` 当"文件编号"去 `path % imgParam` 时，`attack1.ani` 会解出 10 个**不同职业的裸体**
> （因为 `sm_body0000..0009` 是不同外观），这就是最直观的错判现场。

**动画帧的坐标怎么合成（y 轴对齐的关键）**：

```
画布（frameWidth × frameHeight，常见 500×500）
  └─ 内容 w×h 贴在画布 (img.x, img.y) 处
画布左上角放在场景坐标 (ani.x, ani.y)
=> PNG 的左上角应画在 (ani.x + img.x, ani.y + img.y)   ← 忽略 img.x/img.y 就会逐帧抖动
```

实测：`move.ani` 8 帧如果只按 `ani.x/ani.y` 摆放，内容底边在 20px 内上下跳；
把 `img.x/img.y` 加回去后只剩 1px（`attack1` 从 34px 降到 12px，剩下的 12px 是动作本身的下蹲）。

### 5.1 结构

```
u16 frameCount
u16 resourceCount
resourceCount × { i32 len; char path[len] }     ← 贴图路径表（.img）
u16 paramCount
paramCount × { u16 type; <payload> }            ← 全局参数（循环/阴影/坐标…）
frameCount × {
  u16 boxCount
  boxCount × { u16 type(14=DAMAGE 15=ATTACK); i32 ×6 }   ← 碰撞盒六个数
  u16 imgId; u16 imgParam
  i32 x; i32 y
  u16 propCount
  propCount × { u16 type; <payload> }
}
```

### 5.2 真实字节：80 字节的完整 .ani

`map/slough/animation/15_10th_town_deco/10th_deco_02_d.ani`：

```
00000000  01 00 01 00 30 00 00 00 4d 61 70 2f 65 76 65 6e  ....0...Map/even
00000010  74 2f 32 30 31 35 5f 31 30 74 68 5f 74 6f 77 6e  t/2015_10th_town
00000020  5f 64 65 63 6f 2f 31 30 74 68 5f 64 65 63 6f 5f  _deco/10th_deco_
00000030  30 32 5f 64 2e 69 6d 67 00 00 00 00 00 00 00 00  02_d.img........
00000040  00 00 00 00 b0 ff ff ff 01 00 0c 00 96 00 00 00  ................
```

| 偏移 | 字节 | 字段 | 值 |
| --- | --- | --- | --- |
| 0x00 | `01 00` | frameCount | 1 |
| 0x02 | `01 00` | resourceCount | 1 |
| 0x04 | `30 00 00 00` | pathLen | 48 |
| 0x08 | `4d 61 70 …` | path | `Map/event/2015_10th_town_deco/10th_deco_02_d.img` |
| 0x38 | `00 00` | paramCount | 0 |
| 0x3A | `00 00` | boxCount | 0（帧 0 无碰撞盒） |
| 0x3C | `00 00` | imgId | 0（→ 路径表第 0 项） |
| 0x3E | `00 00` | imgParam | 0 |
| 0x40 | `00 00 00 00` | x | 0 |
| 0x44 | `b0 ff ff ff` | y | **-80**（帧锚点，可负） |
| 0x48 | `01 00` | propCount | 1 |
| 0x4A | `0c 00` | prop type | 12 = DELAY |
| 0x4C | `96 00 00 00` | delay | 150（毫秒） |

文本化结果（工具的 `[FRAME0000]` 输出）：

```
[FRAME0000]
    [IMAGE] 0  map/event/2015_10th_town_deco/10th_deco_02_d.img
    [POS] 0 -80
    [IMG_PARAM] 0
    [DELAY] 150
```

### 5.3 帧属性与全局参数的载荷表

帧属性（每个都跟在 `u16 type` 后面）：

| type | 名称 | 载荷 |
| --- | --- | --- |
| 0 | LOOP | i8 |
| 1 | SHADOW | i8 |
| 3 | Ani_COORD | **u16**（注意与全局参数的 i32 不同） |
| 7 | IMAGE_RATE | f32 ×2 |
| 8 | IMAGE_ROTATE | i32 |
| 9 | RGBA | u32 |
| 10 | INTERPOLATION | i8 |
| 11 | GRAPHIC_EFFECT | u16 + (MONOCHROME: rgb×3 / SPACEDISTORT: u16×2) |
| 12 | DELAY | i32 |
| 13 | DAMAGE_TYPE | u16（0 普通 / 1 霸体 / 2 不可破） |
| 14 | DAMAGE_BOX | 见 boxCount 区（六个数） |
| 15 | ATTACK_BOX | 同上 |
| 16 | PLAY_SOUND | i32 len + path[len] |
| 23 | SET_FLAG | i32 |
| 24 | FLIP_TYPE | u16（1 水平 / 2 垂直 / 3 全部） |
| 25 | LOOP_START | 无 |
| 26 | LOOP_END | i32 |
| 27 | CLIP | i16 ×4 |

全局参数（`.ani` 开头的 `paramCount` 段）：`0 LOOP=i8`、`1 SHADOW=i8`、
**`3 Ani_COORD=i32`（4 字节，与帧里的 u16 不对称）**、`18 SPECTRUM/操作块=15 字节`。

### 5.4 两个必须知道的变体（否则 0.2%~16% 的文件解析错）

1. **`imgId == 0xFFFF` 时 `imgParam` 常常整个消失**（少 2 字节）。
   实测 sf85 1500 抽样里 1490 个用"省略"、1 个用"保留"，两种都必须支持。
2. **`imgId == 0xFFFF` 也意味着"本帧不画图"**（纯时序帧 / 纯碰撞帧），clamp 到 1×1 透明即可。

验收手段是**精确消费**：解完后游标必须正好等于 `fileLength`。这条自证判据让 99.8%+ 的文件无需外部真值就能确认。

## 6. 第 3 类编码：纯文本（`.str` / `.nut`）

| 后缀 | 实际内容 | 说明 |
| --- | --- | --- |
| `.str` | 行文本 `key>值`，`\r\n` 分行 | 本地化表（`.kor/.jpn/.chn` 分语言） |
| `.nut` | **Squirrel 源码** | `function checkExecutableSkill_bloodfire(obj)` 这种，直接可读 |
| `.als` | Document | `[use animation]` 列表，不是文本 |

`.nut` 是这次最值钱的发现：**技能/AI/被动逻辑的脚本层没有编译成字节码**，是明文源码。
`sqr/character/**/*.nut` 这种路径下就是每个技能的实现，`obj.sq_AddSetStatePacket(STATE_BLOODFIRE, …)` 这种调用直接写在里面。

## 7. 验证数据（可复现）

| PVF | 文件大小 | 条目数 | dirTree | 明文总量 | `.ani` 精确消费 |
| --- | --- | --- | --- | --- | --- |
| `sf85/老牛DNF客户端/Script.pvf` | 205,695,984 | 370,666 | 30,466,556 | 174,670,507 | **209,309 / 209,635 = 99.84%** |
| `sf110.08/客户端/客户端神话8.0/Script.pvf` | 692,629,849 | 1,092,561 | 108,535,300 | 582,437,259 | 抽样通过 |
| `sf115/Script.pvf` | 923,262,293 | 1,460,792 | 141,585,212 | 779,453,396 | **1,058,417 / 1,058,561 = 99.986%** |

Document 抽样：3000/3000 解析成功（三档各一次）。

## 8. 三个客户端的编码差异（决定"名字从哪拿"）

| 语料 | `.str` 语言 | 正文字符编码 | 中文可用性 |
| --- | --- | --- | --- |
| sf110.08（客户端神话8.0） | 26×`.chn` + 1×`.kor` | **big5hkscs（繁体）** | ✅ 完好：`鬼劍士 / 劍魂 / 鬼泣 / 狂戰士` |
| sf115（人造神） | 26×`.chn` + 2×`.kor` | **big5hkscs（繁体）** | ✅ 正文串完好：`極詣·劍影 / 劍神 / 黑暗君主 / 帝血弒天`；⚠️ 但独立的 `.chn.str` 语言表被写成 `EF BF BD`（U+FFFD） |
| sf85（老牛） | 27×`.kor` + 13×`.jpn` + 1×`.chn` | cp949（韩文） | ✅ 韩文完好（正文串按 big5 解也能得到繁体名） |

**实操结论**：显示名**不必跨包取**——所有文档里的字符串（`[name]`、`[growtype name]`、技能名）
都躺在各包自己的 `stringtable.bin` 里，sf115 也是完好的 big5 繁体，直接解就能拿到。
唯一坏掉的是**独立的 `.str` 语言表**（`character/character.chn.str` 等），那是"ID → 显示名"的
外部映射表，碎了只影响按 ID 反查名字的那条路。

> 这个结论是实测纠正的：早先一度以为 sf115 中文全丢，正是因为**只看了 `.str` 而没看 `stringtable.bin`**。
> 早期判据用「CJK 命中数 − 4×替换符」打分时会误选 gb18030（把 big5 字节解成"看着像汉字"的乱码 + 私用区字符）；
> 改成对 `stringtable.bin` 用 `errors="ignore"` 解码、并且**重罚私用区字符**（`U+E000–U+F8FF`，`-20×`）后，
> big5hkscs 在三档语料上都稳定胜出。

> 还有一层：`stringtable.bin` 与 `.str` 是两套不同的表。
> `stringtable.bin` = 全局字符串池（`i32 count` + `i32 start/end` 偏移对，字符串在 `buf + start + 4`）；
> `n_string.lst` = **magic 53424（= Document 的 `b0 d0`）+ 每 10 字节一条**，把"名字"映射到字符串池下标，
> 再把 `.str` 的 `key>值` 覆盖上去（StringLink 就是这么两级查表的）。

## 9. 陷阱清单（踩过的都在这）

1. **头长 0x38 而不是 0x40**：目录树紧跟 56 字节，差 8 字节就整棵树解成乱码。
2. **`sizeGUID` 恒为 0x24**：它既是 GUID 长度也是"这是不是 PVF"的判据。
3. **目录树末尾有 1~2 字节余量**，别用严格相等当验收。
4. **`fileCrc32` 不是校验和**，只是解密密钥；算 `zlib.crc32` 永远是 0% 命中。
5. **长度必须 4 字节对齐后再解密**，且解完要截回 `fileLength`。
6. **`.ani` 里 `imgId==0xFFFF` 时 `imgParam` 可能整段不存在**（2 字节偏移错误会连锁毁掉整帧）。
7. **全局 `Ani_COORD` 是 i32、帧内 `Ani_COORD` 是 u16**，参考实现两处都写错过。
8. **`.nut` 不是 Document**：按 Document 解会得到一堆空行（type 错位却"不报错"），必须按文本读。
9. **`.lst` 是 Document 不是二进制表**：ID 与路径是交替的 5 字节记录。
10. **`.chn.str` 坏了 ≠ 中文坏了**：sf115 的 `.chn.str` 语言表在构建时就损坏（U+FFFD 是文件里的真实字节），
    但文档正文串（`stringtable.bin`）是完好的 big5 繁体 —— 别因为看到 `.str` 坏了就放弃中文名。
11. **编码判据要看 `stringtable.bin`，且要罚私用区**：只看 `.str` 或只比"CJK 数量"会被 gb18030 骗过去
    （big5 字节用 gb18030 解会生成大量 `U+E000–U+F8FF` 私用区字符，看着像汉字其实全是垃圾）。
11. **文件名大小写**：日志里见过 `.NPK/.npk` 混用，索引查找要大小写不敏感。
12. **`0x1000` 后的头部保护**：`人造神客户端/Script.pvf` 只加密了前 4KB，正文与 `sf115/Script.pvf` 完全相同。

## 10. 复现命令

```bash
# 概览（版本/条目数/后缀分布/字符串表）
python3 tools/pvf_unpack.py info "/mnt/e/dnf-sf/sf110.08/客户端/客户端神话8.0/Script.pvf"

# 列条目 / 搜路径
python3 tools/pvf_unpack.py list <pvf> --grep "character/swordman" --limit 20

# 单文件转文本（Document / .ani / .nut 自动分派）
python3 tools/pvf_unpack.py cat <pvf> "character/swordman/swordman.chr"
python3 tools/pvf_unpack.py cat <pvf> "sqr/character/atmage/bloodfire/bloodfire.nut"

# 批量导出到目录（Document/ANI 转 .txt，二进制保持原样）
python3 tools/pvf_unpack.py extract <pvf> --out analysis/pvf/sf110 --grep "monster/goblin/" --max 30

# 原文落盘（字节级对照用）
python3 tools/pvf_unpack.py raw <pvf> "npc/npc.lst" --out /tmp/npc.lst
```

工具：`tools/pvf_unpack.py`（纯 Python，无第三方依赖；容器/Document/ANI/文本 四种解码器 + 变体自动判定）。
参考实现：[flwmxd/DNF-Porting](https://github.com/flwmxd/DNF-Porting)（C++，本机副本 `/tmp/pvfsrc/`）。
