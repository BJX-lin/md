extends RefCounted
## 程序化主题：不依赖外部字体文件（使用系统 CJK 字体回退），全部样式代码生成。

const BG := Color(0.055, 0.057, 0.065)
const PANEL := Color(0.09, 0.09, 0.10, 0.92)
const LINE := Color(0.44, 0.42, 0.38, 0.55)
const TEXT := Color(0.88, 0.87, 0.84)
const DIM := Color(0.62, 0.61, 0.58)
const ACC := Color(0.72, 0.28, 0.24)

## UI 贴图目录。整套贴图都是可选的：缺任何一张都会自动回落到
## 原来的程序化纯色样式，不影响运行。
const UI_ROOT := "res://assets/ui"

static func build() -> Theme:
	var t := Theme.new()
	var font := _load_font()
	if font:
		t.default_font = font
	t.default_font_size = 26

	# ---- Button
	# 有 assets/ui/choice_button.png 就用纹理底，否则回落到纯色样式。
	# 纹理只做底纹，配色仍由 modulate 控制，保证选中/按下的反馈依旧明显。
	var btn_tex := _tex(UI_ROOT + "/choice_button.png")
	var b_norm: StyleBox
	var b_hover: StyleBox
	var b_press: StyleBox
	var b_dis: StyleBox
	if btn_tex:
		b_norm = _sb_tex(btn_tex, Color(1, 1, 1, 0.94), LINE)
		b_hover = _sb_tex(btn_tex, Color(1.45, 1.12, 1.02, 0.97), Color(0.78, 0.44, 0.36, 0.9))
		b_press = _sb_tex(btn_tex, Color(1.65, 0.78, 0.70, 1.0), ACC)
		b_dis = _sb_tex(btn_tex, Color(0.55, 0.55, 0.58, 0.7), Color(0.3, 0.3, 0.3, 0.4))
	else:
		b_norm = _sb(Color(0.11, 0.11, 0.125, 0.94), LINE, 1)
		b_hover = _sb(Color(0.17, 0.15, 0.15, 0.96), Color(0.75, 0.42, 0.34, 0.85), 1)
		b_press = _sb(Color(0.24, 0.12, 0.11, 0.98), ACC, 1)
		b_dis = _sb(Color(0.09, 0.09, 0.10, 0.7), Color(0.3, 0.3, 0.3, 0.4), 1)
	for s in [b_norm, b_hover, b_press, b_dis]:
		s.content_margin_left = 22
		s.content_margin_right = 22
		s.content_margin_top = 14
		s.content_margin_bottom = 14
	t.set_stylebox("normal", "Button", b_norm)
	t.set_stylebox("hover", "Button", b_hover)
	t.set_stylebox("pressed", "Button", b_press)
	t.set_stylebox("disabled", "Button", b_dis)
	t.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), Color(0.8, 0.5, 0.4, 0.5), 1))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.92, 0.88))
	t.set_color("font_pressed_color", "Button", Color(1, 0.85, 0.80))
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.44, 0.43))
	t.set_font_size("font_size", "Button", 26)

	# ---- Panel
	t.set_stylebox("panel", "Panel", _sb(PANEL, LINE, 1))
	t.set_stylebox("panel", "PanelContainer", _sb(PANEL, LINE, 1))

	# ---- Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 26)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 28)
	t.set_stylebox("normal", "RichTextLabel", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))

	# ---- Scroll / Slider / Check
	t.set_stylebox("panel", "ScrollContainer", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	var grabber := _sb(Color(0.55, 0.32, 0.28, 0.9), Color(0, 0, 0, 0), 0, 6)
	t.set_stylebox("grabber_area", "VScrollBar", grabber)
	t.set_stylebox("grabber_area_highlight", "VScrollBar", grabber)
	t.set_stylebox("scroll", "VScrollBar", _sb(Color(0.15, 0.15, 0.16, 0.6), Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("slider", "HSlider", _sb(Color(0.16, 0.16, 0.17, 0.9), LINE, 1, 6))
	t.set_stylebox("grabber_area", "HSlider", _sb(Color(0.62, 0.3, 0.26, 0.95), Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", _sb(Color(0.78, 0.38, 0.32, 1.0), Color(0, 0, 0, 0), 0, 6))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)

	# ---- Popup
	t.set_stylebox("panel", "PopupPanel", _sb(Color(0.07, 0.07, 0.08, 0.98), LINE, 1))
	return t

## 纹理样式盒：九宫格拉伸，边缘 6px 不参与拉伸，避免细节被扯变形。
static func _sb_tex(tex: Texture2D, tint: Color, border: Color) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.modulate_color = tint
	s.set_texture_margin_all(6)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	# StyleBoxTexture 没有描边，用 region 之外的做法不划算；
	# 边框感由 game_screen 的分隔线与纹理自带的暗角提供。
	_ = border
	return s

## 安全加载 UI 纹理：缺图返回 null，调用方回落到纯色样式，绝不崩。
static func _tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var r = load(path)
	return r if r is Texture2D else null

static func _sb(bg: Color, border: Color, bw: int, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s

static func _load_font() -> Font:
	# 优先项目内字体；否则用系统 CJK 字体族回退，保证中文可显示
	var candidates := [
		"res://assets/fonts/main.ttf", "res://assets/fonts/main.otf",
		"res://assets/fonts/NotoSerifSC.ttf",
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			var f = load(p)
			if f is Font:
				return f
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Noto Serif CJK SC", "Source Han Serif SC", "Songti SC", "SimSun",
		"Noto Sans CJK SC", "Source Han Sans SC", "Microsoft YaHei", "PingFang SC",
		"WenQuanYi Zen Hei", "Droid Sans Fallback", "sans-serif",
	])
	sf.allow_system_fallback = true
	sf.multichannel_signed_distance_field = false
	return sf
