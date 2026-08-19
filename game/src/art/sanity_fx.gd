extends Control
class_name SanityFX
## 理智值对 UI 的持续影响层（不篡改文字，只改变呈现）
##
## 设计原则：
##   * 理智越低，界面越"不可靠"，但**文字内容始终可读**
##   * 所有效果强度随 sanity 连续变化，没有突变
##   * 尊重玩家设置：关闭震动 / 关闭强闪光时自动削弱
##
## 分档（对应 config.gd TH_SANITY）：
##   80+   干净
##   60-79 轻微暗角收紧、极淡噪点
##   40-59 呼吸式明暗、边缘冷色偏
##   25-39 画面轻微抖动、色差分离、心跳暗角
##   10-24 抖动加剧、偶发闪烁、余光黑影
##   <10   持续色差、频繁闪断、视野明显收窄

## 理智低于此值开始出现血色暗角。
## 比正文重影（20）略早一点：先"看见血"，再"看不清字"。
const BLOOD_AT := 35.0

var _t := 0.0
var _noise_seed := 0
var _flash_timer := 0.0
var _blackout := 0.0        # 瞬时闪断
var _shudder := Vector2.ZERO
var _was_active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)

## 0.0（完全正常）→ 1.0（濒临崩溃）
func severity() -> float:
	var san := float(GameState.get_num("sanity"))
	return clampf((80.0 - san) / 80.0, 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta
	_noise_seed = int(_t * 18.0)
	var sev := severity()

	# 抖动（受"画面震动"设置控制）
	if sev > 0.35 and bool(SaveSystem.settings.get("screen_shake", true)):
		var amp: float = (sev - 0.35) * 6.0
		_shudder = Vector2(
			sin(_t * 37.0) * amp * randf_range(0.4, 1.0),
			cos(_t * 41.0) * amp * randf_range(0.4, 1.0)
		)
	else:
		_shudder = Vector2.ZERO

	# 偶发闪断（受"强闪光"设置控制）
	if _blackout > 0.0:
		_blackout = maxf(0.0, _blackout - delta * 4.0)
	elif sev > 0.55:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			# 理智越低越频繁：8 秒 → 2 秒
			_flash_timer = randf_range(2.0, 9.0 - sev * 6.0)
			if bool(SaveSystem.settings.get("flash", true)):
				_blackout = 1.0
	# 性能：理智健康（sev≈0）时这一层什么都不画，
	# 却仍每帧 queue_redraw 一次全屏，属纯浪费。
	# 只在真正有效果、或刚从有效果变为无效果（需要清屏）时重绘。
	var active := sev > 0.01
	if active or _was_active:
		queue_redraw()
	_was_active = active

## 供 game_screen 取用，叠加到世界层位移上
func shudder_offset() -> Vector2:
	return _shudder

func _draw() -> void:
	var sev := severity()
	if sev <= 0.01:
		return
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return

	# ---- 0. 血色暗角贴图：理智 < 35 开始从四边渗入
	# 用真实血迹贴图代替纯黑暗角，恐怖感强得多。
	# 中心保持透明，不遮挡正文与立绘。缺图则跳过，下面的程序化暗角照常工作。
	var san0 := float(GameState.get_num("sanity"))
	if san0 < BLOOD_AT:
		var bt := UITex.get_tex("blood_vignette")
		if bt != null:
			var bg: float = clampf((BLOOD_AT - san0) / BLOOD_AT, 0.0, 1.0)
			# 心跳式脉动，越低越明显
			var beat: float = 0.85 + 0.15 * sin(_t * (1.4 + bg * 2.0))
			var ba: float = bg * 0.72 * beat
			draw_texture_rect(bt, Rect2(Vector2.ZERO, s), false, Color(1, 1, 1, ba))

	# ---- 1. 暗角收紧：理智越低，视野越窄
	var steps := 18
	var vig: float = 0.18 + sev * 0.55
	for i in steps:
		var f := float(i) / steps
		var m := s * 0.5 * f * (1.0 - vig * 0.55)
		var a: float = pow(f, 2.0) * vig * 0.06
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, m.y)), Color(0, 0, 0, a))
		draw_rect(Rect2(0, s.y - m.y, s.x, m.y), Color(0, 0, 0, a))
		draw_rect(Rect2(0, 0, m.x, s.y), Color(0, 0, 0, a * 0.85))
		draw_rect(Rect2(s.x - m.x, 0, m.x, s.y), Color(0, 0, 0, a * 0.85))

	# ---- 2. 呼吸式明暗（像心跳）
	if sev > 0.25:
		var pulse: float = pow(maxf(0.0, sin(_t * (1.2 + sev * 1.8))), 3.0)
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.0, 0.0, pulse * sev * 0.10))

	# ---- 3. 冷色偏 / 色差分离
	if sev > 0.45:
		var sep: float = (sev - 0.45) * 10.0
		draw_rect(Rect2(-sep, 0, s.x, s.y), Color(0.55, 0.15, 0.15, 0.035 * sev))
		draw_rect(Rect2(sep, 0, s.x, s.y), Color(0.12, 0.50, 0.50, 0.035 * sev))

	# ---- 4. 噪点
	if sev > 0.30:
		var rng := RandomNumberGenerator.new()
		rng.seed = _noise_seed
		var n := int(sev * 260.0)
		for i in n:
			var x := rng.randf() * s.x
			var y := rng.randf() * s.y
			draw_rect(Rect2(x, y, 2, 2), Color(0.85, 0.86, 0.84, rng.randf() * 0.09 * sev))

	# ---- 5. 余光黑影（理智很低时，画面边缘出现"有人站着"的暗块）
	if sev > 0.62:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = int(_t * 0.6)
		var a2: float = (sev - 0.62) * 0.9
		var side := rng2.randi() % 2
		var hx := (s.x * 0.04) if side == 0 else (s.x * 0.96)
		var hh := s.y * 0.42
		var hy := s.y * 0.52
		var breathe := sin(_t * 2.1) * 0.25 + 0.75
		draw_rect(Rect2(hx - s.x * 0.03, hy - hh * 0.5, s.x * 0.06, hh),
			Color(0.0, 0.0, 0.0, a2 * 0.30 * breathe))
		draw_circle(Vector2(hx, hy - hh * 0.5), s.x * 0.022,
			Color(0.0, 0.0, 0.0, a2 * 0.34 * breathe))

	# ---- 6. 瞬时闪断
	if _blackout > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, _blackout * 0.72))
