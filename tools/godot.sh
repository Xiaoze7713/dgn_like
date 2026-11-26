#!/usr/bin/env bash
# tools/godot.sh —— 统一 Godot 启动封装（Godot 4.7.2 / WSL2）
#
# 用法：
#   tools/godot.sh --version                 # 只打印引擎版本
#   tools/godot.sh --headless --quit         # headless 冒烟（CI 用，退出码即结论）
#   tools/godot.sh                           # 用 WSLg 窗口跑当前项目
#   tools/godot.sh --editor                  # 打开编辑器（会弹 WSLg 窗口）
#   tools/godot.sh --quit-after 120          # 跑 120 帧后自动退出（出图/冒烟用）
#   tools/godot.sh --write-movie /tmp/f.png --quit-after 6   # 导出 PNG 序列（视觉回归）
#   tools/godot.sh --export-windows [输出目录]                # 导出 Windows exe
#
# 可覆盖的环境变量：
#   GODOT_BIN       引擎可执行文件（默认 tools/godot/godot）
#   GODOT_PROJECT   项目目录（默认 src/game；不存在时回退 tools/smoke）
#   GODOT_DISPLAY   WSLg 显示号（默认 :0）
#   GODOT_RENDER    渲染后端（默认 opengl3；WSL2 里 Vulkan 不可用）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$ROOT/tools/godot/godot}"
RENDER="${GODOT_RENDER:-opengl3}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "找不到 Godot 可执行文件：$GODOT_BIN" >&2
  echo "首次使用请先下载 4.7.2-stable Linux 包并解压到 tools/godot/（见 docs/GODOT-ENV.md）" >&2
  exit 127
fi

# 项目目录
PROJECT="${GODOT_PROJECT:-$ROOT/client}"
if [[ ! -f "$PROJECT/project.godot" ]]; then
  PROJECT="$ROOT/tools/smoke"
  [[ -f "$PROJECT/project.godot" ]] || { echo "没有可运行的项目（client/ 与 tools/smoke 都不存在）" >&2; exit 3; }
  echo "[godot.sh] client/ 还没有 project.godot，回退到 tools/smoke 冒烟工程" >&2
fi

# 参数分流
args=()
headless=0
editor=0
export_win=0
want_version=0
for a in "$@"; do
  case "$a" in
    --version|-v) want_version=1 ;;
    --headless)   headless=1 ;;
    --editor|-e)  editor=1 ;;
    --export-windows) export_win=1 ;;
  esac
  args+=("$a")
done

if (( want_version )); then
  exec "$GODOT_BIN" --version
fi

# WSLg：SSH 会话里 DISPLAY 常是 localhost:10.0（X11 转发，无 GL），需要切到 :0
if (( ! headless )); then
  if [[ -z "${DISPLAY:-}" || "${DISPLAY}" == *":10."* || "${DISPLAY}" == "localhost:"* ]]; then
    if [[ -S /tmp/.X11-unix/X0 ]]; then
      export DISPLAY="${GODOT_DISPLAY:-:0}"
      echo "[godot.sh] DISPLAY -> $DISPLAY（WSLg）" >&2
    fi
  fi
fi

if (( export_win )); then
  # 用法：tools/godot.sh --export-windows [outdir]
  outdir="${2:-$ROOT/build/windows}"
  mkdir -p "$outdir"
  preset="${GODOT_EXPORT_PRESET:-Windows Desktop}"
  if [[ ! -f "$PROJECT/export_presets.cfg" ]]; then
    echo "项目缺少 export_presets.cfg（preset: $preset）" >&2; exit 4
  fi
  exec "$GODOT_BIN" --headless --path "$PROJECT" --export-release "$preset" "$outdir/$(basename "$PROJECT").exe"
fi

if (( editor )); then
  exec "$GODOT_BIN" --path "$PROJECT" --editor
fi

# headless：不要传渲染参数（headless 用 dummy 渲染器，传了也无害但没必要）
if (( headless )); then
  exec "$GODOT_BIN" --path "$PROJECT" "${args[@]}"
fi

# 有窗口：默认 opengl3（WSL2 无 Vulkan，Forward+ 会失败并回退）
has_render=0
for a in "${args[@]}"; do [[ "$a" == "--rendering-driver" || "$a" == --rendering-* ]] && has_render=1; done
if (( has_render )); then
  exec "$GODOT_BIN" --path "$PROJECT" "${args[@]}"
else
  exec "$GODOT_BIN" --path "$PROJECT" --rendering-driver "$RENDER" "${args[@]}"
fi
