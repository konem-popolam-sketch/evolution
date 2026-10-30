extends SceneTree
## Headless-проба существа и FX: API, интеграция с EvolutionDB, морф, tap,
## жизненный цикл эффектов. Запуск:
##   godot_run_headless(script="tests/creature_probe.gd")

const ED := preload("res://scripts/core/evolution_db.gd")
const P := preload("res://scripts/core/palette.gd")

const CREATURE_PATH := "res://scripts/visual/creature.gd"
const TEXT_PATH := "res://scripts/fx/floating_text.gd"
const BURST_PATH := "res://scripts/fx/burst.gd"
const RIPPLE_PATH := "res://scripts/fx/ripple.gd"
const MOTES_PATH := "res://scripts/fx/motes.gd"

var _failed := false
var _creature: Node2D
var _layer: Node2D


func _initialize() -> void:
	print("=== CREATURE/FX PROBE ===")
	if ED.count() != 10:
		_fail("EvolutionDB.count() = %d, ожидалось 10" % ED.count())
		return
	if P.glow(P.CYAN).r <= 1.0 and P.glow(P.CYAN).g <= 1.0:
		_fail("Palette.glow() не даёт HDR-цвет (>1.0)")
		return

	_layer = Node2D.new()
	root.add_child(_layer)

	# --- существо
	var cs: Script = load(CREATURE_PATH)
	if cs == null:
		_fail("не загрузился " + CREATURE_PATH)
		return
	_creature = cs.new()
	_layer.add_child(_creature)
	_creature.setup()
	var p0: Dictionary = _creature.get("_params")
	for key in ["body_radius", "lobes", "tentacles", "tentacle_len", "eyes", "tail", "fins", "spikes", "translucency"]:
		if not p0.has(key):
			_fail("в _params нет ключа " + key)
			return
	print("params[0]: ", p0)
	if absf(float(p0["body_radius"]) - float(ED.get_stage(0)["creature"]["body_radius"])) > 0.01:
		_fail("body_radius не из EvolutionDB: %s vs %s" % [p0["body_radius"], ED.get_stage(0)["creature"]["body_radius"]])
		return

	# Форма всех эр берётся из БД (никакого fallback).
	for i in ED.count():
		var cp: Dictionary = _creature.call("_params_for_stage", i)
		var want: Dictionary = ED.get_stage(i)["creature"]
		for key in want.keys():
			if absf(float(cp[key]) - float(want[key])) > 0.001:
				_fail("эра %d: %s=%s, ожидалось %s" % [i, key, cp[key], want[key]])
				return
	var body0: Array = _creature.call("_body_points", 1.0, 1.0, 1.0)
	if body0.size() != 96:
		_fail("_body_points вернул %d точек вместо 96" % body0.size())
		return
	for pt in body0:
		var v: Vector2 = pt
		if not is_finite(v.x) or not is_finite(v.y) or v.length() < 1.0 or v.length() > 400.0:
			_fail("тело дегенерирует: точка %s" % v)
			return
	print("body: 96 точек, радиус %0.1f" % float(p0["body_radius"]))

	# --- морф эры 9 за ~2 c
	_creature.play_stage_morph(9)
	if not bool(_creature.get("_morphing")):
		_fail("play_stage_morph не запустил морф")
		return
	var mid := 0
	for f in 90:
		_creature._process(1.0 / 60.0)
		mid = int(_creature.get("_stage"))
	if float(_creature.get("_morph_t")) < 1.4:
		_fail("морф идёт не по времени: %0.2f c после 90 кадров" % float(_creature.get("_morph_t")))
		return
	for f in 60:
		_creature._process(1.0 / 60.0)
	if bool(_creature.get("_morphing")):
		_fail("морф не завершился за 2.5 c")
		return
	var p9: Dictionary = _creature.get("_params")
	var want9: Dictionary = ED.get_stage(9)["creature"]
	if absf(float(p9["body_radius"]) - float(want9["body_radius"])) > 0.01:
		_fail("после морфа body_radius=%s, ожидалось %s" % [p9["body_radius"], want9["body_radius"]])
		return
	var col9: Dictionary = _creature.get("_colors")
	if not (col9.get("accent") is Color):
		_fail("палитра эры 9 без accent")
		return
	if not (col9["glow"] is Color) or not (col9["color_b"] is Color):
		_fail("палитра эры 9 неполная")
		return
	print("morph -> stage %d, body_radius %0.1f, accent %s" % [mid, float(p9["body_radius"]), col9["accent"]])

	# --- мембрана: кольца рисуются ручными треугольниками, без триангуляции полигона
	var raw0: Array = _creature.call("_body_points", 1.0, 1.0, 1.0)
	var n: int = raw0.size()
	var idx: PackedInt32Array = _creature.call("_ring_indices", n)
	if idx.size() != n * 6:
		_fail("_ring_indices вернул %d индексов вместо %d" % [idx.size(), n * 6])
		return
	for k in idx.size():
		if idx[k] < 0 or idx[k] >= n * 2:
			_fail("индекс треугольника вне диапазона: %d (n=%d)" % [idx[k], n])
			return
	if _creature.call("_ring_indices", n) != idx:
		_fail("кэш индексов кольца нестабилен")
		return
	# Старый способ («змейка» из 2n вершин в draw_polygon) — сколько колец он не триангулирует.
	var old_bad := 0
	var old_total := 0
	for stage_i in [0, 3, 9]:
		_creature.set("_params", _creature.call("_params_for_stage", stage_i))
		var raw: Array = _creature.call("_body_points", 1.0, 1.0, 1.02)
		var poly := PackedVector2Array()
		for pt in raw:
			poly.append(pt)
		for r in [0, 3, 6, 9]:
			var t0 := float(r) / 10.0
			var t1 := float(r + 1) / 10.0
			var s0 := lerpf(1.0, 0.10, t0)
			var s1 := lerpf(1.0, 0.10, t1)
			var strip := PackedVector2Array()
			for i in poly.size():
				strip.append(poly[i] * s0)
			for i in range(poly.size() - 1, -1, -1):
				strip.append(poly[i] * s1)
			old_total += 1
			if Geometry2D.triangulate_polygon(strip).is_empty():
				old_bad += 1
	_creature.set("_params", p9)
	print("мембрана: %d колец на ручных треугольниках (6n=%d индексов); старый draw_polygon не триангулировал %d/%d проб" % [10, idx.size(), old_bad, old_total])

	# --- tap
	_creature.play_tap()
	if float(_creature.get("_tap")) <= 0.5:
		_fail("play_tap не поднял импульс: %0.2f" % float(_creature.get("_tap")))
		return
	for f in 40:
		_creature._process(1.0 / 60.0)
	if float(_creature.get("_tap")) >= 0.5:
		_fail("импульс tap не затухает: %0.2f" % float(_creature.get("_tap")))
		return

	# --- FX: создание и авто-освобождение
	var ts = load(TEXT_PATH)
	var bs = load(BURST_PATH)
	var rs = load(RIPPLE_PATH)
	var ms = load(MOTES_PATH)
	for pair in [[ts, TEXT_PATH], [bs, BURST_PATH], [rs, RIPPLE_PATH], [ms, MOTES_PATH]]:
		if pair[0] == null:
			_fail("не загрузился " + String(pair[1]))
			return

	var before := _layer.get_child_count()
	ts.spawn(_layer, Vector2(400.0, 300.0), "+12", P.GOLD)
	ts.spawn(_layer, Vector2(420.0, 320.0), "+999", P.PINK, 40, true)
	bs.burst(_layer, Vector2(400.0, 300.0), P.CYAN, 18, 200.0, 5.0)
	rs.ripple(_layer, Vector2(400.0, 300.0), P.AQUA)
	var added := _layer.get_child_count() - before
	if added != 4:
		_fail("FX создали %d узлов вместо 4" % added)
		return
	var fx: Array = []
	for i in range(before, _layer.get_child_count()):
		fx.append(_layer.get_child(i))
	print("FX spawned: ", added)

	for f in 130:
		for node in fx:
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node._process(1.0 / 60.0)
	var alive := 0
	for node in fx:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			alive += 1
	if alive != 0:
		_fail("FX не самоосвободились: осталось %d" % alive)
		return

	# --- Motes
	var motes: Node2D = ms.new()
	_layer.add_child(motes)
	motes.setup()
	motes.setup()
	var mcount: int = (motes.get("_motes") as Array).size()
	var bcount: int = (motes.get("_blooms") as Array).size()
	if mcount != 84 or bcount != 4:
		_fail("Motes: %d мотыльков / %d blooms (setup не идемпотентен или пуст)" % [mcount, bcount])
		return
	motes._process(0.25)
	print("motes: %d, blooms %d" % [mcount, bcount])

	print("PROBE OK: существо + FX живут, морф 2 c, tap, авто-freed, %d мотыльков" % mcount)
	quit(0)


func _fail(reason: String) -> void:
	_failed = true
	printerr("PROBE FAIL: " + reason)
	quit(1)
