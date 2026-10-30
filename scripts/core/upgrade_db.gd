class_name UpgradeDB
extends RefCounted
## Каталог апгрейдов «Эволюции»: 31 запись в 4 категориях.
##
## СХЕМА ЗАПИСИ (ровно эти поля, по контракту):
##   id:String, name:String, desc:String, category:String, icon:String,
##   currency:"biomass"|"dna", base_cost:float, cost_growth:float, value:float,
##   effect:String, max_level:int, unlock_stage:int, unlock_total:float, color:Color
##
## СЕМАНТИКА ЭФФЕКТОВ (level = текущий уровень, 0 = не куплен):
##   "ps_add"      пассив: rate   += value * level
##   "ps_mult"     пассив: rate   *= pow(1.0 + value, level)
##   "click_add"   клик:   click  += value * level
##   "click_mult"  клик:   click  *= pow(1.0 + value, level)
##   "all_mult"    оба:    rate и click *= pow(1.0 + value, level)
##   "auto_click"  авто-клики: auto += value * level (кликов/сек, каждый на силу клика)
##   У множителей value — ПРИРОСТ за уровень долей: 0.06 = «×1.06 за уровень»,
##   полный итог (1 + value)^level. Ровно так считает GameState._recalc().
##
## ЦЕНА: cost(level) = base_cost * pow(cost_growth, level) — как в
##   GameState.get_upgrade_cost(); округления нет, форматирование на стороне UI.
##   Апгрейд доступен, если level < max_level, total_biomass >= unlock_total
##   и stage_index >= unlock_stage. «днк» покупаются за ДНК и НЕ сбрасываются.
##
## БАЛАНС (проверен симуляцией первого забега, tests/content_probe.gd):
##   * потолок дохода первого забега ограничен по построению: суммарный
##     клик-урон ≈ 6·10³, авто-клики ≈ 28/сек, пассив ≈ 12·10³/сек до
##     множителей — поэтому «квадратичный» разгон авто×клик исключён;
##   * авто-клики умышленно дешёвые по количеству (0.2…3/сек за уровень):
##     они множатся на силу клика, и большие значения взрывали бы баланс;
##   * множители — редкие и дорогие (рост цены ×2.0…×2.8, 5…8 уровней):
##     каждый уровень ощутим, но следующий стоит заметно дороже, стены нет;
##   * аддитивные ветки — рабочая лошадка: линейный рост при цене ×1.15…×1.19;
##   * ранний рост мягкий: первый апгрейд 15 биомассы (+0.5/сек), первый
##     клик-апгрейд 20 (+1 к клику) — первые полминуты без простоя;
##   * ДНК-ветка — мета-прогресс (до ×4 за ветку за престиж), заметно
##     ускоряет следующий забег, но не отменяет первый.

## Палитра подключается явно (preload), а не через глобальное имя Palette:
## так файл компилируется даже до первой генерации global_script_class_cache
## (свежий клон, headless-прогон, CI). Семантика цветов — та же палитра игры.
const P := preload("res://scripts/core/palette.gd")

const CAT_GROWTH := "рост"
const CAT_MUTATION := "мутации"
const CAT_SYMBIOSIS := "симбиоз"
const CAT_DNA := "днк"

static var _items: Array = []

## Полный список апгрейдов. Массив общий — только для чтения.
static func all() -> Array:
	if _items.is_empty():
		_build()
	return _items


## Апгрейд по id; пустой словарь, если такого нет.
static func by_id(id: String) -> Dictionary:
	var items := all()
	for i in items.size():
		var it: Dictionary = items[i]
		if String(it["id"]) == id:
			return it
	return {}


## Апгрейды одной категории (в порядке объявления).
static func by_category(cat: String) -> Array:
	var out: Array = []
	var items := all()
	for i in items.size():
		var it: Dictionary = items[i]
		if String(it["category"]) == cat:
			out.append(it)
	return out


## Вкладки панели. «днк» появляется только после первого престижа —
## проверяем GameState без жёсткой зависимости на этапе компиляции.
static func categories() -> Array:
	var cats: Array = [CAT_GROWTH, CAT_MUTATION, CAT_SYMBIOSIS]
	if _prestige_count() > 0:
		cats.append(CAT_DNA)
	return cats


## Сколько всего записей в каталоге.
static func count() -> int:
	return all().size()


## Количество доступных (не заблокированных) апгрейдов для текущего состояния.
static func unlocked_count(total_biomass: float, stage_index: int) -> int:
	var n := 0
	var items := all()
	for i in items.size():
		var it: Dictionary = items[i]
		if total_biomass >= float(it["unlock_total"]) and stage_index >= int(it["unlock_stage"]):
			n += 1
	return n


# --- внутреннее -------------------------------------------------------------

static func _prestige_count() -> int:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root := (loop as SceneTree).root
		if root != null:
			var gs := root.get_node_or_null("GameState")
			if gs != null and gs.get("prestige_count") != null:
				return int(gs.get("prestige_count"))
	return 0


static func _def(id: String, name: String, desc: String, category: String, icon: String,
		currency: String, base_cost: float, cost_growth: float, value: float,
		effect: String, max_level: int, unlock_stage: int, unlock_total: float,
		color: Color) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"desc": desc,
		"category": category,
		"icon": icon,
		"currency": currency,
		"base_cost": base_cost,
		"cost_growth": cost_growth,
		"value": value,
		"effect": effect,
		"max_level": max_level,
		"unlock_stage": unlock_stage,
		"unlock_total": unlock_total,
		"color": color,
	}


static func _build() -> void:
	_items = []

	# --- РОСТ: пассивная биомасса -------------------------------------------
	_items.append(_def("photosynthesis", "Фотосинтез", "+0.5 биомассы/сек за уровень",
		CAT_GROWTH, "☼", "biomass", 15.0, 1.15, 0.5, "ps_add", 20, 0, 0.0, P.GREEN))
	_items.append(_def("cytoplasm", "Цитоплазма", "+2 биомассы/сек за уровень",
		CAT_GROWTH, "❋", "biomass", 60.0, 1.16, 2.0, "ps_add", 20, 0, 40.0,
		P.glow(P.GREEN, 1.15)))
	_items.append(_def("nutrient_flow", "Поток питательных веществ",
		"Пассив ×1.06 за уровень — течение приносит больше",
		CAT_GROWTH, "∿", "biomass", 250.0, 2.20, 0.06, "ps_mult", 6, 0, 120.0, P.CYAN))
	_items.append(_def("bio_pump", "Бионасос", "+12 биомассы/сек за уровень",
		CAT_GROWTH, "◉", "biomass", 1200.0, 1.17, 12.0, "ps_add", 20, 0, 600.0,
		P.glow(P.AQUA, 1.1)))
	_items.append(_def("osmosis", "Осмос", "Пассив ×1.06 за уровень",
		CAT_GROWTH, "◈", "biomass", 3000.0, 2.30, 0.06, "ps_mult", 6, 0, 2500.0,
		P.AQUA))
	_items.append(_def("colony", "Колония", "+60 биомассы/сек за уровень",
		CAT_GROWTH, "⬢", "biomass", 12000.0, 1.18, 60.0, "ps_add", 18, 4, 15000.0,
		P.GREEN))
	_items.append(_def("circulation", "Кровообращение", "Пассив ×1.07 за уровень",
		CAT_GROWTH, "⌬", "biomass", 60000.0, 2.40, 0.07, "ps_mult", 5, 6, 90000.0,
		P.glow(P.PINK, 0.9)))
	_items.append(_def("metabolism", "Метаболизм", "ВСЁ ×1.05 за уровень — и пассив, и клик",
		CAT_GROWTH, "⚛", "biomass", 250000.0, 2.60, 0.05, "all_mult", 5, 7, 550000.0,
		P.GOLD))
	_items.append(_def("deep_current", "Глубинное течение", "+900 биомассы/сек за уровень",
		CAT_GROWTH, "≋", "biomass", 1200000.0, 1.19, 900.0, "ps_add", 12, 8, 3500000.0,
		P.CYAN))
	_items.append(_def("ocean_heart", "Сердце океана", "Пассив ×1.06 за уровень",
		CAT_GROWTH, "✷", "biomass", 5000000.0, 2.80, 0.06, "ps_mult", 5, 8, 20000000.0,
		P.glow(P.CYAN, 1.2)))

	# --- МУТАЦИИ: сила клика -------------------------------------------------
	_items.append(_def("tentacle", "Щупальце", "+1 к силе клика за уровень",
		CAT_MUTATION, "⌇", "biomass", 20.0, 1.14, 1.0, "click_add", 20, 0, 0.0, P.PINK))
	_items.append(_def("cilia", "Чувствительные реснички", "Клик ×1.05 за уровень",
		CAT_MUTATION, "✧", "biomass", 180.0, 2.00, 0.05, "click_mult", 8, 0, 90.0,
		P.glow(P.PINK, 1.1)))
	_items.append(_def("muscle", "Мышечная ткань", "+6 к силе клика за уровень",
		CAT_MUTATION, "◆", "biomass", 900.0, 1.15, 6.0, "click_add", 20, 0, 400.0,
		P.VIOLET))
	_items.append(_def("reflex_arc", "Рефлекторная дуга", "Клик ×1.05 за уровень",
		CAT_MUTATION, "✦", "biomass", 4000.0, 2.10, 0.05, "click_mult", 6, 2, 2500.0,
		P.PINK))
	_items.append(_def("bioelectric", "Биоэлектричество", "Клик ×1.06 за уровень",
		CAT_MUTATION, "∴", "biomass", 25000.0, 2.20, 0.06, "click_mult", 6, 4, 15000.0,
		P.glow(P.AQUA, 1.1)))
	_items.append(_def("jaws", "Хищный хват", "+40 к силе клика за уровень",
		CAT_MUTATION, "◣", "biomass", 120000.0, 1.16, 40.0, "click_add", 15, 5, 90000.0,
		P.DANGER))
	_items.append(_def("synapse", "Синапсы", "ВСЁ ×1.05 за уровень",
		CAT_MUTATION, "❖", "biomass", 400000.0, 2.40, 0.05, "all_mult", 5, 7, 550000.0,
		P.VIOLET))
	_items.append(_def("resonance", "Резонанс", "Клик ×1.06 за уровень",
		CAT_MUTATION, "✺", "biomass", 2000000.0, 2.60, 0.06, "click_mult", 5, 8, 3500000.0,
		P.glow(P.VIOLET, 1.2)))

	# --- СИМБИОЗ: автоматизация и общие ускорения ---------------------------
	_items.append(_def("plankton", "Планктонный симбиоз", "+0.2 авто-клика/сек за уровень",
		CAT_SYMBIOSIS, "∙", "biomass", 100.0, 1.60, 0.2, "auto_click", 6, 0, 40.0,
		P.AQUA))
	_items.append(_def("bacteria", "Бактериальный мат", "+0.4 авто-клика/сек за уровень",
		CAT_SYMBIOSIS, "◍", "biomass", 700.0, 1.60, 0.4, "auto_click", 6, 0, 400.0,
		P.GREEN))
	_items.append(_def("school", "Косяк", "+0.8 авто-клика/сек за уровень",
		CAT_SYMBIOSIS, "▸", "biomass", 4000.0, 1.70, 0.8, "auto_click", 6, 3, 2500.0,
		P.glow(P.AQUA, 1.1)))
	_items.append(_def("symbiont", "Симбионт-сигнальщик", "Пассив ×1.05 за уровень",
		CAT_SYMBIOSIS, "∞", "biomass", 15000.0, 2.00, 0.05, "ps_mult", 6, 4, 12000.0,
		P.CYAN))
	_items.append(_def("reef", "Риф-колония", "+1.5 авто-клика/сек за уровень",
		CAT_SYMBIOSIS, "❉", "biomass", 60000.0, 1.70, 1.5, "auto_click", 5, 6, 90000.0,
		P.PINK))
	_items.append(_def("hive", "Эусоциальный улей", "+3 авто-клика/сек за уровень",
		CAT_SYMBIOSIS, "⬟", "biomass", 500000.0, 1.80, 3.0, "auto_click", 4, 7, 900000.0,
		P.GOLD))
	_items.append(_def("biome", "Единый биом", "ВСЁ ×1.06 за уровень",
		CAT_SYMBIOSIS, "☯", "biomass", 4000000.0, 2.80, 0.06, "all_mult", 5, 8, 9000000.0,
		P.glow(P.GOLD, 1.2)))

	# --- ДНК: вечные бонусы за престиж (не сбрасываются) --------------------
	_items.append(_def("gene_memory", "Генная память", "Пассив ×1.15 за уровень",
		CAT_DNA, "⌘", "dna", 1.0, 2.20, 0.15, "ps_mult", 10, 0, 0.0, P.GOLD))
	_items.append(_def("epigenetics", "Эпигенетика", "Клик ×1.15 за уровень",
		CAT_DNA, "✱", "dna", 1.0, 2.20, 0.15, "click_mult", 10, 0, 0.0,
		P.glow(P.GOLD, 1.15)))
	_items.append(_def("instinct", "Инстинкт", "ВСЁ ×1.12 за уровень",
		CAT_DNA, "❂", "dna", 2.0, 2.40, 0.12, "all_mult", 10, 0, 0.0, P.PINK))
	_items.append(_def("bio_archive", "Биоархив", "+5 биомассы/сек за уровень",
		CAT_DNA, "▤", "dna", 1.0, 1.55, 5.0, "ps_add", 30, 0, 0.0, P.CYAN))
	_items.append(_def("metamorph", "Метаморф", "ВСЁ ×1.20 за уровень",
		CAT_DNA, "✹", "dna", 3.0, 2.60, 0.20, "all_mult", 8, 0, 0.0,
		P.glow(P.VIOLET, 1.2)))
	_items.append(_def("evolution_pulse", "Импульс эволюции", "+8 к силе клика за уровень",
		CAT_DNA, "⟡", "dna", 1.0, 1.60, 8.0, "click_add", 30, 0, 0.0, P.GREEN))
