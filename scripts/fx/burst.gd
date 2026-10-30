class_name Burst
extends Node2D
## Всплеск аддитивных искр в точке. Самоосвобождается, когда искры погасли.

const P := preload("res://scripts/core/palette.gd")
const SELF_PATH := "res://scripts/fx/burst.gd"
const DEFAULT_LIFE := 0.85
const DRAG := 2.6

var _color := P.CYAN
var _parts: Array = []
var _t := 0.0
var _max_t := DEFAULT_LIFE


## Всплеск в мировой точке `global_pos`. `count` искр, `speed` px/c, `size` px.
static func burst(parent: Node, global_pos: Vector2, color: Color, count: int = 16,
		speed: float = 180.0, size: float = 4.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var script: Script = load(SELF_PATH)
	if script == null:
		return
	var b: Variant = script.new()
	b._color = color
	b.z_index = 25
	var n := maxi(1, count)
	for i in n:
		var a := randf() * TAU
		if i > 0 and randf() < 0.5:
			a = TAU * float(i) / float(n) + randf_range(-0.35, 0.35)
		var sp := speed * randf_range(0.35, 1.0)
		var life := DEFAULT_LIFE * randf_range(0.6, 1.15)
		b._parts.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(a), sin(a)) * sp,
			"life": life,
			"max_life": life,
			"size": size * randf_range(0.55, 1.35),
			"hot": randf_range(0.35, 0.85),
		})
		if life > b._max_t:
			b._max_t = life
	parent.add_child(b)
	b.global_position = global_pos


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _process(delta: float) -> void:
	_t += delta
	var alive := 0
	for p in _parts:
		var life: float = float(p["life"])
		if life <= 0.0:
			continue
		life -= delta
		p["life"] = life
		if life <= 0.0:
			continue
		alive += 1
		var vel: Vector2 = p["vel"]
		var pos: Vector2 = p["pos"] + vel * delta
		p["pos"] = pos
		p["vel"] = vel * maxf(0.0, 1.0 - DRAG * delta)
	queue_redraw()
	if alive == 0 or _t >= _max_t + 0.25:
		queue_free()


func _draw() -> void:
	var glow_col := P.glow(_color, 1.9)
	for p in _parts:
		var life: float = float(p["life"])
		if life <= 0.0:
			continue
		var max_life: float = float(p["max_life"])
		var a := clampf(life / max_life, 0.0, 1.0)
		var a2 := a * a
		var pos: Vector2 = p["pos"]
		var vel: Vector2 = p["vel"]
		var sz: float = float(p["size"]) * (0.35 + 0.65 * a)
		# лёгкий трейл
		draw_line(pos, pos - vel * 0.022, P.fade(glow_col, 0.16 * a2), maxf(1.0, sz * 0.7), true)
		draw_circle(pos, sz * 1.6, P.fade(glow_col, 0.10 * a2))
		draw_circle(pos, sz, P.fade(glow_col, 0.42 * a2))
		draw_circle(pos, sz * 0.5, P.fade(P.glow(P.TEXT, 1.4), float(p["hot"]) * 0.55 * a2))
