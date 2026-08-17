extends Control
class_name BGLayer
## 背景层：优先使用 AI 生成的 PNG 背景，缺图时自动回退到代码绘制（bg_painter.gd）。
##
## 资源命名规范：
##   res://assets/bg/<scene_id>_<variant>.png   例：classroom_night.png
##   res://assets/bg/<scene_id>.png             无变体通用图
## 找不到时回退 BGPainter，保证任何场景都不会开天窗。

const BG_ROOT := "res://assets/bg"
const BGPainterS := preload("res://src/art/bg_painter.gd")

var scene_id := "black"
var variant := ""
var flicker := 0.0
var blood_amount := 0.0
var wet := 0.0

var _tex: Texture2D = null
var _painter: BGPainter = null
var _t := 0.0
var _cur_key := ""

## 变体回退链：夜景缺图时退到通用图，而不是直接掉回代码绘制
const VAR_FALLBACK := {
	"night": ["night", "dark", ""],
	"dark": ["dark", "night", ""],
	"dusk": ["dusk", "night", ""],
	"day": ["day", ""],
	"rain": ["rain", "night", "dusk", ""],
	"blood": ["blood", "dark", "night", ""],
	"fire": ["fire", "dark", "night", ""],
	"": [""],
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)

func set_scene(id: String, v: String = "") -> void:
	scene_id = id
	variant = v
	var key := id + "|" + v
	if key == _cur_key:
		return
	_cur_key = key
	_tex = _find_texture(id, v)
	if _tex == null:
		if _painter == null:
			_painter = BGPainterS.new()
			add_child(_painter)
			move_child(_painter, 0)
		_painter.visible = true
		_painter.set_scene(id, v)
	elif _painter != null:
		_painter.visible = false
	queue_redraw()

func _find_texture(id: String, v: String) -> Texture2D:
	if id == "black" or id == "white":
		return null       # 纯色由代码画，无需贴图
	var chain: Array = VAR_FALLBACK.get(v, [v, ""])
	for cand in chain:
		var suffix := "" if String(cand) == "" else "_" + String(cand)
		var p := "%s/%s%s.png" % [BG_ROOT, id, suffix]
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null

func _process(delta: float) -> void:
	_t += delta
	if _painter != null and _painter.visible:
		_painter.flicker = flicker
		_painter.blood_amount = blood_amount
		_painter.wet = wet
	if _tex != null:
		queue_redraw()

func _draw() -> void:
	var s := size
	if _tex == null:
		return
	# 等比铺满（cover），多余部分裁掉，避免黑边
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	var scale := maxf(s.x / tw, s.y / th)
	var dw := tw * scale
	var dh := th * scale
	var pos := Vector2((s.x - dw) * 0.5, (s.y - dh) * 0.5)
	# 灯光闪烁：整体压暗
	var lm := 1.0 - flicker * 0.55
	draw_texture_rect(_tex, Rect2(pos, Vector2(dw, dh)), false, Color(lm, lm, lm, 1.0))

	# 雨（贴图之上叠加动态雨丝）
	if wet > 0.01 or variant == "rain":
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in 110:
			var sp := 1.0 + rng.randf() * 2.0
			var x := fmod(rng.randf() * s.x + _t * 40.0 * sp, s.x)
			var y := fmod(rng.randf() * s.y + _t * 900.0 * sp, s.y)
			draw_line(Vector2(x, y), Vector2(x - 5, y + 26 * sp),
				Color(0.75, 0.82, 0.88, 0.15), 1.2)

	# 血污
	if blood_amount > 0.01 and SaveSystem.gore_level() > 0:
		var lv := SaveSystem.gore_level()
		var col: Color = Cfg.PALETTE["blood"]
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash(scene_id) + 7
		var n := int(blood_amount * (10 if lv == 1 else 24))
		for i in n:
			var cx := rng2.randf() * s.x
			var cy := s.y * (0.35 + rng2.randf() * 0.6)
			var r := rng2.randf_range(6.0, 32.0) * (0.6 if lv == 1 else 1.0)
			draw_circle(Vector2(cx, cy), r, Color(col.r, col.g, col.b, 0.5 * blood_amount))
			if lv == 2 and rng2.randf() < 0.6:
				var hh := rng2.randf_range(20.0, 110.0) * blood_amount
				draw_rect(Rect2(cx - r * 0.18, cy, r * 0.36, hh),
					Color(col.r, col.g, col.b, 0.38 * blood_amount))

	# 暗角
	var steps := 14
	for i in steps:
		var f := float(i) / steps
		var m := s * 0.5 * f * 0.9
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, m.y)), Color(0, 0, 0, 0.012))
		draw_rect(Rect2(0, s.y - m.y, s.x, m.y), Color(0, 0, 0, 0.012))
		draw_rect(Rect2(0, 0, m.x, s.y), Color(0, 0, 0, 0.010))
		draw_rect(Rect2(s.x - m.x, 0, m.x, s.y), Color(0, 0, 0, 0.010))
