extends Control
class_name BGPainter
## 程序化背景绘制：无外部图片资源，全部由代码绘制。
## 支持场景 id + 变体（day/dusk/night/rain/dark/blood/flood/fire...）

var scene_id := "black"
var variant := ""
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var flicker := 0.0        # 由 EffectsLayer 驱动的灯光闪烁
var blood_amount := 0.0   # 血污程度 0..1
var wet := 0.0            # 雨/水渍

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)

func set_scene(id: String, v: String = "") -> void:
	scene_id = id
	variant = v
	_rng.seed = hash(id + v)
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

# ---------------------------------------------------------------- 调色
func _palette() -> Dictionary:
	var base := {
		"sky": Color(0.16, 0.17, 0.20),
		"wall": Color(0.20, 0.20, 0.19),
		"wall2": Color(0.14, 0.14, 0.14),
		"floor": Color(0.11, 0.11, 0.12),
		"accent": Color(0.55, 0.48, 0.36),
		"light": Color(0.95, 0.90, 0.72),
		"deep": Color(0.05, 0.05, 0.06),
	}
	match variant:
		"day":
			base["sky"] = Color(0.62, 0.66, 0.68)
			base["wall"] = Color(0.44, 0.43, 0.40)
			base["wall2"] = Color(0.33, 0.33, 0.31)
			base["floor"] = Color(0.27, 0.26, 0.25)
			base["light"] = Color(1.0, 0.97, 0.86)
		"dusk":
			base["sky"] = Color(0.42, 0.30, 0.26)
			base["wall"] = Color(0.32, 0.27, 0.24)
			base["wall2"] = Color(0.22, 0.19, 0.18)
			base["floor"] = Color(0.18, 0.16, 0.15)
			base["light"] = Color(0.98, 0.78, 0.52)
		"night":
			base["sky"] = Color(0.07, 0.08, 0.12)
			base["wall"] = Color(0.15, 0.15, 0.16)
			base["wall2"] = Color(0.10, 0.10, 0.11)
			base["floor"] = Color(0.08, 0.08, 0.09)
			base["light"] = Color(0.72, 0.78, 0.85)
		"dark":
			base["sky"] = Color(0.03, 0.03, 0.04)
			base["wall"] = Color(0.08, 0.08, 0.09)
			base["wall2"] = Color(0.05, 0.05, 0.06)
			base["floor"] = Color(0.04, 0.04, 0.05)
			base["light"] = Color(0.42, 0.48, 0.52)
		"rain":
			base["sky"] = Color(0.13, 0.15, 0.17)
			base["wall"] = Color(0.17, 0.18, 0.18)
			base["wall2"] = Color(0.11, 0.12, 0.13)
			base["floor"] = Color(0.09, 0.10, 0.11)
			base["light"] = Color(0.66, 0.74, 0.80)
		"blood":
			base["wall"] = Color(0.20, 0.11, 0.11)
			base["wall2"] = Color(0.13, 0.07, 0.07)
			base["floor"] = Color(0.10, 0.05, 0.05)
			base["light"] = Color(0.85, 0.32, 0.26)
		"fire":
			base["sky"] = Color(0.30, 0.14, 0.07)
			base["wall"] = Color(0.30, 0.17, 0.10)
			base["wall2"] = Color(0.19, 0.10, 0.06)
			base["floor"] = Color(0.14, 0.07, 0.04)
			base["light"] = Color(1.0, 0.66, 0.28)
	return base

func _c(p: Dictionary, k: String) -> Color:
	var v: Color = p[k]
	return v

func _draw() -> void:
	var s := size
	var p := _palette()
	var lightmul := 1.0 - flicker * 0.55
	match scene_id:
		"black":
			draw_rect(Rect2(Vector2.ZERO, s), Color.BLACK)
		"classroom":
			_draw_classroom(s, p, lightmul)
		"office":
			_draw_office(s, p, lightmul)
		"hallway":
			_draw_hallway(s, p, lightmul)
		"library":
			_draw_library(s, p, lightmul)
		"dorm":
			_draw_dorm(s, p, lightmul)
		"dorm_door":
			_draw_dorm_door(s, p, lightmul)
		"oldbuilding_out":
			_draw_oldbuilding_out(s, p, lightmul)
		"oldbuilding_stair":
			_draw_stair(s, p, lightmul)
		"broadcast_door":
			_draw_broadcast_door(s, p, lightmul)
		"broadcast_room":
			_draw_broadcast_room(s, p, lightmul)
		"duty_room":
			_draw_duty_room(s, p, lightmul)
		"schoolyard":
			_draw_yard(s, p, lightmul)
		"history_hall":
			_draw_history_hall(s, p, lightmul)
		"archive":
			_draw_archive(s, p, lightmul)
		"monitor_room":
			_draw_monitor_room(s, p, lightmul)
		"mirror":
			_draw_mirror(s, p, lightmul)
		"white":
			draw_rect(Rect2(Vector2.ZERO, s), Color(0.85, 0.85, 0.83))
		_:
			_draw_generic(s, p)
	_draw_grain(s)
	if wet > 0.01 or variant == "rain":
		_draw_rain(s)
	if blood_amount > 0.01 and SaveSystem.gore_level() > 0:
		_draw_blood(s)
	_draw_vignette(s)

# ---------------------------------------------------------------- 通用元素
func _draw_generic(s: Vector2, p: Dictionary) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), p["wall2"])
	draw_rect(Rect2(0, s.y * 0.72, s.x, s.y * 0.28), p["floor"])

func _draw_grain(s: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_t * 12.0)
	for i in 90:
		var x := rng.randf() * s.x
		var y := rng.randf() * s.y
		var a := rng.randf() * 0.05
		draw_rect(Rect2(x, y, 2, 2), Color(1, 1, 1, a))

func _draw_vignette(s: Vector2) -> void:
	var steps := 16
	for i in steps:
		var f := float(i) / steps
		var a := pow(f, 2.2) * 0.5
		var m := s * 0.5 * f * 0.9
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, m.y)), Color(0, 0, 0, a * 0.12), true)
		draw_rect(Rect2(0, s.y - m.y, s.x, m.y), Color(0, 0, 0, a * 0.12), true)
		draw_rect(Rect2(0, 0, m.x, s.y), Color(0, 0, 0, a * 0.10), true)
		draw_rect(Rect2(s.x - m.x, 0, m.x, s.y), Color(0, 0, 0, a * 0.10), true)

func _draw_rain(s: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var amount := 120
	for i in amount:
		var sp := 1.0 + rng.randf() * 2.0
		var x := fmod(rng.randf() * s.x + _t * 40.0 * sp, s.x)
		var y := fmod(rng.randf() * s.y + _t * 900.0 * sp, s.y)
		draw_line(Vector2(x, y), Vector2(x - 5, y + 26 * sp), Color(0.75, 0.82, 0.88, 0.16), 1.2)

func _draw_blood(s: Vector2) -> void:
	var lv := SaveSystem.gore_level()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(scene_id) + 7
	var col: Color = Cfg.PALETTE["blood"]
	var n := int(blood_amount * (10 if lv == 1 else 26))
	for i in n:
		var cx := rng.randf() * s.x
		var cy := s.y * (0.35 + rng.randf() * 0.6)
		var r := rng.randf_range(6.0, 34.0) * (0.6 if lv == 1 else 1.0)
		draw_circle(Vector2(cx, cy), r, Color(col.r, col.g, col.b, 0.55 * blood_amount))
		# 拖痕
		if lv == 2 and rng.randf() < 0.6:
			var h := rng.randf_range(20.0, 120.0) * blood_amount
			draw_rect(Rect2(cx - r * 0.18, cy, r * 0.36, h), Color(col.r, col.g, col.b, 0.4 * blood_amount))
			draw_circle(Vector2(cx, cy + h), r * 0.35, Color(col.r, col.g, col.b, 0.42 * blood_amount))

func _light_cone(pos: Vector2, w: float, h: float, c: Color, a: float) -> void:
	var pts := PackedVector2Array([pos, pos + Vector2(-w, h), pos + Vector2(w, h)])
	draw_colored_polygon(pts, Color(c.r, c.g, c.b, a))

# ---------------------------------------------------------------- 具体场景
func _draw_classroom(s: Vector2, p: Dictionary, lm: float) -> void:
	var wall: Color = p["wall"] * lm
	draw_rect(Rect2(Vector2.ZERO, s), wall)
	# 墙裙
	draw_rect(Rect2(0, s.y * 0.55, s.x, s.y * 0.2), _c(p, "wall2") * lm)
	# 地板 + 透视线
	draw_rect(Rect2(0, s.y * 0.72, s.x, s.y * 0.28), _c(p, "floor") * lm)
	for i in 9:
		var x := s.x * i / 8.0
		draw_line(Vector2(x, s.y * 0.72), Vector2(s.x * 0.5 + (x - s.x * 0.5) * 2.2, s.y), Color(0, 0, 0, 0.18), 1.0)
	# 黑板
	var bb := Rect2(s.x * 0.08, s.y * 0.18, s.x * 0.46, s.y * 0.34)
	draw_rect(bb, Color(0.10, 0.14, 0.12) * lm)
	draw_rect(bb, Color(0.32, 0.28, 0.20, 0.8), false, 3.0)
	# 板书残影
	for i in 5:
		var yy := bb.position.y + 22 + i * bb.size.y / 6.0
		draw_line(Vector2(bb.position.x + 18, yy), Vector2(bb.position.x + 18 + _rng.randf_range(60, bb.size.x - 40), yy), Color(0.75, 0.78, 0.72, 0.10), 2.0)
	# 窗（右侧）
	for i in 3:
		var wx := s.x * (0.60 + i * 0.135)
		var wr := Rect2(wx, s.y * 0.16, s.x * 0.11, s.y * 0.36)
		draw_rect(wr, _c(p, "sky").lightened(0.05))
		draw_rect(wr, Color(0.25, 0.24, 0.22, 0.9), false, 3.0)
		draw_line(Vector2(wr.position.x, wr.position.y + wr.size.y * 0.5), Vector2(wr.end.x, wr.position.y + wr.size.y * 0.5), Color(0.25, 0.24, 0.22, 0.9), 2.0)
		if variant == "day":
			_light_cone(Vector2(wr.position.x + wr.size.x * 0.5, wr.end.y), wr.size.x * 1.4, s.y * 0.5, p["light"], 0.05)
	# 课桌阵列
	var rows := 4
	var cols := 5
	for r in rows:
		for c in cols:
			var depth := float(r) / rows
			var dw := lerpf(s.x * 0.075, s.x * 0.115, depth)
			var dh := lerpf(s.y * 0.035, s.y * 0.06, depth)
			var dx := s.x * 0.5 + (c - (cols - 1) * 0.5) * lerpf(s.x * 0.09, s.x * 0.145, depth) - dw * 0.5
			var dy := s.y * (0.60 + depth * 0.26)
			var empty := (r == rows - 1 and c == cols - 1)
			var col := Color(0.28, 0.24, 0.19) * lm
			if empty:
				col = Color(0.20, 0.17, 0.15) * lm
			draw_rect(Rect2(dx, dy, dw, dh), col)
			draw_rect(Rect2(dx + dw * 0.1, dy + dh, dw * 0.1, dh * 0.9), col.darkened(0.4))
			draw_rect(Rect2(dx + dw * 0.8, dy + dh, dw * 0.1, dh * 0.9), col.darkened(0.4))
			if empty:
				# 最后一排靠窗的空位：轻微高光
				draw_rect(Rect2(dx, dy, dw, dh), Color(0.7, 0.75, 0.78, 0.06 + 0.04 * sin(_t * 1.4)))
	# 日光灯
	for i in 2:
		var lx := s.x * (0.3 + i * 0.4)
		var on := 1.0 if variant != "dark" else 0.15
		draw_rect(Rect2(lx - s.x * 0.09, s.y * 0.06, s.x * 0.18, s.y * 0.022), Color(0.9, 0.92, 0.88, 0.55 * on * lm))
		_light_cone(Vector2(lx, s.y * 0.08), s.x * 0.22, s.y * 0.8, p["light"], 0.04 * on * lm)

func _draw_office(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), _c(p, "wall") * lm)
	draw_rect(Rect2(0, s.y * 0.70, s.x, s.y * 0.30), _c(p, "floor") * lm)
	# 文件柜
	for i in 3:
		var cx := s.x * (0.05 + i * 0.15)
		draw_rect(Rect2(cx, s.y * 0.22, s.x * 0.13, s.y * 0.5), Color(0.24, 0.23, 0.20) * lm)
		for k in 4:
			draw_rect(Rect2(cx + 6, s.y * (0.24 + k * 0.12), s.x * 0.13 - 12, s.y * 0.09), Color(0.18, 0.17, 0.15) * lm)
			draw_rect(Rect2(cx + s.x * 0.05, s.y * (0.275 + k * 0.12), s.x * 0.03, 4), Color(0.5, 0.47, 0.4, 0.6))
	# 办公桌
	var d := Rect2(s.x * 0.52, s.y * 0.55, s.x * 0.42, s.y * 0.12)
	draw_rect(d, Color(0.31, 0.25, 0.19) * lm)
	draw_rect(Rect2(d.position.x, d.end.y, d.size.x, s.y * 0.22), Color(0.22, 0.18, 0.14) * lm)
	# 桌上纸张（违纪记录表）
	draw_rect(Rect2(d.position.x + 40, d.position.y - 18, 130, 34), Color(0.82, 0.80, 0.74, 0.92))
	draw_rect(Rect2(d.position.x + 200, d.position.y - 14, 110, 28), Color(0.74, 0.71, 0.63, 0.88))
	for i in 4:
		draw_line(Vector2(d.position.x + 48, d.position.y - 12 + i * 7), Vector2(d.position.x + 160, d.position.y - 12 + i * 7), Color(0.2, 0.2, 0.2, 0.35), 1.0)
	# 窗
	var wr := Rect2(s.x * 0.63, s.y * 0.12, s.x * 0.3, s.y * 0.3)
	draw_rect(wr, p["sky"])
	draw_rect(wr, Color(0.24, 0.22, 0.20), false, 3.0)

func _draw_hallway(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), _c(p, "wall2") * lm)
	var vp := Vector2(s.x * 0.5, s.y * 0.52)
	# 远端
	draw_rect(Rect2(vp.x - s.x * 0.07, vp.y - s.y * 0.1, s.x * 0.14, s.y * 0.2), Color(0.04, 0.04, 0.05))
	# 地板与天花板透视
	draw_colored_polygon(PackedVector2Array([Vector2(0, s.y), Vector2(s.x, s.y), vp + Vector2(s.x * 0.07, s.y * 0.1), vp - Vector2(s.x * 0.07, -s.y * 0.1)]), _c(p, "floor") * lm)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), vp + Vector2(s.x * 0.07, -s.y * 0.1), vp - Vector2(s.x * 0.07, s.y * 0.1)]), (_c(p, "wall") * 0.7) * lm)
	# 侧墙门
	for i in 4:
		var f := 0.16 + i * 0.19
		var x0 := lerpf(0.0, vp.x - s.x * 0.07, f)
		var x1 := lerpf(0.0, vp.x - s.x * 0.07, f + 0.14)
		var yt := lerpf(0.0, vp.y - s.y * 0.1, f)
		var yb := lerpf(s.y, vp.y + s.y * 0.1, f)
		var yt1 := lerpf(0.0, vp.y - s.y * 0.1, f + 0.14)
		var yb1 := lerpf(s.y, vp.y + s.y * 0.1, f + 0.14)
		draw_colored_polygon(PackedVector2Array([Vector2(x0, yt + (yb - yt) * 0.18), Vector2(x1, yt1 + (yb1 - yt1) * 0.18), Vector2(x1, yb1), Vector2(x0, yb)]), Color(0.16, 0.14, 0.12) * lm)
		var mx0 := s.x - x0
		var mx1 := s.x - x1
		draw_colored_polygon(PackedVector2Array([Vector2(mx0, yt + (yb - yt) * 0.18), Vector2(mx1, yt1 + (yb1 - yt1) * 0.18), Vector2(mx1, yb1), Vector2(mx0, yb)]), Color(0.16, 0.14, 0.12) * lm)
	# 顶灯
	for i in 3:
		var f2 := 0.2 + i * 0.22
		var ly := lerpf(0.0, vp.y - s.y * 0.1, f2 + 0.2)
		var lw := lerpf(s.x * 0.16, s.x * 0.03, f2)
		var on := 1.0
		if i == 1:
			on = 0.25 + 0.75 * (1.0 if fmod(_t * 3.1, 1.0) >= 0.5 else 0.0)
		draw_rect(Rect2(vp.x - lw * 0.5, ly, lw, maxf(2.0, 8.0 * (1.0 - f2))), Color(0.92, 0.94, 0.88, 0.5 * on * lm))
		_light_cone(Vector2(vp.x, ly), lw * 1.6, s.y * 0.6, p["light"], 0.035 * on * lm)

func _draw_library(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.13, 0.11, 0.09) * lm)
	draw_rect(Rect2(0, s.y * 0.78, s.x, s.y * 0.22), Color(0.10, 0.08, 0.07) * lm)
	# 书架
	for i in 5:
		var bx := s.x * (0.03 + i * 0.2)
		var bw := s.x * 0.16
		draw_rect(Rect2(bx, s.y * 0.08, bw, s.y * 0.72), Color(0.19, 0.14, 0.10) * lm)
		for shelf in 6:
			var sy := s.y * (0.10 + shelf * 0.115)
			draw_rect(Rect2(bx + 4, sy, bw - 8, s.y * 0.10), Color(0.09, 0.07, 0.06))
			var rr := RandomNumberGenerator.new()
			rr.seed = i * 31 + shelf
			var x := bx + 8
			while x < bx + bw - 14:
				var w := rr.randf_range(6.0, 16.0)
				var h := s.y * rr.randf_range(0.06, 0.095)
				var c := Color(rr.randf_range(0.18, 0.42), rr.randf_range(0.14, 0.28), rr.randf_range(0.10, 0.22)) * lm
				draw_rect(Rect2(x, sy + s.y * 0.10 - h, w, h), c)
				x += w + 1.5
			draw_rect(Rect2(bx + 4, sy + s.y * 0.10, bw - 8, 4), Color(0.24, 0.18, 0.13) * lm)
	# 尘光
	_light_cone(Vector2(s.x * 0.5, 0), s.x * 0.3, s.y, p["light"], 0.03 * lm)

func _draw_dorm(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), _c(p, "wall") * lm)
	draw_rect(Rect2(0, s.y * 0.74, s.x, s.y * 0.26), _c(p, "floor") * lm)
	# 双层床（左右）
	for side in 2:
		var bx := s.x * 0.04 if side == 0 else s.x * 0.60
		var bw := s.x * 0.36
		for level in 2:
			var by := s.y * (0.20 + level * 0.30)
			draw_rect(Rect2(bx, by, bw, s.y * 0.06), Color(0.30, 0.28, 0.24) * lm)
			draw_rect(Rect2(bx + 6, by - s.y * 0.045, bw - 12, s.y * 0.05), Color(0.36, 0.30, 0.28) * lm)  # 被褥
			draw_rect(Rect2(bx, by, 8, s.y * 0.32), Color(0.22, 0.21, 0.19) * lm)
			draw_rect(Rect2(bx + bw - 8, by, 8, s.y * 0.32), Color(0.22, 0.21, 0.19) * lm)
			# 蚊帐
			draw_rect(Rect2(bx + 2, by - s.y * 0.16, bw - 4, s.y * 0.16), Color(0.75, 0.78, 0.76, 0.05))
	# 门
	var d := Rect2(s.x * 0.44, s.y * 0.28, s.x * 0.13, s.y * 0.46)
	draw_rect(d, Color(0.20, 0.16, 0.13) * lm)
	draw_rect(d, Color(0.30, 0.26, 0.22, 0.8), false, 2.0)
	draw_circle(Vector2(d.end.x - 14, d.position.y + d.size.y * 0.55), 5, Color(0.62, 0.58, 0.42, 0.8))
	# 门缝光
	draw_rect(Rect2(d.position.x, d.end.y - 4, d.size.x, 4), Color(0.85, 0.86, 0.75, 0.10 + 0.06 * sin(_t * 2.2)))

func _draw_dorm_door(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.07, 0.07, 0.08) * lm)
	var d := Rect2(s.x * 0.24, s.y * 0.06, s.x * 0.52, s.y * 0.9)
	draw_rect(d, Color(0.17, 0.13, 0.11) * lm)
	for i in 2:
		draw_rect(Rect2(d.position.x + s.x * 0.05, d.position.y + s.y * (0.08 + i * 0.42), d.size.x - s.x * 0.10, s.y * 0.34), Color(0.13, 0.10, 0.08) * lm)
	# 门镜
	draw_circle(Vector2(d.position.x + d.size.x * 0.5, d.position.y + d.size.y * 0.34), 16, Color(0.05, 0.05, 0.06))
	draw_circle(Vector2(d.position.x + d.size.x * 0.5, d.position.y + d.size.y * 0.34), 12, Color(0.55, 0.60, 0.58, 0.25 + 0.2 * sin(_t * 1.1)))
	# 门缝下的影子：数一数有几只脚
	var lightline := Rect2(d.position.x, d.end.y - 7, d.size.x, 7)
	draw_rect(lightline, Color(0.86, 0.86, 0.78, 0.22))
	var shadows := 2
	if GameState.get_flag("flag_shadow_count_wrong"):
		shadows = 3
	for i in shadows:
		var sx := lightline.position.x + lightline.size.x * (0.28 + i * 0.2)
		draw_rect(Rect2(sx, lightline.position.y, 26, 7), Color(0, 0, 0, 0.85))

func _draw_oldbuilding_out(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), _c(p, "sky"))
	# 楼体
	var b := Rect2(s.x * 0.08, s.y * 0.14, s.x * 0.84, s.y * 0.72)
	draw_rect(b, Color(0.16, 0.16, 0.15) * lm)
	draw_rect(b, Color(0.09, 0.09, 0.09), false, 3.0)
	# 窗格：只有一扇亮着
	var lit_r := 1
	var lit_c := 4
	for r in 4:
		for c in 7:
			var wr := Rect2(b.position.x + b.size.x * (0.05 + c * 0.132), b.position.y + b.size.y * (0.08 + r * 0.22), b.size.x * 0.095, b.size.y * 0.14)
			var on := (r == lit_r and c == lit_c)
			var col := Color(0.05, 0.05, 0.06)
			if on:
				var fl := 0.55 + 0.45 * sin(_t * 6.0 + 1.3)
				col = Color(0.85, 0.72, 0.42, 1.0).lerp(Color(0.2, 0.16, 0.1), 1.0 - fl)
			draw_rect(wr, col)
			draw_rect(wr, Color(0.10, 0.10, 0.10), false, 2.0)
	# 地面与杂草
	draw_rect(Rect2(0, s.y * 0.86, s.x, s.y * 0.14), Color(0.09, 0.10, 0.08) * lm)
	var rr := RandomNumberGenerator.new()
	rr.seed = 99
	for i in 60:
		var gx := rr.randf() * s.x
		var gh := rr.randf_range(6, 26)
		draw_line(Vector2(gx, s.y * 0.87), Vector2(gx + rr.randf_range(-4, 4), s.y * 0.87 - gh), Color(0.16, 0.20, 0.14, 0.7), 1.5)

func _draw_stair(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.09, 0.09, 0.09) * lm)
	# 楼梯
	var steps := 9
	for i in steps:
		var f := float(i) / steps
		var w := lerpf(s.x * 0.9, s.x * 0.3, f)
		var y := s.y * (0.95 - f * 0.62)
		var h := lerpf(s.y * 0.06, s.y * 0.03, f)
		draw_rect(Rect2(s.x * 0.5 - w * 0.5, y, w, h), Color(0.16, 0.15, 0.14).darkened(f * 0.5) * lm)
		draw_rect(Rect2(s.x * 0.5 - w * 0.5, y, w, 2), Color(0.30, 0.28, 0.24, 0.4))
	# 扶手
	draw_line(Vector2(s.x * 0.08, s.y * 0.93), Vector2(s.x * 0.36, s.y * 0.34), Color(0.28, 0.25, 0.21, 0.8), 4.0)
	draw_line(Vector2(s.x * 0.92, s.y * 0.93), Vector2(s.x * 0.64, s.y * 0.34), Color(0.28, 0.25, 0.21, 0.8), 4.0)
	# 上方黑口
	draw_rect(Rect2(s.x * 0.35, s.y * 0.06, s.x * 0.3, s.y * 0.28), Color(0.02, 0.02, 0.03))
	# 剥落墙皮
	var rr := RandomNumberGenerator.new()
	rr.seed = 17
	for i in 40:
		var px := rr.randf() * s.x
		var py := rr.randf() * s.y * 0.7
		draw_circle(Vector2(px, py), rr.randf_range(4, 22), Color(0.22, 0.20, 0.17, 0.25))

func _draw_broadcast_door(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.06, 0.07) * lm)
	var d := Rect2(s.x * 0.28, s.y * 0.10, s.x * 0.44, s.y * 0.84)
	draw_rect(d, Color(0.14, 0.15, 0.16) * lm)          # 铁门
	draw_rect(d, Color(0.24, 0.22, 0.20), false, 3.0)
	# 门半掩：门缝
	var gap := Rect2(d.end.x - s.x * 0.06, d.position.y, s.x * 0.06, d.size.y)
	draw_rect(gap, Color(0.02, 0.02, 0.02))
	var red := 0.5 + 0.5 * sin(_t * 5.0)
	draw_rect(gap, Color(0.85, 0.14, 0.10, 0.10 + 0.28 * red))
	draw_rect(Rect2(gap.position.x - 2, gap.position.y, 3, gap.size.y), Color(1.0, 0.3, 0.2, 0.15 + 0.3 * red))
	# 门牌
	draw_rect(Rect2(d.position.x + s.x * 0.06, d.position.y + s.y * 0.10, s.x * 0.16, s.y * 0.07), Color(0.55, 0.53, 0.46, 0.85))
	# 锈迹
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	for i in 30:
		draw_circle(Vector2(d.position.x + rr.randf() * d.size.x, d.position.y + rr.randf() * d.size.y), rr.randf_range(3, 16), Color(0.36, 0.20, 0.12, 0.28))

func _draw_broadcast_room(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.08, 0.07, 0.08) * lm)
	draw_rect(Rect2(0, s.y * 0.76, s.x, s.y * 0.24), Color(0.05, 0.05, 0.06))
	# 调音台
	var c := Rect2(s.x * 0.12, s.y * 0.58, s.x * 0.76, s.y * 0.2)
	draw_rect(c, Color(0.18, 0.17, 0.16) * lm)
	for i in 14:
		var fx := c.position.x + 22 + i * (c.size.x - 44) / 14.0
		draw_rect(Rect2(fx, c.position.y + 16, 6, c.size.y - 40), Color(0.10, 0.10, 0.10))
		var kv: float = 0.3 + 0.5 * absf(sin(_t * (0.7 + i * 0.11)))
		draw_rect(Rect2(fx - 5, c.position.y + 16 + (c.size.y - 46) * (1.0 - kv), 16, 8), Color(0.55, 0.52, 0.48))
	# VU 灯
	for i in 10:
		var on: bool = float(i) / 10.0 < 0.35 + 0.4 * absf(sin(_t * 3.0))
		draw_rect(Rect2(c.position.x + 20 + i * 22, c.position.y - 22, 16, 10), Color(0.9, 0.25, 0.18, 0.9) if on else Color(0.2, 0.1, 0.1, 0.7))
	# 麦克风
	draw_line(Vector2(s.x * 0.5, c.position.y), Vector2(s.x * 0.5, c.position.y - s.y * 0.16), Color(0.3, 0.3, 0.3), 3.0)
	draw_circle(Vector2(s.x * 0.5, c.position.y - s.y * 0.17), 14, Color(0.22, 0.22, 0.23))
	# 隔音墙泡沫
	for r in 5:
		for cc in 12:
			var q := Rect2(s.x * 0.05 + cc * s.x * 0.078, s.y * 0.08 + r * s.y * 0.075, s.x * 0.07, s.y * 0.065)
			draw_rect(q, Color(0.12, 0.11, 0.12).lightened(0.03 * ((r + cc) % 2)) * lm)
	# 播音椅（空/有人由 actor 层负责）
	draw_rect(Rect2(s.x * 0.44, s.y * 0.78, s.x * 0.12, s.y * 0.05), Color(0.20, 0.16, 0.15) * lm)
	# 红色 ON AIR
	var on_air := 0.4 + 0.6 * (1.0 if fmod(_t * 1.4, 1.0) >= 0.5 else 0.0)
	draw_rect(Rect2(s.x * 0.40, s.y * 0.03, s.x * 0.2, s.y * 0.05), Color(0.5, 0.08, 0.06, 0.35 + 0.5 * on_air))

func _draw_duty_room(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.15, 0.14, 0.12) * lm)
	draw_rect(Rect2(0, s.y * 0.72, s.x, s.y * 0.28), Color(0.10, 0.09, 0.08) * lm)
	# 钥匙板
	var kb := Rect2(s.x * 0.06, s.y * 0.16, s.x * 0.3, s.y * 0.36)
	draw_rect(kb, Color(0.26, 0.20, 0.14) * lm)
	for r in 3:
		for c in 6:
			var kx := kb.position.x + 18 + c * (kb.size.x - 36) / 6.0
			var ky := kb.position.y + 24 + r * (kb.size.y - 40) / 3.0
			draw_line(Vector2(kx, ky), Vector2(kx, ky + 16), Color(0.6, 0.55, 0.35, 0.8), 2.0)
			draw_circle(Vector2(kx, ky + 20), 5, Color(0.62, 0.56, 0.32, 0.85))
	# 桌 + 电水壶 + 烟灰缸
	var d := Rect2(s.x * 0.45, s.y * 0.55, s.x * 0.48, s.y * 0.1)
	draw_rect(d, Color(0.30, 0.24, 0.17) * lm)
	draw_rect(Rect2(d.position.x + 30, d.position.y - 40, 40, 40), Color(0.5, 0.5, 0.52) * lm)
	draw_circle(Vector2(d.position.x + 160, d.position.y - 10), 16, Color(0.35, 0.33, 0.30))
	# 小电视雪花
	var tv := Rect2(s.x * 0.72, s.y * 0.28, s.x * 0.2, s.y * 0.2)
	draw_rect(tv, Color(0.10, 0.10, 0.11))
	var rr := RandomNumberGenerator.new()
	rr.seed = int(_t * 20)
	for i in 200:
		draw_rect(Rect2(tv.position.x + rr.randf() * tv.size.x, tv.position.y + rr.randf() * tv.size.y, 2, 2), Color(0.7, 0.72, 0.7, rr.randf() * 0.5))

func _draw_yard(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), _c(p, "sky"))
	draw_rect(Rect2(0, s.y * 0.62, s.x, s.y * 0.38), Color(0.11, 0.13, 0.11) * lm)
	# 跑道弧线
	for i in 4:
		var yy := s.y * (0.70 + i * 0.05)
		draw_line(Vector2(0, yy), Vector2(s.x, yy - s.y * 0.02), Color(0.4, 0.24, 0.18, 0.25), 2.0)
	# 远处教学楼
	for i in 3:
		var bw := s.x * 0.28
		var bx := s.x * (0.02 + i * 0.33)
		var bh := s.y * (0.22 + i % 2 * 0.05)
		draw_rect(Rect2(bx, s.y * 0.62 - bh, bw, bh), Color(0.10, 0.10, 0.12) * lm)
		for r in 3:
			for c in 5:
				var lit := (i + r + c) % 7 == 0
				draw_rect(Rect2(bx + 12 + c * (bw - 24) / 5.0, s.y * 0.62 - bh + 12 + r * (bh - 24) / 3.0, (bw - 24) / 7.0, bh / 7.0), Color(0.85, 0.78, 0.5, 0.55) if lit else Color(0.06, 0.06, 0.08))
	# 旗杆
	draw_line(Vector2(s.x * 0.5, s.y * 0.62), Vector2(s.x * 0.5, s.y * 0.18), Color(0.55, 0.55, 0.55, 0.8), 3.0)
	var sway := sin(_t * 0.9) * 6.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(s.x * 0.5, s.y * 0.19), Vector2(s.x * 0.56 + sway, s.y * 0.21), Vector2(s.x * 0.5, s.y * 0.27)
	]), Color(0.45, 0.12, 0.10, 0.85))

func _draw_history_hall(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.12, 0.11, 0.11) * lm)
	draw_rect(Rect2(0, s.y * 0.76, s.x, s.y * 0.24), Color(0.08, 0.07, 0.07) * lm)
	# 展柜与相框（毕业照墙）
	for i in 6:
		var fx := s.x * (0.04 + i * 0.157)
		var fr := Rect2(fx, s.y * 0.16, s.x * 0.13, s.y * 0.24)
		draw_rect(fr, Color(0.22, 0.18, 0.13) * lm)
		draw_rect(fr.grow(-6), Color(0.30, 0.29, 0.26) * lm)
		# 照片里的人（一排小竖条），其中一个是空的
		for k in 7:
			var hx := fr.position.x + 12 + k * (fr.size.x - 24) / 7.0
			var missing := (i == 3 and k == 4)
			if missing:
				continue
			draw_rect(Rect2(hx, fr.position.y + fr.size.y * 0.5, (fr.size.x - 24) / 9.0, fr.size.y * 0.34), Color(0.16, 0.16, 0.18))
			draw_circle(Vector2(hx + (fr.size.x - 24) / 18.0, fr.position.y + fr.size.y * 0.46), 3.5, Color(0.42, 0.40, 0.38))
	# 玻璃展柜
	draw_rect(Rect2(s.x * 0.12, s.y * 0.52, s.x * 0.76, s.y * 0.2), Color(0.35, 0.42, 0.44, 0.14))
	draw_rect(Rect2(s.x * 0.12, s.y * 0.52, s.x * 0.76, s.y * 0.2), Color(0.6, 0.7, 0.72, 0.20), false, 2.0)

func _draw_archive(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.10, 0.09, 0.08) * lm)
	draw_rect(Rect2(0, s.y * 0.78, s.x, s.y * 0.22), Color(0.07, 0.06, 0.06))
	# 密集档案架
	for i in 7:
		var rx := s.x * (0.02 + i * 0.14)
		draw_rect(Rect2(rx, s.y * 0.06, s.x * 0.115, s.y * 0.74), Color(0.16, 0.15, 0.13) * lm)
		for shelf in 7:
			var sy := s.y * (0.08 + shelf * 0.10)
			draw_rect(Rect2(rx + 3, sy, s.x * 0.115 - 6, s.y * 0.085), Color(0.09, 0.08, 0.07))
			var rr := RandomNumberGenerator.new()
			rr.seed = i * 13 + shelf
			for k in 6:
				draw_rect(Rect2(rx + 6 + k * (s.x * 0.115 - 14) / 6.0, sy + 6, (s.x * 0.115 - 16) / 7.0, s.y * 0.07), Color(rr.randf_range(0.28, 0.5), rr.randf_range(0.24, 0.38), rr.randf_range(0.18, 0.28), 0.9) * lm)
	# 应急灯
	draw_rect(Rect2(s.x * 0.46, s.y * 0.02, s.x * 0.08, s.y * 0.03), Color(0.2, 0.7, 0.35, 0.5 + 0.3 * sin(_t * 2.0)))

func _draw_monitor_room(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.07, 0.08) * lm)
	# 监视器墙
	for r in 3:
		for c in 4:
			var m := Rect2(s.x * (0.06 + c * 0.23), s.y * (0.08 + r * 0.25), s.x * 0.2, s.y * 0.2)
			draw_rect(m, Color(0.10, 0.10, 0.11))
			draw_rect(m.grow(-4), Color(0.04, 0.05, 0.06))
			var rr := RandomNumberGenerator.new()
			rr.seed = r * 10 + c + int(_t * 6.0)
			# 雪花或画面
			if (r * 4 + c) % 5 == 0:
				for i in 90:
					draw_rect(Rect2(m.position.x + 6 + rr.randf() * (m.size.x - 12), m.position.y + 6 + rr.randf() * (m.size.y - 12), 2, 2), Color(0.7, 0.72, 0.7, rr.randf() * 0.6))
			else:
				draw_rect(m.grow(-8), Color(0.08, 0.11, 0.12))
				# 走廊剪影
				draw_rect(Rect2(m.position.x + m.size.x * 0.4, m.position.y + m.size.y * 0.45, m.size.x * 0.08, m.size.y * 0.4), Color(0.02, 0.02, 0.02, 0.9))
				draw_line(Vector2(m.position.x + 8, m.position.y + m.size.y * 0.62), Vector2(m.end.x - 8, m.position.y + m.size.y * 0.55), Color(0.3, 0.34, 0.34, 0.5), 1.5)
			# 扫描线
			var scan := fmod(_t * 0.4 + (r * 4 + c) * 0.13, 1.0)
			draw_rect(Rect2(m.position.x + 4, m.position.y + 4 + scan * (m.size.y - 8), m.size.x - 8, 3), Color(0.6, 0.85, 0.8, 0.10))
	draw_rect(Rect2(0, s.y * 0.86, s.x, s.y * 0.14), Color(0.11, 0.11, 0.12) * lm)

func _draw_mirror(s: Vector2, p: Dictionary, lm: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.06, 0.07))
	# 盥洗室镜面
	var m := Rect2(s.x * 0.1, s.y * 0.12, s.x * 0.8, s.y * 0.52)
	draw_rect(m, Color(0.14, 0.17, 0.18))
	draw_rect(m, Color(0.4, 0.45, 0.46, 0.5), false, 3.0)
	# 镜中人影（比你慢半拍）
	var off := sin(_t * 0.8) * 8.0
	var cx := m.position.x + m.size.x * 0.5 + off
	draw_circle(Vector2(cx, m.position.y + m.size.y * 0.38), m.size.y * 0.13, Color(0.10, 0.11, 0.12, 0.9))
	draw_rect(Rect2(cx - m.size.x * 0.07, m.position.y + m.size.y * 0.52, m.size.x * 0.14, m.size.y * 0.45), Color(0.10, 0.11, 0.12, 0.9))
	# 水痕
	for i in 12:
		var wx := m.position.x + 20 + i * (m.size.x - 40) / 12.0
		draw_line(Vector2(wx, m.position.y + 10), Vector2(wx + 6, m.end.y - 10), Color(0.6, 0.7, 0.72, 0.06), 2.0)
	# 洗手台
	draw_rect(Rect2(s.x * 0.08, s.y * 0.66, s.x * 0.84, s.y * 0.08), Color(0.30, 0.31, 0.30) * lm)
	draw_rect(Rect2(0, s.y * 0.74, s.x, s.y * 0.26), Color(0.09, 0.09, 0.10))
