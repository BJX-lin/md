extends Control
class_name ActorPainter
## 程序化角色立绘：以剪影 + 校服块面 + 表情记号的方式绘制，
## 契合本作“克制、压抑、不走二次元夸张”的美术方向（c.md / e.md 立绘规范）。

var who := "linzhou"
var emo := "normal"
var active := true          # 说话中 = 高亮
var flip := false
var glitch := 0.0           # 异常度（沈禾/半同化梁野）
var wounded := 0.0          # 伤口/血迹程度
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	var info: Dictionary = Cfg.CHARACTERS.get(who, {})
	var col: Color = info.get("color", Color.WHITE)
	var build: float = float(info.get("build", 0.5))
	var dim := 1.0 if active else 0.42
	var breathe := sin(_t * (1.1 if who != "shenhe" else 0.55)) * 2.0

	var cx := s.x * 0.5
	var ground := s.y * 0.99
	var height := s.y * 0.94
	var head_r := height * 0.072
	var head_y := ground - height + head_r * 1.2 + breathe

	# 影子
	draw_circle(Vector2(cx, ground), height * 0.09, Color(0, 0, 0, 0.35))
	if who == "shenhe":
		# 沈禾没有影子；反而有第二道轮廓
		draw_circle(Vector2(cx, ground), height * 0.09, Color(0.1, 0.2, 0.2, 0.15))

	var body_col := Color(0.16, 0.17, 0.19).lerp(col, 0.22) * dim
	var uniform := Color(0.20, 0.22, 0.26).lerp(col, 0.30) * dim
	var skin := Color(0.72, 0.66, 0.60).lerp(col, 0.10) * dim
	if who == "shenhe":
		skin = Color(0.78, 0.82, 0.80) * dim
		uniform = Color(0.24, 0.30, 0.31) * dim
	if who == "xuqing":
		uniform = Color(0.28, 0.24, 0.27) * dim

	var gj := 0.0
	if glitch > 0.0:
		gj = sin(_t * 31.0) * glitch * 6.0

	# 腿
	var leg_w := height * 0.052 * (0.9 + build * 0.3)
	draw_rect(Rect2(cx - leg_w * 1.5, ground - height * 0.42, leg_w, height * 0.42), body_col.darkened(0.35))
	draw_rect(Rect2(cx + leg_w * 0.5, ground - height * 0.42, leg_w, height * 0.42), body_col.darkened(0.35))
	# 鞋（许清不穿鞋：伏笔）
	if who != "xuqing":
		draw_rect(Rect2(cx - leg_w * 1.7, ground - height * 0.035, leg_w * 1.5, height * 0.035), Color(0.10, 0.10, 0.11) * dim)
		draw_rect(Rect2(cx + leg_w * 0.3, ground - height * 0.035, leg_w * 1.5, height * 0.035), Color(0.10, 0.10, 0.11) * dim)
	else:
		draw_rect(Rect2(cx - leg_w * 1.6, ground - height * 0.02, leg_w * 1.2, height * 0.02), skin)
		draw_rect(Rect2(cx + leg_w * 0.4, ground - height * 0.02, leg_w * 1.2, height * 0.02), skin)

	# 躯干（校服）
	var torso_w := height * (0.15 + build * 0.09)
	var torso_h := height * 0.40
	var torso := Rect2(cx - torso_w * 0.5 + gj, ground - height * 0.42 - torso_h + breathe * 0.4, torso_w, torso_h)
	draw_rect(torso, uniform)
	# 校服拉链/开襟
	draw_line(Vector2(torso.position.x + torso_w * 0.5, torso.position.y + 6), Vector2(torso.position.x + torso_w * 0.5, torso.end.y - 6), Color(0.9, 0.9, 0.88, 0.18), 2.0)
	# 蓝白条纹（国产校服特征）
	draw_rect(Rect2(torso.position.x, torso.position.y + torso_h * 0.16, torso_w, torso_h * 0.045), Color(0.82, 0.83, 0.85, 0.55) * dim)
	draw_rect(Rect2(torso.position.x, torso.position.y + torso_h * 0.22, torso_w, torso_h * 0.02), Color(0.25, 0.35, 0.55, 0.6) * dim)

	# 手臂
	var arm_w := height * 0.042
	var arm_swing := sin(_t * 1.05) * 3.0
	draw_rect(Rect2(torso.position.x - arm_w * 0.9, torso.position.y + torso_h * 0.06 + arm_swing, arm_w, torso_h * 0.82), uniform.darkened(0.12))
	draw_rect(Rect2(torso.end.x - arm_w * 0.1, torso.position.y + torso_h * 0.06 - arm_swing, arm_w, torso_h * 0.82), uniform.darkened(0.12))
	# 手
	draw_circle(Vector2(torso.position.x - arm_w * 0.4, torso.position.y + torso_h * 0.9 + arm_swing), arm_w * 0.55, skin)
	draw_circle(Vector2(torso.end.x + arm_w * 0.4, torso.position.y + torso_h * 0.9 - arm_swing), arm_w * 0.55, skin)

	# 脖子与头
	draw_rect(Rect2(cx - head_r * 0.34 + gj, torso.position.y - head_r * 0.55, head_r * 0.68, head_r * 0.6), skin.darkened(0.12))
	var head_c := Vector2(cx + gj, head_y)
	draw_circle(head_c, head_r, skin)
	# 头发
	_draw_hair(head_c, head_r, dim)

	# 表情
	_draw_face(head_c, head_r, dim)

	# 特殊：沈禾的湿发滴水与焦边袖口
	if who == "shenhe":
		for i in 5:
			var dx := head_c.x + (i - 2) * head_r * 0.35
			var dy := head_c.y + head_r * 0.9 + fmod(_t * 60.0 + i * 33.0, height * 0.35)
			draw_line(Vector2(dx, dy), Vector2(dx, dy + 8), Color(0.6, 0.75, 0.75, 0.35), 1.5)
		draw_rect(Rect2(torso.position.x - arm_w, torso.position.y + torso_h * 0.78, arm_w * 1.4, torso_h * 0.12), Color(0.08, 0.06, 0.05, 0.9))
		draw_rect(Rect2(torso.end.x - arm_w * 0.3, torso.position.y + torso_h * 0.78, arm_w * 1.4, torso_h * 0.12), Color(0.08, 0.06, 0.05, 0.9))

	# 血腥表现
	if wounded > 0.0 and SaveSystem.gore_level() > 0:
		_draw_wounds(torso, head_c, head_r, dim)

	# 异常错位重影
	if glitch > 0.05:
		var ghost_off := Vector2(sin(_t * 7.0) * 9.0 * glitch, 0)
		draw_set_transform(ghost_off, 0.0, Vector2.ONE)
		draw_circle(head_c, head_r, Color(0.7, 0.9, 0.88, 0.10 * glitch))
		draw_rect(torso, Color(0.7, 0.9, 0.88, 0.08 * glitch))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 说话高亮描边
	if active:
		draw_arc(head_c, head_r + 3.0, 0, TAU, 24, Color(col.r, col.g, col.b, 0.20), 2.0)

func _draw_hair(c: Vector2, r: float, dim: float) -> void:
	var hair := Color(0.09, 0.08, 0.09) * dim
	match who:
		"linzhou", "me":
			draw_circle(c + Vector2(0, -r * 0.22), r * 1.02, hair)
			draw_rect(Rect2(c.x - r, c.y - r * 1.1, r * 2, r * 0.85), hair)
		"zhouxu":
			draw_rect(Rect2(c.x - r * 1.02, c.y - r * 1.18, r * 2.04, r * 0.95), hair)  # 板正短发
			draw_rect(Rect2(c.x - r * 1.02, c.y - r * 0.3, r * 0.22, r * 0.5), hair)
		"liangye":
			draw_circle(c + Vector2(0, -r * 0.25), r * 1.05, hair)
			for i in 6:  # 乱翘
				var a := -PI * 0.9 + i * 0.32
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.95, c + Vector2(cos(a), sin(a)) * r * 1.42, hair, 2.5)
		"xuqing":
			draw_circle(c + Vector2(0, -r * 0.2), r * 1.04, hair)
			draw_rect(Rect2(c.x - r * 1.15, c.y - r * 0.4, r * 0.32, r * 1.9), hair)   # 及肩直发
			draw_rect(Rect2(c.x + r * 0.83, c.y - r * 0.4, r * 0.32, r * 1.9), hair)
		"shenhe", "voice":
			var wet_hair := Color(0.07, 0.09, 0.10) * dim
			draw_circle(c + Vector2(0, -r * 0.15), r * 1.06, wet_hair)
			for i in 11:  # 湿发缕
				var hx := c.x - r + i * r * 0.2
				var wave := sin(_t * 0.7 + i) * r * 0.12
				draw_line(Vector2(hx, c.y - r * 0.4), Vector2(hx + wave, c.y + r * 2.6), wet_hair, 3.0)
		"oldqin":
			draw_arc(c + Vector2(0, -r * 0.1), r * 1.0, PI * 1.05, PI * 1.95, 16, Color(0.55, 0.54, 0.50) * dim, 5.0)
		_:
			draw_circle(c + Vector2(0, -r * 0.2), r * 1.02, hair)

func _draw_face(c: Vector2, r: float, dim: float) -> void:
	var ink := Color(0.06, 0.06, 0.07) * dim
	var ey := c.y - r * 0.08
	var ex := r * 0.38
	var blink := 1.0
	if fmod(_t + float(hash(who) % 100) * 0.03, 4.6) < 0.12:
		blink = 0.12
	match emo:
		"fear", "panic", "terrified":
			# 睁大的眼
			draw_circle(Vector2(c.x - ex, ey), r * 0.17, Color(0.92, 0.92, 0.90) * dim)
			draw_circle(Vector2(c.x + ex, ey), r * 0.17, Color(0.92, 0.92, 0.90) * dim)
			draw_circle(Vector2(c.x - ex, ey), r * 0.075, ink)
			draw_circle(Vector2(c.x + ex, ey), r * 0.075, ink)
			draw_arc(Vector2(c.x, c.y + r * 0.42), r * 0.22, PI * 0.15, PI * 0.85, 12, ink, 2.0)
		"cold", "flat":
			draw_line(Vector2(c.x - ex - r * 0.14, ey), Vector2(c.x - ex + r * 0.14, ey), ink, 2.6)
			draw_line(Vector2(c.x + ex - r * 0.14, ey), Vector2(c.x + ex + r * 0.14, ey), ink, 2.6)
			draw_line(Vector2(c.x - r * 0.2, c.y + r * 0.44), Vector2(c.x + r * 0.2, c.y + r * 0.44), ink, 2.0)
		"angry":
			draw_line(Vector2(c.x - ex - r * 0.16, ey - r * 0.12), Vector2(c.x - ex + r * 0.14, ey + r * 0.02), ink, 3.0)
			draw_line(Vector2(c.x + ex - r * 0.14, ey + r * 0.02), Vector2(c.x + ex + r * 0.16, ey - r * 0.12), ink, 3.0)
			draw_line(Vector2(c.x - r * 0.22, c.y + r * 0.46), Vector2(c.x + r * 0.22, c.y + r * 0.40), ink, 2.4)
		"sad", "tired":
			draw_arc(Vector2(c.x - ex, ey), r * 0.14, PI, TAU, 10, ink, 2.4)
			draw_arc(Vector2(c.x + ex, ey), r * 0.14, PI, TAU, 10, ink, 2.4)
			draw_arc(Vector2(c.x, c.y + r * 0.62), r * 0.24, PI * 1.15, PI * 1.85, 12, ink, 2.0)
		"smile", "smirk":
			draw_line(Vector2(c.x - ex - r * 0.12, ey), Vector2(c.x - ex + r * 0.12, ey - r * 0.05), ink, 2.4)
			draw_line(Vector2(c.x + ex - r * 0.12, ey - r * 0.05), Vector2(c.x + ex + r * 0.12, ey), ink, 2.4)
			draw_arc(Vector2(c.x, c.y + r * 0.28), r * 0.28, PI * 0.18, PI * 0.82, 14, ink, 2.2)
		"hollow", "dead", "void":
			# 空洞的眼窝
			draw_circle(Vector2(c.x - ex, ey), r * 0.16, Color(0.03, 0.03, 0.04))
			draw_circle(Vector2(c.x + ex, ey), r * 0.16, Color(0.03, 0.03, 0.04))
			draw_line(Vector2(c.x - r * 0.18, c.y + r * 0.46), Vector2(c.x + r * 0.18, c.y + r * 0.46), Color(0.03, 0.03, 0.04), 2.2)
		_:
			draw_rect(Rect2(c.x - ex - r * 0.12, ey - r * 0.055 * blink, r * 0.24, r * 0.11 * blink), ink)
			draw_rect(Rect2(c.x + ex - r * 0.12, ey - r * 0.055 * blink, r * 0.24, r * 0.11 * blink), ink)
			draw_line(Vector2(c.x - r * 0.16, c.y + r * 0.44), Vector2(c.x + r * 0.16, c.y + r * 0.44), ink, 1.8)
	# 鼻影
	draw_line(Vector2(c.x, c.y + r * 0.06), Vector2(c.x - r * 0.05, c.y + r * 0.24), Color(0, 0, 0, 0.18 * dim), 1.5)

func _draw_wounds(torso: Rect2, head_c: Vector2, head_r: float, dim: float) -> void:
	var lv := SaveSystem.gore_level()
	var blood: Color = Cfg.PALETTE["blood_bright"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(who) * 3 + 11
	var amount := wounded * (0.5 if lv == 1 else 1.0)
	# 面部血痕
	draw_line(head_c + Vector2(head_r * 0.3, -head_r * 0.5), head_c + Vector2(head_r * 0.42, head_r * 0.9), Color(blood.r, blood.g, blood.b, 0.85 * amount), 3.0)
	# 校服血渍
	var n := int(6 * amount) + 1
	for i in n:
		var px := torso.position.x + rng.randf() * torso.size.x
		var py := torso.position.y + rng.randf() * torso.size.y
		draw_circle(Vector2(px, py), rng.randf_range(4, 14) * amount, Color(blood.r * 0.7, blood.g * 0.5, blood.b * 0.5, 0.8 * amount))
		if lv == 2:
			draw_rect(Rect2(px - 2, py, 4, rng.randf_range(10, 40) * amount), Color(blood.r * 0.6, 0.05, 0.05, 0.7 * amount))
	# 完整血腥：手部滴血
	if lv == 2 and amount > 0.6:
		var hand := Vector2(torso.position.x - 6, torso.position.y + torso.size.y * 0.92)
		for i in 4:
			var dy := fmod(_t * 90.0 + i * 40.0, 120.0)
			draw_circle(hand + Vector2(0, dy), 3.0, Color(blood.r, 0.06, 0.06, clampf(1.0 - dy / 120.0, 0.0, 1.0) * amount))
