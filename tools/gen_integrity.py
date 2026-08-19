#!/usr/bin/env python3
"""生成核心文件完整性清单，写入 game/autoload/integrity_manifest.gd。

保护对象是"改了会造成实质危害"的文件：
  * content_policy.gd —— 改了就能放行色情等违规内容
  * workshop.gd       —— 改了就能绕过导入审查
  * config.gd         —— 存着联系方式（防止改成骗子的群）
  * game_state.gd     —— 结局判定与数值门槛
  * save_system.gd    —— 存档签名
  * story_engine.gd   —— 剧本解释器

不保护美术/音频：那些被改了顶多是观感问题，不值得为此增加启动开销。

诚实说明能力边界：
  这类本地校验挡不住"重新编译一个改过的游戏"——攻击者可以连校验一起改掉。
  它真正能挡住的是成本最低、传播最广的那一类：解包改几个字符串、
  发个"补丁包/解锁包"。把门槛从记事本提高到重编工程，
  绝大多数违规二次分发就不会发生。

用法：
    python3 tools/gen_integrity.py           # 只看
    python3 tools/gen_integrity.py --write   # 写入清单
"""
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GAME, "autoload", "integrity_manifest.gd")

# 相对 game/ 的路径
PROTECTED = [
    "autoload/content_policy.gd",
    "autoload/workshop.gd",
    "autoload/config.gd",
    "autoload/game_state.gd",
    "autoload/save_system.gd",
    "autoload/story_engine.gd",
]

SALT = "AfterEveningStudy::integrity::v1"

HEADER = '''extends Node
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
'''

FOOTER = '''}

const SALT := "%s"

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
		push_warning("[完整性] 以下核心文件与发行版不一致：%%s" %% ", ".join(_failed))

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
	return ("检测到游戏核心文件与官方发行版不一致：\\n%%s\\n\\n" +
		"这可能是因为你下载到了被第三方修改过的版本。\\n" +
		"为安全起见，创意工坊等功能可能被停用。\\n" +
		"建议从官方发布页重新下载。") %% ", ".join(_failed)
''' % SALT


def digest(path):
    data = open(path, "rb").read()
    return hashlib.sha256(SALT.encode("utf-8") + data).hexdigest()


def main():
    rows = []
    missing = []
    for rel in PROTECTED:
        full = os.path.join(GAME, rel)
        if not os.path.isfile(full):
            missing.append(rel)
            continue
        rows.append((rel, digest(full)))

    if missing:
        print("!! 找不到这些文件：", ", ".join(missing))
        return 1

    print("受保护文件 %d 个：" % len(rows))
    for rel, d in rows:
        print("  %-34s %s" % (rel, d[:16] + "…"))

    if "--write" not in sys.argv:
        print("\n加 --write 生成 autoload/integrity_manifest.gd")
        return 0

    body = "".join('\t"%s": "%s",\n' % (rel, d) for rel, d in rows)
    open(OUT, "w", encoding="utf-8").write(HEADER + body + FOOTER)
    print("\n已写入 %s" % os.path.relpath(OUT, ROOT))
    print("提醒：之后若再改动受保护文件，需要重新运行本脚本。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
