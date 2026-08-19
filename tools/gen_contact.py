#!/usr/bin/env python3
"""换 QQ 群时，一条命令生成全部四个常量 + 二维码图片。

背景：联系方式在 config.gd 里是混淆存储 + 签名校验的，
手改会导致签名对不上、游戏直接判定为"被篡改"而拒绝显示。
必须用本脚本重新生成。

用法：
    python3 tools/gen_contact.py 743689780
    python3 tools/gen_contact.py 743689780 --write   # 直接改 config.gd 并重生成二维码

生成物：
    QQ_ENC / QQ_SIG / QQ_URL_ENC / QQ_URL_SIG / QQ_QR_SHA
    game/assets/ui/qq_qr.png
"""
import base64
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
CFG = os.path.join(GAME, "autoload", "config.gd")
QR_PATH = os.path.join(GAME, "assets", "ui", "qq_qr.png")

# 必须与 config.gd 的 _CONTACT_KEY 完全一致
KEY = "AfterEveningStudy::contact::v1".encode("utf-8")


def obfuscate(text: str) -> str:
    b = text.encode("utf-8")
    out = bytes(c ^ KEY[i % len(KEY)] for i, c in enumerate(b))
    return base64.b64encode(out).decode()


def sign(text: str) -> str:
    return hashlib.sha256(KEY + text.encode("utf-8") + KEY).hexdigest()[:32]


def make_qr(url: str, path: str) -> str:
    """生成二维码并返回其 SHA256。需要 qrcode + pillow。"""
    import qrcode
    from qrcode.constants import ERROR_CORRECT_H
    from PIL import Image, ImageDraw

    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_H, box_size=10, border=2)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color=(24, 24, 28),
                        back_color=(232, 230, 222)).convert("RGB")
    img = img.resize((512, 512), Image.NEAREST)

    pad = 28
    canvas = Image.new("RGB", (512 + pad * 2, 512 + pad * 2), (232, 230, 222))
    canvas.paste(img, (pad, pad))
    d = ImageDraw.Draw(canvas)
    d.rectangle([0, 0, canvas.width - 1, canvas.height - 1],
                outline=(120, 115, 104), width=2)
    canvas.save(path, optimize=True)
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv
    if not args:
        print(__doc__)
        return 1
    qq = args[0].strip()
    if not qq.isdigit():
        print("群号应为纯数字：", qq)
        return 1
    url = "https://qm.qq.com/q/%s" % qq

    qq_enc, qq_sig = obfuscate(qq), sign(qq)
    url_enc, url_sig = obfuscate(url), sign(url)

    qr_sha = ""
    if write:
        try:
            qr_sha = make_qr(url, QR_PATH)
            print("已重新生成二维码：", os.path.relpath(QR_PATH, ROOT))
        except ImportError:
            print("!! 缺 qrcode/pillow，二维码未生成。")
            print("   pip install qrcode pillow --break-system-packages")
            return 1

    print()
    print('const QQ_ENC := "%s"' % qq_enc)
    print('const QQ_SIG := "%s"' % qq_sig)
    print('const QQ_URL_ENC := "%s"' % url_enc)
    print('const QQ_URL_SIG := "%s"' % url_sig)
    if qr_sha:
        print('const QQ_QR_SHA := "%s"' % qr_sha)
    print()

    if not write:
        print("以上内容需手动替换进 game/autoload/config.gd。")
        print("加 --write 可自动写入并重新生成二维码。")
        return 0

    src = open(CFG, encoding="utf-8").read()
    subs = [
        (r'const QQ_ENC := "[^"]*"', 'const QQ_ENC := "%s"' % qq_enc),
        (r'const QQ_SIG := "[^"]*"', 'const QQ_SIG := "%s"' % qq_sig),
        (r'const QQ_URL_ENC := "[^"]*"', 'const QQ_URL_ENC := "%s"' % url_enc),
        (r'const QQ_URL_SIG := "[^"]*"', 'const QQ_URL_SIG := "%s"' % url_sig),
        (r'const QQ_QR_SHA := "[^"]*"', 'const QQ_QR_SHA := "%s"' % qr_sha),
    ]
    for pat, rep in subs:
        if not re.search(pat, src):
            print("!! config.gd 里找不到:", pat)
            return 1
        src = re.sub(pat, rep, src, count=1)
    open(CFG, "w", encoding="utf-8").write(src)
    print("已写入 game/autoload/config.gd")
    print("建议接着跑：python3 tools/check_assets.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
