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

# ---------------------------------------------------------------- 存档完整性
## 存档签名。
##
## 目的不是「防止玩家改档」——单机游戏没必要跟玩家为敌，改了也只影响自己。
## 真正要挡的是：改档后解锁本该靠通关拿到的真结局 / 全线索图鉴，
## 然后拿着残缺的体验去评价作品，或散播「这游戏结局有 bug」。
##
## 因此策略是「检测并提示」而非「拒绝加载」：
## 签名不符时照常读档，但标记 tampered，结局判定与图鉴解锁走保守分支。
const SAVE_SALT := "AfterEveningStudy::2015-05-17::42"

func _sign(payload: Dictionary) -> String:
	var d := payload.duplicate(true)
	d.erase("_sig")
	# 键排序后再序列化，保证同一份数据签名稳定
	var keys := d.keys()
	keys.sort()
	var ordered := {}
	for k in keys:
		ordered[k] = d[k]
	var raw := JSON.stringify(ordered) + SAVE_SALT
	return raw.sha256_text()

func _verify(d: Dictionary) -> bool:
	if not d.has("_sig"):
		return false
	return String(d["_sig"]) == _sign(d)

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
	var payload := build_payload()
	payload["_sig"] = _sign(payload)
	f.store_string(JSON.stringify(payload, "\t"))
	return true

func autosave() -> void:
	var f := FileAccess.open(autosave_path(), FileAccess.WRITE)
	if f:
		var payload := build_payload()
		payload["_sig"] = _sign(payload)
		f.store_string(JSON.stringify(payload, "\t"))

func read_slot(i: int) -> Dictionary:
	var p := slot_path(i)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		d["_tampered"] = not _verify(d)
		return d
	return {}

func read_autosave() -> Dictionary:
	if not FileAccess.file_exists(autosave_path()):
		return {}
	var f := FileAccess.open(autosave_path(), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		d["_tampered"] = not _verify(d)
		return d
	return {}

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
