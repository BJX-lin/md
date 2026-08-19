extends Control
class_name LoadingOverlay
## 重大选择后的过场加载层。
##
## 三件事同时进行：
##   1. 显示进度条与「正在释放性能…」等状态文案（progress_hint 上方那行）
##   2. 后台按章节预取接下来会用到的贴图（后台运算后续内容）
##   3. 释放已过场章节缓存的贴图（释放已过场的内容）
##
## 用 ResourceLoader.load_threaded_request 做真正的后台加载，
## 主线程只在 _process 里查询进度，不会卡帧。

signal finished

const STAGE_TEXT := {
	"release": "正在释放性能…",
	"preload": "正在载入后续场景…",
	"settle": "正在整理记忆…",
	"done": "完成",
}

var _paths: Array[String] = []
var _idx := 0
var _released := 0
var _t := 0.0
var _stage := "release"
var _min_time := 0.9          # 至少停留这么久，避免一闪而过
var _elapsed := 0.0
var _done := false

var _panel: PanelContainer
var _hint: Label            # 进度条上方的状态文案
var _detail: Label          # 次要说明（释放了多少 / 载入第几个）
var _bar: ProgressBar

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉点击，防止误触推进剧情
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_right = 0.0
	offset_bottom = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	set_process(true)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.075, 0.96)
	sb.border_color = Color(0.46, 0.42, 0.38, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	# 过场面板质感底。与其它面板同样作兄弟节点铺放：
	# PanelContainer 会按 content_margin 内缩子节点，放进去铺不满边缘。
	# 这里用 CenterContainer 跟随 _panel 尺寸，避免手算偏移。
	var grain := UITex.get_tex("panel_frame")
	if grain != null:
		var holder := CenterContainer.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.texture = grain
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = Color(1, 1, 1, 0.26)
		# 跟随面板实际尺寸，面板变大变小都不会露边
		_panel.resized.connect(func():
			tr.custom_minimum_size = _panel.size
			tr.size = _panel.size)
		holder.add_child(tr)
		add_child(holder)
		move_child(holder, _panel.get_index())

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size.x = 520
	_panel.add_child(v)

	# 进度条上方的状态文案
	_hint = Label.new()
	_hint.text = STAGE_TEXT["release"]
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80))
	v.add_child(_hint)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(520, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.58, 0.50)
	fill.set_corner_radius_all(2)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.16, 0.19)
	bg.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", bg)
	v.add_child(_bar)

	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_font_size_override("font_size", 14)
	_detail.add_theme_color_override("font_color", Color(0.58, 0.56, 0.54))
	v.add_child(_detail)

## chapter：即将进入的章节号，用于决定预取哪些图、释放哪些图
func begin(chapter: int, keep_paths: Array[String] = []) -> void:
	# —— 阶段一：释放已过场章节的贴图缓存
	_stage = "release"
	_released = ArtCache.release_stale(chapter, keep_paths)
	# —— 阶段二：把下一章要用的贴图丢进后台线程
	_paths = ArtCache.paths_for_chapter(chapter)
	_idx = 0
	for p in _paths:
		ResourceLoader.load_threaded_request(p)
	if _paths.is_empty():
		_stage = "settle"

func _process(delta: float) -> void:
	_t += delta
	_elapsed += delta
	if _done:
		return

	# 进度：已完成的预取数 / 总数
	var ratio := 1.0 if _paths.is_empty() else float(_idx) / float(_paths.size())
	_bar.value = lerpf(_bar.value, ratio * 100.0, clampf(delta * 8.0, 0.0, 1.0))

	match _stage:
		"release":
			_detail.text = "已释放 %d 项过场资源" % _released
			if _elapsed > 0.28:
				_stage = "preload" if not _paths.is_empty() else "settle"
		"preload":
			# 每帧最多推进几个，避免一帧内集中 load 造成卡顿
			var budget := 3
			while _idx < _paths.size() and budget > 0:
				var p := _paths[_idx]
				var st := ResourceLoader.load_threaded_get_status(p)
				if st == ResourceLoader.THREAD_LOAD_LOADED:
					ArtCache.put(p, ResourceLoader.load_threaded_get(p))
					_idx += 1
					budget -= 1
				elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					_idx += 1
					budget -= 1
				else:
					break   # 还在加载中，等下一帧
			_hint.text = STAGE_TEXT["preload"]
			_detail.text = "%d / %d" % [_idx, _paths.size()]
			if _idx >= _paths.size():
				_stage = "settle"
		"settle":
			_hint.text = STAGE_TEXT["settle"]
			_detail.text = "已释放 %d 项，已预载 %d 项" % [_released, _idx]
			_bar.value = 100.0
			if _elapsed >= _min_time:
				_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	_hint.text = STAGE_TEXT["done"]
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func():
		finished.emit()
		queue_free()
	)
