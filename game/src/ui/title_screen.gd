extends Control
## 标题界面：程序化氛围（雨夜教学楼 + 闪烁窗 + 广播底噪）

signal start_new()
signal continue_game()
signal load_slot(i: int)

const BGPainterS := preload("res://src/art/bg_painter.gd")
const MenuPanelsS := preload("res://src/ui/menu_panels.gd")

var _t := 0.0
var subtitle_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: BGPainter = BGPainterS.new()
	bg.set_scene("oldbuilding_out", "rain")
	add_child(bg)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.01, 0.02, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	var title := Label.new()
	title.text = Cfg.GAME_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	title.add_theme_color_override("font_shadow_color", Color(0.5, 0.05, 0.04, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	v.add_child(title)

	subtitle_label = Label.new()
	subtitle_label.text = Cfg.GAME_SUBTITLE
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 22)
	subtitle_label.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	v.add_child(subtitle_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 34)
	v.add_child(spacer)

	var cycles := int(GameState.persistent.get("cycles", 0))
	if cycles > 0:
		var cy := Label.new()
		cy.text = "这是第 %d 次重排。" % (109 + cycles)
		cy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cy.add_theme_font_size_override("font_size", 23)
		cy.add_theme_color_override("font_color", Color(0.72, 0.34, 0.30))
		v.add_child(cy)

	var has_save := SaveSystem.has_any_save()
	_add_btn(v, "继续（自动存档）", func(): continue_game.emit(), not has_save)
	_add_btn(v, "开始新游戏", func(): _confirm_new())
	_add_btn(v, "读取存档", func():
		var p := MenuPanelsS.save_panel(false)
		p.set_meta("on_load", func(i): load_slot.emit(i))
		add_child(p))
	_add_btn(v, "结局与记录", func(): add_child(MenuPanelsS.gallery_panel()))
	_add_btn(v, "设置", func():
		var p := MenuPanelsS.system_panel()
		p.set_meta("on_quit", func(): pass)
		add_child(p))
	if OS.get_name() != "Web":
		_add_btn(v, "退出", func(): get_tree().quit())

	var ver := Label.new()
	ver.text = "v%s　Godot 4.7.1 stable　含惊吓与血腥描写，建议佩戴耳机" % Cfg.VERSION
	ver.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ver.offset_top = -46
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_font_size_override("font_size", 19)
	ver.add_theme_color_override("font_color", Color(0.55, 0.53, 0.50, 0.8))
	add_child(ver)

	AudioDirector.play_bgm("bgm_title")
	AudioDirector.play_amb("amb_rain")
	set_process(true)

func _add_btn(v: VBoxContainer, text: String, cb: Callable, disabled := false) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(400, 0)
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
	yes.pressed.connect(func():
		root.queue_free()
		start_new.emit())
	h.add_child(yes)
	var no := Button.new()
	no.text = "返回"
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(func(): root.queue_free())
	h.add_child(no)
	add_child(root)

func _process(delta: float) -> void:
	_t += delta
	if subtitle_label:
		subtitle_label.modulate.a = 0.55 + 0.35 * sin(_t * 0.9)
