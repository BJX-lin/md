extends Control
## 标题界面：程序化氛围（雨夜教学楼 + 闪烁窗 + 广播底噪）

signal start_new()
signal continue_game()
signal load_slot(i: int)

const BGLayerS := preload("res://src/art/bg_layer.gd")
const MenuPanelsS := preload("res://src/ui/menu_panels.gd")
const NameEntryS := preload("res://src/ui/name_entry.gd")

var _t := 0.0
var subtitle_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: BGLayer = BGLayerS.new()
	bg.set_scene("schoolyard", "dusk")
	add_child(bg)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.01, 0.02, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# 标题主视觉：光柱下的空椅子（对应《空席》）。
	# 两栏布局下靠右半屏放置，正好落在菜单背后当氛围底，
	# 不会和左侧标题文字抢视线。缺图则完全跳过。
	var emblem := UITex.make_layer("title_emblem", 0.32,
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	if emblem != null:
		emblem.anchor_left = 0.42
		emblem.anchor_right = 1.0
		emblem.anchor_top = 0.0
		emblem.anchor_bottom = 1.0
		emblem.offset_left = 0
		emblem.offset_right = 0
		emblem.offset_top = 0
		emblem.offset_bottom = 0
		add_child(emblem)

	# —— 新版布局：左标题 / 右菜单的两栏式，整体可滚动
	#
	# 改动理由：
	#   * 原来是单列居中，菜单一多（现在 7 项）就会顶到屏幕上下边缘，
	#     小屏或横屏矮机上直接被裁掉，且完全不能滚
	#   * 两栏把"标题主视觉"和"操作区"分开，视线不打架，
	#     右侧菜单靠右也更贴合单手拇指操作
	#   * 外层套 ScrollContainer：无论多矮的屏都能滑到最后一项
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.scroll_deadzone = 12
	add_child(scroll)

	var page := MarginContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("margin_left", 56)
	page.add_theme_constant_override("margin_right", 56)
	page.add_theme_constant_override("margin_top", 40)
	page.add_theme_constant_override("margin_bottom", 64)
	scroll.add_child(page)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(cols)

	# ---- 左栏：标题 / 副标题 / 周目
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)

	var title := Label.new()
	title.text = Cfg.GAME_TITLE
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	title.add_theme_color_override("font_shadow_color", Color(0.5, 0.05, 0.04, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	left.add_child(title)

	# 标题下的一道细红线，替代原来空荡荡的间距
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(140, 2)
	rule.color = Color(0.62, 0.20, 0.18, 0.85)
	left.add_child(rule)

	subtitle_label = Label.new()
	subtitle_label.text = Cfg.GAME_SUBTITLE
	subtitle_label.add_theme_font_size_override("font_size", 21)
	subtitle_label.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	left.add_child(subtitle_label)

	var cycles := int(GameState.persistent.get("cycles", 0))
	if cycles > 0:
		var cy := Label.new()
		cy.text = "这是第 %d 次重排。" % (109 + cycles)
		cy.add_theme_font_size_override("font_size", 22)
		cy.add_theme_color_override("font_color", Color(0.72, 0.34, 0.30))
		left.add_child(cy)

	# ---- 右栏：菜单
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)

	var has_save := SaveSystem.has_any_save()
	_add_btn(right, "继续（自动存档）", func(): continue_game.emit(), not has_save)
	_add_btn(right, "开始新游戏", func(): _confirm_new())
	_add_btn(right, "读取存档", func():
		var p := MenuPanelsS.save_panel(false)
		p.set_meta("on_load", func(i): load_slot.emit(i))
		add_child(p))
	_add_btn(right, "结局与记录", func(): add_child(MenuPanelsS.gallery_panel()))
	_add_btn(right, "设置", func():
		var p := MenuPanelsS.system_panel()
		p.set_meta("on_quit", func(): pass)
		add_child(p))
	_add_btn(right, "BUG 反馈 / 交流群", func(): add_child(MenuPanelsS.feedback_panel()))
	if OS.get_name() != "Web":
		_add_btn(right, "退出", func(): get_tree().quit())

	var ver := Label.new()
	ver.text = "v%s　Godot 4.7.1 stable　含惊吓与血腥描写，建议佩戴耳机" % Cfg.VERSION
	ver.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ver.offset_top = -40
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_font_size_override("font_size", 18)
	ver.add_theme_color_override("font_color", Color(0.55, 0.53, 0.50, 0.8))
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)

	AudioDirector.play_bgm("bgm_title")
	AudioDirector.play_amb("amb_rain")
	set_process(true)

func _add_btn(v: VBoxContainer, text: String, cb: Callable, disabled := false) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	# 标题菜单是玩家第一次接触到的交互，按钮给足高度
	b.custom_minimum_size = Vector2(420, 58)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(func():
		AudioDirector.play_sfx("sfx_click", 0.8)
		cb.call()
	)
	v.add_child(b)

func _confirm_new() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.85)
	root.add_child(shade)
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var l := Label.new()
	l.text = "内容提示\n本作包含：校园怪谈恐怖、突发惊吓演出、\n血腥与伤害描写、自杀/事故相关情节、压抑主题。\n可在设置中调整血腥程度、闪光与震动。\n\n开始新游戏？"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	v.add_child(l)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	var yes := Button.new()
	yes.text = "开始"
	yes.focus_mode = Control.FOCUS_NONE
	yes.custom_minimum_size = Vector2(160, 52)
	yes.pressed.connect(func():
		root.queue_free()
		_open_name_entry())
	h.add_child(yes)
	var no := Button.new()
	no.text = "返回"
	no.focus_mode = Control.FOCUS_NONE
	no.custom_minimum_size = Vector2(160, 52)
	no.pressed.connect(func(): root.queue_free())
	h.add_child(no)
	add_child(root)

func _process(delta: float) -> void:
	_t += delta
	if subtitle_label:
		subtitle_label.modulate.a = 0.55 + 0.35 * sin(_t * 0.9)


## 新游戏第一步：为主角命名（增强代入感）。
## 取消则留在标题；确认后把名字写入 GameState 再正式开始。
func _open_name_entry() -> void:
	var ne := NameEntryS.new()
	ne.confirmed.connect(func(player_name: String):
		GameState.player_name = player_name
		start_new.emit()
	)
	add_child(ne)
