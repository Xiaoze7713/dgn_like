# sf85（老牛 85 版）PVF 体检 + UTF-8 转码报告

日期：2026-11-13　工具：`tools/pvf_string_census.py` / `tools/pvf_to_utf8.py`

## 一句话

**85 包是干净的**（0 条坏串），已经整体转成 UTF-8：`build/sf85.Script.utf8.pvf`
（209,076,192 B，比源 +3.4 MB），Godot 里 `PvfLoader` 直接读出中文，不需要任何编码库。

## 1. 源包

| 项 | 值 |
|---|---|
| 路径 | `/mnt/e/dnf-sf/sf85/老牛DNF客户端/Script.pvf` |
| 大小 | 205,695,984 B（196 MB） |
| file_version | 66282（≠ 110 版的 53579） |
| sizeGUID / GUID | 36 / `fa08bf71-4395-6a4b-a3e3-2617c9fee116`（与 110 版同一个 GUID） |
| 条目数 | 370,666 |
| 目录树 | 30,466,556 B |
| 字符串 | 461,796 条 / 12,784,249 B |
| 明文总量 | 178,050,749 B |

后缀 top10：`.ani 209,635 / .equ 67,777 / .act 26,136 / .stk 10,402 / .ai 8,608 /
.obj 8,034 / .atk 7,913 / .key 5,884 / .ptl 5,243 / .til 3,833`

## 2. 体检（census）

```
非 ASCII 字符串 42,698
  big5hkscs   28,138   ← 主体是繁体中文（这是台服/繁体底包）
  cp949       14,082   ← 韩文原版资源
  gb18030        329
  shift_jis      133   ← 日文活动文本
  utf-8           16
真正坏串（私用区/扩展A/兼容字模）  0 条     ← 和 110 版最大的区别
目录树非 ASCII 路径                5 条（全部 CP949 韩文，已还原）
```

对比 110 版：110 有 **702 条硬坏串 + 476,800–488,200 那一片乱码带**，
85 一条都没有 —— 印证了「110 是玩家 DIY 改过的包，编辑不规范」。

那 5 条路径（与 110 里出现的同族文件）：

```
equipment/character/priest/헤지호그.txt          (hedgehog 刺猬)
equipment/character/mage/빙류환.txt             (冰流环)
stackable/cash/tarot_ani/연출설명.txt           (演出说明)
monster/newmonsters/new_event/dual/dual_face/action/사본 - proc.act
monster/newmonsters/new_event/dual/dual_face/action/사본 - proc1.act
```

## 3. 转码：这次多修了两件事

### 3.1 显示名根本不在 `stringtable` 里

`acoat_default.equ` 的 `[name]` 解析出来是 `基本上衣`，但翻遍 `stringtable`
的 461,796 条都找不到这条 —— 因为它走的是**另一张表**：

```
.equ  [name] → 记录类型 0x0A (STR_LINK) → 下标指向 `name_40600`
                                    ↓
              n_string.lst  →  *.kor.str   （84 个 key>value 文本表）
                                    ↓
              equipment/equipment.kor.str : `name_40600>基本上衣`
```

所以只转 `stringtable` 会得到「路径对了、名字还是乱码」。本次新增第 3 类改写：
**`*.str` / `*.txt` 纯文本文件整体转码**（先按行抽样投票定编码，再逐行解，
解不开的行保留原文；结果必须整体是合法 UTF-8，否则放弃该文件）。

- 85 包：**44 个文件 / 155,955 行**改写
- 判定为「非文本」而跳过的：`.lst`（多为二进制记录，含 NUL），已排除

### 3.2 4 字节对齐的坑（尾巴变垃圾）

PVF 的文件体是「补足 4 字节后整组加密」。写侧若按 `length` 原样加密、
读侧按 `pad4(length)` 解密，**最后一组会被多解一次**，文件尾 1–3 字节变成垃圾
（现象：`.str` 尾部 `禮包>` 变成 `@%\xaa`，导致整文件 UTF-8 校验失败 →
GDScript 退回 latin1 → 全文件乱码）。

修法：新内容先补到 4 的倍数（文本文件用换行补齐，不塞 NUL），再加密、再记 length。

## 4. 结果

| 项 | 值 |
|---|---|
| 产物 | `build/sf85.Script.utf8.pvf` |
| 大小 | 209,076,192 B（+3,380,208 B） |
| 耗时 | 14 s |
| 字符串改写 | 42,682 条（0 条解不开） |
| 文本表改写 | 44 个文件 / 155,955 行 |
| 路径改写 | 5 条 |
| 自检 | 370,666 条一致；`acoat_default.equ` 222 B；`swordman.chr` 4,912 B |

Godot 端到端（`tests/probe_dbg.gd`）：

```
stringtable: len=13126208 strings=461796
attrs=["基本上衣"]          ← 正确，且没有 Unicode parsing error
串[4618]=뇨뇽이            ← 韩文正常
```

## 5. 这包里有什么（做 Godot 移植用）

- `dungeon/`：`act1..act9` + `ancient / anton / timegate / towers / event / quest /
  village / warroom / riskdungeon / shonantournament / southerndale / impossible /
  tutorial / globaltutorial / villageattack`（24 个分组，10 个 act1 副本）
- **格兰之森在这版叫 `mirkwood`**：`dungeon/act1/mirkwood.dgn`、`mirkwooddeep`、
  `mirkwoodfrost`；地图 `map/mirkwood` 等
  （110 版里是 `map/granfloris` + `map/cutscene/granfloris.img`，命名不同）
- `map/`：177 个地图目录
- 角色/装备/技能齐全：`character/swordman/swordman.chr`、
  `character/swordman/animation/move.ani`、`skill/swordman/weaponcombo.skl`
- 客户端 NPK：`/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2`（8.7 GB，比 110 的 27 GB 干净）

## 6. 怎么用

```gdscript
var pvf := PvfLoader.new()
if pvf.open("res://…/sf85.Script.utf8.pvf") != OK:   # 注意返回 Error，不是 bool
    return
var doc: PvfTypes.DocNode = pvf.get_document("equipment/character/swordman/avatar/coat/acoat_default.equ")
print(doc.first("name").attrs[0])                     # 基本上衣
```

## 7. 复现

```bash
# 体检（第 2 个参数是输出目录，别和 110 的产物混在一起）
python3 tools/pvf_string_census.py "/mnt/e/dnf-sf/sf85/老牛DNF客户端/Script.pvf" analysis/pvf/broken-sf85

# 转 UTF-8
python3 tools/pvf_to_utf8.py \
  --src "/mnt/e/dnf-sf/sf85/老牛DNF客户端/Script.pvf" \
  --dst build/sf85.Script.utf8.pvf

# Godot 验证
PVF_UTF8=$PWD/build/sf85.Script.utf8.pvf XDG_DATA_HOME="$PWD/.tmp_udata" \
  GODOT_PROJECT=/mnt/e/godot_proj/dnf_like ./tools/godot.sh --headless \
  --script res://tests/probe_dbg.gd
```

## 8. 已知残留

- 85 包里仍有约 1,000~2,000 条**短韩文**（2–3 音节，如 `샷`）与 GBK 字节空间重叠，
  按中文解也是合法汉字，按先验归了中文（与 110 版同一类问题，不影响结构）。
- `.str` 里的韩文注释本身在源包里就是 `?????`（打包前已被替换），救不回。
