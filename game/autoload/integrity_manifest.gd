extends Node
## 核心文件完整性清单（自动生成，请勿手改）
##
## 由 tools/gen_integrity.py 生成。改动任何受保护文件后必须重新生成：
##     python3 tools/gen_integrity.py --write
##
## 校验失败时：仅记录并提示，不影响正常游玩。
## 目的是让玩家在拿到被第三方修改过的包时能知情，
## 而不是拒绝启动——本地校验挡不住重新编译整个工程的人。

## 受保护文件 → SHA256（盐 + 文件内容）
const MANIFEST := {
	"autoload/config.gd": "8d0358c208cb4297bea43e0de22a71ba1e33815644f3584a9c88f166ccb59762",
	"autoload/game_state.gd": "1e9fcfb914de7994c1e860eaf9a52577d41b8843222e6699459b1502f87e0be5",
	"autoload/save_system.gd": "450fdb3f0ca6f68777472d37fbaf5b0159e924795e139a7124a0cf6ca4ac4b5a",
	"autoload/story_engine.gd": "cfaf04e6b52bb3292c4dfaa2325b3af78e5b685049230e9ec87fc5d062bdffa2",
}

const SALT := "The13thPeriod::integrity::v1"

var _failed: Array[String] = []
var _checked := false

## 字节数组的 SHA256 十六进制摘要（PackedByteArray 无 sha256_text）。
static func _sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()

func _ready() -> void:
	verify()

## 逐个校验。结果缓存，只在启动时做一次。
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

## 给玩家看的说明。
func notice() -> String:
	if _failed.is_empty():
		return ""
	return ("检测到游戏核心文件与官方发行版不一致：\n%s\n\n" +
		"这可能是因为你下载到了被第三方修改过的版本。\n" +
		"建议从官方发布页重新下载。") % ", ".join(_failed)
