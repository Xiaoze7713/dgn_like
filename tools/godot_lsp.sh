#!/usr/bin/env bash
# 常驻 GDScript Language Server（VSCode 扩展 godot-tools 用 attach 模式连 127.0.0.1:6009）
#
# 背景：Windows 版 Godot 编辑器 6005 端口上的 LSP 只报 Windows 路径（E:/godot_proj/dnf_like），
# WSL 里的 VS Code 扩展拿 WSL 路径做 workspace 校验，永远 mismatch → 直接 rejected，所有跳转/补全失效。
# 而扩展自带的 headless 模式要现拉一个 Godot：本项目在 /mnt/e 上冷启动要 ~80s 才开 LSP 端口，
# 超过扩展 autoReconnect 的 10×3s 预算。所以把服务常驻在 tmux 里，扩展只负责连。
#
#   ./tools/godot_lsp.sh start    启动（已在跑就返回）
#   ./tools/godot_lsp.sh status   看状态
#   ./tools/godot_lsp.sh restart  重启
#   ./tools/godot_lsp.sh stop     停
set -uo pipefail

PORT=${GODOT_LSP_PORT:-6009}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJECT=${GODOT_PROJECT:-$ROOT/client}
GODOT=${GODOT_BIN:-$ROOT/tools/godot/godot}
LOG=${GODOT_LSP_LOG:-/tmp/godot_lsp.log}
SESSION=godot_lsp

port_up() { ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | grep -q ":$PORT$"; }

start() {
    if port_up; then echo "[godot_lsp] 已在 127.0.0.1:$PORT 上运行"; return 0; fi
    tmux kill-session -t "$SESSION" 2>/dev/null
    tmux new-session -d -s "$SESSION" \
        "while :; do cd '$PROJECT' && '$GODOT' --headless --editor --path '$PROJECT' --no-window --lsp-port $PORT >> '$LOG' 2>&1; echo \"[godot_lsp] exited \$? at \$(date -Is), respawn...\" >> '$LOG'; sleep 3; done"
    echo "[godot_lsp] 启动中（首次约 20-80s 才监听端口）"
    echo "            tmux: $SESSION   日志: $LOG   端口: 127.0.0.1:$PORT"
    return 0
}

stop() {
    tmux kill-session -t "$SESSION" 2>/dev/null && echo "[godot_lsp] 已停" || echo "[godot_lsp] 没在跑"
}

status() {
    if port_up; then
        echo "[godot_lsp] 端口 127.0.0.1:$PORT 在监听"
        tmux has-session -t "$SESSION" 2>/dev/null && echo "           tmux session $SESSION 在"
    else
        echo "[godot_lsp] 端口 127.0.0.1:$PORT 没监听"
        tmux has-session -t "$SESSION" 2>/dev/null && echo "           （tmux session 在，但还在启动/已卡住）"
    fi
    tail -n 3 "$LOG" 2>/dev/null | sed 's/^/           /'
}

case "${1:-start}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *) echo "用法: $0 {start|stop|restart|status}"; exit 2 ;;
esac
