extends Control
class_name SplashScreen
## 开场动画：显示引擎标识与制作信息，然后淡入标题画面。
##
## 三段式：
##   1. Godot Engine 标识（引擎署名）
##   2. 制作信息与内容分级提示
##   3. 淡出，进入标题
##
## 全程可点击跳过。所有绘制都是代码画的，不依赖任何贴图，
## 因此不会因为缺资源而卡在开场——这是启动路径，必须最稳。

signal finished

const STAGE_DUR := [2.2, 2.6]     # 每段停留时长
const FADE := 0.5                 # 段间淡入淡出

var _t := 0.0
var _stage := 0
var _skipped := false
var _done := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_right = 0.0
	offset_bottom = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	set_process_unhandled_input(true)
	gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_skip()
	)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		_skip()
	elif e is InputEventScreenTouch and e.pressed:
		_skip()

func _skip() -> void:
	if _done:
		return
	_skipped = true
	_finish()

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	queue_redraw()
	var limit: float = float(STAGE_DUR[_stage]) if _stage < STAGE_DUR.size() else 0.0
	if _t >= limit:
		_stage += 1
		_t = 0.0
		if _stage >= STAGE_DUR.size():
			_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		finished.emit()
		queue_free()
	)

## 当前段的淡入淡出系数（0→1→0）
func _alpha() -> float:
	if _stage >= STAGE_DUR.size():
		return 0.0
	var dur: float = float(STAGE_DUR[_stage])
	if _t < FADE:
		return clampf(_t / FADE, 0.0, 1.0)
	if _t > dur - FADE:
		return clampf((dur - _t) / FADE, 0.0, 1.0)
	return 1.0

func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		s = get_viewport_rect().size
	# 纯黑底
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.025), true)

	var a := _alpha()
	if a <= 0.001:
		return
	var f := get_theme_default_font()
	var cx := s.x * 0.5
	var cy := s.y * 0.5

	match _stage:
		0:
			_draw_engine(s, f, cx, cy, a)
		1:
			_draw_credits(s, f, cx, cy, a)

	# 跳过提示
	if not _skipped:
		draw_string(f, Vector2(s.x - 150.0, s.y - 28.0), "点击跳过",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(0.42, 0.42, 0.46, a * 0.75))

## 第一段：引擎标识
func _draw_engine(s: Vector2, f: Font, cx: float, cy: float, a: float) -> void:
	# Godot 机器人头像的简化剪影（代码绘制，不依赖贴图）
	var r := minf(s.x, s.y) * 0.085
	var head := Vector2(cx, cy - r * 0.5)
	var body := Color(0.30, 0.47, 0.62, a)
	var eye := Color(0.92, 0.95, 0.98, a)

	# 头部轮廓
	var pts := PackedVector2Array([
		head + Vector2(-r, -r * 0.55),
		head + Vector2(r, -r * 0.55),
		head + Vector2(r * 1.05, r * 0.5),
		head + Vector2(0, r * 0.95),
		head + Vector2(-r * 1.05, r * 0.5),
	])
	draw_colored_polygon(pts, body)
	# 两只眼睛
	draw_circle(head + Vector2(-r * 0.42, -r * 0.05), r * 0.24, eye)
	draw_circle(head + Vector2(r * 0.42, -r * 0.05), r * 0.24, eye)
	draw_circle(head + Vector2(-r * 0.42, -r * 0.05), r * 0.11, Color(0.12, 0.16, 0.2, a))
	draw_circle(head + Vector2(r * 0.42, -r * 0.05), r * 0.11, Color(0.12, 0.16, 0.2, a))
	# 嘴部横槽
	draw_rect(Rect2(head.x - r * 0.5, head.y + r * 0.42, r, r * 0.13),
		Color(0.16, 0.26, 0.34, a), true)

	var y := cy + r * 1.5
	draw_string(f, Vector2(0, y), "MADE WITH GODOT ENGINE",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 24, Color(0.80, 0.84, 0.88, a))
	draw_string(f, Vector2(0, y + 30.0), "godotengine.org",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 15, Color(0.45, 0.50, 0.56, a * 0.9))

## 第二段：作品信息与分级提示
func _draw_credits(s: Vector2, f: Font, cx: float, cy: float, a: float) -> void:
	draw_string(f, Vector2(0, cy - 58.0), Cfg.GAME_TITLE,
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 40, Color(0.88, 0.86, 0.80, a))
	draw_string(f, Vector2(0, cy - 22.0), Cfg.GAME_SUBTITLE,
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 15, Color(0.50, 0.48, 0.46, a * 0.9))

	# 分隔线
	var lw := minf(s.x * 0.30, 320.0)
	draw_rect(Rect2(cx - lw * 0.5, cy + 2.0, lw, 1.0),
		Color(0.42, 0.39, 0.36, a * 0.55), true)

	draw_string(f, Vector2(0, cy + 42.0), "本作含惊悚与少量血腥描写",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(0.72, 0.62, 0.58, a))
	draw_string(f, Vector2(0, cy + 70.0), "建议在光线充足的环境下游玩",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 16, Color(0.58, 0.56, 0.54, a * 0.9))
	draw_string(f, Vector2(0, cy + 104.0), "血腥表现可在「设置」中调整或关闭",
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 15, Color(0.48, 0.47, 0.46, a * 0.85))

	draw_string(f, Vector2(0, s.y - 52.0), "v" + Cfg.VERSION,
		HORIZONTAL_ALIGNMENT_CENTER, s.x, 14, Color(0.38, 0.38, 0.40, a * 0.8))
