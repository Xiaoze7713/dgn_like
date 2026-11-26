# pvfUtility 二次开发评估（2026-11-15）

对象：<https://github.com/Lancarus/pvfUtility.git>
目标：能否二次开发，让这个工具**直接打开最新国服 `Script.pvf`（nkpi 新格式）**做查看。

## 1. 这个仓库是什么

- **不是原作者仓库**。`README_RECOVERY.md` + `docs/` 说明：它是从**已发布二进制的 BAML/IL 反编译恢复**出来的 WPF 工程（有恢复审计与回归测试）。
- 无 `LICENSE` 文件 ⇒ 许可证状态不明。自己用没问题；**对外分发有法律风险**。
- 规模：`net10.0-windows` / `win-x64`；`find . -name '*.cs' | wc -l` = **1,894**；`SourceLibraries/` 22 个子项目；`lib/` **275 MB / 190 个 DLL**（含 DevExpress v24.1 全家桶，纯本地 `HintPath` 引用，不依赖 NuGet）。
- 附带的 NPK 模块（`SourceLibraries/PvfCode.NPK.Utils`）和经典 PVF 工具链都在，等于一个现成的"DNF 资源 IDE"。

## 2. 编译与运行（已实测通过）

```powershell
# 原本只有 8.0/9.0 SDK，global.json 要 10.0.100+，装了 10.0.404
winget install --id Microsoft.DotNet.SDK.10 --accept-package-agreements --accept-source-agreements
cd E:\pvfUtility-build
dotnet build pvfUtility.sln -c Release -v m
# → 0 个错误 / 1,393 个警告 / 24.53 s
```

- 源码副本：`E:\pvfUtility-build`（418 MB；从 WSL 的 `/tmp/pvfUtility` 拷出，避免 UNC 编译问题）。
- 产物：`E:\pvfUtility-build\bin\Release\net10.0-windows\win-x64\pvfUtility.exe`（237 KB，依赖同目录 DLL）。
- **必须把工作目录设成 exe 所在目录**再启动，否则主窗口不显示（`Start-Process -WorkingDirectory $dir`）。
- 实测界面：左侧文件资源管理器 + 顶部工具栏（导入文件 / 提取文件 / 快速导出 / 导入名称查找 / 批量处理 / PVF差异比较器 / 文档差异比较器 / 独立动画编辑器 / 发布）+ 底部输出面板。
- 截图：`E:\pvfUtility-pw.png`（PrintWindow 抓的，`CopyFromScreen` 会被前台窗口挡住）。

## 3. 它现在只认经典 PVF

全仓库 grep 结果：`nkpi` / `iNfO` / `sk.dat` / `0x2800` / `AES` **全部 0 命中**。

容器层就三处：

| 位置 | 作用 |
| --- | --- |
| `SourceLibraries/PvfCode.Services/PvfCode/PvfGroup.cs:188 OpenPvfPack` / `:60 SavePvfPack` | 读/写整个容器：`guidLen/guid/fileVersion/fileTreeLength/fileTreeChecksum/fileCount` → 解密树 → 每节点 `[u32 nameChecksum][i32 nameLen][name][i32 dataLen][u32 checksum][i32 offset]` → 按 offset 读块 `InitFile` |
| `SourceLibraries/PvfCode.Models/PvfCode/PvfFile.cs:191 InitFile` | 每块用 `DecryptionPvf(block, GetBlockLength(), Checksum)` 解出明文；`GetBlockLength()=(DataLen+3)&-4` |
| `SourceLibraries/PvfCode.Models/PvfCode/Models/Pvf/PvfAlgorithmHelper.cs` | `0x81A79011` + `ror32/rol32(6)` 树加解密；`CreateBuffKey` = CRC32 派生数据密钥 |

另外：经典 PVF 的数据块压缩用的是 **LZNT1**（`ByteHelper.cs:36 RtlDecompressBuffer(2, ...)`），不是 zlib —— 这一条连我们自己的 `docs/PVF-FORMAT-BYTES.md` 都没写。

## 4. 要读新格式，需要补的 6 件事

1. **外层**：`sk.dat` → RSA-1024 PKCS#1 v1.5 私钥解 23×128 B → 2,624 B 链（82 把 32 B 钥匙）；每 10 MiB 段首 0x2800 B 用 `chain[i]` 做 AES-256-CBC（零 IV、无填充）。私钥来自 `DNF.exe` 偏移 204651888 的 PEM 块。
2. **内层头**：`decryptProtected("iNfO")` 后得 `nkpi` + `fileCount/bodySize/groupCount/hashSize/nameSize/bodyOffset`。
3. **名字池**：`strA`（UTF-8）/`strW`（UTF-16）两个帧，各自用 `decryptPString("stAs"/"stWs")` + zlib 解；路径靠 `pathOffset` 的魔法位（`v&1`）寻址。
4. **数据块**：每组 `decryptProtected("mAIn")` → zlib。
5. **哈希流**：`HSrm` 段，只影响写回，只读可跳过。
6. **接进 UI**：让 `PvfGroup.FileList` 装进 6,288,780 个 `PvfFile`（名字用 UTF-8 而非 `Encoding.GetEncoding(949)`，`Data` 直接给解压后明文字节，跳过 `InitFile` 的 CRC 解密路径）。

现成参考实现都在本工作区：`tools/pvf_new_extract.py`（协议）、`tools/pvf_new_db.py`（C 版流密码 + 分组读）、`docs/PVF-NEW-FORMAT-34.md`（完整规格）。

## 5. 两条路线

### 路线 A：给 pvfUtility 打新格式读取（推荐）

- 新增 `NewPvfReader`（C#，约 500–700 行：AES-256-CBC、keystream、zlib/LZNT1 不需要、name pool、nkpi 表）＋在 `OpenPvfPack` 里按签名分流（经典 guidLen 合理值 vs 新格式）。
- 收益：**懒加载**、6.29M 条目录树秒开、UI 全套功能（搜索、差异比较、NPK 预览、动画编辑器）。
- 成本估计：1.5–3 天（协议已 100% 明确，纯粹是移植 + 调试）。
- 风险：`PvfFile` 的 `Data` 私有 setter、`Checksum` 语义要绕开；`stringtable.bin`/`string.lst` 的老约定要映射到新端 `string/*.chn.str` + `list/n_string.lst`，否则物品名/技能名解析不出中文。

### 路线 B：Python 把新 PVF 重打包成经典 PVF（快）

- 写经典容器写入器（header + 树加密 + 每块 LZNT1 压缩 + CRC 密钥），把新端 6.29M 条落盘成 `Script.classic.pvf`，用**未修改的** pvfUtility 打开。
- 成本：0.5–1 天。机器 64 GB 内存够（解压后 7.14 GB）。
- 缺点：一个 7 GB 的中间产物；打开慢；每次更新都要重打包；不是"直接看"。

## 6. 结论

- **能二次开发**：容器层只有 ~3,900 行里的三处，边界清晰，事实是这是个反编译恢复的工程，能编译、能跑。
- 建议 **A**（直接支持新格式）作为主线，B 只当临时手段。
- **写回/编辑暂不可行**：新内层 `HSrm` 哈希流的算法未解（开源服务端只用文件表，客户端是否校验未知），所以第一版只做**只读查看**。
- 许可证不明 ⇒ 自用可以，别分发编译产物。
