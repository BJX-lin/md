extends RefCounted
class_name UITex
## UI 贴图统一入口。
##
## 整套 UI 贴图都是【可选资源】：assets/ui/ 下任何一张缺失，
## 调用方都会回落到原来的程序化纯色样式，绝不报错、绝不崩。
## 这条约束很重要——UI 位于启动路径上，不能因为缺图卡住。
##
## 纹理只做质感底纹，配色/状态反馈仍由各处的 modulate 与
## StyleBoxFlat 控制，因此换皮不会破坏既有的交互反馈逻辑。

const ROOT := "res://assets/ui"

## 已解析过的路径缓存。UI 贴图数量少、生命周期长，
## 常驻缓存比反复 load 更划算，也避免打开菜单时的卡顿。
static var _cache := {}

## 安全取贴图：缺图或类型不对都返回 null。
static func get_tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path := "%s/%s.png" % [ROOT, name]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is Texture2D:
			tex = r
	_cache[name] = tex
	return tex

static func has(name: String) -> bool:
	return get_tex(name) != null

## 造一个铺满父节点的贴图背景层。
##
## alpha 一律压得比较低：这些图是"质感"，不是"主角"，
## 压过头会吃掉正文对比度。缺图返回 null，调用方直接跳过即可。
static func make_layer(name: String, alpha := 1.0,
		stretch := TextureRect.STRETCH_SCALE) -> TextureRect:
	var tex := get_tex(name)
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = stretch
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(1, 1, 1, alpha)
	return tr

## 把贴图层插进容器最底下（在其它子节点之前）。
static func add_under(parent: Control, name: String, alpha := 1.0) -> TextureRect:
	var layer := make_layer(name, alpha)
	if layer == null:
		return null
	parent.add_child(layer)
	parent.move_child(layer, 0)
	return layer

## 纹理样式盒，用于 Button / Panel。
## 九宫格边距避免细节在拉伸时变形。
static func style_box(name: String, tint := Color(1, 1, 1, 1),
		margin := 8) -> StyleBoxTexture:
	var tex := get_tex(name)
	if tex == null:
		return null
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.modulate_color = tint
	s.set_texture_margin_all(margin)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return s
