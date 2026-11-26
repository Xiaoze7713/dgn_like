#!/usr/bin/env bash
# 翻译批次的统一闸门：去重常量 → 重建桩表 → 交叉引用 → 同步 → Godot 运行时加载检查
# 用法：./tools/sqr_gate.sh            （全量）
set -uo pipefail
cd "$(dirname "$0")/.."

echo "== 1/5 常量表"
python3 tools/sqr_consts.py || exit 1
echo "== 2/5 去重 const"
python3 tools/sqr_dedupe_consts.py || exit 1
echo "== 3/5 桩表 + 交叉引用"
python3 tools/sqr_stubs.py || exit 1
python3 tools/sqr_xref.py || exit 1
echo "== 4/5 同步到 Godot 工程"
rsync -a --delete --exclude '.godot' sqr_gd/ /mnt/e/godot_proj/dnf_like/sqr_gd/ || exit 1
echo "== 5/5 运行时加载检查"
XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
  ./tools/godot.sh --headless --script res://tests/check_sqr.gd 2>&1 \
  | grep -E "^(FAIL|=== 共)" 
