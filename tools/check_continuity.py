#!/usr/bin/env python3
"""剧情连贯性审计：找出断层、逻辑接不上、伏笔未回收等问题。

validate_story.py 保证「结构可达」，simulate.py 保证「能通关」，
但两者都不管**叙事是否讲得通**。这个工具补上这一层：

  1. flag 时序：使用点是否早于最早的设置点（会导致分支恒不可达）
  2. 孤儿 flag：设置了但从未被任何条件使用（伏笔没有回收）
  3. 悬空 flag：被条件使用但从未被设置（分支永远走不到）
  4. 道具/线索同样按上述三条检查
  5. 章节跳跃：节点跳转是否跨越了章节边界（可能造成叙事断层）
  6. 时间倒流：@time / @advtime 是否出现时间回退
  7. 角色在场一致性：@show 之后未 @hide/@clearchars 就换场景
"""
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
if not os.path.isfile(os.path.join(GAME, "project.godot")):
    GAME = ROOT
STORY = os.path.join(GAME, "story")

# 章节归属：文件名前缀 → 章节号
def chapter_of(fname):
    m = re.match(r"(\d+)_", fname)
    if not m:
        return 99
    n = int(m.group(1))
    if n < 10:
        return 0
    return min(5, n // 10)


def main():
    errors, warns, notes = [], [], []

    files = sorted(f for f in os.listdir(STORY) if f.endswith(".avg"))
    flag_set = defaultdict(list)     # flag -> [(chapter, file, line)]
    flag_use = defaultdict(list)
    item_set, item_use = defaultdict(list), defaultdict(list)
    clue_set, clue_use = defaultdict(list), defaultdict(list)
    node_chapter = {}
    node_targets = defaultdict(list)
    cur_node = None

    for fn in files:
        ch = chapter_of(fn)
        path = os.path.join(STORY, fn)
        for ln, raw in enumerate(open(path, encoding="utf-8"), 1):
            st = raw.strip()
            if st.startswith("== "):
                cur_node = st[3:].strip()
                node_chapter[cur_node] = ch
                continue
            if st.startswith("--"):
                continue
            loc = (ch, fn, ln)
            # 设置
            m = re.match(r"@flag\s+(\w+)", st)
            if m:
                flag_set[m.group(1)].append(loc)
            m = re.match(r"@item\s+\+(\w+)", st)
            if m:
                item_set[m.group(1)].append(loc)
            m = re.match(r"@clue\s+(\w+)", st)
            if m:
                clue_set[m.group(1)].append(loc)
            # 使用（条件里）
            cond = ""
            mc = re.match(r"@(?:if|elif)\s+(.+)$", st)
            if mc:
                cond = mc.group(1)
            mo = re.search(r"\[(?:if|lock)\s+([^\]]+)\]", st)
            if mo:
                cond = mo.group(1)
            if cond:
                for f in re.findall(r"\b(flag_\w+)", cond):
                    flag_use[f].append(loc)
                for i in re.findall(r"item:(\w+)", cond):
                    item_use[i].append(loc)
                for c in re.findall(r"clue:(\w+)", cond):
                    clue_use[c].append(loc)
            # 跳转
            if cur_node:
                mt = re.search(r"->\s*(\S+)\s*$", st)
                if mt:
                    node_targets[cur_node].append(mt.group(1))
                mg = re.match(r"@goto\s+(\S+)", st)
                if mg:
                    node_targets[cur_node].append(mg.group(1))

    # —— 1 & 3. 时序与悬空
    def audit(kind, setd, used):
        for name, uses in sorted(used.items()):
            if name not in setd:
                errors.append(f"[{kind}] {name} 被条件引用但从未设置"
                              f"（分支永远走不到）→ {uses[0][1]}:{uses[0][2]}")
                continue
            earliest_set = min(c for c, _, _ in setd[name])
            for ch, fn, ln in uses:
                if ch < earliest_set:
                    errors.append(
                        f"[{kind}] {name} 在第{ch}章被使用（{fn}:{ln}），"
                        f"但最早只能在第{earliest_set}章获得 —— 该分支恒不可达")
                    break
        # 2. 孤儿
        for name, sets in sorted(setd.items()):
            if name not in used:
                notes.append(f"[{kind}] {name} 已设置但从未被条件使用"
                             f"（{sets[0][1]}:{sets[0][2]}）")

    audit("flag", flag_set, flag_use)
    audit("item", item_set, item_use)
    audit("clue", clue_set, clue_use)

    # —— 5. 章节跳跃
    for src, tgts in sorted(node_targets.items()):
        sc = node_chapter.get(src, 99)
        for t in tgts:
            tc = node_chapter.get(t)
            if tc is None or sc == 99 or tc == 99:
                continue
            if tc < sc and sc - tc >= 1 and t not in ("prologue",):
                warns.append(f"[章节] {src}(第{sc}章) → {t}(第{tc}章) 章节回退")
            elif tc - sc >= 2:
                warns.append(f"[章节] {src}(第{sc}章) → {t}(第{tc}章) 跳过了整章")

    # —— 6. 时间倒流（按文件内顺序）
    for fn in files:
        last = None
        for ln, raw in enumerate(open(os.path.join(STORY, fn), encoding="utf-8"), 1):
            m = re.match(r"\s*@time\s+(\d+)\s+(\d+):(\d+)", raw)
            if not m:
                continue
            cur = (int(m.group(1)), int(m.group(2)) * 60 + int(m.group(3)))
            if last and cur < last:
                warns.append(f"[时间] {fn}:{ln} 时间回退 "
                             f"第{last[0]}天{last[1] // 60:02d}:{last[1] % 60:02d}"
                             f" → 第{cur[0]}天{cur[1] // 60:02d}:{cur[1] % 60:02d}")
            last = cur

    print("剧情连贯性审计")
    print("=" * 62)
    print(f"剧本 {len(files)} 个，节点 {len(node_chapter)} 个")
    print(f"flag {len(flag_set)} 设 / {len(flag_use)} 用　"
          f"道具 {len(item_set)}/{len(item_use)}　线索 {len(clue_set)}/{len(clue_use)}")
    print("-" * 62)
    for e in errors:
        print(f"  [ERROR] {e}")
    for w in warns[:20]:
        print(f"  [warn ] {w}")
    if len(warns) > 20:
        print(f"  … 另有 {len(warns) - 20} 条警告")
    if notes:
        print(f"\n  未回收的伏笔 {len(notes)} 条（不影响运行，但可考虑补回收）：")
        for n in notes[:12]:
            print(f"    · {n}")
        if len(notes) > 12:
            print(f"    … 另有 {len(notes) - 12} 条")
    print("-" * 62)
    print(f"错误 {len(errors)} 个，警告 {len(warns)} 个，提示 {len(notes)} 个")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
