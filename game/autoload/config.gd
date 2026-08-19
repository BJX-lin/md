extends Node
## 全局常量与配置（《第十三节课》）
## 引擎：Godot Engine 4.7.1 stable / Mobile 渲染后端

const GAME_TITLE := "第十三节课"
const GAME_SUBTITLE := "THE 13TH PERIOD"
const VERSION := "1.1.1"

# ---------------------------------------------------------------- 反馈渠道
## BUG 反馈 / 玩家交流 QQ 群（防篡改存储）。
##
## 威胁模型：导出后的 pck 可以被解包，明文字符串一搜就能找到并替换成
## 骗子的群号，再重新打包分发——玩家扫码进的就是假群。
## 这类"改联系方式"的篡改在同人游戏里很常见，且受害的是玩家。
##
## 做法（三层）：
##   1. 混淆存储：群号与链接不以明文出现，异或后 Base64
##   2. 完整性签名：取用时校验 SHA256 摘要，改了就对不上
##   3. 二维码指纹：图片本身也登记 SHA256，防止只换图片不改代码
##
## 注意：这不是加密，本地数据对本地攻击者不存在真正的机密性。
## 目的是把"记事本搜字符串就能改"提升到"必须读懂并同步改三处"，
## 并且一旦改错，游戏会明确告诉玩家"联系方式可能被篡改，别加"。
##
## 换群时用 tools/gen_contact.py 重新生成下面四个常量与二维码。
const QQ_ENC := "dlJHU0p8QV1e"
const QQ_SIG := "0ccc1702b3e3c42720142a01ffbe4b86"
const QQ_URL_ENC := "KRIAFQF/WUofBEAWIloWCxQVS0xYWkdXW00NAkY="
const QQ_URL_SIG := "7e9a2ce2a5c70e4f50bfec674175f204"
## 二维码图片的 SHA256，防止只替换 assets/ui/qq_qr.png
const QQ_QR_SHA := "0f32c760c3d47ed3ad2ead7d02d5cdcdbafbb3f516f27ace45126c05b77dfa39"

const _CONTACT_KEY := "AfterEveningStudy::contact::v1"

## 字节数组的 SHA256 十六进制摘要。
## 注意：Godot 4.7.1 中 sha256_text() 只存在于 String，
## PackedByteArray 需经 HashingContext（与 tools/gen_contact.py 同算法）。
static func _sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()

## 解出联系方式并校验完整性。校验失败返回空字符串，
## 由调用方负责提示玩家"联系方式可能被篡改"。
static func _decode_contact(enc: String, expect_sig: String) -> String:
	var raw := Marshalls.base64_to_raw(enc)
	if raw.is_empty():
		return ""
	var key := _CONTACT_KEY.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(raw.size())
	for i in raw.size():
		out[i] = raw[i] ^ key[i % key.size()]
	var text := out.get_string_from_utf8()
	if text == "":
		return ""
	var check := key.duplicate()
	check.append_array(text.to_utf8_buffer())
	check.append_array(key)
	if _sha256_hex(check).substr(0, 32) != expect_sig:
		return ""
	return text

## 群号。被篡改时返回空串。
static func qq_group() -> String:
	return _decode_contact(QQ_ENC, QQ_SIG)

## 加群链接（二维码内容）。被篡改时返回空串。
static func qq_group_url() -> String:
	return _decode_contact(QQ_URL_ENC, QQ_URL_SIG)

## 二维码图片是否未被替换。
static func qq_qr_valid() -> bool:
	var f := FileAccess.open("res://assets/ui/qq_qr.png", FileAccess.READ)
	if f == null:
		return false
	var data := f.get_buffer(f.get_length())
	f.close()
	return _sha256_hex(data) == QQ_QR_SHA

# ---------------------------------------------------------------- 数值上下限
# 对应 f.md 《全局变量总表 · 1.1 数值变量表》
# 范围按剧本实际数值校准（tools 统计：各变量单线正增量总和），
# 留出分支余量，避免 clampi_var 截断导致高数值区间失去区分度。
const NUM_RANGE := {
	"truth": [0, 4000],
	"evidence_count": [0, 8],
	"sanity": [0, 100],
	"memory_echo": [0, 1200],
	"shenhe_focus": [0, 350],
	"trust_zhouxu": [-60, 120],
	"trust_liangye": [-60, 110],
	"trust_xuqing": [-10, 12],
	"trust_oldqin": [-12, 26],
	"route_obedience": [0, 100],
	"route_investigate": [0, 130],
	"route_empathy": [0, 110],
	"route_hostility": [0, 40],
	"taboo_count": [0, 40],
	"save_route_score": [0, 400],
	"end_cycle_score": [0, 28],
	"control_route_score": [0, 28],
}

const NUM_DEFAULT := {
	"evidence_count": 0,
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

# ---------------------------------------------------------------- 状态条满刻度
## 与 NUM_RANGE（全收集上限，防截断）不同：这是单周目实际可达的满刻度，
## 状态面板的进度条用它归一化，保证条形图始终有意义（不会因上限过大而空）。
const BAR_MAX := {
	"truth": 1500,
	"memory_echo": 600,
	"shenhe_focus": 300,
	"trust_zhouxu": 60,
	"trust_liangye": 60,
	"trust_xuqing": 12,
	"trust_oldqin": 26,
	"route_obedience": 100,
	"route_investigate": 130,
	"route_empathy": 110,
	"route_hostility": 40,
	"taboo_count": 40,
	"save_route_score": 200,
	"end_cycle_score": 28,
	"control_route_score": 28,
}

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
	"dorm_keeper": {"name": "宿管阿姨", "color": Color(0.70, 0.66, 0.68), "pitch": 116.0, "build": 0.52},
	"classmate_girl": {"name": "前排女生", "color": Color(0.72, 0.68, 0.74), "pitch": 128.0, "build": 0.42},
	"classmate_boy": {"name": "擦黑板的男生", "color": Color(0.62, 0.68, 0.72), "pitch": 112.0, "build": 0.50},
	"canteen_aunt": {"name": "食堂阿姨", "color": Color(0.74, 0.70, 0.62), "pitch": 118.0, "build": 0.55},
	"oldqin": {"name": "老秦", "color": Color(0.70, 0.66, 0.55), "pitch": 104.0, "build": 0.60},
	"voice": {"name": "女声", "color": Color(0.66, 0.84, 0.82), "pitch": 226.0, "build": 0.42},
	"radio": {"name": "广播", "color": Color(0.80, 0.55, 0.48), "pitch": 190.0, "build": 0.0},
	"liheng": {"name": "李恒", "color": Color(0.58, 0.62, 0.70), "pitch": 108.0, "build": 0.47},
	"classmate": {"name": "同学", "color": Color(0.70, 0.70, 0.72), "pitch": 172.0, "build": 0.48},
	"crowd": {"name": "众人", "color": Color(0.66, 0.66, 0.68), "pitch": 160.0, "build": 0.48},
	"unknown": {"name": "？？？", "color": Color(0.60, 0.60, 0.66), "pitch": 140.0, "build": 0.46},
	"me": {"name": "我", "color": Color(0.92, 0.92, 0.94), "pitch": 146.0, "build": 0.5},
}

# ---------------------------------------------------------------- 阈值表（f.md 六）
# truth 标度 0~4000：按 f.md 0~30 节奏重分布（低档密集、高档拉开），
# 与 settle_chapter_4 的 complete(820)/high(640) 判定保持自洽。
const TH_TRUTH := [
	[230, "能确认异常不是错觉"],
	[460, "能读懂基础规则文本"],
	[690, "能理解待定 / 删除的危险差别"],
	[830, "第三章末可稳定推进校史馆线"],
	[920, "可主动质问补位 / 循环"],
	[1150, "真相层级可判为 complete 候选"],
	[1280, "可见高阶真相、自我重复更明确"],
]

## 理智档位边界与 f.md 6.2 对齐（0~19 崩溃边缘）
const TH_SANITY := [
	[80, "叙述稳定，可信"],
	[60, "偶发错听、余光异常"],
	[40, "文本开始出现被篡改的行"],
	[20, "会看到不存在的人、听见自己的声音"],
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

# ---------------------------------------------------------------- 性能
## 目标帧率。
##
## 手机上不追求越高越好：
##   * 本作是阅读型 AVG，60 帧已经完全够用
##   * 高刷屏若放开跑到 90/120，只会徒增发热与耗电，
##     且发热降频之后反而更容易掉到 40 以下
## 因此锁 60 + 开垂直同步，把帧生成时间稳定在 16.7ms，
## 实测目标区间 40~60。
const TARGET_FPS := 60

func _ready() -> void:
	Engine.max_fps = TARGET_FPS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
