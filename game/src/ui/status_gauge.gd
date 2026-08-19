extends Control
class_name StatusGauge
## 顶栏的单个数值指示器：文字 + 条形量表 + 变化反馈。
##
## 相比原先的纯数字，这里能表达三件事：
##   1. 当前量级 —— 条形长度按阈值归一化
##   2. 变化方向 —— 升/降时飘出 +N / -N，并短暂高亮
##   3. 危险程度 —— 低理智会脉动，高关注度会缓慢呼吸
##
## 数值不变时完全不重绘（_process 直接 return），不占性能。

var key := ""
var label_text := ""
var value := 0
var vmax := 100
var _shown := 0.0          # 条形当前显示值，用于平滑过渡
var _flash := 0.0          # 变化高亮残留
var _delta := 0            # 最近一次变化量
var _delta_life := 0.0
var _pulse := 0.0
var _danger := false       # 危险态（低理智 / 高关注）
var _base_col := Color(0.72, 0.71, 0.68)

const W := 132.0
const BAR_H := 3.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 30)

func _ready() -> void:
	set_process(true)
	_shown = float(value)

## 由 game_screen 调用：更新数值并触发反馈
func set_value(v: int, vmax_: int) -> void:
	vmax = maxi(1, vmax_)
	if v != value:
		_delta = v - value
		_delta_life = 1.6
		_flash = 1.0
		value = v
		queue_redraw()

func _process(delta: float) -> void:
	var active := false
	# 条形平滑追赶
	if absf(_shown - float(value)) > 0.5:
		_shown = lerpf(_shown, float(value), clampf(delta * 6.0, 0.0, 1.0))
		active = true
	if _flash > 0.001:
		_flash = maxf(0.0, _flash - delta * 1.8)
		active = true
	if _delta_life > 0.0:
		_delta_life = maxf(0.0, _delta_life - delta)
		active = true
	if _danger:
		_pulse += delta
		active = true
	if active:
		queue_redraw()

func _draw() -> void:
	var ratio := clampf(_shown / float(vmax), 0.0, 1.0)
	var col := _base_col
	var glow := 0.0

	match key:
		"sanity":
			# 理智：越低越红，低于 30% 开始脉动
			if ratio >= 0.6:
				col = Color(0.55, 0.78, 0.72)
			elif ratio >= 0.3:
				col = Color(0.86, 0.72, 0.35)
			else:
				col = Color(0.88, 0.30, 0.26)
				glow = 0.5 + 0.5 * sin(_pulse * 4.0)
			_danger = ratio < 0.3
		"truth":
			col = Color(0.68, 0.75, 0.85).lerp(Color(0.80, 0.88, 1.0), ratio)
			_danger = false
		"shenhe_focus":
			# 沈禾关注：越高越危险，缓慢呼吸
			col = Color(0.70, 0.68, 0.70).lerp(Color(0.90, 0.36, 0.32), ratio)
			_danger = ratio > 0.45
			if _danger:
				glow = 0.35 + 0.35 * sin(_pulse * 2.2)
		"memory_echo":
			col = Color(0.72, 0.70, 0.80).lerp(Color(0.78, 0.62, 0.92), ratio)
			_danger = false
		_:
			_danger = false

	# 变化瞬间整体提亮
	if _flash > 0.0:
		col = col.lerp(Color(1, 1, 1), _flash * 0.5)

	# —— 文字
	var f := get_theme_default_font()
	var fs := 18
	draw_string(f, Vector2(0, 15), "%s %d" % [label_text, value],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# —— 条形底槽
	draw_rect(Rect2(0, 21, W - 18, BAR_H), Color(0.20, 0.20, 0.23, 0.85), true)
	# —— 条形填充
	var fill_w := (W - 18) * ratio
	if fill_w > 0.5:
		var bc := Color(col.r, col.g, col.b, 0.92)
		draw_rect(Rect2(0, 21, fill_w, BAR_H), bc, true)
		# 危险态在条尾加一点辉光
		if glow > 0.01:
			draw_rect(Rect2(maxf(0.0, fill_w - 12.0), 20, 12, BAR_H + 2),
				Color(col.r, col.g, col.b, 0.45 * glow), true)

	# —— 变化量飘字
	if _delta_life > 0.0 and _delta != 0:
		var a := clampf(_delta_life / 1.6, 0.0, 1.0)
		var rise := (1.0 - a) * 10.0
		var dc := Color(0.62, 0.88, 0.70, a) if _delta > 0 else Color(0.92, 0.52, 0.46, a)
		var txt := "+%d" % _delta if _delta > 0 else str(_delta)
		draw_string(f, Vector2(W - 16, 14 - rise), txt,
			HORIZONTAL_ALIGNMENT_RIGHT, -1, 15, dc)
