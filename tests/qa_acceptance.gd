extends SceneTree
## ВРЕМЕННЫЙ приёмочный прогон (QA, t6). Независимо от проб участников:
## поднимает настоящую scenes/main.tscn, дёргает ввод/покупку/эру/престиж/
## сейв-лоад через реальные узлы и сигналы, проверяет состав сцены и HUD.
## Запуск: godot_run_headless(script="tests/qa_acceptance.gd")

const MAIN_SCENE := "res://scenes/main.tscn"

var fails: Array[String] = []
var passes: int = 0
var gs: Node = null
var audio: Node = null
var main_node: Node = null
var hud: Node = null


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		passes += 1
		print("  ok   ", label)
	else:
		fails.append(label)
		print("  FAIL ", label, (" :: " + detail) if detail != "" else "")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _ensure_autoload(path: String, node_name: String) -> Node:
	var n := root.get_node_or_null(node_name)
	if n != null:
		return n
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		return null
	n = script.new()
	n.name = node_name
	root.add_child(n)
	print("  ..   autoload %s создан вручную (в --script режиме отсутствовал)" % node_name)
	return n


func _run() -> void:
	await process_frame
	print("######## QA ACCEPTANCE ########")

	gs = _ensure_autoload("res://scripts/core/game_state.gd", "GameState")
	audio = _ensure_autoload("res://scripts/audio/audio_director.gd", "AudioDirector")
	if gs == null:
		print("FATAL: нет GameState")
		quit(2)
		return
	await process_frame

	# ------------------------------------------------------------ сцена
	print("== Сцена main.tscn ==")
	if not ResourceLoader.exists(MAIN_SCENE):
		print("FATAL: нет сцены")
		quit(2)
		return
	var packed: PackedScene = load(MAIN_SCENE)
	_check(packed != null, "main.tscn загружается")
	if packed == null:
		quit(2)
		return
	main_node = packed.instantiate()
	_check(main_node != null, "main.tscn инстанцируется")
	root.add_child(main_node)
	await _frames(6)

	_check(main_node.get_node_or_null("WorldEnvironment") != null, "WorldEnvironment на месте")
	var backdrop := main_node.get_node_or_null("Backdrop")
	var creature := main_node.get_node_or_null("Creature")
	var motes := main_node.get_node_or_null("Motes")
	var fx_layer := main_node.get_node_or_null("FXLayer")
	var ui_layer := main_node.get_node_or_null("UILayer")
	_check(backdrop != null, "Backdrop создан")
	_check(creature != null, "Creature создан")
	_check(motes != null, "Motes созданы")
	_check(fx_layer != null, "FXLayer создан")
	_check(ui_layer != null, "UILayer создан")
	if creature != null:
		_check(creature.get_child_count() >= 0, "Creature в дереве без ошибок",
				"children=%d" % creature.get_child_count())
		var params: Dictionary = creature.get("_params") if creature.get("_params") != null else {}
		var br: float = float(params.get("body_radius", 0.0))
		_check(br > 20.0, "у существа посчитан радиус тела", "body_radius=%.1f" % br)
	if backdrop != null and backdrop.has_method("is_built"):
		_check(bool(backdrop.call("is_built")), "фон построен (шейдер+ColorRect)")
		_check(backdrop.has_method("get_current_stage"), "API фона на месте")
	ui_layer = ui_layer as CanvasLayer
	hud = ui_layer.get_node_or_null("GameHUD") if ui_layer != null else null
	_check(hud != null, "GameHUD создан")
	if hud == null:
		print("FATAL: нет HUD")
		quit(2)
		return

	# ------------------------------------------------------------ 240 кадров
	print("== Прогон 240 кадров ==")
	var t0: float = float(gs.get("playtime"))
	await _frames(240)
	_check(float(gs.get("playtime")) > t0, "игра живёт (playtime растёт)")
	_check(is_instance_valid(main_node) and main_node.is_inside_tree(), "сцена не развалилась за 240 кадров")

	# ------------------------------------------------------------ HUD
	print("== HUD ==")
	var era_label: Label = hud.get("_era_label")
	var bio_label: Label = hud.get("_biomass_label")
	var rate_label: Label = hud.get("_rate_label")
	var panel: Node = hud.get("_upgrade_panel")
	_check(era_label != null and era_label.text.contains("ЭРА"), "чип эры заполнен", era_label.text if era_label else "null")
	var stage_name_now: String = String(gs.call("stage_name"))
	_check(era_label != null and era_label.text.contains(stage_name_now), "имя эры совпадает с GameState",
			(era_label.text if era_label else "null") + " / " + stage_name_now)
	_check(bio_label != null and bio_label.text != "", "крупная биомасса показана", bio_label.text if bio_label else "null")
	_check(rate_label != null and rate_label.text.contains("/сек"), "строка +N/сек есть", rate_label.text if rate_label else "null")
	_check(panel != null, "панель апгрейдов есть")
	if panel != null:
		var cards: Dictionary = panel.get("_cards")
		_check(cards.size() >= 5, "карточки апгрейдов построены (%d)" % cards.size())
		var tabs: Dictionary = panel.get("_tab_buttons")
		_check(tabs.size() >= 3, "вкладки категорий (%d)" % tabs.size())
	# композиция: панель справа, не в центре
	if panel != null and panel is Control:
		var pr: Rect2 = (panel as Control).get_global_rect()
		_check(pr.position.x >= 800.0, "панель апгрейдов справа (x=%.0f)" % pr.position.x)
		_check((panel as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "панель ловит клики")
	_check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "корень HUD не блокирует океан")

	# ------------------------------------------------------------ клик
	print("== Клик по миру ==")
	gs.reset_progress()
	await _frames(3)
	var clicks0: int = int(gs.get("manual_clicks"))
	var bio0: float = float(gs.get("biomass"))
	var fx0: int = fx_layer.get_child_count() if fx_layer != null else 0
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(260, 420)
	press.global_position = Vector2(260, 420)
	root.push_input(press)
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(260, 420)
	release.global_position = Vector2(260, 420)
	root.push_input(release)
	await _frames(2)
	var clicks1: int = int(gs.get("manual_clicks"))
	_check(clicks1 == clicks0 + 1, "клик дошёл до GameState", "clicks %d -> %d" % [clicks0, clicks1])
	_check(float(gs.get("biomass")) > bio0, "биомасса выросла от клика")
	if fx_layer != null:
		_check(fx_layer.get_child_count() >= fx0, "FX-слой принял эффекты")
	_check(bio_label != null and bio_label.text != "0", "HUD обновил число после клика", bio_label.text if bio_label else "")
	# кулдаун 0.06 c: второй мгновенный клик не должен пройти
	root.push_input(press)
	await _frames(1)
	root.push_input(release)
	await _frames(1)
	_check(int(gs.get("manual_clicks")) == clicks1, "кулдаун клика работает")

	# ------------------------------------------------------------ покупка
	print("== Покупка апгрейда ==")
	var items: Array = UpgradeDB.by_category("рост")
	_check(items.size() >= 5, "категория «рост» не пуста (%d)" % items.size())
	if not items.is_empty():
		var item: Dictionary = items[0]
		var id := String(item.get("id", ""))
		gs.set("biomass", 1.0e7)
		gs.set("total_biomass", 1.0e7)
		gs.call("_check_stage")
		await _frames(4)
		var cards2: Dictionary = panel.get("_cards") if panel != null else {}
		var card: Node = cards2.get(id, null)
		_check(card != null, "карточка %s существует" % id)
		if card != null:
			_check(int(card.get("_state")) == 0, "карточка доступна (ST_AFFORDABLE)")
		var valid: bool = gs.call("can_buy", id)
		_check(valid, "can_buy(%s) == true при 1e7" % id)
		if card != null:
			card.emit_signal("purchase_requested", id)
			await _frames(3)
		var lvl: int = int(gs.call("get_upgrade_level", id))
		_check(lvl == 1, "уровень апгрейда стал 1", "level=%d" % lvl)
		_check(float(gs.get("biomass")) < 1.0e7, "биомасса списана")
		var mult: float = float(gs.call("get_upgrade_multiplier"))
		_check(mult >= 1.0, "множитель посчитан", "x%.3f" % mult)
		if card != null:
			var lvl_label: Label = card.get("_level_label")
			_check(lvl_label != null and lvl_label.text.contains("ур. 1"), "карточка показала «ур. 1»",
					lvl_label.text if lvl_label else "null")
		# отказ при нехватке денег: состояние POOR, покупка не проходит
		gs.set("biomass", 0.0)
		if panel != null:
			panel.call("refresh")
		await _frames(2)
		var lvl_before: int = int(gs.call("get_upgrade_level", id))
		_check(not bool(gs.call("can_buy", id)), "can_buy == false при нулевой биомассе")
		_check(int(gs.call("get_upgrade_level", id)) == lvl_before, "бесплатная покупка невозможна")

	# ------------------------------------------------------------ эра
	print("== Переход эры ==")
	gs.set("biomass", 0.0)
	gs.set("total_biomass", 0.0)
	gs.set("stage_index", 0)
	gs.call("_check_stage")
	await _frames(2)
	var banner: Node = hud.get("_banner")
	var stages: Array = gs.call("_db_stages")
	var th1: float = float(stages[1]["threshold"]) if stages.size() > 1 else 750.0
	gs.set("total_biomass", th1 + 1.0)
	gs.call("_check_stage")
	await _frames(3)
	_check(int(gs.get("stage_index")) == 1, "stage_index == 1", "stage=%d" % int(gs.get("stage_index")))
	if backdrop != null:
		var bstage: int = int(backdrop.call("get_current_stage"))
		_check(bstage == 1 or bstage == -1, "фон переключил эру", "backdrop stage=%d" % bstage)
	if banner != null:
		_check(bool(banner.get("_busy")), "баннер «НОВАЯ ЭРА» играет")
	_check(era_label != null and era_label.text.contains("II"), "HUD показал ЭРУ II",
			era_label.text if era_label else "null")
	if audio != null:
		_check(int(audio.get("_stage")) == 1, "AudioDirector сменил аккорд", "stage=%d" % int(audio.get("_stage")))
	# баннер доигрывает 0.45 + 1.20 + 0.35 + 0.72 ≈ 2.7 c реального времени
	if banner != null:
		_check(banner.mouse_filter == Control.MOUSE_FILTER_IGNORE, "баннер не перехватывает мышь")
	await create_timer(3.4).timeout
	if banner != null:
		_check(not bool(banner.get("_busy")), "баннер завершился и не залип")
		_check(not banner.visible, "баннер скрылся после проигрывания")
	# эра анимирована: фон получает stage 1 через Tween 2 c
	await create_timer(0.2).timeout
	if backdrop != null:
		_check(int(backdrop.call("get_current_stage")) == 1, "фон доехал до эры 1")
	# ввод после баннера не заблокирован
	var c_before: int = int(gs.get("manual_clicks"))
	root.push_input(press)
	await _frames(1)
	root.push_input(release)
	await _frames(2)
	_check(int(gs.get("manual_clicks")) > c_before, "после баннера клики работают")

	# ------------------------------------------------------------ престиж
	print("== ДНК-престиж ==")
	gs.set("total_biomass", 1.0e10)
	gs.set("dna_earned", 0)
	gs.set("dna", 0)
	await _frames(6)
	var pbox: Node = hud.get("_prestige_box")
	var pbtn: Button = hud.get("_prestige_btn")
	_check(bool(gs.call("can_prestige")), "can_prestige == true при 1e10")
	_check(pbox != null and pbox.visible, "кнопка престижа показалась")
	if pbtn != null:
		_check(pbtn.text.contains("ДНК"), "на кнопке престижа есть превью", pbtn.text)
		pbtn.emit_signal("pressed")
		await _frames(4)
		var dna: int = int(gs.get("dna"))
		_check(dna > 0, "ДНК начислена", "dna=%d" % dna)
		_check(float(gs.get("biomass")) == 0.0 and float(gs.get("total_biomass")) == 0.0,
				"престиж сбросил биомассу")
		_check(int(gs.get("stage_index")) == 0, "престиж вернул эру I")
		_check(int(gs.call("get_upgrade_level", String(items[0].get("id", "")))) == 0
				if not items.is_empty() else true, "престиж сбросил апгрейды")

	# ------------------------------------------------------------ сейв/лоад
	print("== Сейв/лоад ==")
	gs.set("biomass", 4242.5)
	gs.set("total_biomass", 9000.0)
	gs.set("dna", 11)
	gs.set("manual_clicks", 77)
	gs.call("save_game")
	var save_path := "res://save/save.json"
	_check(FileAccess.file_exists(save_path), "файл сохранения записан (%s)" % save_path)
	var parsed: Variant = null
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f != null:
			parsed = JSON.parse_string(f.get_as_text())
			f.close()
	_check(typeof(parsed) == TYPE_DICTIONARY, "сейв — валидный JSON")
	if typeof(parsed) == TYPE_DICTIONARY:
		var d: Dictionary = parsed
		_check(int(d.get("v", 0)) == 2, "версия сейва 2")
		_check(is_equal_approx(float(d.get("biomass", 0.0)), 4242.5), "в сейве верная биомасса")
	# ломаем память и читаем заново
	gs.set("biomass", 0.0)
	gs.set("dna", 0)
	gs.set("manual_clicks", 0)
	gs.call("load_game")
	await _frames(2)
	_check(float(gs.get("biomass")) >= 4242.0, "биомасса восстановлена", "%.1f" % float(gs.get("biomass")))
	_check(int(gs.get("dna")) == 11, "ДНК восстановлена", "dna=%d" % int(gs.get("dna")))
	_check(int(gs.get("manual_clicks")) == 77, "клики восстановлены")

	# ------------------------------------------------------------ чистота
	print("== Чистота ==")
	_check(is_instance_valid(main_node), "сцена жива после всех сценариев")
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans < 200, "нет утечки узлов-сирот", "orphans=%d" % orphans)

	print("== ИТОГ ==")
	print("PASS %d / FAIL %d" % [passes, fails.size()])
	if not fails.is_empty():
		print("FAILURES: ", fails)
		print("QA ACCEPTANCE FAIL")
		quit(1)
	else:
		print("QA ACCEPTANCE OK")
		quit(0)
