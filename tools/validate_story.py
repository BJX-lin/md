#!/usr/bin/env python3
"""《晚自习之后》剧本静态校验工具

检查项：
  1. 节点重复定义 / 未定义的跳转目标
  2. 不可达节点
  3. 未知指令、未知角色、未知道具、未知线索、未知变量
  4. @if / @endif 配平
  5. 死路节点（既没有选项也没有 goto/ending/return）
  6. 结局节点完整性（五结局是否都存在）
  7. 统计：节点数、台词数、选项数、字数
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORY_DIR = os.path.join(ROOT, "game", "story")
CFG = os.path.join(ROOT, "game", "autoload", "config.gd")
GS = os.path.join(ROOT, "game", "autoload", "game_state.gd")

KNOWN_CMDS = {
    "bg", "bgm", "stopbgm", "amb", "stopamb", "sfx", "fx", "show", "hide",
    "clearchars", "set", "flag", "state", "item", "clue", "death", "gallery",
    "title", "roster", "note", "wait", "chapter", "settle", "autosave",
    "goto", "ending", "return", "if", "elif", "else", "endif",
}
KNOWN_FX = {
    "shake", "bigshake", "flash", "redflash", "glitch", "static", "blood",
    "bloodburst", "fog", "heartbeat", "names", "darken", "whiteout",
    "scanlines", "crack", "handprint", "eyes", "rewind", "flicker",
}
KNOWN_BG = {
    "black", "white", "classroom", "office", "hallway", "library", "dorm",
    "dorm_door", "oldbuilding_out", "oldbuilding_stair", "broadcast_door",
    "broadcast_room", "duty_room", "schoolyard", "history_hall", "archive",
    "monitor_room", "mirror",
}
ENDINGS = {
    "ending_true_release", "ending_bittersweet_exchange", "ending_manager",
    "ending_destroyer", "ending_empty_seat",
}


def parse_dict_keys(path, start_marker, key_re=r'"([a-z_0-9]+)"\s*:'):
    """从 gd 文件里提取某个字典块的键名"""
    src = open(path, encoding="utf-8").read()
    i = src.find(start_marker)
    if i < 0:
        return set()
    depth = 0
    started = False
    out = []
    for ch_i in range(i, len(src)):
        c = src[ch_i]
        if c == "{":
            depth += 1
            started = True
        elif c == "}":
            depth -= 1
            if started and depth == 0:
                out = src[i:ch_i]
                break
    if not isinstance(out, str):
        out = src[i:]
    return set(re.findall(key_re, out))


def load_known():
    cfg = open(CFG, encoding="utf-8").read()
    gs = open(GS, encoding="utf-8").read()
    nums = set(re.findall(r'"([a-z_0-9]+)":\s*\[-?\d+,\s*\d+\]', cfg))
    chars = parse_dict_keys(CFG, "const CHARACTERS")
    items = parse_dict_keys(GS, "const ITEMS")
    clues = parse_dict_keys(GS, "const CLUES")
    enums = set(re.findall(r'"([a-z_0-9]+)":\s*"[a-z_]+"', cfg.split("ENUM_DEFAULT")[1].split("}")[0])) if "ENUM_DEFAULT" in cfg else set()
    return nums, chars, items, clues, enums


class Node:
    def __init__(self, nid, src, line):
        self.id = nid
        self.src = src
        self.line = line
        self.targets = []
        self.has_choices = False
        self.terminal = False
        self.says = 0
        self.chars = 0


def main():
    nums, chars, items, clues, enums = load_known()
    errors, warnings = [], []
    nodes = {}
    order = []
    if_balance = []

    files = sorted(f for f in os.listdir(STORY_DIR) if f.endswith(".avg"))
    if not files:
        print("没有找到剧本文件")
        return 1

    for fn in files:
        path = os.path.join(STORY_DIR, fn)
        cur = None
        depth = 0
        for ln, raw in enumerate(open(path, encoding="utf-8"), 1):
            line = raw.rstrip("\n")
            s = line.strip()
            if not s or s.startswith("--"):
                continue
            if s.startswith("=="):
                if cur and depth != 0:
                    errors.append(f"{fn}:{cur.line} 节点 {cur.id} 的 @if/@endif 不配平 (剩余 {depth})")
                nid = s[2:].strip()
                if nid in nodes:
                    errors.append(f"{fn}:{ln} 节点重复定义: {nid}（已在 {nodes[nid].src}）")
                cur = Node(nid, f"{fn}:{ln}", ln)
                nodes[nid] = cur
                order.append(nid)
                depth = 0
                continue
            if cur is None:
                errors.append(f"{fn}:{ln} 节点外的内容: {s[:30]}")
                continue

            if s.startswith("*"):
                cur.has_choices = True
                body = s[1:].strip()
                # 条件标签
                for tag in re.findall(r"\[(if|lock)\s+([^\]]+)\]", body):
                    check_cond(tag[1], nums, items, clues, enums, f"{fn}:{ln}", warnings)
                body = re.sub(r"\[[^\]]*\]", "", body).strip()
                if "->" in body:
                    tgt = body.rsplit("->", 1)[1].strip()
                    cur.targets.append((tgt, f"{fn}:{ln}"))
                else:
                    warnings.append(f"{fn}:{ln} 选项没有跳转目标: {body[:24]}")
                continue

            if s.startswith("@"):
                parts = s[1:].split()
                if not parts:
                    continue
                cmd = parts[0].lower()
                args = parts[1:]
                if cmd not in KNOWN_CMDS:
                    errors.append(f"{fn}:{ln} 未知指令 @{cmd}")
                    continue
                if cmd == "if":
                    depth += 1
                    check_cond(" ".join(args), nums, items, clues, enums, f"{fn}:{ln}", warnings)
                elif cmd == "elif":
                    check_cond(" ".join(args), nums, items, clues, enums, f"{fn}:{ln}", warnings)
                elif cmd == "endif":
                    depth -= 1
                    if depth < 0:
                        errors.append(f"{fn}:{ln} 多余的 @endif")
                elif cmd == "goto":
                    t = args[0] if args else ""
                    if t == "__ending__":
                        cur.terminal = True
                        for e in ENDINGS:
                            cur.targets.append((e, f"{fn}:{ln}"))
                    else:
                        cur.targets.append((t, f"{fn}:{ln}"))
                elif cmd in ("ending", "return"):
                    cur.terminal = True
                    if cmd == "ending" and args and args[0] not in ENDINGS and args[0] != "auto":
                        warnings.append(f"{fn}:{ln} 未登记的结局 id: {args[0]}")
                elif cmd == "fx":
                    if args and args[0] not in KNOWN_FX:
                        errors.append(f"{fn}:{ln} 未知特效 @fx {args[0]}")
                elif cmd == "bg":
                    if args and args[0] not in KNOWN_BG:
                        errors.append(f"{fn}:{ln} 未知背景 @bg {args[0]}")
                elif cmd == "set":
                    if not args or args[0] not in nums:
                        errors.append(f"{fn}:{ln} 未知数值变量 @set {args[0] if args else ''}")
                    elif len(args) < 2 or not re.match(r"^[+\-=]?\d+$", args[1]):
                        errors.append(f"{fn}:{ln} @set 值格式错误: {' '.join(args)}")
                elif cmd == "item":
                    if args:
                        iid = args[0].lstrip("+-")
                        if iid not in items:
                            errors.append(f"{fn}:{ln} 未知道具 {iid}")
                elif cmd == "clue":
                    if args and args[0] not in clues:
                        errors.append(f"{fn}:{ln} 未知线索 {args[0]}")
                elif cmd == "state":
                    if args and args[0] not in enums:
                        warnings.append(f"{fn}:{ln} 未登记的状态键 {args[0]}")
                elif cmd in ("show", "hide"):
                    if args and args[0] not in chars:
                        errors.append(f"{fn}:{ln} 未知角色 {args[0]}")
                continue

            # 台词
            cur.says += 1
            cur.chars += len(s)
            m = re.match(r"^([A-Za-z_]+)(\([^)]*\))?[:：]", s)
            if m and m.group(1) not in chars:
                warnings.append(f"{fn}:{ln} 未知说话人 {m.group(1)}")
        if cur and depth != 0:
            errors.append(f"{fn}:{cur.line} 节点 {cur.id} 的 @if/@endif 不配平 (剩余 {depth})")

    # 跳转目标校验
    for nid, node in nodes.items():
        for tgt, loc in node.targets:
            if tgt not in nodes:
                errors.append(f"{loc} 跳转目标不存在: {tgt}（来自节点 {nid}）")
        if not node.targets and not node.terminal:
            errors.append(f"{node.src} 死路节点（无跳转也无结束）: {nid}")

    # 可达性
    reachable = set()
    stack = ["prologue"]
    while stack:
        n = stack.pop()
        if n in reachable or n not in nodes:
            continue
        reachable.add(n)
        for t, _ in nodes[n].targets:
            stack.append(t)
    unreachable = [n for n in order if n not in reachable]
    for n in unreachable:
        warnings.append(f"{nodes[n].src} 不可达节点: {n}")

    for e in ENDINGS:
        if e not in nodes:
            errors.append(f"缺少结局节点: {e}")

    total_says = sum(n.says for n in nodes.values())
    total_chars = sum(n.chars for n in nodes.values())
    total_choices = sum(1 for n in nodes.values() if n.has_choices)
    total_targets = sum(len(n.targets) for n in nodes.values())

    print("=" * 62)
    print("《晚自习之后》剧本校验")
    print("=" * 62)
    print(f"剧本文件 : {len(files)}  ({', '.join(files)})")
    print(f"节点数   : {len(nodes)}")
    print(f"台词行数 : {total_says}")
    print(f"正文字数 : {total_chars}")
    print(f"选择场景 : {total_choices}   跳转边: {total_targets}")
    print(f"可达节点 : {len(reachable)} / {len(nodes)}")
    print("-" * 62)
    for w in warnings:
        print("  [warn ]", w)
    for e in errors:
        print("  [ERROR]", e)
    print("-" * 62)
    print(f"错误 {len(errors)} 个，警告 {len(warnings)} 个")
    return 1 if errors else 0


def check_cond(expr, nums, items, clues, enums, loc, warnings):
    for atom in re.split(r"\s+(?:and|or)\s+", expr.strip()):
        a = atom.strip().lstrip("!")
        if not a:
            continue
        if a.startswith(("item:", "clue:", "state:", "visited:", "death:")):
            kind, _, val = a.partition(":")
            if kind == "item" and val not in items:
                warnings.append(f"{loc} 条件引用未知道具 {val}")
            if kind == "clue" and val not in clues:
                warnings.append(f"{loc} 条件引用未知线索 {val}")
            if kind == "state":
                key = re.split(r"[=!]", val)[0]
                if key not in enums:
                    warnings.append(f"{loc} 条件引用未知状态键 {key}")
            continue
        if a.startswith(("cycles", "chapter", "gore")):
            continue
        m = re.match(r"^([a-z_0-9]+)\s*(<=|>=|==|!=|<|>)", a)
        if m:
            if m.group(1) not in nums:
                warnings.append(f"{loc} 条件引用未知数值变量 {m.group(1)}")
            continue
        if a in nums:
            continue
        if not a.startswith(("flag_", "true_end_", "archive_route", "sanity_bonus")):
            warnings.append(f"{loc} 可疑条件原子: {a}")


if __name__ == "__main__":
    sys.exit(main())
