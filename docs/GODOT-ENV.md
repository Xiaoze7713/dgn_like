# Godot 4.7.2 在本机（WSL2）能不能真跑起来

> 验证于 2026-10-26 22:19–22:30 / WSL2（`6.18.54.1-microsoft-standard-WSL2`，Ubuntu 22.04.5，16 核 / 31G）/ 引擎 `4.7.2.stable.official.ed1daf0bf`
> 每个结论都附本轮实际命令与输出。冒烟工程 `tools/smoke/`，启动封装 `tools/godot.sh`。

## 0. 结论：能开工

| 问题 | 答案 | 证据 |
|---|---|---|
| 这台机器跑得起来吗 | **能**：WSLg 有真 GPU（RTX 4090 直通，经 Mesa/D3D12 走 **OpenGL ES 3.1**），有窗口、能渲染、能离屏出图 | §2 §4 |
| headless 可用吗 | **可用但不出图**（dummy 渲染器）：脚本照跑、日志照打、退出码正常 | §3 |
| 能导出 Windows exe 吗 | **能**，且已在本机 Windows 上跑通（NVIDIA 原生驱动、截图 3840×2160） | §5 |
| 中文行不行 | **行**：默认字体靠系统回退显示中文（Linux→文泉驿，Windows→微软雅黑）；发行版仍建议打包字体 | §6 |
| 渲染后端 | **Compatibility（opengl3）**。本机 **Vulkan 不可用**（无 loader/ICD），Forward+ 报错回退——2D 本来就用 Compatibility，无损失 | §2.2 |

**推荐路径**：项目放 **WSL 侧 ext4**（`src/game/`），用 `tools/godot.sh` 启动；看画面用 **WSLg 窗口**（`DISPLAY=:0`）或 `--write-movie` 导 PNG；给人试玩跑 **Windows exe**。**别把项目放 `/mnt/c`**：1,000 张图导入 3.72s（ext4）vs 18.73s（9p）。

## 1. 安装（项目内，不动系统目录）

```bash
$ curl -L -o /tmp/godot.zip \
    https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
$ mkdir -p tools/godot && unzip -o -q /tmp/godot.zip -d tools/godot && ln -sf Godot_v4.7.2-stable_linux.x86_64 tools/godot/godot
$ ./tools/godot/godot --version
4.7.2.stable.official.ed1daf0bf
$ sha256sum tools/godot/Godot_v4.7.2-stable_linux.x86_64
8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e
```

占用：引擎 140 MB；**导出模板另算 1.28 GB 下载 / 2.0 GB 解包**（§5）。

## 2. 图形能力摸底

### 2.1 GPU 是直通的

```bash
$ ls -l /dev/dxg /dev/dri      # /dev/dxg、card0、renderD128 都在
$ nvidia-smi | head -12        # NVIDIA-SMI 615.71.08 | NVIDIA GeForce RTX 4090 | 24564MiB
```

### 2.2 Vulkan **不可用**（本机唯一硬限制）

```bash
$ ldconfig -p | grep -i vulkan        # 无输出
$ ls /usr/share/vulkan/icd.d          # 目录不存在；/usr/lib/wsl/lib 只有 libd3d12/libdxcore/libcuda
$ DISPLAY=:0 ./tools/godot/godot --display-driver x11 --rendering-driver vulkan --quit
WARNING: Your video card drivers seem not to support the required Vulkan version, switching to OpenGL 3.
```

要让 Forward+ 可用得 `sudo apt install libvulkan1 mesa-vulkan-drivers`（dzn 走 D3D12）；本轮按边界没装系统依赖，2D 项目也**不需要**（Compatibility 更快更稳，且与 Web 导出一致）。

### 2.3 OpenGL：GLX 建不出 3.3，但 GLES 3.1 走得通

```bash
$ DISPLAY=:0 ./tools/godot/godot --path tools/smoke --rendering-driver opengl3 --quit-after 3
ERROR: Condition "ctxErrorOccurred || !gl_display.context->glx_context" is true. Returning: ERR_UNCONFIGURED
   at: _create_context (platform/linuxbsd/x11/gl_manager_x11.cpp:194)
WARNING: Your video card drivers seem not to support the required OpenGL version, switching to OpenGLES.
OpenGL API OpenGL ES 3.1 Mesa 23.2.1-1ubuntu3.1~22.04.4 - Compatibility - Using Device: Microsoft - D3D12 (NVIDIA GeForce RTX 4090)
```

**那条 `glx_context` ERROR 无害**：先试桌面 GL 3.3 → 失败 → 回退 GLES 3.1（Mesa d3d12）→ 正常渲染。看到就当没看见。

### 2.4 X server：有 WSLg，无需 Xvfb

SSH 会话里 `DISPLAY=localhost:10.0`（X11 转发，无 GL）；WSLg 是 `:0`（`/tmp/.X11-unix/X0` 存在）；`which Xvfb` 无（不需要）。**必须显式 `DISPLAY=:0`**，`tools/godot.sh` 会自动纠正。

## 3. headless 冒烟：能跑，出不了图

```bash
$ ./tools/godot.sh --headless --quit
== engine: 4.7.2-stable (official)
== os: Linux | Ubuntu 22.04.5 LTS 22.04
== display_server: headless
== window_size: (0, 0)
== adapter:  | vendor= | api=          ← 没有渲染设备
== utf8: 中文测试 DNF 鬼剑士 洛兰 攻击盒
exit=0
```

冒烟脚本（`tools/smoke/main.gd`：Sprite2D + 64×64 PNG + ~130 行 GDScript）在 headless 下**逻辑全跑通**（导入过的 PNG 加载、字体、打印、退出码 0），但取图为空：

```
== capture: NULL（拿不到图像）
ERROR: Parameter "t" is null. at: texture_2d_get (./servers/rendering/dummy/storage/texture_storage.h:110)
```

**`--headless` = dummy 渲染器，`get_viewport().get_texture().get_image()` 必然为空**——只用于逻辑单测/数据校验/CI 退出码，**任何「出图」验证都必须有窗口**。加 `--rendering-driver opengl3` 也救不了：实测同样 `adapter=` 空。

## 4. 有窗口渲染：能出图（两种方式都验过）

```bash
$ DISPLAY=:0 ./tools/godot/godot --path tools/smoke
== display_server: X11
== window_size: (640, 360)
== adapter: D3D12 (NVIDIA GeForce RTX 4090) | vendor=Microsoft | api=OpenGL ES 3.1 Mesa 23.2.1-1ubuntu3.1~22.04.4
== capture: size=(640, 360) format=5 empty=false
== capture: nonzero_pixels=57600/230400
== capture: save_png err=0 -> .../godot-env-smoke/smoke_offscreen.png
```

更适合视觉回归/录屏的方式：

```bash
$ DISPLAY=:0 ./tools/godot/godot --path tools/smoke --write-movie /tmp/movie/f.png --quit-after 6
Done recording movie at path: /tmp/movie/f.png
4 frames at 60 FPS ... CPU render time: 0.00 seconds (average: 0.12 ms/frame)
$ ls /tmp/movie       # f00000000.png f00000001.png f00000002.png f00000003.png f.wav
```

坑：`DisplayServer.screen_get_image()` 在 **WSLg 返回空**（还报 `Index p_screen = -1 is out of bounds (get_screen_count() = 2)`，要显式传 `0`）；同一 API 在 **Windows 侧正常**（§5 抓到 3840×2160）。**截游戏画面用 viewport capture / `--write-movie`，别用屏幕抓图。**

## 5. 导出 Windows exe

模板**不在**引擎包里，必须单下（1.28 GB）：

```bash
$ curl -L -o /tmp/templates.tpz \
    https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
$ unzip -o -q /tmp/templates.tpz -d /tmp/tpl
$ cp -r /tmp/tpl/templates ~/.local/share/godot/export_templates/4.7.2.stable   # 目录名必须是版本号
$ du -sh ~/.local/share/godot/export_templates/4.7.2.stable
2.0G
```

导出（`tools/smoke/export_presets.cfg`：preset `Windows Desktop`，`embed_pck=true`）：

```bash
$ ./tools/godot/godot --headless --path tools/smoke --export-debug "Windows Desktop" \
    /home/sunmingze/dnf_like/tools/smoke/build/smoke.exe
[ DONE ] savepack
$ file tools/smoke/build/smoke.exe
PE32+ executable (GUI) x86-64 (stripped to external PDB), for MS Windows
$ ls -lh tools/smoke/build/     # smoke.exe 99M（debug；release 更小）+ smoke.console.exe 94K
```

**真在 Windows 上跑过了**（WSL interop 直接执行 exe，`user://` 落到 Windows）：

```bash
$ ./tools/smoke/build/smoke.exe
== capture: nonzero_pixels=57600/230400
== capture: save_png err=0 -> C:/Users/Administrator/AppData/Roaming/Godot/app_userdata/godot-env-smoke/smoke_offscreen.png
== tofu-check default: 中==文 ? false
== screen_get_image: size=(3840, 2160)
```

`.../godot-env-smoke/smoke_report.txt` 里：

```
== os: Windows | Windows 10.0.22631
== display_server: Windows
== adapter: NVIDIA GeForce RTX 4090 | vendor=NVIDIA | api=3.3.0 NVIDIA 616.92
```

坑：导出路径**相对项目目录**解析，传 `tools/smoke/build/x.exe` 会拼成 `tools/smoke/tools/smoke/...` 报 `ERROR: 准备模板: 给定的导出路径不存在。`——**统一传绝对路径**（`tools/godot.sh --export-windows` 已处理）。

### 5.1 Windows 侧能用同一个项目目录吗？能

装了 Windows 版 Godot（同版本 `4.7.2.stable.official.ed1daf0bf`，解压到 `/mnt/c/Users/Public/godot-env/`，173 MB）：

```bash
# A) 项目在 C: 盘 → 正常
$ ./Godot_v4.7.2-stable_win64_console.exe --headless --path 'C:\Users\Public\godot-env\smoke' --import
[ DONE ] loading_editor_layout        exit=0
# B) 项目在 WSL 里（UNC 路径）→ 也能打开并跑脚本
$ ./Godot_v4.7.2-stable_win64_console.exe --headless --path '\\wsl.localhost\Ubuntu-22.04\home\sunmingze\dnf_like\tools\smoke' --quit
== os: Windows | ...   exit=0
```

**但别把项目放 `/mnt/c`**（9p 慢 5 倍）：

| 位置 | `--import` 1,000 张 64×64 PNG |
|---|---|
| WSL ext4 | **3.72 s** |
| `/mnt/c/...`（9p） | **18.73 s** |

**操作方式**：项目/素材放 WSL 侧；要 Windows 原生画面就跑导出的 exe，或用 Windows 版 Godot 打开 `\\wsl.localhost\Ubuntu-22.04\...`（已实测可打开，只读场景够用）。

## 6. 中文显示

不设任何 font override 时，**Linux 与 Windows 都能显示中文**，两个不同汉字位图不同（不是豆腐块）：

```
== tofu-check default: 中==文 ? false      ← Linux（WSLg）与 Windows 导出版都是 false
```

机制是**系统字体回退**：`FontFile.allow_system_fallback` 默认 `true`（*"If set to true, system fonts can be automatically used as fallbacks."* — [FontFile 文档](https://docs.godotengine.org/en/4.7/classes/class_fontfile.html)），本机 Linux 回退 `/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc`、Windows 回退微软雅黑。显式加载也验过：

```
== font msyh load err=0 name=Microsoft YaHei        # load_dynamic_font("/mnt/c/Windows/Fonts/msyh.ttc")
== SystemFont OK, size(中文)=(48.0, 34.0)           # SystemFont(["Microsoft YaHei","Noto Sans SC","WenQuanYi Zen Hei"])
```

两个坑：① **绝对路径跨平台必死**——Windows 侧同脚本 `err=0` 但 `name=` 空、日志 `ERROR: Can't open file from path '/mnt/c/Windows/Fonts/msyh.ttc'`，**字体要放 `res://` 打包**；② **别赌目标机有 CJK 字体**（精简 Linux/容器可能没有），`/mnt/c/Windows/Fonts/` 里的 `NotoSansSC-VF.ttf`（OFL，可合法打包）放进 `res://` 做第一层 fallback，`SystemFont` 只当兜底。

## 7. 目录约定

```
dnf_like/
├── tools/{godot/ 引擎(140MB, 不进 git), godot.sh 唯一入口, smoke/ 环境冒烟工程, *.py 数据管线}
├── src/game/       # ← Godot 项目根：project.godot / *.gd / *.tscn / *.tres / 字体
├── export/         # 外部资源：解包 PNG、图集、ANI 表（不进 res://）
└── docs/ analysis/ data/ logs/
```

1. **`src/game/project.godot` 是项目根**，`res://` = `src/game/`；只放代码、场景、UI 主题、字体和少量必须进 pck 的东西。
2. **`export/` 永远在 `res://` 之外**：几十万文件放进 `res://` 会拖垮导入与编辑器（1,000 文件在 9p 上就 5×）。运行时读绝对路径：
   ```gdscript
   var base := ProjectSettings.globalize_path("res://").path_join("../../export")   # 开发期
   var img := Image.load_from_file(base.path_join("atlas/swordman/body.png"))
   ```
   发行时图集打成 `.pck` 追加包（`--export-pack`）或放 exe 同目录，用 `OS.get_executable_path().get_base_dir()` 定位。
3. **`user://` 只放存档/日志/截图**：Linux `~/.local/share/godot/app_userdata/<项目名>/`，Windows `C:/Users/<用户>/AppData/Roaming/Godot/app_userdata/<项目名>/`。
4. 项目别放 `/mnt/c`；导出的 exe 拷到 `C:` 或留 WSL 里跑（interop 可用）都行。

## 8. 坑清单（本轮真踩到的）

| # | 坑 | 现象 | 处理 |
|---|---|---|---|
| 1 | 脚本解析失败时**进程不退出** | 起窗口后干等直到 timeout | 永远带 `--quit-after N` 或 `timeout`；CI 用 `--headless --quit` 看退出码 |
| 2 | `_log()` 实参多于声明 | `Parse Error: Too many arguments for "_log()" call. Expected at most 5 but received 6.` → `Failed to load script "res://main.gd"` | GDScript 无 varargs：固定几个可选参数或传 Array |
| 3 | PNG 未导入就跑 | `No loader found for resource: res://icon64.png (expected type: Texture2D)` | 先 `--headless --import`（或开一次编辑器） |
| 4 | 导出路径按相对项目目录解析 | `给定的导出路径不存在` | 传绝对路径 |
| 5 | `screen_get_image()` | WSLg 返回空 / `p_screen = -1` 越界 | 传 `0`；WSLg 下改用 viewport capture |
| 6 | GLX `ctxErrorOccurred` 红字 | 每次启动都报 | 无害（回退 GLES 3.1），别当故障 |
| 7 | SSH 的 `DISPLAY=localhost:10.0` | 起窗口建不出上下文 | `DISPLAY=:0`（`godot.sh` 自动纠正） |
| 8 | 字体写绝对路径 | Windows 侧静默失败（err=0 但 name 空） | 字体进 `res://` |
| 9 | 项目放 `/mnt/c` | 导入慢 5× | 项目留 WSL ext4 |

## 9. 开工清单（P3 直接用）

```bash
./tools/godot.sh --version                  # 4.7.2.stable.official.ed1daf0bf
./tools/godot.sh --headless --quit          # 冒烟，exit=0
./tools/godot.sh                            # WSLg 窗口跑当前项目
./tools/godot.sh --editor                   # 打开编辑器
./tools/godot.sh --quit-after 120           # 跑 120 帧自动退出
./tools/godot.sh --write-movie /tmp/f.png --quit-after 6   # PNG 序列（视觉回归）
./tools/godot.sh --export-windows           # → build/windows/<项目名>.exe
```

- `src/game/project.godot` 建好后 `godot.sh` 自动指向它；在那之前回退 `tools/smoke` 冒烟工程（随时自查环境）。
- 建议项目设置：`renderer/rendering_method="gl_compatibility"`、`textures/canvas_textures/default_texture_filter=0`（Nearest）、`display/window/stretch/scale_mode="integer"`。
- 磁盘：引擎 140 MB + 模板 2.0 GB（一次性）+ Windows 编辑器 173 MB（可选）。

**验证者**：godot-scout（团队 dnf-like，任务 t13 / attempt `aed25df5…`）。
