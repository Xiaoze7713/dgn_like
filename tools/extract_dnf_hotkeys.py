"""从客户端 PVF 导出 DNF 官方键位动作表 → Godot 工程 data/dnf_hotkeys.json

数据源：Script.pvf:clientonly/hotkeysystem_ver3.co（34.3.13.22，7,345 B）
每条记录：`[key]` + 名称 + 动作 id(Ixx) + 分类(system/character/dungeon/quickchat)
          + 左右列(left/right/hide) + 默认键位(客户端留空) + 类型(NormalType/…)

同一个动作 id 会按类型重复出现（NormalType / CommonType / CreatorType），
导出时按 (id) 去重，保留第一次出现的 NormalType/CommonType 名称。

用法：
    python3 tools/extract_dnf_hotkeys.py [--out dnf_like/data/dnf_hotkeys.json]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import pvf_new_extract as X  # noqa: E402

PVF = ROOT / "analysis/pvf-new/inner/Script.inner.pvf"
SRC = "clientonly/hotkeysystem_ver3.co"

ROW_RE = re.compile(
    r"\[key\]\s*\n\s*(\S[^\n`]*?)\s+`([^`]*)`\s+`([^`]*)`\s+`([^`]*)`\s+`([^`]*)`\s+`([^`]*)`"
)


def extract() -> dict:
    p = X.NewPvf(str(PVF))
    l10n = X.L10n(p)
    text = X.decode_script(p.read_by_path(SRC), p.resolve, ref=l10n)

    seen: dict[str, dict] = {}
    for name, hid, scope, side, bound, typ in ROW_RE.findall(text):
        name = name.strip()
        # 优先 NormalType/CommonType 的命名，CreatorType/AradRoyalRumble 只是变体
        if hid in seen and typ in ("CreatorType", "AradRoyalRumbleCommonType"):
            continue
        seen[hid] = {
            "id": hid,
            "name": name,
            "scope": scope,
            "side": side,
            "type": typ,
            "default_key": bound.strip(),
        }
    order = {"character": 0, "dungeon": 1, "system": 2, "quickchat": 3}
    entries = sorted(seen.values(), key=lambda e: (order.get(e["scope"], 9), e["id"]))
    return {
        "source": f"Script.pvf:{SRC}",
        "client_version": "34.3.13.22",
        "note": "默认键位在客户端是可配置项，本表从数据里导出的是空；default_key 恒为空字符串。",
        "count": len(entries),
        "entries": entries,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "dnf_like/data/dnf_hotkeys.json"))
    args = ap.parse_args()
    data = extract()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    scopes: dict[str, int] = {}
    for e in data["entries"]:
        scopes[e["scope"]] = scopes.get(e["scope"], 0) + 1
    print(f"{out}: {data['count']} 条  {scopes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
