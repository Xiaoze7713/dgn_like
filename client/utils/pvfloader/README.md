# PVF 加载器（Godot 4.7 / GDScript）

## 新版（latest，world 运行时用）

| 文件 | class_name | 职责 |
|---|---|---|
| `pvf_new_archive.gd` | `PvfNewArchive` | 读 850 MB 原生 `Script.pvf`：AES 段 + `nkpi` + 文件表/字符串池/body zlib |
| `pvf_new_doc.gd` | `PvfNewDoc` | 把 token 流解析成 `DocNode` 树；`node_ints/node_strs` 辅助 |

```gdscript
var a := PvfNewArchive.new()
a.open("/mnt/d/dnf_latest/Script.pvf")
print(a.stats())             # files/body/groups/strings
var raw := a.read("list/town.lst")
var hit := a.find("town/hendonmyre.twn")  # Vector4i(chunk, off, size, dtype)
```

`open()` 会自动找同目录的 `DNF.exe` / `sk.dat`；首次 `find()` 会建目录索引（约 4.5 s），之后按目录只查候选（1–9 ms）。`read()` 返回的容器是 `nkpi`，不经过 sqlite/JSON。

旧版（sf115 等 56 B 头）加载器仍保留在下面；`PvfArchive` 不能读 latest。

读 DNF 的 `Script.pvf`（本机实测：`/mnt/e/dnf-sf/sf115/Script.pvf`，1,460,792 条，目录树 141 MB，整包打开 5.5 s）。

五个文件，一层只干一件事：

| 文件 | class_name | 职责 |
|---|---|---|
| `utils/pvfloader/pvf_types.gd` | `PvfTypes` | **纯数据结构**：`Header` / `Entry` / `DocNode` / `AniFrame` / `AniData` |
| `utils/pvfloader/pvf_archive.gd` | `PvfArchive` | 容器：56 B 头、解密、目录树、条目读取、字符串表 |
| `utils/pvfloader/pvf_document.gd` | `PvfDocument` | 把 `.equ/.chr/.lst/...` 的 5 字节记录流解析成 `DocNode` 树 |
| `utils/pvfloader/pvf_animation.gd` | `PvfAnimation` | 把 `.ani` 解析成 `AniData`（帧、精灵模板、判定盒） |
| `utils/PVFLoader.gd` | `PvfLoader` | 门面：一次 `open()` 后用路径取东西 |

## 1. 容器格式（`PvfArchive`）

```
+0     i32  guid_len (=36)
+4     36 B guid "fa08bf71-...-2617c9fee116"
+0x28  i32  file_version      (sf115 = 53579)
+0x2C  i32  dir_tree_length   (加密后的字节数 = 141,585,212)
+0x30  u32  dir_tree_checksum (crc32 明文目录树)
+0x34  i32  num_files         (1,460,792)
+0x38  dir_tree_length 字节   加密目录树
之后是数据区，每 4 字节对齐
```

* **解密**（每 4 字节、原地）：

  ```
  key  = dir_tree_checksum                       // 目录树用这个
       = entry.crc32(自己的明文，未对齐补齐后)     // 每个文件用自己的
  mix  = 0x81A79011 ^ key
  plain = ror32(cipher ^ mix, 6)
  ```

* **目录树**（解密后）是 `num_files` 条定长记录流，每条依次是：

  ```
  u32 number        序号（0-based）
  i32 path_length   路径字节数
  ... path          path_length 字节，ASCII
  i32 length        明文长度（未 4 字节对齐）
  u32 crc           明文 crc32（也是这条文件的解密 key）
  i32 rel_offset    相对数据区起点
  ```

  即 `Entry{number, path, length, crc, rel_offset, abs_offset}`，`abs_offset = 56 + dir_tree_length + rel_offset`。

* **字符串表**：`stringtable.bin` 自成一条目

  ```
  i32 count
  (count+1) × i32 offsets      // offs[i] = 第 i 条文本起点 - 4
  文本区（纯拼接，没有长度头）
  第 i 条正文 = buf[offs[i]+4 : offs[i+1]+4]
  ```

  `n_string.lst` 是另一张表（magic `53424`），把字符串下标映射到「语言表文件」，内容形如 `key>value`，供 `StringLink(type 10)` 用。

## 2. 数据结构（`PvfTypes`）

```gdscript
PvfTypes.Header        # guid / file_version / dir_tree_length / dir_tree_checksum / num_files / data_start
PvfTypes.Entry         # number / path / length / crc / rel_offset / abs_offset，padded_length() 给对齐后的长度
PvfTypes.DocNode       # name / attrs / children / has_end
    .first("items")     # 取第一个同名子段
    .has("x")  .child_nodes()  .value_at(0)  .get_int(0)  .get_float(0)  .get_str(0)  .get_int_array(0)
    .to_text()          # 还原成带 [段名] 的文本，调试用
PvfTypes.AniFrame      # img_id / img_param / sprite / x / y / delay / damage_boxes / attack_boxes
PvfTypes.AniData       # frame_count / sprites / params / frames / is_exact() / sheet_path(tpl, look, color)
```

`DocNode.attrs` 的值是 `int` / `float` / `String` 三种（对应原始记录 type 2 / 4 / 7）。

## 3. 用法

```gdscript
var pvf := PvfLoader.new()
var err := pvf.open("E:/dnf-sf/sf115/Script.pvf")   # 5.5 s，主线程会卡一下
if err != OK: return

# 1) 存在性 / 列表
pvf.archive.has("character/swordman/swordman.chr")   # 大小写不敏感兜底
pvf.list_dir("character/swordman/animation/").size()
pvf.find_suffix(".ani").size()

# 2) 原始字节 / 文本
var raw: PackedByteArray = pvf.get_bytes("equipment/character/swordman/avatar/coat/acoat_default.equ")
var text: String = pvf.get_text("character/swordman/swordman.chr")

# 3) 结构化文档
var doc := pvf.get_document("equipment/character/swordman/avatar/coat/acoat_default.equ")
var job := doc.first("animation job").first("swordman")
print(job.first("variation").to_text())
#  [variation]
#      0
#      0
print(doc.to_text())        # 整份还原

# 4) 动画
var ani := pvf.get_animation("character/swordman/animation/move.ani")
print(ani.frame_count, " 帧，", ani.sheet_path(), " 模板=", ani.sprites)
for fr in ani.frames:
    print(fr.img_id, fr.x, fr.y, fr.delay, fr.damage_boxes, fr.attack_boxes)

# 5) 不确定类型时
var any = pvf.read_auto("character/swordman/animation/move.ani")   # -> AniData
```

**不想卡主线程**：

```gdscript
pvf.open_threaded(".../Script.pvf")
# 在 _process 里轮询，-1 表示还在跑
while true:
    var n := pvf.poll_loaded()
    if n >= 0:
        print("打开完成：%d 条" % n)
        break
    await get_tree().process_frame
```

## 4. 两个坑（已在代码里处理）

1. **换行/编码**：路径与段名基本都是 ASCII；`sf115` 只有 10 条路径含非 ASCII。GDScript 没有 big5/gb18030 解码器，中文值会退化成乱码（字节 1:1 保留）。想显示中文名，最省事的是直接用第 6 节的 UTF-8 包（见下），否则塞一个 Callable 进去：

   ```gdscript
   pvf.archive.set_text_decoder(func(raw: PackedByteArray) -> String:
       return YourCSharpEncoding.GB18030_GetString(raw)   # 或 Godot 4.4+ 的 JavaClassWrapper 之类
   )
   ```

   `decode_text()` 内部的顺序是：自定义解码器 → 纯 ASCII 快路径 → 自验 UTF-8 → latin1 兜底（绝不触发引擎的 "Unicode parsing error" 刷屏）。

2. **`.ani` 有多种历史变体**（46 种组合：`img_param` 是否省略、坐标 1/2/4 字节、类型严格与否、未知字段长度 0..32）。`PvfAnimation` 逐个试，取「正好把字节消费完」的那个；`AniData.variant` 记下命中的变体，`is_exact()` 判断是否严丝合缝。**不要**用固定偏移硬读。

## 5. 自测

```bash
# 夹具：从真实 Script.pvf 抽 5 个文件，把 93 MB 的字符串表裁到 611 条 -> 29 KB
python3 tools/make_test_pvf.py --out /tmp/pvf_test

# 56 项断言：容器/路径/文档树/动画逐帧字段
XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=$PWD/client \
  ./tools/godot.sh --headless --script res://tests/test_pvf_loader.gd

# 加整包：打开真实 1,460,792 条并计时
PVF_FULL=/mnt/e/dnf-sf/sf115/Script.pvf ... 同上
```

当前结果：`56 通过 / 0 失败`，整包 `1460792 条，解密+建表 ~5.5 s`。

> 新增/改名 `utils/` 下的脚本后，非编辑器模式不认新文件，先跑一次
> `./tools/godot/godot --headless --path client/ --editor --quit`

## 6. 中文显示：直接换 UTF-8 包（推荐）

GDScript 没有 GBK/BIG5 解码器。与其在运行时塞 C# 解码器，不如**离线把字符串表改成 UTF-8**：

```bash
python3 tools/pvf_to_utf8.py --dst build/Script.utf8.pvf
```

- 原理：PVF 里所有文本都不内联，只在 5 字节记录里存 i32 下标指向 `stringtable.bin`。
  只把表换成 UTF-8、**条数与顺序不变**，下标全都不用改；正文文件密文原样复制（crc 不变）。
  整包只是「表变长 + 后面所有文件整体后移」。
- 实测：`923,262,293 → 938,807,745 B`（+14.8 MB），耗时 ~66 s，1,650,063 条全部是合法 UTF-8。
- **编码是混排的**：469,359 条非 ASCII 里
  `big5hkscs 329,246 / gb18030 122,466 / cp949 17,409 / shift_jis 133 / utf-8 78 / cp950 26 / big5 1`。
  这个包里同时存在四种语言：简体 GBK 汉化、BIG5 繁体（比简体还多，如「悲鳴洞穴」「冒險家名望」）、
  **没被汉化的韩文原文**（CP949，如 `뇨뇽이` / `도와주소` / `아이템 특수효과 발동`）、
  **日文活动文本**（Shift-JIS，如 `今まで` / `今日のミッション`）。统一按 gb18030 解会把后三种
  全部解成乱码——而 gb18030 几乎不抛异常，所以「解不开 0 条」并不能证明编码猜对了。
- 逐条判据（`detect_decode`）：① **UTF-8 严格校验先手**（字节能过就一定是 UTF-8）；
  ② 中文按「常用字 +2 / 生僻字 +1 / 扩展 A −2」打分，韩文按「谚文音节：高频音节 +3、其余 +1，
  出现非谚文 −3」打分，日文只在出现**全角假名**时计分（中文按 SJIS 解只会得到半角片假名，
  所以全角假名是硬信号）；③ 同分保留先出现的（中文优先）——包里中文:韩文 ≈ 30:1，短串按先验归中文。
- 已知残留：约 1,900 条**短韩文**（2~3 个音节，如 `녹색`/`갈색`/`풀색`/`샷!!!`）与 GBK 的字节空间
  完全重叠，按 GBK 解也是合法汉字（「踌祸」「哎祸」「鸡!!!」），没有词频表无法区分，仍归中文。
- 真正救不回的只有 702 条（0.15%）：源包打包前就把字节换成了字面 `?`(0x3F)，信息已丢。
  清单见工作区 `analysis/pvf/broken/broken-strings.tsv`（生成器 `tools/pvf_string_census.py`）。
- 换完之后 GDScript 侧什么都不用改，`decode_text()` 的 ASCII 快路径 + 自验 UTF-8 就够：

  ```bash
  XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=$PWD/client \
    ./tools/godot.sh --headless --script res://tests/probe_utf8_pvf.gd
  #  条目 1460792，耗时 5107 ms
  #  [name] = 基本上衣
  ```

- 注意：这个包**只给 Godot 用**，DNF 客户端读不了（它按自己的代码页解）。
- 救不回来的：源包本身就是坏的条目的（目录树里 10 条中文路径、少量双重编码串），任何编码都还原不了。

### 6.1 显示名不在 stringtable（必须一起转 *.kor.str）

`.equ` 里的 `[name]` 走的是另一条链：

```
[name] → 记录类型 0x0A (STR_LINK) → 下标 → `name_40600`
      → n_string.lst → *.kor.str 文本表 → `name_40600>基本上衣`
```

所以只转 `stringtable.bin` 会得到「路径对了、名字还是乱码」。`tools/pvf_to_utf8.py`
现在会额外把 **`*.str` / `*.txt` 纯文本文件**整体转成 UTF-8（先按行抽样投票定编码，
逐行解码，结果必须整体合法 UTF-8 才采纳；`.lst` 多为二进制记录，已排除）。

### 6.2 一个 4 字节对齐的坑（尾巴变垃圾）

文件体是「补足 4 字节后整组加密」。写侧按 `length` 原样加密、读侧按 `pad4(length)`
解密时，**最后一组会被多解一次**，文件尾 1–3 字节变成垃圾（现象：`.str` 尾 `禮包>`
变 `@%\xaa` → 整文件 UTF-8 校验失败 → 退回 latin1 → 全文件乱码）。
新内容必须先补到 4 的倍数（文本用换行补齐，不塞 NUL）再加密、再记 length。

### 6.3 两个包的实测

| 包 | 源 | 产物 | 字符串改写 | 文本表 | 坏串 |
|---|---|---|---|---|---|
| sf115（110 级，玩家 DIY） | 923,262,293 B | `build/Script.utf8.pvf` 938,807,745 B | 469,359 | — | 702 条 + 一片乱码带 |
| sf85（老牛 85 版，干净） | 205,695,984 B | `build/sf85.Script.utf8.pvf` 209,076,192 B | 42,682 | 44 个文件 / 155,955 行 | 0 条 |

**做移植建议用 85 包**：结构干净、体量小（196 MB vs 923 MB）、NPC/副本命名是经典版
（格兰之森叫 `mirkwood` 而不是 110 版的 `granfloris`）。详见
`/home/sunmingze/dnf_like/analysis/pvf/sf85-report.md`。
