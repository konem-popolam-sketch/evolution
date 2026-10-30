class_name Backdrop
extends Node2D
## Полноэкранный биолюминесцентный океан (аврора / каустика / боке / виньетка).
##
## Материал и ColorRect создаются ровно один раз — в setup(). В _process
## обновляются только юниформы (u_focus, u_focus_strength), никаких пересозданий
## узлов и загрузок шейдера.
##
## Палитра берётся из EvolutionDB (динамически, чтобы не ломать сборку, если
## файл ещё не появился) с мягким fallback'ом на Palette.

const SHADER_PATH := "res://shaders/backdrop.gdshader"
const EVOLUTION_DB_PATH := "res://scripts/core/evolution_db.gd"

## Длительность кросс-фейда палитры при смене эры, секунды.
const TRANSITION_TIME := 2.0
## Скорость подтягивания фокуса к существу.
const FOCUS_SMOOTH := 2.2

## Запасная палитра на 10 эр — если EvolutionDB ещё/уже недоступен.
const FALLBACK_STAGES: Array = [
	{"a": Color(0.45, 0.94, 0.85), "b": Color(0.35, 0.79, 1.00), "glow": Color(0.35, 0.88, 0.96)},
	{"a": Color(0.40, 0.95, 0.78), "b": Color(0.45, 0.72, 1.00), "glow": Color(0.40, 0.90, 0.86)},
	{"a": Color(0.55, 1.00, 0.72), "b": Color(0.35, 0.90, 0.95), "glow": Color(0.45, 1.00, 0.80)},
	{"a": Color(0.75, 1.00, 0.62), "b": Color(0.40, 0.95, 0.80), "glow": Color(0.65, 1.00, 0.66)},
	{"a": Color(1.00, 0.88, 0.62), "b": Color(0.62, 1.00, 0.69), "glow": Color(1.00, 0.90, 0.66)},
	{"a": Color(1.00, 0.74, 0.55), "b": Color(0.95, 0.86, 0.55), "glow": Color(1.00, 0.80, 0.55)},
	{"a": Color(1.00, 0.62, 0.81), "b": Color(1.00, 0.80, 0.60), "glow": Color(1.00, 0.66, 0.84)},
	{"a": Color(0.85, 0.62, 1.00), "b": Color(1.00, 0.62, 0.81), "glow": Color(0.90, 0.68, 1.00)},
	{"a": Color(0.60, 0.75, 1.00), "b": Color(0.85, 0.65, 1.00), "glow": Color(0.70, 0.82, 1.00)},
	{"a": Color(1.00, 0.95, 0.80), "b": Color(0.72, 0.62, 1.00), "glow": Color(1.00, 0.92, 0.78)},
]

var _rect: ColorRect
var _mat: ShaderMaterial
var _built := false

var _stage := -1
var _cur: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _stage_tween: Tween
var _pulse_tween: Tween
var _pulse_value := 0.0

var _elapsed := 0.0
var _view_size := Vector2(1280.0, 720.0)
var _focus_uv := Vector2(0.42, 0.55)
var _focus_drawn := Vector2(-1.0, -1.0)
var _focus_world := Vector2.ZERO
var _focus_explicit := false
var _focus_strength := 0.45
const DEFAULT_FOCUS_UV := Vector2(0.42, 0.55)

var _evo_script: Script
var _evo_probed := false
var _gs_bound := false
var _creature_ref: Node2D
var _creature_probed := false


func _ready() -> void:
	# setup() можно не звать извне — узел самодостаточен.
	setup()


## Строит full-rect ColorRect с шейдером по размеру вьюпорта. Идемпотентно.
func setup() -> void:
	if _built:
		return
	_rect = ColorRect.new()
	_rect.name = "OceanRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_rect.z_index = -64
	add_child(_rect)

	_mat = ShaderMaterial.new()
	var sh: Shader = load(SHADER_PATH) as Shader
	if sh != null:
		_mat.shader = sh
	else:
		push_warning("Backdrop: не удалось загрузить шейдер " + SHADER_PATH)
	_rect.material = _mat
	_mat.set_shader_parameter("u_time_offset", float(randi() % 1000) * 0.137)

	_built = true
	_fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_to_viewport):
		vp.size_changed.connect(_fit_to_viewport)

	var start_stage := 0
	var gs := _bind_game_state()
	if gs != null:
		var si: Variant = gs.get("stage_index")
		if si is int or si is float:
			start_stage = int(si)
	_apply_instant(clampi(start_stage, 0, _stage_count() - 1))
	set_process(true)


func _process(delta: float) -> void:
	if not _built or _mat == null:
		return
	if not _gs_bound:
		# setup() могли вызвать до add_child() — добираем GameState, когда вошли в дерево.
		_bind_game_state()
	_elapsed += delta

	# Опорная точка «тепла» + медленный дрейф: фон живёт, но не уползает.
	# Важно: цель считается от опорной точки, а не от текущего сглаженного
	# значения — иначе получается положительная обратная связь и фокус уезжает.
	var base := DEFAULT_FOCUS_UV
	if _focus_explicit and _view_size.x > 0.0 and _view_size.y > 0.0:
		base = _focus_world / _view_size
	elif not _focus_explicit:
		# Сами находим существо-сосед, чтобы «тепло» фона шло за ним.
		var cr := _find_creature()
		if cr != null and _view_size.x > 0.0 and _view_size.y > 0.0:
			_focus_world = cr.global_position
			base = _focus_world / _view_size
	var target := base + Vector2(sin(_elapsed * 0.13) * 0.020, cos(_elapsed * 0.097) * 0.016)
	_focus_uv = _focus_uv.lerp(target, clampf(delta * FOCUS_SMOOTH, 0.0, 1.0))

	if _focus_uv.distance_squared_to(_focus_drawn) > 0.0000004:
		_focus_drawn = _focus_uv
		_mat.set_shader_parameter("u_focus", _focus_uv)
		var breath := 0.88 + 0.12 * sin(_elapsed * 0.37)
		_mat.set_shader_parameter("u_focus_strength", _focus_strength * breath)


## Плавно (2 c) переключает палитру фона на эру index.
func set_stage(index: int, animated: bool = true) -> void:
	if not _built:
		setup()
	index = clampi(index, 0, _stage_count() - 1)
	if index == _stage:
		return
	if not animated or _cur.is_empty():
		_apply_instant(index)
		return
	_apply_animated(index)


## Короткий всплеск свечения: клик, покупка, смена эры.
func pulse(strength: float = 1.0) -> void:
	if not _built:
		setup()
	strength = clampf(strength, 0.0, 2.0)
	if not is_inside_tree():
		_pulse_value = strength
		if _mat != null:
			_mat.set_shader_parameter("u_pulse", strength)
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_method(_set_pulse, _pulse_value, strength, 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_method(_set_pulse, strength, 0.0, 1.05) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Центр «тепла» фона — обычно позиция существа в мировых координатах.
func set_focus(world_pos: Vector2, strength: float = 0.45) -> void:
	if not _built:
		setup()
	_focus_explicit = true
	_focus_world = world_pos
	_focus_strength = clampf(strength, 0.0, 2.0)


## Множитель скорости анимации фона (0 — «замерший» океан).
func set_time_scale(value: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("u_time_scale", clampf(value, 0.0, 4.0))


func get_current_stage() -> int:
	return _stage


func is_built() -> bool:
	return _built


# --- внутреннее -------------------------------------------------------------

func _fit_to_viewport() -> void:
	if _rect == null:
		return
	var vp := get_viewport()
	if vp != null:
		_view_size = vp.get_visible_rect().size
	if _view_size.x <= 0.0 or _view_size.y <= 0.0:
		_view_size = Vector2(1280.0, 720.0)
	_rect.size = _view_size
	_rect.global_position = Vector2.ZERO
	if _mat != null:
		_mat.set_shader_parameter("u_size", _view_size)


func _get_game_state() -> Node:
	# get_node() с абсолютным путём доступен только из активного дерева сцены.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


## Существо-сосед (узел "Creature" в той же сцене). Нужно только для фокуса:
## если снаружи позицию не передали, фон сам следит за свечением существа.
func _find_creature() -> Node2D:
	if _creature_probed:
		var cached: Variant = _creature_ref
		if cached is Node2D and is_instance_valid(cached):
			return cached as Node2D
		return null
	_creature_probed = true
	if not is_inside_tree():
		return null
	var p := get_parent()
	if p != null:
		var n := p.get_node_or_null("Creature")
		if n is Node2D:
			_creature_ref = n as Node2D
			return n as Node2D
	for n in get_tree().get_nodes_in_group("creature"):
		if n is Node2D:
			_creature_ref = n as Node2D
			return n as Node2D
	return null


func _bind_game_state() -> Node:
	var gs := _get_game_state()
	if gs == null:
		return null
	if not gs.has_signal("stage_changed"):
		return gs
	if not gs.is_connected("stage_changed", _on_stage_changed):
		gs.connect("stage_changed", _on_stage_changed)
	_gs_bound = true
	return gs


func _on_stage_changed(index: int) -> void:
	set_stage(index, true)


func _stage_count() -> int:
	var s := _get_evo_script()
	if s != null:
		var inst: Object = null
		if s.can_instantiate():
			inst = s.new()
		if inst != null and inst.has_method("count"):
			var c: Variant = inst.call("count")
			if (c is int or c is float) and int(c) > 0:
				return int(c)
	return FALLBACK_STAGES.size()


func _get_evo_script() -> Script:
	if _evo_probed:
		return _evo_script
	_evo_probed = true
	if ResourceLoader.exists(EVOLUTION_DB_PATH):
		var res: Resource = load(EVOLUTION_DB_PATH)
		if res is Script:
			_evo_script = res as Script
	return _evo_script


func _fetch_stage_dict(index: int) -> Dictionary:
	var s := _get_evo_script()
	if s == null:
		return {}
	var inst: Object = null
	if s.can_instantiate():
		inst = s.new()
	if inst == null or not inst.has_method("get_stage"):
		return {}
	var d: Variant = inst.call("get_stage", index)
	if d is Dictionary:
		return d as Dictionary
	return {}


func _palette_for_stage(index: int) -> Dictionary:
	var falling: Dictionary = FALLBACK_STAGES[clampi(index, 0, FALLBACK_STAGES.size() - 1)]
	# Акценты: цвет «жизни» (a) и его световой сдвиг (b).
	var a: Color = falling["a"]
	var b: Color = falling["b"]
	var g: Color = falling["glow"]
	# Фон: база из Palette, подкрашенная акцентом эры (когда EvolutionDB нет).
	var count := _stage_count()
	var k := 0.0
	if count > 1:
		k = clampf(float(index) / float(count - 1), 0.0, 1.0)
	var mid: Color = (Palette.BG_MID as Color).lerp(a, 0.10 + 0.20 * k)
	var deep: Color = Palette.BG_DEEP

	# EvolutionDB: color_a/color_b — это ФОН эры, accent/glow — её свет.
	var d := _fetch_stage_dict(index)
	if not d.is_empty():
		var ca: Variant = d.get("color_a")
		var cb: Variant = d.get("color_b")
		var cacc: Variant = d.get("accent")
		var cg: Variant = d.get("glow")
		if ca is Color:
			mid = ca as Color
		if cb is Color:
			deep = cb as Color
		if cacc is Color:
			a = cacc as Color
		if cg is Color:
			g = cg as Color
		if cacc is Color and cg is Color:
			b = (cacc as Color).lerp(g as Color, 0.55)

	return {
		"a": a,
		"b": b,
		"glow": g,
		"mid": Color(mid.r, mid.g, mid.b, 1.0),
		"deep": Color(deep.r, deep.g, deep.b, 1.0),
		"energy": clampf(0.16 + 0.62 * k, 0.16, 0.80),
	}


func _apply_instant(index: int) -> void:
	var pal := _palette_for_stage(index)
	_cur = pal
	if _stage_tween != null and _stage_tween.is_valid():
		_stage_tween.kill()
	_set_uniform_pair("u_col_a", "u_col_a_prev", pal["a"])
	_set_uniform_pair("u_col_b", "u_col_b_prev", pal["b"])
	_set_uniform_pair("u_col_glow", "u_col_glow_prev", pal["glow"])
	_mat.set_shader_parameter("u_col_deep", pal["deep"])
	_mat.set_shader_parameter("u_col_mid", pal["mid"])
	_mat.set_shader_parameter("u_energy", pal["energy"])
	_mat.set_shader_parameter("u_stage_blend", 1.0)
	_stage = index


func _apply_animated(index: int) -> void:
	var pal := _palette_for_stage(index)
	_from = _cur.duplicate()
	_to = pal.duplicate()
	# Акценты кросс-фейдятся прямо в шейдере по u_stage_blend.
	_mat.set_shader_parameter("u_col_a_prev", _from["a"])
	_mat.set_shader_parameter("u_col_b_prev", _from["b"])
	_mat.set_shader_parameter("u_col_glow_prev", _from["glow"])
	_mat.set_shader_parameter("u_col_a", _to["a"])
	_mat.set_shader_parameter("u_col_b", _to["b"])
	_mat.set_shader_parameter("u_col_glow", _to["glow"])
	_mat.set_shader_parameter("u_stage_blend", 0.0)
	_stage = index

	if _stage_tween != null and _stage_tween.is_valid():
		_stage_tween.kill()
	if not is_inside_tree():
		_transition_step(1.0)
		return
	_stage_tween = create_tween()
	_stage_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_stage_tween.tween_method(_transition_step, 0.0, 1.0, TRANSITION_TIME)


func _transition_step(t: float) -> void:
	if _mat == null or _from.is_empty():
		return
	_mat.set_shader_parameter("u_stage_blend", t)
	_mat.set_shader_parameter("u_col_deep", (_from["deep"] as Color).lerp(_to["deep"], t))
	_mat.set_shader_parameter("u_col_mid", (_from["mid"] as Color).lerp(_to["mid"], t))
	_mat.set_shader_parameter("u_energy", lerpf(_from["energy"], _to["energy"], t))
	if t >= 1.0:
		_cur = _to.duplicate()


func _set_uniform_pair(main_name: String, prev_name: String, value: Color) -> void:
	_mat.set_shader_parameter(main_name, value)
	_mat.set_shader_parameter(prev_name, value)


func _set_pulse(value: float) -> void:
	_pulse_value = value
	if _mat != null:
		_mat.set_shader_parameter("u_pulse", value)
