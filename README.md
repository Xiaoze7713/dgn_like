# dgn_like

一个 **2D / 2.5D 横版刷子游戏**，用 Godot 4.7 实现。

核心循环：**进图 → 清怪 → 掉落 → 结算 → 回城**。视角是横版 2D，y 轴同时当景深用（y 越大越靠前），靠分层贴图做出 2.5D 的观感。

数据侧解析 DNF 客户端的资源包（PVF 文本/数值/脚本、NPK 图集/动画）作为素材与规则来源；**运行时直接读原包，不预烘焙**，所以换一份客户端数据就能换一整套内容。

## 现在有什么

| 模块 | 位置 | 状态 |
|---|---|---|
| 世界运行时 | `client/game/world/` | 城镇/副本装载、地砖与背景层、pass 网格（可走/阻挡）、NPC 立绘、玩家跑跳、相机跟随、多级缓存 |
| 早期垂直切片 | `client/game/sf85/` | 单房间 + 角色多图层动画 + 怪物 + HUD + 伤害数字（原型保留，作对照） |
| UI 组件库 | `client/ui/` | Control + `_draw` 手绘的物品栏（8×6）、装备槽、金库（14×6）、HUD、主题；`ui/ui_demo.tscn` 可单独跑 |
| 基础设施 | `client/core/` | 环境探测 `Env`、日志 `Log`、配置、常量、输入映射 |
| 测试 | `client/tests/` | 世界冒烟、地图审计、NPK/DDS/DXT 回归、按键、截图等，headless 可跑 |
| 工具链 | `tools/` | PVF 解析导出、ANI 解码、NPK 图集查看、地图内容包编译、引用图 |
| 文档 | `docs/` | 格式规格、地图踩坑、路线图；入口 `docs/KB-INDEX.md` |

## 目录

```
client/        Godot 工程（res:// 根）
  core/        环境 / 日志 / 配置 / 常量 / 输入
  game/
    world/     世界运行时：装载城镇与副本、建图、渲染、玩家、缓存
    sf85/      早期垂直切片：单房间 + 角色 + 怪物 + HUD
  scenes/      主场景 world.tscn、切片场景
  ui/          横版动作游戏风格的 UI 组件库
  tests/       headless 冒烟与回归脚本
tools/         Python / Shell / 前端工具：PVF、NPK、ANI、地图
docs/          规格与踩坑文档（KB-INDEX.md 是入口）
analysis/      分析结论（只收 md，原始数据不入库）
```

## 跑起来

环境：**Godot 4.7.2**（Linux 版，WSLg 下能出窗口；WSL2 里 Vulkan 不可用，统一走 Compatibility / opengl3）。引擎本体不入库，按 `docs/GODOT-ENV.md` 下载后解压到 `tools/godot/`。

```bash
# 0. 首次：先导入一次，生成资源与脚本类缓存
#    （少了这步直接跑会报 Identifier "WorldFont" not declared 之类的假错误）
XDG_DATA_HOME=$PWD/.tmp_udata ./tools/godot.sh --headless --import

# 1. 开窗口跑主场景
XDG_DATA_HOME=$PWD/.tmp_udata ./tools/godot.sh

# 2. 冒烟（headless，退出码即结论）
XDG_DATA_HOME=$PWD/.tmp_udata ./tools/godot.sh --headless --script res://tests/world_smoke.gd

# 3. 出图（需要 WSLg 窗口）
XDG_DATA_HOME=$PWD/.tmp_udata ./tools/godot.sh --script res://tests/world_shot.gd
```

`tools/godot.sh` 默认跑 `client/`；换项目用 `GODOT_PROJECT=/path/to/project`。

**运行时数据**：地图、动画、图集都从客户端原包现读，路径常量在 `client/game/world/flow/world_director.gd` 顶部（默认 `Script.pvf` 与 `ImagePacks2`）。没有这份数据时工具和文档仍可用，游戏跑到装载地图那步会报错。

## 资源为什么不入库

`Script.pvf`（200 MB+）、`ImagePacks2`、导出的图集、分析用的 sqlite（十几 GB）都是本地数据，仓库只放**源码 / 工具 / 文档**。`.gitignore` 里逐条排掉了，仓库体积控制在 10 MB 量级。要跑起来请自备一份客户端数据，并按上面的路径常量指过去。

## 约定

- 每个有实现的目录维护一份 `README.md`（这层能做什么、对外入口签名、调用关系、验证命令、已知坑）；改代码时在同一次改动里更新。
- 改公式 / 常量 / 正则前先 grep 关联点——同一条规则常有第二份实现（城镇 vs 副本、基础 vs 扩展地砖、背景 vs 装饰）。
- 验证要两类都跑：逻辑冒烟 + 视觉截图；不该变的那张用 sha256 比对。
- 文档入口 `docs/KB-INDEX.md`，踩坑记录 `docs/PVF-MAP-PITFALLS.md`。
