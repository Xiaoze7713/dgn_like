# 12 · 首切片抽验与 R13 裁定

> captain 对 `analysis/10-SLICE.md` 的独立复核：把里面写的 id 拿去 `export/_meta/index.sqlite`、`.lst` 注册表、`export/structured/*.jsonl.gz` 里逐个对，不采信「文档说存在」。
> 结论：**12/12 抽验项全部命中**；但 **R13（dgn6 boss 房）的处置建议是错的**，改用坐标 + 房内怪物判定，见 §2。

---

## 1. 抽验清单（全部实测）

| # | 文档声称 | 实测 | 结论 |
|---|---|---|---|
| 1 | 起始城镇 `town.lst`=1 → `town/1_new/new_Elvengard.twn` | `export/_meta/lst/town__town.lst.tsv: 1 → 1_new/new_Elvengard.twn` | ✅ |
| 2 | 副本 dgn 1 = `dungeon/act1/lorien.dgn` | `dungeon__dungeon.lst.tsv: 1 → act1/lorien.dgn` | ✅ |
| 3 | dgn 4 = `act1/mirkwooddeep.dgn` | 同名注册表命中 | ✅ |
| 4 | dgn 6 = `act1/sunderlandpoison.dgn` | 同名注册表命中 | ✅ |
| 5 | 怪 1/12/5001 | `monster.lst: 1→goblin/goblin.mob、12→tau/taubeast.mob、5001→lugaru/lugaru.mob` | ✅ |
| 6 | 太刀 27600 | `kat_damaged.equ` | ✅ |
| 7 | 上衣 10000 | `character/common/jacket/cloth/sht_ragcloth.equ` | ✅ |
| 8 | 腰带 16400 | `character/common/belt/leather/str_crleather.equ` | ✅ |
| 9 | 短裤 12401 | `character/common/pants/leather/pant_wleather.equ` | ✅ |
| 10 | NPC 1 / 2 = 林納斯 / 賽麗亞 | `npc.lst: 1→1_new/linus.npc、2→Seria.npc` | ✅ |
| 11 | `character/exptable.tbl`、`etc/sptable.etc`、`itemshop/equipmentshop1.shp`、`worldmap/lorien.wdm` 存在 | `index.sqlite` 各 1 条 | ✅ |
| 12 | 鬼剑士 Lv1–20 可用技能（文档说 20 个） | `skill/swordman/*.skl` 共 278 个；Lv1–20 取 `[required level]≤20` 后落在 20–22 个量级 | ⚠️ 数量口径需注明是「按 required level 筛过」 |

**附带实测**：`character/swordman/` 子树里 `ani` 188,291 个、`als` 9,400 个、`equ` 12,895 个、`lay` 1 个（`equipment/character/swordman.lay`）——「一个角色 18 万动画帧文件」这个量级要在引擎侧提前设计（见 `docs/GODOT-EVAL.md` 条件 C1）。

---

## 2. R13 裁定：boss 房不能靠 `[type][boss]`

`10-SLICE.md` R13 说 dgn6 的 `[boss map] [2,0,4,1]` 与 `[map specification]` 对不上，建议「实现时优先判 `[type][boss]`」。**这条照做会把 act1 的 boss 全部弄丢。**

实测：

```
dungeon/act1/sunderlandpoison.dgn
  [size] [2, 3]?  → 实为 [2,0]=827/853/859/860、[4,1]=877 两组候选
  [boss map] [2, 0, 4, 1]        ← 两组坐标：(col 2,row 0) 和 (col 4,row 1)
  [map specification]-2 [2, 0, 827, 853, 859, 860]
  [map specification]-7 [4, 1, 877]
```

把这 11 个候选房间的 `.map [type]` 全查了：**全部 `[normal]`，且 `[map name]` 全是被复用成占位名的 `PVP無名`**。同理 `map/lorien/4..9.map`（dgn1 的 6 个房间）也全是 `[normal]` + `PVP無名`。全库 `[type][boss]` 只有 684 个，全在 act2 之后的新副本里。

→ 对 act1 这批老副本，`[type]` 与 `[map name]` 都是**遗留占位**，不承载玩法语义。

**boss 靠什么识别？靠 boss 格里刷的怪。** 实测 dgn6 `[boss map]` 的 (4,1) 格（`map/sunderlandpoison/h832(4,3).map`）房里 18 条 `[monster]` 记录里有 **12 → `tau/taubeast.mob`（牛頭巨獸）**；dgn6 的另一格 `827.map` 里是 lugaru 三兄弟。dgn1 的 (0,2)=(8.map) 里是 goblin。

**实现口径（替换 R13）**：
1. 房间集合 = `[map specification]` 每格候选集随机取一（无 spec 的老 dgn 用同目录 `.map` 约定，见 §3）。
2. **boss 房 = `[boss map]` 的坐标对**（成对读，`[2,0,4,1]` 是 2 个格子不是 1 个），不要按 `[type]` 筛。
3. boss 实体 = 该房 `[monster]` 里等级/HP 最高的那只（dgn6 = tau 12），从 `.mob` 取数即可；`[type][boss]` 只在 act2+ 的副本里当提示用。

---

## 3. 顺手发现的第二种房间分配机制（老副本）

`dungeon/act1/lorien.dgn` **完全没有 `[map specification]`**，只有：
```
[size] [2, 3]      [greed] 'JJEE / LLMM / DDGG'      [start map] [0,0]   [boss map] [0,2]
```
而 `map/lorien/` 下正好 6 个 `4.map … 9.map`，匹配 2×3=6 格。

两种可能：(a) 按 map id 递增铺格；(b) 按文件名里的 `(col,row)` 后缀（新副本如 `n802(1,0).map`、`h832(4,3).map` 就是这种命名）——这解释了为什么新副本的 `.map` 文件名带坐标而老的不是。

→ **实现建议**：优先用 `[map specification]`；缺失时回退「`.map` 文件名里的 `(col,row)`」，再缺失才按 id 递增。这条要写进切片实现说明，否则 dgn1 会退化成随机房。

---

## 4. 与 R2 的关系

怪物基表 11 列语义仍未定（已派 t10 给 design-analyst 做了）。§2 里「boss = 等级/HP 最高」这条判据依赖基表列语义，暂时按「怪物 id 大 / 房内唯一出现在 boss 格的 tau 族」这种人肉判断，等 t10 出结论再换成数值判据。

---

## 追加核验（captain，t10 之后）

### A. 房间 id 不是文件名 —— 必须过 `map.lst`
`dungeon/act1/sunderlandpoison.dgn` 的 `[map specification]` 里写的 852/853/856/859/860/861/862/863/864/865/866/867/872/873/875/876/877 这些**数字房间 id，在 `map/sunderlandpoison/` 下没有同名文件**。全部要经 `map/map.lst` 反查：

| 房间 id | 真实文件 |
|---|---|
| 827 | `sunderlandpoison/827.map` |
| 852 | `sunderlandpoison/e817(1,2).map` |
| 853 | `sunderlandpoison/n802(1,0).map` |
| 856 | `sunderlandpoison/n806(3,0).map` |
| 859 | `sunderlandpoison/n809(2,1).map` |
| 860 | `sunderlandpoison/n816(0,2).map` |
| 861 | `sunderlandpoison/n818(1,2).map` |
| 862 | `sunderlandpoison/n819(1,3).map` |
| 863 | `sunderlandpoison/n820(1,3).map` |
| 864 | `sunderlandpoison/n821(2,3).map` |
| 865 | `sunderlandpoison/n822(2,3).map` |
| 866 | `sunderlandpoison/n823(3,3).map` |
| 867 | `sunderlandpoison/n824(3,3).map` |
| 872 | `sunderlandpoison/h825(3,2).map` |
| 873 | `sunderlandpoison/h826(3,2).map` |
| 875 | `sunderlandpoison/h829(4,2).map` |
| 876 | `sunderlandpoison/h830(4,2).map` |
| 877 | `sunderlandpoison/h832(4,3).map` |

**实现红线：地图加载器必须先建 `map.lst` 的 `id → path` 表，再读 `[map specification]` 里的数字；把数字当文件名会 0/18 命中。** 同理 `[start map]`/`[boss map]` 也走这张表。

### B. dgn6 的真实房间集合（`[map specification]` 逐格）
`[size] [5,2]`，共 8 格 + 起点，`[greed]` = `BBMMBBNNMM` / ` AADDFFGGCC`：

| 格 | 候选房间 id |
|---|---|
| (1,0) | 852, 856, 861 |
| (1,1) | 862, 863, 840 |
| (2,0) | 827, 853, 859, 860 |
| (2,1) | 845, 854, 865, 864 |
| (3,0) | 828, 872, 873, 837 |
| (3,1) | 867, 866 |
| (4,0) | 876, 875 |
| (4,1) | 877 |

`[start map] [0,0]`、`[boss map] [2,0,4,1]` → **boss 房是 (2,0) 与 (4,1) 两格**，候选 = {827, 853, 859, 860} ∪ {877}。

### C. boss 实体核实（**已修正**：tau 不只出现在 877）
先记一条教训：我第一次只 grep 了 `827`，看到里面没有 tau 就下了「只有 877 有 tau」的结论，**这是错的** —— `853`、`860` 里也各有 1 只 `12`。设计组逐房读 `[monster]` 后纠正了我，下表按实测重写。

| 房间 id | 文件 | 怪物构成 | lugaru 精英数 |
|---|---|---|---|
| 827 | `sunderlandpoison/827.map` | 清一色 lugaru 5001/5002/5003 | **8** |
| 859 | `n809(2,1).map` | lugaru + 哥布林 + 1 只 12 | 4 |
| 877 | `h832(4,3).map` | lugaru 精英 + 1 只 12（与精英混编） | 4 |
| 860 | `n816(0,2).map` | lugaru + 哥布林 + 1 只 12 | 1 |
| 853 | `n802(1,0).map` | 哥布林为主 + 1 只 12 | 0 |

结论（两句并列，别只写一句）：
- **要 tau（牛頭巨獸）当 boss → 选 877**（唯一 tau 与 lugaru 精英混编，打起来最有 boss 房样）。
- **要满编精英（更耐打、更像 boss 房）→ 827**（8 只全 lugaru 精英、0 哥布林）。
- 实现口径：boss 房 = `[boss map]` 坐标对；房内 boss 实体按「优先带 tau，否则精英数最多」选，**不读 `[type]`**。

### D. `878 = b813(5,1).map` 疑似越界
`dgn6 [size]` = `[5,2]` → 列 0..4、行 0..1，而 `b813(5,1)` 的列号 5 在网格外；该房含 5004 毒貓王（`[type][boss]`）。疑为 act2 复用遗留。同理 `b801/b802/b827/b831` 一组不在 dgn6 的 `[map specification]` 候选里，切片不用。
