class_name CreatureVisual
extends Node2D
## Процедурное биолюминесцентное существо.
##
## Рисуется целиком в `_draw`: дышит, колышет щупальцами/хвостом/плавниками,
## моргает, светится аддитивной аурой (HDR-цвета из Palette). Форма и палитра
## плавно морфят между эрами (`EvolutionDB`) за ~2 c.
##
## Контракт: setup(), play_tap(), play_stage_morph(index), реакция на
## GameState.stage_changed.

const P := preload("res://scripts/core/palette.gd")
const ED := preload("res://scripts/core/evolution_db.gd")

const EVOLUTION_DB_PATH := "res://scripts/core/evolution_db.gd"
const MORPH_DURATION := 2.0
const BODY_SEGMENTS := 96
const EYE_SEGMENTS := 26
const APPENDAGE_DOTS := 12
const MEMBRANE_RINGS := 10
const FALLBACK_MAX_STAGE := 9

const DEFAULT_PARAMS := {
	"body_radius": 56.0,
	"lobes": 3,
	"tentacles": 4,
	"tentacle_len": 1.0,
	"eyes": 2,
	"tail": 0.3,
	"fins": 1,
	"spikes": 0,
	"translucency": 0.45,
}

## Резервная таблица форм (если EvolutionDB вдруг недоступен).
const FALLBACK_CREATURE := [
	{"body_radius": 44.0, "lobes": 1, "tentacles": 0, "tentacle_len": 0.30, "eyes": 1, "tail": 0.0, "fins": 0, "spikes": 0, "translucency": 0.55},
	{"body_radius": 52.0, "lobes": 2, "tentacles": 2, "tentacle_len": 0.50, "eyes": 2, "tail": 0.10, "fins": 0, "spikes": 0, "translucency": 0.50},
	{"body_radius": 60.0, "lobes": 3, "tentacles": 4, "tentacle_len": 0.70, "eyes": 2, "tail": 0.20, "fins": 1, "spikes": 0, "translucency": 0.45},
	{"body_radius": 70.0, "lobes": 3, "tentacles": 5, "tentacle_len": 0.90, "eyes": 2, "tail": 0.35, "fins": 2, "spikes": 2, "translucency": 0.40},
	{"body_radius": 80.0, "lobes": 4, "tentacles": 6, "tentacle_len": 1.10, "eyes": 2, "tail": 0.50, "fins": 2, "spikes": 4, "translucency": 0.36},
	{"body_radius": 88.0, "lobes": 4, "tentacles": 8, "tentacle_len": 1.30, "eyes": 3, "tail": 0.60, "fins": 3, "spikes": 6, "translucency": 0.32},
	{"body_radius": 96.0, "lobes": 5, "tentacles": 9, "tentacle_len": 1.50, "eyes": 3, "tail": 0.70, "fins": 3, "spikes": 9, "translucency": 0.28},
	{"body_radius": 104.0, "lobes": 5, "tentacles": 10, "tentacle_len": 1.70, "eyes": 4, "tail": 0.80, "fins": 4, "spikes": 12, "translucency": 0.25},
	{"body_radius": 112.0, "lobes": 6, "tentacles": 12, "tentacle_len": 1.90, "eyes": 4, "tail": 0.90, "fins": 4, "spikes": 16, "translucency": 0.22},
	{"body_radius": 120.0, "lobes": 7, "tentacles": 14, "tentacle_len": 2.20, "eyes": 4, "tail": 1.00, "fins": 4, "spikes": 20, "translucency": 0.18},
]


## Дополнительный слой с аддитивным смешиванием — для мягкого свечения.
class AdditivePass extends Node2D:
	var painter: Callable

	func _ready() -> void:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


var _ready_done := false
var _time := 0.0
var _stage := 0

var _params: Dictionary = DEFAULT_PARAMS.duplicate()
var _from_params: Dictionary = DEFAULT_PARAMS.duplicate()
var _to_params: Dictionary = DEFAULT_PARAMS.duplicate()
var _colors: Dictionary = {}
var _from_colors: Dictionary = {}
var _to_colors: Dictionary = {}

var _morphing := false
var _morph_t := 0.0
var _tap := 0.0
var _blink := 1.0
var _blink_timer := 3.0
var _blink_anim := -1.0

var _speckles: Array = []
var _ring_index_cache: Dictionary = {}
var _aura: Node2D
var _front: Node2D
var _glow_tex: Texture2D


func _ready() -> void:
	setup()


# ---------------------------------------------------------------- публичное

## Инициализация. Идемпотентна, вызывается капитаном после add_child.
func setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	_stage = _read_stage()
	_params = _params_for_stage(_stage)
	_from_params = _params.duplicate()
	_to_params = _params.duplicate()
	_colors = _colors_for_stage(_stage)
	_from_colors = _colors.duplicate()
	_to_colors = _colors.duplicate()
	_build_speckles()
	_glow_tex = _make_radial_texture()
	_blink_timer = randf_range(1.8, 4.5)
	_aura = _make_pass(true, Callable(self, "_paint_aura"))
	_front = _make_pass(false, Callable(self, "_paint_front"))
	_connect_gamestate()
	queue_redraw()


## Клик по миру: squash & stretch + вспышка ауры.
func play_tap() -> void:
	setup()
	_tap = 1.0
	queue_redraw()


## Морф к форме и палитре эры `index` за ~2 c (без телепорта).
func play_stage_morph(index: int) -> void:
	setup()
	_stage = clampi(index, 0, _max_stage())
	_from_params = _params.duplicate()
	_from_colors = _colors.duplicate()
	_to_params = _params_for_stage(_stage)
	_to_colors = _colors_for_stage(_stage)
	_params = _from_params.duplicate()
	_colors = _from_colors.duplicate()
	_morph_t = 0.0
	_morphing = true
	_tap = maxf(_tap, 0.45)
	queue_redraw()


# ------------------------------------------------------------------ процесс

func _process(delta: float) -> void:
	setup()
	_time += delta
	_tap = maxf(0.0, _tap - delta * 2.3)
	_update_blink(delta)
	if _morphing:
		_morph_t += delta
		var k := clampf(_morph_t / MORPH_DURATION, 0.0, 1.0)
		var s := k * k * (3.0 - 2.0 * k)
		_params = _lerp_params(_from_params, _to_params, s)
		_colors = _lerp_colors(_from_colors, _to_colors, s)
		if k >= 1.0:
			_morphing = false
			_params = _to_params.duplicate()
			_colors = _to_colors.duplicate()
	queue_redraw()
	if _aura != null:
		_aura.queue_redraw()
	if _front != null:
		_front.queue_redraw()


# ------------------------------------------------------------------ отрисовка

func _draw() -> void:
	setup()
	if _colors.is_empty():
		_colors = _colors_for_stage(_stage)
	var breath := _breath()
	var sx := 1.0 + 0.10 * _tap - 0.012 * breath
	var sy := 1.0 - 0.08 * _tap + 0.018 * breath

	var poly := _body_points(1.0, sx, sy)
	var body_col: Color = _colors.get("color_b", P.AQUA)
	var accent: Color = _colors.get("accent", P.GOLD)
	var glow_col: Color = _colors.get("glow", P.CYAN)
	var transl := float(_params["translucency"])
	var alpha := clampf(0.74 - 0.34 * transl, 0.30, 0.78)

	# Позади тела: хвост и щупальца рисует аддитивный проход ауры.

	# Тело: тёмная масса → мембрана (плавный радиальный градиент) → ядро.
	draw_colored_polygon(poly, Color(body_col.r * 0.12, body_col.g * 0.20, body_col.b * 0.32, alpha * 0.78))
	_draw_membrane(poly, glow_col, accent, alpha)
	draw_colored_polygon(_scale_poly(poly, 0.24), P.fade(P.glow(accent, 1.15), 0.18 * _energy()))

	# Стеклянная кромка + внутренние прожилки — силуэт читается как мембрана.
	_draw_membrane_edge(poly, glow_col)
	_draw_veins(sx, sy, glow_col)

	_draw_speckles(sx, sy, glow_col)
	_draw_fins(sx, sy, body_col)
	_draw_spikes(sx, sy, accent)
	_draw_rim(poly, P.glow(accent, 1.5))
	_draw_eyes(sx, sy)


## Аддитивная аура — рисуется под телом (show_behind_parent).
func _paint_aura(c: CanvasItem) -> void:
	var br := float(_params["body_radius"]) * (1.0 + 0.03 * _breath() + 0.10 * _tap)
	var glow_col: Color = _colors.get("glow", P.CYAN)
	var accent: Color = _colors.get("accent", P.GOLD)
	var e := _energy()
	# Локальный ореол: не шире 1.9 радиуса тела, дальше света нет.
	_soft_glow(c, br * 1.90, glow_col.lerp(accent, 0.35), (0.040 + 0.018 * _tap) * e)
	_soft_glow(c, br * 1.32, glow_col.lerp(accent, 0.60), (0.048 + 0.028 * _tap) * e)
	_paint_appendages(c)


## Щупальца и хвост — цепочки мягких светящихся сгустков (без жёстких лент).
func _paint_appendages(c: CanvasItem) -> void:
	var br := float(_params["body_radius"])
	var e := _energy()
	var breath := _breath()
	var squat := Vector2(1.0 + 0.10 * _tap - 0.012 * breath, 1.0 - 0.08 * _tap + 0.018 * breath)
	var glow_col: Color = _colors.get("glow", P.CYAN)
	var accent: Color = _colors.get("accent", P.GOLD)

	var n := int(_params["tentacles"])
	var tlen := float(_params["tentacle_len"])
	for i in n:
		var f := float(i) / float(maxi(n - 1, 1))
		var base_ang := lerpf(PI * 0.26, PI * 0.74, f)
		var dir := Vector2(cos(base_ang), sin(base_ang))
		var nrm := Vector2(-dir.y, dir.x)
		var length := minf(tlen * br * 0.80, 150.0)
		for s in APPENDAGE_DOTS:
			var k := (float(s) + 0.5) / float(APPENDAGE_DOTS)
			var wave := sin(_time * 1.05 + float(i) * 1.35 - k * 2.4) * br * 0.10 * k
			var p := (dir * (br * 0.88 + length * k) + nrm * wave) * squat
			var rad := br * lerpf(0.075, 0.016, k)
			var a := lerpf(0.075, 0.0, pow(k, 0.75)) * e
			_soft_glow(c, rad, glow_col.lerp(accent, k * 0.45), a)

	var tail := float(_params["tail"])
	if tail > 0.05:
		var t_len := minf(br * (0.55 + 0.80 * tail), 170.0)
		var t_base := Vector2(-br * 0.60, -br * 0.02)
		for s in APPENDAGE_DOTS:
			var k := (float(s) + 0.5) / float(APPENDAGE_DOTS)
			var wave := sin(_time * 1.05 + k * 3.0) * br * 0.15 * k
			var p := (t_base + Vector2(-t_len * k, wave)) * squat
			var rad := br * lerpf(0.150, 0.024, k)
			var a := lerpf(0.065, 0.0, pow(k, 0.75)) * e
			_soft_glow(c, rad, glow_col.lerp(accent, 0.2 * k), a)


## Аддитивный слой поверх тела: ядро и глаза.
func _paint_front(c: CanvasItem) -> void:
	var br := float(_params["body_radius"])
	var accent: Color = _colors.get("accent", P.GOLD)
	var glow_col: Color = _colors.get("glow", P.CYAN)
	var pulse := 1.0 + 0.10 * _tap + 0.03 * _breath()
	var e := _energy()
	_soft_glow(c, br * 1.05 * pulse, accent, (0.055 + 0.035 * _tap) * e)
	_soft_glow(c, br * 0.58 * pulse, glow_col.lerp(P.TEXT, 0.16), (0.075 + 0.05 * _tap) * e)

	var eye_r := maxf(2.6, br * 0.078)
	for p in _eye_positions():
		var ep: Vector2 = p
		c.draw_circle(ep, eye_r * 1.60, P.fade(P.glow(accent, 1.5), 0.09))


# ------------------------------------------------------------- части существа

func _body_points(radius_scale: float, sx: float, sy: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var br := float(_params["body_radius"]) * radius_scale
	var lobes := int(_params["lobes"])
	var lobe_amp := 0.075 * sqrt(float(maxi(lobes, 1)))
	var wob := 0.028 * _breath()
	for i in BODY_SEGMENTS:
		var a := TAU * float(i) / float(BODY_SEGMENTS)
		var r := 1.0 + wob + lobe_amp * cos(float(lobes) * a + _time * 0.55)
		r *= 1.0 + 0.055 * cos(a + 0.8)
		pts.append(Vector2(cos(a) * r * br * sx, sin(a) * r * br * sy))
	return pts


func _scale_poly(poly: PackedVector2Array, f: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * f)
	return out


## Радиус кромки тела под углом `a` — та же формула, что в `_body_points`.
func _edge_radius(a: float) -> float:
	var br := float(_params["body_radius"])
	var lobes := int(_params["lobes"])
	var lobe_amp := 0.075 * sqrt(float(maxi(lobes, 1)))
	var wob := 0.028 * _breath()
	var r := 1.0 + wob + lobe_amp * cos(float(lobes) * a + _time * 0.55)
	r *= 1.0 + 0.055 * cos(a + 0.8)
	return r * br


func _draw_fins(sx: float, sy: float, col: Color) -> void:
	var n := int(_params["fins"])
	if n <= 0:
		return
	var br := float(_params["body_radius"])
	var squash := Vector2(sx, sy)
	var e := _energy()
	var accent: Color = _colors.get("accent", P.GOLD)
	for i in n:
		var sgn := -1.0 if i % 2 == 0 else 1.0
		var ang_r := 0.50 + 0.30 * float(i / 2)
		var ang := ang_r if sgn > 0.0 else PI - ang_r
		var wave := 0.22 * sin(_time * 1.7 + float(i) * 1.1)
		var tip_dir := Vector2(cos(ang + wave * 0.5), sin(ang + wave * 0.5))
		var side_dir := Vector2(-tip_dir.y, tip_dir.x)
		var base_c := tip_dir * br * 0.90
		var tip := tip_dir * (br * 1.34 + br * 0.07 * sin(_time * 2.0 + float(i)))
		# Мягкая стеклянная плоскость плавника: заливка + светящаяся кромка.
		var tri := PackedVector2Array([
			(base_c + side_dir * br * 0.14) * squash,
			(base_c - side_dir * br * 0.14) * squash,
			tip * squash,
		])
		draw_colored_polygon(tri, P.fade(P.glow(col.lerp(accent, 0.6), 1.10), 0.055 * e))
		var edge := PackedVector2Array([tri[0], tri[2], tri[1]])
		draw_polyline(edge, P.fade(P.glow(accent, 1.15), 0.085 * e), 1.0, true)
		for k in 3:
			var t := float(k + 1) / 4.0
			var p: Vector2 = (base_c.lerp(tip, t)) * squash
			_soft_glow(self, br * lerpf(0.16, 0.05, t), accent, 0.045 * e * (1.0 - t * 0.5))


func _draw_spikes(sx: float, sy: float, accent: Color) -> void:
	var n := int(_params["spikes"])
	if n <= 0:
		return
	var br := float(_params["body_radius"])
	var squash := Vector2(sx, sy)
	var e := _energy()
	for i in n:
		var f := float(i) / float(maxi(n - 1, 1))
		# Неравномерный шаг: шипы не «зубьями», а редкими наростами.
		var jit := sin(float(i) * 4.7123 + 1.7) * 0.62 + sin(float(i) * 11.3) * 0.30
		var ang := lerpf(-2.70, -0.42, f) + jit * (TAU / float(maxi(n, 1))) * 0.55
		var dir := Vector2(cos(ang), sin(ang))
		# Привязка к настоящей кромке тела (с учётом лопастей и «гуляния» формы).
		var r_edge := _edge_radius(ang)
		var base := dir * r_edge * 0.99
		var h := br * (0.070 + 0.040 * sin(_time * 1.6 + float(i) * 1.31)) * (0.65 + 0.55 * absf(jit))
		var tip := dir * (r_edge * 0.99 + h)
		var side := Vector2(-dir.y, dir.x) * br * (0.026 + 0.010 * absf(jit))
		var tri := PackedVector2Array([
			(base - side) * squash,
			(base + side) * squash,
			tip * squash,
		])
		draw_colored_polygon(tri, P.fade(P.glow(accent, 1.05), 0.18 * e))
		draw_polyline(tri, P.fade(P.glow(accent, 1.20), 0.12 * e), 1.0, true)


## Радиальный градиент мембраны: кольцевые полосы с интерполяцией цвета —
## гладко, без полос, и без триангуляции «змейкой» (она падала на сильной невыпуклости).
## Каждое кольцо собирается из 2n треугольников вручную и отдаётся
## в RenderingServer.canvas_item_add_triangle_array — движку нечего триангулировать.
func _draw_membrane(poly: PackedVector2Array, glow_col: Color, accent: Color, alpha: float) -> void:
	var e := _energy()
	var n := poly.size()
	if n < 3:
		return
	var idx := _ring_indices(n)
	var rings := MEMBRANE_RINGS
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(n * 2)
	cols.resize(n * 2)
	for r in rings:
		var t0 := float(r) / float(rings)
		var t1 := float(r + 1) / float(rings)
		var s0 := lerpf(1.0, 0.10, t0)
		var s1 := lerpf(1.0, 0.10, t1)
		var a0 := lerpf(0.008, 0.30 * (0.55 + 0.45 * alpha), pow(t0, 1.5)) * e
		var a1 := lerpf(0.008, 0.30 * (0.55 + 0.45 * alpha), pow(t1, 1.5)) * e
		var c0 := P.fade(P.glow(accent.lerp(glow_col, 0.45), 1.02), a0)
		var c1 := P.fade(P.glow(glow_col.lerp(accent, 0.55), 1.05), a1)
		for i in n:
			pts[i] = poly[i] * s0
			cols[i] = c0
			pts[n + i] = poly[i] * s1
			cols[n + i] = c1
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), idx, pts, cols, PackedVector2Array(), PackedInt32Array(),
			PackedFloat32Array(), RID())


## Индексы треугольников кольца: зависят только от n, кэшируются между кадрами.
## Вершины 0..n-1 — внешний контур, n..2n-1 — внутренний (тот же порядок обхода).
func _ring_indices(n: int) -> PackedInt32Array:
	if _ring_index_cache.has(n):
		return _ring_index_cache[n]
	var idx := PackedInt32Array()
	idx.resize(n * 6)
	for i in n:
		var j := (i + 1) % n
		var k := i * 6
		idx[k] = i
		idx[k + 1] = j
		idx[k + 2] = n + j
		idx[k + 3] = i
		idx[k + 4] = n + j
		idx[k + 5] = n + i
	_ring_index_cache[n] = idx
	return idx


## Полупрозрачная «стеклянная» кромка мембраны.
func _draw_membrane_edge(poly: PackedVector2Array, col: Color) -> void:
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, P.fade(P.glow(col, 1.15), 0.035), 4.0, true)
	draw_polyline(closed, P.fade(P.glow(col, 1.30), 0.055), 1.2, true)


## Внутренние прожилки: тонкие изогнутые лучи от ядра к мембране.
func _draw_veins(sx: float, sy: float, col: Color) -> void:
	var br := float(_params["body_radius"])
	var squash := Vector2(sx, sy)
	var e := _energy()
	var veins := 9
	for i in veins:
		var a0 := TAU * float(i) / float(veins) + 0.31
		var pts := PackedVector2Array()
		var steps := 6
		for s in steps + 1:
			var k := float(s) / float(steps)
			var a := a0 + sin(_time * 0.55 + float(i) * 1.7 + k * 2.4) * 0.13 * k
			var r := br * (0.24 + 0.70 * k)
			pts.append(Vector2(cos(a), sin(a)) * r * squash)
		draw_polyline(pts, P.fade(P.glow(col, 1.35), (0.085 - 0.045 * float(i % 3)) * e), 1.5, true)


func _draw_rim(poly: PackedVector2Array, col: Color) -> void:
	var light_dir := Vector2(-0.5, -0.85).normalized()
	var n := poly.size()
	var arc := PackedVector2Array()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var mid := (p + q) * 0.5
		if mid.length_squared() < 0.001:
			continue
		var d := mid.normalized().dot(light_dir)
		if d <= 0.0:
			if arc.size() > 1:
				_flush_rim(arc, col)
			arc = PackedVector2Array()
			continue
		var a := clampf(d, 0.0, 1.0)
		if arc.is_empty():
			arc.append(p)
		arc.append(q)
	if arc.size() > 1:
		_flush_rim(arc, col)


## Один непрерывный блик по кромке: широкий мягкий подслой + узкая жила.
func _flush_rim(arc: PackedVector2Array, col: Color) -> void:
	draw_polyline(arc, P.fade(col, 0.032), 7.0, true)
	draw_polyline(arc, P.fade(col, 0.105), 1.6, true)


func _draw_eyes(sx: float, sy: float) -> void:
	var br := float(_params["body_radius"])
	var eye_r := maxf(2.6, br * 0.078)
	var open := maxf(_blink, 0.05)
	var accent: Color = _colors.get("accent", P.GOLD)
	var squash := Vector2(sx, sy)
	for p in _eye_positions():
		var c: Vector2 = p * squash
		# Тёмный «стеклянный» глаз с тонкой светящейся обводкой.
		var ring := PackedVector2Array()
		for i in EYE_SEGMENTS:
			var a := TAU * float(i) / float(EYE_SEGMENTS)
			ring.append(c + Vector2(cos(a) * eye_r, sin(a) * eye_r * open))
		draw_colored_polygon(ring, Color(0.05, 0.09, 0.13, 0.82))
		var closed := ring.duplicate()
		closed.append(ring[0])
		draw_polyline(closed, P.fade(P.glow(accent, 1.30), 0.42), 1.2, true)

		var iris := PackedVector2Array()
		var ir := eye_r * 0.50
		for i in EYE_SEGMENTS:
			var a := TAU * float(i) / float(EYE_SEGMENTS)
			iris.append(c + Vector2(cos(a) * ir, sin(a) * ir * open))
		draw_colored_polygon(iris, P.fade(P.glow(accent, 1.15), 0.72))

		var pupil := PackedVector2Array()
		var pr := ir * 0.46
		for i in EYE_SEGMENTS:
			var a := TAU * float(i) / float(EYE_SEGMENTS)
			pupil.append(c + Vector2(cos(a) * pr, sin(a) * pr * open))
		draw_colored_polygon(pupil, Color(0.03, 0.05, 0.08, 0.92))

		draw_circle(c + Vector2(-eye_r * 0.28, -eye_r * 0.30 * open), maxf(1.0, eye_r * 0.20 * open), P.fade(P.TEXT, 0.9))


func _eye_positions() -> Array:
	var br := float(_params["body_radius"])
	var n := int(_params["eyes"])
	var out: Array = []
	match n:
		0:
			pass
		1:
			out.append(Vector2(0.0, -0.12 * br))
		2:
			out.append(Vector2(-0.30 * br, -0.16 * br))
			out.append(Vector2(0.30 * br, -0.14 * br))
		3:
			out.append(Vector2(-0.34 * br, -0.12 * br))
			out.append(Vector2(0.34 * br, -0.12 * br))
			out.append(Vector2(0.0, -0.40 * br))
		_:
			out.append(Vector2(-0.34 * br, -0.18 * br))
			out.append(Vector2(0.34 * br, -0.18 * br))
			out.append(Vector2(-0.18 * br, 0.10 * br))
			out.append(Vector2(0.20 * br, 0.12 * br))
	return out


func _draw_speckles(sx: float, sy: float, col: Color) -> void:
	var br := float(_params["body_radius"])
	var squash := Vector2(sx, sy)
	for sp in _speckles:
		var d: Vector2 = sp["dir"]
		var r: float = sp["r"]
		var p := d * r * br * 0.92 * squash
		var tw := 0.55 + 0.45 * sin(_time * 1.7 + float(sp["phase"]))
		var sz: float = float(sp["size"]) * (1.0 + 0.15 * _tap)
		draw_circle(p, sz, P.fade(P.glow(col, 1.3), 0.13 * tw))


# ---------------------------------------------------------------- внутреннее

func _build_speckles() -> void:
	_speckles = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in 16:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.72
		_speckles.append({
			"dir": Vector2(cos(a), sin(a)),
			"r": r,
			"size": rng.randf_range(1.2, 3.4),
			"phase": rng.randf() * TAU,
		})


func _breath() -> float:
	return sin(_time * 0.95) * 0.7 + sin(_time * 0.31) * 0.3


## Компенсация «энергии»: крупное тело не светит ярче мелкого.
## Без неё на поздних эрах аддитивные слои выжигают кадр в белое.
func _energy() -> float:
	var br := float(_params["body_radius"])
	return clampf(pow(72.0 / maxf(br, 1.0), 0.75), 0.5, 1.35)


func _update_blink(delta: float) -> void:
	if _blink_anim >= 0.0:
		_blink_anim += delta / 0.16
		if _blink_anim >= 1.0:
			_blink_anim = -1.0
			_blink = 1.0
			_blink_timer = randf_range(2.2, 6.0)
		else:
			_blink = 1.0 - sin(_blink_anim * PI)
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_anim = 0.0


## Мягкое радиальное свечение: процедурная радиальная текстура, тонированная
## цветом с HDR-яркостью. Без градиентных артефактов, в отличие от draw_circle.
func _soft_glow(c: CanvasItem, radius: float, col: Color, alpha: float) -> void:
	if _glow_tex == null or radius <= 0.5:
		return
	var r := Rect2(-radius, -radius, radius * 2.0, radius * 2.0)
	c.draw_texture_rect(_glow_tex, r, false, P.fade(P.glow(col, 1.25), alpha))


func _make_radial_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.32, 0.68, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.55),
		Color(1.0, 1.0, 1.0, 0.16),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _make_pass(behind: bool, painter: Callable) -> Node2D:
	var p := AdditivePass.new()
	p.painter = painter
	p.show_behind_parent = behind
	add_child(p)
	return p


func _connect_gamestate() -> void:
	var gs := _gamestate()
	if gs == null:
		return
	if gs.has_signal("stage_changed") and not gs.is_connected("stage_changed", Callable(self, "_on_stage_changed")):
		gs.connect("stage_changed", Callable(self, "_on_stage_changed"))


func _on_stage_changed(index: int) -> void:
	play_stage_morph(int(index))


func _gamestate() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


func _read_stage() -> int:
	var gs := _gamestate()
	if gs == null:
		return 0
	var v: Variant = gs.get("stage_index")
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return clampi(int(v), 0, FALLBACK_MAX_STAGE)
	return 0


func _max_stage() -> int:
	var n := int(ED.count())
	if n <= 0:
		return FALLBACK_MAX_STAGE
	return maxi(0, mini(n - 1, FALLBACK_MAX_STAGE))


func _stage_entry(index: int) -> Dictionary:
	var d: Dictionary = ED.get_stage(index)
	if d.has("creature") or d.has("color_a"):
		return d
	return {}


func _params_for_stage(index: int) -> Dictionary:
	var out := DEFAULT_PARAMS.duplicate()
	var src: Dictionary = {}
	var d := _stage_entry(index)
	if d.has("creature") and d["creature"] is Dictionary:
		src = d["creature"]
	elif not d.is_empty():
		src = d
	if src.is_empty():
		src = FALLBACK_CREATURE[clampi(index, 0, FALLBACK_CREATURE.size() - 1)]
	for key in out.keys():
		if src.has(key):
			out[key] = src[key]
	return out


func _colors_for_stage(index: int) -> Dictionary:
	var d := _stage_entry(index)
	var fb: Dictionary = _fallback_colors()[clampi(index, 0, FALLBACK_CREATURE.size() - 1)]
	var out := {
		"color_a": fb["color_a"],
		"color_b": fb["color_b"],
		"accent": fb["accent"],
		"glow": fb["glow"],
	}
	for key in out.keys():
		var v: Variant = d.get(key, null)
		if v is Color:
			out[key] = v
	return out


func _fallback_colors() -> Array:
	return [
		{"color_a": P.CYAN, "color_b": P.AQUA, "accent": P.CYAN, "glow": P.CYAN},
		{"color_a": P.AQUA, "color_b": P.CYAN, "accent": P.GOLD, "glow": P.AQUA},
		{"color_a": P.GREEN, "color_b": P.CYAN, "accent": P.GOLD, "glow": P.GREEN},
		{"color_a": P.CYAN, "color_b": P.VIOLET, "accent": P.VIOLET, "glow": P.AQUA},
		{"color_a": P.PINK, "color_b": P.VIOLET, "accent": P.GOLD, "glow": P.PINK},
		{"color_a": P.GOLD, "color_b": P.PINK, "accent": P.GOLD, "glow": P.GOLD},
		{"color_a": P.VIOLET, "color_b": P.PINK, "accent": P.GOLD, "glow": P.VIOLET},
		{"color_a": P.CYAN, "color_b": P.GREEN, "accent": P.GREEN, "glow": P.CYAN},
		{"color_a": P.AQUA, "color_b": P.VIOLET, "accent": P.PINK, "glow": P.AQUA},
		{"color_a": P.VIOLET, "color_b": P.CYAN, "accent": P.GOLD, "glow": P.VIOLET},
	]


func _lerp_params(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in a.keys():
		var va: Variant = a[key]
		var vb: Variant = b.get(key, va)
		if typeof(va) == TYPE_INT and typeof(vb) == TYPE_INT:
			out[key] = int(round(lerpf(float(va), float(vb), t)))
		else:
			out[key] = lerpf(float(va), float(vb), t)
	return out


func _lerp_colors(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in a.keys():
		var ca: Color = a[key]
		var cb: Color = b.get(key, ca)
		out[key] = ca.lerp(cb, t)
	return out
