extends Control
class_name ActorSprite
## 立绘显示节点：优先加载 AI 生成的 PNG 立绘（带 alpha），
## 找不到对应表情文件时按「表情回退链」降级，全都没有则回退到代码绘制。
##
## 资源命名规范（对应 e.md 立绘表 / 用户提供的 character_expression_sheet）：
##   res://assets/sprites/<char_id>/<char_id>_<pose>_<exp>.png
##   例：assets/sprites/zhouxu/zhouxu_01_neutral.png

const SPRITE_ROOT := "res://assets/sprites"
const ActorPainterS := preload("res://src/art/actor_painter.gd")

var who := "linzhou"
var emo := "normal"
var active := true
var glitch := 0.0
var wounded := 0.0

var _tex: Texture2D = null
var _fallback: ActorPainter = null
var _t := 0.0
var _cur_key := ""

# 每个角色的默认姿态号（多数只有 01）
const DEFAULT_POSE := {
	"linzhou": "01", "zhouxu": "01", "liangye": "01",
	"xuqing": "01", "shenhe": "01", "oldqin": "01",
}

## 表情回退链：找不到该表情时依次尝试后面的
const EMO_FALLBACK := {
	"normal": ["normal", "neutral", "calm"],
	"neutral": ["neutral", "normal", "calm"],
	"calm": ["calm", "neutral", "normal"],
	"flat": ["flat", "neutral", "normal", "calm"],
	"cold": ["cold", "stare", "neutral", "flat", "normal"],
	"stare": ["stare", "cold", "neutral", "normal"],
	"smile": ["smile", "faint_smile", "relief", "normal"],
	"smirk": ["smirk", "faint_smile", "smile", "normal"],
	"faint_smile": ["faint_smile", "smile", "smirk", "normal"],
	"sad": ["sad", "tired", "hurt", "normal"],
	"tired": ["tired", "sad", "normal"],
	"hurt": ["hurt", "sad", "tired", "normal"],
	"fear": ["fear", "nervous", "scared", "normal"],
	"nervous": ["nervous", "fear", "scared", "normal"],
	"scared": ["scared", "fear", "nervous", "normal"],
	"terrified": ["terrified", "scared", "fear", "nervous", "normal"],
	"angry": ["angry", "displeased", "frown", "serious", "normal"],
	"displeased": ["displeased", "angry", "frown", "normal"],
	"frown": ["frown", "displeased", "serious", "normal"],
	"serious": ["serious", "frown", "neutral", "normal"],
	"hollow": ["hollow", "blank", "empty", "void", "normal"],
	"blank": ["blank", "hollow", "empty", "normal"],
	"empty": ["empty", "hollow", "blank", "normal"],
	"void": ["void", "hollow", "empty", "normal"],
	"dead": ["dead", "hollow", "empty", "normal"],
	"half_assimilated": ["half_assimilated", "blank", "hollow", "normal"],
	"unstable": ["unstable", "empty", "hollow", "normal"],
	"urgent": ["urgent", "serious", "frown", "normal"],
	"dark": ["dark", "cold", "serious", "normal"],
	"relief": ["relief", "smile", "normal"],
	"annoyed": ["annoyed", "displeased", "frown", "normal"],
	"release": ["release", "faint_smile", "calm", "normal"],
	"panic": ["panic", "terrified", "scared", "fear", "normal"],
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_refresh()

func setup(who_id: String, emotion: String) -> void:
	who = who_id
	emo = emotion if emotion != "" else "normal"
	_refresh()

func _refresh() -> void:
	var key := who + "/" + emo
	if key == _cur_key:
		return
	_cur_key = key
	_tex = _find_texture(who, emo)
	if _tex == null:
		# 没有任何贴图 → 启用代码绘制回退
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

func _find_texture(char_id: String, emotion: String) -> Texture2D:
	var pose := String(DEFAULT_POSE.get(char_id, "01"))
	var chain: Array = EMO_FALLBACK.get(emotion, [emotion, "normal", "neutral", "calm"])
	# 先按默认姿态找完整回退链
	for e in chain:
		var p := "%s/%s/%s_%s_%s.png" % [SPRITE_ROOT, char_id, char_id, pose, String(e)]
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	# 再扫该角色目录下任意姿态的同表情
	for e in chain:
		for pz in ["01", "02", "03", "04"]:
			var p2 := "%s/%s/%s_%s_%s.png" % [SPRITE_ROOT, char_id, char_id, pz, String(e)]
			if ResourceLoader.exists(p2):
				return load(p2) as Texture2D
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
	# 等比缩放，底部对齐（立绘脚底贴合站位基线）
	var scale := minf(s.x / tw, s.y / th)
	var dw := tw * scale
	var dh := th * scale
	var breathe := sin(_t * 1.1) * 1.5
	var pos := Vector2((s.x - dw) * 0.5, s.y - dh + breathe)

	# 未说话者压暗，突出当前说话人
	var tint := Color(1, 1, 1, 1) if active else Color(0.55, 0.58, 0.62, 0.92)

	# 异常状态：错位重影（沈禾 / 半同化梁野）
	if glitch > 0.02:
		var off := Vector2(sin(_t * 7.0) * 9.0 * glitch, 0.0)
		draw_texture_rect(_tex, Rect2(pos + off, Vector2(dw, dh)), false,
			Color(0.65, 0.95, 0.92, 0.16 * glitch))
		draw_texture_rect(_tex, Rect2(pos - off, Vector2(dw, dh)), false,
			Color(0.95, 0.55, 0.55, 0.13 * glitch))

	draw_texture_rect(_tex, Rect2(pos, Vector2(dw, dh)), false, tint)

	# 血腥叠加（受设置分级控制）
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
