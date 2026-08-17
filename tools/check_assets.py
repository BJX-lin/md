#!/usr/bin/env python3
"""美术资源覆盖率检查

扫描剧本里实际用到的 @bg / @show，对照 assets/ 下已有的图，
列出还缺哪些背景与立绘差分。缺图不会导致报错（引擎会回退到代码绘制），
但这份清单能告诉你「还差多少张」。
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
STORY = os.path.join(GAME, "story")
BG_DIR = os.path.join(GAME, "assets", "bg")
SP_DIR = os.path.join(GAME, "assets", "sprites")

# 与 actor_sprite.gd 的 EMO_FALLBACK 对应：这些表情可由已有图降级顶替
FALLBACK_ROOTS = {
    "normal", "neutral", "calm",
}


def scan_story():
    bgs, sprites = defaultdict(set), defaultdict(set)
    for fn in sorted(os.listdir(STORY)):
        if not fn.endswith(".avg"):
            continue
        for line in open(os.path.join(STORY, fn), encoding="utf-8"):
            s = line.strip()
            m = re.match(r"@bg\s+(\S+)(?:\s+(\S+))?", s)
            if m:
                bgs[m.group(1)].add(m.group(2) or "")
            m = re.match(r"@show\s+(\S+)(?:\s+(\S+))?", s)
            if m:
                sprites[m.group(1)].add(m.group(2) or "normal")
    return bgs, sprites


def have_bg(scene, var):
    for cand in ([var, ""] if var else [""]):
        suffix = "" if cand == "" else "_" + cand
        if os.path.exists(os.path.join(BG_DIR, f"{scene}{suffix}.png")):
            return True
    return False


def have_sprite(char_id, emo):
    d = os.path.join(SP_DIR, char_id)
    if not os.path.isdir(d):
        return False
    files = os.listdir(d)
    if any(f.endswith(f"_{emo}.png") for f in files):
        return True
    # 能被基础表情顶替也算「可显示」（会降级，但不开天窗）
    return any(any(f.endswith(f"_{r}.png") for f in files) for r in FALLBACK_ROOTS)


def exact_sprite(char_id, emo):
    d = os.path.join(SP_DIR, char_id)
    if not os.path.isdir(d):
        return False
    return any(f.endswith(f"_{emo}.png") for f in os.listdir(d))


def main():
    bgs, sprites = scan_story()

    print("=" * 66)
    print("美术资源覆盖率")
    print("=" * 66)

    # 背景
    total = missing = 0
    miss_list = []
    for scene in sorted(bgs):
        for var in sorted(bgs[scene]):
            if scene in ("black", "white"):
                continue
            total += 1
            if not have_bg(scene, var):
                missing += 1
                miss_list.append(f"{scene}" + (f"_{var}" if var else ""))
    print(f"\n【背景】剧本用到 {total} 种，已有 {total - missing} 种，缺 {missing} 种")
    if miss_list:
        seen = []
        for m in miss_list:
            if m not in seen:
                seen.append(m)
        for m in seen:
            print(f"    缺  assets/bg/{m}.png")

    # 立绘
    print(f"\n【立绘】")
    t_exact = t_total = 0
    for char_id in sorted(sprites):
        if char_id in ("radio", "voice", "crowd", "classmate", "unknown", "me"):
            continue   # 无实体立绘的旁白型说话人
        emos = sorted(sprites[char_id])
        have = [e for e in emos if exact_sprite(char_id, e)]
        t_exact += len(have)
        t_total += len(emos)
        d = os.path.join(SP_DIR, char_id)
        n_files = len(os.listdir(d)) if os.path.isdir(d) else 0
        status = "✓" if len(have) == len(emos) else " "
        print(f"  {status} {char_id:9s} 现有图 {n_files} 张 | "
              f"剧本用到 {len(emos)} 种表情，精确匹配 {len(have)} 种")
        lack = [e for e in emos if not exact_sprite(char_id, e)]
        if lack:
            print(f"      待补: {', '.join(lack)}")

    print("-" * 66)
    print(f"立绘表情精确覆盖 {t_exact}/{t_total}")
    print("注：缺图不会报错，引擎按 EMO_FALLBACK 降级，最终回退代码绘制。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
