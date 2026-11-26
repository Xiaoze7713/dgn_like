# pvfUtility × NPK 查看器（内嵌插件）

日期：2026-11-15
宿主：`E:\pvfUtility-build`（pvfUtility 的恢复工程 + 新格式只读补丁）
查看器来源：`tools/npk_inspector/dist/NpkInspector.html`（单文件，1,370,127 B）

## 交互

1. 在 pvfUtility 里打开任意脚本（`.equ/.stk/.skl/.mob/...`）；
2. 把光标放在含 `.img` / `.ogg` / `.npk` 路径的那一行（反引号里），**Ctrl + 鼠标右键**；
3. 右侧弹出「NPK 查看器 - <NPK 文件名>」窗口，自动定位到该 img 条目并显示预览；
4. 再 Ctrl+右键别的 img：**同一个窗口换内容**，不会越开越多；
5. 关闭窗口后再触发会重新创建（单实例服务）。

行内任意位置右键都行——取不到「光标正好压在 token 上」时会回退到整行正则匹配。

## 实现

| 文件 | 作用 |
| --- | --- |
| `lib/npk/NpkInspector.html` | 单文件查看器（CSS/JS/示例数据已内联） |
| `PvfCode/NpkViewer/NpkViewerWindow.cs` | WPF 窗口 + 1 个 WebView2；虚拟源 `https://npkviewer.local` |
| `PvfCode/NpkViewer/NpkViewerService.cs` | 单实例服务；img 路径 → 所属 NPK 绝对路径；索引等待 |
| `PvfCode/ViewModels/DocumentFolder/PvfFileDocument.cs` | `PreviewMouseDown` 里判 Ctrl+右键 → `TryOpenNpkAtOffset` |
| `PvfCode/App.cs` | `--npk <npk> [entry]`、`--at <needle>` 两个调试入口 |

### 为什么用自定义虚拟源

`NpkInspector.html` 原本靠 `<input type=file>` 读本地文件；嵌进 WPF 后改成：

```text
AddWebResourceRequestedFilter("https://npkviewer.local/*", All)
WebResourceRequested:
  /index.html  -> 内存里的 HTML 字节
  /npk/<id>    -> 该 NPK 文件的字节（id -> 绝对路径，进程内字典）
```

页内再 `fetch('/npk/<id>')` → `__NPK.loadPack(bytes, 'sprite_item.NPK')` → 按条目名
`__NPK.selectEntry(idx)`。好处：同源、可 fetch、不用把文件复制进游戏目录。

### img 路径 → NPK

复用宿主已有的 `ImagePack2Service`：

```text
CombineImgPath("Item/IconMaterial2.img").ToLower()   -> "sprite/item/iconmaterial2.img"
NpkImgDIC[key] -> UtImgFile -> GetNpkFilePath(...)   -> "…\ImagePacks2\sprite_item.NPK"
```

`%04d` → `0001`、`%02d%02d` → `0001` 是脚本里的占位符约定，两边都做同样的替换。

## 踩过的坑（都已修）

1. **WebView2Loader.dll 找不到（0x8007007E）**：`App.cs` 启动时会把 exe 目录里的
   `WebView2Loader.dll` 删掉（原本给 VsCodeEditor 用），真身只在
   `runtimes/win-x64/native/`。现在 `NpkViewerWindow.EnsureWebView2Loader()` 先补一份
   再 `SetDllDirectory(BaseDirectory)`。
2. **配置文件被写坏**：`AppSetting.SaveSetting` 直接 `File.WriteAllTextAsync(AppConfig.json)`，
   进程被杀在写一半 → JSON 截断（表现为启动弹「配置文件加载时发生错误 … line 662」）。
   改成写 `.tmp` 再 `File.Replace`，原子落盘。
3. **自动备份写到游戏目录**：`AutoTheBackupPvfConfig` 默认「在 PVF 所在目录备份」，
   对 `Script.pvf` 就是往 `D:\…\地下城与勇士…\pvfUtility_BackUpPvf\` 写。
   给 `PvfPack` 加了 `BackupRedirectPath`，受保护容器统一重定向到
   `<exe>\PvfBackup\Script\`。
4. **`ChunkData` 线程不安全**：`LoadReferencedTreeIcons` 用 `Parallel.ForEach` 并发取数据，
   LRU 缓存 + `Dictionary` 竞争 → `NullReferenceException`（`NewPvfArchive.cs:349`）。
   加锁 + 数组越界时返回空数组。
5. **6.28M 条目扫图标**：受保护容器直接跳过 tree icon 扫描（纯装饰，代价是几十分钟 + 15 GB 内存）。
6. **打开慢（80 s → 18 s）**：判断「是不是脚本」别调 `FileData(i)`，看 `DataType[i]==1` 即可。
7. **双击打开卡死**：主程序会自己重开上次的 PVF，命令行再调一次会撞「是否重新加载」对话框。
   现在先等 `PVF.PvfIsOpen`，超时才主动打开。
8. **ImagePacks2 索引要等**：没索引时 `OpenImg` 不自己起第二份加载（会和主程序抢），
   而是轮询等主程序加载完（实测 8 s，356,703 个 img）。

## 验证

- 无鼠标验证（等价代码路径）：
  `pvfUtility.exe "…\Script.pvf" "stackable/…/chn_10001545_10003439.equ" --at Item/IconMaterial2.img`
  → 日志 `TryOpenNpkAtOffset off=288 token=[Item/IconMaterial2.img]` →
  `key=sprite/item/iconmaterial2.img` → `npk=…\ImagePacks2\sprite_item.NPK` →
  窗口标题 `NPK 查看器 - sprite_item.NPK`，选中第 23 条 `iconmaterial2.img`，
  91 帧、94.2 KB、28×28、v2。
- 截图：`analysis/pvf-new/shots/pvfutility-npk-viewer.png`。

## 已知限制

- 只能看，不能改 NPK（查看器本来就是只读）；
- 打开 pvfUtility 首次载入 ImagePacks2 索引约 2 分钟（之后走缓存）；
- 新格式 PVF 仍只读（`HSrm` 哈希流未破解），保存会返回
  `protected nkpi archives are read-only in this build`。

## 右键菜单（主入口，绕开 Ctrl+右键 冲突）

Ctrl+右键 会和编辑器里「Ctrl+左键打开文件位置」抢事件（Down 能到、Up 被吃掉），所以改成加进**文档编辑器原有的右键菜单**。

- **原菜单一条没动**：`在文件资源管理器中选中 / 刷新 / 保存 / 另存为 / 剪切 / 复制 / 粘贴 / 全选 / 撤销 / 重做 / 大纲显示(L)` 全在；我们的项插在**最上面**，带一条分隔线。
- 第一项文字动态改写：`在 NPK 查看器中打开：<路径>`；光标处（及上下 1–2 行）没有 `.img/.ogg/.npk` 时置灰，标题变成「在 NPK 查看器中打开图片（光标处没有 .img/.ogg/.npk）」。
- 取 token 顺序：右键落点所在行的 token → 落点整行正则 → 上 1 行 → 下 1 行 → 上 2 行 → 下 2 行 → 光标所在行。点行内任意位置都能命中。
- 实现要点：
  - 菜单是 DevExpress 的 `BarManager.DXContextMenu`（定义在 `controls/texteditorfolder/documenttexteditor.xaml`），**不是** WPF `ContextMenu`；给 `Editor.TextArea.ContextMenu` 赋值会把它整个换掉（这一步踩过，已回退）。
  - 正确做法：`AttachNpkDxMenuItem()` 里 `BarManager.GetDXContextMenu(Editor) as PopupMenu`（返回类型是 `IPopupControl`，要显式转），然后 `pm.Items.Insert(0, separator)` + `pm.Items.Insert(0, barButtonItem)`；`BarButtonItem.ItemClick` 直接调 `OpenNpkMenu()`。
  - 右键按下时 `OnPreviewMouseRightButtonDownForNpk` 记 `_lastRightClickOffset`，顺带刷新 `NpkMenuHeader` / `_npkBarItem.Content` / `IsEnabled`（菜单在 MouseUp 才弹，来得及）。
  - `OpenNpkMenu()` 带 `[Command]`，XAML 未来也可以直接绑 `OpenNpkMenuCommand`。
- 自动化入口：`InvokeNpkMenuAt(offset)`（`--at` 也走这条，等于「把菜单第一项点了一遍」）。
- 验证：真鼠标右键 `dungeon/act1/lorien.dgn` 第 5 行 → 原菜单完整弹出、第一项显示 `Map/CutScene/Lorien.img`；键盘 ↓+Enter 激活 → NPK 查看器打开 `sprite_map_cutscene.NPK` 并选中 `lorien.img`。
