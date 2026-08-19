extends Node
## 贴图缓存与生命周期管理（性能优化核心）。
##
## 背景 1920x1080、立绘 768x1280，全部常驻会吃掉几百 MB 显存，
## 手机上很容易被系统杀掉。这里做三件事：
##   1. 统一走缓存拿贴图，避免同一张图被反复 load
##   2. 按章节预取「接下来要用的」
##   3. 释放「已经过场、后面不会再用的」
##
## 章节→资源的映射由 CHAPTER_BG / CHAPTER_CHARS 描述，
## 与剧本里的 @bg / @show 实际使用情况对应。

const BG_ROOT := "res://assets/bg"
const SPRITE_ROOT := "res://assets/sprites"

## 每章会用到的背景文件名（不含扩展名）
const CHAPTER_BG := {
	0: ["keyvisual_school_rain", "office_day", "gate_clock"],
	1: ["canteen_day", "classroom_day", "classroom_evening",
		"classroom_evening_alllook", "classroom_window_reflection", "desk_carving_shen",
		"dorm_307_day", "dorm_307_deepnight", "dorm_307_night_shadow",
		"dorm_door_gap_shadows", "dorm_door_night", "hallway_day",
		"hallway_dusk", "library_counter", "library_dim", "office_day",
		"prop_broadcast_register", "prop_duty_roster", "prop_library_card",
		"prop_missing_poster", "prop_pencil_case", "title_school", "keyvisual_school_rain",
		"hallway_day_empty", "washroom_faucet"],
	2: ["broadcast_door_lightline", "broadcast_room_dark", "classroom_day",
		"dorm_307_deepnight", "dorm_307_night_shadow", "dorm_corridor_night",
		"duty_room_day", "duty_room_night", "hallway_day",
		"hallway_night_flicker", "infirmary_day", "library_counter",
		"library_stacks_night", "office_day", "old_building_classroom",
		"old_building_gate_rain", "old_building_stairs", "oldbuilding_out_night",
		"old_building_classroom_piled", "prop_torn_page", "schoolyard_night_path",
		"schoolyard_night", "stairwell_night",
		"title_school", "washroom_night", "library_stacks_dark", "stairwell_dark_descend"],
	3: ["classroom_evening", "dorm_307_deepnight", "dorm_307_night_namewall",
		"dorm_307_night_shadow", "dorm_door_night", "hallway_dusk",
		"hallway_night", "mirror_dark", "prop_bus_ticket",
		"prop_duty_roster", "prop_library_card", "prop_missing_poster",
		"prop_phone", "rooftop_night", "rooftop_overlook", "washroom_night_mirror", "rooftop_door_night"],
	4: ["archive_inner_door", "campus_rain", "classroom_day",
		"classroom_evening_alllook", "classroom_morning", "duty_room_keyboard",
		"duty_room_night", "graduation_photo_wall", "hallway_day",
		"history_hall_dusk", "history_hall_gate", "monitor_room", "office_night",
		"prop_logbook", "prop_notice_board", "prop_roster_core",
		"prop_videotapes", "school_history_hall", "dorm_307_deepnight", "office_night_lamp", "classroom_day_rollcall", "monitor_room_wall"],
	5: ["broadcast_door_lightline", "broadcast_room_dark", "broadcast_room_fireedge",
		"broadcast_room_master", "broadcast_room_white", "broadcast_shenhe_back",
		"classroom_evening_alllook", "office_day", "old_building_day",
		"old_building_gate_rain", "old_building_stairs", "oldbuilding_out_night",
		"prop_control_cabinet", "school_history_hall", "schoolgate_night",
		"schoolyard_aerial", "title_school"],
}

## 每章登场的角色（用于预取其立绘目录下的所有差分）
const CHAPTER_CHARS := {
	0: ["linday"],
	1: ["canteen_aunt", "classmate_boy", "classmate_girl", "liangye", "unknown", "xuqing",
		"zhouxu"],
	2: ["classmate", "dorm_keeper", "liangye", "liheng", "oldqin", "shenhe",
		"unknown", "xuqing", "zhouxu"],
	3: ["liangye", "liheng", "oldqin", "shenhe", "unknown", "zhouxu"],
	4: ["liangye", "liheng", "oldqin", "shenhe", "xuqing", "zhouxu"],
	5: ["liangye", "shenhe", "unknown", "xuqing", "zhouxu"],
}

var _cache := {}          # path -> Texture2D
var _hits := 0
var _misses := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## 取贴图：命中缓存直接返回，否则同步 load 并存入缓存
func get_tex(path: String) -> Texture2D:
	if _cache.has(path):
		_hits += 1
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	_misses += 1
	var t := load(path) as Texture2D
	if t != null:
		_cache[path] = t
	return t

func put(path: String, res: Resource) -> void:
	var t := res as Texture2D
	if t != null:
		_cache[path] = t

func has(path: String) -> bool:
	return _cache.has(path)

## 某一章需要预取的全部资源路径
func paths_for_chapter(chapter: int) -> Array[String]:
	var out: Array[String] = []
	for name in CHAPTER_BG.get(chapter, []):
		var p := "%s/%s.png" % [BG_ROOT, String(name)]
		if ResourceLoader.exists(p) and not _cache.has(p):
			out.append(p)
	for cid in CHAPTER_CHARS.get(chapter, []):
		var dir := "%s/%s" % [SPRITE_ROOT, String(cid)]
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			if not f.ends_with(".png"):
				continue
			var sp := "%s/%s" % [dir, f]
			if not _cache.has(sp):
				out.append(sp)
	return out

## 释放「本章及以后都不会再用」的缓存。keep 里的路径强制保留（当前画面正在用）。
func release_stale(chapter: int, keep: Array[String] = []) -> int:
	var needed := {}
	for ch in range(chapter, 6):
		for p in paths_for_chapter_all(ch):
			needed[p] = true
	for p in keep:
		needed[p] = true
	var drop: Array[String] = []
	for p in _cache:
		if not needed.has(p):
			drop.append(p)
	for p in drop:
		_cache.erase(p)
	return drop.size()

## 与 paths_for_chapter 相同，但不跳过已缓存的（用于计算「还需要哪些」）
func paths_for_chapter_all(chapter: int) -> Array[String]:
	var out: Array[String] = []
	for name in CHAPTER_BG.get(chapter, []):
		var p := "%s/%s.png" % [BG_ROOT, String(name)]
		if ResourceLoader.exists(p):
			out.append(p)
	for cid in CHAPTER_CHARS.get(chapter, []):
		var dir := "%s/%s" % [SPRITE_ROOT, String(cid)]
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".png"):
				out.append("%s/%s" % [dir, f])
	return out

func stats() -> Dictionary:
	return {"cached": _cache.size(), "hits": _hits, "misses": _misses}

func clear_all() -> void:
	_cache.clear()
