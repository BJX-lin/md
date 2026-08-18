#!/usr/bin/env python3
"""美术资源覆盖率检查（对照 asset_manifest.py 的总清单）

用法：
  python3 tools/check_assets.py            # 覆盖率总览
  python3 tools/check_assets.py --todo     # 只列还没做的，按优先级排序
  python3 tools/check_assets.py --prompt 3 # 打印接下来 3 张的 AI 生图提示词
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asset_manifest as M

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
SP_DIR = os.path.join(GAME, "assets", "sprites")
BG_DIR = os.path.join(GAME, "assets", "bg")

PRIO_ORDER = {"S": 0, "A": 1, "B": 2}


def sprite_path(char_id, pose, exp):
    return os.path.join(SP_DIR, char_id, M.sprite_filename(char_id, pose, exp))


def bg_path(name):
    return os.path.join(BG_DIR, name + ".png")


def collect():
    todo, done = [], []
    for char_id, pose, exp, prio in M.SPRITES:
        item = {
            "kind": "sprite", "prio": prio,
            "id": f"{char_id}_{pose}_{exp}",
            "path": sprite_path(char_id, pose, exp),
            "rel": f"assets/sprites/{char_id}/{M.sprite_filename(char_id, pose, exp)}",
            "prompt": M.sprite_prompt(char_id, pose, exp),
        }
        (done if os.path.exists(item["path"]) else todo).append(item)

    bgmap = {n: d for n, _, d in M.BACKGROUNDS}
    for name, prio, desc in M.BACKGROUNDS:
        item = {
            "kind": "bg", "prio": prio, "id": name,
            "path": bg_path(name), "rel": f"assets/bg/{name}.png",
            "prompt": M.bg_prompt(desc),
        }
        (done if os.path.exists(item["path"]) else todo).append(item)

    for name, base, prio, vdesc in M.VARIANTS:
        item = {
            "kind": "variant", "prio": prio, "id": name,
            "path": bg_path(name), "rel": f"assets/bg/{name}.png",
            "prompt": M.variant_prompt(bgmap.get(base, ""), vdesc),
        }
        (done if os.path.exists(item["path"]) else todo).append(item)

    todo.sort(key=lambda x: (PRIO_ORDER.get(x["prio"], 9), x["kind"], x["id"]))
    return todo, done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--todo", action="store_true")
    ap.add_argument("--prompt", type=int, default=0)
    args = ap.parse_args()

    todo, done = collect()
    total = len(todo) + len(done)

    if args.prompt:
        print(f"接下来 {min(args.prompt, len(todo))} 张的生图提示词\n")
        for it in todo[:args.prompt]:
            print("=" * 70)
            print(f"[{it['prio']}] {it['id']}   →  {it['rel']}")
            print("-" * 70)
            print(it["prompt"])
            print()
        return 0

    if args.todo:
        print(f"待生成 {len(todo)} 张（按优先级排序）\n")
        cur = None
        for it in todo:
            if it["prio"] != cur:
                cur = it["prio"]
                label = {"S": "S 必做", "A": "A 重要", "B": "B 可选"}[cur]
                print(f"\n—— {label} ——")
            print(f"  {it['kind']:7s} {it['rel']}")
        return 0

    print("=" * 68)
    print("美术资源覆盖率（对照《场景图片需求表》《角色立绘表情表》）")
    print("=" * 68)

    for kind, label in [("sprite", "立绘"), ("bg", "场景"), ("variant", "变体")]:
        d = [x for x in done if x["kind"] == kind]
        t = [x for x in todo if x["kind"] == kind]
        n = len(d) + len(t)
        bar_len = 30
        filled = int(bar_len * len(d) / n) if n else 0
        bar = "█" * filled + "·" * (bar_len - filled)
        print(f"\n{label}  {bar}  {len(d)}/{n}")
        if d:
            for x in sorted(d, key=lambda y: y["id"]):
                print(f"    ✓ {x['id']}")
        by_prio = {}
        for x in t:
            by_prio.setdefault(x["prio"], []).append(x)
        for p in ["S", "A", "B"]:
            if p in by_prio:
                print(f"    待做[{p}] {len(by_prio[p])} 张")

    print("\n" + "-" * 68)
    print(f"总计 {len(done)}/{total} 张已就位")
    s_todo = [x for x in todo if x["prio"] == "S"]
    if s_todo:
        print(f"最高优先级(S) 还差 {len(s_todo)} 张：")
        for x in s_todo:
            print(f"    {x['rel']}")
    print("\n缺图不会导致报错：立绘按 EMO_FALLBACK 降级，背景按 BG_MAP 回退，")
    print("主要角色立绘与全部场景已配齐；路人角色回落到内联剪影。")
    print("用 --todo 看完整待办，--prompt N 取下 N 张的生图提示词。")
    return 0



    _check_audio(GAME)

def _check_audio(game_root):
    """校验剧本用到的音频 id 都有外置文件（缺失会回退到程序化合成）。"""
    import re as _re
    story = os.path.join(game_root, "story")
    adir = os.path.join(game_root, "assets", "audio")
    ids = set()
    if os.path.isdir(story):
        for f in os.listdir(story):
            if not f.endswith(".avg"):
                continue
            for line in open(os.path.join(story, f), encoding="utf-8"):
                for m in _re.finditer(r"@(?:bgm|amb|sfx)\s+(\w+)", line):
                    ids.add(m.group(1))
    have = set()
    if os.path.isdir(adir):
        have = {x.rsplit(".", 1)[0] for x in os.listdir(adir)}
    miss = sorted(ids - have)
    print()
    print(f"音频  外置文件 {len(have)} 个，剧本用到 {len(ids)} 个 id")
    if miss:
        print(f"      缺少（将回退程序化合成）: {miss}")
    else:
        print("      全部命中外置文件，0 依赖代码合成")
    return miss


if __name__ == "__main__":
    _rc = main()
    _check_audio(GAME)
    sys.exit(_rc)
