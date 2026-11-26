# pvfUtility 新格式（nkpi）只读支持

目标：把用户选的 `pvfUtility` fork 改成能直接打开当前国服 `Script.pvf`（850,304,454 B，nkpi 内层），只读浏览。

## 一、结论

- 能打开、能浏览、能读脚本，**已实拍验证**（`analysis/pvf-new/shots/pvfutility-text.png`）。
- 打开耗时 ~17–21 s，内存 ~6.6 GB，状态栏显示 `文件数: 6288780`，与 Python 侧完全一致。
- **保存/回写不行**：新内层的 `HSrm` 哈希流算法未知，写入被硬性拦住（返回 `protected nkpi archives are read-only in this build`），不会破坏原包。

## 二、改动清单（全部在 `E:\pvfUtility-build`）

1. 新增 `SourceLibraries/PvfCode.Services/PvfCode/NewPvf/NewPvfArchive.cs`（~560 行）
   - 段解密：`0xA00000` 分块，前 `0x2800` 为 AES-256-CBC（零 IV），key 来自 `sk.dat`。
   - `KeyChain`：从同目录 `DNF.exe` 正则取 `-----BEGIN PRIVATE KEY-----` + 其后 0x200 窗口首个 64-hex；RSA-1024/PKCS#1 解 23×128 B → 2624 B → AES 解前 2560 B + 尾 64 B → 82 把钥匙（按 sk.dat 时间戳缓存）。
   - 内层解析：`iNfO` 头（`nkpi`）、文件表、`HSrm`、`stAs`/`stWs` 名字池、`Gidx` 组表、`mAIn` 分块（zlib）。
   - 流密码：`decryptProtectedCore`（MSVC LCG `0x343FD`，magic `0x269EC3` 用于 iNfO/HSrm/Gidx/mAIn，`0x269EC9` 用于字符串池）。
   - `ResolveWideString(value)`：魔术偏移语义，奇数 → `(v>>1)*2` 走 UTF-16 池，偶数 → `v>>1` 走 UTF-8 池。
   - `FileDataAsScript(index)`：给 token 流前置 `B0 D0`（= u16 53424）让经典脚本判定成立。
2. `PvfFile.cs`：`Data` 由自动属性改为惰性（`LazyDataLoader`），`FileName` 支持 `FileNameOverride`（绕过 GBK/949，新容器是 UTF-8 路径）。
3. `PvfGroup.cs`：`OpenPvfPack` 入口判定新格式 → `OpenProtectedNkpiPack`；6.28M 条目只填元数据（不读数据，否则打开要 80 s）；`Strtable.ExternalResolver` 接名字池；用 `list/n_string.lst` 初始化 `Strview`（`EncodingType.Unicode`）。
4. `PvfPack.cs`：新增 `IsProtectedNkpi`；`SavePvfPack` 对新格式直接返回只读提示（原实现保留为 `SavePvfPackCore`）。
5. `Stringtable.cs`：新增 `Func<int,string> ExternalResolver` 钩子（在 `GetStringItem` 最前面）。
6. 新增 `NewPvfScriptDecoder.cs` + `PvfExtensionHelper.GetFileText` 分流：新格式脚本用自有解码器（type 0=int、2=float、3=标签、6=反引号串、8=本地化引用 `<N::key>` → 走 `Strview`），不再走经典反编译器（两者 token 类型编号不同）。
7. `App.cs`：`--newpvf-selftest <pvf> <report>` 无界面自测；`pvfUtility.exe <pvf> [内部路径]` 直接打开包并可再打开某个文件。

## 三、已知限制

- 只读；`stringtable.bin` 不存在（新容器把标签放名字池），所以靠 `ExternalResolver` 顶替。
- 文本是**繁体中文**（客户端 `string/*.chn.str` 本身是 TC）；需要简体的话走工具的繁→简选项。
- `SGM`（`SideGamePlay/Script.pvf`）钥匙链仍未解，暂不支持。
- 保存路径、导入、批量替换类功能对新包不可用。
- 打开较慢（17–21 s）主要花在 6.28M 条路径解析上，属一次性成本。

## 四、复现

```bat
cd /d E:\pvfUtility-build
dotnet build pvfUtility.sln -c Release -v q
:: 图形界面（第二个参数可选，打开后自动跳到该文件）
bin\Release\net10.0-windows\win-x64\pvfUtility.exe "D:\...\Script.pvf" skill/gunner/activation.skl
:: 无界面自测
bin\Release\net10.0-windows\win-x64\pvfUtility.exe --newpvf-selftest "D:\...\Script.pvf" E:\selftest.txt
```
