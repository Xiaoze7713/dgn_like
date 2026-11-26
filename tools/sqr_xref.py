#!/usr/bin/env python3
"""翻译后处理：把跨脚本调用的「全局函数」接到 SqrGlobals 上。

Squirrel 所有脚本共享一个全局函数命名空间（`addElementalChain_ATMage(...)` 直接调），
GDScript 没有这种东西，所以：

1. 扫描 `sqr_src_utf8/sqr/**.nut` 的顶层 `function name(`，收集 1537 个全局函数；
2. 生成 `sqr_gd/sqr_globals.gd`（`class_name SqrGlobals`，每个名字一个空实现）；
3. 扫描 `sqr_gd/**.gd`：凡是**裸调用**（前面不是 `.`）、不是本文件定义的函数、
   也不是 GDScript 内建/关键字的，加上 `xg.` 前缀，并在类顶部插入 `var xg := SqrGlobals.new()`。

用法：
    python3 tools/sqr_xref.py            # 生成 + 改写
    python3 tools/sqr_xref.py --dry-run  # 只统计，不改文件
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "sqr_src_utf8", "sqr")
# 原版 Squirrel 函数对多余实参是宽容的（多传的被丢掉），GDScript 会报 Too many arguments。
# 桩一律开 16 个可选参数，任何调用长度都能过。
PARAMS = ", ".join(f"_a{i} = null" for i in range(1, 17))
GD = os.path.join(ROOT, "sqr_gd")

BUILTINS = {
    # 关键字 / 字面量
    "if", "elif", "else", "for", "while", "match", "return", "func", "var", "const",
    "and", "or", "not", "in", "is", "as", "true", "false", "null", "self", "super",
    "await", "signal", "pass", "break", "continue", "class", "static", "extends",
    "await", "preload", "load", "assert", "typeof", "print", "printerr", "str",
    "int", "float", "bool", "range", "len", "abs", "min", "max", "clamp", "round",
    "floor", "ceil", "pow", "sqrt", "sin", "cos", "tan", "atan", "atan2", "randf",
    "randi", "randf_range", "randi_range", "randomize", "sign", "lerp", "snapped",
    "deg_to_rad", "rad_to_deg", "push_error", "push_warning", "is_instance_valid",
    "weakref", "JSON", "Color", "Vector2", "Vector3", "Vector4", "Rect2", "Rect2i",
    "PackedByteArray", "PackedInt32Array", "PackedFloat32Array", "PackedStringArray",
    "Array", "Dictionary", "String", "Image", "ImageTexture", "SqrGlobals", "SqrScript",
    "PI", "TAU", "INF", "NAN",
}


def collect_globals() -> set[str]:
    names: set[str] = set()
    for r, _, fs in os.walk(SRC):
        for fn in fs:
            if not fn.endswith(".nut"):
                continue
            t = open(os.path.join(r, fn), encoding="utf-8").read()
            for m in re.finditer(r"^\s*function\s+([A-Za-z_]\w*)\s*\(", t, re.M):
                names.add(m.group(1))
    return names


def local_funcs(text: str) -> set[str]:
    return {m.group(1) for m in re.finditer(r"^func\s+([A-Za-z_]\w*)\s*\(", text, re.M)}


def host_api() -> set[str]:
    p = os.path.join(GD, "sqr_script.gd")
    if not os.path.exists(p):
        return set()
    t = open(p, encoding="utf-8").read()
    return {m.group(1) for m in re.finditer(r"^func\s+(sq_\w+)\s*\(", t, re.M)}


def strip_comments(text: str) -> str:
    out = []
    for ln in text.splitlines():
        in_str = None
        cut = len(ln)
        for i, ch in enumerate(ln):
            if in_str:
                if ch == in_str:
                    in_str = None
            elif ch in "\"'":
                in_str = ch
            elif ch == "#":
                cut = i
                break
        out.append(ln[:cut])
    return "\n".join(out)


def gen_globals(names: set[str], dry: bool) -> None:
    path = os.path.join(GD, "sqr_globals.gd")
    body = [
        "## 跨脚本公共函数表（对应 Squirrel 的全局函数命名空间）\n",
        "##\n",
        "## 原版所有 .nut 共享一个全局命名空间，技能脚本可以直接调用 `*_common.nut` 里的工具函数。\n",
        "## GDScript 没有全局函数，这里统一收口：翻译时跨文件调用写成 `xg.foo(...)`。\n",
        "## 本文件由 `tools/sqr_xref.py` 从源脚本自动生成，**不要手改**。\n",
        "## 每个函数的真实实现在它自己的 .gd 里（见 sqr_gd/INDEX.md）。\n",
        "class_name SqrGlobals\n",
        "extends RefCounted\n\n",
        "## 缺实现时记一笔，方便按需补\n",
        "var missing := {}\n\n",
        f"func _call(name: String, {PARAMS}) -> Variant:\n",
        "\tmissing[name] = int(missing.get(name, 0)) + 1\n",
        "\treturn null\n\n",
    ]
    for n in sorted(names):
        body.append(f"func {n}({PARAMS}) -> Variant:\n" f'\treturn _call("{n}")\n\n')
    if not dry:
        open(path, "w", encoding="utf-8").write("".join(body))
    print(f"sqr_globals.gd: {len(names)} 个全局函数")


def rewrite(path: str, globals_: set[str], api: set[str], dry: bool) -> int:
    text = open(path, encoding="utf-8").read()
    code = strip_comments(text)
    own = local_funcs(text)
    changed = 0
    out_lines = text.splitlines(keepends=True)
    # 只在代码部分定位，然后用行号回写
    pat = re.compile(r"(?<![\.\w])([A-Za-z_]\w*)\s*\(")
    for m in list(pat.finditer(code)):
        name = m.group(1)
        if name in own or name in globals_ and name in api:
            continue
        if name in BUILTINS or name in api:
            continue
        if name not in globals_:
            continue
        # 找到行号，替换该行第一个同名裸调用
        ln = code[: m.start()].count("\n")
        line = out_lines[ln]
        new_line = re.sub(r"(?<![\.\w])" + re.escape(name) + r"\s*\(", "xg." + name + "(", line, count=1)
        if new_line != line:
            out_lines[ln] = new_line
            changed += 1
    if changed:
        text = "".join(out_lines)
        if "var xg" not in text:
            # 插到 extends 之后的第一个空行前
            text = re.sub(r"(extends SqrScript\n)", r"\1\nvar xg := SqrGlobals.new()   # 跨脚本公共函数表\n", text, count=1)
        if not dry:
            open(path, "w", encoding="utf-8").write(text)
    return changed


def main() -> int:
    dry = "--dry-run" in sys.argv
    g = collect_globals()
    gen_globals(g, dry)
    api = host_api()
    total = 0
    files = 0
    for r, _, fs in os.walk(GD):
        for fn in fs:
            if not fn.endswith(".gd") or fn in ("sqr_script.gd", "sqr_globals.gd"):
                continue
            n = rewrite(os.path.join(r, fn), g, api, dry)
            if n:
                files += 1
                total += n
    print(f"改写 {files} 个文件，共 {total} 处跨文件调用加了 xg. 前缀")
    return 0


if __name__ == "__main__":
    sys.exit(main())
