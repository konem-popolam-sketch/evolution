class_name UIKit
extends RefCounted
## Фабрика темы и визуальных примитивов HUD «Эволюция».
##
## Всё оформление процедурное: StyleBoxFlat со скруглениями и мягкими
## полупрозрачными слоями, GradientTexture2D для бликов, шрифт — fallback
## Godot (кириллица поддерживается). Никаких внешних ассетов.
##
## Использование:
##   var theme := UIKit.build_theme()
##   hud.theme = theme
##   var panel := UIKit.make_glass_panel(22, Palette.CYAN)
##   var l := UIKit.make_label("Биомасса", UIKit.FS_MICRO, Palette.TEXT_DIM)

# ---------------------------------------------------------------- размеры шрифтов

const FS_MICRO := 12
const FS_SMALL := 14
const FS_BODY := 16
const FS_SUB := 18
const FS_TITLE := 22
const FS_HEAD := 28
const FS_HERO := 40
const FS_MEGA := 56
const FS_BIG := 64

# ---------------------------------------------------------------- радиусы

const CORNER_PILL := 18
const CORNER_CARD := 16
const CORNER_PANEL := 22
const CORNER_CHIP := 14

const DUR_FAST := 0.14
const DUR_SOFT := 0.28
const DUR_SLOW := 0.55


# ---------------------------------------------------------------- тема

## Собирает тёмную «стеклянную» тему HUD.
static func build_theme() -> Theme:
	var theme := Theme.new()
	var font := ThemeDB.fallback_font
	if font != null:
		theme.default_font = font
	theme.default_font_size = FS_BODY

	_setup_labels(theme)
	_setup_buttons(theme)
	_setup_panels(theme)
	_setup_scrollbars(theme)
	_setup_progress(theme)
	return theme


static func _setup_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", Palette.TEXT)
	theme.set_font_size("font_size", "Label", FS_BODY)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 0)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))
	theme.set_constant("line_spacing", "Label", 2)

	# Вариации подписей (используются через theme_type_variation).
	_variation(theme, "HudMicro", "Label", FS_MICRO, Palette.TEXT_FAINT)
	_variation(theme, "HudSmall", "Label", FS_SMALL, Palette.TEXT_DIM)
	_variation(theme, "HudTitle", "Label", FS_TITLE, Palette.TEXT)
	_variation(theme, "HudHead", "Label", FS_HEAD, Palette.TEXT)

	# RichTextLabel — на случай длинных описаний.
	theme.set_color("default_color", "RichTextLabel", Palette.TEXT_DIM)
	theme.set_font_size("normal_font_size", "RichTextLabel", FS_SMALL)


static func _variation(theme: Theme, name: String, base: String, fs: int, col: Color) -> void:
	theme.set_type_variation(name, base)
	theme.set_font_size("font_size", name, fs)
	theme.set_color("font_color", name, col)


static func _setup_buttons(theme: Theme) -> void:
	var normal := pill_style(Palette.CARD_BG, Palette.fade(Palette.CYAN, 0.10), 0.0)
	var hover := pill_style(Palette.CARD_BG_HOVER, Palette.fade(Palette.CYAN, 0.30), 6.0)
	var pressed := pill_style(Palette.fade(Palette.BG_MID, 0.92), Palette.fade(Palette.CYAN, 0.42), 0.0)
	var disabled := pill_style(Palette.fade(Palette.CARD_BG, 0.45), Palette.fade(Palette.CARD_BORDER, 0.35), 0.0)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", empty_style())

	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Color(1, 1, 1, 1))
	theme.set_color("font_pressed_color", "Button", Palette.CYAN)
	theme.set_color("font_disabled_color", "Button", Palette.TEXT_FAINT)
	theme.set_font_size("font_size", "Button", FS_SMALL)
	theme.set_constant("outline_size", "Button", 0)
	theme.set_constant("h_separation", "Button", 6)

	# Плоская кнопка без рамки и фона (для табов и служебных мест).
	var flat_normal := pill_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0)
	var flat_hover := pill_style(Palette.fade(Palette.CYAN, 0.07), Color(0, 0, 0, 0), 0.0)
	var flat_pressed := pill_style(Palette.fade(Palette.CYAN, 0.12), Color(0, 0, 0, 0), 0.0)
	theme.set_type_variation("HudFlatButton", "Button")
	theme.set_stylebox("normal", "HudFlatButton", flat_normal)
	theme.set_stylebox("hover", "HudFlatButton", flat_hover)
	theme.set_stylebox("pressed", "HudFlatButton", flat_pressed)
	theme.set_stylebox("focus", "HudFlatButton", empty_style())
	theme.set_color("font_color", "HudFlatButton", Palette.TEXT_DIM)
	theme.set_color("font_hover_color", "HudFlatButton", Palette.TEXT)
	theme.set_color("font_pressed_color", "HudFlatButton", Palette.CYAN)
	theme.set_font_size("font_size", "HudFlatButton", FS_SMALL)


static func _setup_panels(theme: Theme) -> void:
	var panel := glass_style(CORNER_PANEL, Palette.PANEL_BG, Palette.fade(Palette.CYAN, 0.10), 1, 18.0)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var card := glass_style(CORNER_CARD, Palette.CARD_BG, Palette.CARD_BORDER, 1, 0.0)
	theme.set_type_variation("HudCard", "PanelContainer")
	theme.set_stylebox("panel", "HudCard", card)


static func _setup_scrollbars(theme: Theme) -> void:
	var track := StyleBoxEmpty.new()
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("scroll", "HScrollBar", track)

	var grabber := glass_style(3, Palette.fade(Palette.TEXT_DIM, 0.26), Color(0, 0, 0, 0), 0, 0.0)
	grabber.set_corner_radius_all(3)
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber", "HScrollBar", grabber)

	var grabber_hl := glass_style(3, Palette.fade(Palette.CYAN, 0.48), Color(0, 0, 0, 0), 0, 0.0)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hl)
	theme.set_stylebox("grabber_highlight", "HScrollBar", grabber_hl)

	var grabber_pr := glass_style(3, Palette.fade(Palette.CYAN, 0.68), Color(0, 0, 0, 0), 0, 0.0)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_pr)
	theme.set_stylebox("grabber_pressed", "HScrollBar", grabber_pr)


static func _setup_progress(theme: Theme) -> void:
	var bg := glass_style(4, Palette.fade(Palette.BG_DEEP, 0.85), Palette.fade(Palette.CYAN, 0.08), 1, 0.0)
	var fill := glass_style(4, Palette.fade(Palette.CYAN, 0.85), Color(0, 0, 0, 0), 0, 6.0)
	fill.shadow_color = Palette.fade(Palette.CYAN, 0.35)
	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_font_size("font_size", "ProgressBar", FS_MICRO)
	theme.set_color("font_color", "ProgressBar", Palette.TEXT_DIM)


# ---------------------------------------------------------------- стили

## Базовый StyleBoxFlat: скругление, фон, рамка, мягкая внешняя тень.
static func glass_style(radius: int, bg: Color, border: Color, border_w: int = 1,
		glow: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.anti_aliasing = true
	s.anti_aliasing_size = 0.7
	if glow > 0.0:
		s.shadow_color = Palette.fade(Palette.CYAN, 0.10)
		s.shadow_size = int(glow)
		s.shadow_offset = Vector2(0, 2)
	return s


## Стиль «таблетки» — кнопки, табы, чипы.
static func pill_style(bg: Color, border: Color, glow: float = 0.0,
		radius: int = CORNER_PILL) -> StyleBoxFlat:
	var s := glass_style(radius, bg, border, 1, glow)
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 7.0
	s.content_margin_bottom = 7.0
	return s


## Стиль круглой кнопки (радиус-«капсула»).
static func circle_style(accent: Color, bg_alpha: float = 0.10, border_alpha: float = 0.24) -> StyleBoxFlat:
	var s := glass_style(99, Palette.fade(accent, bg_alpha), Palette.fade(accent, border_alpha), 1, 8.0)
	s.shadow_color = Palette.fade(accent, 0.16)
	s.shadow_size = 8
	s.content_margin_left = 0.0
	s.content_margin_right = 0.0
	s.content_margin_top = 0.0
	s.content_margin_bottom = 0.0
	return s


## Стиль карточки апгрейда в одном из состояний.
static func card_style(hovered: bool, accent: Color, dimmed: bool = false) -> StyleBoxFlat:
	var bg := Palette.CARD_BG_HOVER if hovered else Palette.CARD_BG
	if dimmed:
		bg = Palette.fade(bg, 0.55)
	var border := Palette.fade(accent, 0.34 if hovered else 0.12)
	if dimmed:
		border = Palette.fade(accent, 0.08)
	var s := glass_style(CORNER_CARD, bg, border, 1, 0.0)
	if hovered:
		s.shadow_color = Palette.fade(accent, 0.18)
		s.shadow_size = 14
		s.shadow_offset = Vector2(0, 3)
	return s


## Пустой стиль (фокус, прозрачные треки).
static func empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## Полупрозрачная «стеклянная» панель с тонким верхним бликом.
## Готовая нода: Panel + градиентный блик, обрезанный по скруглению.
static func make_glass_panel(radius: int = CORNER_PANEL, accent: Color = Palette.CYAN,
		bg: Color = Palette.PANEL_BG, sheen: float = 1.0, glow: float = 18.0) -> Panel:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel",
			glass_style(radius, bg, Palette.fade(accent, 0.12), 1, glow))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sheen > 0.0:
		var top := TextureRect.new()
		top.texture = vertical_gradient(Palette.fade(accent, 0.085 * sheen), Color(0, 0, 0, 0))
		top.stretch_mode = TextureRect.STRETCH_SCALE
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(top)
		top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		top.offset_bottom = -radius * 1.5
		panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	return panel


## Карточка-панель (более светлая, с рамкой акцента).
static func make_card_panel(accent: Color = Palette.CYAN, radius: int = CORNER_CARD) -> Panel:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", card_style(false, accent, false))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


# ---------------------------------------------------------------- градиенты

## Вертикальный градиент как текстура (для бликов/подложек).
static func vertical_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	g.add_point(0.55, Color(
			(top.r + bottom.r) * 0.5, (top.g + bottom.g) * 0.5,
			(top.b + bottom.b) * 0.5, (top.a + bottom.a) * 0.5))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 6
	tex.height = 96
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


## Радиальный градиент — мягкое дыхание свечения под крупными числами.
## Центр = цвет с силой, к краю альфа уходит в ноль; радиус доводится до угла
## (fill_to = 1,1), иначе за пределами круга углы заливаются цветом последнего
## стопа и свечение рисуется жёсткой плашкой.
##
## Важно: при fill_to = (1,1) параметр t — это доля от полудиагонали, поэтому
## на СЕРЕДИНЕ КРОМКИ прямоугольника t ≈ 0.707. Если гасить альфу только к t = 1
## (углы), то по краям текстуры остаётся ~6% цвета и на стыке видна прямая
## линия. Поэтому альфа гарантированно обнуляется к t = 0.66.
static func radial_glow(color: Color, strength: float = 0.55) -> GradientTexture2D:
	var s := clampf(strength, 0.0, 1.0)
	var g := Gradient.new()
	g.set_color(0, Palette.fade(color, s))
	g.set_color(1, Palette.fade(color, 0.0))
	g.add_point(0.24, Palette.fade(color, s * 0.60))
	g.add_point(0.46, Palette.fade(color, s * 0.25))
	g.add_point(0.66, Palette.fade(color, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	return tex


# ---------------------------------------------------------------- подписи

## Обычный лейбл с явными размерами/цветом (без переопределений темы).
static func make_label(text: String, fs: int = FS_BODY, color: Color = Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	return l


## Крупный лейбл с мягким свечением/обводкой (для биомассы и заголовков).
static func make_glow_label(text: String, fs: int, color: Color,
		glow: float = 1.0, outline: int = 0) -> Label:
	var l := make_label(text, fs, color)
	l.add_theme_color_override("font_shadow_color", Palette.fade(Palette.glow(color, 1.15), 0.42 * glow))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Palette.fade(Palette.glow(color, 1.0), 0.16 * glow))
	return l


## Точечный «разделитель» между блоками текста.
static func make_dot(color: Color, radius: float = 2.0) -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(radius * 4.0, radius * 4.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := glass_style(int(radius * 2.0) + 2, Palette.fade(color, 0.75), Color(0, 0, 0, 0), 0, 0.0)
	s.shadow_color = Palette.fade(color, 0.5)
	s.shadow_size = 4
	dot.add_theme_stylebox_override("panel", s)
	return dot


# ---------------------------------------------------------------- утилиты

## Мягкое появление/скрытие через tween (без «дёрганья»).
static func fade_to(control: CanvasItem, target_alpha: float, duration: float = DUR_SOFT) -> Tween:
	var tw := control.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(control, "modulate:a", target_alpha, duration)
	return tw


## Плавное «дыхание» альфы в цикле (свечение, подсказки).
static func breathe(control: CanvasItem, low: float, high: float, duration: float = 2.6) -> Tween:
	control.modulate.a = low
	var tw := control.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.set_loops(0)
	tw.tween_property(control, "modulate:a", high, duration)
	tw.tween_property(control, "modulate:a", low, duration)
	return tw


## «Отказ»: мягкий горизонтальный шейк узла.
static func shake(control: Control, amount: float = 6.0, duration: float = 0.26) -> Tween:
	var base := control.position
	var tw := control.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(control, "position:x", base.x + amount, duration * 0.2)
	tw.tween_property(control, "position:x", base.x - amount * 0.7, duration * 0.2)
	tw.tween_property(control, "position:x", base.x + amount * 0.35, duration * 0.2)
	tw.tween_property(control, "position:x", base.x, duration * 0.4)
	return tw


## Возвращает римское написание индекса эры (I..X).
static func roman(index: int) -> String:
	var r := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return r[clampi(index, 0, r.size() - 1)]
