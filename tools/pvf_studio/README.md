# PVF Studio（桌面版 PVF 阅读器）

DNF 新版 `Script.pvf` 内层（`nkpi` 格式）的图形浏览器。纯 Python 标准库 + tkinter，不依赖浏览器、不需要装包（Linux 侧 `python3-tk` 即可，Windows 自带的 Python 就够）。

## 怎么启动

**Windows 桌面（推荐，用户日常用这个）**

双击桌面上的 **PVF Studio** 快捷方式（`C:\Users\Administrator\Desktop\PVF Studio.lnk`）。

它内部执行：

```bat
wscript "E:\dnf-pvf-studio\launch.vbs"
```

`launch.vbs` 再拉：

```bat
wsl.exe -d Ubuntu-22.04 --cd /home/sunmingze/dnf_like -e env DISPLAY=:0 python3 tools/pvf_studio/pvf_studio.py
```

窗口通过 WSLg 显示，控制台被 `sh.Run ..., 0, False` 隐藏。进程挂掉看不到报错，想看日志就把 `launch.vbs` 里的 `0, False` 临时改成 `1, True`。

**WSL 里直接跑**

```bash
cd /home/sunmingze/dnf_like
DISPLAY=:0 python3 tools/pvf_studio/pvf_studio.py
# 或者直接打开某个文件并选中它
DISPLAY=:0 python3 tools/pvf_studio/pvf_studio.py --open skill/gunner/activation.skl
# 只做自检（不弹窗），CI/回归用
python3 tools/pvf_studio/pvf_studio.py --selftest
```

## 依赖的数据（缺了先生成）

| 文件 | 大小 | 生成方式 |
|---|---|---|
| `analysis/pvf-new/pvf34.tree.sqlite` | 1.5 GB | `python3 tools/pvf_browser/build_tree.py` |
| `analysis/pvf-new/pvf34.sqlite` | 12 GB | `python3 tools/pvf_new_db.py analysis/pvf-new/inner/Script.inner.pvf analysis/pvf-new/pvf34.sqlite` |
| `analysis/pvf-new/pools/strW.bin` | 510 MB | `python3 tools/pvf_dump_pools.py` |
| `analysis/pvf-new/pools/strA.bin` | 0 B | 同上 |

`pools/` 是把 PVF 名字池落成裸文件，桌面端用 `mmap` 秒开（省掉每次解 500 MB 的 20 s）。`<13::name_10000039>` 这种引用就是查 `strW.bin` + `string/*.chn.str` 还原成中文。

## 界面

- 左：真目录树（不是扁平列表），点三角展开，双击切展开/收起。大目录分页（每次 3000 项，末尾「加载更多」）。
- 右：`文本` / `HEX` / `信息` 三页。`文本` 是解码后的 `.skl/.equ/.stk/.lst/.lua/.ai/.act/.atk` 等 token 流；未知二进制给 hex。
- 顶部搜索：按路径（`entries.name` LIKE）或按内容（`text.body` LIKE，后台线程，不卡界面）。
- 工具栏：`折行`、`还原韩文`、`复制路径`、`导出当前文件`（把截断的大文件写全）。

## 根目录 `*.lst` 看着像乱码？不是解包错

`aicharactername.lst` / `itemname.lst` / `monstername.lst` / `npcname.lst` / `passiveobjectname.lst` / `skillname0..10.lst` 这 15 个 name 表，字符串在包里就是**韩文被当成 GBK 解码**后的产物（cp949 → GBK 码表串了）。还原方式：把字符串按 GBK 编回字节、再按 cp949 解：

```
矫鄂        → 시란              (aicharactername.lst)
八篮 乔蝴 唱力 → 검은 피빛 나제      (同上)
绊喉赴       → 고블린             (monstername.lst)
绊喉赴 捧么捍  → 고블린 투척병       (同上)
```

- 阅读器里勾上 **还原韩文** 即可看韩文原名；打开整个文件都是这种乱码时会**自动勾上**（判定：反引号字符串中 ≥50% 且 ≥5 个能还原）。
- 实测覆盖率：`monstername.lst` 12,330/12,332、`itemname.lst` 10,694/10,694、`aicharactername.lst` 1,459/1,466。
- 这些表**不参与显示**——客户端的名字全部来自 `string/*.chn.str`（`ai_character_name_203>烈炎之手波尔拉` 这种），所以中文端没人管它们。随机抽 300 个 `dtype=1` 文件，非 ASCII 反引号字符串数为 0：正常数据里没有中文进过字符串池，中文一律走本地化引用 `<N::key>`。

## 大文件策略

- 读库时用 `substr(data,1,?)` 只取前 16 MB（`MAX_READ_BYTES`），不把 100 MB 的 blob 拉进内存。
- 文本上限 20,000,000 字符（`MAX_TEXT_CHARS`），超了状态栏提示「已截断」，点「导出当前文件」拿全文。
- 实测：100 MB `clientonly/dropinfo/(r)dropinfo.db` 245 ms、36 MB `.str` 33 ms、39 MB `.dat` 387 ms、3.5 MB `.lst` 1.3 s。

## 已知问题

- WSLg 的 `zoomed` 不生效，窗口尺寸靠 `_fit_screen()` 自己算。
- Tk 的 iid 不能含 `\x00`（Tcl 会在 NUL 截断），所以目录树占位节点用 `|ph|` / `|more|` 后缀。
- 只读，不支持改 PVF（改写要重算 `HSrm` 哈希流，见 `docs/PVF-NEW-FORMAT-34.md` 的未解项）。
