extends Node
## AudioDirector — автолоад процедурного звука «Эволюции».
##
## Всё синтезируется в рантайме, никаких внешних ассетов:
##   * эмбиент — AudioStreamGenerator 22050 Гц: тёплые пэды (синус + мягкая
##     вторая гармоника), медленные LFO-«дыхания», однополюсный фильтр,
##     аккорд на каждую эру с плавным кроссфейдом, тихий «океан» из
##     отфильтрованного шума и редкие колокольчики с эхом;
##   * SFX — AudioStreamWAV из PCM (click / buy / stage_up / prestige)
##     с атакой-затуханием и мягким лимитером.
##
## API (контракт): play_click / play_buy / play_stage_up / play_prestige /
## set_stage / set_muted / is_muted.
##
## Безопасность: в headless-режиме и без звукового устройства ничего не
## падает — генератор просто не заполняется, а API остаётся рабочим.

# ---------------------------------------------------------------- константы

const SAMPLE_RATE := 22050
const DT := 1.0 / 22050.0
const BUFFER_LENGTH := 0.2
const MASTER_LEVEL := 0.30
const SFX_POOL_SIZE := 8

## Плавность смены эры: за сколько секунд гаснут старые ноты и вступают новые.
const CROSSFADE_TIME := 3.4
const VOICE_CAP := 10
const BELL_CAP := 3
const DELAY_TIME := 0.42
const DELAY_FEEDBACK := 0.34
const MUTE_FADE := 0.18
const MUTE_POLL := 0.3

## Аккорды эр (MIDI-ноты). Низкий регистр, открытые квинты — «дорого и спокойно».
const STAGE_CHORDS := [
	[45, 57, 64, 69],        # I   — ля минор, открытая квинта
	[50, 57, 65, 69],        # II  — ре минор
	[43, 55, 62, 67],        # III — соль мажор
	[48, 55, 64, 72],        # IV  — до мажор
	[41, 53, 60, 69],        # V   — фа мажор
	[46, 58, 65, 70],        # VI  — си-бемоль
	[43, 59, 62, 67, 71],    # VII — соль с секундой
	[45, 57, 60, 64, 71],    # VIII— ля минор add9
	[50, 57, 62, 69],        # IX  — ре с квартой
	[48, 55, 59, 64, 67],    # X   — до мажор add9, «разрешение»
]

# ---------------------------------------------------------------- состояние

var _muted := false
var _gain := 1.0
var _gain_target := 1.0
var _stage := -1
var _headless := false
var _voices_ready := false
var _frames := PackedVector2Array()
var _fill_capacity := 2048

# генератор
var _ambient: AudioStreamPlayer = null
var _pad_coef := 0.33
var _ts := 0.0
var _rng := RandomNumberGenerator.new()

# голоса пэда (параллельные массивы — горячий путь без словарей/аллокаций)
var _v_freq := PackedFloat32Array()
var _v_amp := PackedFloat32Array()
var _v_target := PackedFloat32Array()
var _v_phase := PackedFloat32Array()
var _v_lfo := PackedFloat32Array()
var _v_lfo_rate := PackedFloat32Array()

# колокольчики
var _b_freq := PackedFloat32Array()
var _b_amp := PackedFloat32Array()
var _b_phase := PackedFloat32Array()
var _b_decay := PackedFloat32Array()
var _bell_timer := 6.0

# эхо
var _delay := PackedFloat32Array()
var _delay_i := 0

# фильтры
var _pad_lp := 0.0
var _noise_lp := 0.0
var _noise_lp2 := 0.0
var _swell := 0.6

# SFX
var _sfx: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0

# GameState
var _gs: Node = null
var _gs_has_muted := false
var _mute_poll := 0.0


# ---------------------------------------------------------------- жизненный цикл

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_headless = DisplayServer.get_name() == "headless"
	_init_synth()
	_init_ambient()
	_init_sfx_pool()
	_build_sfx()
	_bind_game_state()
	set_stage(0)


func _process(delta: float) -> void:
	_gain = move_toward(_gain, _gain_target, delta / MUTE_FADE)
	_poll_mute(delta)
	# В мьюте синтез не крутим впустую — буфер дозаполнится за кадр-два.
	if _gain <= 0.0001 and _gain_target <= 0.0:
		return
	# Медленное «дыхание» тембра пэда — считается раз в кадр, а не на сэмпл.
	_pad_coef = 0.30 + 0.09 * sin(_ts * 0.05)
	_update_bells(delta)
	if _headless or _ambient == null:
		return
	var playback := _ambient.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var available := playback.get_frames_available()
	if available <= 0:
		return
	var count: int = mini(available, _fill_capacity)
	_frames.resize(count)
	for i in count:
		_frames[i] = _synth_frame()
	playback.push_buffer(_frames)


func _init_synth() -> void:
	_v_freq.resize(VOICE_CAP)
	_v_amp.resize(VOICE_CAP)
	_v_target.resize(VOICE_CAP)
	_v_phase.resize(VOICE_CAP)
	_v_lfo.resize(VOICE_CAP)
	_v_lfo_rate.resize(VOICE_CAP)
	_b_freq.resize(BELL_CAP)
	_b_amp.resize(BELL_CAP)
	_b_phase.resize(BELL_CAP)
	_b_decay.resize(BELL_CAP)
	_delay.resize(int(SAMPLE_RATE * DELAY_TIME))


func _init_ambient() -> void:
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "Ambient"
	_ambient.volume_db = 0.0
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = BUFFER_LENGTH
	_ambient.stream = gen
	add_child(_ambient)
	_ambient.play()


func _init_sfx_pool() -> void:
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		add_child(player)
		_sfx_players.append(player)


func _bind_game_state() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	_gs = gs
	for prop in gs.get_property_list():
		if String(prop.get("name", "")) == "muted":
			_gs_has_muted = true
			break
	if _gs_has_muted:
		_muted = bool(gs.get("muted"))
		_gain = 0.0 if _muted else 1.0
		_gain_target = _gain
	if gs.has_signal("stage_changed"):
		var cb := Callable(self, "_on_game_state_stage")
		if not gs.is_connected("stage_changed", cb):
			gs.connect("stage_changed", cb)


func _poll_mute(delta: float) -> void:
	_mute_poll -= delta
	if _mute_poll > 0.0:
		return
	_mute_poll = MUTE_POLL
	if _gs == null:
		_bind_game_state()
		return
	if not _gs_has_muted or not is_instance_valid(_gs):
		return
	var remote := bool(_gs.get("muted"))
	if remote != _muted:
		_apply_mute(remote, false)


func _on_game_state_stage(index: int) -> void:
	set_stage(index)


# ---------------------------------------------------------------- публичный API

func play_click() -> void:
	_play_sfx("click", -6.0, _rng.randf_range(0.97, 1.05))


func play_buy() -> void:
	_play_sfx("buy", -3.0, _rng.randf_range(0.99, 1.02))


func play_stage_up() -> void:
	_play_sfx("stage_up", -2.0, 1.0)


func play_prestige() -> void:
	_play_sfx("prestige", -1.0, 1.0)


## Смена аккорда/настроения под эру 0..9: старые голоса гаснут, новые вступают
## кроссфейдом CROSSFADE_TIME — без щелчков и без обрыва звука.
func set_stage(index: int) -> void:
	var idx: int = clampi(index, 0, STAGE_CHORDS.size() - 1)
	if idx == _stage and _voices_ready:
		return
	_stage = idx
	_voices_ready = true
	for i in VOICE_CAP:
		_v_target[i] = 0.0
	var chord: Array = STAGE_CHORDS[idx]
	for note in chord:
		_assign_voice(float(note))
	# Колокольчики берут ноты текущего аккорда — настроение эры слышно и в них.
	_bell_timer = minf(_bell_timer, _rng.randf_range(5.0, 11.0))
	_swell = 0.6


func set_muted(m: bool) -> void:
	_apply_mute(m, true)


func is_muted() -> bool:
	return _muted


## Диагностика для headless-пробы: размеры буферов и активные голоса.
func get_debug_state() -> Dictionary:
	var active := 0
	for i in VOICE_CAP:
		if _v_amp[i] > 0.001:
			active += 1
	return {
		"stage": _stage,
		"muted": _muted,
		"headless": _headless,
		"active_voices": active,
		"sfx": _sfx.keys(),
		"sample_rate": SAMPLE_RATE,
	}


func _apply_mute(m: bool, push_to_state: bool) -> void:
	_muted = m
	_gain_target = 0.0 if m else 1.0
	if m:
		for player in _sfx_players:
			player.stop()
	if push_to_state and _gs != null and _gs_has_muted and is_instance_valid(_gs):
		_gs.set("muted", m)


# ---------------------------------------------------------------- синтез: аккорды и колокольчики

func _midi_to_freq(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


func _assign_voice(note: float) -> void:
	var slot := -1
	var quietest := -1
	var quiet_amp := 1e9
	for i in VOICE_CAP:
		if _v_target[i] <= 0.0 and _v_amp[i] <= 0.001:
			slot = i
			break
		if _v_amp[i] < quiet_amp:
			quiet_amp = _v_amp[i]
			quietest = i
	if slot < 0:
		slot = quietest if quietest >= 0 else 0
		_v_amp[slot] = 0.0
	_v_freq[slot] = _midi_to_freq(note)
	_v_target[slot] = 1.0
	_v_phase[slot] = _rng.randf_range(0.0, TAU)
	_v_lfo[slot] = _rng.randf_range(0.0, TAU)
	_v_lfo_rate[slot] = _rng.randf_range(0.18, 0.5)


func _update_bells(delta: float) -> void:
	_bell_timer -= delta
	if _bell_timer > 0.0:
		return
	_bell_timer = _rng.randf_range(9.0, 19.0)
	_spawn_bell()


func _spawn_bell() -> void:
	if _stage < 0:
		return
	var chord: Array = STAGE_CHORDS[_stage]
	var note := float(chord[_rng.randi_range(0, chord.size() - 1)]) + 24.0
	if _rng.randf() < 0.35:
		note += 7.0
	var slot := 0
	var quiet_amp := 1e9
	for i in BELL_CAP:
		if _b_amp[i] < quiet_amp:
			quiet_amp = _b_amp[i]
			slot = i
	_b_freq[slot] = _midi_to_freq(note)
	_b_amp[slot] = _rng.randf_range(0.05, 0.085)
	_b_phase[slot] = 0.0
	_b_decay[slot] = _rng.randf_range(0.8, 1.25)


# ---------------------------------------------------------------- синтез: горячий путь

func _synth_frame() -> Vector2:
	_ts += DT
	var fade: float = DT / CROSSFADE_TIME

	# --- пэд: медленно дышащие голоса с мягкой второй гармоникой
	var pad := 0.0
	for i in VOICE_CAP:
		var amp := _v_amp[i]
		var target := _v_target[i]
		if amp < target:
			amp = minf(amp + fade, target)
		elif amp > target:
			amp = maxf(amp - fade, target)
		if amp <= 0.0001:
			if target <= 0.0:
				_v_amp[i] = 0.0
				continue
			amp = 0.0001
		_v_amp[i] = amp
		var phase := _v_phase[i] + _v_freq[i] * DT
		if phase >= TAU:
			phase -= TAU
		_v_phase[i] = phase
		var lfo := _v_lfo[i] + _v_lfo_rate[i] * DT
		if lfo >= TAU:
			lfo -= TAU
		_v_lfo[i] = lfo
		var breathe := 0.74 + 0.26 * sin(lfo)
		pad += (sin(phase) + 0.16 * sin(phase + phase)) * amp * breathe
	pad *= 0.22
	_pad_lp += (pad - _pad_lp) * _pad_coef

	# --- «океан»: два каскада однополюсного ФНЧ по шуму + очень медленный прилив
	var noise := _rng.randf_range(-1.0, 1.0)
	_noise_lp += (noise - _noise_lp) * 0.085
	_noise_lp2 += (_noise_lp - _noise_lp2) * 0.085
	_swell = 0.45 + 0.32 * sin(_ts * 0.29) + 0.23 * sin(_ts * 0.087 + 1.7)

	# --- колокольчики
	var bell := 0.0
	for i in BELL_CAP:
		var bamp := _b_amp[i]
		if bamp <= 0.00005:
			continue
		bamp = maxf(bamp - bamp * DT * _b_decay[i], 0.0)
		_b_amp[i] = bamp
		var bph := _b_phase[i] + _b_freq[i] * DT
		if bph >= TAU:
			bph -= TAU
		_b_phase[i] = bph
		bell += (sin(bph) + 0.3 * sin(bph + bph)) * bamp

	# --- эхо (одна линия задержки с обратной связью — «дорогой» хвост)
	var delayed := _delay[_delay_i]
	_delay[_delay_i] = bell + delayed * DELAY_FEEDBACK
	_delay_i += 1
	if _delay_i >= _delay.size():
		_delay_i = 0

	var mix := (_pad_lp * 0.85 + _noise_lp2 * 1.25 * _swell + bell + delayed * 0.55) * MASTER_LEVEL * _gain
	# Мягкий лимитер: tanh почти линеен на тихом сигнале и не даёт клиппинга.
	var s := tanh(mix * 1.2) * 0.9
	var pan := sin(_ts * 0.23) * 0.07
	return Vector2(s * (1.0 + pan), s * (1.0 - pan))


# ---------------------------------------------------------------- SFX

func _play_sfx(key: String, volume_db: float, pitch: float) -> void:
	if _muted or _sfx_players.is_empty():
		return
	var stream: AudioStream = _sfx.get(key, null)
	if stream == null:
		return
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _build_sfx() -> void:
	_sfx["click"] = _wav_from(_sfx_click())
	_sfx["buy"] = _wav_from(_chime([523.25, 659.25, 784.0], 0.055, 0.012, 0.17, 0.55, 0.42))
	_sfx["stage_up"] = _wav_from(_chime([392.0, 523.25, 659.25, 784.0], 0.09, 0.24, 0.42, 1.7, 0.36))
	_sfx["prestige"] = _wav_from(_chime([261.63, 329.63, 392.0, 523.25, 659.25, 783.99], 0.11, 0.38, 0.62, 2.3, 0.30))


func _sfx_click() -> PackedFloat32Array:
	var n := int(SAMPLE_RATE * 0.13)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var f1 := 660.0
	var f2 := 990.0
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var env := _env(t, 0.004, 0.045)
		if env <= 0.0001:
			continue
		var v := (sin(TAU * f1 * t) + 0.45 * sin(TAU * f2 * t)) * env * 0.5
		buf[i] = v
	return buf


## Мягкий «колокольчик»: несколько нот со сдвигом, атака-затухание,
## фундаментал + тихая вторая и третья гармоники.
func _chime(freqs: Array, stagger: float, attack: float, decay: float,
		duration: float, gain: float) -> PackedFloat32Array:
	var n := int(SAMPLE_RATE * duration)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for k in freqs.size():
		var f: float = float(freqs[k])
		var start: float = float(k) * stagger
		for i in n:
			var t := float(i) / float(SAMPLE_RATE) - start
			if t < 0.0:
				continue
			var env := _env(t, attack, decay)
			if env <= 0.0001:
				continue
			var v := sin(TAU * f * t) + 0.22 * sin(TAU * f * 2.0 * t) + 0.06 * sin(TAU * f * 3.0 * t)
			buf[i] += v * env * gain
	return buf


func _env(t: float, attack: float, decay: float) -> float:
	if t < 0.0:
		return 0.0
	var a := maxf(attack, 0.0005)
	if t < a:
		return t / a
	return exp(-(t - a) / maxf(decay, 0.0005))


func _wav_from(buf: PackedFloat32Array) -> AudioStreamWAV:
	var n := buf.size()
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	# Короткий релиз в конце: обрезанный хвост не должен щёлкать.
	var release: int = mini(n, int(SAMPLE_RATE * 0.006))
	var lp := 0.0
	for i in n:
		var x := buf[i]
		if i >= n - release:
			x *= float(n - 1 - i) / float(release)
		# Мягкий ФНЧ убирает цифровую резкость, лимитер — клиппинг.
		lp += (x - lp) * 0.55
		var v := tanh(lp * 1.05)
		pcm.encode_s16(i * 2, int(round(clampf(v, -1.0, 1.0) * 32000.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	return wav
