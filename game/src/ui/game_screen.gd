extends Control
## 游戏主界面：背景 / 立绘 / 文本框 / 选项 / 顶栏 / 各类弹窗

signal finished(ending_id: String)
signal quit_to_title()

const BGLayerS := preload("res://src/art/bg_layer.gd")
const ActorSpriteS := preload("res://src/art/actor_sprite.gd")
const EffectsLayerS := preload("res://src/art/effects_layer.gd")
const SanityFXS := preload("res://src/art/sanity_fx.gd")
const GoreOverlayS := preload("res://src/art/gore_overlay.gd")
const OW := preload("res://src/ui/overlay_widgets.gd")
const MP := preload("res://src/ui/menu_panels.gd")

var world: Control              # 可抖动的容器
var bg: BGLayer
var actor_root: Control
var actors := {}                # who -> {"node":ActorSprite,"pos":String}
var fx: EffectsLayer
var sanity_fx: SanityFX
var gore: GoreOverlay
var time_label: Label
var ui_root: Control

var name_label: Label
var text_label: RichTextLabel
var box: PanelContainer
var choice_box: VBoxContainer
var continue_hint: Label
var top_bar: HBoxContainer
var status_strip: HBoxContainer
var sanity_bar: ProgressBar

var _typing := false
var _full_text := ""
var _shown := 0
var _type_acc := 0.0
var _cur_who := ""
var _auto := false
var _skip := false
var _auto_timer := 0.0
var _blocked := false           # 被弹窗/演出阻塞
var _pending_wait := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_connect_engine()
	set_process(true)
	set_process_unhandled_input(true)

func begin(node_id: String) -> void:
	StoryEngine.start(node_id)

# ---------------------------------------------------------------- 构建界面
func _build() -> void:
	world = Control.new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)

	bg = BGLayerS.new()
	world.add_child(bg)

	actor_root = Control.new()
	actor_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	actor_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(actor_root)

	fx = EffectsLayerS.new()
	fx.shake_offset.connect(func(o):
		var extra := sanity_fx.shudder_offset() if is_instance_valid(sanity_fx) else Vector2.ZERO
		world.position = o + extra
	)
	add_child(fx)

	sanity_fx = SanityFXS.new()
	add_child(sanity_fx)

	gore = GoreOverlayS.new()
	add_child(gore)

	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(ui_root)

	# 点击推进层（在文本框之下）
	var click := Button.new()
	click.set_anchors_preset(Control.PRESET_FULL_RECT)
	click.flat = true
	click.focus_mode = Control.FOCUS_NONE
	click.pressed.connect(_on_screen_tap)
	var empty := StyleBoxEmpty.new()
	click.add_theme_stylebox_override("normal", empty)
	click.add_theme_stylebox_override("hover", empty)
	click.add_theme_stylebox_override("pressed", empty)
	click.add_theme_stylebox_override("focus", empty)
	ui_root.add_child(click)

	_build_top_bar()
	_build_text_box()
	_build_choice_area()

func _build_top_bar() -> void:
	var wrap := PanelContainer.new()
	wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wrap.offset_left = 0
	wrap.offset_right = 0
	wrap.offset_top = 0
	wrap.offset_bottom = 62
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 0.78)
	sb.border_color = Color(0.4, 0.38, 0.34, 0.4)
	sb.border_width_bottom = 1
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	wrap.add_theme_stylebox_override("panel", sb)
	ui_root.add_child(wrap)

	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 6)
	wrap.add_child(top_bar)

	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 19)
	time_label.add_theme_color_override("font_color", Color(0.78, 0.76, 0.68))
	time_label.custom_minimum_size.x = 190
	top_bar.add_child(time_label)
	_refresh_time()
	GameState.time_changed.connect(func(_d, _m): _refresh_time())

	var vsep := ColorRect.new()
	vsep.custom_minimum_size = Vector2(1, 22)
	vsep.color = Color(0.45, 0.43, 0.38, 0.5)
	top_bar.add_child(vsep)

	status_strip = HBoxContainer.new()
	status_strip.add_theme_constant_override("separation", 14)
	status_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(status_strip)
	_refresh_status()
	GameState.var_changed.connect(func(_k, _o, _n): _refresh_status())

	for spec in [
		["自动", "_toggle_auto"], ["快进", "_toggle_skip"], ["回想", "_open_history"],
		["线索", "_open_clues"], ["状态", "_open_status"], ["存档", "_open_saves"], ["≡", "_open_menu"],
	]:
		var b := Button.new()
		b.text = String(spec[0])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		var s2 := StyleBoxFlat.new()
		s2.bg_color = Color(0.13, 0.12, 0.13, 0.85)
		s2.border_color = Color(0.45, 0.42, 0.38, 0.5)
		s2.set_border_width_all(1)
		s2.set_corner_radius_all(3)
		s2.content_margin_left = 12
		s2.content_margin_right = 12
		s2.content_margin_top = 6
		s2.content_margin_bottom = 6
		b.add_theme_stylebox_override("normal", s2)
		b.pressed.connect(Callable(self, String(spec[1])))
		top_bar.add_child(b)
		if spec[0] == "自动":
			b.set_meta("role", "auto")
		if spec[0] == "快进":
			b.set_meta("role", "skip")

func _refresh_time() -> void:
	if time_label == null:
		return
	time_label.text = GameState.time_display()
	# 深夜/凌晨用冷色，强化时段感
	var h := GameState.story_minute / 60
	if h >= 22 or h < 5:
		time_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.84))
	elif h < 8:
		time_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
	else:
		time_label.add_theme_color_override("font_color", Color(0.80, 0.77, 0.68))

func _refresh_status() -> void:
	for c in status_strip.get_children():
		c.queue_free()
	for key in Cfg.NUM_VISIBLE:
		var lbl := Label.new()
		var v := GameState.get_num(key)
		lbl.text = "%s %d" % [Cfg.NUM_LABEL[key], v]
		lbl.add_theme_font_size_override("font_size", 19)
		var col := Color(0.72, 0.71, 0.68)
		if key == "sanity":
			col = Color(0.55, 0.78, 0.72) if v >= 60 else (Color(0.86, 0.72, 0.35) if v >= 30 else Color(0.86, 0.30, 0.26))
		elif key == "truth":
			col = Color(0.68, 0.75, 0.85)
		elif key == "shenhe_focus" and v >= 8:
			col = Color(0.86, 0.40, 0.36)
		lbl.add_theme_color_override("font_color", col)
		status_strip.add_child(lbl)

func _build_text_box() -> void:
	box = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 24
	box.offset_right = -24
	box.offset_top = -252
	box.offset_bottom = -20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.045, 0.055, 0.90)
	sb.border_color = Color(0.48, 0.44, 0.40, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 18
	sb.content_margin_bottom = 16
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 12
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(box)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(0.86, 0.72, 0.52))
	v.add_child(name_label)

	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = false
	text_label.scroll_active = false
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("normal_font_size", 29)
	text_label.add_theme_constant_override("line_separation", 10)
	v.add_child(text_label)

	continue_hint = Label.new()
	continue_hint.text = "▼"
	continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_hint.add_theme_font_size_override("font_size", 20)
	continue_hint.add_theme_color_override("font_color", Color(0.8, 0.6, 0.45, 0.8))
	v.add_child(continue_hint)

func _build_choice_area() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -70
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(center)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 12)
	choice_box.custom_minimum_size.x = 720
	center.add_child(choice_box)

# ---------------------------------------------------------------- 引擎连接
func _connect_engine() -> void:
	StoryEngine.line_ready.connect(_on_line)
	StoryEngine.choices_ready.connect(_on_choices)
	StoryEngine.scene_requested.connect(_on_scene)
	StoryEngine.actor_requested.connect(_on_actor)
	StoryEngine.effect_requested.connect(_on_effect)
	StoryEngine.overlay_requested.connect(_on_overlay)
	StoryEngine.chapter_started.connect(_on_chapter)
	StoryEngine.story_finished.connect(func(e): finished.emit(e))
	GameState.clue_unlocked.connect(func(_id): pass)

func _on_scene(kind: String, value: String, extra: String) -> void:
	if kind == "bg":
		bg.set_scene(value, extra)
		bg.blood_amount = 0.0
		if extra == "blood":
			bg.blood_amount = 0.8
		bg.wet = 1.0 if extra == "rain" else 0.0

func _on_actor(kind: String, who: String, emo: String, pos: String) -> void:
	match kind:
		"show":
			var a: ActorSprite
			if actors.has(who):
				a = actors[who]["node"]
			else:
				a = ActorSpriteS.new()
				a.who = who
				actor_root.add_child(a)
				actors[who] = {"node": a, "pos": pos}
			a.setup(who, emo if emo != "" else "normal")
			actors[who]["pos"] = pos
			# 特殊呈现
			a.glitch = 0.0
			a.wounded = 0.0
			if who == "shenhe":
				a.glitch = 0.35
			if who == "liangye" and GameState.get_state("liangye_state") == "half_assimilated":
				a.glitch = 0.5
				a.wounded = 0.35
			if who == "liangye" and GameState.get_flag("flag_liangye_bleeding"):
				a.wounded = 0.8
			if who == "oldqin" and GameState.get_state("oldqin_state") == "burned":
				a.wounded = 1.0
			_layout_actors()
		"hide":
			if actors.has(who):
				actors[who]["node"].queue_free()
				actors.erase(who)
				_layout_actors()
		"clear":
			for k in actors.keys():
				actors[k]["node"].queue_free()
			actors.clear()

func _layout_actors() -> void:
	var keys := actors.keys()
	var slots := {"left": 0.22, "center": 0.5, "right": 0.78, "farleft": 0.10, "farright": 0.90}
	var i := 0
	for k in keys:
		var d: Dictionary = actors[k]
		var a: ActorSprite = d["node"]
		var pos := String(d["pos"])
		var fx_ratio: float = float(slots.get(pos, 0.5))
		if not slots.has(pos):
			fx_ratio = 0.5 + (i - (keys.size() - 1) * 0.5) * 0.26
		# 立绘素材为 768x1280 竖图，按高度铺满可视区（文本框上沿之上）
		var box_top := size.y - 252.0 - 20.0
		var h := clampf(box_top - 62.0, size.y * 0.55, size.y * 0.94)
		var w := h * (768.0 / 1280.0)
		a.size = Vector2(w, h)
		# 脚底压在文本框上沿略下方，避免悬空
		a.position = Vector2(size.x * fx_ratio - w * 0.5, box_top + 26.0 - h)
		i += 1

func _on_effect(name: String, power: float) -> void:
	# 血腥 UI 痕迹（仅完整血腥档生效，内部自带开关判断）
	match name:
		"handprint", "bloodhand":
			gore.add_mark("handprint", power)
			AudioDirector.play_sfx("sfx_flesh", 0.5)
			return
		"bloodsmear":
			gore.add_mark("smear", power)
			return
		"blooddrip":
			gore.add_mark("drip", power)
			AudioDirector.play_sfx("sfx_water", 0.4)
			return
		"bloodedge":
			gore.add_mark("edge", power)
			return
		"bloodcrack":
			gore.add_mark("crack", power)
			AudioDirector.play_sfx("sfx_glass", 0.5)
			return
		"cleanblood":
			gore.clear_marks()
			return
	fx.play(name, power)
	if name == "flicker":
		bg.flicker = 1.0
		create_tween().tween_property(bg, "flicker", 0.0, 1.2)
	elif name == "blood" or name == "bloodburst":
		bg.blood_amount = minf(1.0, bg.blood_amount + 0.35 * power)

func _on_chapter(num: int, title: String) -> void:
	_blocked = true
	var ov := OW.chapter_card(num, title)
	add_child(ov)
	ov.tree_exited.connect(_unblock)

func _on_overlay(kind: String, payload: Dictionary) -> void:
	match kind:
		"title":
			_blocked = true
			var ov := OW.title_card(String(payload.get("text", "")))
			add_child(ov)
			ov.tree_exited.connect(_unblock)
		"note":
			_blocked = true
			var ov2 := OW.note_card(String(payload.get("text", "")))
			add_child(ov2)
			ov2.tree_exited.connect(_unblock)
		"roster":
			_blocked = true
			var ov3 := OW.roster_card()
			add_child(ov3)
			ov3.tree_exited.connect(_unblock)
		"item":
			var t := OW.toast("获得道具：" + GameState.item_name(String(payload.get("id", ""))))
			add_child(t)
			AudioDirector.play_sfx("sfx_page", 0.7)
		"clue":
			var cid := String(payload.get("id", ""))
			var cname := String(GameState.CLUES.get(cid, {}).get("name", cid))
			var t2 := OW.toast("线索：" + cname)
			add_child(t2)
			AudioDirector.play_sfx("sfx_write", 0.8)
		"wait":
			_blocked = true
			_pending_wait = float(payload.get("time", 1.0))

func _unblock() -> void:
	_blocked = false
	StoryEngine.advance()

# ---------------------------------------------------------------- 文本
func _on_line(line: Dictionary) -> void:
	_clear_choices()
	_cur_who = String(line.get("who", ""))
	var style := String(line.get("style", "line"))
	var raw := String(line.get("text", ""))
	raw = _corrupt(raw)

	if _cur_who == "":
		name_label.visible = false
	else:
		name_label.visible = true
		name_label.text = String(Cfg.CHARACTERS.get(_cur_who, {}).get("name", _cur_who))
		name_label.add_theme_color_override("font_color", Cfg.CHARACTERS.get(_cur_who, {}).get("color", Color.WHITE))

	# 高亮说话者
	for k in actors:
		actors[k]["node"].active = (k == _cur_who)

	var prefix := ""
	var suffix := ""
	match style:
		"narration":
			prefix = "[color=#b9b6ae]"
			suffix = "[/color]"
		"note":
			prefix = "[color=#c9a24a][i]"
			suffix = "[/i][/color]"
		_:
			prefix = "[color=#e6e3dc]"
			suffix = "[/color]"
	_full_text = prefix + raw + suffix
	text_label.text = _full_text
	text_label.visible_characters = 0
	_shown = 0
	_typing = true
	_type_acc = 0.0
	continue_hint.visible = false
	if _cur_who != "":
		AudioDirector.play_sfx("sfx_click", 0.10)

## 低理智时的文本篡改（保证叙述不可靠感）
## 低理智不再篡改台词本身（会影响阅读与理解），
## 改为通过 SanityFX 影响 UI 呈现：抖动、色偏、暗角、噪点。
func _corrupt(t: String) -> String:
	return t

func _process(delta: float) -> void:
	if _pending_wait > 0.0:
		_pending_wait -= delta
		if _pending_wait <= 0.0:
			_pending_wait = 0.0
			_unblock()
		return
	if _typing:
		var spd := SaveSystem.text_delay()
		if _skip:
			spd = 0.001
		_type_acc += delta
		while _type_acc >= spd and _typing:
			_type_acc -= spd
			_shown += 1
			text_label.visible_characters = _shown
			if _shown % 3 == 0 and _cur_who != "" and not _skip:
				AudioDirector.play_blip(_cur_who)
			if _shown >= text_label.get_total_character_count():
				_typing = false
				text_label.visible_characters = -1
				continue_hint.visible = true
				_auto_timer = 0.0
	elif (_auto or _skip) and not _blocked and choice_box.get_child_count() == 0:
		_auto_timer += delta
		var need := 0.05 if _skip else float(SaveSystem.settings.get("auto_speed", 1.6))
		if _auto_timer >= need:
			_auto_timer = 0.0
			_advance()
	# 呼吸提示
	if continue_hint.visible:
		continue_hint.modulate.a = 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() / 500.0))
	_layout_actors_if_needed()

var _last_size := Vector2.ZERO
func _layout_actors_if_needed() -> void:
	if size != _last_size:
		_last_size = size
		_layout_actors()

# ---------------------------------------------------------------- 选项
func _on_choices(list: Array) -> void:
	_clear_choices()
	continue_hint.visible = false
	AudioDirector.play_sfx("sfx_chair", 0.35)
	var idx := 0
	for c in list:
		var ch: Dictionary = c
		var b := Button.new()
		var txt := String(ch["text"])
		if not bool(ch.get("enabled", true)):
			txt += "  〔%s〕" % String(ch.get("hint", "条件未满足"))
		b.text = txt
		b.disabled = not bool(ch.get("enabled", true))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(720, 0)
		b.add_theme_font_size_override("font_size", 27)
		b.pressed.connect(func():
			AudioDirector.play_sfx("sfx_click", 0.8)
			_clear_choices()
			StoryEngine.pick_choice(ch)
		)
		choice_box.add_child(b)
		b.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.05 * idx)
		tw.tween_property(b, "modulate:a", 1.0, 0.22)
		idx += 1

func _clear_choices() -> void:
	for c in choice_box.get_children():
		c.queue_free()

# ---------------------------------------------------------------- 输入
func _on_screen_tap() -> void:
	if choice_box.get_child_count() > 0:
		return
	_advance()

func _advance() -> void:
	if _blocked:
		return
	if _typing:
		_typing = false
		text_label.visible_characters = -1
		continue_hint.visible = true
		return
	_auto_timer = 0.0
	StoryEngine.advance()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE, KEY_ENTER:
				_on_screen_tap()
			KEY_ESCAPE:
				_open_menu()
			KEY_A:
				_toggle_auto()
			KEY_S:
				_toggle_skip()
			KEY_H:
				_open_history()
			KEY_TAB:
				_open_clues()

func _toggle_auto() -> void:
	_auto = not _auto
	_skip = false
	_mark_toggle()

func _toggle_skip() -> void:
	_skip = not _skip
	_auto = false
	_mark_toggle()

func _mark_toggle() -> void:
	for b in top_bar.get_children():
		if b is Button and b.has_meta("role"):
			var r := String(b.get_meta("role"))
			var on := (_auto and r == "auto") or (_skip and r == "skip")
			b.modulate = Color(1.0, 0.7, 0.6) if on else Color.WHITE

# ---------------------------------------------------------------- 菜单
func _open_history() -> void:
	_push_panel(MP.history_panel())

func _open_clues() -> void:
	_push_panel(MP.clue_panel())

func _open_status() -> void:
	_push_panel(MP.status_panel())

func _open_saves() -> void:
	var p := MP.save_panel(true)
	p.set_meta("on_load", func(idx: int):
		var d := SaveSystem.read_slot(idx)
		if d.is_empty():
			return
		GameState.from_dict(d)
		_refresh_status()
		var n := String(d.get("node", "prologue"))
		StoryEngine.start(n if StoryEngine.has_story_node(n) else "prologue")
	)
	_push_panel(p)

func _open_menu() -> void:
	var p := MP.system_panel()
	p.set_meta("on_quit", func():
		SaveSystem.autosave()
		quit_to_title.emit()
	)
	_push_panel(p)

func _push_panel(p: Control) -> void:
	_blocked = true
	add_child(p)
	p.tree_exited.connect(func(): _blocked = false)
