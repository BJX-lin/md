extends Control
class_name BGLayer
## 背景层：优先使用 PNG 背景图，缺图自动回退到代码绘制（bg_painter.gd），不会开天窗。
##
## 资源命名规范（对应《场景图片需求表》的 file_name 列）：
##   res://assets/bg/<file_name>.png
##   例：classroom_evening.png / dorm_307_night.png / broadcast_room.png
##
## 剧本里写的是引擎 scene_id（如 @bg classroom night），
## 由 BG_MAP 映射到资源表的文件名，并支持按变体逐级回退。

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

## scene_id + variant → 候选文件名（按优先级，前面找不到就试后面）
## 与《场景图片需求表》二、三节完全对应
const BG_MAP := {
	"office": {
		"": ["office_day"], "day": ["office_day"], "dusk": ["office_day"],
	},
	"classroom": {
		"": ["classroom_day"],
		"day": ["classroom_day"],
		"dusk": ["classroom_evening", "classroom_day"],
		"night": ["classroom_evening"],
		"dark": ["classroom_evening"],
		"blood": ["classroom_evening"],
	},
	"hallway": {
		"": ["hallway_day"],
		"day": ["hallway_day"],
		"dusk": ["hallway_night", "hallway_day"],
		"night": ["hallway_night"],
		"dark": ["hallway_night"],
	},
	"library": {
		"": ["library_day"],
		"day": ["library_day"],
		"dusk": ["library_dim", "library_day"],
		"night": ["library_dim"], "dark": ["library_dim"],
	},
	"dorm": {
		"": ["dorm_307_day"],
		"day": ["dorm_307_day"],
		"night": ["dorm_307_night"],
		"dark": ["dorm_307_night"],
		"blood": ["dorm_307_night"],
	},
	"dorm_door": {
		"": ["dorm_corridor_night"],
		"night": ["dorm_corridor_night"],
		"dark": ["dorm_corridor_night"],
	},
	"duty_room": {
		"": ["duty_room"], "day": ["duty_room"], "night": ["duty_room"],
	},
	"oldbuilding_out": {
		"": ["old_building_gate_rain"],
		"rain": ["old_building_gate_rain"],
		"dusk": ["old_building_gate_rain"],
		"night": ["old_building_gate_rain"],
	},
	"oldbuilding_stair": {
		"": ["old_building_stairs"],
		"dark": ["old_building_stairs"], "night": ["old_building_stairs"],
	},
	"broadcast_door": {
		"": ["broadcast_door"],
		"dark": ["broadcast_door"], "night": ["broadcast_door"],
	},
	"broadcast_room": {
		"": ["broadcast_room"],
		"dark": ["broadcast_room"],
		"fire": ["broadcast_room_fireedge", "broadcast_room"],
	},
	"history_hall": {
		"": ["school_history_hall"],
		"dusk": ["school_history_hall"], "dark": ["school_history_hall"],
	},
	"archive": {
		"": ["archive_inner_door"], "dark": ["archive_inner_door"],
	},
	"monitor_room": {
		"": ["monitor_room"], "dark": ["monitor_room"],
	},
	"schoolyard": {
		"": ["campus_rain"],
		"rain": ["campus_rain"], "night": ["campus_rain"],
		"day": ["title_school", "campus_rain"],
		"dusk": ["title_school", "campus_rain"],
	},
	"mirror": {
		"": ["dorm_307_night"], "dark": ["dorm_307_night"], "day": ["dorm_307_day"],
	},
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
		return null
	var candidates: Array = []
	if BG_MAP.has(id):
		var table: Dictionary = BG_MAP[id]
		if table.has(v):
			candidates.append_array(table[v])
		if table.has("") and v != "":
			candidates.append_array(table[""])
		# 兜底：该场景下所有登记过的文件
		for k in table:
			candidates.append_array(table[k])
	# 直接按 scene_id 命名的图也认
	candidates.append(id + ("_" + v if v != "" else ""))
	candidates.append(id)
	for name in candidates:
		var p := "%s/%s.png" % [BG_ROOT, String(name)]
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
	var tw := float(_tex.get_width())
	var th := float(_tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	# cover 铺满
	var scale := maxf(s.x / tw, s.y / th)
	var dw := tw * scale
	var dh := th * scale
	var pos := Vector2((s.x - dw) * 0.5, (s.y - dh) * 0.5)
	var lm := 1.0 - flicker * 0.55
	# 变体调色：没有专门的变体图时，用色调模拟昼夜/血/火
	var tint := Color(lm, lm, lm, 1.0)
	match variant:
		"night", "dark":
			tint = Color(lm * 0.62, lm * 0.66, lm * 0.78, 1.0)
		"dusk":
			tint = Color(lm * 0.92, lm * 0.78, lm * 0.68, 1.0)
		"rain":
			tint = Color(lm * 0.74, lm * 0.80, lm * 0.88, 1.0)
		"blood":
			tint = Color(lm * 1.0, lm * 0.62, lm * 0.60, 1.0)
		"fire":
			tint = Color(lm * 1.0, lm * 0.74, lm * 0.52, 1.0)
	draw_texture_rect(_tex, Rect2(pos, Vector2(dw, dh)), false, tint)

	# fg_rain_heavy：雨层
	if wet > 0.01 or variant == "rain":
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in 110:
			var sp := 1.0 + rng.randf() * 2.0
			var x := fmod(rng.randf() * s.x + _t * 40.0 * sp, s.x)
			var y := fmod(rng.randf() * s.y + _t * 900.0 * sp, s.y)
			draw_line(Vector2(x, y), Vector2(x - 5, y + 26 * sp),
				Color(0.75, 0.82, 0.88, 0.15), 1.2)

	# 血污层
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
