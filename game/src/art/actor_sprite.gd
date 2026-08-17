extends Control
class_name ActorSprite
## 立绘显示节点
##
## 资源命名规范（对应《角色立绘表情表》）：
##   res://assets/sprites/<char_id>/<char_id>_pose<NN>_<exp>.png
##   例：assets/sprites/zhouxu/zhouxu_pose01_neutral.png
##
## 查找顺序：
##   1. 剧情指定的姿态 + 精确表情
##   2. 剧情指定的姿态 + 表情回退链
##   3. 其它姿态 + 表情回退链
##   4. 该角色任意一张图
##   5. 全都没有 → 回退 actor_painter 代码绘制（不会开天窗）

const SPRITE_ROOT := "res://assets/sprites"
const ActorPainterS := preload("res://src/art/actor_painter.gd")

var who := "linzhou"
var emo := "normal"
var active := true
var glitch := 0.0
var wounded := 0.0
var pose := ""          # 留空=按状态自动选姿态

var _tex: Texture2D = null
var _fallback: ActorPainter = null
var _t := 0.0
var _cur_key := ""

## 剧本角色键 → 立绘目录名（主角在资源表里叫 linday）
const CHAR_DIR := {
	"linzhou": "linday", "me": "linday",
	"zhouxu": "zhouxu", "liangye": "liangye",
	"xuqing": "xuqing", "shenhe": "shenhe", "oldqin": "oldqin",
}

## 每角色可用姿态（对应资源表 pose 配置）
const POSES := {
	"zhouxu": ["pose01", "pose02"],
	"liangye": ["pose01", "pose02", "pose03", "pose04"],
	"xuqing": ["pose01", "pose02", "pose03"],
	"shenhe": ["pose01", "pose02", "pose03", "pose04"],
	"oldqin": ["pose01", "pose02"],
	"linday": ["pose01", "pose02", "pose03"],
}

## 表情回退链（覆盖剧本用到的全部表情 + 资源表定义的表情）
const EMO_FALLBACK := {
	# —— 通用基底
	"normal": ["normal", "neutral", "calm"],
	"neutral": ["neutral", "normal", "calm"],
	"calm": ["calm", "neutral", "normal"],
	# —— 周叙系
	"flat": ["flat", "neutral", "normal", "calm"],
	"cold": ["cold", "dark", "stare", "frown", "neutral", "normal"],
	"frown": ["frown", "displeased", "serious", "neutral", "normal"],
	"serious": ["serious", "frown", "neutral", "normal"],
	"urgent": ["urgent", "serious", "frown", "neutral", "normal"],
	"dark": ["dark", "cold", "serious", "neutral", "normal"],
	"soft": ["soft", "relief", "neutral", "normal"],
	"tired": ["tired", "sad", "neutral", "normal", "calm"],
	# —— 梁野系
	"annoyed": ["annoyed", "displeased", "frown", "normal"],
	"nervous": ["nervous", "scared", "fear", "normal"],
	"fear": ["fear", "nervous", "scared", "normal"],
	"scared": ["scared", "nervous", "fear", "normal"],
	"terrified": ["terrified", "scared", "nervous", "fear", "urgent", "serious", "frown", "normal", "neutral"],
	"panic": ["panic", "terrified", "scared", "nervous", "normal"],
	"blank": ["blank", "hollow", "empty", "half", "normal"],
	"relief": ["relief", "soft", "fragile", "normal"],
	"fragile": ["fragile", "relief", "sad", "normal"],
	"half": ["half", "blank", "hollow", "empty", "normal"],
	"half_assimilated": ["half", "blank", "hollow", "empty", "normal"],
	# —— 许清系
	"stare": ["stare", "cold", "empty", "neutral", "normal"],
	"displeased": ["displeased", "frown", "angry", "neutral", "normal"],
	"faintsmile": ["faintsmile", "faint_smile", "smile", "smirk", "neutral"],
	"faint_smile": ["faintsmile", "faint_smile", "smile", "smirk", "neutral"],
	"smile": ["smile", "faintsmile", "faint_smile", "relief", "soft", "neutral", "normal", "calm"],
	"smirk": ["smirk", "faintsmile", "faint_smile", "smile", "neutral"],
	"empty": ["empty", "hollow", "blank", "void", "neutral"],
	"unstable": ["unstable", "empty", "hollow", "neutral"],
	# —— 沈禾系
	"sad": ["sad", "tired", "hurt", "fragile", "empty", "calm", "neutral", "normal"],
	"hurt": ["hurt", "sad", "tired", "calm"],
	"hollow": ["hollow", "empty", "blank", "void", "calm"],
	"release": ["release", "faintsmile", "faint_smile", "calm"],
	"void": ["void", "hollow", "empty", "blank", "calm"],
	"dead": ["dead", "hollow", "empty", "calm"],
	# —— 老秦系
	"warning": ["warning", "nervous", "serious", "normal"],
	"shocked": ["shocked", "terrified", "scared", "nervous", "normal"],
	# —— 林昼系
	"confused": ["confused", "neutral", "normal"],
	"determined": ["determined", "serious", "neutral", "normal"],
	# —— 其它
	"angry": ["angry", "displeased", "frown", "serious", "stare", "hurt", "sad", "normal", "neutral", "calm"],
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_refresh()

func setup(who_id: String, emotion: String, pose_id: String = "") -> void:
	who = who_id
	emo = emotion if emotion != "" else "normal"
	pose = pose_id
	_refresh()

func _refresh() -> void:
	var key := "%s/%s/%s" % [who, emo, _auto_pose()]
	if key == _cur_key:
		return
	_cur_key = key
	_tex = _find_texture(who, emo)
	if _tex == null:
		if _fallback == null:
			_fallback = ActorPainterS.new()
			_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(_fallback)
		_fallback.visible = true
		_fallback.who = who
		_fallback.emo = emo
	elif _fallback != null:
		_fallback.visible = false
	queue_redraw()

## 按剧情状态自动挑姿态（剧本没显式指定时）
func _auto_pose() -> String:
	if pose != "":
		return pose
	match who:
		"liangye":
			var half := GameState.get_state("liangye_state") == "half_assimilated"
			if half or GameState.get_flag("flag_liangye_half_assimilated"):
				return "pose04"
			if emo in ["blank", "hollow", "empty"]:
				return "pose03"
			if emo in ["nervous", "scared", "terrified", "fear", "panic", "relief", "fragile"]:
				return "pose02"
			return "pose01"
		"zhouxu":
			if emo in ["dark", "tired", "urgent"] or GameState.get_num("trust_zhouxu") <= -2:
				return "pose02"
			return "pose01"
		"xuqing":
			if GameState.get_state("xuqing_state") in ["revealed", "destabilized", "observer"]:
				return "pose03"
			if emo in ["empty", "unstable"]:
				return "pose03"
			if emo in ["stare", "faintsmile", "faint_smile"] and GameState.current_chapter >= 3:
				return "pose02"
			return "pose01"
		"shenhe":
			if emo == "release":
				return "pose04"
			if GameState.current_chapter >= 5:
				return "pose03"
			if emo in ["sad", "tired", "hurt"]:
				return "pose02"
			return "pose01"
		"linzhou", "me":
			if emo == "empty":
				return "pose03"
			if emo in ["shocked", "determined"]:
				return "pose02"
			return "pose01"
	return "pose01"

func _find_texture(char_id: String, emotion: String) -> Texture2D:
	var dir := String(CHAR_DIR.get(char_id, char_id))
	var chain: Array = EMO_FALLBACK.get(emotion, [emotion, "normal", "neutral", "calm"])
	var want := _auto_pose()

	# 1+2. 指定姿态 + 表情回退链
	for e in chain:
		var p := "%s/%s/%s_%s_%s.png" % [SPRITE_ROOT, dir, dir, want, String(e)]
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	# 3. 其它姿态 + 表情回退链
	var all_poses: Array = POSES.get(dir, ["pose01", "pose02", "pose03", "pose04"])
	for e in chain:
		for pz in all_poses:
			var p2 := "%s/%s/%s_%s_%s.png" % [SPRITE_ROOT, dir, dir, String(pz), String(e)]
			if ResourceLoader.exists(p2):
				return load(p2) as Texture2D
	# 4. 该角色任意一张
	for pz in all_poses:
		for e in ["neutral", "normal", "calm"]:
			var p3 := "%s/%s/%s_%s_%s.png" % [SPRITE_ROOT, dir, dir, String(pz), e]
			if ResourceLoader.exists(p3):
				return load(p3) as Texture2D
	return null

func _process(delta: float) -> void:
	_t += delta
	if _fallback != null and _fallback.visible:
		_fallback.active = active
		_fallback.glitch = glitch
		_fallback.wounded = wounded
	if _tex != null:
		queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	var scale := minf(s.x / tw, s.y / th)
	var dw := tw * scale
	var dh := th * scale
	var breathe := sin(_t * 1.1) * 1.5
	var pos := Vector2((s.x - dw) * 0.5, s.y - dh + breathe)
	var tint := Color(1, 1, 1, 1) if active else Color(0.55, 0.58, 0.62, 0.92)

	if glitch > 0.02:
		var off := Vector2(sin(_t * 7.0) * 9.0 * glitch, 0.0)
		draw_texture_rect(_tex, Rect2(pos + off, Vector2(dw, dh)), false,
			Color(0.65, 0.95, 0.92, 0.16 * glitch))
		draw_texture_rect(_tex, Rect2(pos - off, Vector2(dw, dh)), false,
			Color(0.95, 0.55, 0.55, 0.13 * glitch))

	draw_texture_rect(_tex, Rect2(pos, Vector2(dw, dh)), false, tint)

	if wounded > 0.0 and SaveSystem.gore_level() > 0:
		var lv := SaveSystem.gore_level()
		var amount: float = wounded * (0.5 if lv == 1 else 1.0)
		var blood: Color = Cfg.PALETTE["blood_bright"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(who) * 3 + 11
		var n := int(6 * amount) + 1
		for i in n:
			var px := pos.x + dw * rng.randf_range(0.25, 0.75)
			var py := pos.y + dh * rng.randf_range(0.18, 0.72)
			draw_circle(Vector2(px, py), rng.randf_range(4, 13) * amount,
				Color(blood.r * 0.7, blood.g * 0.4, blood.b * 0.4, 0.75 * amount))
			if lv == 2:
				draw_rect(Rect2(px - 2, py, 4, rng.randf_range(10, 46) * amount),
					Color(blood.r * 0.6, 0.05, 0.05, 0.6 * amount))
