extends Node2D
## Сборка сцены «Эволюция»: фон, существо, частицы, FX, HUD.
## Все визуальные узлы — отдельные скрипты команды; если файла ещё нет,
## узел просто не создаётся (игра остаётся играбельной).

const PATH_BACKDROP := "res://scripts/visual/backdrop.gd"
const PATH_CREATURE := "res://scripts/visual/creature.gd"
const PATH_MOTES := "res://scripts/fx/motes.gd"
const PATH_HUD := "res://scripts/ui/game_hud.gd"
const PATH_FLOATING_TEXT := "res://scripts/fx/floating_text.gd"
const PATH_BURST := "res://scripts/fx/burst.gd"
const PATH_RIPPLE := "res://scripts/fx/ripple.gd"

var backdrop: Node = null
var creature: Node = null
var motes: Node = null
var hud: Node = null
var fx_layer: Node2D = null
var ui_layer: CanvasLayer = null
var _hint: Label = null

var _click_cooldown: float = 0.0


func _ready() -> void:
	_setup_environment()
	fx_layer = Node2D.new()
	fx_layer.name = "FXLayer"
	add_child(fx_layer)

	backdrop = _spawn(PATH_BACKDROP, "Backdrop")
	creature = _spawn(PATH_CREATURE, "Creature")
	motes = _spawn(PATH_MOTES, "Motes")

	if creature != null:
		creature.position = get_viewport_rect().size * Vector2(0.42, 0.52)
		if creature.has_method("setup"):
			creature.call("setup")
	if backdrop != null and backdrop.has_method("setup"):
		backdrop.call("setup")
	if motes != null and motes.has_method("setup"):
		motes.call("setup")

	_build_hud()
	_build_hint()
	_apply_stage(GameState.stage_index, false)

	GameState.stage_changed.connect(_on_stage_changed)
	GameState.biomass_changed.connect(_on_biomass_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	set_process(true)


func _process(delta: float) -> void:
	if _click_cooldown > 0.0:
		_click_cooldown = maxf(0.0, _click_cooldown - delta)


func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 1.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	we.environment = env
	add_child(we)


func _spawn(script_path: String, node_name: String) -> Node:
	if not ResourceLoader.exists(script_path):
		return null
	var script: Script = load(script_path)
	if script == null or not script.can_instantiate():
		return null
	var inst: Variant = script.new()
	var node: Node = inst as Node
	if node == null:
		return null
	node.name = node_name
	add_child(node)
	return node


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)
	ui_layer = layer
	if not ResourceLoader.exists(PATH_HUD):
		return
	var script: Script = load(PATH_HUD)
	if script == null or not script.can_instantiate():
		return
	var inst: Variant = script.new()
	var control: Node = inst as Node
	if control == null:
		return
	control.name = "GameHUD"
	layer.add_child(control)
	hud = control
	if hud.has_method("bind"):
		hud.call("bind")
	if hud.has_signal("reset_requested"):
		hud.connect("reset_requested", Callable(self, "_on_reset_requested"))


## Мягкая подсказка первого запуска: гаснет после первого клика по воде
## (или сама через 20 c), чтобы игрок понял основное действие без туториала.
func _build_hint() -> void:
	if ui_layer == null:
		return
	var label := Label.new()
	label.name = "FirstHint"
	label.text = "кликай по воде — так рождается жизнь"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.52, 0.74, 0.77, 0.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.0))
	ui_layer.add_child(label)
	_hint = label
	_layout_hint()

	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_method(_set_hint_alpha, 0.0, 0.62, 1.4)
	tween.tween_interval(17.0)
	tween.tween_method(_set_hint_alpha, 0.62, 0.0, 1.6)
	tween.tween_callback(_drop_hint)


func _layout_hint() -> void:
	if _hint == null or not is_instance_valid(_hint):
		return
	var vp := get_viewport_rect().size
	# Держим подсказку в свободной воде: слева от панели апгрейдов и выше
	# блока престижа, чтобы она ничего не перекрывала.
	var free_w := minf(vp.x * 0.66, 940.0)
	_hint.size = Vector2(520.0, 26.0)
	_hint.position = Vector2((free_w - _hint.size.x) * 0.5, vp.y - 196.0)


func _set_hint_alpha(a: float) -> void:
	if _hint == null or not is_instance_valid(_hint):
		return
	_hint.add_theme_color_override("font_color", Color(0.52, 0.74, 0.77, a))


func _drop_hint() -> void:
	if _hint == null or not is_instance_valid(_hint):
		_hint = null
		return
	_hint.queue_free()
	_hint = null


func _fade_hint_away() -> void:
	if _hint == null or not is_instance_valid(_hint):
		return
	var node := _hint
	_hint = null
	var tween := create_tween()
	tween.tween_method(func(a: float) -> void:
		if is_instance_valid(node):
			node.add_theme_color_override("font_color", Color(0.52, 0.74, 0.77, a)), 0.62, 0.0, 0.9)
	tween.tween_callback(Callable(node, "queue_free"))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _click_cooldown > 0.0:
		return
	_click_cooldown = 0.06
	var pos := get_global_mouse_position()
	var gained := GameState.tap(pos)
	if gained <= 0.0:
		return
	_on_click_feedback(pos, gained)


func _on_click_feedback(pos: Vector2, gained: float) -> void:
	var accent := _stage_color()
	if creature != null and creature.has_method("play_tap"):
		creature.call("play_tap")
	_spawn_fx_burst(pos, accent)
	_spawn_fx_ripple(pos, accent)
	var text := "+" + GameState.format_number(gained)
	_spawn_fx_text(pos + Vector2(0, -28), text, accent)
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("play_click"):
		audio.call("play_click")
	if backdrop != null and backdrop.has_method("pulse"):
		backdrop.call("pulse", 0.35)
	if _hint != null and GameState.manual_clicks >= 1:
		_fade_hint_away()


func _spawn_fx_text(pos: Vector2, text: String, color: Color) -> void:
	if not ResourceLoader.exists(PATH_FLOATING_TEXT):
		return
	var script: Script = load(PATH_FLOATING_TEXT)
	if script == null:
		return
	if script.has_method("spawn"):
		script.call("spawn", fx_layer, pos, text, color, 26, false)
	else:
		var inst: Variant = script.new()
		var node: Node = inst as Node
		if node != null:
			fx_layer.add_child(node)
			if node.has_method("spawn"):
				node.call("spawn", fx_layer, pos, text, color, 26, false)


func _spawn_fx_burst(pos: Vector2, color: Color) -> void:
	_call_static_fx(PATH_BURST, "burst", [fx_layer, pos, color, 14, 150.0, 3.5])


func _spawn_fx_ripple(pos: Vector2, color: Color) -> void:
	_call_static_fx(PATH_RIPPLE, "ripple", [fx_layer, pos, color, 16.0, 120.0, 0.8])


func _call_static_fx(path: String, method: String, args: Array) -> void:
	if not ResourceLoader.exists(path):
		return
	var script: Script = load(path)
	if script == null:
		return
	if script.has_method(method):
		script.callv(method, args)
		return
	var inst: Variant = script.new()
	var node: Node = inst as Node
	if node != null and node.has_method(method):
		node.callv(method, args)
		fx_layer.add_child(node)


func _apply_stage(index: int, animated: bool) -> void:
	if backdrop != null and backdrop.has_method("set_stage"):
		backdrop.call("set_stage", index, animated)
	if creature != null and creature.has_method("play_stage_morph"):
		creature.call("play_stage_morph", index)
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("set_stage"):
		audio.call("set_stage", index)


func _on_stage_changed(index: int) -> void:
	_apply_stage(index, true)
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("play_stage_up"):
		audio.call("play_stage_up")
	if creature != null and creature.has_method("play_tap"):
		creature.call("play_tap")


func _on_biomass_changed(_value: float) -> void:
	pass


func _on_reset_requested() -> void:
	# Сброс уже выполнен в GameHUD._do_reset() (сброс -> emit). Второй вызов
	# reset_progress() давал двойной save_game() и двойной каскад сигналов.
	# Здесь только возвращаем визуал к первой эре.
	_apply_stage(GameState.stage_index, false)
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("set_stage"):
		audio.call("set_stage", GameState.stage_index)


func _on_viewport_resized() -> void:
	if creature != null:
		creature.position = get_viewport_rect().size * Vector2(0.42, 0.52)
	_layout_hint()


func _stage_color() -> Color:
	var stages := []
	if ResourceLoader.exists("res://scripts/core/evolution_db.gd"):
		var script: Script = load("res://scripts/core/evolution_db.gd")
		if script != null and script.has_method("all"):
			var arr: Variant = script.call("all")
			if typeof(arr) == TYPE_ARRAY:
				stages = arr
	if GameState.stage_index >= 0 and GameState.stage_index < stages.size():
		var st: Dictionary = stages[GameState.stage_index]
		return st.get("accent", Palette.CYAN)
	return Palette.CYAN
