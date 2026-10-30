extends Control
## Модалка статистики: аккуратная стеклянная карточка по центру,
## список ключевых чисел и кнопка полного сброса с двойным подтверждением.
##
## Открывается кнопкой «статистика» в правом нижнем углу HUD,
## закрывается кликом по затемнению или Esc. Пока открыта — блокирует
## ввод в мир, но сама модалка не анимирует ничего в _process, кроме
## отсчёта «времени на подтверждение» (дёшево).

signal reset_requested
signal closed

const ARM_SECONDS := 4.0

var _built: bool = false
var _is_open: bool = false
var _armed: bool = false
var _arm_left: float = 0.0
var _acc: float = 0.0
## Единственный активный твин (открытие ИЛИ закрытие). Старый всегда
## убивается: иначе хвост закрытия вызывал _finish_close уже после нового
## open() и прятал панель, оставляя _is_open == true (ревью M3).
var _tw: Tween = null

var _veil: ColorRect
var _box: Panel
var _pad: MarginContainer
var _rows: VBoxContainer
var _reset_btn: Button
var _reset_hint: Label
var _values: Dictionary = {}   # key -> Label


func _ready() -> void:
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_veil = ColorRect.new()
	_veil.color = Palette.fade(Palette.BG_DEEP, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.gui_input.connect(_on_veil_input)
	add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_box = UIKit.make_glass_panel(UIKit.CORNER_PANEL, Palette.VIOLET, Palette.PANEL_BG, 1.0, 26.0)
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_box)
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.offset_left = -290.0
	_box.offset_right = 290.0
	_box.offset_top = -272.0
	_box.offset_bottom = 272.0
	_box.resized.connect(box_pivot_update)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 20)
	_box.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad = pad

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)

	# --- заголовок
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var title := UIKit.make_glow_label("СТАТИСТИКА", UIKit.FS_HEAD, Palette.TEXT, 0.5)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "закрыть"
	close_btn.theme_type_variation = "HudFlatButton"
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close_panel)
	head.add_child(close_btn)

	var sub := UIKit.make_label("жизнь твоего существа в цифрах", UIKit.FS_MICRO, Palette.TEXT_FAINT)
	col.add_child(sub)

	# --- строки
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 7)
	col.add_child(_rows)

	_add_row("Эра", "era")
	_add_row("Биомасса", "biomass")
	_add_row("Всего биомассы", "total")
	_add_row("Биомасса в секунду", "rate")
	_add_row("За клик", "click")
	_add_row("Множитель", "mult")
	_add_row("ДНК", "dna")
	_add_row("ДНК всего", "dna_total")
	_add_row("Кликов сделано", "clicks")
	_add_row("Престижей", "prestige")
	_add_row("Время в игре", "time")

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 4)
	col.add_child(spacer)

	# --- сброс
	_reset_btn = Button.new()
	_reset_btn.text = "сбросить весь прогресс"
	_reset_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_reset_btn.custom_minimum_size = Vector2(0, 40)
	_reset_btn.add_theme_color_override("font_color", Palette.fade(Palette.DANGER, 0.90))
	_reset_btn.add_theme_color_override("font_hover_color", Palette.DANGER)
	_reset_btn.add_theme_stylebox_override("normal",
			UIKit.pill_style(Palette.fade(Palette.DANGER, 0.06), Palette.fade(Palette.DANGER, 0.22)))
	_reset_btn.add_theme_stylebox_override("hover",
			UIKit.pill_style(Palette.fade(Palette.DANGER, 0.14), Palette.fade(Palette.DANGER, 0.45), 6.0))
	_reset_btn.pressed.connect(_on_reset_pressed)
	col.add_child(_reset_btn)

	_reset_hint = UIKit.make_label("это удалит биомассу, ДНК и все апгрейды",
			UIKit.FS_MICRO, Palette.TEXT_FAINT)
	_reset_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reset_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_reset_hint)

	call_deferred("_fit_box")


## Высота стекла = высота контента + запас, иначе кнопка сброса и подпись
## свисают ниже подложки (нашла приёмка). Нижний запас >= 16 px.
func _fit_box() -> void:
	if _box == null or _pad == null or not is_instance_valid(_pad):
		return
	var extra := 0.0
	var box_style := _box.get_theme_stylebox("panel")
	if box_style is StyleBox:
		extra = box_style.get_minimum_size().y
	var need: float = _pad.get_combined_minimum_size().y + extra + 4.0
	var h: float = clampf(maxf(need, 360.0), 320.0, 660.0)
	if not is_equal_approx(_box.size.y, h):
		_box.offset_top = -h * 0.5
		_box.offset_bottom = h * 0.5
	box_pivot_update()


func _add_row(title: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_rows.add_child(row)

	var key_label := UIKit.make_label(title, UIKit.FS_SMALL, Palette.TEXT_DIM)
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_label)

	var value := UIKit.make_label("—", UIKit.FS_SMALL, Palette.TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	var line := HSeparator.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxEmpty.new()
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	line.add_theme_stylebox_override("separator", s)
	_rows.add_child(line)

	_values[key] = value


# ---------------------------------------------------------------- открытие

func is_open() -> bool:
	return _is_open


## Гасит висящий твин (открытия или закрытия) вместе с его колбэками.
func _kill_tween() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null


func open() -> void:
	if not _built:
		_build()
	# Панель уже на экране и не гаснет — только освежаем числа.
	var already_shown: bool = _is_open and visible and modulate.a > 0.99
	_kill_tween()
	_is_open = true
	visible = true
	modulate.a = 1.0
	_disarm_reset()
	refresh()
	_fit_box()
	set_process(true)
	box_pivot_update()
	if already_shown:
		# Твин уже погашен — доводим визуал до конечного состояния сразу.
		_veil.color = Palette.fade(Palette.BG_DEEP, 0.72)
		_box.scale = Vector2.ONE
		return
	# Один источник правды: visible == _is_open, а альфа всегда доводится до 1.0,
	# даже если открытие перебило незаконченное закрытие (полупрозрачной не остаётся).
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(_veil, "color:a", 0.72, 0.22)
	_tw.tween_property(_box, "scale", Vector2.ONE, 0.26).from(Vector2(0.965, 0.965)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_panel() -> void:
	if not _is_open:
		return
	_is_open = false
	_disarm_reset()
	set_process(false)
	_kill_tween()
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(_veil, "color:a", 0.0, 0.18)
	_tw.tween_property(self, "modulate:a", 0.0, 0.18)
	_tw.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	_tw = null
	visible = false
	modulate.a = 1.0
	_is_open = false
	closed.emit()


func box_pivot_update() -> void:
	if _box != null:
		_box.pivot_offset = _box.size * 0.5


# ---------------------------------------------------------------- данные

func refresh() -> void:
	if not _built:
		return
	_set_value("era", "ЭРА %s · %s" % [UIKit.roman(GameState.stage_index), GameState.stage_name()])
	_set_value("biomass", GameState.format_number(GameState.biomass))
	_set_value("total", GameState.format_number(GameState.total_biomass))
	_set_value("rate", "%s/сек" % GameState.format_number(GameState.get_rate()))
	_set_value("click", GameState.format_number(GameState.get_click_power()))
	_set_value("mult", "×%.2f" % GameState.get_upgrade_multiplier())
	_set_value("dna", GameState.format_number(float(GameState.dna)))
	_set_value("dna_total", GameState.format_number(float(GameState.dna_earned)))
	_set_value("clicks", GameState.format_number(float(GameState.manual_clicks)))
	_set_value("prestige", str(GameState.prestige_count))
	_set_value("time", _format_duration(GameState.playtime))


func _set_value(key: String, text: String) -> void:
	var label: Label = _values.get(key, null)
	if label != null and is_instance_valid(label) and label.text != text:
		label.text = text


static func _format_duration(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%d ч %02d мин" % [h, m]
	if m > 0:
		return "%d мин %02d с" % [m, s]
	return "%d с" % s


# ---------------------------------------------------------------- сброс

func _on_reset_pressed() -> void:
	if not _armed:
		_armed = true
		_arm_left = ARM_SECONDS
		_reset_btn.text = "нажми ещё раз — это необратимо"
		_reset_btn.add_theme_color_override("font_color", Palette.DANGER)
		_reset_btn.add_theme_stylebox_override("normal",
				UIKit.pill_style(Palette.fade(Palette.DANGER, 0.16), Palette.fade(Palette.DANGER, 0.55), 8.0))
		_reset_hint.text = "подтверждение действует 4 секунды"
		_sfx("play_click")
		return

	_disarm_reset()
	_sfx("play_prestige")
	reset_requested.emit()
	refresh()
	_reset_hint.text = "прогресс сброшен — начинаем сначала"


func _disarm_reset() -> void:
	_armed = false
	_arm_left = 0.0
	if _reset_btn == null:
		return
	_reset_btn.text = "сбросить весь прогресс"
	_reset_btn.add_theme_color_override("font_color", Palette.fade(Palette.DANGER, 0.90))
	_reset_btn.add_theme_stylebox_override("normal",
			UIKit.pill_style(Palette.fade(Palette.DANGER, 0.06), Palette.fade(Palette.DANGER, 0.22)))
	if _reset_hint != null:
		_reset_hint.text = "это удалит биомассу, ДНК и все апгрейды"


func _process(delta: float) -> void:
	if not _is_open:
		return
	if _armed:
		_arm_left -= delta
		if _arm_left <= 0.0:
			_disarm_reset()
	_acc += delta
	if _acc >= 0.25:
		_acc = 0.0
		refresh()


# ---------------------------------------------------------------- ввод

func _on_veil_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()


func _sfx(method: String) -> void:
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method(method):
		audio.call(method)
