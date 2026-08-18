#!/usr/bin/env python3
"""把不同批次生成的美术统一到同一套色调，消除风格割裂。

背景：美术分多轮生成，前期是日系悬疑校园 AVG 风（低饱和冷调），
后期按《场景.md》要求改用写实厚涂风，道具特写又偏亮偏暖。
实测三批图的平均饱和度 0.285 / 0.257 / 0.362，明度 0.194 / 0.221 / 0.313——
道具图比场景图亮 61%，并排出现会明显跳脱。

做法：把每张图向全局基准（目标饱和度 / 明度）做加权靠拢，
只压差异、不做风格重绘，保留各自的构图与细节。
  - 饱和度：向目标值收敛，避免某几张过艳
  - 明度：整体对齐，避免忽明忽暗
  - 统一叠一层极淡的冷色（青蓝）统一色温
  - 保留 alpha（立绘）不动

用法：
  python3 tools/harmonize_art.py --dry       # 只报告，不写入
  python3 tools/harmonize_art.py             # 校正 bg
  python3 tools/harmonize_art.py --sprites   # 同时校正立绘
"""
import os
import sys
import argparse
import colorsys

from PIL import Image, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
if not os.path.isfile(os.path.join(GAME, "project.godot")):
    GAME = ROOT
BG = os.path.join(GAME, "assets", "bg")
SP = os.path.join(GAME, "assets", "sprites")

# 分组基准：白天场景本来就该比夜景亮，不能一刀切压暗，
# 否则 hallway_day / canteen_day 会被压成夜景，破坏叙事。
# 只统一「饱和度与色温」，明度按昼夜分组各自对齐。
TARGET_SAT = 0.265
LUM_DAY = 0.360      # 白天 / 室外阴天
LUM_NIGHT = 0.185    # 夜间 / 室内昏暗
# 文件名含这些词的按白天基准
DAY_HINT = ("_day", "day_", "canteen", "hallway_day", "title_school",
            "campus_rain", "keyvisual", "photo_wall", "graduation",
            "desk_carving")
# 道具特写单独一档：它们出现在昏暗室内，但作为特写需要看清细节，
# 取白天与夜间之间的中间值
PROP_HINT = ("prop_",)
LUM_PROP = 0.250
# 靠拢强度：1.0 = 完全对齐（会显得死板），0.6 保留各图性格
PULL = 0.6
# 统一冷色温：极淡的青蓝，避免各批次色温不一
COOL = (0.985, 0.995, 1.02)


def measure(im):
    small = im.convert("RGB").resize((72, 40))
    px = list(small.getdata())
    sat = lum = 0.0
    for r, g, b in px:
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        sat += s
        lum += l
    n = len(px)
    return sat / n, lum / n


def harmonize(path, dry=False):
    im = Image.open(path)
    alpha = im.getchannel("A") if im.mode == "RGBA" else None
    rgb = im.convert("RGB")
    s0, l0 = measure(rgb)
    if s0 <= 0.001 or l0 <= 0.001:
        return None

    name = os.path.basename(path).lower()
    if any(h in name for h in PROP_HINT):
        target_lum = LUM_PROP
    elif any(h in name for h in DAY_HINT):
        target_lum = LUM_DAY
    else:
        target_lum = LUM_NIGHT

    # 饱和度全局统一；明度按昼夜分组对齐
    s_factor = 1.0 + (TARGET_SAT / s0 - 1.0) * PULL
    l_factor = 1.0 + (target_lum / l0 - 1.0) * PULL
    # 限幅收紧：只压差异，不改变画面性质
    s_factor = max(0.70, min(1.30, s_factor))
    l_factor = max(0.82, min(1.20, l_factor))

    out = ImageEnhance.Color(rgb).enhance(s_factor)
    out = ImageEnhance.Brightness(out).enhance(l_factor)

    # 统一冷色温
    r, g, b = out.split()
    r = r.point(lambda v: min(255, int(v * COOL[0])))
    g = g.point(lambda v: min(255, int(v * COOL[1])))
    b = b.point(lambda v: min(255, int(v * COOL[2])))
    out = Image.merge("RGB", (r, g, b))

    s1, l1 = measure(out)
    if not dry:
        if alpha is not None:
            out = out.convert("RGBA")
            out.putalpha(alpha)
        out.save(path, optimize=True)
    return (s0, l0, s1, l1, s_factor, l_factor)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--sprites", action="store_true")
    a = ap.parse_args()

    files = [os.path.join(BG, f) for f in sorted(os.listdir(BG))
             if f.endswith(".png")]
    if a.sprites:
        for base, _, fs in os.walk(SP):
            files += [os.path.join(base, f) for f in sorted(fs)
                      if f.endswith(".png")]

    before_s = before_l = after_s = after_l = 0.0
    n = 0
    biggest = []
    for p in files:
        r = harmonize(p, a.dry)
        if r is None:
            continue
        s0, l0, s1, l1, sf, lf = r
        before_s += s0
        before_l += l0
        after_s += s1
        after_l += l1
        n += 1
        biggest.append((abs(1 - sf) + abs(1 - lf), os.path.basename(p), sf, lf))

    biggest.sort(reverse=True)
    print("调整幅度最大的 8 张：")
    for _, name, sf, lf in biggest[:8]:
        print(f"  {name:38s} 饱和×{sf:.2f}  明度×{lf:.2f}")
    print()
    print(f"共处理 {n} 张" + ("（--dry 未写入）" if a.dry else ""))
    print(f"  平均饱和度 {before_s / n:.3f} → {after_s / n:.3f}  "
          f"（目标 {TARGET_SAT}）")
    print(f"  平均明度   {before_l / n:.3f} → {after_l / n:.3f}  "
          f"（白天 {LUM_DAY} / 夜间 {LUM_NIGHT}）")

    # 分组离散度：标准差越小越统一
    def spread(paths):
        vals = []
        for p in paths:
            s, l = measure(Image.open(p))
            vals.append((s, l))
        if not vals:
            return 0, 0
        ms = sum(v[0] for v in vals) / len(vals)
        ml = sum(v[1] for v in vals) / len(vals)
        ds = (sum((v[0] - ms) ** 2 for v in vals) / len(vals)) ** 0.5
        dl = (sum((v[1] - ml) ** 2 for v in vals) / len(vals)) ** 0.5
        return ds, dl

    if not a.dry:
        ds, dl = spread([os.path.join(BG, f) for f in os.listdir(BG)
                         if f.endswith(".png")])
        print(f"  背景离散度 饱和σ={ds:.3f}  明度σ={dl:.3f}（越小越统一）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
