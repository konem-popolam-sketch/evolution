extends SceneTree
## Временная headless-проба контента (Лайт): схемы, диапазоны, монотонность, баланс.
## Запуск: godot_run_headless(script="tests/content_probe.gd"). В конце quit().

const UPGRADE_DB_PATH := "res://scripts/core/upgrade_db.gd"
const EVOLUTION_DB_PATH := "res://scripts/core/evolution_db.gd"

const ITEM_KEYS := ["id", "name", "desc", "category", "icon", "currency", "base_cost",
	"cost_growth", "value", "effect", "max_level", "unlock_stage", "unlock_total", "color"]
const STAGE_KEYS := ["index", "name", "subtitle", "threshold", "color_a", "color_b",
	"accent", "glow", "creature"]
const CREATURE_KEYS := ["body_radius", "lobes", "tentacles", "tentacle_len", "eyes",
	"tail", "fins", "spikes", "translucency"]
const EFFECTS := ["ps_add", "ps_mult", "click_add", "click_mult", "all_mult", "auto_click"]
const CATS := ["рост", "мутации", "симбиоз", "днк"]

var _fails: Array[String] = []

func _initialize() -> void:
	var u_script: Script = load(UPGRADE_DB_PATH)
	var e_script: Script = load(EVOLUTION_DB_PATH)
	if u_script == null or e_script == null:
		print("FAIL: не загрузились скрипты БД")
		quit(1)
		return
	var u: Object = u_script.new()
	var e: Object = e_script.new()

	var items: Array = u.call("all")
	var stages: Array = e.call("all")

	_check_upgrades(u, items)
	_check_evolution(e, stages)
	_balance_snapshot(items, stages)
	_simulate_run(items, stages)

	if _fails.is_empty():
		print("PROBE OK: %d апгрейдов, %d эр — схемы, диапазоны и инварианты соблюдены"
			% [items.size(), stages.size()])
		quit(0)
	else:
		for f in _fails:
			print("FAIL: ", f)
		print("PROBE FAILED: %d проблем" % _fails.size())
		quit(1)


func _fail(msg: String) -> void:
	_fails.append(msg)


func _check_upgrades(u: Object, items: Array) -> void:
	if items.size() < 24:
		_fail("апгрейдов %d < 24" % items.size())
	if int(u.call("count")) != items.size():
		_fail("UpgradeDB.count() расходится с all().size()")

	var ids := {}
	var per_cat := {}
	for i in items.size():
		var it: Dictionary = items[i]
		var tag := "%d/%s" % [i, String(it.get("id", "?"))]
		for k in ITEM_KEYS:
			if not it.has(k):
				_fail("%s: нет поля %s" % [tag, k])
		if it.size() != ITEM_KEYS.size():
			_fail("%s: лишние поля (ожидалось %d, есть %d)" % [tag, ITEM_KEYS.size(), it.size()])

		var id := String(it.get("id", ""))
		if id.is_empty():
			_fail("%s: пустой id" % tag)
		elif ids.has(id):
			_fail("%s: дубликат id" % tag)
		ids[id] = true
		if String(it.get("name", "")).is_empty():
			_fail("%s: пустое имя" % tag)
		if String(it.get("desc", "")).is_empty():
			_fail("%s: пустое описание" % tag)
		if String(it.get("icon", "")).is_empty():
			_fail("%s: пустая иконка" % tag)

		var cat := String(it.get("category", ""))
		if not CATS.has(cat):
			_fail("%s: неизвестная категория '%s'" % [tag, cat])
		per_cat[cat] = int(per_cat.get(cat, 0)) + 1

		var cur := String(it.get("currency", ""))
		if cur != "biomass" and cur != "dna":
			_fail("%s: валюта '%s'" % [tag, cur])
		if cat == "днк" and cur != "dna":
			_fail("%s: категория днк должна быть за ДНК" % tag)
		if cat != "днк" and cur != "biomass":
			_fail("%s: обычная категория должна быть за биомассу" % tag)

		var eff := String(it.get("effect", ""))
		if not EFFECTS.has(eff):
			_fail("%s: неизвестный эффект '%s'" % [tag, eff])
		var value := float(it.get("value", 0.0))
		if eff == "ps_add" or eff == "click_add" or eff == "auto_click":
			if value <= 0.0:
				_fail("%s: аддитивный эффект с value<=0" % tag)
		elif eff == "ps_mult" or eff == "click_mult" or eff == "all_mult":
			# value — прирост долей за уровень: 0.12 = ×1.12 (GameState: pow(1+value, level))
			if value <= 0.0 or value > 1.0:
				_fail("%s: множитель value вне (0; 1] (%f)" % [tag, value])

		if float(it.get("base_cost", 0.0)) <= 0.0:
			_fail("%s: base_cost<=0" % tag)
		var growth := float(it.get("cost_growth", 1.0))
		if growth < 1.05 or growth > 3.2:
			_fail("%s: cost_growth вне 1.05..3.2 (%f)" % [tag, growth])
		if int(it.get("max_level", 0)) < 1:
			_fail("%s: max_level<1" % tag)
		var us := int(it.get("unlock_stage", 0))
		if us < 0 or us > 8:
			_fail("%s: unlock_stage вне 0..8 (%d)" % [tag, us])
		if float(it.get("unlock_total", 0.0)) < 0.0:
			_fail("%s: unlock_total<0" % tag)
		if typeof(it.get("color")) != TYPE_COLOR:
			_fail("%s: color не Color" % tag)

	for c in CATS:
		if int(per_cat.get(c, 0)) < 3:
			_fail("категория '%s' слишком бедная: %d" % [c, int(per_cat.get(c, 0))])

	# Проверка выборок.
	if u.call("by_id", "photosynthesis").is_empty():
		_fail("by_id не находит photosynthesis")
	if not u.call("by_id", "no_such_id").is_empty():
		_fail("by_id на несуществующем id вернул не пусто")
	if (u.call("by_category", "рост") as Array).size() < 3:
		_fail("by_category('рост') пуст")
	# Без GameState (headless) вкладка «днк» не показывается.
	var cats: Array = u.call("categories")
	if cats.size() != 3:
		_fail("categories() без престижа вернул %d вкладок" % cats.size())


func _check_evolution(e: Object, stages: Array) -> void:
	if stages.size() != 10:
		_fail("эр %d, ожидалось 10" % stages.size())
	if int(e.call("count")) != 10:
		_fail("EvolutionDB.count() != 10")
	if int(e.call("all").size()) != stages.size():
		_fail("all() размер нестабилен")

	var prev_threshold := -1.0
	var prev := {}
	for i in stages.size():
		var st: Dictionary = stages[i]
		var tag := "%d/%s" % [i, String(st.get("name", "?"))]
		for k in STAGE_KEYS:
			if not st.has(k):
				_fail("%s: нет поля %s" % [tag, k])
		if int(st.get("index", -1)) != i:
			_fail("%s: index != позиция" % tag)
		if String(st.get("name", "")).is_empty() or String(st.get("subtitle", "")).is_empty():
			_fail("%s: пустое имя/подпись" % tag)
		var th := float(st.get("threshold", -1.0))
		if i == 0 and th != 0.0:
			_fail("%s: порог первой эры должен быть 0" % tag)
		if th <= prev_threshold:
			_fail("%s: порог не растёт (%f <= %f)" % [tag, th, prev_threshold])
		prev_threshold = th
		for ck in ["color_a", "color_b", "accent", "glow"]:
			if typeof(st.get(ck)) != TYPE_COLOR:
				_fail("%s: %s не Color" % [tag, ck])

		var cr: Dictionary = st.get("creature", {})
		for k in CREATURE_KEYS:
			if not cr.has(k):
				_fail("%s: в creature нет %s" % [tag, k])
		if cr.size() != CREATURE_KEYS.size():
			_fail("%s: лишние ключи creature" % tag)

		var r := float(cr.get("body_radius", 0.0))
		if r < 40.0 or r > 120.0:
			_fail("%s: body_radius вне 40..120 (%f)" % [tag, r])
		var lobes := int(cr.get("lobes", 0))
		if lobes < 1 or lobes > 7:
			_fail("%s: lobes вне 1..7 (%d)" % [tag, lobes])
		var tent := int(cr.get("tentacles", 0))
		if tent < 0 or tent > 14:
			_fail("%s: tentacles вне 0..14 (%d)" % [tag, tent])
		var tl := float(cr.get("tentacle_len", 0.0))
		if tl < 0.3 or tl > 2.2:
			_fail("%s: tentacle_len вне 0.3..2.2 (%f)" % [tag, tl])
		var eyes := int(cr.get("eyes", 0))
		if eyes < 0 or eyes > 4:
			_fail("%s: eyes вне 0..4 (%d)" % [tag, eyes])
		var tail := float(cr.get("tail", 0.0))
		if tail < 0.0 or tail > 1.0:
			_fail("%s: tail вне 0..1 (%f)" % [tag, tail])
		var fins := int(cr.get("fins", 0))
		if fins < 0 or fins > 4:
			_fail("%s: fins вне 0..4 (%d)" % [tag, fins])
		var spikes := int(cr.get("spikes", 0))
		if spikes < 0 or spikes > 20:
			_fail("%s: spikes вне 0..20 (%d)" % [tag, spikes])
		var tr := float(cr.get("translucency", -1.0))
		if tr < 0.0 or tr > 1.0:
			_fail("%s: translucency вне 0..1 (%f)" % [tag, tr])

		# Плавность: шаг формы между эрами не больше 20%.
		if not prev.is_empty():
			if r < float(prev["body_radius"]) or r > float(prev["body_radius"]) * 1.2:
				_fail("%s: body_radius не монотонен/скачок" % tag)
			if lobes < int(prev["lobes"]):
				_fail("%s: lobes убывают" % tag)
			if tent < int(prev["tentacles"]):
				_fail("%s: tentacles убывают" % tag)
			if eyes < int(prev["eyes"]):
				_fail("%s: eyes убывают" % tag)
			if fins < int(prev["fins"]):
				_fail("%s: fins убывают" % tag)
			if spikes < int(prev["spikes"]):
				_fail("%s: spikes убывают" % tag)
			if tl < float(prev["tentacle_len"]):
				_fail("%s: tentacle_len убывает" % tag)
			if tail < float(prev["tail"]):
				_fail("%s: tail убывает" % tag)
			if tr > float(prev["translucency"]):
				_fail("%s: translucency растёт" % tag)
		prev = cr.duplicate()

	# stage_at / next_threshold / get_stage.
	if int(e.call("stage_at", 0.0)) != 0:
		_fail("stage_at(0) != 0")
	if int(e.call("stage_at", 59.0)) != 0:
		_fail("stage_at(59) != 0")
	if int(e.call("stage_at", 60.0)) != 1:
		_fail("stage_at(60) != 1")
	if int(e.call("stage_at", 1.0e12)) != 9:
		_fail("stage_at(огромное) != 9")
	if float(e.call("next_threshold", 9)) != 0.0:
		_fail("next_threshold(последняя) != 0")
	if float(e.call("next_threshold", 0)) != 60.0:
		_fail("next_threshold(0) != 60")
	if int(e.call("get_stage", -5).get("index", -1)) != 0:
		_fail("get_stage(-5) не зажат в 0")
	if int(e.call("get_stage", 99).get("index", -1)) != 9:
		_fail("get_stage(99) не зажат в 9")

	var mid: Dictionary = e.call("lerp_creature", 0, 9, 0.5)
	for k in CREATURE_KEYS:
		if not mid.has(k):
			_fail("lerp_creature потерял %s" % k)
	var r0 := float(e.call("get_stage", 0).get("creature").get("body_radius"))
	var r9 := float(e.call("get_stage", 9).get("creature").get("body_radius"))
	var rm := float(mid.get("body_radius", -1.0))
	if rm <= r0 or rm >= r9:
		_fail("lerp_creature: середина вне диапазона (%f)" % rm)


func _simulate_run(items: Array, stages: Array) -> void:
	## Первый забег «с нуля», математика 1:1 как в GameState._recalc().
	## Игрок кликает 2 раза/сек (расслабленный темп) и жадно берёт самый дешёвый
	## доступный апгрейд. Свип по масштабу порогов эр показывает, где баланс
	## даёт ровный темп без стен.
	print("--- БАЛАНС: свип масштаба порогов эр (2 клика/сек, жадные покупки) ---")
	var scales := [1.0, 10.0, 30.0, 100.0, 300.0, 1000.0]
	for s in scales:
		var res := _run(items, stages, float(s), false)
		var last: Variant = res["times"][stages.size() - 1]
		var line := "  ×%-6.0f " % float(s)
		if last == null:
			line += "10-я эра не достигнута за 6 ч"
		else:
			line += "10-я эра %6.1f мин |" % (float(last) / 60.0)
			for i in range(1, stages.size()):
				var t: Variant = res["times"][i]
				if t == null:
					line += " —"
				else:
					line += " %4.1f" % (float(t) / 60.0)
		print(line)
	var final := _run(items, stages, 1.0, true)
	for i in stages.size():
		var t: Variant = final["times"][i]
		var line := "  %d %-12s" % [i, String(stages[i]["name"])]
		if t == null:
			print(line + " не достигнута за 6 ч")
		else:
			print(line + " %6.1f мин" % (float(t) / 60.0))
	print("  покупок: %d, апгрейдов в работе: %d" % [final["buys"], final["working"]])
	if final["times"][stages.size() - 1] == null:
		_fail("симуляция: последняя эра не достигнута за 6 часов — возможна стена")
		return
	# Темп: каждая эра не дольше 20 минут, весь забег — 15…70 минут.
	var prev_t := 0.0
	for i in range(1, stages.size()):
		var t: float = float(final["times"][i])
		var dur := t - prev_t
		prev_t = t
		if dur > 20.0 * 60.0:
			_fail("эра %d тянется %.1f мин — стена" % [i, dur / 60.0])
	var total := prev_t / 60.0
	if total < 15.0:
		_fail("забег слишком быстрый: %.1f мин" % total)
	if total > 70.0:
		_fail("забег слишком долгий: %.1f мин" % total)


func _num(v: float) -> String:
	if v >= 1.0e9:
		return "%.1fB" % (v / 1.0e9)
	if v >= 1.0e6:
		return "%.1fM" % (v / 1.0e6)
	if v >= 1.0e3:
		return "%.1fK" % (v / 1.0e3)
	return "%.1f" % v


func _run(items: Array, stages: Array, scale: float, verbose: bool) -> Dictionary:
	var level := {}
	var total := 0.0
	var elapsed := 0.0
	var dt := 0.2
	var clicks_per_sec := 2.0
	var stage_time := []
	stage_time.resize(stages.size())
	stage_time[0] = 0.0
	var stage_i := 0
	var buys := 0
	while elapsed < 3600.0 * 6.0 and stage_i < stages.size() - 1:
		var ps_add := 0.0
		var ps_mult := 1.0
		var click_add := 0.0
		var click_mult := 1.0
		var all_mult := 1.0
		var auto := 0.0
		for it in items:
			var lv := int(level.get(it["id"], 0))
			if lv <= 0:
				continue
			var value := float(it["value"])
			match String(it["effect"]):
				"ps_add":
					ps_add += value * lv
				"ps_mult":
					ps_mult *= pow(1.0 + value, lv)
				"click_add":
					click_add += value * lv
				"click_mult":
					click_mult *= pow(1.0 + value, lv)
				"all_mult":
					all_mult *= pow(1.0 + value, lv)
				"auto_click":
					auto += value * lv
		var rate := ps_add * ps_mult * all_mult
		rate += auto * (1.0 + click_add) * click_mult * all_mult
		var click := maxf(1.0, 1.0 + click_add) * click_mult * all_mult
		total += (rate + click * clicks_per_sec) * dt
		elapsed += dt

		while stage_i < stages.size() - 1 and total >= float(stages[stage_i + 1]["threshold"]) * scale:
			stage_i += 1
			stage_time[stage_i] = elapsed
			if verbose:
				print("      [%s] доход %s/сек, клик %s" % [
					String(stages[stage_i]["name"]), _num(rate), _num(click)])

		# жадная покупка: самый дешёвый доступный апгрейд
		var best_id := ""
		var best_cost := INF
		for it in items:
			var id := String(it["id"])
			var lv := int(level.get(id, 0))
			if lv >= int(it["max_level"]):
				continue
			# первый забег идёт без ДНК: днк-ветка недоступна
			if String(it["currency"]) != "biomass":
				continue
			if stage_i < int(it["unlock_stage"]):
				continue
			if total < float(it["unlock_total"]):
				continue
			var cost := float(it["base_cost"]) * pow(float(it["cost_growth"]), float(lv))
			if cost <= total and cost < best_cost:
				best_cost = cost
				best_id = id
		if best_id != "":
			total -= best_cost
			level[best_id] = int(level.get(best_id, 0)) + 1
			buys += 1
	return {"times": stage_time, "buys": buys, "working": level.size()}


func _balance_snapshot(items: Array, stages: Array) -> void:
	print("--- БАЛАНС: каталог ---")
	for cat in CATS:
		var n := 0
		for it in items:
			if String(it["category"]) == cat:
				n += 1
		print("  %-8s %d апгрейдов" % [cat, n])
	print("--- БАЛАНС: первые цены (мягкий старт) ---")
	for id in ["tentacle", "photosynthesis", "plankton", "cytoplasm", "cilia"]:
		for it in items:
			if String(it["id"]) == id:
				print("  %-14s %6.0f %s" % [id, float(it["base_cost"]), String(it["name"])])
	print("--- БАЛАНС: эры ---")
	for i in stages.size():
		var st: Dictionary = stages[i]
		var th := float(st["threshold"])
		var ratio := 0.0
		if i > 0:
			ratio = th / float(stages[i - 1]["threshold"])
		print("  %d %-12s порог %14.0f  шаг ×%.1f" % [i, String(st["name"]), th, ratio])
