#!/usr/bin/env python3
"""选项影响力审计

需求：「每个选项都会影响结局」。

本工具检查每个选项是否具备"影响力"，判定标准（满足其一即算）：
  1. 选项自带 @set / @flag / @state / @item / @clue 效果
  2. 选项跳转到的节点，在其**开头连续的指令区**里带上述效果
     （即选择后立刻产生后果，而非纯粹的文本分叉）

对完全没有影响力的选项给出清单，便于补齐。
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORY = os.path.join(ROOT, "game", "story")

EFFECT_CMDS = {"set", "flag", "state", "item", "clue", "death", "settle", "gallery"}


def parse():
    """返回 nodes: id -> {'effects': bool, 'lines': [...]}, choices: [...]"""
    nodes = {}
    choices = []
    cur = None
    for fn in sorted(os.listdir(STORY)):
        if not fn.endswith(".avg"):
            continue
        for ln, raw in enumerate(open(os.path.join(STORY, fn), encoding="utf-8"), 1):
            s = raw.strip()
            if not s or s.startswith("--"):
                continue
            if s.startswith("=="):
                cur = s[2:].strip()
                nodes[cur] = {"body": [], "file": fn, "line": ln}
                continue
            if cur is None:
                continue
            nodes[cur]["body"].append((ln, raw))
            if s.startswith("*"):
                body = s[1:].strip()
                body = re.sub(r"\[[^\]]*\]", "", body).strip()
                target = ""
                if "->" in body:
                    body, target = body.rsplit("->", 1)
                    target = target.strip()
                choices.append({
                    "file": fn, "line": ln, "node": cur,
                    "text": body.strip(), "target": target, "own": False,
                })
            elif s.startswith("@") and choices and raw.startswith((" ", "\t")):
                cmd = s[1:].split()[0].lower()
                if cmd in EFFECT_CMDS:
                    choices[-1]["own"] = True
    return nodes, choices


def node_has_immediate_effect(nodes, nid):
    """节点开头的指令区里是否有变量影响（允许穿插演出指令与条件块）"""
    if nid not in nodes:
        return False
    seen_text = 0
    for ln, raw in nodes[nid]["body"]:
        s = raw.strip()
        if s.startswith("*"):
            break
        if s.startswith("@"):
            cmd = s[1:].split()[0].lower()
            if cmd in EFFECT_CMDS:
                return True
            continue
        # 允许开头有少量叙述再给效果
        seen_text += 1
        if seen_text > 14:
            break
    return False


def main():
    nodes, choices = parse()
    weak = []
    for c in choices:
        if c["own"]:
            continue
        if c["target"] and node_has_immediate_effect(nodes, c["target"]):
            continue
        weak.append(c)

    print("=" * 72)
    print("选项影响力审计")
    print("=" * 72)
    print(f"选项总数 {len(choices)}   有影响 {len(choices)-len(weak)}   "
          f"无影响 {len(weak)}")
    if weak:
        print("-" * 72)
        by_file = defaultdict(list)
        for c in weak:
            by_file[c["file"]].append(c)
        for fn in sorted(by_file):
            print(f"\n  {fn}")
            for c in by_file[fn]:
                t = c["text"][:34]
                print(f"    :{c['line']:<5d} [{c['node']}] {t} -> {c['target']}")
    print("-" * 72)
    pct = 100.0 * (len(choices) - len(weak)) / max(1, len(choices))
    print(f"影响力覆盖率 {pct:.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
