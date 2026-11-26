# NPK / IMG 语料独立校验报告

- 语料目录：`/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2`
- `.NPK` 文件数：**4730**（`os.listdir` 枚举，含前导空格文件名）
- 条目总数：**211,456**（全部索引项）
- 校验脚本：`tools/npk_corpus_verify.py`（纯 Python 标准库，**未 import** `tools/npk_parser.py`）
- 机器可读统计：`analysis/npk/verify/corpus-verify.json`
- 全量索引阶段耗时：20.7 s，只读 **53.5 MiB**（仅头+索引区，未读 27 GB 数据区）
- IMG 头扫描：31.1 s，读 6.5 MiB（211,456 个条目 × 32B pread）
- 帧记录抽样：1.4 s，读 39.3 MiB，300 个 .img（来自 161 个不同 NPK）

> 独立复核的含义：格式假设全部由本脚本逐字节重新推导/核对，反例给出实际字节；
> 与 `docs/NPK-FORMAT.md` 的对照见 §8。

## 0. 摘要（关键数字）

| 校验项 | 结果 |
| --- | --- |
| NPK magic `NeoplePack_Bill\0` | **4730/4730 (100.00%)** |
| 文件大小 == `20+n*264+32+Σsize` | **4727/4730 (99.94%)** |
| 文件大小 == `max(offset+size)` | **4728/4730 (99.96%)** |
| 条目总数 Σn | **211,456** |
| 每包条目数 n（min/median/max） | **1 / 6.0 / 3604** |
| 索引项 offset/size 合法率 | **211456/211456 (100.00%)** |
| 数据区完全连续（无空洞/重叠）的包 | **4729/4730 (99.98%)** |
| 文件名 XOR 解密可读率 | **211380/211456 (99.96%)** |
| 后缀分布 | `.img` **207,779** / `.ogg` **0** / 其他 **3,677** |
| SHA-256 通过率 | **4730/4730 (100.00%)** |
| 条目总数（全部后缀，含 .com/无后缀） | **211,456**（其中 `.img` 后缀 207,779） |
| IMG magic V2 `Neople Img File\0` | **211330/211456 (99.94%)**（211,330） |
| IMG magic V1 `Neople Image File\0`（旧版 18B） | **105/211456 (0.05%)**（105） |
| 16B 截断存根（size==16，非完整 IMG） | **21**（EOF 短读 10） |
| 广义 IMG 格式条目（V2 16B magic 含存根 + V1 18B magic） | **211456/211456 (100.00%)**（V2 magic 211,351 / V1 105 / 未知 0） |
| IMG version 分布（全部条目） | v2 **211,326** / v5 **4** / v1 **105** / v4 0 / v6 0 |
| `tableLength == frameCount*36`（V2/V5） | **198896/211330 (94.12%)** |
| 抽样 `tableLength == 帧记录区字节数`（36*fc-28*指向帧） | **195/195 (100.00%)** |
| IMG 头 zero 字段 == 0（V2） | **211330/211330 (100.00%)** |
| 抽样帧记录布局精确（记录+帧体==条目大小） | **195/195 (100.00%)** |
| 抽样帧总数 / 指向帧 | **25,907** / 148 |
| 抽样压缩帧 zlib 头 `0x78` | **23479/23479 (100.00%)** |
| 抽样 zlib 解压长度 == w*h*bpp | **549/549 (100.00%)** |
| 反例总数（各类合计，详见 §7） | **41** 条事件 |

## 1. NPK 容器层

### 1.1 magic 与头部

| 项目 | 结果 |
| --- | --- |
| magic 通过 | 4730/4730 (100.00%) |
| magic 失败（反例） | 0 |
| 头部/索引区读取异常 | 0 |
| n == 0 的空包 | 0 |

### 1.2 文件大小与索引区

| 项目 | 结果 |
| --- | --- |
| `size == 20+n*264+32+Σ(entry.size)` | 4727/4730 (99.94%) |
| `size == max(offset+size)` | 4728/4730 (99.96%) |
| 数据区起点紧贴校验位之后（head_gap==0） | 4730/4730 (100.00%) |
| 文件尾无多余字节（tail_slack==0） | 4728/4730 (99.96%) |
| 大小不一致反例 | 3 |

| 文件 | filesize | n | data_start | Σsize | 期望结束 | max(off+size) | Δ(Σ) | Δ(max) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `!                               九言QQ52656038!!!!.NPK` | 7119909 | 11 | 2956 | 7116915 | 7119871 | 7119871 | 38 | 38 |
| `!                              jiuyana!!!!!!.NPK` | 108178 | 1 | 316 | 107824 | 108140 | 108140 | 38 | 38 |
| `sprite_character_priest_atequipment_weapon_axe.npk` | 60688798 | 688 | 181684 | 60886908 | 61068592 | 60688798 | -379794 | 0 |

### 1.3 每包条目数 n

| 项目 | 数值 |
| --- | --- |
| 最小值 | 1 |
| 中位数 | 6.0 |
| 最大值 | 3604 |
| 总和 | 211,456 |

## 2. 索引项 (i32 offset, i32 size, 256B XOR 名)

| 校验 | 计数 |
| --- | --- |
| offset < 0 | 0 |
| size < 0 | 0 |
| offset < 索引区结束（数据区起点） | 0 |
| offset + size > filesize | 0 |
| 索引项本身非法（合计，去重前） | 0 |

**数据区连续性**（把每包条目按 offset 排序后检查相邻区间）：

| 项目 | 结果 |
| --- | --- |
| 完全连续（无空洞、无重叠） | 4729/4730 (99.98%) |
| 有空洞的包数 | 0 |
| 空洞总字节 | 0 |
| 有重叠的包数 | 1 |
| 索引表按 offset 升序的包 | 4730/4730 (100.00%) |

重叠反例（前 10）：

| 文件 | 条目# | 前区间结束 | 本条 offset | 重叠字节 |
| --- | --- | --- | --- | --- |
| `sprite_character_priest_atequipment_weapon_axe.npk` | 37 | 618229 | 608601 | 9628 |
| `sprite_character_priest_atequipment_weapon_axe.npk` | 176 | 7296905 | 7192353 | 104552 |
| `sprite_character_priest_atequipment_weapon_axe.npk` | 568 | 46960530 | 46823533 | 136997 |
| `sprite_character_priest_atequipment_weapon_axe.npk` | 570 | 47079191 | 46960530 | 118661 |
| `sprite_character_priest_atequipment_weapon_axe.npk` | 572 | 47089147 | 47079191 | 9956 |

## 3. 文件名 XOR 解密

密钥构造（独立推导，见 `make_name_key()`）：

```
key = b"puchikon@neople dungeon and fighter "  # 36B
      + b"DNF" * 73                          # 填充到第 255 字节
      + b"\0"                                # 第 256 字节 = 0
```

证据：用「base 周期重复」作密钥时，解密结果从第 36 字节起变成乱码；
用 DNF 填充后，全部名字可读；且索引项尾部填充区满足 `enc[i] == key[i]`（padding==0 的可观测证据，name_tail_padding_nonzero=0）。

| 项目 | 结果 |
| --- | --- |
| 解密后可读（ASCII 且带扩展名） | 211380/211456 (99.96%) |
| 不可读反例 | 76 |
| 含控制/非 ASCII 字节 | 73 |
| 空名字 | 0 |
| 需要 trim 的名字 | 0 |
| 最长名字 | 133 B |
| 同包重名 | 11 个包 |
| 备选密钥「base 周期重复」可读条目 | 685/19132 (3.58%)（应远小于上者 → 反证） |
| 备选密钥「DNF 填充但末位非 0」可读条目 | 19127/19132 (99.97%)（与正确密钥仅差第 256 字节，故同率；见 §3.1） |

后缀分布（解密后）：

| 后缀 | 数量 |
| --- | --- |
| `.img` | 207,779 |
| `.com` | 3,601 |
| `<无扩展名>` | 75 |
| `.zmg` | 1 |

文件名反例（前 10）：

| 文件 | 条目# | 原因 | 解密字节 |
| --- | --- | --- | --- |
| `!                                                         !sprite_cs_shop积分商城补丁.NPK` | 1 | no-extension | `31 37 30 38 30 32 36` |
| `!!!积分商城补丁.NPK` | 1 | no-extension | `31 37 30 38 30 32 36` |
| `!!蝴蝶之舞礼包.NPK` | 4 | control/non-ascii 0xb1 | `2d 2d 2d 2d b1 d5 d4 c2 b1 d5 d4 c2 b1 d5 d4 c2 2d 2d 2d 2d 2d 2d 2d 2d` |
| `!!蝴蝶之舞礼包.NPK` | 28 | control/non-ascii 0xa1 | `a1 ef a1 ef a1 ef a1 ef a1 ef a1 be 31 a1 bf a1 ef a1 ef a1 ef a1 ef a1 ef` |
| `!!蝴蝶之舞礼包.NPK` | 52 | control/non-ascii 0xa1 | `a1 ef a1 ef a1 ef a1 ef a1 ef a1 be 32 a1 bf a1 ef a1 ef a1 ef a1 ef a1 ef` |
| `!!蝴蝶之舞礼包.NPK` | 76 | control/non-ascii 0xa1 | `a1 ef a1 ef a1 ef a1 ef a1 ef a1 be 33 a1 bf a1 ef a1 ef a1 ef a1 ef a1 ef` |
| `!!蝴蝶之舞礼包.NPK` | 100 | control/non-ascii 0xa1 | `a1 ef a1 ef a1 ef a1 ef a1 ef a1 be 34 a1 bf a1 ef a1 ef a1 ef a1 ef a1 ef` |
| `!!蝴蝶之舞礼包.NPK` | 124 | control/non-ascii 0xa1 | `a1 ef a1 ef a1 ef a1 ef a1 ef a1 be 35 a1 bf a1 ef a1 ef a1 ef a1 ef a1 ef` |
| `!!蝴蝶之舞礼包.NPK` | 145 | control/non-ascii 0xa1 | `a1 ef a1 ef a1 ef a1 ef a1 ef a1 be 36 a1 bf a1 ef a1 ef a1 ef a1 ef a1 ef` |
| `!!蝴蝶之舞礼包.NPK` | 166 | control/non-ascii 0xa1 | `a1 ef a1 ef a1 ef a1 ef a1 ef a1 be 37 a1 bf a1 ef a1 ef a1 ef a1 ef a1 ef` |

同包重名反例（前 5）：

| 文件 | n | 重名条目数 | 例子 |
| --- | --- | --- | --- |
| `!            跨界继承.NPK` | 22 | 11 | `sprite/interface2/ui/newitemtool/newitemtool.img`×2; `sprite/interface2/itemtoolwindow/item_carving_succession/carving.img`×2; `sprite/interface2/itemtoolwindow/item_carving_succession/carving_cn.img`×2; `sprite/interface2/itemtoolwindow/item_carving_succession/effect01.img`×2; `sprite/interface2/itemtoolwindow/item_carving_succession/effect02.img`×2 |
| `!    武器.NPK` | 355 | 8 | `sprite/character/gunner/atequipment/weapon/hcan/gg_hcan0093b.img`×2; `sprite/character/swordman/atequipment/weapon/katana/sg_katana0093a.img`×2; `sprite/character/swordman/atequipment/weapon/katana/sg_katana0033a.img`×2; `sprite/character/swordman/atequipment/weapon/katana/sg_katana0033b.img`×2; `sprite/character/swordman/atequipment/weapon/katana/sg_katana0061a.img`×2 |
| `!    皮肤.NPK` | 192 | 10 | `sprite/character/swordman/equipment/avatar/skin/sm_body81292.img`×2; `sprite/character/fighter/equipment/avatar/skin/ft_body81292.img`×2; `sprite/character/gunner/equipment/avatar/skin/gn_body81292.img`×2; `sprite/character/gunner/atequipment/avatar/skin/gg_body81292.img`×2; `sprite/character/mage/atequipment/avatar/skin/mm_body81292.img`×2 |
| `!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!sprite_character_mage_equipment_weapon_spear.npk` | 807 | 82 | `sprite/character/mage/equipment/weapon/spear/(tn)mg_spear1101c.img`×2; `sprite/character/mage/equipment/weapon/spear/(tn)mg_spear1102c.img`×2; `sprite/character/mage/equipment/weapon/spear/(tn)mg_spear1101d.img`×2; `sprite/character/mage/equipment/weapon/spear/(tn)mg_spear1102d.img`×2; `sprite/character/mage/equipment/weapon/spear/(tn)mg_spear1401c.img`×2 |
| `1A冥灵之塔补丁.NPK` | 584 | 1 | `sprite/monster/flyingmonstermark.img`×2 |

## 4. SHA-256 校验

**范围（独立复核结论）**：对文件开头 `prefix = 20 + n*264` 字节取前 `(prefix // 17) * 17` 字节做 SHA-256，与索引表后的 32B 比对。

| 项目 | 结果 |
| --- | --- |
| 校验通过 | **4730/4730 (100.00%)**（覆盖全部 4730 个包，不是抽样） |
| 校验失败 | 0 |

> 说明：任务书建议「大包只抽样」。实测发现校验范围只到 header+index（每包 ≤ 数 MB，
> 全语料合计仅 53.5 MiB 读取），因此**全量 4730 个都做了校验**，
> 比抽样更强。大包的数据区一个字节都没读。

## 5. IMG 头层（全部 211,456 个索引条目）

| 项目 | 结果 |
| --- | --- |
| 条目总数 | 211,456（`.img` 207,779 / 非 `.img` 3,677） |
| V2 magic `Neople Img File\0` | 211,330（211330/211456 (99.94%)；另有 21 个 16B 存根前 16B 也命中 V2 magic，单列下行） |
| V1 magic `Neople Image File\0` | 105（105/211456 (0.05%)） |
| V2 16B magic 命中（含存根） | 211,351（211351/211456 (99.95%)） |
| 广义 IMG 格式（V2 含存根 + V1） | 211,456（211456/211456 (100.00%)） |
| 未知 magic | 0 |
| 16B 截断存根（size==16） | 21（其中 EOF 短读 10） |
| zero 字段 == 0（V2 非存根） | 211330/211330 (100.00%) |
| frameCount > 0（V2/V5；fc==0 为空帧 img，单列如下） | 211311/211330 (99.99%) |
| fc==0 的空帧 img（32B，仅头，结构合法） | 19 |
| frameCount 合计（V2/V5 有效） | 28,775,245 |
| frameCount 合计（V2/V5 含坏头，存根除外） | 28,775,245 |
| frameCount 合计（V1） | 2,454 |
| frameCount min/median/max | 1 / 174 / 10000 |
| `tableLength == frameCount*36`（V2/V5） | 198896/211330 (94.12%) |

版本分布：

| version | 数量 | 占比 |
| --- | --- | --- |
| v2 | 211,326 | 99.939% |
| v5 | 4 | 0.002% |
| v1 | 105 | 0.050% |
| v4 | 0 | 0.000% |
| v6 | 0 | 0.000% |

`tableLength` 取值 Top 10（值 → 条目数）：

| tableLength | 数量 |
| --- | --- |
| 5796 | 23,461 |
| 6516 | 20,611 |
| 8712 | 15,186 |
| 7740 | 14,841 |
| 6264 | 13,084 |
| 5148 | 11,050 |
| 7092 | 10,363 |
| 6336 | 10,250 |
| 8856 | 8,864 |
| 36 | 7,912 |

`tableLength != frameCount*36` 反例（前 10，通常是含 0x11 指向帧的 img —— 指向帧记录只有 8B，所以 `tl < fc*36`）：

| 文件 | img | tableLength | frameCount | fc*36 | 版本 |
| --- | --- | --- | --- | --- | --- |
| `!                                                                                          login_1.NPK` | `sprite/interface/newresult/pcroompremiumreward.img` | 116 | 4 | 144 | v2 |
| `!                                                                                          login_1.NPK` | `sprite/interface2/hud/information_button/informati` | 39652 | 1138 | 40968 | v2 |
| `!                                                                                         login_1.NPK` | `sprite/interface/newresult/pcroompremiumreward.img` | 116 | 4 | 144 | v2 |
| `!                                                                                         login_1.NPK` | `sprite/interface2/hud/information_button/informati` | 39652 | 1138 | 40968 | v2 |
| `!                                                                             sprite_common_digit_tp.NPK` | `sprite/common/digit/red_systemfont.img` | 704 | 11 | 396 | v5 |
| `!                                                       sprite_common_digit_tp.NPK` | `red_systemfont.img` | 704 | 11 | 396 | v5 |
| `!                               九言QQ52656038!!!!.NPK` | `sprite/jiuyana/diy1.img` | 686 | 8 | 288 | v2 |
| `!                               九言QQ52656038!!!!.NPK` | `sprite/jiuyana/diy2.img` | 686 | 8 | 288 | v2 |
| `!                               九言QQ52656038!!!!.NPK` | `sprite/jiuyana/diy3.img` | 686 | 8 | 288 | v2 |
| `!                               九言QQ52656038!!!!.NPK` | `sprite/jiuyana/diy4.img` | 686 | 8 | 288 | v2 |

**`tableLength` 语义（本次独立结论）**：全量上 `tableLength == frameCount*36` 只占 94.12%，差值恰好来自 0x11 指向帧（记录只有 8B，比 36B 少 28B）。抽样逐条核对：`tableLength == 36*frameCount - 28*指向帧数` 的比例为 **191/195 (97.95%)**（v2 单独：191/191 (100.00%)）。⇒ **tableLength = 帧记录区字节数（不含 32B IMG 头）**，不是固定 `frameCount*36`。全量比例用 `tl_checked=211330` 作分母为 94.12%。

frameCount == 0 的空帧 img（前 10，32B 条目、结构合法，仅列出供参考）：

| 文件 | img | frameCount | version | entry size |
| --- | --- | --- | --- | --- |
| `!                                                         !sprite_cs_shop积分商城补丁.NPK` | `1708026` | 0 | v2 | 32 |
| `!                         321220081（1）.NPK` | `sprite/common/commoneffect/dust/dust02.img` | 0 | v2 | 32 |
| `!                         321220081（1）.NPK` | `sprite/monster/collosseumofempire/morphling/effect` | 0 | v2 | 32 |
| `!                         321220081（1）.NPK` | `sprite/monster/collosseumofempire/morphling/effect` | 0 | v2 | 32 |
| `!                         321220081（1）.NPK` | `sprite/monster/collosseumofempire/morphling/effect` | 0 | v2 | 32 |
| `!!!积分商城补丁.NPK` | `1708026` | 0 | v2 | 32 |
| `!!蝴蝶之舞礼包.NPK` | `----������������--------` | 0 | v2 | 32 |
| `!!蝴蝶之舞礼包.NPK` | `��������` | 0 | v2 | 32 |
| `!!蝴蝶之舞礼包.NPK` | `������������` | 0 | v2 | 32 |
| `!!蝴蝶之舞礼包.NPK` | `��������` | 0 | v2 | 32 |

### 5.1 旧版 V1 magic（105 个条目，全部 version=1）

语料中存在第二种 IMG magic：`Neople Image File\0`（18 字节 = 17 字符 + NUL）。其头部布局与 V2 不同：magic 18B + 2B 填充 + u32 zero@20 + u32 version@24 + u32 frameCount@28，**没有 tableLength 字段**（按 V2 从 @16 读出的 101 恰是 magic 尾部 `e\0\0\0` 的重叠解读）；帧数据从 @32 开始，并且是 **记录/帧体交替排列**：每帧 = [36B 记录][压缩帧体]，不是独立记录表。

**口径说明**：3,601 个 `.com`、75 个无扩展名、1 个 `.zmg` 条目，头部同样命中 V2 IMG magic（version=2）——它们本质是 IMG 数据、只是扩展名写错。因此 §5 分母改用全部索引条目，不再只用 `.img` 后缀条目（原口径 207,779 会使 magic 通过率被低估为 207,664/207,779）。

## 6. 帧记录抽样（300 个 .img）

抽样方法：从全部 .img 条目中随机抽 300 个（seed=20261104），限制每个 NPK 最多 2 个、条目 ≤2MB；**所有 v4/v5/v6 及旧版 v1 条目强制纳入**。

| 项目 | 结果 |
| --- | --- |
| 样本数（不同 NPK 数） | 300（161） |
| 解析成功 / 失败 | 287 / 13 |
| 版本分布 | {'1': 105, '2': 191, '5': 4} |
| 帧总数 | 25,907 |
| 指向帧 (0x11) | 148 |
| **布局精确**（记录区 + Σ帧体 + ΣDDS == 条目大小） | **195/195 (100.00%)** |
| 布局不匹配 | 0 |
| 压缩帧 zlib 头 0x78 | 23479/23479 (100.00%) |
| zlib 解压长度 == w*h*bpp（每个 img 最多核 3 帧） | 549/549 (100.00%) |
| `tableLength == 帧记录区字节数` | 195/195 (100.00%) |
| `tableLength == 36*fc - 28*指向帧` | 191/195 (97.95%) |
| 未压缩帧 length != w*h*bpp | 0（已知历史脏数据） |
| 帧几何非法 | 0 |
| 指向帧 linkTo 越界 | 0 |

帧 type 分布（抽样）：

| type | 数量 | 含义 |
| --- | --- | --- |
| `0x10` | 23,554 | ARGB8888 0x10 |
| `0x0E` | 345 | ARGB1555/INDEXED 0x0E |
| `0x12` | 212 | FXT1/DXT1 0x12 |
| `0x11` | 148 | REFERENCE 0x11 |

压缩标志分布（非指向帧）：

| compressed | 数量 | 含义 |
| --- | --- | --- |
| `0x06` | 23,479 | 0x06 zlib |
| `0x05` | 350 | 0x05 未压缩 |
| `0x07` | 282 | 0x07 像素在 v5 DDS 表 |

解析失败反例（前 10）：

| 文件 | img | 版本 | frameCount | 错误 | 头部字节 |
| --- | --- | --- | --- | --- | --- |
| `1021皮肤↓↓↓↓↓↓↓↓↓↓.NPK` | `sprite/character/swordman/equipment/avatar/sk` | v1 | 2 | bad record at frame 2, pos=13973, type=186 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 f2 00 00 00 10 00 00 00 06 00 00 00 c8 00 00 00 c8 00 00 00 ...` |
| `1021皮肤↓↓↓↓↓↓↓↓↓↓.NPK` | `sprite/character/swordman/equipment/avatar/sk` | v1 | 2 | bad record at frame 2, pos=23819, type=135 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 f2 00 00 00 10 00 00 00 06 00 00 00 bd 00 00 00 bd 00 00 00 ...` |
| `sprite_common_etc.NPK` | `sprite/common/etc/auramaster.img` | v1 | 1 | record truncated at frame 1, pos=72 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 04 00 00 00 0e 00 00 00 05 00 00 00 01 00 00 00 01 00 00 00 ...` |
| `sprite_common_etc.NPK` | `sprite/common/etc/genie_effect.img` | v1 | 9 | bad record at frame 9, pos=205060, type=393216 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 15 00 00 00 10 00 00 00 06 00 00 00 a5 00 00 00 a4 00 00 00 ...` |
| `sprite_common_etc.NPK` | `sprite/common/etc/castinggage.img` | v1 | 4 | bad record at frame 4, pos=344, type=115 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 0a 00 00 00 0e 00 00 00 06 00 00 00 34 00 00 00 04 00 00 00 ...` |
| `sprite_common_hiteffect.NPK` | `sprite/common/hiteffect/darkhit1.img` | v1 | 5 | bad record at frame 5, pos=11404, type=393216 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 06 00 00 00 10 00 00 00 06 00 00 00 27 00 00 00 29 00 00 00 ...` |
| `sprite_common_hiteffect.NPK` | `sprite/common/hiteffect/darkhit2.img` | v1 | 2 | bad record at frame 2, pos=281, type=393216 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 06 00 00 00 0f 00 00 00 06 00 00 00 16 00 00 00 17 00 00 00 ...` |
| `sprite_common_hiteffect.NPK` | `sprite/common/hiteffect/icesplinter3.img` | v1 | 2 | bad record at frame 2, pos=600, type=806580553 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 11 00 00 00 0f 00 00 00 06 00 00 00 11 00 00 00 15 00 00 00 ...` |
| `sprite_common_hiteffect.NPK` | `sprite/common/hiteffect/lighthit1.img` | v1 | 5 | bad record at frame 5, pos=7527, type=393216 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 06 00 00 00 10 00 00 00 06 00 00 00 20 00 00 00 21 00 00 00 ...` |
| `sprite_common_hiteffect.NPK` | `sprite/common/hiteffect/prsummer3.img` | v1 | 2 | bad record at frame 2, pos=600, type=806580553 | `4e 65 6f 70 6c 65 20 49 6d 61 67 65 20 46 69 6c 65 00 00 00 00 00 00 00 01 00 00 00 11 00 00 00 0f 00 00 00 06 00 00 00 11 00 00 00 15 00 00 00 ...` |

### 6.2 旧版 v1 条目（记录/帧体交替布局）

- 强制纳入 v1 条目：解析成功 **92** / 失败 13
- 记录/帧体交替布局字节精确：**88** / 不匹配 4
- v1 帧类型：`0x10`×772，`0x0E`×642，`0x0F`×234；压缩方式：`0x06`×1644，`0x05`×4

### 6.1 v5 条目逐字段核对（全量 4 个）

- `!                                                                             sprite_common_digit_tp.NPK` → `sprite/common/digit/red_systemfont.img`：size=2817, frameCount=11, tableLength=704, ddsCount=11, colorNum=0, imgLength=2817, DDS 压缩字节=1761, 布局精确=True Δ=0
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 14, 0, 33, 140, 7, 10)
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 14, 1, 27, 100, 5, 10)
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 14, 2, 38, 140, 7, 10)
- `!                                                       sprite_common_digit_tp.NPK` → `red_systemfont.img`：size=2817, frameCount=11, tableLength=704, ddsCount=11, colorNum=0, imgLength=2817, DDS 压缩字节=1761, 布局精确=True Δ=0
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 14, 0, 33, 140, 7, 10)
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 14, 1, 27, 100, 5, 10)
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 14, 2, 38, 140, 7, 10)
- `!   sprite_interface2_raid.NPK` → `sprite/interface2/raid/raid_channel_cn.img`：size=211408, frameCount=69, tableLength=3828, ddsCount=1, colorNum=0, imgLength=211408, DDS 压缩字节=135786, 布局精确=True Δ=0
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 16, 0, 135786, 278528, 544, 128)
- `1A冥灵之塔补丁.NPK` → `sprite/monster/ch_monsterface.img`：size=76960, frameCount=235, tableLength=14396, ddsCount=4, colorNum=0, imgLength=76960, DDS 压缩字节=52746, 布局精确=True Δ=0
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 18, 0, 51727, 60608, 504, 240)
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 18, 1, 327, 8320, 128, 128)
  - DDS rec `(title,pf,index,fullLength,length,w,h)=`(1, 18, 2, 345, 416, 24, 24)

## 7. 反例清单（汇总）

| 类别 | 数量 | 位置 |
| --- | --- | --- |
| NPK magic 不符 | 0 | §1.1 |
| 头部/索引区读取异常 | 0 | §1.1 |
| 文件大小不一致 | 3 | §1.2 |
| 索引项非法 | 0 | §2 |
| 数据区空洞包 | 0 | §2 |
| 数据区重叠包 | 1 | §2 |
| 文件名不可读 | 76 | §3 |
| SHA-256 校验失败 | 0 | §4 |
| IMG magic 不符（未知 magic） | 0 | §5 |
| 16B 截断存根（size==16） | 21 | §5 |
| 旧版 v1 抽样布局不匹配 | 4 | §6 |
| IMG zero 字段非 0 | 0 | §5 |
| fc==0 空帧 img（32B 仅头，结构合法，仅参考） | 19 | §5 |
| 抽样布局不匹配 | 0 | §6 |
| 抽样解析失败 | 13 | §6 |
| 抽样未压缩帧 length 与几何不符 | 0 | §6 |

## 8. 与 `docs/NPK-FORMAT.md` 的对照

| 文档结论 | 本次独立复核 | 判定 |
| --- | --- | --- |
| 4,730 个 .NPK | 4730 | 一致 |
| 条目总数 211,456 | 211,456 | 一致 |
| magic / size / 条目数全部通过、坏包 0 | magic 4730/4730，size 全等 4727/4730，异常头 0 | 基本一致 |
| 索引项 264B、offset/size 语义 | 合法率 100.0000% | 一致 |
| 文件名密钥 base + DNF 填充、末位 \0 | 名字可读率 99.964% | 一致（并给出可观测证据） |
| SHA-256 范围 = 头+索引 前 len/17*17 | 通过 4730/4730 | 一致（全量验证） |
| v2 207,622 / v5 4 / v4=v6=0（.img 口径） | `.img`: v2 207,649 / v5 4 / v1 105；全部条目: v2 211,326 / v5 4 / v1 105 | 一致（v2 差额 = 3,677 个非 `.img` 后缀条目；v1 是文档未记录的旧版 magic） |
| 帧总数约 2,878 万 | V2/V5 有效 28,775,245 + V1 2,454 = **28,777,699** | 一致（≈2,878 万） |
| `tableLength` 恒为记录区长度（待验证） | **tableLength = 36*fc - 28*指向帧数**（抽样核对率 97.95%，全量 `==fc*36` 为 94.12%） | **确认文档猜测**，并给出精确公式 |
| 帧记录 36B / 指向帧 8B / v5 共享 64B | 抽样布局精确 100.00% | 一致（v2 按 type==0x11 走 8B 才能字节对齐） |
| 未压缩帧 length 不可信（语料脏数据） | 抽样命中 0 帧 | 一致（独立复现） |
| 压缩帧 0x06 以 zlib 头 0x78 开头 | 100.00% | 一致 |
| 同包重名（worldmap 等） | 11 个包重名 | 一致（见 §3） |

## 9. 局限与未验证项

- 帧像素解码（ARGB/BGRA 通道序、DXT 解压）不在本任务范围；本脚本只核记录层与布局。
- v5 的 64B 分流规则在 4 个样本上按文档假设验证；样本极少，不等于强结论。
- `tableLength` 的精确语义（是否等于记录区字节数、是否含 32B 头）由全量统计与布局对齐推断，未找到官方文档。
- 文件名密钥第 256 字节不可观测（名字最长 133B，填充区全 0），只能证明前 255 字节；末位 \0 与参考实现一致。
- zlib 解压长度只核了每个 img 最多 3 帧（549/549 通过），未逐帧全解压；内容正确性（像素）不在范围。
- 旧版 v1（105 个）：92 个可解析、其中 88 个记录/帧体交替布局字节精确；13 个解析失败 + 4 个布局不匹配
  仍未定位（多为含截断帧/指向帧的脏数据，或 v1 的 0x11 指向帧记录形式与 36B 假设不符）。

复现命令：

```bash
python3 tools/npk_corpus_verify.py --stage all
```

*报告生成时间：2026-11-04 20:03:53*
