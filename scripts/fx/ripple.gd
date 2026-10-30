class_name Ripple
extends Node2D
## Расходящееся мягкое кольцо (клик по миру, смена эры). Самоосвобождается.

const P := preload("res://scripts/core/palette.gd")
const SELF_PATH := "res://scripts/fx/ripple.gd"

var _color := P.CYAN
var _start := 20.0
var _end := 160.0
var _duration := 0.9
var _t := 0.0


## Кольцо от `start_radius` до `end_radius` за `duration` секунд.
static func ripple(parent: Node, global_pos: Vector2, color: Color, start_radius: float = 20.0,
		end_radius: float = 160.0, duration: float = 0.9) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var script: Script = load(SELF_PATH)
	if script == null:
		return
	var r: Variant = script.new()
	r._color = color
	r._start = start_radius
	r._end = maxf(end_radius, start_radius + 1.0)
	r._duration = maxf(0.1, duration)
	r.z_index = 24
	parent.add_child(r)
	r.global_position = global_pos


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= _duration:
		queue_free()


func _draw() -> void:
	var k := clampf(_t / _duration, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 2.0)
	var radius := lerpf(_start, _end, ease_k)
	var fade := pow(1.0 - k, 1.6)
	var glow_col := P.glow(_color, 1.8)

	# тонкий блик по фронту волны
	for i in 3:
		var rr := radius * (1.0 - 0.045 * float(i))
		if rr <= 0.5:
			continue
		var w := 3.4 - 0.9 * float(i)
		var a := fade * (0.55 - 0.15 * float(i))
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 72, P.fade(glow_col, a), maxf(1.0, w), true)

	# мягкая заливка внутри кольца
	draw_circle(Vector2.ZERO, radius, P.fade(glow_col, 0.035 * fade))
