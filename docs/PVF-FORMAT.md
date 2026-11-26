# PVF 文件格式笔记

基线文件：`data/Script.pvf`（来自 `/mnt/e/dnf-sf/sf115/` 人造神客户端，923,262,293 字节，2026-07-28）

| 属性 | 值 |
|---|---|
| 格式版本 | `53579` |
| UUID | `fa08bf71-4395-6a4b-a3e3-2617c9fee116` |
| 目录树长度 | 141,585,212 字节 |
| CRC | `0x5c72be97` |
| 文件数 | 1,460,792 |
| 数据总量 | 781,676,984 字节 |

---

## 1. 容器结构

```
[ i32 uuid_len ][ uuid ][ i32 version ][ i32 tree_len ][ u32 tree_crc ][ u32 file_count ]
[ 加密的文件树 (tree_len 字节) ]
[ 文件数据区 ... ]
```

- 头部 56 字节。
- 文件树按 `tree_crc` 解密：
  - `key = 0x81A79011`
  - `xor = tree_crc ^ key`
  - 按 **4 字节小端字**异或 `xor`，再对每个字做
    `(v & 0x3F) << 26 | (v & ~0x3F) >> 6` 的位旋转。
- 树每项：

```
u32 filenameLen
u32 pathLen
char path[pathLen]         # 全部小写
u32 fileLength             # 向上取 4 对齐后的长度
u32 fileCrc32
u32 relativeOffset         # 相对「header + tree」结束位置的偏移
```

> 注意：`fileLength` 是**对齐后**长度，读原始字节时要按 `relativeOffset` 取。

## 2. stringtable.bin

```
[ u32 count ]
[ u32 start[count] ]        # 每个字符串的起始字节偏移（相对本文件 +4）
[ 字符串字节区 ]
```

- `count = 1,650,063`
- 第 `n` 个字符串 = `bytes[start[n] : start[n+1]]`，最后一个到文件末尾。
- **踩坑记录**：`R1ddles/pvf_python` 的 `StringTable` 注释说「指第 n 和 n+1 个 int，不是第 n 组 int」，即索引区是**每串一个 u32**（不是 start/end 成对）。若误按 `n*8` 取会整体偏移一倍，读到的全是别的字符串——**看起来仍是通顺中文，所以极难发现**。正确读法是 `u32 at 4*n` 与 `4*(n+1)`。

## 3. 数据文件：标签流

除 `.ani` / `.nut` / `.str` 外，PVF 数据文件都是「标签流」：

- 从偏移 **2** 开始，每单元 5 字节：`u8 type + 4 字节值`（小端）。
- `type` 语义：

| type | 含义 |
|---|---|
| 2 | 整数（int32） |
| 3 | 整数（同 2，语义上多为 bool） |
| 4 | 浮点（float32） |
| 5 / 6 / 8 | stringtable 索引 |
| 7 | stringtable 索引（输出时加引号） |
| 9 | 二次替换：`n_string[值1][stringtable[值2]]` |

- 前两字节（`0xB0 0xD0`）是版本标记，解析时跳过。
- 解析后按 `[tag] value...` 的层级结构还原成文本，就是 `export/text/` 里的样子。

## 4. 文本编码：Big5 + GBK 混合

这是本项目最容易踩的坑。

- 客户端基底是**台服**：`stringtable` 与内联字符串是 **Big5（繁体）**。
- 但私服（人造神）往里注入了 **GBK（简体）** 字节串，同一个 stringtable 里两种编码并存。
- 因此**不能全局用一种编码**，必须逐字符串判别。
- 判别方法（`tools/pvf_loader.py:decode_any`）：
  1. 分别尝试 Big5 / GBK 解码；
  2. 用字符频度表 `data/zh-common.txt`（由 `代码表/*.txt` + AgentKnowledge 语料统计，并补上对应繁体形）算「常用字占比」；
  3. 出现日文假名直接重罚（GBK 字节被误读成 Big5 时常落在假名区）；
  4. 取分数高者，同分优先 Big5。

效果：`堈嘉も慫 - 湮蔚濂` → `远古奇迹 - 大将军`。

## 5. n_string.lst 与 .str 本地化

- `n_string.lst`：26 条，`id → .str 路径`，例如
  `0 → Character/Character.chn.str`、`3 → equipment/equipment.chn.str`。
- `.str` 是明文 `key > value`，用于把 `type 9` 的 key 二次替换成文本。
- 本客户端里 **`equipment/equipment.chn.str` 只有 4 字节（空）**，其它（skill 1.3MB、quest 2.7MB、monster 114KB…）都有内容。
- 结果：技能/任务/怪物文本能正常还原；**物品名大量以 `name_xxxxxx` 这类 key 形式残留**。
- 物品名补救：`/mnt/e/dnf-sf/sf115/代码表/所有代码.txt`（UTF-8，134,384 条，`代码<TAB>名称`），可做 id→中文名映射。

## 6. 各类型文件

| 扩展名 | 数量 | 性质 |
|---|---|---|
| `.ani` | 1,058,561 | **二进制**动画描述（版本 6），引用 `.img` 帧图；P0.5 待解析 |
| `.equ` | 108,645 | 标签流：装备/时装 |
| `.act` | 77,511 | 标签流：动作脚本（[MOTION]/[TRIGGER]/[BEHAVIOR]） |
| `.als` | 77,490 | 标签流：动作链接（动画别名） |
| `.stk` | 28,794 | 标签流：可堆叠物品 |
| `.obj` | 24,436 | 标签流：被动对象 |
| `.atk` | 18,877 | 标签流：攻击信息/判定盒 |
| `.ai` | 13,969 | 标签流：AI |
| `.til` | 9,944 | 标签流：地块图集 |
| `.ptl` | 6,632 | 标签流：粒子 |
| `.key` | 6,461 | 标签流：AI 按键序列 |
| `.map` | 5,800 | 标签流：地图 |
| `.mob` | 4,042 | 标签流：怪物 |
| `.skl` | 4,005 | 标签流：技能 |
| `.qst` | 3,852 | 标签流：任务 |
| `.apd` | 3,382 | 标签流：附加体（buff/状态） |
| `.nut` | 2,489 | **明文** Squirrel 脚本 |
| `.npc` | 811 | 标签流 |
| `.cre` | 631 | 标签流：宠物 |
| `.dgn` | 625 | 标签流：副本 |
| `.etc` | 620 | 标签流 |
| `.aic` | 595 | 标签流：AI 角色 |
| `.rep` | 484 | 标签流 |
| `.ui` | 378 | 标签流：界面 |
| `.twn` | 81 | 标签流：城镇 |
| `.lst` | 58 | id → 路径 注册表 |
| `.str` | 28 | 本地化表 |

## 7. 工具与用法

```bash
# 建索引（1,460,792 条 → export/_meta/index.sqlite）
.venv/bin/python tools/pvf_extract.py index

# 导出可读文本树（约 90 秒，12 进程）
.venv/bin/python tools/pvf_extract.py text --jobs 12

# 只导出某几个根目录 / 扩展名
.venv/bin/python tools/pvf_extract.py text --roots skill,equipment --exts skl,equ

# 导出 stringtable / n_string / 全部 .lst 注册表
.venv/bin/python tools/pvf_extract.py meta

# 看单个文件
.venv/bin/python tools/pvf_extract.py show stackable/lv105_equipment/6012124.stk
.venv/bin/python tools/pvf_extract.py show --zhconv skill/swordman/armormasterycloth.skl

# 查文件在 PVF 里的位置/大小
.venv/bin/python tools/pvf_extract.py info monster/championtower/john/animation/stay_0.ani
```

## 8. 输出目录

```
export/
├── text/            # 39.5 万个解码后的文本文件（镜像 PVF 路径，追加 .txt）
│   ├── character/   # 14 个职业树
│   ├── skill/       # 3,656 个技能
│   ├── equipment/   # 10.4 万装备
│   ├── monster/     # .act/.ai/.atk 等
│   └── ...          # 106 万个 .ani 以 <path>.bin 原样保留（待 P0.5 解析）
└── _meta/
    ├── index.sqlite       # 全量索引：path/ext/size/crc/offset/kind
    ├── ext-stats.tsv      # 扩展名统计
    ├── roots.tsv          # 根目录统计
    ├── stringtable.tsv    # 165 万条字符串（index<TAB>text）
    ├── n_string.tsv       # n_string 映射
    ├── lst/*.tsv          # 58 个注册表的 id→path
    └── SUMMARY.json
```

## 9. 尚未解决

- `.ani` 二进制格式（版本 6）未解 → P0.5
- 物品名 key 未解析 → 需要 `.chn.str`（本客户端为空），改用 `代码表` 映射
- ~~`.lst` 边界格式：`n_quest/epicquest.lst`、`trainingquest.lst` 解析报错~~ → 已解决，见下节
- 服务端逻辑（伤害公式/掉落率/经验）不在 PVF 内

## 10. 文本渲染的截断陷阱（2026-10-26 补，重要）

`pvfReader.dictSegment2text(dictSegment, maxSegNum=50, depth=4)` 有两个默认限制，**会把数据悄悄截断**：

1. `maxSegNum=50`：任何数组超过 50 个值 → 只留前 50 个 + `...`；
2. `depth=4`：嵌套超过 4 层 → 整段退化成 Python dict 的字符串表示；
3. 更隐蔽的是**递归调用没有把 `maxSegNum` 传下去**（`dictSegment2text(segment, prefix+prefixAdd, depth=depth-1)`），所以嵌套块一律按默认 50 截断。

实测影响（同一文件，默认渲染 vs 完整渲染）：

| 文件类型 | 平均膨胀 | 单文件最大 |
|---|---:|---:|
| `.chr`（角色基表） | **15.9×** | 29× |
| `.apd`（附身/召唤） | 2.1× | 28× |
| `.skl`（技能） | 1.8× | 3× |
| `.mob`（怪物） | 1.4× | 6× |
| `.equ / .dgn` | 1.1× | 2× |
| `.qst / .act / .atk / .obj / .nut` | 1.0× | 1× |

例：`character/swordman/swordman.chr` 默认渲染 1,535 字节 / 102 行，完整渲染 **24,863 字节 / 514 行**。

**结论**：`export/text` 已改为无截断渲染（`tools/pvf_loader.py: render_dict_full()`，`pvf_extract.py text --full`）。
做数值校验、读 `[level info]` / `[level property]` / 长 `[greed]` / 顶层键 >50 的 `.equ` 时，**必须用不截断的版本**；
早期用默认渲染导出的副本只能当"目录浏览"用，不能当数据源。

## 11. `.lst` 的两种形态（重要）

扩展名不可信。58 个 `.lst` 里有 **55 个是 id→路径表**（`<bIbI>` 10 字节记录：type2=int 主键、type7=stringtable 索引指向路径），
另外 **3 个是标签流配置**，只是历史原因套了 `.lst` 后缀：

| 文件 | 内容 |
| --- | --- |
| `n_quest/epicquest.lst` | `[episode]` → `[episode_name]` / `[epic_index]`（任务 id 列表）/ `[complete_text]` |
| `n_quest/trainingquest.lst` | 同上结构（教学任务） |
| `n_quest/dailyrandomquest.lst` | `[group]` → 每日随机任务 id 列表 |

判据：用 `Lst_lite2`（`<bIbI>`）解析时若在 `StrIndexIndex` 上抛 `UnboundLocalError`，就说明是标签流。
统一入口 `tools/pvf_loader.py: read_lst_any(pvf, path)` → `("table", rows)` 或 `("text", rendered)`。
`pvf_extract.py` 的 `text` / `meta` 命令都已改走它，因此 `export/text/n_quest/*.lst.txt` 现在是完整可读文本。
