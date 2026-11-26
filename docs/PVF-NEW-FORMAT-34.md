# 新版客户端 Script.pvf 格式规格（国服 34.3.13.22，2025）

对象：`dnf_latest/Script.pvf` 850,304,454 B；`dnf_latest/SideGamePlay/Script_SGM.pvf` 61,532,055 B。

**状态：外层与内层全部解开，脚本可完整导出为文本。**

参考实现：`gitgud.io/RicardoLz/115`（dfo-lan 服务端，`server/work/dfo-lan/internal/catalog/pvf/*.go`）。
本机复刻：`tools/pvf_new_unwrap.py`（外层）+ `tools/pvf_new_extract.py`（内层）。

---

## 1. 外层 wrapper：sk.dat 钥匙链 + 每 10 MiB 段头 AES

整件按 **0xA00000（10,485,760 B）** 切段，段数 = `ceil(体积/0xA00000)` = **82**。

| 位置 | 内容 |
| --- | --- |
| 每段 `[0, 0x2800)` | AES-256-CBC，零 IV，无填充，key = `chain[i]`；解出来是**明文（真的）** |
| 每段 `[0x2800, 0xA00000)` | 明文 |
| 首段最前 48 B | 明文即内层容器头，但**还叠了一层 `decryptProtected("iNfO")`**（见 §3） |

钥匙链来自 `sk.dat`（2,944 B）：

1. `2,944 = 23 × 128`；每 128 B 是一块 **RSA-1024 / PKCS#1 v1.5** 密文；
2. 用 `DNF.exe` 里的私钥解 → 每块 117 B 明文，共 `23 × 117 = 2,691` 字节，但链只有 **2,624 B**（尾块按实际长度截断）；
3. 链本身再经 **AES-256-CBC（零 IV、无填充）** 处理：前 `L-(L%256)` = 2,560 B 是密文，尾 64 B 原样；解出 `2624 = 82 × 32` ⇒ **82 把 32 B 段钥匙**，与段数一一对应。

取钥（`DNF.exe` 280,795,768 B，整体加壳，`.std` 段）：

- PEM 私钥在偏移 **204,651,888**（915 B，`-----BEGIN PRIVATE KEY-----`，RSA-1024）；
- wrapKey（32 B 的 AES 钥匙，即"解链的钥匙"）取该 PEM 结尾后 **0x200 窗口内第一个 64 位大写十六进制串**：
  `A7F93D76DC6ACD8A27216D4CB2D74ADBE380B99F919E8077231EC17F9D36D52C`（偏移 204,652,816）；
- 偏移 210,508,661 另有一个 PEM，后面是 UTF-16 的 OpenSSL 文案，**是诱饵**。

段内改了首 0x2800 B 之后即得 `*.inner.pvf`（等长）。850 MB 全解 **约 3.4 s**。

---

## 2. 内层容器布局（`nkpi`）

```
0x00                    0x30        header            decryptProtected("iNfO")
0x30                    N*0x18      file table        明文
+hashSize                            hash stream       decryptProtected("HSrm")
+nameSize                            name section      8 B 前缀 + strA 帧 + strW 帧
+G*8                                 group table       decryptProtected("Gidx")
+bodySize                            body              每 chunk: zlib → decryptProtected("mAIn")
```

header（48 B，解密后）：

| 偏移 | 字段 | 本机实测 |
| --- | --- | --- |
| 0 | magic | `nkpi` = `0x69706B6E` |
| 24 | fileCount | **6,288,780** |
| 32 | bodySize | 596,629,844 |
| 36 | groupCount | 96,775 |
| 40 | hashSize | 59,390,448 |
| 44 | nameSize | 42,579,194 |
| 28 | bodyOffset（冗余冗余存一份） | 253,674,610 |

自洽方程（与文件大小**精确相等**）：

```
48 + 6,288,780×24 + 59,390,448 + 42,579,194 + 96,775×8 + 596,629,844 = 850,304,454
```

文件表每条 24 B：`[nameOffset][pathOffset][chunkIndex][dataOffset][dataSize][dataType]`。
`dataType`：**1 = tag 流脚本（文本）6,270,321 条**、**3 = UTF-16 文本 18,088 条**、**4 = 二进制 371 条**。

组表每 8 B：`[u32 该组结束的累计压缩偏移][u32 原始长度]`；chunk i 的压缩区间是 `[g[i-1].compressedSize, g[i].compressedSize)`。

---

## 3. 流密码 `decryptProtected`（LCG，加解同路）

```
key 取 UTF-16 前 4 个 word w0..w3
seed = 0x339E9711*w0 + 0x393*(w3 + 0x393*(w2 + 0x393*w1))   (mod 2^32)

每 4 字节:
  t1 = 0x343FD*seed + magic ; seed = 0x343FD*t1 + magic
  xorKey = (t1 & 0xFFFF0000) + (seed >> 16)
  u32le ^= xorKey
尾部不足 4 字节:
  t1,t2 各再推一次；finalKey = (t1 & 0xFFFF0000) + ((t2 >> 16) & 0xFFFF)，按小端逐字节异或
```

`magic = 0x269EC3`（`iNfO` / `HSrm` / `Gidx` / `mAIn`），`magic = 0x269EC9`（字符串池 `stAs` / `stWs`）。

字符串池帧：`[u32 密文长 ^ xorConst][u32 原文长 ^ 密文长][decryptPString(key) → zlib]`

| 池 | key | xorConst | 编码 | 本机大小 |
| --- | --- | --- | --- | --- |
| strA | `stAs` | `0xE7ADF7EA` | UTF-8 | **0 B**（空） |
| strW | `stWs` | `0xB8DEA7AC` | UTF-16LE | 509,898,432 B |

字符串寻址：`v & 1 == 1` ⇒ strW 字节偏移 `(v>>1)*2`；`v & 1 == 0` ⇒ strA 偏移 `v>>1`；NUL 结尾。

---

## 4. 脚本 tag 流（dataType = 1）

每 token **5 字节**：`[1B type][i32 value]`。

| type | 含义 | 渲染 |
| --- | --- | --- |
| 0 | 整数 | `value ` |
| 2 | float32 | `value ` |
| 3 | 字符串（多为标签，形如 `[name]`） | 换行 + 4 空格 + 文本 |
| 5 | `{5=``}` | 换行 |
| 6 | 反引号字符串 `` `x` `` | 行内 |
| 7 | `{7=``}` | 换行 |
| **8** | **新版新增：值字符串**（Go 实现里未处理） | 接在上一条标签后 |

### 本地化：文本外置

新版脚本里的可见文本不再是字面量，而是引用 `<N::key>`：

- `N` = `list/n_string.lst` 的表序号（本机 **38 张**，0..37）；
- 表文件是 `string/<Name>.chn.str`（UTF-16LE 纯文本，每行 `key>文本`，首行 `// Kor Comment`）；
- 例：`stackable/10015001/10015138.stk` 的 `[name]` = `<13::name_10015138>` → 查 `string/stackable.chn.str` → **`使徒卡恩 卡片`**。

`tools/pvf_new_extract.py` 已内建该解析（`--no-zh` 可关）。

---

## 5. 工具链

```bash
# 1) 外层：取钥 + 解 82 个段头 -> *.inner.pvf
python3 tools/pvf_new_unwrap.py dnf_latest                        # 需 DNF.exe/sk.dat/Script.pvf
#    产物 /tmp/inner/Script.inner.pvf, /tmp/inner/SGM.inner.pvf

# 2) 内层：索引 / 统计 / 导出
python3 tools/pvf_new_extract.py /tmp/inner/Script.inner.pvf --list analysis/pvf-new/index.tsv.gz
python3 tools/pvf_new_extract.py /tmp/inner/Script.inner.pvf --stats analysis/pvf-new/stats2.json
python3 tools/pvf_new_extract.py /tmp/inner/Script.inner.pvf \
        --extract export/ --suffix .skl,.lst,.lua --limit 40000
python3 tools/pvf_new_extract.py /tmp/inner/Script.inner.pvf --list /dev/stdout | head   # 索引预览
```

`NewPvf`（Python 类，`tools/pvf_new_extract.py`）也直接当库用：

```python
from pvf_new_extract import NewPvf, decode_script, L10n
p = NewPvf('/tmp/inner/Script.inner.pvf')
zh = L10n(p)
for idx, d, n, path, dt, ds, ci, do in p.entries():   # 6.29M 条
    ...
    text = decode_script(p.chunk(ci)[do:do+ds], p.resolve, zh)
```

---

## 6. 本机实测规模

| | Script.pvf | SGM.pvf |
| --- | --- | --- |
| inner 体积 | 850,304,454 B | 61,532,055 B |
| 条目 | **6,288,780** | 331,725（表头脏 1 行） |
| 解压后总字节 | **7,142,625,379** | 408,064,488 |
| dataType 1 / 3 / 4 | 6,270,321 / 18,088 / 371 | — |
| body | 596,629,844 B（≈ 8.5–12× 压缩） | 53,560,431 B |
| 最大 chunk | 13,796,150 B | — |
| strA / strW | 0 / 509,898,432 B | — |

顶层目录（Script）：`contents` 2,948,079、`passiveobject` 872,257、`monster` 722,723、`live` 443,014、`equipment` 432,150、`map` 273,420、`stackable` 203,449、`character` 151,038 ……

后缀：`.ani` 4,241,248、`.act` 538,737、`.equ` 388,146、`.als` 330,266、`.stk` 199,043、`.til` 141,884、`.obj` 123,576、`.atk` 76,227、`.map` 49,170、`.ai` 24,644、`.mob` 21,872、`.skl` 6,739、`.**lua` 4,496**、`.npc` 4,468、`.lst` 611、`.str` 87；**`.nut` 0**。

---

## 7. 仍未解 / 待办

| 项 | 状态 |
| --- | --- |
| `Script_SGM.pvf` 的钥匙链 | 段头用主链 `chain[0]` 解不出 `nkpi`；它应有独立的 sk.dat（未在客户端目录里找到第二个 sk.dat，可能在 `dstr.dat` 或 `apollo_reslist` 里） |
| hash 流（`HSrm`，59,390,448 B）算法 | 结构已知（`[i32 n][n×8][i32 m][m×4]`），`n` 疑似 = fileCount、`m` 疑似条目索引；32 位哈希函数未取证。**服务端查找只用文件表**，所以不影响解包 |
| `dstr.dat`（1,975,200 B = 15,431×128 B RSA 块） | 两种私钥分别能解 11,567 / 13,136 块，解出仍是随机字节 ⇒ 还有一层，用途未定（可能与 SGM 钥匙 / 账号数据有关） |
| `DolphinPathHdiff/apollo_reslist.flist.gen` | 8,360,112 B，头 u32 = 27,867（= 客户端文件数），正体 8 B 块滚动模式 ⇒ 加密的路径清单 |
| 数据区真伪校验 | 新版没有老版那种逐文件 crc32；body 用 zlib（自带 adler32） |
