#!/usr/bin/env python3
"""剧本正文质量检查

只检查"玩家会读到的文字"（台词与旁白），忽略指令行。

检查项：
  1. 正文里混入的拉丁字母/异常外文词（生成过程中的手滑）
  2. 中英文标点混用（正文里出现半角 , . ? ! : ; ）
  3. 疑似占位符 / 未替换文本（TODO、XXX、待补、???）
  4. 重复行（同一节点内连续出现完全相同的句子）
  5. 超长单行（阅读体验差，建议断句）
  6. 引号配对（“ ” 「 」）
  7. 各章正文字数统计
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORY = os.path.join(ROOT, "game", "story")

SPEAKER_RE = re.compile(r"^([a-z_]+)(\([^)]*\))?[:：]")
# 正文里允许出现的西文（数字、罗马数字式编号等）
ALLOW_LATIN = re.compile(r"^[\s0-9A-Za-z：:．.、,，%~\-—…()（）]*$")
PLACEHOLDER = re.compile(r"(TODO|FIXME|XXX|待补|待填|占位|\?\?\?|placeholder)", re.I)
MAX_LINE = 120


def body_text(line):
    """取出玩家实际读到的文字"""
    s = line.strip()
    if not s or s.startswith(("--", "==", "@", "*")):
        return None
    s = re.sub(r"^>\s*", "", s)
    m = SPEAKER_RE.match(s)
    if m:
        s = s[m.end():].strip()
    return s


def main():
    errors, warns = [], []
    stats = {}
    files = sorted(f for f in os.listdir(STORY) if f.endswith(".avg"))

    for fn in files:
        path = os.path.join(STORY, fn)
        total = 0
        prev = None
        prev_ln = 0
        cur_node = "?"
        for ln, raw in enumerate(open(path, encoding="utf-8"), 1):
            st = raw.strip()
            if st.startswith("=="):
                cur_node = st[2:].strip()
                prev = None
                continue
            t = body_text(raw)
            if t is None:
                continue
            total += len(t)

            # 1. 异常拉丁词（排除纯数字/编号行）
            latin = re.findall(r"[A-Za-zÀ-ÿ]{3,}", t)
            if latin and not ALLOW_LATIN.match(t):
                errors.append(f"{fn}:{ln} [{cur_node}] 正文混入外文词 {latin}: {t[:40]}")

            # 2. 中文里的半角标点
            if re.search(r"[\u4e00-\u9fff][,.?!;]", t) or re.search(r"[,.?!;][\u4e00-\u9fff]", t):
                warns.append(f"{fn}:{ln} [{cur_node}] 中英标点混用: {t[:40]}")

            # 3. 占位符
            if PLACEHOLDER.search(t):
                errors.append(f"{fn}:{ln} [{cur_node}] 疑似占位文本: {t[:40]}")

            # 4. 连续重复行
            if prev is not None and t == prev and len(t) > 6:
                warns.append(f"{fn}:{ln} [{cur_node}] 与上一行重复: {t[:34]}")
            prev = t
            prev_ln = ln

            # 5. 超长行
            if len(t) > MAX_LINE:
                warns.append(f"{fn}:{ln} [{cur_node}] 单行过长({len(t)}字)，建议断句")

            # 6. 引号配对
            if t.count("“") != t.count("”"):
                warns.append(f"{fn}:{ln} [{cur_node}] 引号不配对: {t[:40]}")

        stats[fn] = total

    print("=" * 66)
    print("剧本正文质量检查")
    print("=" * 66)
    total_all = sum(stats.values())
    for fn in files:
        print(f"  {fn:24s} {stats[fn]:6d} 字")
    print(f"  {'合计':24s} {total_all:6d} 字")
    print("-" * 66)
    for w in warns[:40]:
        print("  [warn ]", w)
    if len(warns) > 40:
        print(f"  ...另有 {len(warns)-40} 条警告")
    for e in errors:
        print("  [ERROR]", e)
    print("-" * 66)
    print(f"错误 {len(errors)} 个，警告 {len(warns)} 个")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
