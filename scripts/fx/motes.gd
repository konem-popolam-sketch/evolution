class_name Motes
extends Node2D
## Фоновые биолюминесцентные «мотыльки»: медленно плывут вверх, мерцают,
## тянутся на весь вьюпорт. Аддитивное смешивание, HDR-цвета.

const P := preload("res://scripts/core/palette.gd")
const COUNT := 84
const BLOOMS := 4

var _motes: Array = []
var _blooms: Array = []
var _ready_done := false
var _time := 0.0
var _glow_tex: Texture2D


## Инициализация. Идемпотентна; вызывается капитаном после add_child.
func setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

	var cols := [P.CYAN, P.AQUA, P.VIOLET, P.GOLD, P.PINK]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20241107
	for i in COUNT:
		_motes.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"speed": rng.randf_range(0.004, 0.021),
			"sway": rng.randf_range(0.4, 1.8),
			"phase": rng.randf() * TAU,
			"size": rng.randf_range(0.9, 3.2),
			"color": cols[rng.randi_range(0, cols.size() - 1)],
			"twinkle": rng.randf_range(0.5, 1.9),
		})
	for i in BLOOMS:
		_blooms.append({
			"x": rng.randf_range(0.1, 0.9),
			"y": rng.randf_range(0.1, 0.9),
			"radius": rng.randf_range(70.0, 130.0),
			"color": cols[rng.randi_range(0, cols.size() - 1)],
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.01, 0.03),
		})
	_glow_tex = _make_radial_texture()
	queue_redraw()


func _ready() -> void:
	setup()


func _process(delta: float) -> void:
	setup()
	_time += delta
	queue_redraw()


func _draw() -> void:
	setup()
	if not is_inside_tree():
		return
	var vp := get_viewport_rect()
	var origin := to_local(vp.position)
	var sz := vp.size
	if sz.x <= 1.0 or sz.y <= 1.0:
		return

	# Крупные туманные пятна света — мягкий радиальный градиент, без диска.
	for b in _blooms:
		var bx := fposmod(float(b["x"]) + sin(_time * 0.07 + float(b["phase"])) * 0.03, 1.0)
		var by := fposmod(float(b["y"]) + _time * float(b["speed"]), 1.0)
		var p := origin + Vector2(bx * sz.x, by * sz.y)
		var col: Color = b["color"]
		var rad: float = b["radius"]
		var pulse := 0.75 + 0.25 * sin(_time * 0.5 + float(b["phase"]))
		if _glow_tex != null:
			var rect := Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
			draw_texture_rect(_glow_tex, rect, false, P.fade(P.glow(col, 1.15), 0.045 * pulse))

	# Мелкие светящиеся точки.
	for m in _motes:
		var y := fposmod(float(m["y"]) + _time * float(m["speed"]), 1.0)
		var x := fposmod(float(m["x"]) + sin(_time * 0.25 + float(m["phase"])) * 0.022 * float(m["sway"]), 1.0)
		var p := origin + Vector2(x * sz.x, y * sz.y)
		var tw := 0.55 + 0.45 * sin(_time * float(m["twinkle"]) + float(m["phase"]))
		var col: Color = m["color"]
		var s: float = m["size"]
		draw_circle(p, s * (1.0 + 0.25 * tw), P.fade(P.glow(col, 1.5), 0.09 + 0.16 * tw))
		draw_circle(p, s * 0.45, P.fade(P.TEXT, 0.10 + 0.16 * tw))


func _make_radial_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.70, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.50),
		Color(1.0, 1.0, 1.0, 0.13),
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
