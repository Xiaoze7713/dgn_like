# GDScript Logger（可直接拷走）

仿服务端的日志组件：**终端 + 文件双 sink**、**TEXT / JSON 双格式**、**trace→fatal 级别**、
**每条日志带调用点 `file:line in func`**、**WARN 及以上自动附栈**，再加上一个
**运行时常量 / 环境组件 `Env`**（dev / test / staging / prod）。

## 文件清单

| 文件 | 作用 |
| --- | --- |
| `core/log/log_core.gd` | 核心（`class_name LogCore`）：级别、格式化、字段清洗、文件轮转。不依赖 autoload，可单独 `new()`。 |
| `core/log/log_tag.gd` | 带 tag 的子 logger（`class_name LogTag`），`Log.tag("Net").warn(...)`。 |
| `core/log/log.gd` | autoload `Log`：全项目调用的门面，带终端+文件两个 sink。 |
| `core/app_env.gd` | autoload `Env`：环境判定、版本号、平台、按环境分档的常量、日志配置。 |
| `tests/test_logger.gd` | 自测（42 项断言），跑法见文末。 |

把 `core/log/` 和 `core/app_env.gd` 拷进你的工程，再在 `project.godot` 注册两个 autoload（顺序：Env 在前）：

```ini
[autoload]

Env="*res://core/app_env.gd"
Log="*res://core/log/log.gd"
```

> 注意：Godot 4 自带一个全局类 `Logger`，所以核心类叫 `LogCore`，别改名成 `Logger`。

## 用法

```gdscript
# 各处直接调，不需要 import（autoload 全局可用）
Log.debug("加载关卡", {"id": 3, "ms": 12})
Log.info("进入战斗")
Log.warn("帧率偏低", {"fps": 21})            # 自动带栈
Log.error("存档写入失败", {"slot": 2})
Log.fatal("显存不足，退出")

# 第二个参数传 dict = 结构化字段；传字符串 = tag
Log.info("登录成功", {"uid": 10086})
Log.info("网络重连", "Net")                  # tag = Net
Log.tag("Net").warn("丢包", {"loss": 0.12})  # 等价写法

# 错误码：自动补 err / err_id 两个字段
var f := FileAccess.open("user://save.json", FileAccess.READ)
if f == null:
	Log.exc("打开存档失败", FileAccess.get_open_error(), {"path": "user://save.json"})

# 整个 dict 当消息：抽走 "msg"/"message"/"tag"，剩下的进 fields
Log.info({"msg": "任务完成", "quest": 42})

# 条件判断，避免无谓的字符串拼接
if Log.is_enabled(Log.Level.DEBUG):
	Log.debug("脏数据", {"dump": heavy_debug_dump()})
```

### 运行时切换

```gdscript
Log.set_level("warn")        # 只留 warn 及以上
Log.set_format("json")       # 同时切终端和文件（-1 跟随的都被覆盖）
Log.setup({                  # 细粒度覆盖任意配置项
	"level": "debug",
	"console_format": "text",  # 终端人读
	"file_format": "json",     # 文件给 jq / 采集器吃
	"file_enabled": true,
	"file_path": "user://logs/game-{env}-{date}.log",
	"use_color": true,
})
Log.flush()                  # 立刻刷盘（崩溃前/退出前建议调一次）
```

## 输出长什么样

TEXT（终端，`show_source=true`，WARN 起带栈）：

```
2026-11-13 16:28:51.256 [WARN ] [test] [Net] 丢包 loss=0.12  (res://net/client.gd:88 in _on_drop)
	at _on_drop (res://net/client.gd:88)
	at _process (res://net/client.gd:41)
2026-11-13 16:28:51.257 [ERROR] [test] 打开存档失败 path="user://save.json" err="File not found" err_id=7  (res://save/save.gd:12 in load_game)
```

JSON（一行一条，直接 `jq` / 进 ELK）：

```json
{"ts":"2026-11-13 16:28:51.256","level":"WARN","level_id":3,"env":"test","app":"dnf_like","ver":"0.1.0",
 "tag":"Net","msg":"丢包","file":"res://net/client.gd","line":88,"func":"_on_drop",
 "stack":[{"fn":"_on_drop","file":"res://net/client.gd","line":88}],
 "fields":{"loss":0.12},"frame":120}
```

TEXT 里 ERROR / FATAL 走 `printerr`（进 stderr），方便 CI 抓；改 `errors_to_stderr=false` 可都走 stdout。

## Env：环境与常量

```gdscript
if Env.is_prod:
	disable_cheat()
print(Env.env_name, Env.version, Env.build, Env.platform, Env.is_editor)
print(Env.cfg("server_url"), Env.cfg("allow_cheat", false))
print(Env.summary())          # 一行拿全，日志启动时打出来很方便
```

* 判定优先级：命令行 `--env=test` / `--test` / `--prod` … → `project.godot` 的 `app/env`
  → 导出的 feature tag `test|staging|prod` → 自动（编辑器=dev、debug 包=test、release 包=prod）。
* 常量表在 `core/app_env.gd` 的 `PROFILES`，日志项用 `log/` 前缀；同名 `ProjectSettings`
  项（`app/server_url`）会盖掉 `PROFILES`，方便打包时按渠道覆盖。
* `Env` 的 `_ready()` 会自动调 `Log.configure_from_env()`，即日志默认配置来自当前环境的 profile。

命令行直接调日志（不用改代码，QA 常用）：

```bash
godot --path src/game -- --env=test --log-level=warn --log-json
godot --path src/game -- --log-file=user://logs/dump.log --log-stack=3 --log-no-color
```

支持：`--env=` `--log-level=` `--log-file=` `--log-stack=` `--log-json` `--log-text`
`--log-color` `--log-no-color` `--log-file-off`。

## 配置项（`Log.setup()` / `LogCore` 字段）

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `level` | `debug` | trace/debug/info/warn/error/fatal/off，数字或字符串都行 |
| `format` | `text` | 兜底格式 |
| `console_format` / `file_format` | `-1` | `-1` = 跟随 `format`，否则 `text`/`json` |
| `use_color` | `true` | 只影响 TEXT 终端；headless 自动关 |
| `show_source` | `true` | 是否追加 `(file:line in func)` |
| `show_stack` | `8` | TEXT 最多打几帧；`0` = 不打 |
| `stack_min_level` | `warn` | 哪级起采集/打印栈 |
| `capture_stack` | `true` | 关掉则任何级别都不采栈 |
| `errors_to_stderr` | `true` | ERROR/FATAL 走 `printerr` |
| `engine_report` | `false` | 同时 `push_warning/push_error`，编辑器调试器里断得上 |
| `json_pretty` | `false` | 多行 JSON；默认一行一条 |
| `startup_log` | `true` | 启动打一行 `[boot] logger ready ...` |
| `file_enabled` | `false` | 是否写文件 |
| `file_path` | `user://logs/{app}-{env}-{date}.log` | 支持 `{app}` `{env}` `{date}`；跨天自动换文件 |
| `file_max_bytes` | `8MB` | 超过就轮转 `.1 .2 …` |
| `file_max_backups` | `5` | 保留几个备份 |
| `file_flush` | `true` | 每条 flush |

字段清洗：Vector/Color/Node 之类不能进 JSON 的值会自动转成可序列化形式
（`Vector2` → `"(1, 2)"`、`Object` → `"<Node#id>"`、Packed 数组 → 普通数组、NaN → `"NaN"`），
嵌套深度上限 6 层，不会因为一次 `Log.info(..., {"node": self})` 炸掉。

## 已知限制（engine 给的，不是实现问题）

* `get_stack()` 在**导出 release 包**里返回空数组 → 出包后调用点 file:line 和栈会缺失（编辑器/debug 包正常）。
  排查线上问题时用 debug 包或自己把关键位置写进 fields。
* 文件 sink 用 `FileAccess` + `Mutex`，非线程安全场景（多线程同时写）也够用；单条写入是原子的。
* 日志目录默认在 `user://logs/`（桌面 Linux 是 `~/.local/share/godot/app_userdata/<项目名>/logs/`）。

## 自测

```bash
cd /home/sunmingze/dnf_like
XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT="$PWD/src/game" \
  ./tools/godot.sh --headless --script res://tests/test_logger.gd
# 期望：==== 42 ok, 0 fail ====，退出码 0
```

覆盖：级别过滤、5 级序列、JSON 结构、调用点 file/line/func、WARN 栈、`--` 无 tag 键、
tag 子 logger、`exc` 错误码、dict 当消息、脏字段清洗（Vector2/Object/Packed/NaN）、
TEXT sink 与栈帧上限、按字节轮转、关文件 sink、`LogTag`。
