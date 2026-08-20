extends Node
# Integrity

##     python3 tools/gen_integrity.py --write

const MANIFEST := {
	"autoload/config.gd": "f985efc9643c1684348a5197cf8adacb6620d039770074fe03cb5ee3b66f77c4",
	"autoload/game_state.gd": "83c8bf166545754127db2dc58a79b83cbc35fa944f6281e51be129243441aae1",
	"autoload/save_system.gd": "989adf9330832bf7838412f46eb81f68ba1708db3b4816089ad068607cfd23dd",
	"autoload/story_engine.gd": "64b6b9c2b2b72ff6ca9ae4eb07af642491d8d09ea00da0a2132fb33e3a8209bc",
}

const SALT := "The13thPeriod::integrity::v1"

var _failed: Array[String] = []
var _checked := false

static func _sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()

func _ready() -> void:
	verify()

# Cache
func verify() -> void:
	if _checked:
		return
	_checked = true
	_failed.clear()
	for rel in MANIFEST:
		var path := "res://" + String(rel)
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_failed.append(String(rel))
			continue
		var data := f.get_buffer(f.get_length())
		f.close()
		var salted := SALT.to_utf8_buffer()
		salted.append_array(data)
		if _sha256_hex(salted) != String(MANIFEST[rel]):
			_failed.append(String(rel))
	if not _failed.is_empty():
		push_warning("[完整性] 以下核心文件与发行版不一致：%s" % ", ".join(_failed))

func is_intact() -> bool:
	return _failed.is_empty()

func failed_files() -> Array[String]:
	return _failed

func notice() -> String:
	if _failed.is_empty():
		return ""
	return ("检测到游戏核心文件与官方发行版不一致：\n%s\n\n" +
		"这可能是因为你下载到了被第三方修改过的版本。\n" +
		"建议从官方发布页重新下载。") % ", ".join(_failed)
