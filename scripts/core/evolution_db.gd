class_name EvolutionDB
extends RefCounted
## 10 эр эволюции: пороги по total_biomass, палитры и параметры формы существа.
##
## СХЕМА ЭРЫ (ровно эти поля, по контракту):
##   index:int, name:String, subtitle:String, threshold:float,
##   color_a:Color, color_b:Color, accent:Color, glow:Color, creature:Dictionary
##
## creature: body_radius 40..120, lobes 1..7, tentacles 0..14, tentacle_len 0.3..2.2,
##           eyes 0..4, tail 0..1, fins 0..4, spikes 0..20, translucency 0..1.
##
## КРИВАЯ ПОРОГОВ (плавная, без стен): 0 → 60 → 400 → 2.5 тыс. → 15 тыс. → 90 тыс.
##   → 400 тыс. → 2 млн → 9 млн → 30 млн. Шаг между эрами 6.7×…4.4× и постепенно
##   выравнивается: чем позже эра, тем медленнее растёт доход, поэтому снижение
##   шага держит ВРЕМЯ прохождения эры ровным (симуляция первого забега:
##   1.2 / 1.7 / 2.7 / 3.6 / 5.3 / 6.8 / 6.0 / 5.6 / 13.0 мин, всего ≈ 46 мин).
##   Последняя эра — осознанный «рывок к престижу»: сюда доходят не ради
##   простоя, а чтобы забрать ДНК.
##
## Форма существа меняется МОНОТОННО и мелкими шагами (≤ ±20% за эру), поэтому
## морф между эрами выглядит как плавное превращение, а не как подмена тела.

## Палитра подключается явно (preload), а не через глобальное имя Palette:
## так файл компилируется даже до первой генерации global_script_class_cache.
const P := preload("res://scripts/core/palette.gd")

const STAGE_COUNT := 10

static var _stages: Array = []

## Все эры по возрастанию индекса. Массив общий — только для чтения.
static func all() -> Array:
	if _stages.is_empty():
		_build()
	return _stages


## Индекс эры для накопленной биомассы (0..9). Никогда не выходит за границы.
static func stage_at(total: float) -> int:
	var arr := all()
	var idx := 0
	for i in arr.size():
		var st: Dictionary = arr[i]
		if total >= float(st["threshold"]):
			idx = i
		else:
			break
	return idx


## Эра по индексу; индекс зажимается в допустимый диапазон.
static func get_stage(i: int) -> Dictionary:
	var arr := all()
	var n := arr.size()
	var idx: int = clampi(i, 0, n - 1)
	return arr[idx]


## Порог следующей эры; 0.0 если это последняя эра.
static func next_threshold(i: int) -> float:
	var arr := all()
	var n := arr.size()
	if n == 0:
		return 0.0
	var idx: int = clampi(i, 0, n - 1)
	if idx >= n - 1:
		return 0.0
	var nxt: Dictionary = arr[idx + 1]
	return float(nxt["threshold"])


static func count() -> int:
	return all().size()


## Удобный хелпер для визуала: плавная форма между двумя эрами (t = 0..1).
## Не требуется контрактом, но избавляет CreatureVisual от дублирования логики.
static func lerp_creature(from_index: int, to_index: int, t: float) -> Dictionary:
	var a: Dictionary = get_stage(from_index)["creature"]
	var b: Dictionary = get_stage(to_index)["creature"]
	var k: float = clampf(t, 0.0, 1.0)
	var out := {}
	for key in a.keys():
		var va := float(a[key])
		var vb := float(b[key])
		var v := lerpf(va, vb, k)
		if key == "lobes" or key == "tentacles" or key == "eyes" or key == "fins" or key == "spikes":
			v = roundf(v)
		out[key] = v
	return out


# --- внутреннее -------------------------------------------------------------

static func _creature(body_radius: float, lobes: int, tentacles: int, tentacle_len: float,
		eyes: int, tail: float, fins: int, spikes: int, translucency: float) -> Dictionary:
	return {
		"body_radius": body_radius,
		"lobes": lobes,
		"tentacles": tentacles,
		"tentacle_len": tentacle_len,
		"eyes": eyes,
		"tail": tail,
		"fins": fins,
		"spikes": spikes,
		"translucency": translucency,
	}


static func _stage(index: int, name: String, subtitle: String, threshold: float,
		color_a: Color, color_b: Color, accent: Color, glow: Color,
		creature: Dictionary) -> Dictionary:
	return {
		"index": index,
		"name": name,
		"subtitle": subtitle,
		"threshold": threshold,
		"color_a": color_a,
		"color_b": color_b,
		"accent": accent,
		"glow": glow,
		"creature": creature,
	}


static func _build() -> void:
	_stages = []

	# I — тёплая искра в холодной воде.
	_stages.append(_stage(0, "Искра", "Первая клетка в тёплой воде", 0.0,
		Color(0.055, 0.105, 0.185), Color(0.020, 0.040, 0.090),
		P.GOLD, P.glow(P.GOLD, 1.75),
		_creature(40.0, 1, 0, 0.30, 0, 0.00, 0, 0, 0.95)))

	# II — тело обретает мягкость и первые лучи.
	_stages.append(_stage(1, "Капля", "Мягкое тело учится чувствовать", 60.0,
		Color(0.045, 0.110, 0.195), Color(0.020, 0.050, 0.105),
		Color(0.95, 0.80, 0.55), P.glow(Color(0.95, 0.78, 0.52), 1.6),
		_creature(46.0, 2, 1, 0.45, 1, 0.05, 0, 0, 0.90)))

	# III — клетки держатся вместе.
	_stages.append(_stage(2, "Амёба", "Клетки держатся вместе", 400.0,
		Color(0.040, 0.125, 0.200), Color(0.020, 0.060, 0.115),
		P.AQUA, P.glow(P.AQUA, 1.5),
		_creature(53.0, 3, 3, 0.65, 1, 0.10, 0, 1, 0.83)))

	# IV — пульсирующий свет в глубине.
	_stages.append(_stage(3, "Медуза", "Пульсирующий свет в глубине", 2500.0,
		Color(0.038, 0.140, 0.215), Color(0.025, 0.070, 0.140),
		P.CYAN, P.glow(P.CYAN, 1.6),
		_creature(61.0, 3, 5, 0.85, 2, 0.15, 1, 2, 0.76)))

	# V — ветви тянутся к течению.
	_stages.append(_stage(4, "Полип", "Ветви тянутся к течению", 15000.0,
		Color(0.045, 0.150, 0.205), Color(0.030, 0.080, 0.160),
		P.GREEN, P.glow(P.GREEN, 1.5),
		_creature(70.0, 4, 7, 1.05, 2, 0.22, 1, 4, 0.68)))

	# VI — первое настоящее движение вперёд.
	_stages.append(_stage(5, "Рыба", "Первое движение вперёд", 90000.0,
		Color(0.048, 0.130, 0.230), Color(0.030, 0.070, 0.180),
		Color(0.45, 0.85, 1.00), P.glow(Color(0.42, 0.84, 1.00), 1.7),
		_creature(79.0, 4, 8, 1.15, 2, 0.35, 2, 6, 0.58)))

	# VII — тело обретает волю.
	_stages.append(_stage(6, "Странник", "Тело обретает волю", 400000.0,
		Color(0.070, 0.120, 0.250), Color(0.040, 0.060, 0.200),
		P.VIOLET, P.glow(P.VIOLET, 1.8),
		_creature(89.0, 5, 10, 1.35, 3, 0.50, 2, 9, 0.48)))

	# VIII — сила без спешки.
	_stages.append(_stage(7, "Хищник", "Сила без спешки", 2000000.0,
		Color(0.095, 0.100, 0.255), Color(0.050, 0.050, 0.195),
		Color(0.86, 0.56, 1.00), P.glow(Color(0.85, 0.55, 1.00), 1.9),
		_creature(99.0, 5, 11, 1.55, 3, 0.65, 3, 12, 0.38)))

	# IX — свет становится мыслью.
	_stages.append(_stage(8, "Разум", "Свет становится мыслью", 9000000.0,
		Color(0.125, 0.085, 0.250), Color(0.060, 0.040, 0.195),
		P.PINK, P.glow(P.PINK, 1.85),
		_creature(110.0, 6, 13, 1.85, 4, 0.82, 3, 16, 0.27)))

	# X — океан отвечает.
	_stages.append(_stage(9, "Сверхразум", "Океан отвечает", 30000000.0,
		Color(0.155, 0.090, 0.215), Color(0.075, 0.050, 0.180),
		P.glow(P.GOLD, 1.15), P.glow(P.GOLD, 2.1),
		_creature(120.0, 7, 14, 2.10, 4, 1.00, 4, 20, 0.18)))
