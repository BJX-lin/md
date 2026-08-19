extends Control
## 游戏主界面：背景 / 立绘 / 文本框 / 选项 / 顶栏 / 各类弹窗

signal finished(ending_id: String)
signal quit_to_title()

const BGLayerS := preload("res://src/art/bg_layer.gd")
const ActorSpriteS := preload("res://src/art/actor_sprite.gd")
const LoadingOverlayS := preload("res://src/ui/loading_overlay.gd")
const StatusGaugeS := preload("res://src/ui/status_gauge.gd")
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
var _box_text_holder: VBoxContainer      # 正文容器，纹理必须插在它之前
var _box_texture: TextureRect            # 对话框纸纹底（缺图时为 null）
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

## 读档后立刻把画面还原成存档那一刻：背景 + 台上的立绘。
## 不这样做的话，存档点所在节点通常没有 @bg 指令，
## 背景会一直空着，直到玩家推进到下一条 @bg 才出现。
func restore_scene() -> void:
	if is_instance_valid(bg):
		bg.set_scene(GameState.scene_bg, GameState.scene_variant)
		bg.blood_amount = 0.8 if GameState.scene_variant == "blood" else 0.0
		bg.wet = 1.0 if GameState.scene_variant == "rain" else 0.0
	for k in actors.keys():
		actors[k]["node"].queue_free()
	actors.clear()
	for a in GameState.scene_actors:
		var d: Dictionary = a
		_on_actor("show", String(d.get("who", "")),
			String(d.get("emo", "normal")), String(d.get("pos", "center")))

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
	# 旋屏 / 窗口缩放后必须重新排布立绘，否则位置和尺寸还是旧屏幕的
	resized.connect(_layout_actors)

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
	# 复用已建好的量表节点，只更新数值——原先每次全部 queue_free 再重建，
	# 数值一变就重建 4 个 Label，白白产生垃圾。
	if status_strip.get_child_count() != Cfg.NUM_VISIBLE.size():
		for c in status_strip.get_children():
			c.queue_free()
		for key in Cfg.NUM_VISIBLE:
			var g: StatusGauge = StatusGaugeS.new()
			g.key = String(key)
			g.label_text = String(Cfg.NUM_LABEL.get(key, key))
			status_strip.add_child(g)
	var i := 0
	for key in Cfg.NUM_VISIBLE:
		var node := status_strip.get_child(i) as StatusGauge
		i += 1
		if node == null:
			continue
		var rng: Array = Cfg.NUM_RANGE.get(key, [0, 100])
		node.set_value(GameState.get_num(key), int(rng[1]))
	_apply_state_theme()

## 让整个界面随数值变化，而不只是顶栏数字：
##   - 理智越低，文本框边框越红、正文越发灰、字距轻微不稳
##   - 沈禾关注度高时，名字栏染上一层红
##   - 真相到达阈值时，顶栏出现一条渐亮的提示线
func _apply_state_theme() -> void:
	var san := float(GameState.get_num("sanity"))
	var san_max: float = float((Cfg.NUM_RANGE.get("sanity", [0, 100]) as Array)[1])
	var sev := clampf((san_max * 0.8 - san) / (san_max * 0.8), 0.0, 1.0)

	if is_instance_valid(box):
		var sb := box.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			# 边框由冷灰渐变为暗红
			sb.border_color = Color(0.48, 0.44, 0.40, 0.55).lerp(
				Color(0.72, 0.24, 0.22, 0.85), sev)
			sb.set_border_width_all(1 + int(round(sev * 1.5)))
	if is_instance_valid(text_label):
		# 正文在低理智时略微褪色发灰
		text_label.modulate = Color(1, 1, 1).lerp(Color(0.86, 0.82, 0.82), sev * 0.8)

	var focus := float(GameState.get_num("shenhe_focus"))
	var focus_max: float = float((Cfg.NUM_RANGE.get("shenhe_focus", [0, 60]) as Array)[1])
	var fr := clampf(focus / focus_max, 0.0, 1.0)
	if is_instance_valid(name_label):
		name_label.add_theme_color_override("font_color",
			Color(0.84, 0.78, 0.62).lerp(Color(0.92, 0.42, 0.38), fr * 0.75))

## 给对话框铺一层纸纹底。
##
## 纹理做成 box 的【兄弟节点并排在它前面】，而不是 box 的子节点：
## PanelContainer 会把子节点按 content_margin 内缩 28px，
## 纹理若放进去就铺不满边缘，会露出一圈色差。
##
## 相应地把 StyleBoxFlat 的底色调成半透明——底色只负责压暗，
## 遮挡立绘下半身的任务交给不透明的纹理本身。
## 边框仍在 StyleBoxFlat 上，_apply_state_theme() 的理智染色照常生效。
##
## assets/ui/dialogue_panel.png 缺失时整段跳过：底色自动还原为
## 原来的 0.985 不透明，观感朴素但完全可用。
func _apply_box_texture() -> void:
	var path := "res://assets/ui/dialogue_panel.png"
	if not ResourceLoader.exists(path):
		return
	var tex = load(path)
	if not (tex is Texture2D):
		return

	_box_texture = TextureRect.new()
	_box_texture.texture = tex
	_box_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_box_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_box_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_texture.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_box_texture.offset_left = box.offset_left
	_box_texture.offset_right = box.offset_right
	_box_texture.offset_top = box.offset_top
	_box_texture.offset_bottom = box.offset_bottom
	ui_root.add_child(_box_texture)
	ui_root.move_child(_box_texture, box.get_index())

	# 底色让位给纹理：只保留压暗作用
	var sb := box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = Color(0.03, 0.03, 0.04, 0.55)

func _build_text_box() -> void:
	box = PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 24
	box.offset_right = -24
	box.offset_top = -252
	box.offset_bottom = -20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.045, 0.055, 0.985)   # 半身构图：需完全遮住立绘下半身
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

	# 纹理底纹：铺在 StyleBoxFlat 之上、正文之下。
	# 之所以用独立 TextureRect 而不是把 panel 换成 StyleBoxTexture，
	# 是因为 _apply_state_theme() 需要按理智值改边框颜色/粗细，
	# 那段逻辑依赖 panel 仍然是 StyleBoxFlat。
	_apply_box_texture()

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	_box_text_holder = v

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

		# —— 半身构图 ——
		# 立绘素材是 768x768 半身图（已裁掉永远看不见的下半身）：
		# 让人物占满可视区，图的底边沉进文本框被遮住。
		# 这样脸部更大、表情更清楚，也符合常见 AVG 的视觉习惯。
		var box_top: float = size.y - 272.0
		if is_instance_valid(box) and box.size.y > 1.0:
			box_top = box.position.y
		var top_bar_h := 56.0

		# 立绘素材已由 tools/crop_sprites.py 裁成半身（到大腿中部为止），
		# 因此图的底边就相当于「腰线偏下」，直接对齐到文本框内即可。
		# 裁切让每张立绘的显存占用降低 40%。
		const WAIST_RATIO := 0.88
		var waist_y: float = box_top + 40.0
		# 可视区 = 顶栏下沿 → 腰线，这段要装下人物的「头顶到腰」
		var visible_h: float = waist_y - top_bar_h
		# 由此反推整张立绘应有的高度
		var h: float = visible_h / WAIST_RATIO
		var w: float = h * (768.0 / 768.0)
		# 多人同屏时按槽位间距收窄，防止相邻立绘互相重叠
		var max_w: float = size.x * (0.52 if keys.size() > 1 else 0.68)
		if w > max_w:
			w = max_w
			h = w * (768.0 / 768.0)
		a.size = Vector2(w, h)
		# 纵向：让腰线对齐 waist_y（头顶可能超出顶栏一点，由 ActorSprite 内部裁掉）
		var top_y: float = waist_y - h * WAIST_RATIO
		# 横向夹紧，保证脸部不被切
		var x: float = clampf(size.x * fx_ratio - w * 0.5, -w * 0.08,
			maxf(0.0, size.x - w * 0.92))
		a.position = Vector2(x, top_y)
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
			_confirm_choice(b, ch)
		)
		choice_box.add_child(b)
		b.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.05 * idx)
		tw.tween_property(b, "modulate:a", 1.0, 0.22)
		idx += 1

## 选择反馈：先把选中项高亮、其余淡出，飘出这次选择造成的影响，
## 再决定是直接推进还是走过场加载。
func _confirm_choice(btn: Button, ch: Dictionary) -> void:
	_blocked = true
	for c in choice_box.get_children():
		var other := c as Button
		if other == null:
			continue
		other.disabled = true
		if other != btn:
			var tw_o := create_tween()
			tw_o.tween_property(other, "modulate:a", 0.18, 0.16)

	# 选中项：描边高亮 + 轻微放大
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.19, 0.16, 0.95)
	sb.border_color = Color(0.86, 0.78, 0.56)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_disabled_color", Color(0.94, 0.90, 0.80))
	btn.pivot_offset = btn.size * 0.5
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(1.035, 1.035), 0.12)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.10)

	_flash_choice_effects(ch)

	var major := _is_major_choice(ch)
	await get_tree().create_timer(0.42 if major else 0.26).timeout
	_clear_choices()
	_blocked = false

	if major:
		_run_transition(func(): StoryEngine.pick_choice(ch))
	else:
		StoryEngine.pick_choice(ch)

## 把选项造成的数值 / 线索变化，以小字飘在文本框上方
func _flash_choice_effects(ch: Dictionary) -> void:
	var msgs: Array[String] = []
	for e in ch.get("effects", []):
		var ef: Dictionary = e
		var cmd := String(ef.get("cmd", ""))
		var args: Array = ef.get("args", [])
		if cmd == "set" and args.size() >= 2:
			var key := String(args[0])
			if not Cfg.NUM_VISIBLE.has(key):
				continue
			var label := String(Cfg.NUM_LABEL.get(key, key))
			msgs.append("%s %s" % [label, String(args[1])])
		elif cmd == "clue":
			msgs.append("获得线索")
		elif cmd == "item":
			msgs.append("获得道具")
	if msgs.is_empty():
		return
	var lbl := Label.new()
	lbl.text = "　".join(msgs)
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.add_theme_color_override("font_color", Color(0.86, 0.80, 0.60))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl.position = Vector2(size.x * 0.5 - 200, size.y - 300)
	lbl.custom_minimum_size.x = 400
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 34.0, 0.9)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(lbl.queue_free)

## 重大选择判定：带 flag / 道具 / 结局分支，或数值改动较大
func _is_major_choice(ch: Dictionary) -> bool:
	var weight := 0
	for e in ch.get("effects", []):
		var ef: Dictionary = e
		var cmd := String(ef.get("cmd", ""))
		if cmd == "flag" or cmd == "item":
			weight += 3
		elif cmd == "clue":
			weight += 2
		elif cmd == "set":
			var args: Array = ef.get("args", [])
			if args.size() >= 2:
				var v := String(args[1]).lstrip("+-=")
				if v.is_valid_int() and int(v) >= 3:
					weight += 2
	return weight >= 4

## 过场：显示进度条 + 后台预取 + 释放已过场资源，完成后执行 next
func _run_transition(next: Callable) -> void:
	var ov := LoadingOverlayS.new()
	add_child(ov)
	var keep: Array[String] = []
	if is_instance_valid(bg):
		var cur := bg.current_texture_path()
		if cur != "":
			keep.append(cur)
	ov.begin(GameState.current_chapter, keep)
	ov.finished.connect(func():
		if next.is_valid():
			next.call()
	)

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
		restore_scene()
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
