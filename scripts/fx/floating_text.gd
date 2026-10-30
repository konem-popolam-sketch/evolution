class_name FloatingText
extends Node2D
## Всплывающий текст («+12», «-250», названия эр). Самоосвобождается.

const P := preload("res://scripts/core/palette.gd")
const SELF_PATH := "res://scripts/fx/floating_text.gd"
const BASE_LIFE := 1.2
const RISE := 78.0

var _text := ""
var _color := P.TEXT
var _size := 30
var _crit := false
var _life := BASE_LIFE
var _t := 0.0
var _drift := Vector2.ZERO
var _sparks: Array = []


## Создать всплывающий текст над `global_pos`. `crit` — крупнее, с искрами.
static func spawn(parent: Node, global_pos: Vector2, text: String, color: Color,
		size: int = 30, crit: bool = false) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var script: Script = load(SELF_PATH)
	if script == null:
		return
	var ft: Variant = script.new()
	ft._text = text
	ft._color = color
	ft._size = maxi(12, size)
	ft._crit = crit
	ft._life = BASE_LIFE * (1.35 if crit else 1.0)
	ft._drift = Vector2(randf_range(-16.0, 16.0), 0.0)
	ft.z_index = 30
	if crit:
		for i in 9:
			var a := randf() * TAU
			ft._sparks.append({
				"dir": Vector2(cos(a), sin(a)),
				"speed": randf_range(38.0, 96.0),
				"size": randf_range(1.2, 2.6),
			})
	parent.add_child(ft)
	ft.global_position = global_pos


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= _life:
		queue_free()


func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	if f == null:
		return
	var k := clampf(_t / _life, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 2.4)
	var offset := Vector2(_drift.x * ease_k, -RISE * ease_k)
	var fade := 1.0 - smoothstep(0.58, 1.0, k)
	var pop := clampf(_t / 0.14, 0.0, 1.0)
	var scale_v := lerpf(0.72, 1.0, pop)
	if _crit:
		scale_v *= 1.0 + 0.12 * (1.0 - pop) + 0.05 * sin(_t * 16.0) * (1.0 - pop)

	# искры вокруг всплывающего текста
	if not _sparks.is_empty():
		var spark_fade := clampf(1.0 - _t / 0.55, 0.0, 1.0)
		if spark_fade > 0.0:
			var glow_s := P.glow(_color, 1.9)
			for sp in _sparks:
				var dir: Vector2 = sp["dir"]
				var p: Vector2 = offset + dir * (float(sp["speed"]) * _t) + Vector2(0.0, 26.0 * _t * _t)
				draw_circle(p, float(sp["size"]) * spark_fade, P.fade(glow_s, 0.55 * spark_fade))

	var fs := _size
	var w := f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_set_transform(Vector2(offset.x, offset.y + fs * 0.35), 0.0, Vector2(scale_v, scale_v))

	var glow_col := P.glow(_color, 1.8)
	for i in 3:
		draw_string_outline(f, Vector2(-w * 0.5, 0.0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			7 - i * 2, P.fade(glow_col, (0.10 + 0.07 * float(i)) * fade))
	draw_string(f, Vector2(-w * 0.5, 2.0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			P.fade(P.BG_DEEP, 0.35 * fade))
	draw_string(f, Vector2(-w * 0.5, 0.0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			P.fade(P.TEXT, 0.95 * fade))
