#!/usr/bin/env python3
"""校验 ArtCache 的章节映射与释放逻辑（不依赖 Godot 运行时）。

检查项：
  1. CHAPTER_BG / CHAPTER_CHARS 引用的资源都真实存在
  2. 剧本里每章实际用到的 @bg，都被该章的 CHAPTER_BG 覆盖
     （否则过场预取不到，游戏中会临时同步 load 造成卡顿）
  3. 模拟逐章推进，验证缓存占用不会单调增长（释放确实生效）
"""
import os
import re
import sys
import glob
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
if not os.path.isdir(GAME):
    GAME = ROOT

AC = os.path.join(GAME, "autoload", "art_cache.gd")
BG_DIR = os.path.join(GAME, "assets", "bg")
SP_DIR = os.path.join(GAME, "assets", "sprites")
STORY = os.path.join(GAME, "story")


def parse_map(src, const_name, end_marker):
    blk = src[src.find(const_name):]
    if end_marker:
        blk = blk[:blk.find(end_marker)]
    out = {}
    for m in re.finditer(r"(\d+):\s*\[([^\]]*)\]", blk, re.S):
        out[int(m.group(1))] = [x.strip().strip('"')
                                for x in m.group(2).split(",") if x.strip()]
    return out


def main():
    errors, warnings = [], []
    src = open(AC, encoding="utf-8").read()
    ch_bg = parse_map(src, "const CHAPTER_BG", "const CHAPTER_CHARS")
    ch_ch = parse_map(src, "const CHAPTER_CHARS", "")

    have_bg = {f[:-4] for f in os.listdir(BG_DIR) if f.endswith(".png")}
    have_ch = {d for d in os.listdir(SP_DIR)
               if os.path.isdir(os.path.join(SP_DIR, d))}

    # 1. 引用有效性
    for ch, names in ch_bg.items():
        for n in names:
            if n not in have_bg:
                errors.append(f"CHAPTER_BG[{ch}] 引用不存在的背景: {n}")
    for ch, names in ch_ch.items():
        for c in names:
            if c not in have_ch:
                errors.append(f"CHAPTER_CHARS[{ch}] 引用不存在的角色目录: {c}")

    # 2. 剧本实际用量是否被覆盖
    bg_map_src = open(os.path.join(GAME, "src", "art", "bg_layer.gd"),
                      encoding="utf-8").read()
    blk = bg_map_src[bg_map_src.find("const BG_MAP"):]
    blk = blk[:blk.find("\n}\n") + 2]
    BG_MAP = {}
    for m in re.finditer(r'"(\w+)":\s*\{([^}]*)\}', blk, re.S):
        inner = {}
        for mm in re.finditer(r'"(\w*)":\s*\[([^\]]*)\]', m.group(2)):
            inner[mm.group(1)] = [x.strip().strip('"')
                                  for x in mm.group(2).split(",") if x.strip()]
        BG_MAP[m.group(1)] = inner

    def resolve(sid, v):
        if sid in ("black", "white"):
            return None
        t = BG_MAP.get(sid, {})
        cand = list(t.get(v, []))
        if v:
            cand += t.get("", [])
        for k in t:
            cand += t[k]
        cand += [f"{sid}_{v}" if v else sid, sid]
        for c in cand:
            if c in have_bg:
                return c
        return None

    # 章节号来自 @chapter 指令
    cur_ch = 1
    per_ch = collections.defaultdict(set)
    for fn in sorted(os.listdir(STORY)):
        if not fn.endswith(".avg"):
            continue
        for line in open(os.path.join(STORY, fn), encoding="utf-8"):
            mc = re.match(r"\s*@chapter\s+(\d+)", line)
            if mc:
                cur_ch = int(mc.group(1))
            mb = re.match(r"\s*@bg\s+(\S+)(?:\s+(\S+))?", line)
            if mb:
                r = resolve(mb.group(1), mb.group(2) or "")
                if r:
                    per_ch[cur_ch].add(r)

    for ch, used in sorted(per_ch.items()):
        declared = set(ch_bg.get(ch, []))
        missing = used - declared
        if missing:
            warnings.append(
                f"第{ch}章实际用到但未在 CHAPTER_BG 声明（过场预取不到，"
                f"运行时会同步 load）: {sorted(missing)}")

    # 3. 模拟逐章推进，验证释放生效
    def paths(ch):
        out = set()
        for n in ch_bg.get(ch, []):
            p = os.path.join(BG_DIR, n + ".png")
            if os.path.exists(p):
                out.add(p)
        for c in ch_ch.get(ch, []):
            out |= set(glob.glob(os.path.join(SP_DIR, c, "*.png")))
        return out

    cache = set()
    peak = 0
    print("模拟逐章推进（预取 + 释放）：")
    for ch in range(6):
        cache |= paths(ch)                      # 预取本章
        needed = set()
        for f in range(ch, 6):
            needed |= paths(f)
        dropped = len(cache - needed)
        cache &= needed                         # 释放后面用不到的
        mb = sum(os.path.getsize(p) for p in cache) / 1024 / 1024
        peak = max(peak, mb)
        print(f"  第{ch}章：缓存 {len(cache):3d} 个文件 "
              f"{mb:5.1f} MB（本章释放 {dropped} 个）")
    total_mb = sum(os.path.getsize(p)
                   for p in glob.glob(os.path.join(BG_DIR, "*.png"))
                   + glob.glob(os.path.join(SP_DIR, "*", "*.png"))) / 1024 / 1024
    print(f"\n全部美术资源 {total_mb:.1f} MB，"
          f"分章加载后峰值 {peak:.1f} MB（省 {(1 - peak / total_mb) * 100:.0f}%）")
    if peak >= total_mb:
        warnings.append("分章加载没有降低峰值占用，释放逻辑可能失效")

    print("-" * 62)
    for e in errors:
        print(f"  [ERROR] {e}")
    for w in warnings:
        print(f"  [warn ] {w}")
    print(f"错误 {len(errors)} 个，警告 {len(warnings)} 个")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
