#!/usr/bin/env bash
# 起 PVF 浏览器（tmux 里跑，别挂在前台——DSH 重启会把前台进程带走）
set -euo pipefail
cd "$(dirname "$0")/../.."

PORT="${PORT:-8770}"
SESS=pvfbrowser

if ! [ -f analysis/pvf-new/pvf34.tree.sqlite ]; then
    echo "[1/2] 建目录索引（约 42 秒）"
    python3 tools/pvf_browser/build_tree.py
fi

tmux kill-session -t "$SESS" 2>/dev/null || true
tmux new-session -d -s "$SESS" \
    "cd '$PWD' && python3 tools/pvf_browser/serve.py --port '$PORT' --decode > /tmp/pvfbrowser.log 2>&1"

for i in $(seq 1 60); do
    if curl -sf "http://127.0.0.1:${PORT}/api/stats" >/dev/null 2>&1; then
        echo "PVF 浏览器已就绪: http://127.0.0.1:${PORT}"
        exit 0
    fi
    sleep 1
done
echo "启动超时，看看 /tmp/pvfbrowser.log" >&2
tail -20 /tmp/pvfbrowser.log >&2 || true
exit 1
