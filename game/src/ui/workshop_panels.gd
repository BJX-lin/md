extends RefCounted
class_name WorkshopPanels
## 创意工坊界面：工程列表 / 可视化编辑器 / 校验 / 导入导出。
##
## 设计原则：玩家不需要懂 .avg 语法。
## 每一屏演出 = 一张卡片，背景/音乐/立绘用下拉选，台词用输入框，
## 选项用"文本 + 跳到第几幕"。编译成 .avg 的事情交给 Workshop.compile()。

const TOUCH_MIN := 48
const MP = preload("res://src/ui/menu_panels.gd")

# ---------------------------------------------------------------- 可选项
## 下拉里给玩家看的选项。刻意只放常用的，避免选择瘫痪。
const BG_CHOICES := [
	["classroom", "教室"], ["hallway", "走廊"], ["dorm", "宿舍"],
	["library", "图书馆"], ["office", "办公室"], ["washroom", "水房"],
	["stairwell", "楼梯间"], ["rooftop", "天台"], ["canteen", "食堂"],
	["schoolyard", "操场"], ["duty_room", "值班室"], ["oldbuilding_out", "旧楼外"],
	["broadcast_room", "广播室"], ["monitor_room", "监控室"], ["infirmary", "医务室"],
]
const VAR_CHOICES := [
	["", "默认"], ["day", "白天"], ["dusk", "黄昏"],
	["night", "夜晚"], ["dark", "深夜"], ["rain", "雨天"],
]
const BGM_CHOICES := [
	["", "不变"], ["bgm_unease", "不安"], ["bgm_horror", "惊悚"],
	["bgm_investigate", "调查"], ["bgm_truth", "真相"],
	["bgm_day_class", "日常"], ["bgm_chase", "追逐"], ["bgm_final", "终章"],
]
const ACTOR_CHOICES := [
	["", "无人"], ["zhouxu", "周叙"], ["liangye", "梁野"],
	["xuqing", "许清"], ["shenhe", "沈禾"], ["oldqin", "老秦"],
	["liheng", "李恒"], ["linzhou", "林昼"],
]
const EMO_CHOICES := [
	["normal", "平常"], ["neutral", "中性"], ["frown", "皱眉"],
	["serious", "严肃"], ["tired", "疲惫"], ["nervous", "紧张"],
	["scared", "害怕"], ["sad", "悲伤"], ["hollow", "空洞"],
	["stare", "凝视"], ["faintsmile", "浅笑"],
]
const POS_CHOICES := [["left", "左"], ["center", "中"], ["right", "右"]]

# ---------------------------------------------------------------- 入口
static func workshop_panel() -> Control:
	var pair := MP._shell("创意工坊")
	var root: Control = pair[0]
	var v := MP._scroll(pair[1])

	# 本体被改过就整体停用——这是硬边界，不给任何绕过入口。
	if ContentPolicy.is_tampered():
		v.add_child(_tamper_card())
		return root

	var intro := Label.new()
	intro.text = "用可视化编辑器设计你自己的剧情，导出配置分享给别人，也可以导入别人的作品。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 23)
	intro.add_theme_color_override("font_color", Color(0.78, 0.77, 0.73))
	v.add_child(intro)

	v.add_child(_rules_card())

	# —— 操作行
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(_btn("新建剧本", func():
		var p := Workshop.new_project()
		p["scenes"] = [Workshop.new_scene("开场")]
		Workshop.save_project(p)
		root.add_child(editor_panel(p["id"]))
	))
	row.add_child(_btn("导入配置", func(): root.add_child(import_panel())))

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.4, 0.38, 0.34, 0.4)
	v.add_child(sep)

	# —— 工程列表
	Workshop.refresh_list()
	if Workshop.projects.is_empty():
		var empty := Label.new()
		empty.text = "还没有作品。点「新建剧本」开始，或导入别人的配置。"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 22)
		empty.add_theme_color_override("font_color", Color(0.60, 0.58, 0.55))
		v.add_child(empty)
	else:
		for it in Workshop.projects:
			v.add_child(_project_card(root, it))
	return root

# ---------------------------------------------------------------- 卡片
static func _tamper_card() -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.06, 0.05, 0.95)
	sb.border_color = Color(0.80, 0.30, 0.26, 0.9)
	sb.set_border_width_all(2)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	box.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = ContentPolicy.tamper_notice()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(0.96, 0.80, 0.76))
	box.add_child(l)
	return box

static func _rules_card() -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 0.92)
	sb.border_color = Color(0.52, 0.46, 0.38, 0.6)
	sb.set_border_width_all(1)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	box.add_theme_stylebox_override("panel", sb)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	box.add_child(cv)
	var h := Label.new()
	h.text = "内容规则（内置于游戏本体，无法修改）"
	h.add_theme_font_size_override("font_size", 22)
	h.add_theme_color_override("font_color", Color(0.86, 0.74, 0.52))
	cv.add_child(h)
	for r in ContentPolicy.rules_summary():
		var l := Label.new()
		l.text = "· " + String(r)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(0.68, 0.67, 0.64))
		cv.add_child(l)
	return box

static func _project_card(root: Control, it: Dictionary) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.12, 0.94)
	sb.border_color = Color(0.45, 0.42, 0.38, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	box.add_theme_stylebox_override("panel", sb)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	box.add_child(cv)

	var t := Label.new()
	t.text = String(it["title"])
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76))
	cv.add_child(t)

	var meta := Label.new()
	meta.text = "%d 幕　%s%s" % [
		int(it["scenes"]),
		("作者 " + String(it["author"]) + "　") if String(it["author"]) != "" else "",
		String(it["updated"])]
	meta.add_theme_font_size_override("font_size", 20)
	meta.add_theme_color_override("font_color", Color(0.60, 0.58, 0.55))
	cv.add_child(meta)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	cv.add_child(row)
	var pid := String(it["id"])
	row.add_child(_btn("编辑", func(): root.add_child(editor_panel(pid)), 110))
	row.add_child(_btn("校验", func():
		root.add_child(validate_panel(pid)), 110))
	row.add_child(_btn("导出", func(): root.add_child(export_panel(pid)), 110))
	row.add_child(_btn("删除", func():
		Workshop.delete_project(pid)
		root.queue_free()
	, 110))
	return box

# ---------------------------------------------------------------- 编辑器
static func editor_panel(pid: String) -> Control:
	var proj := Workshop.load_project(pid)
	var pair := MP._shell("编辑：%s" % String(proj.get("title", "")))
	var root: Control = pair[0]
	var v := MP._scroll(pair[1])

	# —— 元信息
	v.add_child(_text_row("标题", String(proj.get("title", "")), func(s):
		proj["title"] = s))
	v.add_child(_text_row("作者", String(proj.get("author", "")), func(s):
		proj["author"] = s))

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.4, 0.38, 0.34, 0.4)
	v.add_child(sep)

	# —— 场景列表容器（重建式刷新，逻辑简单不易出错）
	var host := VBoxContainer.new()
	host.add_theme_constant_override("separation", 14)
	v.add_child(host)

	var rebuild := func(): pass
	rebuild = func():
		for c in host.get_children():
			c.queue_free()
		var scenes: Array = proj.get("scenes", [])
		for i in scenes.size():
			host.add_child(_scene_card(proj, i, rebuild))

	rebuild.call()

	var addrow := HBoxContainer.new()
	addrow.add_theme_constant_override("separation", 12)
	v.add_child(addrow)
	addrow.add_child(_btn("＋ 添加一幕", func():
		(proj["scenes"] as Array).append(Workshop.new_scene("第%d幕" % ((proj["scenes"] as Array).size() + 1)))
		rebuild.call()
	))
	addrow.add_child(_btn("保存", func():
		Workshop.save_project(proj)
		AudioDirector.play_sfx("sfx_write", 0.8)
	))
	addrow.add_child(_btn("保存并校验", func():
		Workshop.save_project(proj)
		root.add_child(validate_panel(String(proj["id"])))
	))
	return root

static func _scene_card(proj: Dictionary, idx: int, rebuild: Callable) -> Control:
	var scenes: Array = proj["scenes"]
	var sc: Dictionary = scenes[idx]

	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.11, 0.94)
	sb.border_color = Color(0.48, 0.44, 0.40, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	box.add_theme_stylebox_override("panel", sb)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 9)
	box.add_child(cv)

	# 标题行
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	cv.add_child(head)
	var num := Label.new()
	num.text = "第 %d 幕" % (idx + 1)
	num.add_theme_font_size_override("font_size", 24)
	num.add_theme_color_override("font_color", Color(0.86, 0.74, 0.52))
	num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(num)
	if idx > 0:
		head.add_child(_btn("↑", func():
			var t = scenes[idx - 1]; scenes[idx - 1] = scenes[idx]; scenes[idx] = t
			rebuild.call()
		, 56))
	if idx < scenes.size() - 1:
		head.add_child(_btn("↓", func():
			var t = scenes[idx + 1]; scenes[idx + 1] = scenes[idx]; scenes[idx] = t
			rebuild.call()
		, 56))
	head.add_child(_btn("✕", func():
		scenes.remove_at(idx)
		rebuild.call()
	, 56))

	cv.add_child(_text_row("场景名", String(sc.get("name", "")), func(s): sc["name"] = s))
	cv.add_child(_pick_row("背景", BG_CHOICES, String(sc.get("bg", "classroom")),
		func(k): sc["bg"] = k))
	cv.add_child(_pick_row("时段", VAR_CHOICES, String(sc.get("bg_variant", "")),
		func(k): sc["bg_variant"] = k))
	cv.add_child(_pick_row("音乐", BGM_CHOICES, String(sc.get("bgm", "")),
		func(k): sc["bgm"] = k))
	cv.add_child(_pick_row("出场角色", ACTOR_CHOICES, String(sc.get("actor", "")),
		func(k): sc["actor"] = k))
	cv.add_child(_pick_row("表情", EMO_CHOICES, String(sc.get("actor_emo", "normal")),
		func(k): sc["actor_emo"] = k))
	cv.add_child(_pick_row("站位", POS_CHOICES, String(sc.get("actor_pos", "center")),
		func(k): sc["actor_pos"] = k))

	# —— 台词
	var lh := Label.new()
	lh.text = "台词"
	lh.add_theme_font_size_override("font_size", 21)
	lh.add_theme_color_override("font_color", Color(0.72, 0.70, 0.66))
	cv.add_child(lh)
	var lines: Array = sc.get("lines", [])
	for li in lines.size():
		var ld: Dictionary = lines[li]
		var lr := HBoxContainer.new()
		lr.add_theme_constant_override("separation", 8)
		cv.add_child(lr)
		var who := LineEdit.new()
		who.text = String(ld.get("who", ""))
		who.placeholder_text = "说话人(留空=旁白)"
		who.custom_minimum_size = Vector2(200, TOUCH_MIN)
		who.text_changed.connect(func(s): ld["who"] = s)
		lr.add_child(who)
		var tx := LineEdit.new()
		tx.text = String(ld.get("text", ""))
		tx.placeholder_text = "台词内容"
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tx.custom_minimum_size.y = TOUCH_MIN
		tx.text_changed.connect(func(s): ld["text"] = s)
		lr.add_child(tx)
		lr.add_child(_btn("✕", func():
			lines.remove_at(li)
			rebuild.call()
		, 56))
	cv.add_child(_btn("＋ 添加台词", func():
		lines.append({"who": "", "text": ""})
		sc["lines"] = lines
		rebuild.call()
	))

	# —— 选项
	var ch := Label.new()
	ch.text = "选项（留空则顺序播放到下一幕）"
	ch.add_theme_font_size_override("font_size", 21)
	ch.add_theme_color_override("font_color", Color(0.72, 0.70, 0.66))
	cv.add_child(ch)
	var chs: Array = sc.get("choices", [])
	for ci in chs.size():
		var cd: Dictionary = chs[ci]
		var cr := HBoxContainer.new()
		cr.add_theme_constant_override("separation", 8)
		cv.add_child(cr)
		var ct := LineEdit.new()
		ct.text = String(cd.get("text", ""))
		ct.placeholder_text = "选项文字"
		ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ct.custom_minimum_size.y = TOUCH_MIN
		ct.text_changed.connect(func(s): cd["text"] = s)
		cr.add_child(ct)
		# 跳转目标用"第几幕"，玩家不用记节点 id
		var tgt := OptionButton.new()
		tgt.custom_minimum_size = Vector2(150, TOUCH_MIN)
		for si in scenes.size():
			tgt.add_item("到第%d幕" % (si + 1), si)
		var cur_goto := String(cd.get("goto", ""))
		for si in scenes.size():
			if cur_goto == "%s_s%d" % [String(proj.get("id", "wk")), si]:
				tgt.select(si)
		tgt.item_selected.connect(func(si):
			cd["goto"] = "%s_s%d" % [String(proj.get("id", "wk")), si])
		cr.add_child(tgt)
		cr.add_child(_btn("✕", func():
			chs.remove_at(ci)
			rebuild.call()
		, 56))
	cv.add_child(_btn("＋ 添加选项", func():
		chs.append({"text": "", "goto": ""})
		sc["choices"] = chs
		rebuild.call()
	))
	return box

# ---------------------------------------------------------------- 校验页
## 带多条进度条的校验结果页。
## 进度条不只是装饰：它把"我这个本子完成度如何"变成一眼可见的东西。
static func validate_panel(pid: String) -> Control:
	var proj := Workshop.load_project(pid)
	var res := Workshop.validate(proj)
	var pair := MP._shell("校验：%s" % String(proj.get("title", "")))
	var root: Control = pair[0]
	var v := MP._scroll(pair[1])

	# —— 总体结论
	var head := Label.new()
	if bool(res.get("ok", false)):
		head.text = "✓ 通过　可以导出分享"
		head.add_theme_color_override("font_color", Color(0.58, 0.82, 0.62))
	else:
		head.text = "✗ 未通过　请修正下列问题"
		head.add_theme_color_override("font_color", Color(0.92, 0.48, 0.44))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 30)
	v.add_child(head)

	# —— 进度条组
	var scenes := int(res.get("scenes", 0))
	var chars := int(res.get("chars", 0))
	var lines_total := 0
	var choices_total := 0
	var with_actor := 0
	for sc in proj.get("scenes", []):
		var d: Dictionary = sc
		lines_total += (d.get("lines", []) as Array).size()
		choices_total += (d.get("choices", []) as Array).size()
		if String(d.get("actor", "")) != "":
			with_actor += 1

	v.add_child(_bar("场景数", scenes, ContentPolicy.MAX_NODES, "%d / %d 幕"))
	v.add_child(_bar("总字数", chars, ContentPolicy.MAX_TOTAL_CHARS, "%d / %d 字"))
	v.add_child(_bar("台词量", lines_total, maxi(1, scenes * 6), "%d 句（建议每幕 6 句）"))
	v.add_child(_bar("分支密度", choices_total, maxi(1, scenes), "%d 个选项"))
	v.add_child(_bar("立绘覆盖", with_actor, maxi(1, scenes), "%d / %d 幕有角色出场"))

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.4, 0.38, 0.34, 0.4)
	v.add_child(sep)

	# —— 问题清单
	for e in res.get("errors", []):
		v.add_child(_issue("✗ " + String(e), Color(0.92, 0.48, 0.44)))
	for w in res.get("warns", []):
		v.add_child(_issue("! " + String(w), Color(0.86, 0.72, 0.40)))
	if (res.get("errors", []) as Array).is_empty() \
			and (res.get("warns", []) as Array).is_empty():
		v.add_child(_issue("没有发现问题。", Color(0.62, 0.72, 0.66)))

	# 命中的违规词单独列出，作者才知道改哪里
	var pol: Dictionary = res.get("policy", {})
	var hits: Array = pol.get("hits", [])
	if not hits.is_empty():
		var hl := Label.new()
		hl.text = "命中的违规词：" + ", ".join(PackedStringArray(hits))
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hl.add_theme_font_size_override("font_size", 21)
		hl.add_theme_color_override("font_color", Color(0.90, 0.60, 0.56))
		v.add_child(hl)
	return root

static func _bar(title: String, value: int, vmax: int, fmt: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = title
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", Color(0.78, 0.76, 0.72))
	row.add_child(l)
	var n := Label.new()
	n.text = fmt % [value, vmax] if fmt.count("%d") > 1 else fmt % value
	n.add_theme_font_size_override("font_size", 20)
	n.add_theme_color_override("font_color", Color(0.62, 0.70, 0.78))
	row.add_child(n)

	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = maxi(1, vmax)
	pb.value = mini(value, vmax)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 14)
	var ratio := float(value) / float(maxi(1, vmax))
	var fill := StyleBoxFlat.new()
	# 超过 90% 转红，提示接近上限
	fill.bg_color = Color(0.55, 0.72, 0.60) if ratio < 0.9 else Color(0.85, 0.45, 0.40)
	fill.set_corner_radius_all(3)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.16, 0.16, 0.19)
	bgs.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("fill", fill)
	pb.add_theme_stylebox_override("background", bgs)
	box.add_child(pb)
	return box

static func _issue(text: String, col: Color) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", col)
	return l

# ---------------------------------------------------------------- 导入导出
static func export_panel(pid: String) -> Control:
	var proj := Workshop.load_project(pid)
	var txt := Workshop.export_text(proj)
	var pair := MP._shell("导出：%s" % String(proj.get("title", "")))
	var root: Control = pair[0]
	var v := MP._scroll(pair[1])

	if txt == "":
		v.add_child(_issue("✗ 内容未通过校验，无法导出。请先在「校验」页修正问题。",
			Color(0.92, 0.48, 0.44)))
		v.add_child(_btn("去校验", func(): root.add_child(validate_panel(pid))))
		return root

	var tip := Label.new()
	tip.text = "下面是你的作品配置。复制后可以发给别人，对方用「导入配置」即可游玩。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 22)
	tip.add_theme_color_override("font_color", Color(0.78, 0.77, 0.73))
	v.add_child(tip)

	var te := TextEdit.new()
	te.text = txt
	te.editable = false
	te.custom_minimum_size = Vector2(0, 300)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(te)

	var done := Label.new()
	done.add_theme_font_size_override("font_size", 21)
	done.add_theme_color_override("font_color", Color(0.58, 0.78, 0.62))
	done.modulate.a = 0.0

	v.add_child(_btn("复制到剪贴板", func():
		DisplayServer.clipboard_set(txt)
		AudioDirector.play_sfx("sfx_click", 0.8)
		done.text = "已复制（%d 字符）" % txt.length()
		done.modulate.a = 1.0
		if done.is_inside_tree():
			done.create_tween().tween_property(done, "modulate:a", 0.0, 2.2).set_delay(1.2)
	))
	v.add_child(done)
	return root

static func import_panel() -> Control:
	var pair := MP._shell("导入配置")
	var root: Control = pair[0]
	var v := MP._scroll(pair[1])

	var tip := Label.new()
	tip.text = "把别人给你的配置粘贴到下面，然后点「导入」。\n导入的内容同样会经过内容规则审查。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 22)
	tip.add_theme_color_override("font_color", Color(0.78, 0.77, 0.73))
	v.add_child(tip)

	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 280)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.placeholder_text = "在此粘贴工坊配置…"
	v.add_child(te)

	var msg := Label.new()
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 22)
	v.add_child(msg)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(_btn("从剪贴板粘贴", func():
		te.text = DisplayServer.clipboard_get()))
	row.add_child(_btn("导入", func():
		var r := Workshop.import_text(te.text)
		if bool(r.get("ok", false)):
			var p: Dictionary = r["project"]
			Workshop.save_project(p)
			msg.text = "✓ 已导入《%s》，回到工坊列表即可看到。" % String(p.get("title", ""))
			msg.add_theme_color_override("font_color", Color(0.58, 0.82, 0.62))
			AudioDirector.play_sfx("sfx_write", 0.8)
		else:
			msg.text = "✗ " + String(r.get("reason", "导入失败"))
			msg.add_theme_color_override("font_color", Color(0.92, 0.48, 0.44))
	))
	return root

# ---------------------------------------------------------------- 控件
static func _btn(text: String, cb: Callable, w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, TOUCH_MIN)
	b.pressed.connect(func():
		AudioDirector.play_sfx("sfx_click", 0.6)
		cb.call())
	return b

static func _text_row(title: String, value: String, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(120, TOUCH_MIN)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 21)
	h.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size.y = TOUCH_MIN
	e.text_changed.connect(func(s): cb.call(s))
	h.add_child(e)
	return h

static func _pick_row(title: String, options: Array, current: String, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(120, TOUCH_MIN)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 21)
	h.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size.y = TOUCH_MIN
	for i in options.size():
		var pair: Array = options[i]
		ob.add_item(String(pair[1]), i)
		if String(pair[0]) == current:
			ob.select(i)
	ob.item_selected.connect(func(i):
		cb.call(String((options[i] as Array)[0])))
	h.add_child(ob)
	return h
