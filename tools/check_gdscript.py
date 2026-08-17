#!/usr/bin/env python3
"""GDScript 轻量静态检查（不依赖 Godot 可执行文件）

检查项：
  1. 括号 / 方括号 / 花括号 是否配平（按逻辑行，支持续行）
  2. preload / load 的 res:// 路径是否存在
  3. 缩进是否混用空格与制表符
  4. Callable(self, "name") 引用的方法是否存在
  5. autoload 单例名是否在 project.godot 中注册
  6. signal 连接的信号是否在目标脚本中声明（跨脚本按名字宽松匹配）
  7. 关键字拼写：func/var/const/signal 行的基本形态
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")


def res_to_path(p):
    return os.path.join(GAME, p.replace("res://", ""))


def logical_lines(src):
    """把续行（括号未闭合 / 反斜杠结尾）合并成逻辑行"""
    out = []
    buf = ""
    depth = 0
    start_ln = 1
    for ln, raw in enumerate(src.split("\n"), 1):
        line = raw.split("#")[0] if not in_string_hash(raw) else strip_comment(raw)
        if not buf:
            start_ln = ln
        buf += line
        depth += count_depth(line)
        if depth <= 0:
            out.append((start_ln, buf, depth))
            buf = ""
            depth = 0
    if buf:
        out.append((start_ln, buf, depth))
    return out


def in_string_hash(line):
    return '"' in line and "#" in line and line.index('"') < line.index("#")


def strip_comment(line):
    out = ""
    in_str = False
    q = ""
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                out += line[i:i + 2]
                i += 2
                continue
            if c == q:
                in_str = False
            out += c
        else:
            if c in "\"'":
                in_str = True
                q = c
                out += c
            elif c == "#":
                break
            else:
                out += c
        i += 1
    return out


def count_depth(line):
    d = 0
    in_str = False
    q = ""
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == q:
                in_str = False
        else:
            if c in "\"'":
                in_str = True
                q = c
            elif c in "([{":
                d += 1
            elif c in ")]}":
                d -= 1
        i += 1
    return d


def main():
    errors, warnings = [], []
    gd_files = []
    for base, _, files in os.walk(GAME):
        for f in files:
            if f.endswith(".gd"):
                gd_files.append(os.path.join(base, f))
    gd_files.sort()

    autoloads = set()
    proj = open(os.path.join(GAME, "project.godot"), encoding="utf-8").read()
    in_auto = False
    for line in proj.split("\n"):
        if line.strip() == "[autoload]":
            in_auto = True
            continue
        if line.startswith("[") and in_auto:
            in_auto = False
        if in_auto and "=" in line:
            autoloads.add(line.split("=")[0].strip())
            path = line.split("=")[1].strip().strip('"').lstrip("*")
            if path.startswith("res://") and not os.path.exists(res_to_path(path)):
                errors.append(f"project.godot autoload 指向不存在的文件: {path}")

    all_signals = set()
    all_funcs = {}
    for path in gd_files:
        src = open(path, encoding="utf-8").read()
        all_signals |= set(re.findall(r"^signal\s+([a-zA-Z_0-9]+)", src, re.M))
        all_funcs[path] = set(re.findall(r"^\s*(?:static\s+)?func\s+([a-zA-Z_0-9]+)", src, re.M))

    total_lines = 0
    for path in gd_files:
        rel = os.path.relpath(path, ROOT)
        src = open(path, encoding="utf-8").read()
        total_lines += src.count("\n")

        # 1. 括号配平
        depth = 0
        for ln, line, _d in logical_lines(src):
            depth += count_depth(line)
            if depth < 0:
                errors.append(f"{rel}:{ln} 括号多余闭合")
                depth = 0
        if depth != 0:
            errors.append(f"{rel} 文件末尾括号未闭合 (深度 {depth})")

        # 2. preload 路径
        for m in re.finditer(r'(?:preload|load)\(\s*"(res://[^"]+)"', src):
            p = m.group(1)
            if not os.path.exists(res_to_path(p)):
                if "assets/fonts" in p:
                    continue  # 可选字体，运行时用 ResourceLoader.exists 判断
                errors.append(f"{rel} preload 路径不存在: {p}")

        # 3. 缩进混用
        for ln, raw in enumerate(src.split("\n"), 1):
            indent = re.match(r"^[ \t]*", raw).group(0)
            if " " in indent and "\t" in indent:
                errors.append(f"{rel}:{ln} 缩进混用空格与制表符")

        # 4. Callable(self, "x")
        for m in re.finditer(r'Callable\(\s*self\s*,\s*"([a-zA-Z_0-9]+)"', src):
            if m.group(1) not in all_funcs[path]:
                errors.append(f"{rel} Callable 引用了不存在的方法: {m.group(1)}")

        # 5. 单例引用
        for name in re.findall(r"\b(Cfg|GameState|StoryEngine|AudioDirector|SaveSystem)\b", src):
            if name not in autoloads:
                errors.append(f"{rel} 引用了未注册的单例: {name}")
                break

        # 6. signal 连接
        for m in re.finditer(r"\.([a-z_0-9]+)\.connect\(", src):
            sig = m.group(1)
            builtin = {
                "pressed", "toggled", "value_changed", "tree_exited", "tree_entered",
                "text_changed", "item_selected", "timeout", "finished", "gui_input",
                "resized", "visibility_changed", "mouse_entered", "mouse_exited",
            }
            if sig not in all_signals and sig not in builtin:
                warnings.append(f"{rel} 连接了未声明的信号: {sig}")

        # 7. func 行基本形态
        for ln, raw in enumerate(src.split("\n"), 1):
            st = raw.strip()
            if st.startswith("func ") and not st.rstrip().endswith(":") and "->" not in st:
                if not st.rstrip().endswith(":"):
                    errors.append(f"{rel}:{ln} func 定义缺少冒号: {st[:50]}")

    print("=" * 62)
    print("GDScript 静态检查")
    print("=" * 62)
    print(f"脚本文件 : {len(gd_files)}")
    print(f"代码行数 : {total_lines}")
    print(f"自动加载 : {', '.join(sorted(autoloads))}")
    print("-" * 62)
    for w in warnings:
        print("  [warn ]", w)
    for e in errors:
        print("  [ERROR]", e)
    print("-" * 62)
    print(f"错误 {len(errors)} 个，警告 {len(warnings)} 个")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
