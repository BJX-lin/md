extends Node
## 全局常量与配置（《晚自习之后》）
## 引擎：Godot Engine 4.7.1 stable / Mobile 渲染后端

const GAME_TITLE := "晚自习之后"
const GAME_SUBTITLE := "AFTER EVENING STUDY"
const VERSION := "1.0.0"

# ---------------------------------------------------------------- 数值上下限
# 对应 f.md 《全局变量总表 · 1.1 数值变量表》
const NUM_RANGE := {
	"truth": [0, 30],
	"sanity": [0, 100],
	"memory_echo": [0, 15],
	"shenhe_focus": [0, 15],
	"trust_zhouxu": [-5, 5],
	"trust_liangye": [-5, 5],
	"trust_xuqing": [-5, 3],
	"trust_oldqin": [-5, 5],
	"route_obedience": [0, 10],
	"route_investigate": [0, 10],
	"route_empathy": [0, 10],
	"route_hostility": [0, 10],
	"taboo_count": [0, 20],
	"save_route_score": [0, 20],
	"end_cycle_score": [0, 20],
	"control_route_score": [0, 20],
}

const NUM_DEFAULT := {
	"truth": 0,
	"sanity": 70,
	"memory_echo": 0,
	"shenhe_focus": 0,
	"trust_zhouxu": 0,
	"trust_liangye": 0,
	"trust_xuqing": 0,
	"trust_oldqin": 0,
	"route_obedience": 0,
	"route_investigate": 0,
	"route_empathy": 0,
	"route_hostility": 0,
	"taboo_count": 0,
	"save_route_score": 0,
	"end_cycle_score": 0,
	"control_route_score": 0,
}

# 数值中文名（用于状态面板）
const NUM_LABEL := {
	"truth": "真相",
	"sanity": "理智",
	"memory_echo": "回响",
	"shenhe_focus": "关注",
	"trust_zhouxu": "周叙信任",
	"trust_liangye": "梁野信任",
	"trust_xuqing": "许清态度",
	"trust_oldqin": "老秦信任",
	"route_obedience": "守规",
	"route_investigate": "调查",
	"route_empathy": "共情",
	"route_hostility": "对抗",
	"taboo_count": "违规",
	"save_route_score": "救人线",
	"end_cycle_score": "终止线",
	"control_route_score": "接管线",
}

# 玩家可见的核心四项
const NUM_VISIBLE := ["truth", "sanity", "memory_echo", "shenhe_focus"]

# ---------------------------------------------------------------- 枚举状态
const ENUM_DEFAULT := {
	"liangye_state": "normal",
	"oldqin_state": "alive",
	"zhouxu_state": "normal",
	"xuqing_state": "hidden",
	"shenhe_state": "echo",
	"liangye_final_state_ch3": "fragile_alive",
	"zhouxu_final_state_ch3": "split_guard",
	"truth_state": "partial",
	"liangye_end_state": "present_unstable",
	"zhouxu_end_state": "follow_to_threshold",
}

# ---------------------------------------------------------------- 角色定义
# 名称 / 主色 / 声线基频（程序化音效用）/ 立绘轮廓参数
const CHARACTERS := {
	"linzhou": {"name": "林昼", "color": Color(0.86, 0.87, 0.90), "pitch": 150.0, "build": 0.5},
	"zhouxu": {"name": "周叙", "color": Color(0.62, 0.74, 0.86), "pitch": 128.0, "build": 0.52},
	"liangye": {"name": "梁野", "color": Color(0.88, 0.76, 0.55), "pitch": 168.0, "build": 0.44},
	"xuqing": {"name": "许清", "color": Color(0.78, 0.62, 0.66), "pitch": 205.0, "build": 0.46},
	"shenhe": {"name": "沈禾", "color": Color(0.72, 0.86, 0.83), "pitch": 232.0, "build": 0.42},
	"oldqin": {"name": "老秦", "color": Color(0.70, 0.66, 0.55), "pitch": 104.0, "build": 0.60},
	"voice": {"name": "女声", "color": Color(0.66, 0.84, 0.82), "pitch": 226.0, "build": 0.42},
	"radio": {"name": "广播", "color": Color(0.80, 0.55, 0.48), "pitch": 190.0, "build": 0.0},
	"classmate": {"name": "同学", "color": Color(0.70, 0.70, 0.72), "pitch": 172.0, "build": 0.48},
	"crowd": {"name": "众人", "color": Color(0.66, 0.66, 0.68), "pitch": 160.0, "build": 0.48},
	"unknown": {"name": "？？？", "color": Color(0.60, 0.60, 0.66), "pitch": 140.0, "build": 0.46},
	"me": {"name": "我", "color": Color(0.92, 0.92, 0.94), "pitch": 146.0, "build": 0.5},
}

# ---------------------------------------------------------------- 阈值表（f.md 六）
const TH_TRUTH := [
	[5, "能确认异常不是错觉"],
	[10, "能读懂基础规则文本"],
	[15, "能理解待定 / 删除的危险差别"],
	[18, "第三章末可稳定推进校史馆线"],
	[20, "可主动质问补位 / 循环"],
	[25, "真相层级可判为 complete 候选"],
]

const TH_SANITY := [
	[80, "叙述稳定，可信"],
	[60, "偶发错听、余光异常"],
	[40, "文本开始出现被篡改的行"],
	[25, "会看到不存在的人、听见自己的声音"],
	[10, "选项文本可能撒谎"],
]

# ---------------------------------------------------------------- 表现设置
enum GoreLevel { OFF, MILD, FULL }

const TEXT_SPEED_PRESET := [0.075, 0.045, 0.024, 0.008]

const PALETTE := {
	"ink": Color(0.043, 0.047, 0.055),
	"paper": Color(0.86, 0.85, 0.80),
	"blood": Color(0.42, 0.06, 0.07),
	"blood_bright": Color(0.62, 0.09, 0.09),
	"rust": Color(0.36, 0.20, 0.14),
	"cold": Color(0.36, 0.48, 0.55),
	"warn": Color(0.85, 0.62, 0.28),
	"ghost": Color(0.60, 0.79, 0.76),
	"ui_line": Color(0.55, 0.53, 0.48, 0.5),
}

static func clampi_var(key: String, v: int) -> int:
	if NUM_RANGE.has(key):
		var r: Array = NUM_RANGE[key]
		return clampi(v, int(r[0]), int(r[1]))
	return v
