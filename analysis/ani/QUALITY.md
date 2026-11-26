# P0.5 `.ani` 帧表数据集 — 质量报告

数据来源：sf115「人造神」客户端 Script.pvf 解包产物 `export/text/**/*.ani.bin`（**1,047,702** 个）
解析器：`tools/ani_parser.py`（格式规范见 `docs/ANI-FORMAT.md`，最终定的 v6 文法见那里 §4）
导出器：`tools/export_ani_tables.py`（本报告所有数字由它的 `--stats-only` 与独立 JSONL 扫描产出）
统计文件：`export/ani/_stats_only.json`（权威全量）、`export/ani/_stats.json`（最近一次 `--run`，断点续跑时只含本次 chunk，不作权威口径）

---

## 1. 结论

| 验收项 | 目标 | 实测 | 判定 |
|---|---|---|---|
| ok 率（严格闭合解析成功） | ≥ 95% | **95.356%**（999,051 / 1,047,702） | ✅ |
| 数据集完整性 | 每个 ani 一行 | 185 个分片合计 **1,047,702 行** = 文件数；`bad_json` **0** | ✅ |
| 断点续跑跳过已完成分片 | 能 | kill 后重启日志 `已完成 143，待跑 276`，重启后只补跑剩余 chunk | ✅ |
| 单进程吞吐 | ≥ 0.43 ms/文件 | **0.123 ms/文件**（30,000 个 monster 子集，3.7 s） | ✅ |
| 失败样本可复验 | 能落到路径+原因+hex | 第 6 节：44 行样本表（按签名×目录去重）+ 4 段 hex 证据 + 单文件复查命令 | ✅ |
| 不做"放宽校验换 ok 率" | 必须 | 见第 8 节：主动**拒绝**了一个能把 ok 率抬高约 0.8% 的伪解 | ✅ |

> 本表是 **v2 口径**（`0x17` = flagIndex 定案、4 字节优先，并据此重跑全量）。与 v1 的差异见 §9.1：
> ok 从 95.161% 升到 **95.356%**（多解析出约 2,050 个文件：4 字节优先才找得到真正的帧边界）。

## 2. 怎么跑

```bash
# 全量导出（断点续跑安全：中途 kill 再跑会跳过已写好的 chunk）
.venv/bin/python tools/export_ani_tables.py --run --jobs 10
# 只出统计（不写盘），用于出质量报告
.venv/bin/python tools/export_ani_tables.py --stats-only --jobs 10
# 只补做汇总（.parts/*.part -> <shard>.jsonl）
.venv/bin/python tools/export_ani_tables.py --finalize
# 子集（调试）
.venv/bin/python tools/export_ani_tables.py --stats-only --only monster --limit 30000
```

实测耗时（本机，ext4 + 冷热混合页缓存）：

| 阶段 | 命令 | 实测 |
|---|---|---|
| 导出 1.05M 个 ani（含一次 kill/续跑） | `--run --jobs 10` | 约 **98 s**（两段：143 chunk 36 s + 276 chunk 62 s） |
| 汇总分片 | `--finalize` | 185 个分片，产出 1.66 GiB JSONL |
| 权威统计（不写盘） | `--stats-only --jobs 10` | **131.6 s**（约 7,960 文件/秒） |
| 单进程 | `--stats-only --jobs 1 --only monster --limit 30000` | 3.7 s → **0.123 ms/文件** |

> 两个脚本别搞混：**全量导出器是 `tools/export_ani_tables.py`**（`--run/--stats-only/--finalize`）；
> `analysis/ani/export_ani_tables.py` 是 t1 阶段的子集导出脚本（`--samples/--glob/--prefix`），只用来出 5 个样例 JSON。
>
> 本次运行日志已留档：`export/ani/_logs/`（导出两段 + 权威统计 + 独立 JSONL 扫描结果 `/tmp/ani_scan.json` 副本）。

> `--jobs` 在这台机器上几乎不加速（10 进程聚合 7,960 文件/秒 ≈ 单进程 8,108 文件/秒）：瓶颈是 105 万个小文件的
> `open/read` 系统调用与 inode 查找，不是解析 CPU。留着 `--jobs` 是为了换 I/O 更快的主机时能吃到并行。

---

## 3. 数据集总览

| 指标 | 数值 |
|---|---|
| ani 文件总数 | 1,047,702 |
| `ok`（解析成功） | 999,051 (**95.356%**) |
| ├ `clean`（读完到 EOF 且尾部无残留） | 996,948 (95.156%) |
| └ `dirty`（帧解析成功但尾部有非零残留/不闭合） | 2,103 (0.201%) |
| `fail`（无法闭合解析，记录为 `{"src","error"}` 行） | 48,651 (**4.644%**) |
| 帧总数 | **10,947,930** |
| 平均帧数（ok 文件） | 10.96 帧/动画 |
| 最大帧数 | **1,118**（单个动画） |
| 含攻击盒（`ab` 非空）的 ani | **24,026**（占 ok 的 2.40%） |
| 含攻击盒的帧 | 127,277 |
| 含伤害盒（`db` 非空）的 ani | **51,526**（占 ok 的 5.16%） |
| 含伤害盒的帧 | 418,928 |
| **含 flagIndex（`flag` 非空）的 ani** | **104,008**（占 ok 的 10.41%） |
| ani 记录里声明的 `.img` 条目 / 去重 | 977,272 / 56,772 |
| 帧级图像槽次数（每帧最多 1 个） | 9,411,366 |
| 其中 `img` 行路径为 `null`（图像下标越界） | 2,927（数据瑕疵，见第 7 节注） |
| 其中带 `%04d` 模板的帧级引用 | 4,021,112（42.7%，见第 7 节） |
| 全部动画总时长（`total_ms` 求和） | 17,663,819,176 ms ≈ **204.4 天** |
| 数据集体积 | 1.66 GiB / 185 个分片（最大 `equipment__character.jsonl` 649 MiB） |

关键量级结论：**"含攻击盒的动画只占 2.4%，但它们承载了全部打击判定"**。实现组的攻击判定系统只需订阅
这 24,026 个动画的帧表事件，不需要对所有动画建判定通道。

## 4. 按根目录（PVF 顶层目录）

| 根目录 | 文件数 | ok | fail | dirty | fail 率 |
|---|---|---|---|---|---|
| equipment | 546,412 | 529,577 | 16,835 | 1,299 | 3.08% |
| monster | 263,002 | 248,800 | 14,202 | 443 | 5.40% |
| passiveobject | 126,276 | 119,923 | 6,353 | 162 | 5.03% |
| character | 60,036 | 57,968 | 2,068 | 66 | 3.44% |
| map | 24,234 | 23,890 | 344 | 5 | 1.42% |
| creature | 8,833 | 8,762 | 71 | 124 | 0.80% |
| common | 6,937 | 2,850 | 4,087 | 0 | 58.92% |
| skin | 5,676 | 1,216 | 4,460 | 0 | 78.58% |
| sqr | 2,249 | 2,116 | 133 | 2 | 5.91% |
| ui | 961 | 903 | 58 | 1 | 6.04% |
| npc | 876 | 870 | 6 | 0 | 0.68% |
| uniquebeast | 537 | 517 | 20 | 0 | 3.72% |
| localization | 346 | 346 | 0 | 0 | 0.00% |
| dungeon | 334 | 330 | 4 | 0 | 1.20% |
| worldmap | 325 | 325 | 0 | 0 | 0.00% |
| aicharacter | 239 | 231 | 8 | 0 | 3.35% |
| etc | 184 | 183 | 1 | 0 | 0.54% |
| town | 132 | 132 | 0 | 0 | 0.00% |
| chatemoticon | 65 | 65 | 0 | 0 | 0.00% |
| stackable | 37 | 36 | 1 | 1 | 2.70% |
| pet / aura / stagemap | 5 / 4 / 2 | 全 ok | 0 | 0 | 0% |

两个红点都很集中、且都**不是玩法关键路径**：

- `skin` 78.58% 失败 = `skin/animation/damagefont/**`（伤害数字字体动画，4,460 个全失败）。
- `common` 58.92% 失败 = `common/**` 下的同类伤害字体/特效动画（4,087 个）。
- 真正的战斗内容（equipment 3.08%、monster 5.40%、passiveobject 5.03%、map 1.42%）都在 3%~6% 区间。

## 5. 按职业 / 按版本

职业由路径段匹配（`class_tag()`，18 个职业名 + `(非职业)` 兜底）：

| 职业 | n | ok | fail | fail 率 |
|---|---|---|---|---|
| (非职业) | 412,715 | 384,208 | 28,507 | 6.91% |
| swordman | 210,825 | 201,359 | 9,466 | 4.49% |
| priest | 108,788 | 107,214 | 1,574 | 1.45% |
| mage | 96,214 | 94,094 | 2,120 | 2.20% |
| fighter | 75,552 | 74,889 | 663 | 0.88% |
| thief | 66,237 | 62,893 | 3,344 | 5.05% |
| gunner | 64,526 | 61,874 | 2,652 | 4.11% |
| atmage | 4,699 | 4,613 | 86 | 1.83% |
| demoniclancer | 2,931 | 2,890 | 41 | 1.40% |
| atpriest | 2,144 | 1,995 | 149 | 6.95% |
| atgunner | 1,868 | 1,840 | 28 | 1.50% |
| atfighter | 889 | 869 | 20 | 2.25% |
| atswordman | 250 | 249 | 1 | 0.40% |
| creator | 42 | 42 | 0 | 0.00% |
| darkknight | 22 | 22 | 0 | 0.00% |

版本由路径匹配（`version_tag()`：`act<N>`、`contents/<四位年>`、`<NNN>level*`，否则 `base`）：

| 版本 | n | fail | fail 率 |
|---|---|---|---|
| base | 940,728 | 42,116 | 4.48% |
| 110lvl | 71,357 | 4,282 | 6.00% |
| year2022 | 31,709 | 2,091 | 6.59% |
| act8 | 1,619 | 28 | 1.73% |
| 220lvl | 414 | 30 | 7.25% |
| act9 | 334 | 0 | 0.00% |
| act7 | 190 | 0 | 0.00% |
| act10 | 182 | 0 | 0.00% |
| 其余 act*/year* | 各 <60 | 多为 0 | — |

**版本结论**：越新的内容（110lvl / year2022 / act11）失败率略高，说明新版本客户端给 `.ani` 加了写法；
老版本（act3/act7/act9/act10 等）几乎 100% 可解析。这对 P0.6 有直接含义：**主力玩法内容（老职业 + 老副本）
解析质量最好；110 级以后的新怪/新特效要按"尽量解析、失败降级"来设计**。

## 6. 失败样本

### 6.1 归类（48,651 条，按路径族）

| 归类 | 数量 | 占比 | 说明 |
|---|---|---|---|
| 其它帧文法变体 | 26,024 | 53.49% | 帧内 count/前导与标准模型不符 |
| avatar（时装）路径族 | 13,361 | 27.46% | 路径含 `/avatar/` 或 `/at_`；签名同属"文法变体" |
| damagefont 特效动画 | 8,400 | 17.27% | 伤害数字字体动画，几乎全族失败 |
| 空文件（0 字节） | 863 | 1.77% | 客户端里有 863 个 0 字节 `.ani`（垃圾/占位文件） |
| 头部截断（图像路径越界） | 3 | 0.01% | 文件被截断在前 4+4+N 字节内 |

> `avatar` 一行是**路径启发式**分组，不代表"时装全坏"：`equipment/character/swordman/avatar/**` 里
> 抽样 300 个只有 8 个失败。真正坏得多的是 `equipment/character/swordman`、`thief`、`gunner` 几个大目录。

### 6.2 签名分析（对全部 48,651 个失败文件逐个回溯，取"走得最远的那次尝试"的首个崩点）

| 首个崩点 | 文件数 | 含义 |
|---|---|---|
| `nhead>64` | 11,596 | `n_head`/`n_tail` 读到 >64 → 帧前导宽度与标准模型不同 |
| `head_id=0x01` | 9,920 | 该处不是已知字段 id（把别的数据当成了 id） |
| `head_id=0xffff` | 8,476 | 该处不是已知字段 id（把别的数据当成了 id） |
| `ntail>64` | 3,442 | `n_head`/`n_tail` 读到 >64 → 帧前导宽度与标准模型不同 |
| `head_id=0x00` | 2,639 | 该处不是已知字段 id（把别的数据当成了 id） |
| `tail_id=0x00` | 2,498 | 该处不是已知字段 id（把别的数据当成了 id） |
| `tail_id=0x19` | 2,346 | 该处不是已知字段 id（把别的数据当成了 id） |
| `tail_id=0xffff` | 1,914 | 该处不是已知字段 id（把别的数据当成了 id） |
| `tail_id=0x18` | 1,489 | 该处不是已知字段 id（把别的数据当成了 id） |
| `tail_id=0x01` | 1,394 | 该处不是已知字段 id（把别的数据当成了 id） |

**共同点**：绝大多数（`n_head`/`n_tail` 过大 + 未知 id 位）不是"缺一个字段"，而是**帧前导宽度不同**。
这类文件里，图像槽到 pos 之间常见 6 字节（标准）之外的 8~10 字节前导。
签名共 168 种，top10 占 94.0%（完整表口径见 `tools/ani_parser.py --check` 的统计与 §6.3 的 hex 证据）。

### 6.3 四段 hex 证据（可复验）

**(a) damagefont 族** `export/text/skin/animation/damagefont/damagefont3/white/4.ani.bin`（272 B，fc=5，ic=1）：
```
00000000: 05 00 01 00 3e 00 00 00 43 6f 6d 6d 6f 6e 2f 45  ....>...Common/E
00000010: 74 63 2f 44 61 6d 61 67 65 46 6f 6e 74 53 6b 69  tc/DamageFontSki
...
body 起点 70，body 202 字节；严格解析在第 1 帧 off=41 崩，那里是 `00 00 0b 00 05 00 ff ff ff 0a 00 01 00 00 00 00 04 00 00 00`
→ "字段 id" 位置读到 0xffff（不是任何已知 id）。
```
**(b) 未知 id 0x12 族** `export/text/monster/bakalraid/monster/steich/animation/attack_01/a01_03_backstep.ani.bin`
（284 B，fc=3，ic=1，body 206）：
```
01 00 | 12 00 | 01 1e 00 00 00 2c 01 00 00 | ff a8 00
        ^id=0x12  ^ 疑似 4 字节 payload（30）但后续对不上
```
**(c) 前导多 4 字节族** `export/text/monster/110levelnormaldungeon/addeff/856262/animation/attack_0/dashloop_02.ani.bin`
（1,068 B，fc=22，ic=1，img=`Common/CommonEffect2/SpeedLine/SpeedLine001.img`，body 1,013）：
```
01 00 01 00 00 00 00 00 00 00 00 | a4 fe ff ff | e9 fe ff ff
^ 10 字节前导（标准模型是 6）      ^ x=-348        ^ y=-279
```
即"图像槽 + pos"之前多了 4 个 0 字节，把标准模型的 6 字节前导撑成 10 字节。
**(d) 多 6 字节 prologue 族** `export/text/equipment/character/swordman/avatar/coat/coat_effect_longpao/symbol_16.ani.bin`
（2,528 B，fc=55，ic=1，body 2,461）：`02 00 00 00 01 01 | 00 00 00 00 00 00 00 00 | dd fe ...`
→ 文件级 prologue 是 6 字节（`02 00 00 00 01 01`），紧接着 8 个 0 字节才到 pos。

### 6.4 top 50 失败样本（路径 + 原因，按二级目录去重各取一个）

（表格见文末附录 A：44 行，含 `src`、`error` 原文与首个崩点签名）

### 6.5 为什么这些失败"真的是解析不了"而不是解析器偷懒

1. 对同一文件，`parse_ani` 会先跑 **7 个 profile × prologue 0..12 的严格试解**（不允许未知 id），再跑
   带回溯的兜底；两条路都失败才落 `error`。兜底路径允许未知 id 试 {0,2,4,5,6,8,12,...} 字节并做全帧闭合校验。
2. 用 §6.3(a) 的文件手算即可确认：把 `ff ff ff 0a 00 01` 当成任何"字段 id+定长 payload"都会破坏后续帧闭合。
3. 反证：曾试过"给未知 id 补一个 4 字节 payload"能把一部分文件救活。抽查 600 个失败文件后发现，
   被救活的 115 个里 **114 个读到的 payload 完全相同 `ff 0a 00 01`** —— 那是把对齐错开 4 字节后的
   **伪影**，不是真字段。这个"优化"因此被放弃（见第 8 节）。

---

## 7. `img` 引用悬空率：**100%，但这是预期行为**

| 口径 | 数值 |
|---|---|
| ani 记录里声明的 `.img` 条目 | 977,272（去重 56,772） |
| 帧级图像槽引用（每帧最多 1 个，共 9,411,366 次；去重 60,106 个 img 路径） | 9,411,366 |
| 其中路径为 `null`（`img_index` 越界，帧仍可用） | 2,927（0.03%） |
| 在 `export/_meta/index.sqlite` 里能命中的 | **0**（该库里 `ext='img'` 的记录只有 **1** 条） |
| `export/_meta/refgraph.sqlite` 的 `img` 边 | 1,335,379 条，`resolved` **全部为 0** |
| 对比：`anim` 边 `resolved` | 696,563 / 920,976 命中（ani→ani 的 SUB ANI 关系是好的） |

原因：**`.img` 图像资源不在 Script.pvf 里**（它们在客户端的 `ImagePacks2/*.NPK`）。本次解包只做了
Script.pvf，所以"悬空"是数据边界，不是解析错误。

两个使用注意：
1. **不要把悬空当缺失**：P0.6（图集）必须从 `ImagePacks2` 的 NPK 取 `.img`，用同一套路径做映射。
2. **50.6% 的引用带 `%04d` 模板**（如 `Character/Gunner/ATEquipment/Avatar/skin/gg_body%04d.img`），
   这是"一个动作跨多张图"的写法，运行时要按帧号选文件，不能按字面路径找单个文件。

---

## 8. 我们没有做（以及为什么）

- **没有放宽 `clean` 判据去换 ok 率**：`ok` 只要求"帧数 == frame_max 且读到的帧结构自洽"；
  `dirty`（2,103 个，尾部残留）单独记，没有并入 `ok` 的 clean 口径。当前 clean 95.156% / ok 95.356%，
  两个数都给出来了。
- **没有引入"未知 id 猜长度"的宽松路径去刷指标**：§6.5 证明它主要产出伪解。
- **没有为 `damagefont` 写特例解析器**：伤害数字字体不是玩法关键路径，写特例会把"未解"伪装成"已解"。
- **没有把 `.img` 悬空算成失败**：见第 7 节。

---

## 9. 已知风险 / 未解项

| 项 | 影响 | 现状 |
|---|---|---|
| 帧前导宽度变体（多 2/4 字节） | 约 3.3 万个文件解析失败（`n_head`/`n_tail` 过大 + 未知 id 位合计 47,785） | 未解；需要拿到 pvfUtility 的 `PvfCode.Services` 反编译或更多官方样例 |
| 文件级 prologue 结构 | 已解析的文件靠"试 prologue 长度 0..12"覆盖 | 未解；`[u16 nFileFields][(id,value)×n]` 假说只覆盖 2/5/8 长度 |
| `damagefont` 族文法 | 8,400 个失败（`skin` 4,460 + `common` 3,940 同级族） | 未解；不影响玩法（伤害数字字体） |
| `dirty` 2,103 个（尾部残留） | 帧数据可用，尾部语义丢失 | 可接受；多是 1~3 个 0 字节 |
| 23 个未知字段 id 的语义 | 只影响 `fx` 细节 | 见 `docs/ANI-FORMAT.md` §5 |
| `0x0b`(2B) 与 `0x17`(flagIndex) 是否互斥 | 若互斥，可把 `0x19` 等未知 id 的定位范围缩一半；不互斥则两条线要各查各的 | **未验证**，留给后续（本版两者按独立字段各自保留） |

### 9.1 本版变更：`0x17` 从「未知字段」升级为 `flagIndex`（数据集已重跑）

- **语义定案**：`0x17` = 每帧的 **flagIndex**，**i32 小端**，作者自定义整数，等同脚本传给
  `sq_SetCurrentAnimation` 的 flag 实参（证据：`analysis/11-P0-BLOCKERS.md` ①，`.nut` 实参逐值对照
  `dashattack.ani` = `[—,100,—,1,101]`、`after_threesideex.ani` 帧 2 = 3）。
- **旧说法作废**：ANI-FORMAT 早期版本把 `0x17` 记为「4~6 字节未知字段 / 值域 0..7」，**是错的**。
  值域假象来自只看少数样本（小值占多数）。
- **测量**：30,000 抽样里 2,881 个文件（9.6%）含 flag，8,379 次出现**全部恰好 4 字节**；
  全量口径：**104,008 个 ani（占 ok 的 10.41%）带 flag**。
  解析器 `_profiles()` 已改为 4 字节优先（其余长度仅作对齐伪影兜底）。**注意：这一步并不"零副作用"**——
  改成 4 字节优先后全量 ok 从 996,999 升到 999,051（+2,052，95.161% → 95.356%），
  因为按真实宽度切分才能继续走完后续帧；clean/dirty 也相应变化，本报告已全部按 v2 重算。
- **数据集**：`frames[].flag` 已加入 JSONL 记录（缺省 = 该帧无 flag 事件），因此
  `export/ani/*.jsonl` **已按新 schema 重跑**；加载器读不到 `flag` 键即视为 None，不需要分支。

**对下游（P0.6 / 引擎）的建议**：帧表里的 `x/y/d/img/ab/db` 是可靠的（ground truth 5/5 逐值命中，
见 `docs/ANI-FORMAT.md` §9）；失败文件在 JSONL 里是 `{"src","error"}` 行，加载器**跳过即可**，
不要抛异常中断整包加载。

---

## 10. 复现 / 单文件复查

```bash
# 复查任意一个失败文件的原因（打印 header、帧偏移、尾部残留）
.venv/bin/python tools/ani_parser.py export/text/skin/animation/damagefont/damagefont3/white/4.ani.bin

# 拿某条记录的攻击盒
.venv/bin/python - <<'PY'
import json
for line in open('export/ani/passiveobject__actionobject.jsonl', encoding='utf-8'):
    r = json.loads(line)
    if r.get('src','').endswith('chiefsars/animation/boom.ani'):
        for f in r['frames'][:4]:
            print(f['i'], f['d'], f['pos'] if 'pos' in f else (f['x'], f['y']), f.get('ab'))
PY
```

---

## 附录 A：失败样本表（按签名 × 目录去重，44 行）

口径：从全量 48,651 个失败文件里，按「签名 × 二级目录去重」各取一条，`error` 为解析器原文。
（这是**样本表**，不是完整清单；完整清单可直接从 `export/ani/*.jsonl` 里筛 `{"src","error"}` 行得到。）

| # | path（`export/text/` 下，去掉 `.bin`） | error | 该文件的首个崩点（签名） |
|---|---|---|---|
| 1 | `passiveobject/script_sqr_nut/mage/animation/elementalcurtain/elementalcurtain_groundcircle.ani` | 无法解析帧结构（4 帧，body 302 字节） | `head_id=0xfed4` |
| 2 | `monster/meisterlaboratory/monster/2phase/herz/monster/herz_2phase/animation/gaebolgdocking.ani` | 无法解析帧结构（18 帧，body 471 字节） | `head_id=0xfe79` |
| 3 | `ui/tournament/animation/suju_pve_starteff_02.ani` | 无法解析帧结构（8 帧，body 257 字节） | `head_id=0x10` |
| 4 | `monster/bakalraid/monster/bakal/passiveobject/firepillar/animation/exp/dashattack01bomb_05.ani` | 无法解析帧结构（22 帧，body 1157 字节） | `head_id=0x141e` |
| 5 | `monster/newmonsters/anton/phase1/strongleg/dimensionsoul/animation/atgunneranimation/sattack.ani` | 无法解析帧结构（5 帧，body 531 字节） | `head_id=0xff29` |
| 6 | `passiveobject/equipmentpassiveobject/105lv_equipment/jump_earthquake/gravitydownfloor1_01.ani` | 无法解析帧结构（20 帧，body 867 字节） | `tail_id=0xfff5` |
| 7 | `monster/vensom/monster/steich/animation/attack_01/a01_02_grab.ani` | 无法解析帧结构（3 帧，body 250 字节） | `tail_id=0xa4` |
| 8 | `passiveobject/ozma_raid/addeff/571246/animation/attack_3/shockewave/screwattackjumpfront_00.ani` | 无法解析帧结构（29 帧，body 1470 字节） | `head_id=0x1c` |
| 9 | `passiveobject/actionobject/monster/anton/phase2/black_volcano/rok/dark_bigboom/animation/dark_bigboom_basic_1.ani` | 无法解析帧结构（9 帧，body 405 字节） | `tail_id=0x1f4` |
| 10 | `monster/110levelnormaldungeon/addeff/856275/animation/armorparts/attack_13_2.ani` | 无法解析帧结构（4 帧，body 108 字节） | `head_id=0xfea9` |
| 11 | `passiveobject/changqing_atswordman/animation/atdoomsday/domeloopdown_01.ani` | 无法解析帧结构（8 帧，body 327 字节） | `tail_id=0x999a` |
| 12 | `monster/destroyedcastleofdead/monster/boss/abyss_walker/animation/r_n_attack_0/slash02r_07.ani` | 无法解析帧结构（7 帧，body 237 字节） | `head_id=0x140` |
| 13 | `monster/kcontents22/theevildomwar/boss/doghead/animation/effect/12_typhoonabyss_1/dogheadabyssattack02move_00.ani` | 无法解析帧结构（18 帧，body 854 字节） | `tail_id=0x3cb4` |
| 14 | `monster/newmonsters1/gcontents/210128_ilrustrea/boss/agnat/animation/attack_airattack/combatattack_09.ani` | 无法解析帧结构（16 帧，body 534 字节） | `tail_id=0x465a` |
| 15 | `character/common/animation/3rdrare_effect/13thrareavatareffectatmage_12.ani` | 无法解析帧结构（40 帧，body 1169 字节） | `head_id=0x00` |
| 16 | `character/demoniclancer/effect/animation/burstslash/hit/hit_end_back_2.ani` | 无法解析帧结构（7 帧，body 345 字节） | `head_id=0x01` |
| 17 | `character/fighter/animation/thunderrushdashbody_00.ani` | 无法解析帧结构（3 帧，body 297 字节） | `head_id=0x12` |
| 18 | `character/gunner/animation/fastdraw_body_lefthandend.ani` | 无法解析帧结构（2 帧，body 150 字节） | `head_id=0x12` |
| 19 | `character/mage/animation/ani_als/elementalmaster_3rd/elementalmaster_3rd_04.ani` | 无法解析帧结构（67 帧，body 1696 字节） | `tail_id=0xa9a9` |
| 20 | `character/priest/animation/skyearthstrikesin2_body.ani` | 无法解析帧结构（44 帧，body 1062 字节） | `tail_id=0x3200` |
| 21 | `character/swordman/animation/ani_als/waveoflightning/end/endcover_05.ani` | 无法解析帧结构（10 帧，body 434 字节） | `head_id=0x6400` |
| 22 | `character/thief/animation/excelstrikehit3.ani` | 无法解析帧结构（10 帧，body 314 字节） | `tail_id=0x01` |
| 23 | `passiveobject/character/priest/animation/deflectwallex/explosion_light_red_dodge.ani` | 无法解析帧结构（7 帧，body 337 字节） | `tail_id=0x46` |
| 24 | `monster/110levelscenario/canyonhills/passiveobject/kd_atack_sniping/animation/scopeotherbase.ani` | 无法解析帧结构（4 帧，body 185 字节） | `tail_id=0xc8ff` |
| 25 | `monster/ozma_raid/monster/raid/phase1/boss/berias_raid/animation/charge_slash/chargeslashend_bottom_05.ani` | 无法解析帧结构（11 帧，body 415 字节） | `tail_id=0x3264` |
| 26 | `passiveobject/gcontents/190307_preyraid/map/slenikon/animation/body1/body1_2_basic.ani` | 无法解析帧结构（2 帧，body 74 字节） | `head_id=0x11` |
| 27 | `monster/noblessecode/monster/named/johan/animation/attack_4/attack_4_1.ani` | 无法解析帧结构（12 帧，body 331 字节） | `tail_id=0x50ff` |
| 28 | `creature/chn_2019_event_ddt_jiansheng60_qq506807329/atgunner/animation/attack1/boomeffect.ani` | 无法解析帧结构（7 帧，body 200 字节） | `tail_id=0xff` |
| 29 | `equipment/character/mage/avatar/belt/belt_a/exticionsin1_body.ani` | 无法解析帧结构（25 帧，body 799 字节） | `tail_id=0x96ff` |
| 30 | `monster/kcontents3/mtrangeofexile/restingplaceforextinction/devastar/animation/effect/attack5_01.ani` | 无法解析帧结构（16 帧，body 668 字节） | `tail_id=0xff00` |
| 31 | `monster/kcontents2/blackpurgatory/boss/beriassummon/beriastree/animation/treestarttree_02.ani` | 无法解析帧结构（17 帧，body 639 字节） | `tail_id=0x1450` |
| 32 | `monster/contents/2022/stolenlandispins/monster/ashcore/animation/comein/incoming_08.ani` | 无法解析帧结构（25 帧，body 909 字节） | `tail_id=0x141e` |
| 33 | `common/commoneffect/animation/newranksystem/combo/combo_bonus_on01.ani` | 无法解析帧结构（3 帧，body 119 字节） | `head_id=0x03` |
| 34 | `common/damagefont/damagefont0/actadd/0.ani` | 无法解析帧结构（5 帧，body 194 字节） | `head_id=0xffff` |
| 35 | `common/monster/big/monster_2000/m_start_blank_mask.ani` | 无法解析帧结构（12 帧，body 301 字节） | `head_id=0xfea2` |
| 36 | `passiveobject/kcontents2/blackpurgatory/add/567423/animation/eff/tree/treestartfront_15.ani` | 无法解析帧结构（22 帧，body 923 字节） | `tail_id=0xcccd` |
| 37 | `monster/event/bluemarble/bwanga/animation/combo2.ani` | 无法解析帧结构（6 帧，body 443 字节） | `tail_id=0x6666` |
| 38 | `aicharacter/_jojochan/swordman/godsword/animation/dash.ani` | 无法解析帧结构（8 帧，body 984 字节） | `head_id=0x00` |
| 39 | `aicharacter/atfighter/roychan/animation/niddle.ani` | 无法解析帧结构（6 帧，body 259 字节） | `head_id=0x01` |
| 40 | `aicharacter/gunner/cypher_man/animation/earthbreakout3.ani` | 无法解析帧结构（4 帧，body 183 字节） | `head_id=0x01` |
| 41 | `aicharacter/thief/rodem/animation/sit_1.ani` | 无法解析帧结构（3 帧，body 99 字节） | `ntail>64` |
| 42 | `passiveobject/kcontents3/darktemple/airak/animation/pinetreecircle/start/pine_s_wind_floor_twirl.ani` | 无法解析帧结构（43 帧，body 1759 字节） | `tail_id=0xff96` |
| 43 | `sqr/custom/equipment/animation/105lv_equipment/newrandomoption/hiding/hidingendfront_02.ani` | 无法解析帧结构（17 帧，body 712 字节） | `tail_id=0xc01` |
| 44 | `monster/vehicle/lasercataani/chargedlaserfireeffect.ani` | 无法解析帧结构（3 帧，body 95 字节） | `tail_id=0xff80` |
