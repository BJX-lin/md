#!/usr/bin/env python3
"""背景图优化：为手机端压缩场景图

AI 生成的原图是 1408x768 左右的无损 PNG，单张 2MB+，
一整套 22 张会超过 50MB，对手机端包体和显存都不友好。

处理：
  1. 缩放到目标宽度（默认 1920，覆盖主流手机横屏分辨率）
  2. 量化到 256 色调色板 PNG——本作是低饱和冷色调，
     色带在暗部几乎不可见，但体积能降到 1/5~1/8
  3. 对比量化前后，若质量损失过大（误差超阈值）则回退保留原图

用法：
  python3 tools/optimize_bg.py            # 处理 assets/bg 下所有 png
  python3 tools/optimize_bg.py --width 1600
  python3 tools/optimize_bg.py --dry      # 只报告，不改文件
"""
import argparse
import os
import sys

try:
    from PIL import Image, ImageChops, ImageStat
except ImportError:
    print("需要 Pillow: pip install pillow --break-system-packages")
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG_DIR = os.path.join(ROOT, "game", "assets", "bg")
MAX_MEAN_ERR = 6.0        # 量化后平均像素误差上限，超过则不量化


def optimize(path, width, dry=False):
    im = Image.open(path).convert("RGB")
    before = os.path.getsize(path)
    ow, oh = im.size

    if im.width > width:
        h = round(im.height * width / im.width)
        im = im.resize((width, h), Image.LANCZOS)

    # 量化到 256 色
    quant = im.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
    check = quant.convert("RGB")
    diff = ImageChops.difference(im, check)
    err = sum(ImageStat.Stat(diff).mean) / 3.0

    use_quant = err <= MAX_MEAN_ERR
    out = quant if use_quant else im

    if dry:
        return before, before, ow, oh, im.size, err, use_quant

    out.save(path, optimize=True)
    after = os.path.getsize(path)
    return before, after, ow, oh, im.size, err, use_quant


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=1920)
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    if not os.path.isdir(BG_DIR):
        print("没有 assets/bg 目录")
        return 0
    files = sorted(f for f in os.listdir(BG_DIR) if f.lower().endswith(".png"))
    if not files:
        print("assets/bg 下没有 png")
        return 0

    print("=" * 70)
    print(f"背景图优化（目标宽度 {args.width}，256 色量化）")
    print("=" * 70)
    tb = ta = 0
    for f in files:
        p = os.path.join(BG_DIR, f)
        b, a, ow, oh, ns, err, q = optimize(p, args.width, args.dry)
        tb += b
        ta += a
        tag = "量化" if q else "保留真彩(误差大)"
        print(f"  {f:32s} {ow}x{oh} → {ns[0]}x{ns[1]}  "
              f"{b/1024/1024:5.2f}MB → {a/1024/1024:5.2f}MB  err={err:.2f} {tag}")
    print("-" * 70)
    if args.dry:
        print("（dry run，未写入）")
    else:
        print(f"  合计 {tb/1024/1024:.1f}MB → {ta/1024/1024:.1f}MB "
              f"（省 {100*(1-ta/max(tb,1)):.0f}%）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
