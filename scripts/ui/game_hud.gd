class_name GameHUD
extends Control
## HUD игры «Эволюция» — единственный корневой UI-узел (по контракту).
##
## Состав (всё строится кодом в bind()):
##   * верх слева  — чип эры «ЭРА III · Амёба» + тонкий прогресс + «до следующей: …»;
##   * верх центр  — крупная биомасса с дышащим свечением и «+N/сек»;
##   * справа      — панель апгрейдов 400 px (UpgradePanel);
##   * низ слева   — кнопка ДНК-престижа с превью награды;
##   * низ справа  — круглые кнопки: звук / статистика / полный сброс;
##   * слои поверх — EvolutionBanner (смена эры), StatsPanel (модалка), тост.
##
## Обновления — из _process с троттлингом THROTTLE (~0.08 c). Тексты
## переписываются только при изменении; узлы не пересоздаются.
## Сигналы GameState обрабатываются точечно, редкие события (покупка,
## новая эра, престиж) обновляют HUD мгновенно.
##
## Центр экрана не перекрывается: панель справа, надписи только по краям.

signal reset_requested

const THROTTLE := 0.08
const BIO_MIN_INTERVAL := 0.045
const RESET_ARM_SECONDS := 4.0
const PRESTIGE_WIDTH := 320.0
const PRESTIGE_MARGIN := 18.0  # зазор блока престижа до нижней кромки экрана

const UpgradePanelScript := preload("res://scripts/ui/upgrade_panel.gd")
const StatsPanelScript := preload("res://scripts/ui/stats_panel.gd")
const BannerScript := preload("res://scripts/ui/evolution_banner.gd")


## Процедурные иконки круглых кнопок (без шрифтовых символов).
class Glyph extends Control:
	var kind: String = "sound"
	var tint: Color = Palette.TEXT_DIM

	func _init(k: String = "sound", t: Color = Palette.TEXT_DIM) -> void:
		kind = k
		tint = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_kind(k: String) -> void:
		kind = k
		queue_redraw()

	func set_tint(c: Color) -> void:
		tint = c
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		if c.x <= 1.0:
			return
		var col := tint
		match kind:
			"stats":
				var base_y := c.y + 7.5
				for i in 3:
					var h := 6.0 + float(i) * 4.0
					var x := c.x - 9.0 + float(i) * 8.0
					draw_rect(Rect2(Vector2(x, base_y - h), Vector2(5.0, h)),
							Palette.fade(col, 0.55 + 0.18 * float(i)), true)
			"reset":
				draw_arc(c, 8.5, -2.55, 1.95, 28, col, 1.9, true)
				var tip_angle := 1.95
				var tip := c + Vector2(cos(tip_angle), sin(tip_angle)) * 8.5
				draw_colored_polygon(PackedVector2Array([
					tip + Vector2(-1.5, -5.0),
					tip + Vector2(5.0, 0.5),
					tip + Vector2(-3.5, 4.0),
				]), col)
			_:
				# "sound" / "muted"
				draw_rect(Rect2(c + Vector2(-9.0, -3.5), Vector2(5.0, 7.0)), col, true)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-4.0, -3.5),
					c + Vector2(2.0, -9.0),
					c + Vector2(2.0, 9.0),
					c + Vector2(-4.0, 3.5),
				]), col)
				if kind == "muted":
					draw_line(c + Vector2(4.0, -8.0), c + Vector2(10.0, 8.0),
							Palette.fade(Palette.DANGER, 0.85), 1.8, true)
				else:
					draw_arc(c + Vector2(1.0, 0.0), 8.0, -0.85, 0.85, 18, col, 1.7, true)
					draw_arc(c + Vector2(1.0, 0.0), 12.5, -0.80, 0.80, 20,
							Palette.fade(col, 0.5), 1.3, true)


var _built: bool = false

# --- тайминги
var _t: float = 0.0
var _acc: float = 0.0
var _bio_pending: bool = false
var _bio_last: float = -1.0

# --- эра
var _era_chip: PanelContainer
var _era_label: Label
var _era_bar: ProgressBar
var _era_next: Label

# --- биомасса
var _glow: TextureRect
var _biomass_label: Label
var _rate_label: Label
var _mult_label: Label

# --- панели и слои
var _upgrade_panel: Control = null
var _banner: Control = null
var _stats: Control = null

# --- престиж
var _prestige_box: PanelContainer
var _prestige_btn: Button
var _prestige_note: Label
var _prestige_pulse: Tween
var _prestige_pulse_paused := false

# --- круглые кнопки / сброс
var _sound_btn: Button
var _sound_glyph: Glyph
var _reset_btn: Button
var _reset_armed: bool = false
var _reset_arm_left: float = 0.0

# --- тост
var _toast: PanelContainer
var _toast_label: Label
var _toast_tw: Tween

var _audio: Node = null


# ================================================================ публичное

## Строит весь интерфейс. Вызывается после add_child (см. контракт).
func bind() -> void:
	if _built:
		return
	_built = true
	theme = UIKit.build_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_top_scrim()
	_build_biomass_glow()
	_build_era_chip()
	_build_biomass_text()
	_build_upgrade_panel()
	_build_prestige()
	_build_corner_buttons()
	_build_banner()
	_build_stats()
	_build_toast()
	_connect_state()

	_update_sound_glyph()
	_refresh_all()
	set_process(true)


## Показать модалку статистики (для main.gd / горячих клавиш).
func show_stats() -> void:
	if _stats != null:
		_stats.open()


## Короткое сообщение внизу по центру.
func toast(text: String, color: Color = Palette.CYAN, duration: float = 5.0) -> void:
	if not _built or _toast == null:
		return
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast.add_theme_stylebox_override("panel",
			UIKit.pill_style(Palette.fade(Palette.BG_MID, 0.94), Palette.fade(color, 0.34), 14.0, 20))
	_toast.visible = true
	_toast.modulate.a = 0.0
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.26)
	_toast_tw.tween_interval(maxf(duration, 0.5))
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.45)
	_toast_tw.tween_callback(_hide_toast)


func _hide_toast() -> void:
	if _toast != null:
		_toast.visible = false


func is_stats_open() -> bool:
	return _stats != null and _stats.is_open()


# ================================================================ построение

func _build_top_scrim() -> void:
	# Мягкий тёмный градиент сверху: лежит НАД миром, ПОД текстом HUD,
	# клики не ловит. Нужен, чтобы светлый фон не съедал крупное число.
	var scrim := TextureRect.new()
	scrim.texture = _scrim_texture()
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	scrim.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scrim.offset_left = 0.0
	scrim.offset_right = 0.0
	scrim.offset_top = 0.0
	scrim.offset_bottom = 250.0


## Вертикальный скрим: тёмный сверху -> полностью прозрачный снизу.
## Свой градиент, а не UIKit.vertical_gradient: у того на краю остаётся
## полупрозрачная кромка и на светлом фоне видна полоса.
func _scrim_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([
		Palette.fade(Palette.BG_DEEP, 0.55),
		Palette.fade(Palette.BG_DEEP, 0.26),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 8
	tex.height = 128
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


## Мягкое дыхание свечения: яркий центр -> прозрачные края.
## Радиус доводится до угла (fill_to = 1,1), иначе углы текстуры заливаются
## цветом последней точки и свечение выглядит квадратом. Альфы низкие:
## под числом должен читаться ореол, а не заливка фона.
## Альфа обнуляется уже к t = 0.66: при fill_to (1,1) середина кромки — это
## t ≈ 0.707, и если гасить только к углам, по краям текстуры остаётся ~1.5%
## цвета, что даёт видимую прямую линию на стыке.
func _glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.44, 0.66, 1.0])
	g.colors = PackedColorArray([
		Palette.fade(Palette.CYAN, 0.24),
		Palette.fade(Palette.CYAN, 0.15),
		Palette.fade(Palette.CYAN, 0.05),
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	return tex


func _build_biomass_glow() -> void:
	_glow = TextureRect.new()
	_glow.texture = _glow_texture()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	# Квадратный rect с центром на числе: широкий прямоугольник читался
	# ровной бирюзовой плашкой с резкими краями.
	_glow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_glow.offset_left = -260.0
	_glow.offset_right = 260.0
	_glow.offset_top = -170.0
	_glow.offset_bottom = 350.0
	_glow.modulate.a = 0.85
	_glow.resized.connect(func() -> void: _glow.pivot_offset = _glow.size * 0.5)

	# Дыхание свечения: один зацикленный Tween, ничего не создаётся в кадре.
	var bt := create_tween()
	bt.set_loops()
	bt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bt.tween_property(_glow, "modulate:a", 0.62, 2.7)
	bt.parallel().tween_property(_glow, "scale", Vector2(1.05, 1.05), 2.7)
	bt.tween_property(_glow, "modulate:a", 0.88, 2.7)
	bt.parallel().tween_property(_glow, "scale", Vector2.ONE, 2.7)


func _build_era_chip() -> void:
	# PanelContainer сам считает высоту по содержимому — пустого низа нет.
	_era_chip = PanelContainer.new()
	_era_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_era_chip.add_theme_stylebox_override("panel",
			UIKit.glass_style(UIKit.CORNER_CHIP, Palette.fade(Palette.PANEL_BG, 0.70),
					Palette.fade(Palette.CYAN, 0.22), 1, 12.0))
	add_child(_era_chip)
	_era_chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_era_chip.offset_left = 20.0
	_era_chip.offset_top = 18.0
	# Высота по содержимому: жёсткие 86 px подрезали нижнюю строку.
	_era_chip.custom_minimum_size = Vector2(268, 86)
	_era_chip.offset_right = 288.0
	_era_chip.offset_bottom = 104.0

	# Внутренние отступы: у glass_style их нет, и текст лип к самой рамке.
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 11)
	pad.add_theme_constant_override("margin_bottom", 11)
	_era_chip.add_child(pad)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)

	_era_label = UIKit.make_glow_label("ЭРА I · Амёба", UIKit.FS_SUB, Palette.TEXT, 0.35)
	col.add_child(_era_label)

	_era_bar = ProgressBar.new()
	_era_bar.show_percentage = false
	_era_bar.min_value = 0.0
	_era_bar.max_value = 1.0
	_era_bar.step = 0.001
	_era_bar.value = 0.0
	_era_bar.custom_minimum_size = Vector2(0, 7)
	_era_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_era_bar)

	_era_next = UIKit.make_label("до следующей: —", UIKit.FS_MICRO, Palette.TEXT_DIM)
	col.add_child(_era_next)

	# Подгоняем под фактическую высоту содержимого (шрифт может быть крупнее).
	_era_chip.reset_size()


func _build_biomass_text() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 9)
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -300.0
	box.offset_right = 300.0
	box.offset_top = 10.0
	box.offset_bottom = 150.0

	_biomass_label = UIKit.make_glow_label("0", UIKit.FS_BIG, Palette.TEXT, 1.15, 6)
	_biomass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_biomass_label)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 10)
	box.add_child(line)

	_rate_label = UIKit.make_label("+0/сек", UIKit.FS_SUB, Palette.CYAN)
	line.add_child(_rate_label)

	_mult_label = UIKit.make_label("", UIKit.FS_MICRO, Palette.TEXT_DIM)
	_mult_label.add_theme_font_size_override("font_size", 11)
	_mult_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_mult_label)


func _build_upgrade_panel() -> void:
	_upgrade_panel = UpgradePanelScript.new()
	add_child(_upgrade_panel)
	_upgrade_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_upgrade_panel.offset_left = -420.0
	_upgrade_panel.offset_right = -20.0
	_upgrade_panel.offset_top = 16.0
	_upgrade_panel.offset_bottom = -104.0
	_upgrade_panel.purchased.connect(_on_purchased)


func _build_prestige() -> void:
	# Панель по содержимому: стеклянная плашка с внутренними отступами.
	# Раньше это был голый VBox с фиксированной высотой — подпись переносилась
	# и вылезала за стекло, а сам блок висел на кромке экрана.
	_prestige_box = PanelContainer.new()
	_prestige_box.add_theme_stylebox_override("panel",
			UIKit.glass_style(UIKit.CORNER_PANEL, Palette.fade(Palette.PANEL_BG, 0.74),
					Palette.fade(Palette.VIOLET, 0.24), 1, 14.0))
	add_child(_prestige_box)
	_prestige_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_prestige_box.offset_left = 22.0
	_prestige_box.offset_right = 22.0 + PRESTIGE_WIDTH
	_prestige_box.offset_top = -160.0
	_prestige_box.offset_bottom = -PRESTIGE_MARGIN
	# Блок виден всегда: при выключенной кнопке игрок видит, что механика есть,
	# и что нужно для её открытия (нашла приёмка).

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	_prestige_box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)

	_prestige_btn = Button.new()
	_prestige_btn.text = "ДНК-ПРЕСТИЖ"
	_prestige_btn.focus_mode = Control.FOCUS_NONE
	_prestige_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_prestige_btn.custom_minimum_size = Vector2(0, 46)
	_prestige_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prestige_btn.add_theme_font_size_override("font_size", UIKit.FS_BODY)
	_prestige_btn.add_theme_color_override("font_color", Palette.TEXT)
	_prestige_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	_prestige_btn.add_theme_color_override("font_disabled_color", Palette.TEXT_FAINT)
	_prestige_btn.add_theme_stylebox_override("normal",
			UIKit.pill_style(Palette.fade(Palette.VIOLET, 0.16), Palette.fade(Palette.VIOLET, 0.42), 14.0))
	_prestige_btn.add_theme_stylebox_override("hover",
			UIKit.pill_style(Palette.fade(Palette.VIOLET, 0.26), Palette.fade(Palette.VIOLET, 0.66), 20.0))
	_prestige_btn.add_theme_stylebox_override("pressed",
			UIKit.pill_style(Palette.fade(Palette.VIOLET, 0.34), Palette.fade(Palette.VIOLET, 0.80), 0.0))
	_prestige_btn.add_theme_stylebox_override("disabled",
			UIKit.pill_style(Palette.fade(Palette.PANEL_BG, 0.62), Palette.fade(Palette.VIOLET, 0.18)))
	_prestige_btn.pressed.connect(_on_prestige_pressed)
	col.add_child(_prestige_btn)

	_prestige_note = UIKit.make_label("", UIKit.FS_MICRO, Palette.TEXT_FAINT)
	_prestige_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Одна строка: панель подстраивается по высоте, а кегль подбирается по ширине.
	_prestige_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	_prestige_note.clip_text = false
	col.add_child(_prestige_note)

	call_deferred("_fit_prestige")

	_prestige_pulse = create_tween()
	_prestige_pulse.set_loops()
	_prestige_pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_prestige_pulse.tween_property(_prestige_btn, "modulate:a", 0.88, 2.2)
	_prestige_pulse.tween_property(_prestige_btn, "modulate:a", 1.00, 2.2)


## Подгоняет высоту панели престижа под содержимое и держит зазор до кромки.
func _fit_prestige() -> void:
	if _prestige_box == null:
		return
	_prestige_box.offset_left = 22.0
	_prestige_box.offset_right = 22.0 + PRESTIGE_WIDTH
	_prestige_box.offset_bottom = -PRESTIGE_MARGIN
	var h: float = _prestige_box.get_combined_minimum_size().y
	_prestige_box.offset_top = -PRESTIGE_MARGIN - h


## Подбирает кегль подписи так, чтобы строка влезала в панель без переноса.
func _fit_prestige_note() -> void:
	if _prestige_note == null:
		return
	var avail: float = PRESTIGE_WIDTH - 28.0
	var font: Font = _prestige_note.get_theme_font("font")
	var chosen: int = UIKit.FS_MICRO
	for fs in [UIKit.FS_MICRO, 11, 10]:
		var w: float = font.get_string_size(_prestige_note.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
		if w <= avail:
			chosen = int(fs)
			break
		chosen = int(fs)
	if _prestige_note.get_theme_font_size("font_size") != chosen:
		_prestige_note.add_theme_font_size_override("font_size", chosen)


func _build_corner_buttons() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.offset_left = -168.0
	row.offset_right = -22.0
	row.offset_top = -64.0
	row.offset_bottom = -22.0

	_sound_btn = _make_round_button("sound", Palette.CYAN, "Звук")
	_sound_btn.pressed.connect(_on_sound_pressed)
	_sound_glyph = _sound_btn.get_meta("glyph") as Glyph
	row.add_child(_sound_btn)

	var stats_btn := _make_round_button("stats", Palette.AQUA, "Статистика")
	stats_btn.pressed.connect(_on_stats_pressed)
	row.add_child(stats_btn)

	_reset_btn = _make_round_button("reset", Palette.DANGER, "Полный сброс")
	_reset_btn.pressed.connect(_on_reset_pressed)
	row.add_child(_reset_btn)


func _make_round_button(kind: String, accent: Color, tooltip: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(42, 42)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.tooltip_text = tooltip
	btn.add_theme_stylebox_override("normal", UIKit.circle_style(accent, 0.09, 0.24))
	btn.add_theme_stylebox_override("hover", UIKit.circle_style(accent, 0.18, 0.46))
	btn.add_theme_stylebox_override("pressed", UIKit.circle_style(accent, 0.26, 0.62))
	btn.add_theme_stylebox_override("focus", UIKit.empty_style())
	var glyph := Glyph.new(kind, Palette.fade(accent, 0.92))
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_child(glyph)
	btn.set_meta("glyph", glyph)
	return btn


func _build_banner() -> void:
	_banner = BannerScript.new()
	add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_stats() -> void:
	_stats = StatsPanelScript.new()
	add_child(_stats)
	_stats.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stats.reset_requested.connect(_do_reset)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast.add_theme_stylebox_override("panel",
			UIKit.pill_style(Palette.fade(Palette.BG_MID, 0.94), Palette.fade(Palette.CYAN, 0.30), 14.0, 20))
	add_child(_toast)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -310.0
	_toast.offset_right = 310.0
	_toast.offset_top = -136.0
	_toast.offset_bottom = -84.0

	_toast_label = UIKit.make_label("", UIKit.FS_SMALL, Palette.TEXT)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toast.add_child(_toast_label)


# ================================================================ сигналы

func _connect_state() -> void:
	if not GameState.biomass_changed.is_connected(_on_biomass_changed):
		GameState.biomass_changed.connect(_on_biomass_changed)
	if not GameState.rate_changed.is_connected(_on_rate_changed):
		GameState.rate_changed.connect(_on_rate_changed)
	if not GameState.upgrade_purchased.is_connected(_on_upgrade_purchased):
		GameState.upgrade_purchased.connect(_on_upgrade_purchased)
	if not GameState.upgrade_unlocked.is_connected(_on_upgrade_unlocked):
		GameState.upgrade_unlocked.connect(_on_upgrade_unlocked)
	if not GameState.stage_changed.is_connected(_on_stage_changed):
		GameState.stage_changed.connect(_on_stage_changed)
	if not GameState.prestige_done.is_connected(_on_prestige_done):
		GameState.prestige_done.connect(_on_prestige_done)
	if not GameState.stats_changed.is_connected(_on_stats_changed):
		GameState.stats_changed.connect(_on_stats_changed)
	if not GameState.game_loaded.is_connected(_on_game_loaded):
		GameState.game_loaded.connect(_on_game_loaded)


func _on_biomass_changed(_value: float) -> void:
	_bio_pending = true
	if _t - _bio_last >= BIO_MIN_INTERVAL:
		_bio_last = _t
		_bio_pending = false
		_update_biomass()


func _on_rate_changed(_rate: float) -> void:
	_update_rate()


func _on_upgrade_purchased(_id: String, _level: int) -> void:
	if _upgrade_panel != null:
		_upgrade_panel.refresh()
	_update_biomass()
	_update_rate()


func _on_upgrade_unlocked(_id: String) -> void:
	if _upgrade_panel != null:
		_upgrade_panel.refresh()


func _on_stage_changed(index: int) -> void:
	if _banner != null:
		_banner.play(index)
	_sfx("play_stage_up")
	_audio_call("set_stage", [index])
	_update_era()
	_refresh_all()


func _on_prestige_done(gained_dna: int, count: int) -> void:
	toast("ДНК +%d · новый цикл №%d" % [gained_dna, count], Palette.VIOLET, 4.5)
	_refresh_all()


func _on_stats_changed() -> void:
	if _stats != null and _stats.is_open():
		_stats.refresh()


func _on_game_loaded(first_time: bool, offline_gain: float, offline_seconds: float) -> void:
	if first_time or offline_gain <= 0.0:
		return
	toast("Пока тебя не было %s — +%s биомассы"
			% [_format_duration(offline_seconds), GameState.format_number(offline_gain)],
			Palette.CYAN, 7.0)


func _on_purchased(_id: String, _level: int) -> void:
	# Панель уже сама сыграла вспышку/звук — здесь только мгновенные числа.
	_update_biomass()
	_update_rate()


# ================================================================ кнопки

func _on_sound_pressed() -> void:
	GameState.muted = not GameState.muted
	_audio_call("set_muted", [GameState.muted])
	_update_sound_glyph()
	if not GameState.muted:
		_sfx("play_click")


func _update_sound_glyph() -> void:
	if _sound_glyph == null:
		return
	var muted: bool = GameState.muted
	_sound_glyph.set_kind("muted" if muted else "sound")
	_sound_glyph.set_tint(Palette.TEXT_FAINT if muted else Palette.fade(Palette.CYAN, 0.92))


func _on_stats_pressed() -> void:
	_sfx("play_click")
	if _stats != null:
		_stats.open()


func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_arm_left = RESET_ARM_SECONDS
		_reset_btn.add_theme_stylebox_override("normal",
				UIKit.circle_style(Palette.DANGER, 0.24, 0.62))
		toast("Нажми ещё раз, чтобы сбросить весь прогресс", Palette.DANGER, RESET_ARM_SECONDS - 0.4)
		_sfx("play_click")
		return
	_disarm_reset()
	_do_reset()


func _disarm_reset() -> void:
	_reset_armed = false
	_reset_arm_left = 0.0
	if _reset_btn != null:
		_reset_btn.add_theme_stylebox_override("normal",
				UIKit.circle_style(Palette.DANGER, 0.09, 0.24))


func _do_reset() -> void:
	GameState.reset_progress()
	reset_requested.emit()
	toast("Прогресс сброшен — океан ждёт новое существо", Palette.TEXT_DIM, 4.5)
	_refresh_all()


func _on_prestige_pressed() -> void:
	if not GameState.can_prestige():
		return
	_sfx("play_prestige")
	GameState.do_prestige()
	_refresh_all()


# ================================================================ обновление

func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	if _reset_armed:
		_reset_arm_left -= delta
		if _reset_arm_left <= 0.0:
			_disarm_reset()
	_acc += delta
	if _acc >= THROTTLE:
		_acc = 0.0
		_bio_pending = false
		_refresh_all()
	elif _bio_pending and _t - _bio_last >= BIO_MIN_INTERVAL:
		_bio_last = _t
		_bio_pending = false
		_update_biomass()


func _refresh_all() -> void:
	_update_era()
	_update_biomass()
	_update_rate()
	_update_prestige()
	if _upgrade_panel != null:
		_upgrade_panel.refresh()


func _update_era() -> void:
	if _era_label == null:
		return
	var index: int = GameState.stage_index
	var title := "ЭРА %s · %s" % [UIKit.roman(index), GameState.stage_name()]
	if _era_label.text != title:
		_era_label.text = title
	var progress := clampf(GameState.stage_progress(), 0.0, 1.0)
	_era_bar.value = progress
	var threshold := GameState.next_stage_threshold()
	var next_text := "финальная эра"
	if threshold > 0.0:
		next_text = "до следующей: %s" % GameState.format_number(
				maxf(threshold - GameState.total_biomass, 0.0))
	if _era_next.text != next_text:
		_era_next.text = next_text


func _update_biomass() -> void:
	if _biomass_label == null:
		return
	var text := GameState.format_number(GameState.biomass)
	if _biomass_label.text != text:
		_biomass_label.text = text


func _update_rate() -> void:
	if _rate_label == null:
		return
	var text := "+%s/сек" % GameState.format_number(GameState.get_rate())
	if _rate_label.text != text:
		_rate_label.text = text
	var mult := GameState.get_upgrade_multiplier()
	var mult_text := "×%.2f" % mult if mult > 1.005 else ""
	if _mult_label.text != mult_text:
		_mult_label.text = mult_text


## Порог ДНК-престижа живёт ТОЛЬКО в ядре (game_state.gd:202) — здесь нет ни
## своей константы, ни своей формулы (ревью M6). Если ядро отдаст порог
## напрямую, используется его метод; иначе порог ищется как обратная задача к
## prestige_gain_preview() на «песочном» экземпляре того же скрипта — баланс
## по-прежнему правится в одном месте. Ответ кэшируется по dna_earned.
var _prestige_threshold_cache: float = -1.0
var _prestige_threshold_dna: int = -1


func _prestige_threshold() -> float:
	if GameState.has_method("prestige_threshold"):
		return float(GameState.call("prestige_threshold"))
	if _prestige_threshold_cache >= 0.0 and _prestige_threshold_dna == GameState.dna_earned:
		return _prestige_threshold_cache
	var probe: Node = GameState.get_script().new()
	if probe == null:
		return 0.0
	probe.set("dna_earned", GameState.dna_earned)
	var hi: float = 1.0
	while _probe_gain(probe, hi) <= 0 and hi < 1e15:
		hi *= 2.0
	var lo: float = 0.0
	for i in 80:
		var mid: float = (lo + hi) * 0.5
		if _probe_gain(probe, mid) > 0:
			hi = mid
		else:
			lo = mid
	probe.free()
	_prestige_threshold_cache = hi
	_prestige_threshold_dna = GameState.dna_earned
	return hi


func _probe_gain(probe: Node, total: float) -> int:
	probe.set("total_biomass", total)
	return int(probe.call("prestige_gain_preview"))


func _update_prestige() -> void:
	if _prestige_box == null:
		return
	# Кнопка не исчезает: пока престиж недоступен, она заблокирована и
	# подпись объясняет, сколько биомассы осталось до открытия ДНК.
	var can: bool = GameState.can_prestige()
	_prestige_btn.disabled = not can
	# Tween в Godot 4 не имеет свойства paused: останавливаем пульс методами.
	if _prestige_pulse != null and _prestige_pulse.is_valid():
		if can:
			if _prestige_pulse_paused:
				_prestige_pulse_paused = false
				_prestige_pulse.play()
		elif not _prestige_pulse_paused:
			_prestige_pulse_paused = true
			_prestige_pulse.pause()
	if can:
		var gain: int = GameState.prestige_gain_preview()
		var btn_text := "ДНК-ПРЕСТИЖ · +%d" % gain
		if _prestige_btn.text != btn_text:
			_prestige_btn.text = btn_text
		var note := "сброс биомассы и апгрейдов, ДНК остаётся"
		if _prestige_note.text != note:
			_prestige_note.text = note
			_fit_prestige_note()
			_fit_prestige()
		return
	var need_total: float = _prestige_threshold()
	var left: float = maxf(0.0, need_total - GameState.total_biomass)
	if _prestige_btn.text != "ДНК-ПРЕСТИЖ":
		_prestige_btn.text = "ДНК-ПРЕСТИЖ"
	# Короткая формулировка: строка должна влезать в панель в один ряд.
	var hint := "откроется на %s · осталось %s" % [
		GameState.format_number(need_total), GameState.format_number(left)]
	if _prestige_note.text != hint:
		_prestige_note.text = hint
		_fit_prestige_note()
		_fit_prestige()


# ================================================================ утилиты

func _format_duration(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	if total < 60:
		return "%d с" % total
	var days := total / 86400
	var hours := (total % 86400) / 3600
	var minutes := (total % 3600) / 60
	if days > 0:
		return "%d д %d ч" % [days, hours]
	if hours > 0:
		return "%d ч %02d мин" % [hours, minutes]
	return "%d мин" % minutes


func _audio_node() -> Node:
	if _audio == null or not is_instance_valid(_audio):
		_audio = get_node_or_null("/root/AudioDirector")
	return _audio


func _sfx(method: String) -> void:
	var audio := _audio_node()
	if audio != null and audio.has_method(method):
		audio.call(method)


func _audio_call(method: String, args: Array) -> void:
	var audio := _audio_node()
	if audio != null and audio.has_method(method):
		audio.callv(method, args)
