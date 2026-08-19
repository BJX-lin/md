#!/usr/bin/env python3
"""重算 content_policy.gd 的规则签名。

改了任何一条内容规则（禁词、上限、指令白名单）之后必须跑这个，
否则游戏启动自校验会判定"本体被篡改"并停用创意工坊。

这正是设计意图：只有能改工程源码的人（作者）才能调整规则，
而且必须显式地重新签名，不会因为手滑改一个字就悄悄放行违规内容。

用法：
    python3 tools/gen_policy_sig.py           # 只打印
    python3 tools/gen_policy_sig.py --write   # 直接写回 content_policy.gd
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GD = os.path.join(ROOT, "game", "autoload", "content_policy.gd")


def parse_array(src, name):
    """抓出 const NAME := [ ... ] 里的全部字符串字面量，保持源码顺序。"""
    m = re.search(r"const %s := \[(.*?)\n\]" % name, src, re.S)
    if not m:
        raise SystemExit("找不到数组: " + name)
    return re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))


def parse_const(src, name):
    m = re.search(r'const %s := "([^"]*)"' % name, src)
    if m:
        return m.group(1)
    m = re.search(r"const %s := (\d+)" % name, src)
    if not m:
        raise SystemExit("找不到常量: " + name)
    return m.group(1)


def main():
    src = open(GD, encoding="utf-8").read()

    parts = [parse_const(src, "POLICY_VERSION")]
    for name in ["BLOCK_SEXUAL", "BLOCK_MINOR", "BLOCK_HARM",
                 "BLOCK_HATE", "BLOCK_DOXX"]:
        parts.extend(parse_array(src, name))
    parts.extend(parse_array(src, "ALLOWED_CMDS"))
    for name in ["MAX_NODES", "MAX_TOTAL_CHARS", "MAX_LINE_CHARS"]:
        parts.append(parse_const(src, name))

    salt = parse_const(src, "POLICY_SALT")
    text = salt + "|" + "\n".join(parts)
    sig = hashlib.sha256(text.encode("utf-8")).hexdigest()

    cur = parse_const(src, "POLICY_SIGNATURE")
    print("规则条目 : %d" % len(parts))
    print("当前签名 : %s" % cur)
    print("实际签名 : %s" % sig)
    print("状态     : %s" % ("一致" if cur == sig else "不一致，需更新"))

    if "--write" in sys.argv:
        if cur == sig:
            print("\n无需改动。")
            return 0
        src2 = re.sub(r'const POLICY_SIGNATURE := "[^"]*"',
                      'const POLICY_SIGNATURE := "%s"' % sig, src, count=1)
        open(GD, "w", encoding="utf-8").write(src2)
        print("\n已写回 content_policy.gd")
    elif cur != sig:
        print("\n加 --write 可自动更新。")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
