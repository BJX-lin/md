#!/usr/bin/env python3
"""把全身立绘裁成半身，大幅削减显存占用。

背景：演出改为半身构图后，立绘只显示「头顶 → 腰线」这一段，
腰以下永远被文本框遮住。但 768x1280 的整张图仍然会被解码进显存
（每张 768*1280*4 ≈ 3.75 MB），下半身纯属浪费。

做法：按 WAIST_RATIO 裁掉腰线以下的部分，并留一点余量供呼吸浮动。
裁完后 game_screen 的布局公式同步改为 1.0（图本身就是到腰为止）。

  768x1280 → 768x768   显存 3.75MB → 2.25MB   每张省 40%

用法：
  python3 tools/crop_sprites.py --dry     # 只看会怎么裁
  python3 tools/crop_sprites.py           # 实际执行
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
if not os.path.isfile(os.path.join(GAME, "project.godot")):
    GAME = ROOT
SPRITE_DIR = os.path.join(GAME, "assets", "sprites")

# 腰线在全身高度的比例（与 game_screen._layout_actors 保持一致）
WAIST_RATIO = 0.55
# 腰线以下额外保留的余量，供呼吸浮动与文本框边缘遮挡
MARGIN = 0.05
KEEP = WAIST_RATIO + MARGIN          # 0.60


def main():
    dry = "--dry" in sys.argv
    if not os.path.isdir(SPRITE_DIR):
        print("找不到立绘目录:", SPRITE_DIR)
        return 1

    files = []
    for base, _, fs in os.walk(SPRITE_DIR):
        for f in sorted(fs):
            if f.endswith(".png"):
                files.append(os.path.join(base, f))

    before_vram = after_vram = 0
    before_disk = after_disk = 0
    done = skipped = 0

    for p in files:
        im = Image.open(p).convert("RGBA")
        w, h = im.size
        before_vram += w * h * 4
        before_disk += os.path.getsize(p)

        new_h = int(round(h * KEEP))
        if new_h >= h:
            after_vram += w * h * 4
            after_disk += os.path.getsize(p)
            skipped += 1
            continue

        cropped = im.crop((0, 0, w, new_h))
        # 裁完后如果底部整行都是透明的，说明这个角色本来就没画到腰下，
        # 再往上收一点，避免留一条空白
        alpha = cropped.getchannel("A")
        bbox = alpha.getbbox()
        if bbox and bbox[3] < new_h:
            cropped = cropped.crop((0, 0, w, bbox[3]))

        if not dry:
            cropped.save(p, optimize=True)
        cw, ch = cropped.size
        after_vram += cw * ch * 4
        after_disk += os.path.getsize(p) if not dry else 0
        done += 1
        if done <= 5:
            print(f"  {os.path.relpath(p, SPRITE_DIR):46s} "
                  f"{w}x{h} → {cw}x{ch}")

    if done > 5:
        print(f"  … 其余 {done - 5} 张同样处理")
    print()
    print(f"处理 {done} 张，跳过 {skipped} 张"
          + ("（--dry 未实际写入）" if dry else ""))
    print(f"显存占用 {before_vram / 1024 / 1024:6.0f} MB → "
          f"{after_vram / 1024 / 1024:6.0f} MB "
          f"（省 {(1 - after_vram / before_vram) * 100:.0f}%）")
    if not dry:
        print(f"磁盘占用 {before_disk / 1024 / 1024:6.1f} MB → "
              f"{after_disk / 1024 / 1024:6.1f} MB")
        print()
        print("提醒：裁切后立绘本身就是「到腰为止」，")
        print("game_screen._layout_actors 的 WAIST_RATIO 需同步改为 1.0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
