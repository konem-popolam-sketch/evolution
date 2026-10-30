extends Control
## Полноэкранный SOFT-переход новой эры.
##
## Появление: затемнение, расходящееся кольцо, мягкое свечение, заголовок
## «НОВАЯ ЭРА», имя эры и подпись. Автоскрытие ~2.7 c. Ввод не блокирует:
## mouse_filter = IGNORE, после проигрывания узел просто исчезает.
##
## API: play(stage_index) -> void, сигнал finished.

signal finished

const HOLD := 1.20
const FADE_IN := 0.45
const FADE_OUT := 0.72

var _busy: bool = false
var _built: bool = false

var _veil: ColorRect
var _ring: Ring
var _glow: TextureRect
var _center: VBoxContainer
var _title: Label
var _name_label: Label
var _subtitle: Label
var _divider: Panel


## Расходящееся кольцо эры (процедурно, без текстур).
class Ring extends Control:
	var tint: Color = Palette.CYAN
	var progress: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_progress(v: float) -> void:
		progress = clampf(v, 0.0, 1.0)
		queue_redraw()

	func set_tint(c: Color) -> void:
		tint = c
		queue_redraw()

	func _draw() -> void:
		if progress <= 0.002:
			return
		var c := size * 0.5
		var max_r := minf(size.x, size.y) * 0.52
		var r := lerpf(70.0, max_r, ease(progress, 0.65))
		var a := 1.0 - progress
		draw_arc(c, r, 0.0, TAU, 96, Palette.fade(Palette.glow(tint, 1.45), 0.55 * a), 2.6, true)
		draw_arc(c, r * 0.74, 0.0, TAU, 96, Palette.fade(tint, 0.26 * a), 1.4, true)
		draw_circle(c, r * 0.16, Palette.fade(Palette.glow(tint, 1.2), 0.08 * a))


func _ready() -> void:
	_build()
	visible = false


func _build() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_veil = ColorRect.new()
	_veil.color = Palette.fade(Palette.BG_DEEP, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_glow = TextureRect.new()
	_glow.texture = UIKit.radial_glow(Palette.CYAN, 0.60)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	# Квадратное поле: при растяжении в широкий прямоугольник радиальный
	# градиент читался ровной плашкой вместо ореола.
	_glow.set_anchors_preset(Control.PRESET_CENTER)
	_glow.offset_left = -330.0
	_glow.offset_right = 330.0
	_glow.offset_top = -330.0
	_glow.offset_bottom = 330.0
	_glow.modulate.a = 0.0

	_ring = Ring.new()
	add_child(_ring)
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_center = VBoxContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_theme_constant_override("separation", 6)
	add_child(_center)
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.offset_left = -400.0
	_center.offset_right = 400.0
	_center.offset_top = -150.0
	_center.offset_bottom = 150.0
	_center.pivot_offset = Vector2(400, 150)

	_title = UIKit.make_label("НОВАЯ ЭРА", UIKit.FS_TITLE, Palette.TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.modulate.a = 0.0
	_center.add_child(_title)

	_divider = Panel.new()
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_divider.custom_minimum_size = Vector2(0, 2)
	_divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_divider.modulate.a = 0.0
	_center.add_child(_divider)

	_name_label = UIKit.make_glow_label("", UIKit.FS_BIG, Palette.CYAN, 1.2, 4)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.modulate.a = 0.0
	_center.add_child(_name_label)

	_subtitle = UIKit.make_label("", UIKit.FS_SUB, Palette.TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.modulate.a = 0.0
	_center.add_child(_subtitle)


## Проиграть переход. Повторные вызовы во время проигрывания игнорируются.
func play(stage_index: int) -> void:
	if not _built:
		_build()
	if _busy:
		return
	var stage: Dictionary = EvolutionDB.get_stage(clampi(stage_index, 0, EvolutionDB.count() - 1))
	var accent: Color = Palette.CYAN
	var glow_col: Color = Palette.CYAN
	if stage.get("accent", null) is Color:
		accent = stage["accent"]
	if stage.get("glow", null) is Color:
		glow_col = stage["glow"]

	_name_label.text = String(stage.get("name", "Новая форма"))
	_name_label.add_theme_color_override("font_color", glow_col)
	_name_label.add_theme_color_override("font_shadow_color", Palette.fade(Palette.glow(glow_col, 1.2), 0.5))
	_subtitle.text = String(stage.get("subtitle", ""))
	_glow.texture = UIKit.radial_glow(glow_col, 0.62)
	_ring.tint = accent
	_ring.progress = 0.0
	_ring.queue_redraw()
	_divider.add_theme_stylebox_override("panel",
			UIKit.glass_style(2, Palette.fade(accent, 0.55), Color(0, 0, 0, 0), 0, 6.0))

	_busy = true
	visible = true
	modulate.a = 1.0
	_veil.color = Palette.fade(Palette.BG_DEEP, 0.0)
	_ring.set_progress(0.0)
	_title.modulate.a = 0.0
	_name_label.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_divider.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_center.scale = Vector2(0.972, 0.972)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_veil, "color:a", 0.70, FADE_IN)
	tw.tween_property(_glow, "modulate:a", 0.88, 0.85)
	tw.tween_method(_ring.set_progress, 0.0, 1.0, 1.55)
	tw.tween_property(_center, "scale", Vector2.ONE, 0.95) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_title, "modulate:a", 1.0, 0.50).from(0.0)
	tw.tween_property(_divider, "modulate:a", 1.0, 0.55).from(0.0)
	tw.tween_property(_name_label, "modulate:a", 1.0, 0.70).from(0.0).set_delay(0.10)
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.70).from(0.0).set_delay(0.22)

	await get_tree().create_timer(HOLD + 0.35).timeout
	if not is_inside_tree():
		return
	var out := create_tween()
	out.set_parallel(true)
	out.tween_property(_veil, "color:a", 0.0, FADE_OUT)
	out.tween_property(_glow, "modulate:a", 0.0, FADE_OUT * 0.8)
	out.tween_property(self, "modulate:a", 0.0, FADE_OUT * 0.9)
	await out.finished
	visible = false
	modulate.a = 1.0
	_busy = false
	finished.emit()
