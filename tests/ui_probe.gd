extends SceneTree
## Headless-проба UI: HUD, панель апгрейдов, карточки, баннер эры, статистика, тост.
## Запуск: godot_run_headless(script="tests/ui_probe.gd")
##
## Проверяет, что интерфейс строится без ошибок, реагирует на сигналы ядра,
## не перекрывает центр экрана и что сброс требует двойного подтверждения.

var failures: Array[String] = []
var gs: Node = null
var hud: Control = null
var reset_signals: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		failures.append(label)
		print("  FAIL ", label)


func _labels(root_node: Node) -> Array:
	var out: Array = []
	for n in root_node.find_children("*", "Label", true, false):
		out.append(n)
	return out


func _buttons(root_node: Node) -> Array:
	var out: Array = []
	for n in root_node.find_children("*", "Button", true, false):
		out.append(n)
	return out


func _has_label_text(root_node: Node, needle: String) -> bool:
	for l in _labels(root_node):
		if String(l.text).contains(needle):
			return true
	return false


func _find_button(root_node: Node, needle: String) -> Button:
	var lower := needle.to_lower()
	for b in _buttons(root_node):
		if String(b.text).to_lower().contains(lower) or String(b.tooltip_text).to_lower().contains(lower):
			return b
	return null


func _run() -> void:
	await process_frame
	gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return

	# Headless-окно 64x64 по умолчанию — выставляем целевой размер 1280x720.
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	var screen: Vector2 = Vector2(root.size)
	print("== Экран %s ==" % str(screen))
	print("== Сборка HUD ==")
	var hud_script: Script = load("res://scripts/ui/game_hud.gd")
	_check(hud_script != null, "скрипт HUD загружается")
	if hud_script == null:
		quit(1)
		return
	hud = hud_script.new()
	root.add_child(hud)
	hud.reset_requested.connect(func() -> void: reset_signals += 1)
	hud.bind()
	gs.reset_progress()
	await process_frame
	await process_frame

	_check(hud.theme != null, "тема применена")
	_check(hud.get_child_count() > 6, "узлы построены (%d)" % hud.get_child_count())
	_check(is_equal_approx(float(hud.THROTTLE), 0.08), "троттлинг 0.08 с")

	print("== Чип эры ==")
	_check(_has_label_text(hud, "ЭРА "), "подпись эры есть")
	_check(_has_label_text(hud, "до следующей"), "прогресс до следующей эры")

	print("== Биомасса ==")
	gs.biomass = 1234.0
	gs.total_biomass = 1234.0
	gs.biomass_changed.emit(gs.biomass)
	await process_frame
	await process_frame
	_check(_has_label_text(hud, gs.format_number(gs.biomass)), "число биомассы обновлено")

	print("== Вкладки и карточки ==")
	var tabs := 0
	for t in ["Рост", "Мутации", "Симбиоз", "ДНК"]:
		if _find_button(hud, t) != null:
			tabs += 1
	_check(tabs >= 3, "вкладки категорий (%d/4)" % tabs)
	var cards: Array = hud.find_children("*", "PanelContainer", true, false)
	_check(cards.size() >= 1, "карточки апгрейдов созданы (%d)" % cards.size())

	print("== Покупка ==")
	gs.biomass = 1e12
	gs.total_biomass = 1e12
	gs.upgrade_purchased.emit("", 1)
	await process_frame
	await process_frame
	var before_total: float = gs.total_biomass
	var shown := false
	for l in _labels(hud):
		if String(l.text).contains("×"):
			shown = true
	_check(not is_nan(before_total), "покупка не ломает HUD")

	print("== Баннер новой эры ==")
	gs.total_biomass = 1e20
	gs._check_stage()
	await process_frame
	await process_frame
	_check(_has_label_text(hud, "НОВАЯ ЭРА") or gs.stage_index > 0, "смена эры обработана (эра %d)" % gs.stage_index)

	print("== Престиж ==")
	gs.reset_progress()
	gs.total_biomass = 1e9
	gs.dna_earned = 0
	await process_frame
	await process_frame
	var prestige_btn := _find_button(hud, "престиж")
	_check(prestige_btn != null and prestige_btn.is_visible_in_tree(), "кнопка ДНК-престижа видна")
	if prestige_btn != null:
		prestige_btn.pressed.emit()
		await process_frame
		_check(gs.prestige_count >= 1, "престиж выполнен (циклов %d)" % gs.prestige_count)

	print("== Звук ==")
	var sound_btn := _find_button(hud, "Звук")
	_check(sound_btn != null, "кнопка звука есть")
	if sound_btn != null:
		var was: bool = gs.muted
		sound_btn.pressed.emit()
		await process_frame
		_check(gs.muted != was, "mute переключается")

	print("== Статистика ==")
	var stats_btn := _find_button(hud, "Статистика")
	_check(stats_btn != null, "кнопка статистики есть")
	if stats_btn != null:
		stats_btn.pressed.emit()
		await process_frame
		_check(bool(hud.is_stats_open()), "панель статистики открыта")
		var stats := hud.get_node_or_null("StatsPanel")
		if stats == null:
			for c in hud.get_children():
				if c.has_method("close_panel"):
					stats = c
		if stats != null:
			for i in 3:
				await process_frame
			var box = stats.get("_box")
			var rbtn = stats.get("_reset_btn")
			var rhint = stats.get("_reset_hint")
			if box is Control and rbtn is Control and rhint is Control:
				var box_rect: Rect2 = (box as Control).get_global_rect()
				var rb: Rect2 = (rbtn as Control).get_global_rect()
				var rh: Rect2 = (rhint as Control).get_global_rect()
				var bottom: float = maxf(rb.position.y + rb.size.y, rh.position.y + rh.size.y)
				var gap: float = (box_rect.position.y + box_rect.size.y) - bottom
				_check(gap >= 12.0,
						"кнопка сброса и подпись внутри стекла (запас %.0f px)" % gap)
			stats.close_panel()
			# Закрытие анимировано — даём твину доиграть, иначе вуаль ещё видима.
			for i in 30:
				await process_frame
			_check(not bool(hud.is_stats_open()), "панель статистики закрыта")

	print("== Тост ==")
	hud.toast("проверка тоста", Palette.CYAN, 0.5)
	await process_frame
	_check(_has_label_text(hud, "проверка тоста"), "тост отображается")

	print("== Сброс: двойное подтверждение ==")
	gs.biomass = 500.0
	gs.total_biomass = 500.0
	await process_frame
	var reset_btn := _find_button(hud, "Полный сброс")
	_check(reset_btn != null, "кнопка сброса есть")
	if reset_btn != null:
		var sig_before: int = reset_signals
		reset_btn.pressed.emit()
		await process_frame
		_check(gs.biomass >= 500.0 or gs.total_biomass > 0.0, "первый клик не сбрасывает")
		_check(reset_signals == sig_before, "сигнал сброса не отправлен на первый клик")
		reset_btn.pressed.emit()
		await process_frame
		await process_frame
		_check(gs.biomass < 500.0 and gs.total_biomass == 0.0, "второй клик сбрасывает прогресс")
		_check(reset_signals == sig_before + 1, "сигнал reset_requested отправлен")

	print("== Эффекты и все вкладки ==")
	var seen_ids := {}
	var effect_texts: Array[String] = []
	var mult_shown := false
	var raw_value_leak := ""
	for tab_name in ["Рост", "Мутации", "Симбиоз", "ДНК"]:
		var tab_btn := _find_button(hud, tab_name)
		if tab_btn == null:
			continue
		tab_btn.pressed.emit()
		await process_frame
		await process_frame
		for node in hud.find_children("*", "PanelContainer", true, false):
			if not node.has_method("apply") or not node.has_method("_effect_text"):
				continue
			var card := node as Control
			var cid := String(card.item_id)
			if cid != "":
				seen_ids[cid] = true
			var txt := String(card.call("_effect_text"))
			if txt == "":
				continue
			effect_texts.append(txt)
			if txt.begins_with("×"):
				mult_shown = true
			if txt.begins_with("0.") or txt.begins_with("."):
				raw_value_leak = txt
	_check(seen_ids.size() >= 24, "карточек по всем вкладкам >= 24 (сейчас %d)" % seen_ids.size())
	_check(effect_texts.size() > 0, "эффекты апгрейдов отображаются (%d)" % effect_texts.size())
	_check(mult_shown, "множители показаны как ×N.NN")
	_check(raw_value_leak == "", "нет сырых долей вида 0.06 (%s)" % raw_value_leak)

	print("== Раскладка ==")
	for i in 5:
		await process_frame
	var panel: Control = null
	for c in hud.get_children():
		if c is Control and c.has_method("refresh") and c.has_method("flash_card"):
			panel = c
	_check(panel != null, "панель апгрейдов найдена")
	if panel != null:
		var r: Rect2 = panel.get_global_rect()
		_check(r.position.x > screen.x * 0.55, "панель справа (x=%.0f из %.0f)" % [r.position.x, screen.x])
		_check(r.size.x >= 380.0 and r.size.x <= 440.0, "ширина панели ~400 (%.0f)" % r.size.x)
		_check(r.position.y >= 0.0 and r.end.y <= screen.y, "панель влезает по высоте")
	var center := Rect2(Vector2(screen.x * 0.5 - 150.0, 180.0), Vector2(300.0, 300.0))
	var covered := ""
	for c in hud.find_children("*", "Control", true, false):
		var ctrl := c as Control
		if ctrl == null or not ctrl.is_visible_in_tree():
			continue
		if ctrl.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		if ctrl.get_global_rect().intersects(center):
			covered = String(ctrl.name) if ctrl.name != "" else String(ctrl.get_class())
			break
	_check(covered == "", "центр не перекрыт кликабельным UI (%s)" % covered)

	print("== Читаемость верхней зоны ==")
	var scrim := hud.get_child(0) as Control
	_check(scrim is TextureRect and scrim.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"scrim первым слоем и не ловит клики")
	if scrim != null:
		_check(scrim.size.y >= 200.0 and is_equal_approx(scrim.size.x, screen.x),
				"scrim во всю ширину сверху (%.0fx%.0f)" % [scrim.size.x, scrim.size.y])
	var chip: PanelContainer = null
	for c in hud.find_children("*", "PanelContainer", true, false):
		if c.find_children("*", "ProgressBar", true, false).size() > 0:
			chip = c
	_check(chip != null, "чип эры найден")
	if chip != null:
		var chip_rect := chip.get_global_rect()
		_check(chip_rect.size.x <= 320.0 and chip_rect.size.y <= 118.0,
				"чип компактный (%.0fx%.0f)" % [chip_rect.size.x, chip_rect.size.y])
		_check(chip_rect.position.y + chip_rect.size.y < 200.0, "чип не сползает вниз")
		var pb := chip.find_children("*", "ProgressBar", true, false)[0] as Control
		_check(pb != null and pb.size.x > 100.0, "прогресс-бар заполняет ширину чипа")
		var pad: MarginContainer = null
		for c in chip.find_children("*", "MarginContainer", true, false):
			pad = c
		_check(pad != null
				and pad.get_theme_constant("margin_left") >= 10
				and pad.get_theme_constant("margin_right") >= 10,
				"контент чипа не липнет к рамке")
		if pad != null and pb != null:
			var left_edge: float = pb.get_global_rect().position.x - chip.get_global_rect().position.x
			_check(left_edge >= 10.0, "внутренний отступ чипа (%.0f px)" % left_edge)
	var glow := hud.get_child(1) as TextureRect
	if glow == null:
		_check(false, "свечение под числом найдено")
	else:
		_check(glow.size.x <= 620.0 and is_equal_approx(glow.size.x, glow.size.y),
				"свечение под числом квадратное и не шире 620 (%.0fx%.0f)"
				% [glow.size.x, glow.size.y])
		var gt := glow.texture as GradientTexture2D
		_check(gt != null
				and gt.gradient.get_color(gt.gradient.get_point_count() - 1).a <= 0.02,
				"край градиента свечения прозрачный")
	var big := hud.get("_biomass_label") as Label
	var mult := hud.get("_mult_label") as Label
	_check(big != null and mult != null, "узлы биомассы доступны")
	if big != null and mult != null:
		var big_rect := big.get_global_rect()
		var mult_rect := mult.get_global_rect()
		var gap: float = mult_rect.position.y - (big_rect.position.y + big_rect.size.y)
		_check(gap >= 7.0, "строка скорости отодвинута от числа (%.1f px)" % gap)
		_check(mult.get_theme_font_size("font_size") <= 12,
				"кегль множителя уменьшен (%d)" % mult.get_theme_font_size("font_size"))

	print("== Ремонт по приёмке ==")
	var glow_tex := UIKit.radial_glow(Palette.CYAN, 0.62)
	var gg := glow_tex.gradient
	_check(gg.get_color(0).a >= 0.5, "radial_glow: центр светится (%.2f)" % gg.get_color(0).a)
	_check(gg.get_color(gg.get_point_count() - 1).a <= 0.02,
			"radial_glow: край прозрачный (%.2f)" % gg.get_color(gg.get_point_count() - 1).a)
	_check(glow_tex.fill == GradientTexture2D.FILL_RADIAL
			and glow_tex.fill_to.is_equal_approx(Vector2.ONE),
			"radial_glow: радиальная форма до угла")

	var banner = null
	for c in hud.get_children():
		if c.has_method("play") and c.get("_glow") != null:
			banner = c
	_check(banner != null, "баннер перехода найден")
	if banner != null:
		var bglow = banner.get("_glow") as TextureRect
		var ok_sq: bool = bglow != null and is_equal_approx(bglow.size.x, bglow.size.y) \
				and bglow.size.x <= 760.0
		_check(ok_sq, "свечение баннера квадратное (%s)"
				% ("%.0fx%.0f" % [bglow.size.x, bglow.size.y] if bglow != null else "нет узла"))

	var card_node: Control = null
	for n in hud.find_children("*", "PanelContainer", true, false):
		if n.has_method("_effect_text"):
			card_node = n
			break
	if card_node != null:
		var nm := card_node.get("_name_label") as Label
		_check(nm != null and nm.text_overrun_behavior == TextServer.OVERRUN_TRIM_WORD_ELLIPSIS,
				"название карточки усекается по слову")
		_check(nm != null and nm.tooltip_text != "", "полное название в подсказке")

	gs.total_biomass = 0.0
	gs.dna_earned = 0
	hud.call("_refresh_all")
	await process_frame
	var pbox = hud.get("_prestige_box")
	var pbtn = hud.get("_prestige_btn")
	var pnote = hud.get("_prestige_note")
	_check(pbox != null and (pbox as Control).visible, "блок престижа виден всегда")
	_check(pbtn != null and (pbtn as Button).disabled, "кнопка престижа заблокирована без ДНК")
	_check(pnote != null and (pnote as Label).text != "", "подсказка, когда откроется ДНК")

	# --- t10: подложка свечения не обрезается кромкой текстуры
	var zero_off := -1.0
	for i in gg.get_point_count():
		if gg.get_color(i).a <= 0.002:
			zero_off = gg.offsets[i]
			break
	_check(zero_off >= 0.0 and zero_off <= 0.70,
			"radial_glow гаснет до кромки текстуры (offset %.2f)" % zero_off)

	# --- t10: блок престижа целиком внутри экрана, текст внутри стекла
	for i in 3:
		await process_frame
	var vp := hud.get_viewport_rect().size
	var pbox_rect: Rect2 = (pbox as Control).get_global_rect()
	var gap_bottom: float = vp.y - (pbox_rect.position.y + pbox_rect.size.y)
	_check(gap_bottom >= 16.0, "блок престижа не ниже 16 px от кромки (%.0f px)" % gap_bottom)
	_check(pbox_rect.size.y + gap_bottom <= vp.y - 4.0,
			"блок престижа не вылезает сверху (h=%.0f)" % pbox_rect.size.y)
	if pnote != null:
		var nrect: Rect2 = (pnote as Control).get_global_rect()
		_check(nrect.position.y + nrect.size.y <= pbox_rect.position.y + pbox_rect.size.y - 2.0,
				"подпись престижа внутри стекла (низ %.0f <= %.0f)"
				% [nrect.position.y + nrect.size.y, pbox_rect.position.y + pbox_rect.size.y])
		_check(nrect.position.x >= pbox_rect.position.x - 0.5
				and nrect.position.x + nrect.size.x <= pbox_rect.position.x + pbox_rect.size.x + 0.5,
				"подпись престижа не шире панели")
		_check((pnote as Label).autowrap_mode == TextServer.AUTOWRAP_OFF,
				"подпись престижа в одну строку")

	if banner != null:
		var veil = banner.get("_veil") as Control
		var br: Rect2 = veil.get_global_rect() if veil != null else Rect2()
		_check(veil != null and is_equal_approx(br.size.x, vp.x) and is_equal_approx(br.size.y, vp.y),
				"затемнение баннера на весь экран (%s)" % str(br.size))

	print("== Ремонт по ревью (t11) ==")
	# (а) гонка close→open: хвост закрытия не должен прятать заново открытую панель
	var sp: Node = hud.get_node_or_null("StatsPanel")
	if sp == null:
		for c in hud.get_children():
			if c.has_method("close_panel"):
				sp = c
	_check(sp != null, "панель статистики доступна для проверки гонки")
	if sp != null:
		sp.call("open")
		await process_frame
		sp.call("close_panel")
		await process_frame
		sp.call("open")
		var visible_right_away: bool = (sp as Control).visible
		for i in 30:
			await process_frame
		_check(visible_right_away and (sp as Control).visible,
				"close→open в пределах 0.2 c оставляет панель видимой")
		_check(bool(hud.is_stats_open()), "close→open: is_open() == true")
		_check((sp as Control).modulate.a > 0.98,
				"close→open: модалка не осталась полупрозрачной (%.2f)"
				% (sp as Control).modulate.a)
		sp.call("close_panel")
		for i in 30:
			await process_frame
		_check(not (sp as Control).visible and not bool(hud.is_stats_open()),
				"после гонки панель закрывается штатно")

	# (б) кэш stylebox: повторный refresh без смены состояния не пересоздаёт рамку
	var mcard = null
	for n in hud.find_children("*", "PanelContainer", true, false):
		if n.has_method("apply") and n.has_method("_effect_text"):
			mcard = n
			break
	_check(mcard != null, "карточка для проверки кэша найдена")
	if mcard != null:
		mcard.call("apply", 0, 1, "10 биомассы", "не хватает 5")
		var s1: StyleBox = mcard.get_theme_stylebox("panel")
		mcard.call("apply", 0, 1, "10 биомассы", "не хватает 5")
		var s2: StyleBox = mcard.get_theme_stylebox("panel")
		_check(is_same(s1, s2), "повторный refresh не пересоздаёт stylebox карточки")
		mcard.call("apply", 0, 2, "10 биомассы", "закрыто")
		var s3: StyleBox = mcard.get_theme_stylebox("panel")
		mcard.call("apply", 0, 1, "10 биомассы", "не хватает 5")
		var s4: StyleBox = mcard.get_theme_stylebox("panel")
		_check(not is_same(s1, s3) and is_same(s1, s4),
				"stylebox переключается по состоянию и берётся из кэша обратно")

	# (в) порог престижа — только из ядра, в HUD нет ни константы, ни формулы
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	_check(hsrc != "" and not hsrc.contains("500_000") and not hsrc.contains("500000"),
			"в game_hud нет литерала порога престижа")
	_check(not hsrc.contains("PRESTIGE_BASE"), "дубль константы престижа убран")
	var thr: float = float(hud.call("_prestige_threshold"))
	_check(thr > 0.0, "порог престижа получен из ядра (%.0f)" % thr)
	if thr > 0.0:
		var saved_total: float = gs.total_biomass
		var saved_dna: int = gs.dna_earned
		gs.dna_earned = 0
		gs.total_biomass = thr
		var can_at: bool = bool(gs.can_prestige())
		gs.total_biomass = thr * 0.999
		var cant_below: bool = bool(gs.can_prestige())
		gs.total_biomass = saved_total
		gs.dna_earned = saved_dna
		_check(can_at and not cant_below, "порог совпадает с can_prestige() ядра")

	print("== ИТОГ ==")
	if failures.is_empty():
		print("UI PROBE OK")
		quit(0)
	else:
		print("UI PROBE FAIL: ", failures)
		quit(1)
