#!/usr/bin/env python3
"""把 game/story/*.avg 导出为一份可阅读的 Markdown 剧本全文。

.avg 是给引擎读的 DSL，混着 @bg / @set / @flag 之类的演出与数值指令。
这里把它转成人能顺畅读下去的文本：

  - 保留章节 / 节点结构，节点转成带锚点的小标题
  - 角色台词转成「角色名：台词」，旁白与心理独白按原样保留
  - 选项转成列表，并标注它跳转到哪个节点、有什么前置条件
  - 演出指令（@bg / @fx / @wait / @sfx）折叠成一行灰色注记，不打断阅读
  - 数值与 flag 变化收进选项后面的括号，方便看清每个选择的影响
  - 开头附全书信息、章节目录、角色表与阅读说明

用法：
  python3 tools/export_script_md.py                 # 输出到 docs/剧本全文.md
  python3 tools/export_script_md.py --out X.md      # 指定输出路径
"""
import os
import re
import sys
import argparse
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
if not os.path.isfile(os.path.join(GAME, "project.godot")):
    GAME = ROOT
STORY = os.path.join(GAME, "story")

# 文件 → 章节归属与说明
FILE_INFO = OrderedDict([
    ("00_prologue.avg", ("序章", "雨夜，南栖中学，东楼那扇新换木条的窗")),
    ("10_ch1.avg", ("第一章 《点名》", "报到第一天，主线")),
    ("12_ch1_day.avg", ("第一章 《点名》", "白天支线：所有异常都伪装成普通校园细节")),
    ("15_ch1_side.avg", ("第一章 《点名》", "午休自由探索")),
    ("18_ch1b.avg", ("第一章 《点名》", "第一夜：查寝与门外的东西")),
    ("20_ch2.avg", ("第二章 《名单》", "主线：借书卡、旧楼、名册第四十二行")),
    ("23_ch2_school.avg", ("第二章 《名单》", "支线：在活人身上找证据")),
    ("25_ch2_side.avg", ("第二章 《名单》", "支线：图书馆与教务处")),
    ("27_liheng.avg", ("第二章 《名单》", "支线：李恒——最沉默的那个人")),
    ("28_ch2_night.avg", ("第二章 《名单》", "支线：雨夜的宿舍楼")),
    ("30_ch3.avg", ("第三章 《替身》", "主线：梁野的异变")),
    ("33_ch3_deep.avg", ("第三章 《替身》", "支线：查寝后到天亮的四小时")),
    ("35_ch3_side.avg", ("第三章 《替身》", "支线：夜间探索")),
    ("37_zhouyun.avg", ("第三章 《替身》", "支线：周芸——把「少一个人」带出校园")),
    ("40_ch4.avg", ("第四章 《照片》", "主线：校史馆与内档室")),
    ("43_xuqing.avg", ("第四章 《照片》", "支线：许清——上一个没能停下来的人")),
    ("44_oldqin.avg", ("第四章 《照片》", "支线：老秦——在册/待定/删除")),
    ("45_ch4_side.avg", ("第四章 《照片》", "支线：档案室周边")),
    ("47_ch4_archive.avg", ("第四章 《照片》", "支线：内档室深挖")),
    ("48_liheng2.avg", ("第四章 《照片》", "支线：两个「待定」的人正面对话")),
    ("50_final.avg", ("终章 《晚自习之后》", "五个结局")),
])

CHARS = OrderedDict([
    ("me", "林昼（主角）"), ("linday", "林昼（主角）"),
    ("zhouxu", "周叙"), ("liangye", "梁野"), ("xuqing", "许清老师"),
    ("shenhe", "沈禾"), ("oldqin", "老秦"), ("liheng", "李恒"),
    ("dorm_keeper", "宿管阿姨"), ("canteen_aunt", "食堂阿姨"),
    ("classmate", "同学"), ("classmate_boy", "擦黑板的男生"),
    ("classmate_girl", "前排女生"), ("unknown", "？？？"),
])

NUM_LABEL = {
    "truth": "真相", "sanity": "理智", "memory_echo": "记忆回响",
    "shenhe_focus": "沈禾关注", "save_route_score": "拯救倾向",
    "end_cycle_score": "终结循环", "control_route_score": "管理者倾向",
    "route_obedience": "服从", "route_investigate": "调查",
    "route_empathy": "共情", "route_hostility": "敌意",
    "taboo_count": "禁忌", "trust_zhouxu": "周叙信任",
    "trust_liangye": "梁野信任", "trust_xuqing": "许清信任",
    "trust_oldqin": "老秦信任",
}

# 纯演出指令：折叠成注记
STAGE = {"bg", "bgm", "amb", "sfx", "fx", "wait", "show", "hide",
         "clearchars", "stopbgm", "stopamb", "autosave", "overlay",
         "time", "advtime", "title", "chapter"}
# 影响类指令：附在选项/节点后
EFFECT = {"set", "flag", "item", "clue", "state", "death", "ending"}


def esc(s):
    """Markdown 转义：避免正文里的符号被解析成语法"""
    return s.replace("\\", "\\\\").replace("*", "\\*").replace("_", "\\_")


def fmt_effect(cmd, args):
    if cmd == "set" and len(args) >= 2:
        return f"{NUM_LABEL.get(args[0], args[0])} {args[1]}"
    if cmd == "flag":
        return f"标记 {args[0]}" if args else "标记"
    if cmd == "item":
        a = args[0] if args else ""
        return f"获得道具 {a.lstrip('+')}" if a.startswith("+") else f"道具 {a}"
    if cmd == "clue":
        return f"获得线索 {args[0]}" if args else "获得线索"
    if cmd == "state" and len(args) >= 2:
        return f"状态 {args[0]}={args[1]}"
    if cmd == "death":
        return f"**死亡：{args[0] if args else ''}**"
    if cmd == "ending":
        return f"**结局：{args[0] if args else ''}**"
    return cmd


def convert(path):
    out = []
    pending_stage = []
    pending_fx = []

    def flush_stage():
        if pending_stage:
            out.append(f"> `演出` {' · '.join(pending_stage)}\n")
            pending_stage.clear()

    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        st = line.strip()

        if not st:
            continue
        # 注释
        if st.startswith("--"):
            txt = st.lstrip("-").strip()
            if txt:
                out.append(f"<!-- {txt} -->\n")
            continue
        # 节点
        if st.startswith("== "):
            flush_stage()
            nid = st[3:].strip()
            out.append(f"\n<a id=\"{nid}\"></a>\n")
            out.append(f"#### ◇ `{nid}`\n")
            continue
        # 指令
        if st.startswith("@"):
            m = re.match(r"@(\w+)\s*(.*)$", st)
            if not m:
                continue
            cmd, rest = m.group(1), m.group(2).strip()
            args = rest.split() if rest else []
            if cmd == "chapter":
                flush_stage()
                out.append(f"\n### 　\n")
                continue
            if cmd == "note":
                flush_stage()
                body = rest.replace("\\n", "\n> ")
                out.append(f"\n> **【文本 / 纸面内容】**\n> {body}\n")
                continue
            if cmd in ("if", "else", "endif", "elif"):
                flush_stage()
                if cmd == "if":
                    out.append(f"\n**〔条件分支：若 {esc(rest)}〕**\n")
                elif cmd == "else":
                    out.append(f"\n**〔否则〕**\n")
                else:
                    out.append(f"\n**〔分支结束〕**\n")
                continue
            if cmd == "goto":
                flush_stage()
                if rest == "__ending__":
                    # 引擎的动态结局派发，不是真实节点
                    out.append("\n→ **进入结局判定**（依据变量走五个结局之一）\n")
                else:
                    out.append(f"\n→ 跳转至 [`{rest}`](#{rest})\n")
                continue
            if cmd == "return":
                flush_stage()
                out.append("\n→ 返回上层\n")
                continue
            if cmd in EFFECT:
                pending_fx.append(fmt_effect(cmd, args))
                continue
            if cmd in STAGE:
                if cmd == "wait":
                    continue
                if cmd == "bg":
                    pending_stage.append(f"场景＝{rest}")
                elif cmd == "show":
                    who = args[0] if args else ""
                    pending_stage.append(f"{CHARS.get(who, who)} 出场"
                                         + (f"（{args[1]}）" if len(args) > 1 else ""))
                elif cmd in ("bgm", "amb", "sfx", "fx"):
                    pending_stage.append(f"{cmd} {rest}")
                elif cmd == "time":
                    pending_stage.append(f"时间＝第{args[0]}天 {args[1] if len(args) > 1 else ''}")
                elif cmd == "title":
                    out.append(f"\n**〔{rest}〕**\n")
                continue
            continue
        # 选项
        if st.startswith("*"):
            flush_stage()
            body = st.lstrip("*").strip()
            cond = ""
            mc = re.match(r"\[(?:if|lock)\s+([^\]]+)\]\s*(.*)$", body)
            if mc:
                cond, body = mc.group(1), mc.group(2)
            tgt = ""
            mt = re.search(r"->\s*(\S+)\s*$", body)
            if mt:
                tgt = mt.group(1)
                body = body[:mt.start()].strip()
            s = f"- **选项**：{esc(body)}"
            if tgt:
                s += f" → [`{tgt}`](#{tgt})"
            if cond:
                s += f"　*〔需要：{esc(cond)}〕*"
            out.append(s + "\n")
            if pending_fx:
                out.append(f"  - 影响：{' / '.join(pending_fx)}\n")
                pending_fx.clear()
            continue
        # 台词 / 旁白
        flush_stage()
        if pending_fx:
            out.append(f"> `影响` {' / '.join(pending_fx)}\n")
            pending_fx.clear()
        m = re.match(r"^([A-Za-z_][\w]*)(?:\(([^)]*)\))?：(.*)$", st)
        if m:
            who, emo, txt = m.group(1), m.group(2), m.group(3)
            name = CHARS.get(who, who)
            tag = f"（{emo}）" if emo else ""
            out.append(f"**{name}**{tag}：{esc(txt)}\n")
            continue
        if st.startswith(">"):
            out.append(f"*{esc(st.lstrip('>').strip())}*\n")
            continue
        out.append(f"{esc(st)}\n")

    flush_stage()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "剧本全文.md"))
    a = ap.parse_args()

    files = [f for f in sorted(os.listdir(STORY)) if f.endswith(".avg")]
    # 统计
    total_chars = 0
    total_nodes = 0
    for f in files:
        src = open(os.path.join(STORY, f), encoding="utf-8").read()
        total_nodes += len(re.findall(r"^== ", src, re.M))
        for line in src.split("\n"):
            s = line.strip()
            if s and not s.startswith(("@", "--", "==", "*", ">")):
                s = re.sub(r"^[A-Za-z_][\w]*(?:\([^)]*\))?：", "", s)
                total_chars += len(re.sub(r"\s", "", s))

    doc = []
    doc.append("# 《晚自习之后》剧本全文\n")
    doc.append("> 国产校园恐怖文字互动视觉小说 · 完整剧本\n")
    doc.append(f"> 共 **{len(files)}** 个剧本文件 · **{total_nodes}** 个节点 · "
               f"正文约 **{total_chars:,}** 字\n")
    doc.append("\n---\n")
    doc.append("\n## 阅读说明\n")
    doc.append("本文由 `game/story/*.avg` 自动生成（`tools/export_script_md.py`）。"
               "`.avg` 是给引擎读的脚本格式，这里已转换为可读文本：\n")
    doc.append("""
| 标记 | 含义 |
|---|---|
| `#### ◇ 节点名` | 一个剧本节点，选项跳转的落点 |
| **角色名**：台词 | 角色对白，括号内是表情差分 |
| *斜体* | 主角的心理独白 / 旁白强调 |
| **【文本 / 纸面内容】** | 剧中出现的纸条、名单、短信等 |
| **选项** | 玩家可选分支，标注跳转目标与解锁条件 |
| `影响` / 影响 | 该处造成的数值、标记、道具、线索变化 |
| `演出` | 场景、音乐、音效、立绘等演出指令（不影响阅读） |
| **〔条件分支〕** | 依据变量状态展开的不同内容 |
""")
    doc.append("\n> 剧本是**非线性**的：同一节点在不同变量状态下呈现不同内容，"
               "选项会改变后续走向与结局。按顺序通读可了解全部内容，"
               "但实际游玩单周目只会经历其中一部分。\n")

    doc.append("\n## 主要角色\n")
    doc.append("""
| 角色 | 身份 | 一句话 |
|---|---|---|
| **林昼** | 转学生，主角 | 「你不是转学生，你是补位。」 |
| **周叙** | 班长 | 「我没记错。我只是证明不了。」 |
| **梁野** | 同班同学，307 室友 | 敞着校服的吊儿郎当，直到拉链拉到顶那天 |
| **李恒** | 307 第四个室友 | 「说了就得记住。记住了，忘的时候就疼。」 |
| **许清** | 班主任 | 赤脚五年，每天点名念完整的四十二个 |
| **老秦** | 夜班保安 | 「勾是我还记得脸的。叉是我只记得名字了。」 |
| **沈禾** | 五年前失踪的女生 | 「你也别替我答到。」 |
| **周芸** | 周叙的姐姐 | 四十二张票，四十一个人 |
""")

    doc.append("\n## 目录\n")
    cur_ch = None
    for f in files:
        ch, desc = FILE_INFO.get(f, ("其他", ""))
        if ch != cur_ch:
            doc.append(f"\n**{ch}**\n")
            cur_ch = ch
        anchor = f.replace(".avg", "").replace("_", "-")
        doc.append(f"- [{f}](#{anchor}) — {desc}\n")

    doc.append("\n---\n")

    cur_ch = None
    for f in files:
        ch, desc = FILE_INFO.get(f, ("其他", ""))
        if ch != cur_ch:
            doc.append(f"\n\n# {ch}\n")
            cur_ch = ch
        anchor = f.replace(".avg", "").replace("_", "-")
        src = open(os.path.join(STORY, f), encoding="utf-8").read()
        n_nodes = len(re.findall(r"^== ", src, re.M))
        doc.append(f"\n<a id=\"{anchor}\"></a>\n")
        doc.append(f"\n## {f}\n")
        doc.append(f"*{desc} · {n_nodes} 个节点*\n")
        doc.append("\n")
        doc.extend(convert(os.path.join(STORY, f)))

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write("".join(doc))
    size = os.path.getsize(a.out)
    print(f"已导出：{a.out}")
    print(f"  {len(files)} 个剧本 · {total_nodes} 个节点 · 正文约 {total_chars:,} 字")
    print(f"  文档大小 {size / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
