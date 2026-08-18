extends Control
class_name BGLayer
## 背景层：全部场景组合均已配齐 PNG 专属贴图（check_bg_coverage 校验 0 回退）。
## 找不到贴图时只铺一层纯色底，不再挂任何代码绘制层。
##
## 资源命名规范（对应《场景图片需求表》的 file_name 列）：
##   res://assets/bg/<file_name>.png
##   例：classroom_evening.png / dorm_307_night.png / broadcast_room.png
##
## 剧本里写的是引擎 scene_id（如 @bg classroom night），
## 由 BG_MAP 映射到资源表的文件名，并支持按变体逐级回退。

const BG_ROOT := "res://assets/bg"

var scene_id := "black"
var variant := ""
var flicker := 0.0
var blood_amount := 0.0
var wet := 0.0

var _tex: Texture2D = null
var _t := 0.0
var _cur_key := ""
var _cur_tex_path := ""

## scene_id + variant → 候选文件名（按优先级，前面找不到就试后面）
## 与《场景图片需求表》二、三节完全对应
const BG_MAP := {
	"office": {
		"": ["office_day"], "day": ["office_day"], "dusk": ["office_day"],
		"night": ["office_night", "office_day"], "dark": ["office_night", "office_day"],
	},
	"classroom": {
		"": ["classroom_day", "classroom_evening"],
		"day": ["classroom_day", "classroom_evening"],
		"dusk": ["classroom_evening", "classroom_day"],
		"night": ["classroom_evening_alllook", "classroom_evening"],
		"reflection": ["classroom_window_reflection", "classroom_evening"],
		"rollcall": ["classroom_window_reflection", "classroom_evening"],
		"dark": ["classroom_evening_alllook", "classroom_evening"],
		"blood": ["classroom_evening_missingseat", "classroom_evening"],
	},
	"hallway": {
		"": ["hallway_day", "hallway_night"],
		"day": ["hallway_day", "hallway_night"],
		"dusk": ["hallway_dusk", "hallway_night", "hallway_day"],
		"night": ["hallway_night"],
		"dark": ["hallway_night"],
	},
	"library": {
		"": ["library_day"],
		"day": ["library_day"],
		"night": ["library_stacks_night", "library_dim"],
		"dark": ["library_stacks_night", "library_dim"],
		"dusk": ["library_dim", "library_day"],
		"night": ["library_dim", "library_day"],
		"dark": ["library_dim", "library_day"],
	},
	"dorm": {
		"": ["dorm_307_day", "dorm_307_night"],
		"day": ["dorm_307_day", "dorm_307_night"],
		"night": ["dorm_307_night_shadow", "dorm_307_night"],
		"dark": ["dorm_307_night_shadow", "dorm_307_night"],
		"shadow": ["dorm_307_night_shadow", "dorm_307_night"],
		"names": ["dorm_307_night_namewall", "dorm_307_night"],
		"wet": ["dorm_307_night_wetfloor", "dorm_307_night"],
		"blood": ["dorm_307_night_wetfloor", "dorm_307_night"],
	},
	"dorm_door": {
		"": ["dorm_door_night", "dorm_corridor_night", "hallway_night"],
		"gap": ["dorm_door_gap_shadows", "dorm_door_night"],
		"dark_gap": ["dorm_door_gap_shadows", "dorm_door_night"],
		"night": ["dorm_door_night", "dorm_corridor_night", "hallway_night"],
		"dark": ["dorm_door_night", "dorm_corridor_night", "hallway_night"],
	},
	"duty_room": {
		"": ["duty_room", "office_day"],
		"day": ["duty_room_day", "duty_room", "office_day"],
		"night": ["duty_room", "office_day"],
	},
	"oldbuilding_out": {
		"": ["old_building_gate_rain"],
		"rain": ["old_building_gate_rain"],
		"dusk": ["old_building_gate_rain"],
		"night": ["oldbuilding_out_night", "old_building_gate_rain"],
		"day": ["oldbuilding_out_night", "old_building_gate_rain"],
	},
	"prop": {
		"": ["prop_pencil_case"],
		"pencil_case": ["prop_pencil_case"],
		"videotape": ["prop_videotapes"],
		"ticket": ["prop_bus_ticket"],
		"torn_page": ["prop_torn_page"],
		"library_card": ["prop_library_card"],
		"register": ["prop_broadcast_register"],
		"roster": ["prop_roster_core"],
		"poster": ["prop_missing_poster"],
		"duty": ["prop_duty_roster"],
		"logbook": ["prop_logbook"],
		"notice": ["prop_notice_board"],
	},
	"desk": {
		"": ["desk_carving_shen"], "dark": ["desk_carving_shen"],
		"carving": ["desk_carving_shen"],
	},
	"rooftop": {
		"": ["rooftop_night"], "night": ["rooftop_night"], "dark": ["rooftop_night"],
	},
	"oldbuilding_class": {
		"": ["old_building_classroom"], "dark": ["old_building_classroom"],
		"night": ["old_building_classroom"],
	},
	"photo_wall": {
		"": ["graduation_photo_wall", "school_history_hall"],
		"dark": ["graduation_photo_wall", "school_history_hall"],
		"dusk": ["graduation_photo_wall", "history_hall_dusk"],
	},
	"keyboard": {
		"": ["duty_room_keyboard", "duty_room"],
		"day": ["duty_room_keyboard", "duty_room_day"],
		"night": ["duty_room_keyboard", "duty_room"],
	},
	"oldbuilding_stair": {
		"": ["old_building_stairs", "old_building_corridor"],
		"dark": ["old_building_stairs", "old_building_corridor"],
		"night": ["old_building_stairs", "old_building_corridor"],
		"red": ["old_building_corridor_red", "old_building_corridor"],
		"blood": ["old_building_corridor_red", "old_building_corridor"],
	},
	"broadcast_door": {
		"": ["broadcast_door_lightline", "broadcast_door"],
		"dark": ["broadcast_door_lightline", "broadcast_door"],
		"night": ["broadcast_door_lightline", "broadcast_door"],
		"open": ["broadcast_door_opencrack", "broadcast_door"],
	},
	"broadcast_room": {
		"": ["broadcast_room_emptyseat", "broadcast_room"],
		"shenhe": ["broadcast_shenhe_back", "broadcast_room"],
		"back": ["broadcast_shenhe_back", "broadcast_room"],
		"dark": ["broadcast_room_emptyseat", "broadcast_room"],
		"fire": ["broadcast_room_fireedge", "broadcast_room"],
		"void": ["void_broadcast_edge", "broadcast_room"],
		"blood": ["broadcast_room"],
	},
	"history_hall": {
		"": ["school_history_hall", "library_day"],
		"dusk": ["history_hall_dusk", "school_history_hall", "library_day"],
		"dark": ["school_history_hall", "library_day"],
	},
	"archive": {
		"": ["archive_inner_door", "monitor_room"],
		"dark": ["archive_inner_door", "monitor_room"],
		"snow": ["monitor_room_snow", "monitor_room"],
	},
	"monitor_room": {
		"": ["monitor_room"], "dark": ["monitor_room"],
		"snow": ["monitor_room_snow", "monitor_room"],
	},
	"schoolyard": {
		"": ["campus_rain", "old_building_gate_rain"],
		"rain": ["campus_rain", "old_building_gate_rain"],
		"night": ["schoolyard_night", "campus_rain", "old_building_gate_rain"],
		"day": ["title_school", "campus_rain", "old_building_gate_rain"],
		"keyvisual": ["keyvisual_school_rain", "title_school"],
		"dusk": ["title_school", "campus_rain", "old_building_gate_rain"],
	},
	"dorm_hall": {
		"": ["dorm_corridor_night"], "night": ["dorm_corridor_night"], "dark": ["dorm_corridor_night"], "day": ["hallway_day"],
	},
	"washroom": {
		"": ["washroom_night"], "night": ["washroom_night"], "dark": ["washroom_night"],
	},
	"canteen": {
		"": ["canteen_day"], "day": ["canteen_day"], "dark": ["canteen_day"],
	},
	"mirror": {
		"": ["mirror_dark", "dorm_307_night"], "dark": ["mirror_dark", "dorm_307_night"],
		"day": ["dorm_307_day"],
	},
}

func _init() -> void:
	# 必须在 _init 就铺满：set_scene() 可能在入树前被调用，
	# 若那时 size 仍是 (0,0)，_draw() 会直接 return，表现为整屏全黑。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_right = 0.0
	offset_bottom = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	# 尺寸变化（旋屏 / 窗口缩放）后必须重绘，否则沿用旧的 cover 计算
	resized.connect(queue_redraw)
	queue_redraw()

func set_scene(id: String, v: String = "") -> void:
	scene_id = id
	variant = v
	var key := id + "|" + v
	if key == _cur_key:
		return
	_cur_key = key
	_tex = _find_texture(id, v)
	# 全部场景组合均已有专属贴图（check_bg_coverage 校验 0 回退），
	# 找不到贴图时只留纯色底，不再挂代码绘制层。
	queue_redraw()

## 当前正在显示的贴图路径（供过场加载时标记为「保留，勿释放」）
func current_texture_path() -> String:
	return _cur_tex_path

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
			_cur_tex_path = p
			return ArtCache.get_tex(p)
	return null

func _process(delta: float) -> void:
	# 性能：静止画面不需要每帧重绘。只有存在动态元素
	# （灯管闪烁 / 雨丝 / 血迹动画）时才推进时间轴并请求重绘。
	var animated := flicker > 0.001 or wet > 0.01 or variant == "rain" or blood_amount > 0.001
	if not animated:
		return
	_t += delta
	if _tex != null:
		queue_redraw()

func _draw() -> void:
	var s := size
	# 入树早期 size 可能还是 0，此时先用父节点/视口尺寸兜底，避免整屏全黑
	if s.x <= 1.0 or s.y <= 1.0:
		var p := get_parent_control()
		if p != null and p.size.x > 1.0:
			s = p.size
		else:
			s = get_viewport_rect().size
	if _tex == null:
		# black / white 等纯色场景，或极端缺图情况：铺纯色，避免空白
		draw_rect(Rect2(Vector2.ZERO, s),
			Color(0.93, 0.93, 0.95) if scene_id == "white" else Color(0.02, 0.02, 0.03), true)
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
