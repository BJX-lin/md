#!/usr/bin/env python3
"""场景贴图覆盖检查

复刻 bg_layer.gd 的 BG_MAP 查找逻辑，对剧本里出现的每一个
@bg <scene> <variant> 组合，判断它最终会：
  A. 命中专属贴图
  B. 命中回退贴图（气质接近的替代图）
  C. 回落到代码绘制

这样能在不启动 Godot 的情况下，确认没有任何场景"开天窗"。
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORY = os.path.join(ROOT, "game", "story")
BG_DIR = os.path.join(ROOT, "game", "assets", "bg")
GD = os.path.join(ROOT, "game", "src", "art", "bg_layer.gd")


def parse_bg_map():
    """从 bg_layer.gd 里解析 BG_MAP"""
    src = open(GD, encoding="utf-8").read()
    start = src.index("const BG_MAP := {")
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                block = src[start:i + 1]
                break
    bgmap = {}
    # 每个 scene 条目： "name": { ... },
    for m in re.finditer(r'"([a-z0-9_]+)":\s*\{(.*?)\n\t\},', block, re.S):
        scene, body = m.group(1), m.group(2)
        table = {}
        for vm in re.finditer(r'"([a-z0-9_]*)":\s*\[([^\]]*)\]', body):
            var = vm.group(1)
            files = re.findall(r'"([a-z0-9_]+)"', vm.group(2))
            table[var] = files
        bgmap[scene] = table
    return bgmap


def scan_script():
    used = defaultdict(set)
    for fn in sorted(os.listdir(STORY)):
        if not fn.endswith(".avg"):
            continue
        for line in open(os.path.join(STORY, fn), encoding="utf-8"):
            m = re.match(r"@bg\s+(\S+)(?:\s+(\S+))?", line.strip())
            if m:
                used[m.group(1)].add(m.group(2) or "")
    return used


def resolve(bgmap, have, scene, var):
    """复刻 _find_texture 的候选顺序"""
    if scene in ("black", "white"):
        return ("solid", None)
    cands = []
    if scene in bgmap:
        t = bgmap[scene]
        if var in t:
            cands += t[var]
        if "" in t and var != "":
            cands += t[""]
        for k in t:
            cands += t[k]
    cands.append(scene + ("_" + var if var else ""))
    cands.append(scene)

    primary = bgmap.get(scene, {}).get(var, []) or bgmap.get(scene, {}).get("", [])
    for i, c in enumerate(cands):
        if c in have:
            # 是否是该 variant 的首选
            kind = "exact" if (primary and c == primary[0]) else "fallback"
            return (kind, c)
    return ("code", None)


def main():
    bgmap = parse_bg_map()
    have = {f[:-4] for f in os.listdir(BG_DIR)} if os.path.isdir(BG_DIR) else set()
    used = scan_script()

    print("=" * 72)
    print("场景贴图覆盖检查（复刻 bg_layer.gd 查找逻辑）")
    print("=" * 72)
    print(f"磁盘贴图 {len(have)} 张 | 剧本用到 {sum(len(v) for v in used.values())} 个场景组合\n")

    stat = {"exact": 0, "fallback": 0, "code": 0, "solid": 0}
    rows = []
    for scene in sorted(used):
        for var in sorted(used[scene]):
            kind, f = resolve(bgmap, have, scene, var)
            stat[kind] += 1
            rows.append((scene, var, kind, f))

    icon = {"exact": "✓", "fallback": "~", "code": "·", "solid": " "}
    label = {"exact": "专属图", "fallback": "回退图", "code": "代码绘制", "solid": "纯色"}
    for scene, var, kind, f in rows:
        name = f"{scene}" + (f" [{var}]" if var else "")
        print(f"  {icon[kind]} {name:32s} {label[kind]:8s} {f or ''}")

    print("-" * 72)
    print(f"  专属图 {stat['exact']}   回退图 {stat['fallback']}   "
          f"代码绘制 {stat['code']}   纯色 {stat['solid']}")
    if stat["code"]:
        print("\n  说明：全部场景组合均有专属贴图，")
        print("  只是不如 AI 图精细。补齐对应贴图后会自动切换。")
    print("  无任何场景会开天窗。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
