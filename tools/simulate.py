#!/usr/bin/env python3
"""《晚自习之后》剧情运行时模拟器

用 Python 复刻 story_engine.gd / game_state.gd 的语义，离线跑通全流程，用于验证：
  * 任意随机路线都能跑到某个结局（无死循环、无断链）
  * 五个结局都可达（含定向剧本验证真结局）
  * 变量始终在合法区间内
  * 关键锁定选项（真结局链）能被满足

用法：
  python3 tools/simulate.py            # 随机 800 次通关 + 定向真结局验证
  python3 tools/simulate.py --runs 200
  python3 tools/simulate.py --trace     # 打印一条完整路径
"""
import argparse
import os
import random
import re
import sys
from collections import Counter

def _find_root():
    """兼容两种布局：仓库(tools/ 与 game/ 平级) 与 发布包(_tools/ 与 project.godot 平级)"""
    here = os.path.dirname(os.path.abspath(__file__))
    for base in (os.path.dirname(here), here):
        for cand in (os.path.join(base, "game"), base):
            if os.path.isfile(os.path.join(cand, "project.godot")):
                return cand
    return os.path.join(os.path.dirname(here), "game")

GAME = _find_root()
STORY_DIR = os.path.join(GAME, "story")
CFG = os.path.join(GAME, "autoload", "config.gd")

NUM_RANGE = {}
NUM_DEFAULT = {}
ENUM_DEFAULT = {}


def load_cfg():
    src = open(CFG, encoding="utf-8").read()
    rng_block = src.split("const NUM_RANGE := {")[1].split("}")[0]
    for k, lo, hi in re.findall(r'"([a-z_0-9]+)":\s*\[(-?\d+),\s*(\d+)\]', rng_block):
        NUM_RANGE[k] = (int(lo), int(hi))
    def_block = src.split("const NUM_DEFAULT := {")[1].split("}")[0]
    for k, v in re.findall(r'"([a-z_0-9]+)":\s*(-?\d+)', def_block):
        NUM_DEFAULT[k] = int(v)
    en_block = src.split("const ENUM_DEFAULT := {")[1].split("}")[0]
    for k, v in re.findall(r'"([a-z_0-9]+)":\s*"([a-z_]+)"', en_block):
        ENUM_DEFAULT[k] = v


# ------------------------------------------------------------------ 解析
class Parser:
    def __init__(self):
        self.nodes = {}

    def parse_dir(self, d):
        for fn in sorted(os.listdir(d)):
            if fn.endswith(".avg"):
                self.parse(open(os.path.join(d, fn), encoding="utf-8").read())

    def parse(self, txt):
        cur = None
        prog = []
        if_stack = []
        last_choices = None
        for raw in txt.split("\n"):
            s = raw.strip()
            if not s:
                last_choices = None
                continue
            if s.startswith("--"):
                continue
            if s.startswith("=="):
                if cur:
                    self.nodes[cur] = prog
                cur = s[2:].strip()
                prog, if_stack, last_choices = [], [], None
                continue
            if cur is None:
                continue
            if last_choices is not None and raw.startswith(" ") and s.startswith("@"):
                last_choices[-1]["effects"].append(self.cmd(s))
                continue
            if s.startswith("*"):
                ch = self.choice(s[1:].strip())
                if prog and prog[-1]["op"] == "choices":
                    prog[-1]["choices"].append(ch)
                    last_choices = prog[-1]["choices"]
                else:
                    prog.append({"op": "choices", "choices": [ch]})
                    last_choices = prog[-1]["choices"]
                continue
            last_choices = None
            if s.startswith("@"):
                head = s[1:].split()[0].lower()
                if head == "if":
                    prog.append({"op": "branch", "cond": s[3:].strip(), "jump": -1})
                    if_stack.append({"cond_idx": len(prog) - 1, "exits": []})
                elif head == "elif":
                    fr = if_stack[-1]
                    prog.append({"op": "jump", "jump": -1})
                    fr["exits"].append(len(prog) - 1)
                    prog[fr["cond_idx"]]["jump"] = len(prog)
                    prog.append({"op": "branch", "cond": s[5:].strip(), "jump": -1})
                    fr["cond_idx"] = len(prog) - 1
                elif head == "else":
                    fr = if_stack[-1]
                    prog.append({"op": "jump", "jump": -1})
                    fr["exits"].append(len(prog) - 1)
                    prog[fr["cond_idx"]]["jump"] = len(prog)
                    fr["cond_idx"] = -1
                elif head == "endif":
                    fr = if_stack.pop()
                    if fr["cond_idx"] >= 0:
                        prog[fr["cond_idx"]]["jump"] = len(prog)
                    for e in fr["exits"]:
                        prog[e]["jump"] = len(prog)
                else:
                    prog.append(self.cmd(s))
                continue
            prog.append({"op": "say"})
        if cur:
            self.nodes[cur] = prog

    @staticmethod
    def cmd(s):
        parts = s[1:].split()
        return {"op": "cmd", "cmd": parts[0].lower(), "args": parts[1:]}

    @staticmethod
    def choice(s):
        cond = lock = ""
        body = s
        while body.startswith("["):
            close = body.index("]")
            tag = body[1:close].strip()
            body = body[close + 1:].strip()
            if tag.startswith("if "):
                cond = tag[3:].strip()
            elif tag.startswith("lock "):
                lock = tag[5:].strip()
        target = ""
        if "->" in body:
            body, target = body.rsplit("->", 1)
            target = target.strip()
        return {"text": body.strip(), "target": target, "cond": cond, "lock": lock, "effects": []}


# ------------------------------------------------------------------ 状态
class State:
    def __init__(self):
        self.nums = dict(NUM_DEFAULT)
        self.flags = {}
        self.states = dict(ENUM_DEFAULT)
        self.items = set()
        self.clues = set()
        self.visited = set()
        self.deaths = []
        self.chapter = 1

    def add(self, k, d):
        lo, hi = NUM_RANGE.get(k, (-999, 999))
        self.nums[k] = max(lo, min(hi, self.nums.get(k, 0) + d))

    def set(self, k, v):
        lo, hi = NUM_RANGE.get(k, (-999, 999))
        self.nums[k] = max(lo, min(hi, v))

    def n(self, k):
        return self.nums.get(k, 0)

    # ---- 章节结算（对应 game_state.gd）
    def settle(self, ch):
        if ch == 1:
            if self.flags.get("flag_liangye_library") and self.flags.get("flag_library_page109"):
                self.states["liangye_state"] = "fear_alive"
            elif self.n("trust_liangye") < 0 and not self.flags.get("flag_liangye_library"):
                self.states["liangye_state"] = "missing_marked"
            elif self.n("trust_liangye") >= 4:
                self.states["liangye_state"] = "ally_shaken"
            else:
                self.states["liangye_state"] = "normal"
            self.states["zhouxu_state"] = "guarding" if self.n("trust_zhouxu") >= 2 else ("hiding" if self.n("trust_zhouxu") <= -5 else "normal")
            self.states["shenhe_state"] = "calling" if self.n("shenhe_focus") >= 9 else "echo"
            if self.n("trust_xuqing") <= -3:
                self.states["xuqing_state"] = "suspected"
            self.chapter = 2
        elif ch == 2:
            if self.flags.get("flag_liangye_marked") and self.n("trust_liangye") < 0:
                self.states["liangye_state"] = "missing_marked"
                self.items.add("item_library_card")
                self.add("truth", 2)
                self.deaths.append("梁野")
            elif self.flags.get("flag_liangye_half"):
                self.states["liangye_state"] = "half_assimilated"
            elif self.n("trust_liangye") >= 4:
                self.states["liangye_state"] = "ally_shaken"
            else:
                self.states["liangye_state"] = "fear_alive"
            self.states["zhouxu_state"] = "guarding" if self.n("trust_zhouxu") >= 2 else ("coercing" if self.n("trust_zhouxu") <= -5 else "hiding")
            if self.flags.get("flag_oldqin_survived"):
                self.states["oldqin_state"] = "alive"
            elif self.flags.get("flag_oldqin_burndeath"):
                self.states["oldqin_state"] = "burned"
            if self.n("shenhe_focus") >= 20 or self.flags.get("flag_first_face_to_face_shenhe"):
                self.states["shenhe_state"] = "half_present"
            elif self.n("shenhe_focus") >= 9:
                self.states["shenhe_state"] = "calling"
            if self.n("trust_xuqing") <= -3 or self.flags.get("flag_found_xuqing_log_fragment"):
                self.states["xuqing_state"] = "suspected"
            self.chapter = 3
        elif ch == 3:
            if self.flags.get("flag_gave_up_roommate"):
                self.states["liangye_final_state_ch3"] = "abandoned"
            elif self.flags.get("flag_liangye_half_assimilated"):
                self.states["liangye_final_state_ch3"] = "rescued_half" if self.n("trust_liangye") >= 3 else "missing"
            elif self.flags.get("flag_liangye_returned") and self.n("trust_liangye") >= 4:
                self.states["liangye_final_state_ch3"] = "anchor_alive"
            elif self.flags.get("flag_liangye_returned"):
                self.states["liangye_final_state_ch3"] = "fragile_alive"
            elif self.states.get("liangye_state") == "missing_marked":
                self.states["liangye_final_state_ch3"] = "missing"
            else:
                self.states["liangye_final_state_ch3"] = "fragile_alive"
            if self.n("trust_zhouxu") >= 4 and self.flags.get("flag_zhouxu_confessed_part"):
                self.states["zhouxu_final_state_ch3"] = "confessor_protector"
            elif self.n("trust_zhouxu") <= -5:
                self.states["zhouxu_final_state_ch3"] = "coercer"
            else:
                self.states["zhouxu_final_state_ch3"] = "split_guard"
            if self.flags.get("flag_name_written_back"):
                self.flags["true_end_precondition_1"] = True
            if self.flags.get("flag_night_roster_taken") or "item_night_roster" in self.items:
                self.flags["true_end_precondition_2"] = True
            self.chapter = 4
        elif ch == 4:
            # 真结局前置复核（与 game_state.settle_chapter_4 一致）：
            # 这两个 flag 依赖的道具在第四章才拿得到，只在第三章判一次会漏。
            if self.flags.get("flag_name_written_back"):
                self.flags["true_end_precondition_1"] = True
            if self.flags.get("flag_night_roster_taken") or "item_night_roster" in self.items:
                self.flags["true_end_precondition_2"] = True
            t = self.n("truth")
            core = self.flags.get("flag_saw_fire_video") and self.flags.get("flag_saw_self_repeat") and self.flags.get("flag_rule_terms_complete")
            th_complete = 740 if self.flags.get("flag_testimony_given") else 820
            if t >= th_complete and core and self.flags.get("flag_true_linday_status_known"):
                self.states["truth_state"] = "complete"
            elif t >= 640 and (self.flags.get("flag_saw_fire_video") or self.flags.get("flag_roster_core_taken")):
                self.states["truth_state"] = "high"
            else:
                self.states["truth_state"] = "partial"
            m = {
                "anchor_alive": "present_anchor",
                "rescued_half": "present_fragile_truth",
                "fragile_alive": "present_unstable",
            }
            base = m.get(self.states.get("liangye_final_state_ch3"), "absent_echo")
            self.states["liangye_end_state"] = "absent_echo" if self.flags.get("flag_liangye_final_loss") else base
            z = self.states.get("zhouxu_final_state_ch3")
            if z == "confessor_protector":
                self.states["zhouxu_end_state"] = "enter_with_player" if self.n("trust_zhouxu") >= 4 else "follow_to_threshold"
            elif z == "coercer":
                self.states["zhouxu_end_state"] = "pressure_player"
            else:
                self.states["zhouxu_end_state"] = "follow_to_threshold"
            ready = (("item_roster_core" in self.items or "item_night_roster" in self.items)
                     and ("item_admin_key" in self.items or self.flags.get("flag_fakewall_opened"))
                     and self.n("truth") >= 640)
            if ready:
                self.flags["flag_terminal_broadcast_ready"] = True
            self.chapter = 5

    def determine_ending(self):
        # 与 game_state.gd 保持一致：篡改档回落空席（模拟中恒为 False）
        if getattr(self, "save_tampered", False):
            return "ending_empty_seat"
        # 全员报数路线：三条支线全通才解锁，本身即构成真结局资格
        if self.flags.get("flag_count_overflow"):
            self.states["truth_state"] = "complete"
            self.flags["flag_terminal_broadcast_ready"] = True
            self.flags["true_end_precondition_1"] = True
            self.flags["true_end_precondition_2"] = True
            self.flags["flag_rule_terms_complete"] = True
        if (self.states.get("truth_state") == "complete"
                and self.flags.get("true_end_precondition_1")
                and self.flags.get("true_end_precondition_2")
                and self.n("save_route_score") >= 46
                and self.flags.get("flag_rule_terms_complete")
                and self.flags.get("flag_terminal_broadcast_ready")
                and not self.flags.get("flag_gave_up_roommate")
                and self.states.get("liangye_end_state") in ("present_anchor", "present_fragile_truth")):
            return "ending_true_release"
        if (self.n("save_route_score") >= 31 and self.flags.get("flag_terminal_broadcast_ready")
                and (self.states.get("liangye_end_state") == "absent_echo"
                     or not self.flags.get("flag_rule_terms_complete")
                     or self.flags.get("flag_player_self_substitute"))):
            return "ending_bittersweet_exchange"
        if (self.n("end_cycle_score") >= 7 and self.flags.get("flag_terminal_broadcast_ready")
                and self.flags.get("flag_chose_end_cycle")):
            return "ending_destroyer"
        if self.n("control_route_score") >= 7 or (self.flags.get("flag_gave_up_roommate") and self.n("control_route_score") >= 5):
            return "ending_manager"
        return "ending_empty_seat"


# ------------------------------------------------------------------ 条件
def ev(st, expr):
    e = expr.strip()
    if not e:
        return True
    if " or " in e:
        return any(ev(st, p) for p in e.split(" or "))
    if " and " in e:
        return all(ev(st, p) for p in e.split(" and "))
    return atom(st, e)


def atom(st, a):
    s = a.strip()
    if s.startswith("!"):
        return not atom(st, s[1:])
    if s.startswith("item:"):
        return s[5:] in st.items
    if s.startswith("clue:"):
        return s[5:] in st.clues
    if s.startswith("visited:"):
        return s[8:] in st.visited
    if s.startswith("death:"):
        return any(d.startswith(s[6:]) for d in st.deaths)
    if s.startswith("state:"):
        body = s[6:]
        if "==" in body:
            k, v = body.split("==", 1)
            cur = st.states.get(k.strip(), "")
            return cur in v.strip().split("|") if "|" in v else cur == v.strip()
        if "!=" in body:
            k, v = body.split("!=", 1)
            return st.states.get(k.strip(), "") != v.strip()
        return False
    if s.startswith("cycles"):
        return cmpnum(0, s[6:])
    if s.startswith("chapter"):
        return cmpnum(st.chapter, s[7:])
    if s.startswith("gore"):
        return cmpnum(2, s[4:])
    for op in ("<=", ">=", "==", "!=", "<", ">"):
        i = s.find(op)
        if i > 0:
            k = s[:i].strip()
            if k in NUM_RANGE:
                return cmpnum(st.n(k), s[i:])
            return False
    if s in NUM_RANGE:
        return st.n(s) > 0
    return bool(st.flags.get(s, False))


def cmpnum(v, tail):
    t = tail.strip()
    for op in (">=", "<=", "==", "!="):
        if t.startswith(op):
            x = int(t[2:])
            return {">=": v >= x, "<=": v <= x, "==": v == x, "!=": v != x}[op]
    if t.startswith(">"):
        return v > int(t[1:])
    if t.startswith("<"):
        return v < int(t[1:])
    return v != 0


# ------------------------------------------------------------------ 运行
class Runner:
    def __init__(self, nodes, chooser, trace=False):
        self.nodes = nodes
        self.st = State()
        self.chooser = chooser
        self.trace = trace
        self.path = []
        self.steps = 0

    def run(self, start="prologue", max_steps=40000):
        nid = start
        while True:
            if nid not in self.nodes:
                raise RuntimeError("节点不存在: " + nid)
            self.st.visited.add(nid)
            self.path.append(nid)
            prog = self.nodes[nid]
            ip = 0
            jumped = None
            while ip < len(prog):
                self.steps += 1
                if self.steps > max_steps:
                    raise RuntimeError("步数超限，可能存在死循环。最近路径: " + " -> ".join(self.path[-12:]))
                ins = prog[ip]
                ip += 1
                op = ins["op"]
                if op == "say":
                    continue
                if op == "branch":
                    if not ev(self.st, ins["cond"]):
                        ip = ins["jump"]
                    continue
                if op == "jump":
                    ip = ins["jump"]
                    continue
                if op == "choices":
                    vis = [c for c in ins["choices"] if not c["cond"] or ev(self.st, c["cond"])]
                    usable = [c for c in vis if not c["lock"] or ev(self.st, c["lock"])]
                    if not usable:
                        if not vis:
                            continue
                        raise RuntimeError(f"节点 {nid} 的所有选项都被锁死")
                    ch = self.chooser(nid, usable, self.st)
                    for e in ch["effects"]:
                        self.exec(e)
                    if ch["target"]:
                        jumped = ch["target"]
                        break
                    continue
                r = self.exec(ins)
                if r:
                    if r == "__END__":
                        return self.ending
                    jumped = r
                    break
            if jumped:
                nid = jumped
                continue
            raise RuntimeError(f"节点 {nid} 执行完毕却没有跳转（死路）")

    def exec(self, ins):
        c = ins["cmd"]
        a = ins["args"]
        st = self.st
        if c == "set":
            k, v = a[0], a[1]
            if v.startswith("="):
                st.set(k, int(v[1:]))
            else:
                st.add(k, int(v))
        elif c == "flag":
            st.flags[a[0]] = (len(a) < 2 or a[1].lower() != "false")
        elif c == "state":
            st.states[a[0]] = a[1]
        elif c == "item":
            if a[0].startswith("-"):
                st.items.discard(a[0][1:])
            else:
                st.items.add(a[0].lstrip("+"))
        elif c == "clue":
            st.clues.add(a[0])
        elif c == "death":
            st.deaths.append(a[0])
        elif c == "settle":
            st.settle(int(a[0]))
        elif c == "chapter":
            st.chapter = int(a[0])
        elif c in ("time", "timeat", "advtime"):
            pass
        elif c == "goto":
            t = a[0]
            return st.determine_ending() if t == "__ending__" else t
        elif c == "ending":
            self.ending = st.determine_ending() if a[0] == "auto" else a[0]
            return "__END__"
        elif c == "return":
            self.ending = "__return__"
            return "__END__"
        return None


def random_chooser(rng):
    def f(_nid, choices, _st):
        return rng.choice(choices)
    return f


def greedy_true_end(rng):
    """尽量走真结局的策略：偏好救人 / 调查 / 真相相关选项"""
    good_kw = ["沈禾", "名字", "真相", "救", "抓住", "帮", "看", "翻", "递", "名单", "写回",
               "先点", "不完整", "错了", "跟", "拿", "别替", "确认", "问", "残页", "录像", "日志",
               "钥匙", "借书卡", "不会丢下", "一起", "抓", "拦"]
    bad_kw = ["放手", "让他去", "到。", "替他答", "不去", "沉默不管", "打断", "硬闯", "三样都拿"]

    def f(_nid, choices, _st):
        best, score = None, -999
        for c in choices:
            s = 0
            t = c["text"]
            for k in good_kw:
                if k in t:
                    s += 3
            for k in bad_kw:
                if k in t:
                    s -= 8
            for e in c["effects"]:
                if e["cmd"] == "set":
                    key, val = e["args"][0], e["args"][1]
                    d = int(val.lstrip("=")) * (1 if not val.startswith("-") else 1)
                    if key in ("truth", "save_route_score", "trust_liangye", "trust_zhouxu", "route_investigate", "route_empathy"):
                        s += abs(d) * (2 if not val.startswith("-") else -2)
                    if key in ("taboo_count", "route_hostility", "control_route_score", "end_cycle_score"):
                        s -= abs(d) * 2
                    if key == "sanity" and val.startswith("-"):
                        s -= 1
                elif e["cmd"] == "flag":
                    if e["args"][0] in ("flag_gave_up_roommate", "flag_liangye_final_loss"):
                        s -= 40
                    else:
                        s += 2
                elif e["cmd"] == "item":
                    s += 3
            s += rng.random()
            if s > score:
                best, score = c, s
        return best
    return f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=800)
    ap.add_argument("--trace", action="store_true")
    ap.add_argument("--seed", type=int, default=20260817)
    args = ap.parse_args()

    load_cfg()
    p = Parser()
    p.parse_dir(STORY_DIR)
    print(f"载入节点 {len(p.nodes)} 个")

    rng = random.Random(args.seed)
    counts = Counter()
    failures = []
    max_len = 0
    range_violations = []

    for i in range(args.runs):
        r = Runner(p.nodes, random_chooser(rng))
        try:
            e = r.run()
            counts[e] += 1
            max_len = max(max_len, len(r.path))
            for k, v in r.st.nums.items():
                lo, hi = NUM_RANGE[k]
                if not (lo <= v <= hi):
                    range_violations.append((k, v))
        except Exception as ex:
            failures.append(f"run#{i}: {ex}")

    # 定向验证：真结局
    true_hit = 0
    for i in range(60):
        r = Runner(p.nodes, greedy_true_end(random.Random(args.seed + i)))
        try:
            if r.run() == "ending_true_release":
                true_hit += 1
        except Exception as ex:
            failures.append(f"greedy#{i}: {ex}")

    print("=" * 62)
    print("剧情运行时模拟")
    print("=" * 62)
    print(f"随机通关 : {args.runs} 次，失败 {len(failures)} 次")
    print(f"最长路径 : {max_len} 个节点")
    print("结局分布 :")
    names = {
        "ending_true_release": "真结局《点名停止》",
        "ending_bittersweet_exchange": "遗憾结局《留堂》",
        "ending_manager": "管理者结局《管理员》",
        "ending_destroyer": "毁灭结局《焚校》",
        "ending_empty_seat": "空席结局《到》",
    }
    for k, v in counts.most_common():
        print(f"   {names.get(k, k):28s} {v:5d}  ({v * 100.0 / max(1, args.runs):.1f}%)")
    print(f"定向真结局策略 : 60 次中命中 {true_hit} 次")
    missing = [k for k in names if counts[k] == 0 and not (k == 'ending_true_release' and true_hit)]
    if missing:
        print("  [warn ] 随机策略未覆盖的结局: " + ", ".join(names[m] for m in missing))
    for f in failures[:20]:
        print("  [ERROR]", f)
    if range_violations:
        print("  [ERROR] 数值越界:", set(range_violations))
    print("-" * 62)
    ok = not failures and not range_violations and true_hit > 0
    print("结果:", "通过" if ok else "存在问题")

    if args.trace:
        r = Runner(p.nodes, greedy_true_end(random.Random(1)))
        e = r.run()
        print("\n示例路径 (%s):" % names.get(e, e))
        print(" -> ".join(r.path))
        print("终局变量:", {k: v for k, v in r.st.nums.items() if v})
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
