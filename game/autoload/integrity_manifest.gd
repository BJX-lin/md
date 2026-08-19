extends Node
# Integrity

##     python3 tools/gen_integrity.py --write

const MANIFEST := {
	"autoload/config.gd": "334db0f1574be57e747063826f116ee57ff0df849b4306628b74436cd5669b39",
	"autoload/game_state.gd": "d3a6c9e4de3ac8741d5a88fb8de485d74d8694c2ef9834acca4405f2b553375e",
	"autoload/save_system.gd": "975f4fdfd5b04356bd922eebe4b5b6e928b199f5299493d1ac978d38ea41b059",
	"autoload/story_engine.gd": "875a77dea51991da69cd03440bd1fd22e7974e796c22732f1f90eb9811ca302a",
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
