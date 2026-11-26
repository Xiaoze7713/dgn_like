#!/usr/bin/env python3
"""删除翻译后 .gd 里与基类 SqrConsts 重名的常量声明。

原版 Squirrel 里每个 .nut 的顶层 slot 都落在同一个全局命名空间，
所以同一个常量可能在头文件和技能脚本里各写一遍。
GDScript 里 `SqrScript extends SqrConsts`，子类再声明同名常量会报
`The member "X" already exists in parent class SqrConsts.`。

处理规则：
- 值与 SqrConsts 相同的 `const NAME := v` → 删掉，留一行注释说明它在基类；
- 值不同的 → 保留原行但包在注释里，并标 `# 【译注】与基类同名但取值不同`，
  让人工决定（这种情况目前为 0）。
- 只处理 `const`，不动 `var`（但宿主全局对象占位 `var X = null` 会删掉，
  因为 X 已在 SqrConsts 里声明，子类重声明会报 already exists）。

用法：python3 tools/sqr_dedupe_consts.py [--check] [路径...]
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONSTS = ROOT / "sqr_gd" / "sqr_consts.gd"
DECL = re.compile(r"^const\s+([A-Za-z_]\w*)\s*:=\s*(-?\d+)\s*(?:#.*)?$")
# 宿主全局对象：基类已声明，子类不能再 `var X = null`
HOST_VAR = re.compile(r"^var\s+([A-Za-z_]\w*)\s*=\s*null\s*(?:#.*)?$")


def load_consts() -> dict[str, str]:
    vals: dict[str, str] = {}
    for line in CONSTS.read_text(encoding="utf-8").splitlines():
        m = DECL.match(line)
        if m:
            vals[m.group(1)] = m.group(2)
    return vals


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    consts = load_consts()
    files = [Path(a) for a in args] or sorted((ROOT / "sqr_gd").rglob("*.gd"))
    stripped = conflicts = 0
    for f in files:
        if f.name in ("sqr_consts.gd", "sqr_script.gd", "sqr_globals.gd"):
            continue
        lines = f.read_text(encoding="utf-8").splitlines(keepends=True)
        changed = False
        out = []
        for line in lines:
            hv = HOST_VAR.match(line.rstrip("\n"))
            if hv and hv.group(1) in ("IRDSQRCharacter", "IRDSUltimateSkill",
                                      "CNSquirrelAppendage", "CNAvenger"):
                keepline = line[: len(line) - len(line.lstrip())]
                out.append(f"{keepline}# {hv.group(1)} = null：宿主全局对象在基类 SqrConsts 里\n")
                stripped += 1
                changed = True
                continue
            m = DECL.match(line.rstrip("\n"))
            if not m or m.group(1) not in consts:
                out.append(line)
                continue
            name, val = m.group(1), m.group(2)
            if consts[name] == val:
                keepline = line[: len(line) - len(line.lstrip())]
                out.append(f"{keepline}# {name} = {val}：常量在基类 SqrConsts 里\n")
                stripped += 1
            else:
                out.append(f"# {line.rstrip()}\n{line[: len(line) - len(line.lstrip())]}# 【译注】与基类同名但取值不同（基类={consts[name]}）\n")
                conflicts += 1
            changed = True
        if changed and not check:
            f.write_text("".join(out), encoding="utf-8")
    print(f"删除重复常量 {stripped} 处，取值冲突 {conflicts} 处" + ("（--check 未写入）" if check else ""))
    return 1 if conflicts else 0


if __name__ == "__main__":
    raise SystemExit(main())
