#!/usr/bin/env python3
"""发行前把关：确认所有防篡改签名都是最新的。

三处签名必须同时正确，否则玩家一启动就会看到"本体被修改"：
  1. content_policy.gd 的规则签名（POLICY_SIGNATURE）
  2. integrity_manifest.gd 的核心文件摘要
  3. config.gd 的联系方式签名与二维码指纹

任何一处过期都返回非零，打包脚本据此中止。
"""
import base64
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")


def _read(p):
    return open(p, encoding="utf-8").read()


def _const(src, name):
    m = re.search(r'const %s := "([^"]*)"' % name, src)
    if m:
        return m.group(1)
    m = re.search(r"const %s := (\d+)" % name, src)
    return m.group(1) if m else ""


def _arr(src, name):
    m = re.search(r"const %s := \[(.*?)\n\]" % name, src, re.S)
    if not m:
        return []
    return re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))


def check_policy():
    p = os.path.join(GAME, "autoload", "content_policy.gd")
    src = _read(p)
    parts = [_const(src, "POLICY_VERSION")]
    for n in ["BLOCK_SEXUAL", "BLOCK_MINOR", "BLOCK_HARM",
              "BLOCK_HATE", "BLOCK_DOXX"]:
        parts.extend(_arr(src, n))
    parts.extend(_arr(src, "ALLOWED_CMDS"))
    for n in ["MAX_NODES", "MAX_TOTAL_CHARS", "MAX_LINE_CHARS"]:
        parts.append(_const(src, n))
    text = _const(src, "POLICY_SALT") + "|" + "\n".join(parts)
    actual = hashlib.sha256(text.encode()).hexdigest()
    want = _const(src, "POLICY_SIGNATURE")
    ok = actual == want
    print("  %s 内容规则签名" % ("✓" if ok else "✗"))
    if not ok:
        print("      过期 —— 请跑 python3 tools/gen_policy_sig.py --write")
    return 0 if ok else 1


def check_manifest():
    p = os.path.join(GAME, "autoload", "integrity_manifest.gd")
    if not os.path.isfile(p):
        print("  ✗ 缺少 integrity_manifest.gd")
        print("      请跑 python3 tools/gen_integrity.py --write")
        return 1
    src = _read(p)
    salt = _const(src, "SALT").encode()
    rows = re.findall(r'"([^"]+\.gd)": "([0-9a-f]+)"', src)
    if not rows:
        print("  ✗ 完整性清单为空")
        return 1
    bad = []
    for rel, want in rows:
        full = os.path.join(GAME, rel)
        if not os.path.isfile(full):
            bad.append(rel + "(缺失)")
            continue
        actual = hashlib.sha256(salt + open(full, "rb").read()).hexdigest()
        if actual != want:
            bad.append(rel)
    ok = not bad
    print("  %s 核心文件摘要（%d 个）" % ("✓" if ok else "✗", len(rows)))
    if bad:
        for b in bad:
            print("      过期: %s" % b)
        print("      请跑 python3 tools/gen_integrity.py --write")
    return 0 if ok else 1


def check_contact():
    p = os.path.join(GAME, "autoload", "config.gd")
    src = _read(p)
    key = "AfterEveningStudy::contact::v1".encode()
    rc = 0
    for enc_name, sig_name, label in [
            ("QQ_ENC", "QQ_SIG", "群号"),
            ("QQ_URL_ENC", "QQ_URL_SIG", "加群链接")]:
        enc, sig = _const(src, enc_name), _const(src, sig_name)
        if not enc:
            continue
        raw = base64.b64decode(enc)
        text = bytes(raw[i] ^ key[i % len(key)]
                     for i in range(len(raw))).decode("utf-8", "replace")
        ok = hashlib.sha256(key + text.encode() + key).hexdigest()[:32] == sig
        print("  %s 联系方式·%s" % ("✓" if ok else "✗", label))
        if not ok:
            rc = 1
    qr_sha = _const(src, "QQ_QR_SHA")
    qr_path = os.path.join(GAME, "assets", "ui", "qq_qr.png")
    if qr_sha and os.path.isfile(qr_path):
        actual = hashlib.sha256(open(qr_path, "rb").read()).hexdigest()
        ok = actual == qr_sha
        print("  %s 二维码图片指纹" % ("✓" if ok else "✗"))
        if not ok:
            print("      请跑 python3 tools/gen_contact.py <群号> --write")
            rc = 1
    return rc


def main():
    print("=" * 58)
    print("防篡改签名检查")
    print("=" * 58)
    rc = check_policy() | check_manifest() | check_contact()
    print("-" * 58)
    print("全部通过" if rc == 0 else "存在过期签名 —— 发行前必须修正")
    return rc


if __name__ == "__main__":
    sys.exit(main())
