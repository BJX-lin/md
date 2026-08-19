extends Node
## 创意工坊：玩家自主设计剧情内容。
##
## ============================ 边界 ============================
##
## 工坊内容跑在**沙箱**里：
##   * 只允许 ContentPolicy.ALLOWED_CMDS 白名单里的指令
##   * 不能用 @death / @settle / @ending —— 玩家内容不应污染主线
##     的角色生死与结局判定
##   * 数值改动只落在工坊自己的临时状态上，不写主线存档
##
## 所有内容在**导入时**和**导出时**都过一遍 ContentPolicy.review()。
## 双向都查是有意的：导入挡住别人塞给你的东西，
## 导出挡住你把违规内容传出去。
##
## ============================ 存储 ============================
##
## 工程存在 user://workshop/<id>.json，导出是同一份 JSON 加一层
## 校验头。用 JSON 而不是自定义二进制，是为了让玩家能看懂、能手改、
## 能在群里贴出来——工坊的价值就在于流通。

signal project_list_changed()
signal validation_done(result: Dictionary)

const DIR := "user://workshop"
const EXPORT_MAGIC := "AESWORKSHOP"
const FORMAT_VERSION := 1

## 内容包签名盐。用于导出文件的完整性校验（不是保密，是防损坏/防乱改）。
const PACK_SALT := "AfterEveningStudy::workshop::v1"

var projects: Array = []          # [{id, title, author, updated, nodes:int, chars:int}]
var current: Dictionary = {}      # 当前编辑中的工程

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	refresh_list()

# ---------------------------------------------------------------- 工程模型
## 一个空工程。
##
## scenes 是"可视化设计"的数据源：每个 scene 是一屏演出，
## 编辑器按顺序渲染成节点列表，玩家不需要写 .avg 语法。
func new_project(title := "未命名剧本") -> Dictionary:
	return {
		"format": FORMAT_VERSION,
		"id": "wk_%d" % Time.get_unix_time_from_system(),
		"title": title,
		"author": "",
		"summary": "",
		"updated": Time.get_datetime_string_from_system(false, true),
		"scenes": [],
	}

## 一屏演出的默认结构。
func new_scene(name := "新场景") -> Dictionary:
	return {
		"name": name,
		"bg": "classroom",
		"bg_variant": "day",
		"bgm": "bgm_unease",
		"amb": "",
		"actor": "",
		"actor_emo": "normal",
		"actor_pos": "center",
		"lines": [],          # [{who, text}]
		"choices": [],        # [{text, goto}]
		"next": "",           # 无选项时的下一幕（空=顺序推进）
	}

# ---------------------------------------------------------------- 列表
func refresh_list() -> void:
	projects.clear()
	var d := DirAccess.open(DIR)
	if d == null:
		project_list_changed.emit()
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".json"):
			var p := _read_json(DIR + "/" + f)
			if not p.is_empty():
				projects.append({
					"id": String(p.get("id", f.get_basename())),
					"title": String(p.get("title", "未命名")),
					"author": String(p.get("author", "")),
					"updated": String(p.get("updated", "")),
					"scenes": (p.get("scenes", []) as Array).size(),
					"file": DIR + "/" + f,
				})
		f = d.get_next()
	d.list_dir_end()
	projects.sort_custom(func(a, b): return String(a["updated"]) > String(b["updated"]))
	project_list_changed.emit()

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}

# ---------------------------------------------------------------- 存取
func save_project(p: Dictionary) -> bool:
	if ContentPolicy.is_tampered():
		return false
	p["updated"] = Time.get_datetime_string_from_system(false, true)
	var path := "%s/%s.json" % [DIR, String(p.get("id", "wk_tmp"))]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(p, "\t"))
	f.close()
	refresh_list()
	return true

func load_project(id: String) -> Dictionary:
	return _read_json("%s/%s.json" % [DIR, id])

func delete_project(id: String) -> void:
	DirAccess.remove_absolute("%s/%s.json" % [DIR, id])
	refresh_list()

# ---------------------------------------------------------------- 编译
## 把可视化工程编译成 .avg 文本。
##
## 这一步同时承担"把玩家的图形化编辑翻译成引擎能跑的东西"和
## "把内容摊平成一整段纯文本以便审查"两个职责。
func compile(p: Dictionary) -> String:
	var out := PackedStringArray()
	var scenes: Array = p.get("scenes", [])
	out.append("-- 创意工坊作品：%s" % String(p.get("title", "未命名")))
	if String(p.get("author", "")) != "":
		out.append("-- 作者：%s" % String(p["author"]))
	out.append("")

	for i in scenes.size():
		var sc: Dictionary = scenes[i]
		var nid := _node_id(p, i)
		out.append("== %s" % nid)
		var bgv := String(sc.get("bg_variant", ""))
		var bg_line := "@bg " + String(sc.get("bg", "classroom"))
		if bgv != "":
			bg_line += " " + bgv
		out.append(bg_line)
		if String(sc.get("bgm", "")) != "":
			out.append("@bgm %s" % String(sc["bgm"]))
		if String(sc.get("amb", "")) != "":
			out.append("@amb %s" % String(sc["amb"]))
		out.append("@clearchars")
		if String(sc.get("actor", "")) != "":
			out.append("@show %s %s %s" % [
				String(sc["actor"]),
				String(sc.get("actor_emo", "normal")),
				String(sc.get("actor_pos", "center"))])
		for ln in sc.get("lines", []):
			var who := String((ln as Dictionary).get("who", ""))
			var txt := String((ln as Dictionary).get("text", ""))
			if txt.strip_edges() == "":
				continue
			if who == "":
				out.append("> %s" % txt)
			else:
				out.append("%s：%s" % [who, txt])
		var chs: Array = sc.get("choices", [])
		if chs.is_empty():
			var nxt := String(sc.get("next", ""))
			if nxt != "":
				out.append("@goto %s" % nxt)
			elif i + 1 < scenes.size():
				out.append("@goto %s" % _node_id(p, i + 1))
			else:
				out.append("@return")
		else:
			for c in chs:
				var cd: Dictionary = c
				var tgt := String(cd.get("goto", ""))
				if tgt == "":
					tgt = _node_id(p, mini(i + 1, scenes.size() - 1))
				out.append("* %s -> %s" % [String(cd.get("text", "继续")), tgt])
		out.append("")
	return "\n".join(out)

func _node_id(p: Dictionary, idx: int) -> String:
	return "%s_s%d" % [String(p.get("id", "wk")), idx]

# ---------------------------------------------------------------- 校验
## 全面校验一个工程。返回结构化结果供 UI 逐条展示。
func validate(p: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warns := PackedStringArray()
	var scenes: Array = p.get("scenes", [])

	if ContentPolicy.is_tampered():
		errors.append(ContentPolicy.tamper_reason())
		return {"ok": false, "errors": Array(errors), "warns": [],
			"policy": {}, "chars": 0, "scenes": 0}

	if scenes.is_empty():
		errors.append("还没有任何场景")

	# —— 结构
	var ids := {}
	for i in scenes.size():
		ids[_node_id(p, i)] = true
	for i in scenes.size():
		var sc: Dictionary = scenes[i]
		var label := "第%d幕「%s」" % [i + 1, String(sc.get("name", ""))]
		if (sc.get("lines", []) as Array).is_empty() \
				and (sc.get("choices", []) as Array).is_empty():
			warns.append("%s 是空的" % label)
		for c in sc.get("choices", []):
			var tgt := String((c as Dictionary).get("goto", ""))
			if tgt != "" and not ids.has(tgt):
				errors.append("%s 的选项指向了不存在的场景：%s" % [label, tgt])
		var nx := String(sc.get("next", ""))
		if nx != "" and not ids.has(nx):
			errors.append("%s 的后继场景不存在：%s" % [label, nx])
		# 背景合法性
		var bg := String(sc.get("bg", ""))
		if bg != "" and not BGLayerRef.BG_MAP.has(bg):
			warns.append("%s 使用了未知背景 %s（会回退到默认图）" % [label, bg])

	# —— 内容审查
	var text := compile(p)
	var review: Dictionary = ContentPolicy.review(text, scenes.size())
	if not bool(review.get("ok", false)):
		for r in review.get("reasons", []):
			errors.append("内容规则：%s" % String(r))

	var res := {
		"ok": errors.is_empty(),
		"errors": Array(errors),
		"warns": Array(warns),
		"policy": review,
		"chars": text.length(),
		"scenes": scenes.size(),
	}
	validation_done.emit(res)
	return res

const BGLayerRef = preload("res://src/art/bg_layer.gd")

# ---------------------------------------------------------------- 导入导出
## 导出为可分享的文本（Base64 包裹 + 校验）。
## 返回空串代表被内容规则拒绝。
func export_text(p: Dictionary) -> String:
	var v := validate(p)
	if not bool(v.get("ok", false)):
		return ""
	var body := JSON.stringify(p)
	var sig := (PACK_SALT + body).sha256_text().substr(0, 32)
	var payload := {
		"magic": EXPORT_MAGIC,
		"format": FORMAT_VERSION,
		"policy": ContentPolicy.POLICY_VERSION,
		"sig": sig,
		"data": Marshalls.utf8_to_base64(body),
	}
	return JSON.stringify(payload, "\t")

## 从文本导入。返回 {ok, project, reason}
func import_text(txt: String) -> Dictionary:
	if ContentPolicy.is_tampered():
		return {"ok": false, "reason": ContentPolicy.tamper_reason()}
	var d = JSON.parse_string(txt)
	if not (d is Dictionary):
		return {"ok": false, "reason": "不是有效的工坊文件"}
	var head: Dictionary = d
	if String(head.get("magic", "")) != EXPORT_MAGIC:
		return {"ok": false, "reason": "文件标识不符，可能不是本作的工坊文件"}
	if int(head.get("format", 0)) > FORMAT_VERSION:
		return {"ok": false, "reason": "该文件由更新版本的游戏导出，请先更新游戏"}
	var body := Marshalls.base64_to_utf8(String(head.get("data", "")))
	if body == "":
		return {"ok": false, "reason": "文件内容为空或已损坏"}
	var expect := String(head.get("sig", ""))
	if (PACK_SALT + body).sha256_text().substr(0, 32) != expect:
		return {"ok": false, "reason": "校验失败，文件可能已被修改或传输损坏"}
	var pd = JSON.parse_string(body)
	if not (pd is Dictionary):
		return {"ok": false, "reason": "工程数据损坏"}

	# 导入方也要过一遍内容审查——不能因为"别人签过名"就信任。
	var proj: Dictionary = pd
	var review: Dictionary = ContentPolicy.review(
		compile(proj), (proj.get("scenes", []) as Array).size())
	if not bool(review.get("ok", false)):
		var rs: Array = review.get("reasons", [])
		return {"ok": false,
			"reason": "该内容未通过规则审查：" + ", ".join(PackedStringArray(rs))}

	# 换个 id 落地，避免覆盖同名工程
	proj["id"] = "wk_%d" % Time.get_unix_time_from_system()
	proj["title"] = String(proj.get("title", "导入作品"))
	return {"ok": true, "project": proj, "reason": ""}
