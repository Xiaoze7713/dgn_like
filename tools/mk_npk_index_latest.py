"""扫最新国服客户端的 ImagePacks2 -> 运行时索引（与 mk_npk_index.py 同格式）。

用法：python3 tools/mk_npk_index_latest.py
输出：analysis/pvf-new/npk-index.jsonl.gz + /mnt/e/godot_proj/dnf_like/assets/npk-index-latest.bin
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mk_npk_index as base

base.PACK = "/mnt/d/WeGameApps/rail_apps/地下城与勇士：创新世纪(1)/ImagePacks2"
base.OUT_JSONL = "analysis/pvf-new/npk-index.jsonl.gz"
base.OUT_BIN = "/mnt/e/godot_proj/dnf_like/assets/npk-index-latest.bin"

if __name__ == "__main__":
    sys.exit(base.main())
