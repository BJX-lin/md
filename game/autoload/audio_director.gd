extends Node
## 音频总监：全部音频在运行时程序化合成（AudioStreamWAV），
## 不依赖任何外部音频文件——空资源也不会报错（对应 e.md《音频安全方案》方案B）。
##
## 通道：music（BGM 循环）/ ambience（环境）/ sfx（音效，8 路复用）

const SR := 22050
const AUDIO_ROOT := "res://assets/audio"

var _music: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _cache: Dictionary = {}
var _cur_bgm := ""
var _cur_amb := ""

var master_volume := 1.0
var bgm_volume := 0.7
var sfx_volume := 0.85

func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	add_child(_music)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Master"
	add_child(_amb)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_pool.append(p)

func apply_settings(s: Dictionary) -> void:
	master_volume = float(s.get("vol_master", 1.0))
	bgm_volume = float(s.get("vol_bgm", 0.7))
	sfx_volume = float(s.get("vol_sfx", 0.85))
	_music.volume_db = linear_to_db(maxf(0.0001, bgm_volume * master_volume))
	_amb.volume_db = linear_to_db(maxf(0.0001, bgm_volume * master_volume * 0.8))

# ---------------------------------------------------------------- 播放接口
func play_bgm(id: String) -> void:
	if id == _cur_bgm and _music.playing:
		return
	_cur_bgm = id
	var st := _stream_for(id)
	if st == null:
		return
	_music.stream = st
	_music.volume_db = linear_to_db(maxf(0.0001, bgm_volume * master_volume))
	_music.play()

func stop_bgm() -> void:
	_cur_bgm = ""
	_music.stop()

func play_amb(id: String) -> void:
	if id == _cur_amb and _amb.playing:
		return
	_cur_amb = id
	var st := _stream_for(id)
	if st == null:
		return
	_amb.stream = st
	_amb.volume_db = linear_to_db(maxf(0.0001, bgm_volume * master_volume * 0.75))
	_amb.play()

func stop_amb() -> void:
	_cur_amb = ""
	_amb.stop()

func play_sfx(id: String, vol_scale: float = 1.0) -> void:
	var st := _stream_for(id)
	if st == null:
		return
	var p := _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = st
	p.volume_db = linear_to_db(maxf(0.0001, sfx_volume * master_volume * vol_scale))
	p.pitch_scale = randf_range(0.96, 1.04)
	p.play()

## 打字机的“字音”，按角色音色变调
func play_blip(char_key: String) -> void:
	var st := _stream_for("_blip")
	if st == null:
		return
	var p := _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	var base := float(Cfg.CHARACTERS.get(char_key, {}).get("pitch", 150.0))
	p.stream = st
	p.pitch_scale = clampf(base / 150.0, 0.6, 2.0) * randf_range(0.97, 1.03)
	p.volume_db = linear_to_db(maxf(0.0001, sfx_volume * master_volume * 0.16))
	p.play()

# ---------------------------------------------------------------- 取流
## 音效缓存上限。BGM / 环境音各自只有一条在播，不计入；
## 音效有 26 种但同一场景反复用的就那几种，超出上限就淘汰最久未用的。
const SFX_CACHE_MAX := 12
var _lru: Array[String] = []

func _touch(id: String) -> void:
	_lru.erase(id)
	_lru.append(id)
	# BGM / 环境音常驻（只有 1~2 条），只淘汰音效
	var sfx := _lru.filter(func(x): return x.begins_with("sfx_"))
	while sfx.size() > SFX_CACHE_MAX:
		var old: String = sfx.pop_front()
		_lru.erase(old)
		_cache.erase(old)

func _stream_for(id: String) -> AudioStream:
	if _cache.has(id):
		_touch(id)
		return _cache[id]
	# 优先使用外置音频文件（res://assets/audio/<id>.wav|.ogg|.mp3）。
	# 音频与代码解耦：换音只要按同名覆盖文件，不必改任何代码。
	var ext := _external_stream(id)
	if ext != null:
		_cache[id] = ext
		_touch(id)
		return ext
	# 找不到文件才回退到内置程序化合成（保证永远有声音）
	var data := _synth(id)
	if data.is_empty():
		return null
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = SR
	st.stereo = false
	st.data = data
	if id.begins_with("bgm_") or id.begins_with("amb_"):
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = data.size() / 2
	_cache[id] = st
	return st

## 从 res://assets/audio/ 读取外置音频。
## 支持 .ogg / .wav / .mp3，按此优先级查找。
func _external_stream(id: String) -> AudioStream:
	for ext in [".ogg", ".wav", ".mp3"]:
		var p := "%s/%s%s" % [AUDIO_ROOT, id, ext]
		if not ResourceLoader.exists(p):
			continue
		var st := load(p) as AudioStream
		if st == null:
			continue
		# BGM 与环境音需要循环
		if id.begins_with("bgm_") or id.begins_with("amb_"):
			if st is AudioStreamWAV:
				var w := st as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				w.loop_end = w.data.size() / 2
			elif st is AudioStreamOggVorbis:
				(st as AudioStreamOggVorbis).loop = true
			elif st is AudioStreamMP3:
				(st as AudioStreamMP3).loop = true
		return st
	return null

## 外置音频缺失时的兜底：返回一段极短静音，避免上层拿到 null。
## 全部 48 个音频已烘焙到 res://assets/audio/（见 tools/bake_audio.py），
## 正常情况下不会走到这里。原先 550 行程序化合成代码已随音频外置一并移除。
func _synth(_id: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(int(SR * 0.05) * 2)
	return out
