#!/usr/bin/env python3
"""死亡连贯性检查：已死/失踪的角色不应再像活人一样出场说话。

背景：@death 只是登记，引擎不会阻止该角色后续出场。曾出现过
「梁野在旧楼失踪后，第四天早上还坐在床沿穿鞋聊天」这类断裂。

判定方式：跑随机通关，沿【真实执行到的分支】记录"已死角色仍开口"，
因此被 @if !death:X 正确保护的行不会误报。

允许清单 GHOST_OK 里的节点是有意为之的"回声/幻听"演出
（梁野以 hollow 表情出现在监控雪花、广播里等），不算 bug。
"""
import collections
import importlib.util
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# 有意设计的亡者回声场景：这些地方角色本就该以"不在场的声音"出现
GHOST_OK = {
    "ch3_s8_absent", "ch4_ly_absent", "final_ly_absent",
    "final_sc2", "ch4_sc6", "final_ly_unstable",
    "ch4_ly_b1", "ch4_ly_b2",
}


def main():
    runs = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
    spec = importlib.util.spec_from_file_location(
        "sim", os.path.join(HERE, "simulate.py"))
    m = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ["simulate"]
    try:
        spec.loader.exec_module(m)
    except SystemExit:
        pass
    sys.argv = argv

    m.load_cfg()
    p = m.Parser()
    p.parse_dir(m.STORY_DIR)

    rng = random.Random(777)
    agg = collections.Counter()
    for _ in range(runs):
        r = m.Runner(p.nodes, m.random_chooser(rng))
        try:
            r.run()
        except Exception:
            continue
        for k, v in r.dead_speaks.items():
            agg[k] += v

    print("=" * 62)
    print("死亡连贯性检查")
    print("=" * 62)
    print(f"随机通关 {runs} 次")

    bad = {k: v for k, v in agg.items() if k[1] not in GHOST_OK}
    ok = {k: v for k, v in agg.items() if k[1] in GHOST_OK}

    if ok:
        print(f"\n有意的亡者回声场景 {len(ok)} 处（已在允许清单）：")
        for (c, n), v in sorted(ok.items(), key=lambda x: -x[1]):
            print(f"  · {c} @ {n}")

    print("-" * 62)
    if bad:
        print(f"错误 {len(bad)} 处 —— 已死角色仍像活人一样说话：")
        for (c, n), v in sorted(bad.items(), key=lambda x: -x[1]):
            print(f"  [ERROR] {c} 在节点 {n} 说话（{v} 次）")
        print("\n修法：给入口选项或该段加 @if !death:<中文名> 保护，")
        print("      或改写成只留声音的回声演出并加进 GHOST_OK。")
        return 1
    print("错误 0 个 —— 没有死者以活人身份出场")
    return 0


if __name__ == "__main__":
    sys.exit(main())
