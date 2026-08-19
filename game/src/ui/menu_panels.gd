extends RefCounted
class_name MenuPanels
## 各类菜单面板：回想 / 线索 / 状态 / 存读档 / 系统设置 / 图鉴

static func _shell(title: String) -> Array:
	## 返回 [root, content_vbox]
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.01, 0.015, 0.90)
	root.add_child(shade)

	# 菜单底纹：夜里的黑板墙。压在遮罩之上、面板之下。
	# 遮罩已经足够暗，这里只是给大片纯黑加一点质感，透明度压得很低。
	# 缺图跳过，回到原来的纯色遮罩。
	var bg_path := "res://assets/ui/menu_bg.png"
	if ResourceLoader.exists(bg_path):
		var btex = load(bg_path)
		if btex is Texture2D:
			var wall := TextureRect.new()
			wall.texture = btex
			wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			wall.stretch_mode = TextureRect.STRETCH_SCALE
			wall.set_anchors_preset(Control.PRESET_FULL_RECT)
			wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wall.modulate = Color(1, 1, 1, 0.32)
			root.add_child(wall)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 60
	frame.offset_right = -60
	frame.offset_top = 40
	frame.offset_bottom = -40
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.98)
	sb.border_color = Color(0.45, 0.42, 0.37, 0.6)
	sb.set_border_width_all(1)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	frame.add_theme_stylebox_override("panel", sb)
	root.add_child(frame)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	frame.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(0.88, 0.74, 0.52))
	head.add_child(t)
	var close := Button.new()
	close.text = "关闭"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func():
		AudioDirector.play_sfx("sfx_click", 0.6)
		root.queue_free()
	)
	head.add_child(close)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.4, 0.38, 0.34, 0.5)
	v.add_child(sep)

	var content := VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	v.add_child(content)
	return [root, content]

static func _scroll(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# 手机端：开启触摸拖拽与惯性，滚动条加宽便于拇指操作
	sc.follow_focus = false
	sc.scroll_deadzone = 12
	parent.add_child(sc)
	var vsb := sc.get_v_scroll_bar()
	if vsb:
		vsb.custom_minimum_size.x = 18
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	sc.add_child(v)
	return v

# ---------------------------------------------------------------- 回想
static func history_panel() -> Control:
	var pair := _shell("回想")
	var root: Control = pair[0]
	var content: Control = pair[1]

	var hist: Array = GameState.history
	var start := maxi(0, hist.size() - 300)

	# 用 ScrollContainer + VBox，并额外挂一个拖拽转发器，
	# 让整块区域都能像手机 App 那样按住拖动（不必精准按住滚动条）
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.scroll_deadzone = 12
	content.add_child(sc)
	var vsb := sc.get_v_scroll_bar()
	if vsb:
		vsb.custom_minimum_size.x = 18

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	sc.add_child(v)

	for i in range(start, hist.size()):
		var h: Dictionary = hist[i]
		var who := String(h.get("who", ""))
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.selection_enabled = false
		# 关键：让子控件不吃掉拖拽事件，否则手指按在文字上无法滑动
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rt.add_theme_font_size_override("normal_font_size", 25)
		rt.add_theme_constant_override("line_separation", 6)
		if who == "__choice__":
			rt.text = "[color=#c98b46]▶ 你的选择：%s[/color]" % String(h.get("text", ""))
		elif who == "":
			rt.text = "[color=#a9a69f]%s[/color]" % String(h.get("text", ""))
		else:
			var nm := String(Cfg.CHARACTERS.get(who, {}).get("name", who))
			var col: Color = Cfg.CHARACTERS.get(who, {}).get("color", Color.WHITE)
			rt.text = "[color=#%s]%s[/color]　%s" % [col.to_html(false), nm, String(h.get("text", ""))]
		v.add_child(rt)

	if hist.is_empty():
		var e := Label.new()
		e.text = "（还没有内容）"
		e.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(e)

	# 底部快捷跳转条：一键回到最新 / 最早，避免长回想里反复拖
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	content.add_child(bar)

	var b_top := Button.new()
	b_top.text = "▲ 最早"
	b_top.focus_mode = Control.FOCUS_NONE
	b_top.add_theme_font_size_override("font_size", 22)
	b_top.pressed.connect(func():
		AudioDirector.play_sfx("sfx_click", 0.5)
		sc.scroll_vertical = 0
	)
	bar.add_child(b_top)

	var b_bottom := Button.new()
	b_bottom.text = "▼ 最新"
	b_bottom.focus_mode = Control.FOCUS_NONE
	b_bottom.add_theme_font_size_override("font_size", 22)
	b_bottom.pressed.connect(func():
		AudioDirector.play_sfx("sfx_click", 0.5)
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
	)
	bar.add_child(b_bottom)

	# 打开时默认停在最新一条
	root.ready.connect(func():
		await root.get_tree().process_frame
		var bar_v := sc.get_v_scroll_bar()
		if bar_v:
			sc.scroll_vertical = int(bar_v.max_value)
	, CONNECT_ONE_SHOT)
	return root

# ---------------------------------------------------------------- 线索
static func clue_panel() -> Control:
	var pair := _shell("线索簿　（%d / %d）" % [GameState.clues.size(), GameState.CLUES.size()])
	var root: Control = pair[0]
	var v := _scroll(pair[1])
	# 已解锁线索
	for cid in GameState.CLUES:
		var info: Dictionary = GameState.CLUES[cid]
		var got := GameState.clues.has(cid)
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.10, 0.11, 0.9) if got else Color(0.07, 0.07, 0.08, 0.7)
		sb.border_color = Color(0.55, 0.42, 0.30, 0.6) if got else Color(0.24, 0.24, 0.24, 0.5)
		sb.set_border_width_all(1)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		p.add_theme_stylebox_override("panel", sb)
		v.add_child(p)
		var vv := VBoxContainer.new()
		p.add_child(vv)
		var t := Label.new()
		t.text = ("【第%d章】%s" % [int(info.get("ch", 1)), String(info.get("name", cid))]) if got else "【？】未获得的线索"
		t.add_theme_font_size_override("font_size", 26)
		t.add_theme_color_override("font_color", Color(0.90, 0.78, 0.55) if got else Color(0.42, 0.42, 0.42))
		vv.add_child(t)
		var d := Label.new()
		d.text = String(info.get("text", "")) if got else "——"
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 23)
		d.add_theme_color_override("font_color", Color(0.78, 0.77, 0.74) if got else Color(0.32, 0.32, 0.32))
		vv.add_child(d)

	# 道具
	var t2 := Label.new()
	t2.text = "—— 随身物品 ——"
	t2.add_theme_font_size_override("font_size", 27)
	t2.add_theme_color_override("font_color", Color(0.80, 0.62, 0.40))
	v.add_child(t2)
	if GameState.inventory.is_empty():
		var e := Label.new()
		e.text = "（空）"
		e.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		v.add_child(e)
	for iid in GameState.inventory:
		var info2: Dictionary = GameState.ITEMS.get(iid, {})
		var l := Label.new()
		l.text = "◆ %s —— %s" % [String(info2.get("name", iid)), String(info2.get("desc", ""))]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(0.84, 0.82, 0.78))
		v.add_child(l)
	return root

# ---------------------------------------------------------------- 状态
static func status_panel() -> Control:
	var pair := _shell("状态")
	var root: Control = pair[0]
	var v := _scroll(pair[1])

	var head := Label.new()
	head.text = "第 %s 章　游玩时长 %d 分钟　周目 %d" % [
		("终" if GameState.current_chapter >= 5 else str(GameState.current_chapter)),
		int(GameState.play_seconds / 60.0),
		int(GameState.persistent.get("cycles", 0)) + 1,
	]
	head.add_theme_font_size_override("font_size", 25)
	head.add_theme_color_override("font_color", Color(0.78, 0.77, 0.72))
	v.add_child(head)

	for key in ["truth", "sanity", "memory_echo", "shenhe_focus"]:
		v.add_child(_bar_row(key))
	var sep := Label.new()
	sep.text = "—— 关系 ——"
	sep.add_theme_color_override("font_color", Color(0.80, 0.62, 0.40))
	v.add_child(sep)
	for key in ["trust_zhouxu", "trust_liangye", "trust_xuqing", "trust_oldqin"]:
		v.add_child(_bar_row(key))
	var sep2 := Label.new()
	sep2.text = "—— 倾向 ——"
	sep2.add_theme_color_override("font_color", Color(0.80, 0.62, 0.40))
	v.add_child(sep2)
	for key in ["route_obedience", "route_investigate", "route_empathy", "route_hostility", "taboo_count"]:
		v.add_child(_bar_row(key))

	# 阈值提示（真相解读）
	var tips := Label.new()
	var truth := GameState.get_num("truth")
	var msg := "你还什么都不确定。"
	for pair2 in Cfg.TH_TRUTH:
		if truth >= int(pair2[0]):
			msg = String(pair2[1])
	tips.text = "认知：" + msg
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.add_theme_font_size_override("font_size", 24)
	tips.add_theme_color_override("font_color", Color(0.70, 0.80, 0.88))
	v.add_child(tips)

	var san := GameState.get_num("sanity")
	var smsg := "叙述稳定，可信。"
	for pair3 in Cfg.TH_SANITY:
		if san <= int(pair3[0]):
			smsg = String(pair3[1])
	var stip := Label.new()
	stip.text = "精神：" + smsg
	stip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stip.add_theme_font_size_override("font_size", 24)
	stip.add_theme_color_override("font_color", Color(0.86, 0.66, 0.52))
	v.add_child(stip)

	# 角色状态
	var sep3 := Label.new()
	sep3.text = "—— 相关的人 ——"
	sep3.add_theme_color_override("font_color", Color(0.80, 0.62, 0.40))
	v.add_child(sep3)
	for row in [
		["梁野", _liangye_desc()], ["周叙", _zhouxu_desc()],
		["许清", _xuqing_desc()], ["沈禾", _shenhe_desc()], ["老秦", _oldqin_desc()],
	]:
		var l := Label.new()
		l.text = "%s：%s" % [String(row[0]), String(row[1])]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 24)
		v.add_child(l)

	if not GameState.deaths.is_empty():
		var dl := Label.new()
		dl.text = "已失去：" + ", ".join(GameState.deaths)
		dl.add_theme_color_override("font_color", Color(0.80, 0.28, 0.24))
		dl.add_theme_font_size_override("font_size", 24)
		v.add_child(dl)
	return root

static func _bar_row(key: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = Cfg.NUM_LABEL.get(key, key)
	l.custom_minimum_size.x = 160
	l.add_theme_font_size_override("font_size", 24)
	h.add_child(l)
	var r: Array = Cfg.NUM_RANGE.get(key, [0, 10])
	var pb := ProgressBar.new()
	pb.min_value = float(r[0])
	pb.max_value = float(r[1])
	pb.value = float(GameState.get_num(key))
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(360, 20)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bgsb := StyleBoxFlat.new()
	bgsb.bg_color = Color(0.12, 0.12, 0.13)
	bgsb.set_corner_radius_all(3)
	var fgsb := StyleBoxFlat.new()
	fgsb.bg_color = Color(0.62, 0.30, 0.26)
	if key == "sanity":
		fgsb.bg_color = Color(0.35, 0.62, 0.55)
	elif key == "truth":
		fgsb.bg_color = Color(0.40, 0.52, 0.70)
	elif key.begins_with("trust"):
		fgsb.bg_color = Color(0.66, 0.56, 0.32)
	fgsb.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bgsb)
	pb.add_theme_stylebox_override("fill", fgsb)
	h.add_child(pb)
	var val := Label.new()
	val.text = str(GameState.get_num(key))
	val.custom_minimum_size.x = 60
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 24)
	h.add_child(val)
	return h

static func _liangye_desc() -> String:
	match GameState.get_state("liangye_final_state_ch3"):
		"anchor_alive": return "还在。他说过不会先走。"
		"rescued_half": return "拉回来了，但他说话有时是过去时。"
		"abandoned": return "你放开了手。"
		"missing": return "没有回来。名字后面写着“已听见”。"
	match GameState.get_state("liangye_state"):
		"missing_marked": return "被点到过名，一整天都在发抖。"
		"half_assimilated": return "回来了。影子却没跟上。"
		"fear_alive": return "怕得要命，但还在你旁边。"
		"ally_shaken": return "肯跟你一起查了。"
		_: return "还算正常。"

static func _zhouxu_desc() -> String:
	match GameState.get_state("zhouxu_final_state_ch3"):
		"confessor_protector": return "他坦白了一部分，并且决定站在你这边。"
		"coercer": return "他只想尽快结束，包括用你结束。"
	match GameState.get_state("zhouxu_state"):
		"guarding": return "他在护着你，也在瞒着你。"
		"hiding": return "他躲着你的问题。"
		"coercing": return "他开始逼你做决定。"
		_: return "班长。做事很稳。"

static func _xuqing_desc() -> String:
	match GameState.get_state("xuqing_state"):
		"revealed": return "已经确认：她五年前就不在名册上了。"
		"destabilized": return "被你说破了——她只是站得太久的人。"
		"observer": return "她不再拦你，只是看着。"
		"suspected": return "她走路没有声音，也从不穿鞋。"
		_: return "班主任。语文老师。"

static func _shenhe_desc() -> String:
	match GameState.get_state("shenhe_state"):
		"seated_core": return "她坐在播音椅上，等你念完。"
		"half_present": return "她已经能被看见一部分了。"
		"calling": return "她在叫名字。有时候叫的是你的。"
		_: return "只是一个只剩半个字的名字。"

static func _oldqin_desc() -> String:
	if GameState.get_flag("flag_oldqin_survived"):
		return "你把他从火里拖出来了。他说这是五年来头一回活着走出那间屋子。"
	match GameState.get_state("oldqin_state"):
		"burned": return "值班室烧了。他没出来。"
		"missing": return "钥匙板上少了一把钥匙，人也少了一个。"
		_: return "守夜的老保安。抽很凶的烟。"

# ---------------------------------------------------------------- 存读档
static func save_panel(allow_save: bool) -> Control:
	var pair := _shell("存档 / 读档")
	var root: Control = pair[0]
	var v := _scroll(pair[1])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)

	for i in SaveSystem.SLOT_COUNT:
		var d := SaveSystem.read_slot(i)
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.10, 0.11, 0.95)
		sb.border_color = Color(0.45, 0.40, 0.35, 0.7)
		sb.set_border_width_all(1)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		p.add_theme_stylebox_override("panel", sb)
		p.custom_minimum_size = Vector2(430, 0)
		grid.add_child(p)
		var vv := VBoxContainer.new()
		p.add_child(vv)
		var meta: Dictionary = d.get("_meta", {})
		var head := Label.new()
		head.text = "槽 %d" % (i + 1)
		head.add_theme_color_override("font_color", Color(0.86, 0.72, 0.48))
		head.add_theme_font_size_override("font_size", 24)
		vv.add_child(head)
		var info := Label.new()
		if d.is_empty():
			info.text = "—— 空 ——"
			info.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		else:
			info.text = "第%s章　真相%d　理智%d\n%s\n%s" % [
				str(meta.get("chapter", 1)), int(meta.get("truth", 0)), int(meta.get("sanity", 0)),
				String(meta.get("preview", "")), String(meta.get("time", "")),
			]
		info.add_theme_font_size_override("font_size", 21)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vv.add_child(info)
		var hb := HBoxContainer.new()
		vv.add_child(hb)
		if allow_save:
			var bs := Button.new()
			bs.text = "保存"
			bs.focus_mode = Control.FOCUS_NONE
			bs.add_theme_font_size_override("font_size", 21)
			bs.pressed.connect(func():
				SaveSystem.save_slot(i)
				AudioDirector.play_sfx("sfx_write", 0.8)
				root.queue_free()
			)
			hb.add_child(bs)
		var bl := Button.new()
		bl.text = "读取"
		bl.disabled = d.is_empty()
		bl.focus_mode = Control.FOCUS_NONE
		bl.add_theme_font_size_override("font_size", 21)
		bl.pressed.connect(func():
			var cb = root.get_meta("on_load", null)
			if cb is Callable:
				cb.call(i)
			root.queue_free()
		)
		hb.add_child(bl)
	return root

# ---------------------------------------------------------------- 系统设置
static func system_panel() -> Control:
	var pair := _shell("设置")
	var root: Control = pair[0]
	var v := _scroll(pair[1])

	v.add_child(_option_row("文本速度", ["很慢", "慢", "正常", "极快"], int(SaveSystem.settings.get("text_speed", 2)), func(i):
		SaveSystem.set_setting("text_speed", i)))
	v.add_child(_option_row("血腥表现", ["关闭", "温和", "完整"], int(SaveSystem.settings.get("gore", 2)), func(i):
		SaveSystem.set_setting("gore", i)))
	v.add_child(_toggle_row("画面震动", bool(SaveSystem.settings.get("screen_shake", true)), func(b):
		SaveSystem.set_setting("screen_shake", b)))
	v.add_child(_toggle_row("强闪光效果", bool(SaveSystem.settings.get("flash", true)), func(b):
		SaveSystem.set_setting("flash", b)))
	v.add_child(_slider_row("总音量", float(SaveSystem.settings.get("vol_master", 1.0)), func(x):
		SaveSystem.set_setting("vol_master", x)))
	v.add_child(_slider_row("音乐/环境", float(SaveSystem.settings.get("vol_bgm", 0.7)), func(x):
		SaveSystem.set_setting("vol_bgm", x)))
	v.add_child(_slider_row("音效", float(SaveSystem.settings.get("vol_sfx", 0.85)), func(x):
		SaveSystem.set_setting("vol_sfx", x)))
	v.add_child(_slider_row("自动播放停顿", float(SaveSystem.settings.get("auto_speed", 1.6)), func(x):
		SaveSystem.set_setting("auto_speed", clampf(x * 3.0, 0.3, 3.0)), float(SaveSystem.settings.get("auto_speed", 1.6)) / 3.0))

	var warn := Label.new()
	warn.text = "提示：本作含惊吓演出、血腥描写与压抑题材。可在上方随时降低表现强度。"
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.add_theme_font_size_override("font_size", 22)
	warn.add_theme_color_override("font_color", Color(0.75, 0.58, 0.42))
	v.add_child(warn)

	var quit := Button.new()
	quit.text = "保存并返回标题"
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(func():
		var cb = root.get_meta("on_quit", null)
		root.queue_free()
		if cb is Callable:
			cb.call()
	)
	v.add_child(quit)
	return root

static func _option_row(title: String, options: Array, current: int, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 220
	h.add_child(l)
	var group_buttons: Array[Button] = []
	for i in options.size():
		var b := Button.new()
		b.text = String(options[i])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.modulate = Color(1.0, 0.72, 0.6) if i == current else Color.WHITE
		group_buttons.append(b)
		b.pressed.connect(func():
			cb.call(i)
			for k in group_buttons.size():
				group_buttons[k].modulate = Color(1.0, 0.72, 0.6) if k == i else Color.WHITE
			AudioDirector.play_sfx("sfx_click", 0.5)
		)
		h.add_child(b)
	return h

static func _toggle_row(title: String, value: bool, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 220
	h.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(b): cb.call(b))
	h.add_child(c)
	return h

static func _slider_row(title: String, value: float, cb: Callable, display := -1.0) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 220
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value if display < 0.0 else display
	s.custom_minimum_size = Vector2(360, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(x): cb.call(x))
	h.add_child(s)
	return h

# ---------------------------------------------------------------- 图鉴
static func gallery_panel() -> Control:
	var pair := _shell("结局与记录")
	var root: Control = pair[0]
	var v := _scroll(pair[1])
	const ENDINGS := [
		["ending_true_release", "真结局《点名停止》", "让沈禾离席，让晚自习真正下课。"],
		["ending_bittersweet_exchange", "遗憾结局《留堂》", "有人得留下来，那就你留。"],
		["ending_manager", "管理者结局《管理员》", "规则不需要被打破，只需要换个人执行。"],
		["ending_destroyer", "毁灭结局《焚校》", "把名单、广播和这栋楼一起烧掉。"],
		["ending_empty_seat", "空席结局《到》", "你答了一声。之后就没人再答了。"],
	]
	var got: Dictionary = GameState.persistent.get("endings", {})
	for e in ENDINGS:
		var id := String(e[0])
		var unlocked := got.has(id)
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.09, 0.10, 0.95) if unlocked else Color(0.07, 0.07, 0.08, 0.8)
		sb.border_color = Color(0.62, 0.32, 0.26, 0.8) if unlocked else Color(0.25, 0.25, 0.25, 0.6)
		sb.set_border_width_all(1)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		p.add_theme_stylebox_override("panel", sb)
		v.add_child(p)
		var vv := VBoxContainer.new()
		p.add_child(vv)
		var t := Label.new()
		t.text = String(e[1]) if unlocked else "？？？"
		t.add_theme_font_size_override("font_size", 27)
		t.add_theme_color_override("font_color", Color(0.90, 0.74, 0.52) if unlocked else Color(0.40, 0.40, 0.40))
		vv.add_child(t)
		var d := Label.new()
		d.text = (String(e[2]) + "　（达成 %d 次）" % int(got.get(id, 0))) if unlocked else "尚未抵达。"
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 23)
		d.add_theme_color_override("font_color", Color(0.78, 0.76, 0.72) if unlocked else Color(0.34, 0.34, 0.34))
		vv.add_child(d)
	var st := Label.new()
	st.text = "已循环 %d 次　线索图鉴 %d / %d　最高真相 %d" % [
		int(GameState.persistent.get("cycles", 0)),
		(GameState.persistent.get("clues_seen", []) as Array).size(),
		GameState.CLUES.size(),
		int(GameState.persistent.get("best_truth", 0)),
	]
	st.add_theme_font_size_override("font_size", 24)
	st.add_theme_color_override("font_color", Color(0.70, 0.78, 0.84))
	v.add_child(st)
	return root
