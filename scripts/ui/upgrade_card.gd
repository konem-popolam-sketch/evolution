extends PanelContainer
## Карточка одного апгрейда в панели роста/мутаций/симбиоза/ДНК.
##
## Отвечает только за показ и ввод: цена/подсказка приходят уже
## отформатированными строками от UpgradePanel. Покупку совершает панель
## (через GameState), карточка лишь сообщает о нажатии.
##
## Состояния карточки:
##   ST_AFFORDABLE — доступно (золотая цена, подсветка рамки);
##   ST_POOR       — не хватает валюты (тусклая цена, подсказка «не хватает…»);
##   ST_LOCKED     — заблокировано (подсказка «откроется…»);
##   ST_MAX        — максимальный уровень.
##
## Анимации: наведение (мягкая подсветка + микро-масштаб), нажатие (сжатие),
## покупка (вспышка + расходящееся кольцо), отказ (лёгкий наклон + красная цена).
## Всё на Tween, без аллокаций в _process.

signal purchase_requested(item_id: String)

const ST_AFFORDABLE := 0
const ST_POOR := 1
const ST_LOCKED := 2
const ST_MAX := 3

const CARD_HEIGHT := 92.0

var item_id: String = ""

var _item: Dictionary = {}
var _accent: Color = Palette.CYAN
var _state: int = ST_LOCKED
var _hovered: bool = false
var _pressed: bool = false
var _dimmed: bool = false
var _built: bool = false

var _sigil: Control
var _flash: Control
var _name_label: Label
var _level_label: Label
var _desc_label: Label
var _effect_label: Label
var _price_label: Label
var _hint_label: Label

var _hover_tw: Tween
var _press_tw: Tween
var _reject_tw: Tween

## Кэш stylebox по (hovered, dimmed): карточка обновляется ~12 раз в секунду,
## а StyleBoxFlat на каждый тик — это лишняя перестройка темы (ревью M4).
## Пересоздаётся только при смене акцента (setup).
var _styles: Dictionary = {}      # int(hovered) * 2 + int(dimmed) -> StyleBoxFlat
var _styles_accent: Color = Color(0, 0, 0, 0)
var _panel_style: StyleBox = null


## Внутренняя иконка-сигил: процедурное кольцо с ядром, тонированное цветом апгрейда.
class Sigil extends Control:
	var tint: Color = Color(1, 1, 1, 1)
	var dim: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(40, 40)

	func set_look(t: Color, is_dim: bool) -> void:
		tint = t
		dim = is_dim
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		if r <= 0.0:
			return
		var a_outer := 0.20 if dim else 0.62
		var a_inner := 0.14 if dim else 0.38
		var a_core := 0.28 if dim else 0.92
		draw_circle(c, r, Palette.fade(tint, 0.09 if not dim else 0.045))
		draw_arc(c, r * 0.88, 0.0, TAU, 40, Palette.fade(tint, a_outer), 1.6, true)
		draw_arc(c, r * 0.60, 0.0, TAU, 34, Palette.fade(tint, a_inner), 1.2, true)
		draw_circle(c, r * 0.26, Palette.fade(Palette.glow(tint, 1.25), a_core))


## Вспышка покупки: затухающее кольцо и мягкая заливка.
class Flash extends Control:
	var tint: Color = Palette.CYAN
	var amount: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func set_amount(v: float) -> void:
		amount = clampf(v, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		if amount <= 0.002:
			return
		var c := size * 0.5
		var r := lerpf(minf(size.x, size.y) * 0.30, maxf(size.x, size.y) * 0.72, 1.0 - amount)
		draw_circle(c, r, Palette.fade(tint, 0.16 * amount))
		draw_arc(c, r, 0.0, TAU, 56, Palette.fade(Palette.glow(tint, 1.35), 0.42 * amount), 2.0, true)


func _ready() -> void:
	_build()


## Данные апгрейда до входа в дерево (панель вызывает сразу после new()).
func setup(item: Dictionary) -> void:
	_item = item
	item_id = String(item.get("id", ""))
	var col: Color = Palette.CYAN
	var raw = item.get("color", null)
	if raw is Color:
		col = raw
	_accent = col
	if _built:
		_apply_look()


func _build() -> void:
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, CARD_HEIGHT)
	add_theme_stylebox_override("panel", _style_for(false, true))
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	gui_input.connect(_on_gui_input)

	_flash = Flash.new()
	_flash.tint = _accent
	add_child(_flash)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	_sigil = Sigil.new()
	_sigil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sigil.set_look(_accent, true)
	row.add_child(_sigil)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	col.add_child(top)

	_name_label = UIKit.make_label(String(_item.get("name", "")), UIKit.FS_BODY, Palette.TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	# Усечение по границе слова: посимвольный трим давал «Поток питательных вещ…».
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	_name_label.tooltip_text = String(_item.get("name", ""))
	top.add_child(_name_label)

	_effect_label = UIKit.make_label(_effect_text(), UIKit.FS_MICRO, Palette.fade(_accent, 0.92))
	_effect_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_effect_label)

	_level_label = UIKit.make_label("", UIKit.FS_MICRO, Palette.TEXT_DIM)
	_level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_level_label)

	_desc_label = UIKit.make_label(String(_item.get("desc", "")), UIKit.FS_MICRO, Palette.TEXT_FAINT)
	_desc_label.clip_text = true
	_desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_desc_label)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 8)
	col.add_child(bottom)

	_price_label = UIKit.make_label("", UIKit.FS_SMALL, Palette.GOLD)
	_price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price_label.clip_text = true
	_price_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom.add_child(_price_label)

	_hint_label = UIKit.make_label("", UIKit.FS_MICRO, Palette.TEXT_FAINT)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_hint_label)

	_apply_look()


## Текст эффекта. ВАЖНО: для множительных эффектов `value` — доля прироста
## (0.06 => «×1.06 за уровень», ядро делает pow(1.0 + value, level)),
## для аддитивных — абсолютная прибавка.
func _effect_text() -> String:
	var eff := String(_item.get("effect", ""))
	var value: float = float(_item.get("value", 0.0))
	match eff:
		"ps_mult", "click_mult", "all_mult":
			return "×%.2f" % (1.0 + value)
		"ps_add":
			return "+%s/сек" % _fmt_value(value)
		"click_add":
			return "+%s/клик" % _fmt_value(value)
		"auto_click":
			return "+%s/сек авто" % _fmt_value(value)
	return ""


func _fmt_value(v: float) -> String:
	var a := absf(v)
	if a >= 100.0:
		return "%.0f" % v
	if a >= 10.0:
		return "%.1f" % v
	if a >= 1.0:
		return "%.1f" % v
	if a >= 0.1:
		return "%.2f" % v
	return "%.3f" % v


func _on_resized() -> void:
	pivot_offset = size * 0.5


## Обновление состояния. Вызывается панелью на каждом троттл-тике (~0.08 c),
## поэтому тексты меняются только при реальном отличии.
func apply(level: int, state: int, price_text: String, hint_text: String) -> void:
	if not _built:
		_build()
	_state = state
	var max_level: int = int(_item.get("max_level", 1))
	_set_text(_level_label, "ур. %d" % level if max_level > 1 else "")
	if state == ST_MAX:
		_set_text(_price_label, "МАКСИМУМ")
		_set_color(_price_label, Palette.CYAN)
	elif state == ST_LOCKED:
		_set_text(_price_label, "закрыто")
		_set_color(_price_label, Palette.TEXT_FAINT)
	else:
		_set_text(_price_label, price_text)
		_set_color(_price_label, Palette.GOLD if state == ST_AFFORDABLE else Palette.TEXT_DIM)
	_set_text(_hint_label, hint_text)
	_apply_look()


func _apply_look() -> void:
	if not _built:
		return
	var dimmed := (_state == ST_LOCKED or _state == ST_MAX)
	var style := _style_for(_hovered, dimmed)
	if style != _panel_style:
		_panel_style = style
		add_theme_stylebox_override("panel", style)
	if dimmed != _dimmed:
		_dimmed = dimmed
		_sigil.set_look(_accent, dimmed)
		modulate = Color(1, 1, 1, 0.78) if dimmed else Color(1, 1, 1, 1)
	_set_color(_name_label, Palette.TEXT_FAINT if _state == ST_LOCKED else Palette.TEXT)


## Четыре варианта рамки на карточку, создаются один раз на акцент.
func _style_for(hovered: bool, dimmed: bool) -> StyleBox:
	if _styles.is_empty() or _styles_accent != _accent:
		_styles_accent = _accent
		_styles.clear()
		for d in [false, true]:
			for h in [false, true]:
				_styles[(1 if h else 0) * 2 + (1 if d else 0)] = UIKit.card_style(
						h and not d, _accent, d)
	return _styles[(1 if hovered else 0) * 2 + (1 if dimmed else 0)]


func _set_color(label: Label, color: Color) -> void:
	if label == null:
		return
	if not label.has_theme_color_override("font_color") \
			or label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


# ---------------------------------------------------------------- ввод

func _on_hover(entered: bool) -> void:
	if _hovered == entered:
		return
	_hovered = entered
	_apply_look()
	if _hover_tw != null and _hover_tw.is_valid():
		_hover_tw.kill()
	var target := 1.012 if (entered and not _dimmed) else 1.0
	_hover_tw = create_tween()
	_hover_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hover_tw.tween_property(self, "scale", Vector2.ONE * target, 0.16)


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_pressed = true
		_press(0.975)
	else:
		if not _pressed:
			return
		_pressed = false
		_press(1.0 if not _hovered else 1.012)
		if get_global_rect().has_point(get_global_mouse_position()):
			if _state == ST_AFFORDABLE:
				purchase_requested.emit(item_id)
			else:
				reject()


func _press(target: float) -> void:
	if _press_tw != null and _press_tw.is_valid():
		_press_tw.kill()
	_press_tw = create_tween()
	_press_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_press_tw.tween_property(self, "scale", Vector2.ONE * target, 0.10)


## Вспышка успешной покупки.
func flash_purchase() -> void:
	if not _built:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(_flash.set_amount, 1.0, 0.0, 0.55)
	tw.tween_property(self, "scale", Vector2.ONE * 1.03, 0.12)
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_delay(0.12)


## Мягкий отказ: карточка «качнулась», цена мигнула красным.
func reject() -> void:
	if not _built:
		return
	if _reject_tw != null and _reject_tw.is_valid():
		_reject_tw.kill()
	_price_label.add_theme_color_override("font_color", Palette.DANGER)
	_reject_tw = create_tween()
	_reject_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reject_tw.tween_property(self, "rotation", 0.018, 0.06)
	_reject_tw.tween_property(self, "rotation", -0.014, 0.08)
	_reject_tw.tween_property(self, "rotation", 0.0, 0.12)
	_reject_tw.tween_callback(_restore_price_color)


func _restore_price_color() -> void:
	if not _built:
		return
	if _state == ST_MAX:
		_set_color(_price_label, Palette.CYAN)
	elif _state == ST_LOCKED:
		_set_color(_price_label, Palette.TEXT_FAINT)
	elif _state == ST_AFFORDABLE:
		_set_color(_price_label, Palette.GOLD)
	else:
		_set_color(_price_label, Palette.TEXT_DIM)
