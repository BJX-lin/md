extends Node
## 核心文件完整性清单（自动生成，请勿手改）
##
## 由 tools/gen_integrity.py 生成。改动任何受保护文件后必须重新生成：
##     python3 tools/gen_integrity.py --write
##
## 校验失败的处理是**分级**的，不是一律拒绝启动：
##   * content_policy / workshop 被改 → 停用创意工坊（防止放行违规内容）
##   * 其它文件被改                   → 仅记录并提示，不影响正常游玩
## 这样既守住了"别拿本作分发违规内容"的底线，
## 又不会因为玩家做了个无害的汉化/改色就让游戏打不开。
##
## 能力边界：本地校验挡不住重新编译整个工程的人。
## 目标是把改动成本从"记事本改字符串"提高到"重编工程"，
## 从而消灭成本最低、传播最广的那一类二次分发。

## 受保护文件 → SHA256
const MANIFEST := {
	"autoload/content_policy.gd": "3d8af32a39a4aa8b8713ae3e74c9c564e0c4c6a7707e3f8223a7acac9aea08d4",
	"autoload/workshop.gd": "19b8f93af0854abceb02cc4a40b714f8761cafaf68f0f38c12fd0fdf108610b1",
	"autoload/config.gd": "2bd0a559b8a1efd32b8198cb5995c3a90e6143e2ba13348b9ee643c9d7f8e2f4",
	"autoload/game_state.gd": "89ed906ef530aa744cdefc76260f6e32915b1115dd0562c4a8740e93bdfd69ff",
	"autoload/save_system.gd": "d87cc3b4d064856746f4f5acf31672be90905a0ded6b1ab0eb051e5f5033cb1d",
	"autoload/story_engine.gd": "4ac833ae8903496182bf081fae8fc08e61111aa0a6df3d7b94a25119eb48d997",
}

const SALT := "AfterEveningStudy::integrity::v1"

var _failed: Array[String] = []
var _checked := false

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
		if salted.sha256_text() != String(MANIFEST[rel]):
			_failed.append(String(rel))
	if not _failed.is_empty():
		push_warning("[完整性] 以下核心文件与发行版不一致：%s" % ", ".join(_failed))

func is_intact() -> bool:
	return _failed.is_empty()

func failed_files() -> Array[String]:
	return _failed

## 创意工坊相关文件是否被改。被改则工坊停用。
func workshop_files_intact() -> bool:
	for rel in _failed:
		if rel.contains("content_policy") or rel.contains("workshop"):
			return false
	return true

## 给玩家看的说明。
func notice() -> String:
	if _failed.is_empty():
		return ""
	return ("检测到游戏核心文件与官方发行版不一致：\n%s\n\n" +
		"这可能是因为你下载到了被第三方修改过的版本。\n" +
		"为安全起见，创意工坊等功能可能被停用。\n" +
		"建议从官方发布页重新下载。") % ", ".join(_failed)
