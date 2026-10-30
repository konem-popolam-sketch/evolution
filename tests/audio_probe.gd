extends SceneTree
## Headless-проба модуля audio: API, синтез, мьют, SFX-буферы.
## Запуск: godot_run_headless(script="tests/audio_probe.gd")
## Завершается через quit(); код 0 — все проверки прошли.

var _fails: Array[String] = []


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		print("  FAIL ", label)
		_fails.append(label)


func _initialize() -> void:
	# Автолоады получают _ready только когда root войдёт в дерево, поэтому
	# все проверки — в отложенной корутине, после первого кадра.
	_run.call_deferred()


func _run() -> void:
	await process_frame
	print("=== AUDIO PROBE ===")

	var ad: Node = root.get_node_or_null("AudioDirector")
	if ad == null:
		print("  note: автолоад не активен, создаём AudioDirector вручную")
		var script: GDScript = load("res://scripts/audio/audio_director.gd")
		ad = script.new()
		ad.name = "AudioDirector"
		root.add_child(ad)
		await process_frame
	_check(ad != null, "AudioDirector существует")

	# --- API из контракта
	for method in ["play_click", "play_buy", "play_stage_up", "play_prestige",
			"set_stage", "set_muted", "is_muted"]:
		_check(ad.has_method(method), "метод %s" % method)

	# --- SFX сгенерированы из PCM
	var state: Dictionary = ad.get_debug_state()
	_check(int(state["sample_rate"]) == 22050, "частота эмбиента 22050")
	var sfx_keys: Array = state["sfx"]
	for key in ["click", "buy", "stage_up", "prestige"]:
		_check(sfx_keys.has(key), "SFX %s сгенерирован" % key)
		var stream: AudioStream = ad._sfx.get(key, null)
		if stream is AudioStreamWAV:
			var wav: AudioStreamWAV = stream
			_check(wav.data.size() > 2000, "SFX %s: PCM %d байт" % [key, wav.data.size()])
			_check(wav.format == AudioStreamWAV.FORMAT_16_BITS, "SFX %s: 16 bit" % key)
			var last: int = wav.data.decode_s16(wav.data.size() - 2)
			_check(absi(last) < 300, "SFX %s: хвост без щелчка (%.0f)" % [key, float(last)])
		else:
			_check(false, "SFX %s: AudioStreamWAV" % key)

	# --- смена эр: аккорд всегда назначается, без падения
	for i in range(-2, 12):
		ad.set_stage(i)
		var st: Dictionary = ad.get_debug_state()
		var expect: int = clampi(i, 0, 9)
		_check(int(st["stage"]) == expect, "set_stage(%d) -> %d" % [i, expect])

	# --- синтез: 22050 кадров (1 c), значения конечные и в пределах лимитера
	var peak := 0.0
	var bad := 0
	for i in 22050:
		var frame: Vector2 = ad._synth_frame()
		var m: float = maxf(absf(frame.x), absf(frame.y))
		peak = maxf(peak, m)
		if not is_finite(frame.x) or not is_finite(frame.y) or m > 1.2:
			bad += 1
	_check(bad == 0, "синтез: нет NaN/клиппинга (плохих кадров %d)" % bad)
	_check(peak > 0.0005, "синтез: сигнал не тишина (пик %.4f)" % peak)
	_check(peak < 1.0, "синтез: мягкий лимитер держит уровень (пик %.4f)" % peak)
	_check(int(ad.get_debug_state()["active_voices"]) >= 4, "синтез наполняет голоса пэда (%d)" % int(ad.get_debug_state()["active_voices"]))

	# --- бюджет CPU и установившийся уровень (3 с = почти полный кроссфейд)
	var t0 := Time.get_ticks_usec()
	var steady_peak := 0.0
	for i in 66150:
		var fr: Vector2 = ad._synth_frame()
		steady_peak = maxf(steady_peak, maxf(absf(fr.x), absf(fr.y)))
	var per_sec_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 3.0
	print("  info: синтез 1 с аудио = %.1f мс CPU (%.1f%% реального времени)" % [
		per_sec_ms, per_sec_ms / 10.0])
	print("  info: установившийся пик эмбиента %.3f" % steady_peak)
	_check(per_sec_ms < 350.0, "синтез укладывается в бюджет CPU (%.1f мс/с)" % per_sec_ms)
	_check(steady_peak > 0.02, "эмбиент слышимый, но тихий (пик %.3f)" % steady_peak)
	_check(steady_peak < 0.6, "эмбиент не клиппирует (пик %.3f)" % steady_peak)

	# --- реальный путь заполнения генератора (dummy-драйвер в headless)
	var was_headless: bool = ad._headless
	ad._headless = false
	var playback = ad._ambient.get_stream_playback() if ad._ambient != null else null
	if playback is AudioStreamGeneratorPlayback:
		var before: int = playback.get_frames_available()
		for i in 8:
			ad._process(0.016)
		_check(playback.get_frames_available() < before, "буфер генератора заполняется push_buffer")
	else:
		print("  skip push_buffer — playback недоступен без устройства")
	ad._headless = was_headless

	# --- мьют: гейн уходит в 0, звук становится тишиной
	ad.set_muted(true)
	_check(ad.is_muted(), "is_muted() == true после set_muted(true)")
	for i in 60:
		ad._process(0.05)
	var peak_muted := 0.0
	for i in 512:
		var frame2: Vector2 = ad._synth_frame()
		peak_muted = maxf(peak_muted, maxf(absf(frame2.x), absf(frame2.y)))
	_check(peak_muted < 0.0005, "мьют глушит эмбиент (пик %.6f)" % peak_muted)
	# SFX в мьюте не играют — просто не должны падать
	ad.play_click()
	ad.play_buy()
	ad.play_stage_up()
	ad.play_prestige()
	ad.set_muted(false)
	_check(not ad.is_muted(), "is_muted() == false после set_muted(false)")
	for i in 60:
		ad._process(0.05)
	var peak_back := 0.0
	for i in 512:
		var frame3: Vector2 = ad._synth_frame()
		peak_back = maxf(peak_back, maxf(absf(frame3.x), absf(frame3.y)))
	_check(peak_back > 0.0005, "звук возвращается после снятия мьюта (пик %.4f)" % peak_back)

	# --- плавность: смена эры не даёт щелчков (сравниваем с обычным наклоном волны)
	ad.set_stage(7)
	for i in 33075:
		ad._synth_frame()
	var steady_jump := 0.0
	var p1 := 0.0
	for i in 22050:
		var fs: Vector2 = ad._synth_frame()
		steady_jump = maxf(steady_jump, absf(fs.x - p1))
		p1 = fs.x
	ad.set_stage(2)
	var fade_jump := 0.0
	var p2 := p1
	for i in 33075:
		var ff: Vector2 = ad._synth_frame()
		fade_jump = maxf(fade_jump, absf(ff.x - p2))
		p2 = ff.x
	print("  info: макс. скачок волны — фон %.4f, при смене эры %.4f" % [steady_jump, fade_jump])
	_check(fade_jump <= maxf(steady_jump * 1.35, 0.02),
		"кроссфейд эры без щелчков (%.4f vs фон %.4f)" % [fade_jump, steady_jump])

	ad._spawn_bell()
	var bell_ok := true
	var bell_peak := 0.0
	var prev2 := p2
	for i in 8820:
		var fr5: Vector2 = ad._synth_frame()
		if not is_finite(fr5.x) or not is_finite(fr5.y):
			bell_ok = false
		bell_peak = maxf(bell_peak, absf(fr5.x))
		bell_ok = bell_ok and absf(fr5.x - prev2) < maxf(steady_jump * 2.0, 0.05)
		prev2 = fr5.x
	_check(bell_ok, "колокольчик с эхом звучит без щелчков/NaN")
	_check(bell_peak > 0.05, "колокольчик слышен на фоне пэда (пик %.3f)" % bell_peak)

	# --- синхронизация с GameState.muted (если автолоад уже есть)
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null and gs.get("muted") != null:
		ad.set_muted(true)
		_check(bool(gs.get("muted")) == true, "set_muted пишет GameState.muted")
		gs.set("muted", false)
		for i in 12:
			ad._process(0.05)
		_check(not ad.is_muted(), "AudioDirector подхватывает GameState.muted")
		ad.set_muted(false)
	else:
		print("  skip GameState.muted — автолоада ещё нет (капитан пишет параллельно)")

	# --- SFX-плееры в пуле, повторные вызовы не создают узлов
	var child_count := ad.get_child_count()
	ad.play_click()
	ad.play_click()
	ad.play_buy()
	_check(ad.get_child_count() == child_count, "пул SFX не растёт при игре")

	print("=== AUDIO PROBE RESULT: %s (%d fail) ===" % [
		"PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	quit(0 if _fails.is_empty() else 1)
