extends SceneTree
## Headless-смоук ядра: экономика, апгрейды, эры, престиж, сейв/лоад.
## Запуск: godot_run_headless(script="tests/smoke_test.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		failures.append(label)
		print("  FAIL ", label)


func _run() -> void:
	await process_frame
	var gs := root.get_node_or_null("GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return

	print("== DB ==")
	var items: Array = gs._db_items()
	var stages: Array = gs._db_stages()
	_check(items.size() >= 20, "апгрейдов >= 20 (сейчас %d)" % items.size())
	_check(stages.size() == 10, "эр ровно 10 (сейчас %d)" % stages.size())

	print("== Экономика ==")
	gs.reset_progress()
	for i in 40:
		gs.tap(Vector2.ZERO)
	_check(gs.biomass > 0.0, "клики дают биомассу")
	var rate0: float = gs.get_rate()

	print("== Покупка ==")
	if items.is_empty():
		print("FAIL: нет апгрейдов")
		quit(1)
		return
	var first: Dictionary = items[0]
	var id := String(first.get("id", ""))
	gs._levels.clear()
	gs.biomass = 1e12
	gs.total_biomass = 1e12
	var ok: bool = gs.buy_upgrade(id)
	_check(ok, "покупка %s" % id)
	_check(gs.get_upgrade_level(id) == 1, "уровень апгрейда = 1")
	_check(gs.get_upgrade_cost(id) > float(first.get("base_cost", 0.0)), "цена растёт")

	print("== Эры ==")
	gs.total_biomass = 0.0
	gs.stage_index = 0
	gs._levels.clear()
	gs.biomass = 1e15
	var before: int = gs.stage_index
	gs._check_stage()
	_check(gs.stage_index >= 0, "стадия вычисляется")
	gs.stage_index = 0
	gs.total_biomass = 1e20
	gs._check_stage()
	_check(gs.stage_index == 9, "потолок эр = 9 (сейчас %d)" % gs.stage_index)

	print("== Престиж ==")
	gs.total_biomass = 1e9
	gs.dna_earned = 0
	var preview: int = gs.prestige_gain_preview()
	_check(preview > 0, "превью ДНК > 0 (%d)" % preview)
	var gained: int = gs.do_prestige()
	_check(gained > 0 and gs.dna >= gained, "престиж начислил ДНК")
	_check(gs.biomass == 0.0 and gs.total_biomass == 0.0, "престиж сбросил биомассу")

	print("== Форматирование ==")
	_check(gs.format_number(999) == "999", "999")
	_check(gs.format_number(1500).contains("тыс"), "1500 -> тыс")
	_check(gs.format_number(2_500_000).contains("млн"), "2.5e6 -> млн")

	print("== Сейв/лоад ==")
	gs.biomass = 4242.0
	gs.dna = 7
	gs.save_game()
	gs.biomass = 0.0
	gs.dna = 0
	gs.load_game()
	_check(is_equal_approx(gs.biomass, 4242.0) or gs.biomass > 4242.0, "биомасса восстановлена")
	_check(gs.dna == 7, "ДНК восстановлена")

	print("== ИТОГ ==")
	if failures.is_empty():
		print("SMOKE OK")
		quit(0)
	else:
		print("SMOKE FAIL: ", failures)
		quit(1)
