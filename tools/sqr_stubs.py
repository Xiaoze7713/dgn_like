#!/usr/bin/env python3
"""重新生成 `sqr_gd/sqr_script.gd` 的宿主 API 桩表。

为什么需要：原脚本的调用签名很随意（`sq_CreateParticle` 有 9 个参数、
`sq_FindShootingTarget` 有 13 个），GDScript 的参数个数是硬约束。
所以桩统一开 **16 个带默认值的参数**，兼容任何调用长度。

同时会扫一遍翻译后的 `.gd`，把「裸调用但哪儿都没定义」的名字补成宿主内建桩
（`printc` / `isSameObject` / `setCurrentAnimationFromCutomIndex` 这类
在原版里是 C++ 直接注入 self 的方法）。

用法：
  python3 tools/sqr_stubs.py            # 重新生成并打印新增的宿主内建
  python3 tools/sqr_stubs.py --check    # 只报告缺哪些名字，不写文件
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GD = ROOT / "sqr_gd"
SCRIPT = GD / "sqr_script.gd"
GLOBALS = GD / "sqr_globals.gd"
MANIFEST = ROOT / "analysis" / "sqr" / "manifest.json"

ARGS = ", ".join(f"_a{i} = null" for i in range(1, 17))

KEYWORDS = {
    "if", "else", "elif", "for", "while", "match", "func", "return", "var", "const",
    "or", "and", "not", "in", "is", "null", "true", "false", "self", "await", "break", "continue",
    "print", "printt", "prints", "printerr", "str", "int", "float", "bool", "range",
    "len", "abs", "max", "min", "clamp", "round", "floor", "ceil", "sqrt", "pow",
    "sin", "cos", "tan", "randi", "randf", "sign", "typeof", "is_instance_valid",
    "load", "preload", "Vector2", "Vector3", "Color", "Rect2", "Array", "Dictionary",
    "String", "Callable", "PackedByteArray", "lerp", "snapped", "wrapf", "clampf",
    "maxf", "minf", "absi", "maxi", "mini", "posmod", "deg_to_rad", "rad_to_deg",
    "assert", "push_error", "push_warning", "instance_from_id", "weakref",
}

BLOCKED = {"sq_AddFunctionName", "sq_AddEffect", "_stub", "_init"}

HOST_HEADER = """
# ---------------------------------------------------------------------------
# 宿主内建：原版里这些方法由 C++ 直接注入到 self 上（不经过 sq_ 前缀），
# 脚本里是裸调用。这里补同样签名的空实现，让翻译后的脚本能编译。
# 名称与语义见 `docs/SQR-API.md`。
# ---------------------------------------------------------------------------
"""


def collect_manifest() -> list[str]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    names = data if isinstance(data, list) else (data.get("api") or data.get("apis") or [])
    if names and isinstance(names[0], dict):
        names = [n["name"] for n in names]
    return sorted(set(n for n in names if isinstance(n, str) and n.startswith("sq_")))


def defined_in(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return set(re.findall(r"^func\s+(\w+)", path.read_text(encoding="utf-8"), re.M))


def strip_comments(text: str) -> str:
    """去掉 `#` 之后的注释（不碰字符串里的 #），避免把注释里的 foo() 当成裸调用。"""
    out = []
    for line in text.splitlines():
        q = None
        cut = len(line)
        i = 0
        while i < len(line):
            ch = line[i]
            if q:
                if ch == "\\":
                    i += 2
                    continue
                if ch == q:
                    q = None
            elif ch in "\"'":
                q = ch
            elif ch == "#":
                cut = i
                break
            i += 1
        out.append(line[:cut])
    return "\n".join(out)


def scan_bare_calls() -> set[str]:
    """找 `foo(...)` 这种裸调用，且本文件没定义、全局也没有的。"""
    globals_defined = defined_in(GLOBALS) | defined_in(SCRIPT)
    missing: dict[str, str] = {}
    for f in sorted(GD.rglob("*.gd")):
        if f in (SCRIPT, GLOBALS):
            continue
        text = strip_comments(f.read_text(encoding="utf-8"))
        local = set(re.findall(r"^func\s+(\w+)", text, re.M))
        local |= set(re.findall(r"^\s*var\s+(\w+)", text, re.M))
        local |= set(re.findall(r"^\s*const\s+(\w+)", text, re.M))
        for m in re.finditer(r"(?<![\w.$])([A-Za-z_]\w*)\s*\(", text):
            name = m.group(1)
            if name in KEYWORDS or name in local or name in globals_defined:
                continue
            if name.startswith("sq_"):
                continue
            if name in ("or", "and", "not", "in", "is"):
                continue
            # 跳过注释行
            line_start = text.rfind("\n", 0, m.start()) + 1
            if text[line_start:m.start()].lstrip().startswith("#"):
                continue
            missing.setdefault(name, f.relative_to(GD).as_posix())
    return missing


def main() -> int:
    check = "--check" in sys.argv
    names = [n for n in collect_manifest() if n not in BLOCKED]
    host = scan_bare_calls()
    existing_host = {
        n for n in defined_in(SCRIPT) - set(names) - {"_stub", "_init"} if n not in KEYWORDS and n not in BLOCKED
    }
    for name, src in sorted(host.items()):
        if name not in existing_host:
            print(f"  补宿主内建桩 {name}()  ← {src}")

    if check:
        return 0

    out = []
    out.append("""## SQR（Squirrel）脚本运行时基类 —— 翻译版
##
## 原版 DNF 客户端把 Squirrel VM 内嵌在 exe 里，脚本放在 PVF 的 `sqr/` 目录，
## 由 `sq_RunScript` 加载。脚本里 `sq_*` 是宿主注入的引擎绑定（host API），
## 另有少量不带前缀的宿主内建（`printc`、`isSameObject` 等）同样由 C++ 注入。
##
## 这个类把它们全部声明成空实现，作用有两个：
##   1. 让翻译出来的 GDScript 能通过语法检查（符号找不到会编译失败）；
##   2. 作为**移植清单**：哪些函数必须真正实现，一目了然。
##
## 参数一律 16 个带默认值，因为原脚本调用签名很随意
## （`sq_CreateParticle` 9 个、`sq_FindShootingTarget` 13 个）。
## 真实实现时把 `_stub()` 换成对 `SqrVM` / 场景节点的调用即可。
##
## 注意：`sq_AddFunctionName` / `sq_AddEffect` **故意不在桩表里** ——
## 它们在每个 `ap_*.nut` 里同时是「脚本级入口函数」的定义名，放进基类会
## 报 `Function signature doesn't match the parent`。
class_name SqrScript
extends SqrConsts

## 当前对象绑定的 VM（由 SqrVM 注入）
var vm = null

## 该脚本在 PVF 里的原始路径（如 sqr/character/atmage/chainlightning/chainlightning.nut）
var source_path := ""


func _stub(name: String) -> Variant:
	if vm != null and vm.has_method("on_missing_api"):
		vm.on_missing_api(name)
	return null

""")
    out.append(HOST_HEADER)
    for name in sorted(existing_host | set(host)):
        out.append(f"func {name}({ARGS}) -> Variant:\n\treturn _stub(\"{name}\")\n\n")
    for name in names:
        out.append(f"func {name}({ARGS}) -> Variant:\n\treturn _stub(\"{name}\")\n\n")
    SCRIPT.write_text("".join(out), encoding="utf-8")
    print(f"sqr_script.gd: {len(names)} 个 sq_* 桩 + {len(existing_host | set(host))} 个宿主内建桩")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
