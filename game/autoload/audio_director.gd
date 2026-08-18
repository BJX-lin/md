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

# ---------------------------------------------------------------- 合成
func _stream_for(id: String) -> AudioStream:
	if _cache.has(id):
		return _cache[id]
	# 优先使用外置音频文件（res://assets/audio/<id>.wav|.ogg|.mp3）。
	# 音频与代码解耦：换音只要按同名覆盖文件，不必改任何代码。
	var ext := _external_stream(id)
	if ext != null:
		_cache[id] = ext
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

func _pack(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		out.encode_s16(i * 2, v)
	return out

func _noise(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		a[i] = rng.randf_range(-1.0, 1.0)
	return a

func _env(buf: PackedFloat32Array, attack: float, release: float) -> void:
	var n := buf.size()
	var ai := maxi(1, int(attack * SR))
	var ri := maxi(1, int(release * SR))
	for i in n:
		var g := 1.0
		if i < ai:
			g *= float(i) / ai
		if i > n - ri:
			g *= float(n - i) / ri
		buf[i] = buf[i] * g

func _lowpass(buf: PackedFloat32Array, cut: float) -> void:
	var a := clampf(cut, 0.001, 0.999)
	var prev := 0.0
	for i in buf.size():
		prev = prev + a * (buf[i] - prev)
		buf[i] = prev

func _synth(id: String) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	match id:
		# ---------------- BGM（低频氛围循环） ----------------
		"bgm_title", "bgm_menu":
			return _pack(_drone(14.0, [55.0, 82.5, 110.0, 164.5], 0.11, rng, 0.25))
		"bgm_day_class":
			return _pack(_drone(12.0, [98.0, 147.0, 196.0], 0.07, rng, 0.16))
		"bgm_unease":
			return _pack(_drone(12.0, [61.7, 92.5, 123.4, 185.0], 0.09, rng, 0.3))
		"bgm_investigate":
			return _pack(_drone(12.0, [73.4, 110.0, 146.8], 0.08, rng, 0.22))
		"bgm_rollcall":
			return _pack(_drone(10.0, [58.0, 87.0, 116.0, 232.0], 0.13, rng, 0.42))
		"bgm_horror":
			return _pack(_drone(11.0, [43.6, 65.4, 87.3, 130.8], 0.16, rng, 0.55))
		"bgm_chase":
			return _pack(_pulse_bed(10.0, 132.0, rng))
		"bgm_truth":
			return _pack(_drone(13.0, [65.4, 98.0, 130.8, 196.0], 0.10, rng, 0.3))
		"bgm_final":
			return _pack(_drone(14.0, [49.0, 73.4, 98.0, 146.8, 220.0], 0.14, rng, 0.5))
		"bgm_ending_true":
			return _pack(_drone(15.0, [65.4, 98.0, 130.8, 164.8, 196.0], 0.07, rng, 0.12))
		"bgm_ending_bad":
			return _pack(_drone(14.0, [41.2, 61.7, 82.4], 0.13, rng, 0.45))
		# ---------------- 环境音 ----------------
		"amb_classroom_day":
			return _pack(_air(10.0, 0.06, 0.035, rng))
		"amb_classroom_night":
			return _pack(_air(10.0, 0.05, 0.02, rng))
		"amb_hallway":
			return _pack(_air(10.0, 0.055, 0.012, rng))
		"amb_rain":
			return _pack(_rain(10.0, rng))
		"amb_dorm_night":
			return _pack(_air(10.0, 0.045, 0.018, rng))
		"amb_old_building":
			return _pack(_air(10.0, 0.07, 0.008, rng))
		"amb_broadcast_static":
			return _pack(_static_bed(10.0, rng))
		"amb_fire":
			return _pack(_fire(10.0, rng))
		"amb_library":
			return _pack(_air(10.0, 0.04, 0.03, rng))
		# ---------------- 音效 ----------------
		"sfx_click":
			return _pack(_click(0.05, 1400.0, rng))
		"_blip":
			return _pack(_click(0.028, 900.0, rng))
		"sfx_page":
			return _pack(_paper(0.35, rng))
		"sfx_knock_soft":
			return _pack(_knock(3, 0.34, 0.5, rng))
		"sfx_knock_hard":
			return _pack(_knock(3, 0.26, 1.0, rng))
		"sfx_knock_pattern":
			return _pack(_knock_pattern(rng))
		"sfx_door":
			return _pack(_door(1.4, rng))
		"sfx_door_slam":
			return _pack(_slam(0.6, rng))
		"sfx_broadcast_click":
			return _pack(_click(0.09, 320.0, rng))
		"sfx_broadcast_static":
			return _pack(_burst_static(1.2, rng))
		"sfx_heartbeat":
			return _pack(_heartbeat(1.1))
		"sfx_scream":
			return _pack(_scream(1.2, rng))
		"sfx_whisper":
			return _pack(_whisper(1.6, rng))
		"sfx_glass":
			return _pack(_glass(0.8, rng))
		"sfx_step":
			return _pack(_step(0.24, rng))
		"sfx_steps_run":
			return _pack(_run_steps(1.6, rng))
		"sfx_chair":
			return _pack(_chair(0.7, rng))
		"sfx_sting":
			return _pack(_sting(1.0, rng))
		"sfx_low_boom":
			return _pack(_boom(1.8))
		"sfx_water":
			return _pack(_water_drip(1.0, rng))
		"sfx_flesh":
			return _pack(_flesh(0.5, rng))
		"sfx_bell":
			return _pack(_bell(2.2))
		"sfx_write":
			return _pack(_write(0.6, rng))
		"sfx_lighter":
			return _pack(_lighter(0.5, rng))
		"sfx_fire_burst":
			return _pack(_fire_burst(1.6, rng))
		"sfx_rewind":
			return _pack(_rewind(1.0, rng))
		"sfx_breath":
			return _pack(_breath(1.4, rng))
	return PackedByteArray()

# ------- 各类合成器 -------
func _drone(dur: float, freqs: Array, amp: float, rng: RandomNumberGenerator, noise_amt: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.02)
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		var k := 0
		for f in freqs:
			var lfo := 1.0 + 0.004 * sin(TAU * (0.05 + 0.017 * k) * t)
			v += sin(TAU * float(f) * lfo * t) * amp / (1.0 + k * 0.6)
			k += 1
		v += nz[i] * noise_amt * 0.4
		# 缓慢起伏
		v *= 0.75 + 0.25 * sin(TAU * 0.037 * t)
		buf[i] = v
	_crossfade_loop(buf, 0.6)
	return buf

func _pulse_bed(dur: float, bpm: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var period := 60.0 / bpm
	var nz := _noise(n, rng)
	_lowpass(nz, 0.05)
	for i in n:
		var t := float(i) / SR
		var ph := fmod(t, period) / period
		var thump: float = exp(-ph * 14.0) * sin(TAU * 48.0 * t)
		var sub := sin(TAU * 36.7 * t) * 0.16
		buf[i] = thump * 0.5 + sub + nz[i] * 0.06
	_crossfade_loop(buf, 0.2)
	return buf

func _air(dur: float, amp: float, hum: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.012)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		buf[i] = nz[i] * amp * 6.0 + sin(TAU * 50.0 * t) * hum
	_crossfade_loop(buf, 0.5)
	return buf

func _rain(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.35)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		buf[i] = nz[i] * (0.13 + 0.03 * sin(TAU * 0.11 * t))
	# 偶发滴水
	for k in 26:
		var pos := rng.randi_range(0, n - SR / 2)
		var l := int(0.09 * SR)
		for j in l:
			if pos + j >= n:
				break
			var e: float = exp(-float(j) / l * 9.0)
			buf[pos + j] += sin(TAU * rng.randf_range(900.0, 2400.0) * float(j) / SR) * e * 0.09
	_crossfade_loop(buf, 0.4)
	return buf

func _static_bed(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var flick := 1.0 if fmod(t, 1.7) > 0.06 else 2.6
		buf[i] = nz[i] * 0.10 * flick + sin(TAU * 100.0 * t) * 0.02
	_crossfade_loop(buf, 0.3)
	return buf

func _fire(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.08)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = nz[i] * 0.22
	for k in 60:
		var pos := rng.randi_range(0, n - 400)
		var l := rng.randi_range(120, 380)
		for j in l:
			var e: float = exp(-float(j) / l * 6.0)
			buf[pos + j] += rng.randf_range(-1.0, 1.0) * e * 0.14
	_crossfade_loop(buf, 0.35)
	return buf

func _crossfade_loop(buf: PackedFloat32Array, secs: float) -> void:
	var l := mini(int(secs * SR), buf.size() / 3)
	var n := buf.size()
	for i in l:
		var a := float(i) / l
		buf[i] = buf[i] * a + buf[n - l + i] * (1.0 - a)

func _click(dur: float, freq: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		buf[i] = (sin(TAU * freq * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4) * exp(-t * 60.0)
	return buf

func _paper(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var env: float = exp(-pow((t - dur * 0.35) / (dur * 0.28), 2.0))
		buf[i] = nz[i] * env * 0.35 * (0.5 + 0.5 * sin(TAU * 7.0 * t))
	return buf

func _knock(times: int, gap: float, power: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int((gap * times + 0.5) * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for k in times:
		var pos := int(k * gap * SR)
		_add_knock(buf, pos, power, rng)
	return buf

func _knock_pattern(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# 三下，停，两下
	var n := int(2.6 * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var times := [0.0, 0.32, 0.64, 1.45, 1.78]
	for t in times:
		_add_knock(buf, int(float(t) * SR), 0.9, rng)
	return buf

func _add_knock(buf: PackedFloat32Array, pos: int, power: float, rng: RandomNumberGenerator) -> void:
	var l := int(0.22 * SR)
	for j in l:
		if pos + j >= buf.size():
			return
		var t := float(j) / SR
		var e: float = exp(-t * 34.0)
		var v := (sin(TAU * 96.0 * t) * 0.7 + sin(TAU * 187.0 * t) * 0.3 + rng.randf_range(-1.0, 1.0) * 0.35) * e
		buf[pos + j] += v * 0.85 * power

func _door(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var f := 210.0 + 130.0 * sin(TAU * 0.7 * t) + 40.0 * sin(TAU * 5.3 * t)
		var creak: float = sin(TAU * f * t) * (0.5 + 0.5 * sin(TAU * 11.0 * t))
		var env: float = sin(PI * clampf(t / dur, 0.0, 1.0))
		buf[i] = (creak * 0.22 + rng.randf_range(-1.0, 1.0) * 0.05) * env
	return buf

func _slam(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var e: float = exp(-t * 12.0)
		buf[i] = (sin(TAU * 62.0 * t) * 0.8 + rng.randf_range(-1.0, 1.0) * 0.6) * e
	return buf

func _burst_static(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.7)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		buf[i] = nz[i] * 0.3 * exp(-t * 1.6) + sin(TAU * 120.0 * t) * 0.04 * exp(-t * 3.0)
	return buf

func _heartbeat(dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		for pos in [0.0, 0.28]:
			var dt: float = t - float(pos)
			if dt >= 0.0:
				v += sin(TAU * 44.0 * dt) * exp(-dt * 16.0) * (1.0 if pos == 0.0 else 0.7)
		buf[i] = v * 0.7
	return buf

func _scream(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var f := 620.0 + 320.0 * sin(TAU * 5.5 * t) - 180.0 * t
		phase += TAU * f / SR
		var harsh := sin(phase) + 0.5 * sin(phase * 2.02) + 0.28 * sin(phase * 3.05)
		var e: float = sin(PI * clampf(t / dur, 0.0, 1.0))
		buf[i] = (harsh * 0.28 + rng.randf_range(-1.0, 1.0) * 0.12) * e
	return buf

func _whisper(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.25)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var syl: float = maxf(0.0, sin(TAU * 3.2 * t))
		buf[i] = nz[i] * syl * 0.22
	_env(buf, 0.15, 0.4)
	return buf

func _glass(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for k in 22:
		var pos := int(rng.randf_range(0.0, dur * 0.4) * SR)
		var f := rng.randf_range(1600.0, 5200.0)
		var l := int(rng.randf_range(0.06, 0.3) * SR)
		for j in l:
			if pos + j >= n:
				break
			var t := float(j) / SR
			buf[pos + j] += sin(TAU * f * t) * exp(-t * 16.0) * 0.16
	return buf

func _step(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var e: float = exp(-t * 26.0)
		buf[i] = (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 150.0 * t) * 0.5) * e * 0.5
	return buf

func _run_steps(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var t := 0.0
	while t < dur - 0.2:
		var pos := int(t * SR)
		var l := int(0.16 * SR)
		for j in l:
			if pos + j >= n:
				break
			var tt := float(j) / SR
			buf[pos + j] += (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 170.0 * tt) * 0.5) * exp(-tt * 30.0) * 0.5
		t += rng.randf_range(0.2, 0.26)
	return buf

func _chair(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var f := 320.0 + 90.0 * sin(TAU * 3.0 * t)
		buf[i] = (sin(TAU * f * t) * 0.3 + rng.randf_range(-1.0, 1.0) * 0.25) * sin(PI * clampf(t / dur, 0.0, 1.0)) * 0.6
	return buf

func _sting(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var f := 1200.0 * exp(-t * 2.0) + 90.0
		var e: float = exp(-t * 3.4)
		buf[i] = (sin(TAU * f * t) * 0.35 + rng.randf_range(-1.0, 1.0) * 0.25) * e
	return buf

func _boom(dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		buf[i] = sin(TAU * (36.0 - 12.0 * t) * t) * exp(-t * 2.2) * 0.8
	return buf

func _water_drip(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for k in 3:
		var pos := int(rng.randf_range(0.0, dur * 0.7) * SR)
		var f := rng.randf_range(1100.0, 2100.0)
		var l := int(0.13 * SR)
		for j in l:
			if pos + j >= n:
				break
			var t := float(j) / SR
			buf[pos + j] += sin(TAU * (f - 700.0 * t) * t) * exp(-t * 22.0) * 0.3
	return buf

func _flesh(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	# 湿黏的撕裂/挤压声（血腥演出用）
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.12)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var e: float = exp(-t * 5.0)
		buf[i] = (nz[i] * 1.6 + sin(TAU * 74.0 * t) * 0.25) * e * 0.55
	return buf

func _bell(dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var parts := [523.25, 659.25, 784.0, 1046.5]
	for i in n:
		var t := float(i) / SR
		var v := 0.0
		var k := 0
		for f in parts:
			v += sin(TAU * float(f) * t) * exp(-t * (1.4 + k * 0.9)) / (1.0 + k)
			k += 1
		buf[i] = v * 0.35
	return buf

func _write(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.45)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		buf[i] = nz[i] * 0.16 * maxf(0.0, sin(TAU * 9.0 * t))
	_env(buf, 0.05, 0.15)
	return buf

func _lighter(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in int(0.05 * SR):
		var t := float(i) / SR
		buf[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.7
	var pos := int(0.08 * SR)
	for j in range(pos, n):
		var t := float(j - pos) / SR
		buf[j] += rng.randf_range(-1.0, 1.0) * exp(-t * 6.0) * 0.2
	return buf

func _fire_burst(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.1)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var e: float = minf(1.0, t * 12.0) * exp(-t * 1.2)
		buf[i] = (nz[i] * 1.4 + sin(TAU * 48.0 * t) * 0.3) * e * 0.6
	return buf

func _rewind(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := 2600.0 - 1500.0 * t
		ph += TAU * f / SR
		buf[i] = (sin(ph) * 0.2 + rng.randf_range(-1.0, 1.0) * 0.18) * (0.6 + 0.4 * sin(TAU * 24.0 * t))
	_env(buf, 0.03, 0.2)
	return buf

func _breath(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * SR)
	var nz := _noise(n, rng)
	_lowpass(nz, 0.08)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / SR
		var cyc: float = maxf(0.0, sin(TAU * 0.8 * t))
		buf[i] = nz[i] * cyc * cyc * 0.5
	return buf
