extends SceneTree
## Визуальная проба фона: 120 кадров, смена эр, пульсы, ресайз.
## Запуск: godot_run_headless(script="tests/visual_backdrop_probe.gd").

const FRAMES := 120

var _backdrop: Node
var _frames := 0
var _failed := false


func _initialize() -> void:
	print("=== BACKDROP PROBE ===")
	var script: Resource = load("res://scripts/visual/backdrop.gd")
	if script == null or not (script is Script):
		_fail("не загрузился scripts/visual/backdrop.gd")
		return
	var shader: Resource = load("res://shaders/backdrop.gdshader")
	if shader == null or not (shader is Shader):
		_fail("не загрузился shaders/backdrop.gdshader")
		return
	print("shader uniforms: ", (shader as Shader).get_shader_uniform_list().size())
	var shader_ok := true
	for u in (shader as Shader).get_shader_uniform_list():
		if u.has("name") and str(u["name"]) == "u_stage_blend":
			shader_ok = true
	if not shader_ok:
		_fail("в шейдере нет u_stage_blend")
		return

	_backdrop = (script as Script).new()
	root.add_child(_backdrop)
	_backdrop.setup()
	if not _backdrop.is_built():
		_fail("Backdrop не собрался в setup()")
		return
	if _backdrop.get_current_stage() != 0:
		_fail("стартовая эра не 0: %d" % _backdrop.get_current_stage())
		return

	# Проверяем API и переходы.
	_backdrop.set_focus(Vector2(420.0, 380.0), 1.0)
	_backdrop.pulse(1.2)
	_backdrop.set_stage(4, true)
	_backdrop.set_time_scale(1.0)
	print("stage after set_stage(4): ", _backdrop.get_current_stage())


func _process(delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		if _backdrop != null:
			_backdrop.set_stage(7, true)
			_backdrop.pulse(0.8)
	if _frames == 60:
		if _backdrop != null:
			_backdrop.set_stage(9, false)
			_backdrop.set_focus(Vector2(640.0, 300.0), 1.4)
	if _frames >= FRAMES:
		if _failed:
			return true
		if _backdrop == null or _backdrop.get_current_stage() != 9:
			printerr("PROBE FAIL: финальная эра не 9")
			quit(1)
			return true
		print("PROBE OK: %d кадров, эра %d, фон жив" % [_frames, int(_backdrop.get_current_stage())])
		quit(0)
		return true
	return false


func _fail(reason: String) -> void:
	_failed = true
	printerr("PROBE FAIL: " + reason)
	quit(1)
