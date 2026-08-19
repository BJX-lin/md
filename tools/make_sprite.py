#!/usr/bin/env python3
"""立绘后处理：白底转透明 + 去重影 + 裁切 + 竖向画布

生成器输出的是横向白底图，且偶尔带半透明重影副本。
本脚本把它处理成 VN 可直接用的透明背景立绘。

流程：
  1. 洪水填充式白底去除（从四边向内，只删连通的白色区域，保护角色内部白色）
  2. 连通域分析，只保留最大的人物主体（去掉重影/残片）
  3. 按不透明像素裁切到最小外接框
  4. 放进竖向透明画布（默认 768x1280），底部对齐、水平居中

用法：
  python3 tools/make_sprite.py game/assets/sprites/xuqing/xuqing_01_neutral.png
  python3 tools/make_sprite.py --all          # 处理 sprites 下所有 png
"""
import argparse
import os
import sys
from collections import deque

try:
    from PIL import Image
except ImportError:
    print("需要 Pillow: pip install pillow --break-system-packages")
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITE_DIR = os.path.join(ROOT, "game", "assets", "sprites")
CANVAS = (768, 1280)
WHITE_THRESHOLD = 236      # 高于此值视为背景白
EDGE_SOFTEN = 2            # 边缘羽化半径


def remove_white_bg(im, thr=WHITE_THRESHOLD):
    """从四边洪水填充，只清除与边界连通的白色，保护角色内部的白色（校服条纹等）"""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    def is_bg(x, y):
        r, g, b, a = px[x, y]
        return r >= thr and g >= thr and b >= thr

    visited = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not visited[y * w + x] and is_bg(x, y):
                visited[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y * w + x] and is_bg(x, y):
                visited[y * w + x] = 1
                q.append((x, y))

    while q:
        x, y = q.popleft()
        px[x, y] = (255, 255, 255, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny * w + nx] and is_bg(nx, ny):
                visited[ny * w + nx] = 1
                q.append((nx, ny))
    return im


def keep_largest_blob(im, min_ratio=0.15):
    """只保留最大连通域（人物主体），删除重影/碎片"""
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    blobs = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or px[sx, sy][3] < 24:
                continue
            comp = []
            seen[sy * w + sx] = 1
            q = deque([(sx, sy)])
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny][3] >= 24:
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            blobs.append(comp)
    if not blobs:
        return im, 0
    blobs.sort(key=len, reverse=True)
    biggest = len(blobs[0])
    removed = 0
    for comp in blobs[1:]:
        if len(comp) < biggest * min_ratio:
            for x, y in comp:
                px[x, y] = (255, 255, 255, 0)
            removed += 1
    return im, removed



def drop_ghost_columns(im, ghost_sat=26, ghost_min_alpha=24):
    """删除低饱和度的半透明重影副本。

    生成器有时会在主体旁边吐一个灰白色的复制影子。它常与主体像素连通，
    连通域法删不掉，但它有个稳定特征：几乎无彩度（R≈G≈B）且偏灰。
    做法：按列统计"有彩色像素"的分布，找出主体列区间，
    区间外若整列都是灰的，就整列清掉。
    """
    w, h = im.size
    px = im.load()
    colorful = [0] * w
    for x in range(w):
        c = 0
        for y in range(0, h, 3):          # 隔行采样，够用且快
            r, g, b, a = px[x, y]
            if a < ghost_min_alpha:
                continue
            if max(r, g, b) - min(r, g, b) > ghost_sat:
                c += 1
        colorful[x] = c

    peak = max(colorful) if colorful else 0
    if peak == 0:
        return im, 0
    thr = peak * 0.12
    cols = [x for x in range(w) if colorful[x] >= thr]
    if not cols:
        return im, 0

    # 从彩度最高的列向两侧扩展，得到主体列区间
    center = colorful.index(peak)
    lo = hi = center
    while lo - 1 >= 0 and colorful[lo - 1] >= thr:
        lo -= 1
    while hi + 1 < w and colorful[hi + 1] >= thr:
        hi += 1

    # 安全阀：低饱和角色（黑白灰服装）整体彩度低，容易被误判。
    # 只有当主体区间已足够宽（>=45% 画宽），才敢清除区间外内容。
    if (hi - lo + 1) < w * 0.45:
        return im, 0

    # 再确认区间外确实存在成片内容（真重影），而不是零星描边
    outside = 0
    for x in range(w):
        if lo <= x <= hi:
            continue
        for y in range(0, h, 4):
            if px[x, y][3] >= ghost_min_alpha:
                outside += 1
                break
    if outside < w * 0.06:
        return im, 0

    removed = 0
    for x in range(w):
        if lo <= x <= hi:
            continue
        has = False
        for y in range(h):
            if px[x, y][3] >= ghost_min_alpha:
                px[x, y] = (255, 255, 255, 0)
                has = True
        if has:
            removed += 1
    return im, (1 if removed else 0)


def soften_edges(im, radius=EDGE_SOFTEN):
    """轻微羽化 alpha 边缘，避免锯齿"""
    try:
        from PIL import ImageFilter
        a = im.getchannel("A").filter(ImageFilter.GaussianBlur(radius * 0.5))
        im.putalpha(a)
    except Exception:
        pass
    return im


def fit_canvas(im, canvas=CANVAS, margin_bottom=8):
    bbox = im.getbbox()
    if not bbox:
        return im
    im = im.crop(bbox)
    cw, ch = canvas
    avail_h = ch - margin_bottom
    scale = min(avail_h / im.height, cw * 0.96 / im.width)
    nw, nh = max(1, int(im.width * scale)), max(1, int(im.height * scale))
    im = im.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.paste(im, ((cw - nw) // 2, ch - margin_bottom - nh), im)
    return out


def solidify_alpha(im, solid_thr=190, edge_lo=12):
    """把「本该实心」的像素 alpha 拉回 255。

    FASTOCTREE 量化会把 alpha 一起纳入调色板，导致人物躯干的 255
    被近似成 87~246 —— 表现为整个立绘半透明，像幽灵/全息投影。
    这里只保留真正的边缘羽化（介于 edge_lo..solid_thr 之间的过渡带），
    其余一律归为全不透明或全透明。
    """
    im = im.convert("RGBA")
    a = im.getchannel("A")
    # >=solid_thr 视为主体，强制 255；<=edge_lo 视为背景，强制 0；中间保留做抗锯齿
    lut = [0 if v <= edge_lo else (255 if v >= solid_thr else v) for v in range(256)]
    im.putalpha(a.point(lut))
    return im


def compress(path, colors=200):
    """RGBA 量化压缩（保留 alpha）。
    Pillow 对 RGBA 只支持 FASTOCTREE / libimagequant。
    量化会破坏 alpha，故量化后必须重新贴回原始 alpha 通道。"""
    im = Image.open(path).convert("RGBA")
    before = os.path.getsize(path)
    im = solidify_alpha(im)
    alpha = im.getchannel("A")          # 量化前先留底
    q = im.quantize(colors=colors, method=Image.FASTOCTREE).convert("RGBA")
    q.putalpha(alpha)                   # 用未被量化污染的 alpha 覆盖回去
    q = solidify_alpha(q)
    q.save(path, optimize=True)
    return before, os.path.getsize(path)


def process(path, canvas=CANVAS):
    im = Image.open(path)
    orig = im.size
    # 幂等保护：已是透明底的图不再重复抠白/羽化，只做裁切归位
    already = False
    if im.mode == "RGBA":
        a = im.getchannel("A")
        transparent = sum(1 for v in a.resize((64, 64)).getdata() if v < 16)
        already = transparent > 64 * 64 * 0.2
    if already:
        # 已抠好的图必须完全不动：fit_canvas 会再次裁切+缩放，
        # 反复执行会把人物越缩越小，最终 alpha 全空（曾毁掉 4 张图）。
        # 半身图（crop_sprites.py 裁过，高宽比接近 1:1）同样跳过，
        # 否则会被重新拉回 768x1280 全身画布，白白吃掉 40% 显存。
        if im.size[0] > 0 and im.size[1] / im.size[0] < 1.35:
            print(f"  {os.path.relpath(path, ROOT)}  已是半身图，跳过")
            return True
        if im.size == canvas:
            print(f"  {os.path.relpath(path, ROOT)}  已是透明底且尺寸正确，跳过")
            return True
        im2 = fit_canvas(im, canvas)
        a2 = im2.getchannel("A")
        ratio2 = sum(1 for v in a2.getdata() if v > 128) / (canvas[0] * canvas[1]) * 100
        if ratio2 < 3.0:
            print(f"  {os.path.relpath(path, ROOT)}  !! 归位后人物占比 "
                  f"{ratio2:.1f}%，判定为异常，保持原样不写回")
            return False
        im2.save(path)
        print(f"  {os.path.relpath(path, ROOT)}  已是透明底，仅重新归位")
        return True
    im = remove_white_bg(im)
    im, removed = keep_largest_blob(im)
    im, ghosts = drop_ghost_columns(im)
    removed += ghosts
    im = soften_edges(im)
    im = fit_canvas(im, canvas)
    a = im.getchannel("A")
    opaque = sum(1 for v in a.getdata() if v > 128)
    ratio = opaque / (canvas[0] * canvas[1]) * 100
    if ratio < 3.0:
        print(f"  {os.path.relpath(path, ROOT)}  !! 抠图后人物占比 "
              f"{ratio:.1f}%，判定为失败，保持原文件不覆盖")
        return False
    im.save(path)
    print(f"  {os.path.relpath(path, ROOT)}")
    print(f"    {orig[0]}x{orig[1]} → {canvas[0]}x{canvas[1]}  "
          f"去除残影 {removed} 处  人物占比 {ratio:.1f}%")
    return ratio > 3.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--compress", action="store_true", help="只做量化压缩，不重新抠图")
    args = ap.parse_args()

    targets = []
    if args.all:
        for base, _, fs in os.walk(SPRITE_DIR):
            for f in sorted(fs):
                if f.endswith(".png"):
                    targets.append(os.path.join(base, f))
    else:
        targets = [p if os.path.isabs(p) else os.path.join(ROOT, p) for p in args.paths]

    if not targets:
        print("没有指定文件。用法：make_sprite.py <png> 或 --all")
        return 1

    if args.compress:
        tb = ta = 0
        print(f"压缩 {len(targets)} 张立绘")
        for p in targets:
            b, a = compress(p)
            tb += b
            ta += a
            print(f"  {os.path.relpath(p, ROOT):52s} {b/1024/1024:.2f}MB → {a/1024/1024:.2f}MB")
        print(f"合计 {tb/1024/1024:.1f}MB → {ta/1024/1024:.1f}MB "
              f"（省 {100*(1-ta/max(tb,1)):.0f}%）")
        return 0

    print(f"处理 {len(targets)} 张立绘")
    ok = 0
    for p in targets:
        try:
            if process(p):
                ok += 1
        except Exception as e:
            print(f"  [失败] {p}: {e}")
    print(f"完成 {ok}/{len(targets)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
