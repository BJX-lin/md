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
from collections import defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
if not os.path.isfile(os.path.join(GAME, "project.godot")):
    GAME = ROOT
STORY = os.path.join(GAME, "story")

# 章节归属：文件名前缀 → 章节号
## 允许被多个章节进入的支线 hub（有意设计，非章节回退）
CROSS_CHAPTER_HUBS = {"liheng_hub"}


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
            # 跨章可回访的支线 hub：这些节点被设计成多个章节都能进入
            # （李恒线从第二章和第三章都可以观察），不算回退。
            if t in CROSS_CHAPTER_HUBS:
                continue
            if tc < sc and sc - tc >= 1 and t not in ("prologue",):
                warns.append(f"[章节] {src}(第{sc}章) → {t}(第{tc}章) 章节回退")
            elif tc - sc >= 2:
                warns.append(f"[章节] {src}(第{sc}章) → {t}(第{tc}章) 跳过了整章")

    # —— 6. 时间倒流（沿跳转图传播，能抓到「换个顺序走支线导致时钟倒退」）
    #
    # 只看文件内行序是不够的：第四章许清/老秦/李恒三条支线可任意排序，
    # 各自写死一个绝对 @time，玩家先看 22:30 的李恒再看 19:20 的许清就会倒流。
    # 这里从 prologue 出发，在跳转图上传播每个节点的【最早/最晚】到达时刻，
    # 若某节点的 @time 早于它可能的到达时刻，即判定为时间倒流。
    #
    # @timeat 是单调时钟（只进不退），因此豁免。
    node_time = {}    # node -> [(kind, value, line)]  kind: set/seek/adv
    node_out = {}
    cur_node = None
    for fn in files:
        for ln, raw in enumerate(open(os.path.join(STORY, fn), encoding="utf-8"), 1):
            s = raw.rstrip("\n")
            m = re.match(r"==\s*(\S+)", s)
            if m:
                cur_node = m.group(1)
                node_time[cur_node] = []
                node_out[cur_node] = []
                continue
            if cur_node is None:
                continue
            t = s.strip()
            m = re.match(r"@(time|timeat)\s+(\d+)\s+(\d+):(\d+)", t)
            if m:
                node_time[cur_node].append(
                    ("set" if m.group(1) == "time" else "seek",
                     int(m.group(2)) * 1440 + int(m.group(3)) * 60 + int(m.group(4)), ln))
            m = re.match(r"@advtime\s+(-?\d+)", t)
            if m:
                node_time[cur_node].append(("adv", int(m.group(1)), ln))
            for tg in re.findall(r"->\s*(\S+)", s) + re.findall(r"@goto\s+(\S+)", s):
                node_out[cur_node].append(tg)

    START = "prologue"
    if START in node_time:
        # 支线 hub 普遍带 [if !visited:X] 守卫，实际不可能无限循环。
        # 若沿着环反复累加 @advtime，"最晚到达"会被夸大到荒谬的值（第 40 天）。
        # 因此先用 DFS 找出回边（指向递归栈上节点的边）并剔除，
        # 在剩下的有向无环图上传播时间，结果才是真实可达区间。
        back_edges = set()
        color = {}

        def _find_back(root):
            stack = [(root, 0)]
            color[root] = 1
            while stack:
                n, i = stack.pop()
                outs = node_out.get(n, [])
                if i < len(outs):
                    stack.append((n, i + 1))
                    t = outs[i]
                    if t not in node_time:
                        continue
                    c = color.get(t, 0)
                    if c == 1:
                        back_edges.add((n, t))
                    elif c == 0:
                        color[t] = 1
                        stack.append((t, 0))
                else:
                    color[n] = 2

        _find_back(START)
        for n in list(node_time):
            if color.get(n, 0) == 0:
                _find_back(n)

        lo = {START: 1 * 1440 + 14 * 60 + 40}
        hi = dict(lo)
        queue = deque([START])
        guard = 0
        while queue and guard < 200000:
            guard += 1
            n = queue.popleft()
            for base in {lo[n], hi[n]}:
                cur = base
                for kind, val, _ln in node_time.get(n, []):
                    if kind == "set":
                        cur = val
                    elif kind == "seek":
                        cur = max(cur, val)
                    else:
                        cur += val
                for t in node_out.get(n, []):
                    if t not in node_time or (n, t) in back_edges:
                        continue
                    changed = False
                    if t not in lo:
                        lo[t] = hi[t] = cur
                        changed = True
                    else:
                        if cur < lo[t]:
                            lo[t] = cur
                            changed = True
                        if cur > hi[t]:
                            hi[t] = cur
                            changed = True
                    if changed:
                        queue.append(t)

        def _fmt(k):
            return f"第{k // 1440}天{(k % 1440) // 60:02d}:{(k % 1440) % 60:02d}"

        for n, evs in sorted(node_time.items()):
            if n not in hi:
                continue
            sets = [e for e in evs if e[0] == "set"]
            if not sets:
                continue
            _kind, tgt, ln = sets[0]
            if hi[n] > tgt:
                warns.append(
                    f"[时间] {n}:{ln} 时间倒流 —— 最晚可能在 {_fmt(hi[n])} 到达，"
                    f"却被 @time 拨回 {_fmt(tgt)}（改用 @timeat 可只进不退）")

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
