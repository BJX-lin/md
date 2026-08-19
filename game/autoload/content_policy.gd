extends Node
## 创意工坊内容规则（本体内置 · 防篡改）
##
## ============================ 为什么规则要写死在本体里 ============================
##
## 创意工坊允许玩家自造剧情并导出/导入配置，这天然带来一个风险：
## 有人会用它承载色情、露骨性描写、真实未成年人性化、极端仇恨等内容，
## 然后把"配置文件"当作规避手段四处传播——出事的是本作的名声与玩家。
##
## 因此本模块的规则**不是外部配置**，而是编译进游戏本体的常量：
##   * 玩家改不了：规则不在 user:// 里，改存档、改配置都碰不到
##   * 改了就会被发现：POLICY_SIGNATURE 是全部规则文本的摘要，
##     启动时自校验，对不上就判定为"本体被修改过"
##   * 只有拿到工程源码的人才能改（即作者自己），这正是我们想要的边界
##
## 被篡改时的行为：**彻底停用创意工坊**，并提示玩家去下载未经修改的版本。
## 宁可少一个功能，也不让改过的版本打着本作的名义分发违规内容。
##
## ============================ 这不是万能的 ============================
##
## 必须说清楚：本地校验挡不住"重新编译一个改过的游戏"。
## 它能挡住的是**成本低、传播快**的那一类：解包改文本、发个"补丁包"、
## 发个"解锁配置"。把门槛从"记事本"提到"重编引擎"，
## 绝大多数违规传播就不会发生了。

signal policy_violation(reasons: Array)

# ---------------------------------------------------------------- 规则版本
const POLICY_VERSION := "1.0"

## 规则摘要盐值。与规则文本一起参与签名。
const POLICY_SALT := "AfterEveningStudy::policy::v1"

# ---------------------------------------------------------------- 禁止内容
## 一级：色情与露骨性描写。命中即整份内容拒绝导入。
##
## 说明：本作正文本身允许"微涩"（暧昧、暗示、擦边的紧张感），
## 那部分是作者写死在本体剧本里的、有分寸的表达。
## 玩家自造内容不开放这一层——因为无法逐条审核，只能一刀切。
const BLOCK_SEXUAL := [
	"性交", "做爱", "口交", "肛交", "自慰", "手淫", "射精", "高潮",
	"淫水", "淫叫", "浪叫", "抽插", "插入下体", "阴茎", "阴道", "阴部",
	"乳头", "乳交", "裸体", "全裸", "赤裸全身", "脱光", "扒光",
	"强奸", "轮奸", "迷奸", "性侵", "猥亵", "下体", "私处",
	"色情", "情色", "黄色小说", "成人内容", "18禁", "R18", "NSFW",
	"约炮", "卖淫", "嫖娼", "援交", "包养",
]

## 二级：未成年人性化。本作角色全部是高中生，这条必须最严。
const BLOCK_MINOR := [
	"萝莉", "正太", "幼女", "幼男", "童颜巨乳", "未成年裸", "小学生裸",
	"儿童色情", "恋童",
]

## 三级：极端暴力的"教程化"表达。
## 注意本作本身是恐怖题材，允许血腥描写；
## 这里挡的是"可操作的伤害指南"，不是恐怖氛围。
const BLOCK_HARM := [
	"制作炸弹", "制造炸弹", "炸弹配方", "制毒", "制作毒品",
	"自杀方法", "自杀教程", "如何自杀", "上吊教程", "割腕教程",
	"约死", "相约自杀",
]

## 四级：仇恨与人身攻击。
const BLOCK_HATE := [
	"种族清洗", "杀光所有", "灭绝人种",
]

## 五级：真实世界个人信息与引流。
## 创意工坊内容会被传播，不能变成挂人或拉私群的载体。
const BLOCK_DOXX := [
	"身份证号", "家庭住址是", "手机号是", "银行卡号",
	"加我微信", "加我qq", "加我QQ", "私聊我", "扫码进群", "破解版下载",
]

## 允许的最大体量。防止有人塞一整本书进来拖垮解析。
const MAX_NODES := 400
const MAX_TOTAL_CHARS := 200000
const MAX_LINE_CHARS := 2000

## 允许玩家内容使用的指令白名单。
## 刻意不含 @death / @settle / @ending 这类会污染主线状态的指令——
## 玩家内容跑在沙箱里，不应该能改主线结局与角色生死。
const ALLOWED_CMDS := [
	"bg", "bgm", "amb", "sfx", "fx", "show", "hide", "clearchars",
	"wait", "title", "note", "time", "timeat", "advtime",
	"if", "elif", "else", "endif", "goto", "return",
	"set", "flag", "state", "item", "clue",
]

# ---------------------------------------------------------------- 自校验
## 规则签名。由 tools/gen_policy_sig.py 生成。
## 任何人改了上面的规则数组而没有同步这个签名，游戏就会判定本体被篡改。
const POLICY_SIGNATURE := "9a421369747d389faa225bc54f844df07145e215c7c6f709d102ee519242012a"

var _tampered := false
var _tamper_reason := ""

func _ready() -> void:
	_self_check()

## 把全部规则拼成一段规范文本，用于签名。
## 顺序固定，因此同样的规则永远得到同样的摘要。
func _policy_text() -> String:
	var parts := PackedStringArray()
	parts.append(POLICY_VERSION)
	for arr in [BLOCK_SEXUAL, BLOCK_MINOR, BLOCK_HARM, BLOCK_HATE, BLOCK_DOXX]:
		for w in arr:
			parts.append(String(w))
	for c in ALLOWED_CMDS:
		parts.append(String(c))
	parts.append(str(MAX_NODES))
	parts.append(str(MAX_TOTAL_CHARS))
	parts.append(str(MAX_LINE_CHARS))
	return POLICY_SALT + "|" + "\n".join(parts)

func _self_check() -> void:
	# 第一层：规则文本自身的签名
	var actual := _policy_text().sha256_text()
	if actual != POLICY_SIGNATURE:
		_tampered = true
		_tamper_reason = "内容规则签名不符"
		push_warning("[创意工坊] 内容规则已被修改，工坊功能停用。期望 %s 实际 %s"
			% [POLICY_SIGNATURE.substr(0, 12), actual.substr(0, 12)])
		return
	# 第二层：文件级完整性。
	# 单靠规则文本签名挡不住"连签名一起改"，
	# 文件摘要清单是独立的一道，两处都得改对才能绕过。
	if Engine.has_singleton("Integrity") or Integrity != null:
		if not Integrity.workshop_files_intact():
			_tampered = true
			_tamper_reason = "核心文件校验未通过（%s）" % ", ".join(Integrity.failed_files())

## 本体是否被改过。为 true 时创意工坊整体停用。
func is_tampered() -> bool:
	return _tampered

func tamper_reason() -> String:
	return _tamper_reason

## 给玩家看的提示。措辞要让人明白该去做什么，而不是只说"出错了"。
func tamper_notice() -> String:
	return ("检测到游戏本体的内容规则已被修改。\n\n" +
		"为避免被用于传播违规内容，创意工坊已停用。\n" +
		"请从官方发布页下载未经修改的游戏版本。\n\n" +
		"（原因：%s）" % _tamper_reason)

# ---------------------------------------------------------------- 内容审查
## 审查一份玩家内容。
## 返回 { ok: bool, reasons: Array[String], hits: Array[String] }
##
## 设计取舍：命中即拒绝整份，不做"自动打码"。
## 自动替换会让作者以为内容通过了，实际发布出去仍是违规的；
## 明确拒绝并告诉他哪一条不合规，才是对双方都负责的做法。
func review(text: String, node_count: int = 0) -> Dictionary:
	var reasons := PackedStringArray()
	var hits := PackedStringArray()

	if _tampered:
		reasons.append("游戏本体内容规则已被修改，工坊停用")
		return {"ok": false, "reasons": reasons, "hits": hits}

	# —— 体量
	if text.length() > MAX_TOTAL_CHARS:
		reasons.append("内容过长（%d 字，上限 %d）" % [text.length(), MAX_TOTAL_CHARS])
	if node_count > MAX_NODES:
		reasons.append("节点过多（%d 个，上限 %d）" % [node_count, MAX_NODES])

	# —— 关键词。统一转小写再比，避免大小写绕过。
	var low := text.to_lower()
	var groups := {
		"色情或露骨性描写": BLOCK_SEXUAL,
		"未成年人性化": BLOCK_MINOR,
		"可操作的伤害指南": BLOCK_HARM,
		"仇恨言论": BLOCK_HATE,
		"个人信息或站外引流": BLOCK_DOXX,
	}
	for label in groups:
		var found := PackedStringArray()
		for w in groups[label]:
			if low.contains(String(w).to_lower()):
				found.append(String(w))
		if not found.is_empty():
			reasons.append("含%s" % label)
			for f in found:
				hits.append(f)

	# —— 超长行（常见于塞入大段无关文本）
	for line in text.split("\n"):
		if line.length() > MAX_LINE_CHARS:
			reasons.append("存在超长行（%d 字）" % line.length())
			break

	var ok := reasons.is_empty()
	if not ok:
		policy_violation.emit(Array(reasons))
	return {"ok": ok, "reasons": Array(reasons), "hits": Array(hits)}

## 校验单条指令是否允许玩家内容使用。
func cmd_allowed(cmd: String) -> bool:
	return ALLOWED_CMDS.has(cmd)

## 规则摘要，展示在工坊页面让作者心里有数。
func rules_summary() -> Array:
	return [
		"禁止色情、露骨性描写与任何形式的未成年人性化",
		"禁止可操作的伤害/自杀/制毒指南",
		"禁止仇恨言论与人身攻击",
		"禁止真实个人信息、站外引流与破解链接",
		"单份内容上限 %d 个节点 / %d 字" % [MAX_NODES, MAX_TOTAL_CHARS],
		"恐怖、悬疑、血腥氛围是允许的——本作本身就是恐怖题材",
	]
