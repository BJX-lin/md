extends Node
## 存档系统：8 个手动槽 + 1 个自动槽 + 设置 + 跨周目持久数据

const SAVE_DIR := "user://saves"
const SETTINGS_PATH := "user://settings.cfg"
const PERSIST_PATH := "user://persistent.json"
const SLOT_COUNT := 8

var settings := {
	"text_speed": 2,        # 0..3
	"auto_speed": 1.6,      # 自动模式停顿秒
	"vol_master": 1.0,
	"vol_bgm": 0.7,
	"vol_sfx": 0.85,
	"gore": 2,              # 0=关闭 1=温和 2=完整
	"screen_shake": true,
	"flash": true,          # 强闪光（光敏友好开关）
	"skip_seen_only": true,
	"font_scale": 1.0,
}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	load_settings()
	load_persistent()
	AudioDirector.apply_settings(settings)

# ---------------------------------------------------------------- 设置
func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			settings[k] = d[k]

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))
	AudioDirector.apply_settings(settings)

func set_setting(k: String, v) -> void:
	settings[k] = v
	save_settings()

func text_delay() -> float:
	var i := clampi(int(settings.get("text_speed", 2)), 0, 3)
	return Cfg.TEXT_SPEED_PRESET[i]

func gore_level() -> int:
	return int(settings.get("gore", 2))

# ---------------------------------------------------------------- 持久数据
func load_persistent() -> void:
	if not FileAccess.file_exists(PERSIST_PATH):
		return
	var f := FileAccess.open(PERSIST_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			GameState.persistent[k] = d[k]

func save_persistent() -> void:
	var f := FileAccess.open(PERSIST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(GameState.persistent, "\t"))

# ---------------------------------------------------------------- 存档槽
func slot_path(i: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, i]

func autosave_path() -> String:
	return "%s/auto.json" % SAVE_DIR

func build_payload() -> Dictionary:
	var d := GameState.to_dict()
	d["_meta"] = {
		"version": Cfg.VERSION,
		"time": Time.get_datetime_string_from_system(true),
		"chapter": GameState.current_chapter,
		"node": GameState.current_node,
		"truth": GameState.get_num("truth"),
		"sanity": GameState.get_num("sanity"),
		"preview": _preview_text(),
		"playtime": int(GameState.play_seconds),
	}
	return d

func _preview_text() -> String:
	for i in range(GameState.history.size() - 1, -1, -1):
		var h: Dictionary = GameState.history[i]
		if String(h.get("who", "")) != "__choice__":
			var t := String(h.get("text", ""))
			return t.substr(0, mini(28, t.length()))
	return "——"

func save_slot(i: int) -> bool:
	var f := FileAccess.open(slot_path(i), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(build_payload(), "\t"))
	return true

func autosave() -> void:
	var f := FileAccess.open(autosave_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(build_payload(), "\t"))

func read_slot(i: int) -> Dictionary:
	var p := slot_path(i)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func read_autosave() -> Dictionary:
	if not FileAccess.file_exists(autosave_path()):
		return {}
	var f := FileAccess.open(autosave_path(), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func delete_slot(i: int) -> void:
	var p := slot_path(i)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func has_any_save() -> bool:
	if FileAccess.file_exists(autosave_path()):
		return true
	for i in SLOT_COUNT:
		if FileAccess.file_exists(slot_path(i)):
			return true
	return false
