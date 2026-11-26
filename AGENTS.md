# 工作区说明（dnf_like）

## 能力索引：改功能必须同步 README（2026-11-25，用户要求）

- 每个有实现的目录都维护一份 `README.md`（类似“这一层能做什么”的索引）；新增或修改函数、常量、信号、资源格式时，在**同一次改动**里更新所在目录的 README，不要等收尾补。
- README 至少写清：文件/职责、对外入口的签名与参数语义、调用关系、坐标/缓存/生命周期规则、验证命令、已知坑。函数说明写“做什么、返回什么、谁调用”，不抄实现。
- 层级：`game/world/README.md` → 各子目录 `README.md` → 文件顶部注释；先读上层索引，再按需下钻到文件。新功能要能被外层直接找到入口。
- 新增目录/新增对外入口却找不到 README 行，视为改动未完成。


## 文档更新：先要授权（2026-11-15，用户提出后记）

- 用户有时默认开着**工作区权限**（`workspace-write`）：这个模式下 `docs/`、`*.md` 的写入不会弹审批，静默就成功了。
- 所以**动文档之前一律先问一句**（新建、改写、迁移、删除都算），不要因为"没被拦住"就当成已授权。
- 适用范围：`docs/`、各 `AGENTS.md`、协作知识库里的 md，以及顺手做的索引/登记行。
- 纯代码改动不在此列，仍按任务要求走。

## 改动纪律：先查关联，再动手（2026-11-18，用户提）

> 用户原话：「很多东西注意下关联关系，干了什么，哪里有影响，不要改了这里那里错了，现阶段就这一小段代码，还是频繁出问题。」
> 现阶段代码量很小，出错基本不是"难"，而是**改一处漏一处**：同一条规则被写了两三遍，改完没验证另一份。

### 三条铁律

1. **改公式 / 常量 / 正则之前，先 grep 出所有使用点**，在回复里列出「哪几处共用、哪几处是同一条规则的另一份实现」。已知的成对实现（改一个必须同步改另一个）：

   | 规则 | 写在哪几处 |
   |---|---|
   | 地砖落点（`画布高 = 行数×16 + img_pos`） | 基础地砖 + **扩展地砖**（两处规则不同：基础层画布底边对齐，扩展层顶边贴网格下沿） |
   | 内容包 key | `tools/pvf_world/build_pack.py` 的 `key_of()` + `game/world/content/pack_content.gd` 的 `KEY_PATTERN`（正则必须逐字一致） |
   | 坐标系（翻不翻 y） | 地砖 / pass 网格 / 怪物 NPC 物件 / `[animation]` / 背景层，**五套，各不相同** |
   | `[animation]` 的 +120 | `RoomBuilder.y_shift`（600−480 的差，不是可调参数） |
   | z 层级 | `_layer_z()` 的分档表（100 以内，`z_index` 越界会被 Godot 静默拒绝） |

2. **一次只改一个点，改完要能说清"哪些像素/行为该变、哪些不该变"**，并用证据验证：
   - 逻辑：`tests/world_smoke.gd`（657 项）
   - 视觉：`tests/world_shot.gd` 拍**城镇 + 副本各一张**；不该变的那张用 sha256 比对（例：改副本地砖公式时，城镇截图必须字节相同）
   - 只跑一类不算验证完。

3. **不许用"全局开关 / 整层停用"掩盖单点 bug**。反例（真发生过）：装饰 `[closeback]` 漂移 → 我直接把整个视差关掉；正确做法是 `_scroll_factor(layer, room, is_background)` 按**来源**区分。

### 动手前自检 5 问

1. 这个值/函数还有谁在用？（`grep` 一遍，别凭记忆）
2. 有没有同一规则的**第二份实现**？（城镇 vs 副本、基础 vs 扩展、背景 vs 装饰）
3. 它会不会**静默失败**？（`z_index` 越界、JSON `null` 传给 `int()`、`Dictionary.get()` 的类型推断、`class_name` 缓存没刷）
4. 影响城镇还是副本？会不会只对 `img_pos = 0` 的图正确？
5. 怎么证明没弄坏别的？（冒烟 + 两张截图 + 该不变的哈希）

### 收尾

改完把「现象 / 根因 / 证据」补进 `docs/PVF-MAP-PITFALLS.md`；规则层面的结论进 `docs/PVF-MAP-LOADING.md`。别只写在回复里——下个窗口看不到回复。

## 工具入口（必读 · 2026-11-17 建表，开新窗口先扫一眼）

| 工具 | 怎么开 | 用途 / 备注 |
|---|---|---|
| **PvfUtility 新格式 fork** | 桌面 `DNF PVF 工具.lnk`；exe = `E:\pvfUtility-build\bin\Release\net10.0-windows\win-x64\pvfUtility.exe`；备用 `E:\launch_pvf.cmd`、`E:\launch_pvf2.cmd` | 读最新国服 `Script.pvf`（6,288,780 条目，~7 GB 内存，~40 s）。**必须把工作目录设成 exe 所在目录**，否则主窗口不显示；参数只能走 ASCII 路径 `D:\dnf_latest\Script.pvf`（`D:\dnf_latest` 是指向中文客户端目录的 junction，中文路径传进去会被代码页弄坏、静默不加载）。**保护格式只读**，保存被硬拦。细节见 `docs/PVFUTILITY-NEWPVF-PATCH.md`、`docs/PVFUTILITY-FORK-ASSESSMENT.md` |
| PVF Studio（旧的，用户说以后不用） | 桌面 `PVF Studio.lnk` → `E:\dnf-pvf-studio\launch.vbs` → WSL `python3 tools/pvf_studio/pvf_studio.py` | 桌面版 PVF 阅读器；已被 PvfUtility 取代，保留只为回溯 |
| PVF 网页浏览器 | `http://127.0.0.1:8770`（tmux 会话 `pvfbrowser`，入口 `tools/pvf_browser/start.sh`） | 网页版 PVF 查询；库 `analysis/pvf-new/pvf34.sqlite`(12 GB) + `pvf34.tree.sqlite`，由 dnf_latest 的 Script.pvf 建 |
| NPK Inspector | 双击 `tools/npk_inspector/dist/NpkInspector.html`，选 `...\ImagePacks2` | 单文件网页版 NPK 看图集/逐帧/播放；自动化截图见 `tools/npk_inspector/test/shot.mjs` |
| 知识树索引 | `docs/KB-INDEX.md` | 查 PVF 格式/机制/公式「结论 + 出处」，先看它的 §0 入口表 |
| **踩坑记录（地图）** | `docs/PVF-MAP-PITFALLS.md` | 做地图/渲染前先扫：z_index 越界、两套坐标、`[img pos]` 是顶部空白、NPC 画布原点、F 键冲突；§5 是流程纪律，§6 是 2026-11-25 增量，§7 是复查命令 |
| **地图内容包编译（旧）** | `python3 tools/pvf_world/build_pack.py --town hendonmyre ... --out .../assets/pvf/world` | 已不是运行时路径：`WorldDirector` 改为 `LivePvfContent` 直接读 `/mnt/d/dnf_latest/Script.pvf`。脚本保留用于对照/调试；`--dry-run` 只验证。规则见 `docs/PVF-MAP-LOADING.md` |
| **地图全量审计** | `XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like ./tools/godot.sh --headless --script res://tests/audit_maps.gd` | 加载 twn 489 + dgn 目录 15,700 张 map，输出 `dnf_like/data/debug/audit_maps.{json,md}`；当前 114 张空文件、302 个未解析 label。约 72 s |
| **地图运行时（Godot）** | `/mnt/e/godot_proj/dnf_like`：`game/world/**`、`scenes/world.tscn`；`XDG_DATA_HOME=$PWD/.tmp_udata GODOT_PROJECT=/mnt/e/godot_proj/dnf_like ./tools/godot.sh --headless --script res://tests/world_smoke.gd` | 城镇/副本装载、换图、回城、NPC 立绘、城镇列表 UI。冒烟 `world_smoke.gd`（669 项：128 城镇全部 area）、手感 `world_walk.gd`（8/2，副本待接）、UI/跨城/缓存 `world_ui.gd`（53 项）、怪物/对象解析 `world_entities.gd`（12 项）、地砖帧号 `tile_frames.gd`（6 项）、NPK DDS 回归 `npk_dds.gd`（6 项）、DXT 单测 `npk_dxt.gd`（14 项）、引用资源批量扫描 `npk_scan.gd`（4,343 图/约 5 分钟）、截图 `world_shot.gd`（非 headless + WSLg，`--ui=1` 城镇列表，`--map=...` 单图，`--walk=area` 只走 area，`--movable-y=N`）。**运行时直接读** `Script.pvf` + `ImagePacks2`，不读 JSON、不读 `assets/npk-index-latest.bin`；路径常量在 `world_director.gd` 顶部 |
| **latest .stk / .chr 字典** | `python3 tools/stk_dict.py`、`python3 tools/chr_scan.py`、`python3 tools/pvf_refs.py` | 全量道具字段字典（199,043 个 .stk、727 字段）、55 个 .chr 结构树、引用图（115,496 条边）。产物在 `analysis/pvf-new/items/`、`analysis/pvf-new/chr/`。规则与枚举见 `docs/PVF-NEW-STK-CHR-SPEC.md` |

## 产出登记规则（2026-11-17，用户提「新窗口别忘」）

- 每个任务只要产出**以后还会用**的东西（工具、脚本、数据快照、关键结论），就登记：上面那张表加一行，或在对应小节补一句。
- 每行至少写：**路径 / 怎么开 / 限制与坑 / 怎么验证**。细节别塞进本文件，放 `docs/` 对应文档，这里只留链接。
- 一次性的调试脚本、临时截图不要登记。
- 判断标准：如果三天后新开一个窗口、只读本文件，能不能直接把它开起来 —— 不能就说明登记不合格。

## 真实项目位置

- **真实 Godot 项目：`/mnt/e/godot_proj/dnf_like`**（WSL 下的 Windows E 盘）。
- 工作区里 `/home/sunmingze/dnf_like/dnf_like` 是它的**符号链接**；`res://` 根 = 该目录。
- 项目形态：Godot 4.7 / Forward Plus / .NET（C#，`project/assembly_name="dnf_like"`）/ Jolt Physics；目录有 `core/ game/ services/ models/ resources/ utils/ tests/`。
- 已有的 `core/config.gd`、`core/constants.gd`、`core/global.gd` 是项目原有模块，和日志/环境组件不是一套东西，改名前先看清楚。

## 日志组件（2026-11-13 交付，用户已拿走）

- 交付版已拷进真实项目：
  - `core/log/log_core.gd`、`core/log/log_tag.gd`、`core/log/log.gd`、`core/log/README.md`
  - `core/app_env.gd`（autoload `Env`）
  - `tests/test_logger.gd`、`tests/probe_scene.gd|.tscn`
- 真实项目的 `project.godot` 已于 2026-11-13 注册这两个 autoload（`[autoload]` 段，Env 在前）：

  ```ini
  [autoload]
  Env="*res://core/app_env.gd"
  Log="*res://core/log/log.gd"
  ```

  验证方式（headless 跑真实项目，42 项自测全绿）：

  ```bash
  XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
    ./tools/godot.sh --headless --script res://tests/test_logger.gd
  ```

- `core/app_env.gd` 的 `version` 现在会在 `application/config/version` 为空时回退 `"0.0.0"`（真实项目没设版本号）。
- 检测/自测脚本 `tests/probe_scene.*`、`tests/test_logger.gd` 留在真实项目里；不想要可删，不影响 logger 本体。

- 工作区里的 `src/game/` 是当时的脚手架副本（含自测与 README 源），仅作参考/回归用；改真实项目时以 `/mnt/e/godot_proj/dnf_like` 为准。

## 本机调试注意（2026-11-14，用户提出后记）

- **浏览器自动化优先用 Chrome**：`C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`（本机 157.0.8103.51）。
  之前用 Edge headless 调 NPK Inspector，Windows 侧残留了大量 msedge 进程没关；用户怀疑是 Edge/Windows 回收的坑，之后别再拿 Edge 做常驻/批量自动化（临时兜底可以）。
- 截图脚本 `tools/npk_inspector/test/shot.mjs` 已改：自动 Chrome → 回退 Edge；每次用唯一 profile（`E:\tmp_bprof_<pid>_<rand>`），结束先 `Browser.close` 再补杀，启动时清扫旧 profile 目录。
- 手工兜底：`node tools/npk_inspector/test/cleanup.mjs` —— 只杀命令行带 `tmp_bprof_` / `tmp_edgeprof_` 标记的 chrome/msedge，不碰用户自己开的浏览器，并删对应 profile 目录。
- 沙箱：`/mnt/e` 能不能从 WSL 直接写，取决于当前 **DSH file policy** —— `workspace-write` 下写/删会被拒（「权限不够」），`danger-full-access` 下正常可写（2026-11-15 实测 `cp`／`chmod` 通过）。真被拒时再交给 PowerShell（`/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`）。
