extends Control
## Правая панель апгрейдов: заголовок, вкладки категорий, прокручиваемый
## список карточек. Панель же совершает покупку (через GameState), играет
## звук и анимацию вспышки.
##
## Владельцы:
##   scripts/ui/upgrade_card.gd  — карточка;
##   этот файл                   — вкладки, список, экономика клика.
##
## Обновляется из GameHUD на троттл-тике ~0.08 c: пересобираются только
## изменившиеся тексты, узлы не пересоздаются (кроме смены вкладки/набора
## категорий и появления новых апгрейдов).

signal purchased(item_id: String, level: int)

const CardScript := preload("res://scripts/ui/upgrade_card.gd")

const ST_AFFORDABLE := 0
const ST_POOR := 1
const ST_LOCKED := 2
const ST_MAX := 3

const PANEL_PAD := 14

var _audio: Node = null
var _built: bool = false

var _tabs_bar: HBoxContainer
var _cards_box: VBoxContainer
var _scroll: ScrollContainer
var _empty_label: Label
var _mult_label: Label

var _tab: String = "рост"
var _tabs_sig: String = ""
var _cards: Dictionary = {}      # id -> Control (UpgradeCard)
var _order: Array[String] = []   # порядок id в списке
var _tab_buttons: Dictionary = {}  # category -> Button


func _ready() -> void:
	_build()
	refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Стеклянная подложка на всю панель.
	var bg := UIKit.make_glass_panel(UIKit.CORNER_PANEL, Palette.AQUA)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", PANEL_PAD + 4)
	pad.add_theme_constant_override("margin_right", PANEL_PAD + 4)
	pad.add_theme_constant_override("margin_top", PANEL_PAD)
	pad.add_theme_constant_override("margin_bottom", PANEL_PAD)
	add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)

	# --- заголовок
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)

	var title := UIKit.make_glow_label("АПГРЕЙДЫ", UIKit.FS_TITLE, Palette.TEXT, 0.55)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	_mult_label = UIKit.make_label("", UIKit.FS_MICRO, Palette.CYAN)
	_mult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mult_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_mult_label)

	var subtitle := UIKit.make_label("формируй своё существо", UIKit.FS_MICRO, Palette.TEXT_FAINT)
	col.add_child(subtitle)

	# --- вкладки
	_tabs_bar = HBoxContainer.new()
	_tabs_bar.add_theme_constant_override("separation", 4)
	col.add_child(_tabs_bar)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sep_style := StyleBoxEmpty.new()
	sep_style.content_margin_top = 2
	sep_style.content_margin_bottom = 2
	sep.add_theme_stylebox_override("separator", sep_style)
	col.add_child(sep)

	# --- список карточек
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)

	_cards_box = VBoxContainer.new()
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_cards_box)

	_empty_label = UIKit.make_label("здесь пока пусто — продолжай расти", UIKit.FS_SMALL, Palette.TEXT_FAINT)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	col.add_child(_empty_label)

	_build_bottom_fade()


## Мягкое затухание списка у нижней кромки панели: последняя карточка
## уходит в темноту, а не обрывается ровной линией. Клики не ловит.
func _build_bottom_fade() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var solid := Palette.fade(Palette.PANEL_BG, 0.92)
	g.colors = PackedColorArray([
		Color(solid.r, solid.g, solid.b, 0.0),
		Palette.fade(Palette.PANEL_BG, 0.62),
		solid,
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 8
	tex.height = 128
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)

	var fade := TextureRect.new()
	fade.texture = tex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_left = 1.0
	fade.offset_right = -1.0
	fade.offset_top = -96.0
	fade.offset_bottom = -1.0


# ---------------------------------------------------------------- обновление

## Полное обновление панели (вызывается HUD'ом на троттл-тике).
func refresh() -> void:
	if not _built:
		_build()
	_sync_tabs()

	if _mult_label != null:
		var mult := GameState.get_upgrade_multiplier()
		var txt := "×%.2f" % mult if mult > 1.005 else ""
		if _mult_label.text != txt:
			_mult_label.text = txt

	var items: Array = UpgradeDB.by_category(_tab)
	var visible_items: Array = []
	var keep := {}
	for raw in items:
		var item: Dictionary = raw
		var id := String(item.get("id", ""))
		if id == "":
			continue
		visible_items.append(item)
		keep[id] = true

	# Убираем карточки, которых больше нет в этой категории.
	for id in _cards.keys():
		if not keep.has(id):
			var dead: Control = _cards[id]
			_cards.erase(id)
			if is_instance_valid(dead):
				dead.queue_free()

	var idx := 0
	for raw in visible_items:
		var item: Dictionary = raw
		var id := String(item.get("id", ""))
		var card: Control = _cards.get(id, null)
		if card == null or not is_instance_valid(card):
			card = CardScript.new()
			card.setup(item)
			card.purchase_requested.connect(_on_card_purchase)
			_cards[id] = card
			_cards_box.add_child(card)
		else:
			_cards_box.move_child(card, idx)
		idx += 1
		var state := _state_for(item)
		card.apply(GameState.get_upgrade_level(id), state, _price_text(item, state), _hint_text(item, state))

	_empty_label.visible = visible_items.is_empty()
	if _scroll != null:
		_scroll.visible = not visible_items.is_empty()


func _state_for(item: Dictionary) -> int:
	var id := String(item.get("id", ""))
	if not GameState.is_upgrade_available(id):
		return ST_LOCKED
	if GameState.get_upgrade_level(id) >= int(item.get("max_level", 1)):
		return ST_MAX
	if GameState.can_buy(id):
		return ST_AFFORDABLE
	return ST_POOR


func _price_text(item: Dictionary, state: int) -> String:
	if state == ST_MAX:
		return "МАКСИМУМ"
	var cost := GameState.get_upgrade_cost(String(item.get("id", "")))
	if is_inf(cost):
		return "МАКСИМУМ"
	if String(item.get("currency", "biomass")) == "dna":
		return "%s ДНК" % GameState.format_number(cost)
	return "%s биомассы" % GameState.format_number(cost)


func _hint_text(item: Dictionary, state: int) -> String:
	match state:
		ST_MAX:
			return "предел роста"
		ST_LOCKED:
			var unlock_stage: int = int(item.get("unlock_stage", 0))
			if unlock_stage > GameState.stage_index:
				return "откроется позже"
			var unlock_total: float = float(item.get("unlock_total", 0.0))
			if unlock_total > 0.0:
				return "всего %s" % GameState.format_number(unlock_total)
			return "недоступно"
		ST_POOR:
			var cost := GameState.get_upgrade_cost(String(item.get("id", "")))
			if is_inf(cost):
				return ""
			var have := GameState.biomass
			if String(item.get("currency", "biomass")) == "dna":
				have = float(GameState.dna)
			return "не хватает %s" % GameState.format_number(maxf(cost - have, 0.0))
		_:
			return "готово к покупке"


# ---------------------------------------------------------------- вкладки

func _sync_tabs() -> void:
	var cats := _categories()
	var sig := "|".join(PackedStringArray(cats))
	if sig == _tabs_sig:
		return
	_tabs_sig = sig
	for child in _tabs_bar.get_children():
		child.queue_free()
	_tab_buttons.clear()
	if not cats.has(_tab):
		_tab = String(cats[0]) if not cats.is_empty() else "рост"
	for cat in cats:
		var btn := Button.new()
		btn.text = _tab_title(String(cat))
		btn.theme_type_variation = "HudFlatButton"
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = false
		btn.pressed.connect(_on_tab_pressed.bind(String(cat)))
		_tabs_bar.add_child(btn)
		_tab_buttons[cat] = btn
	_paint_tabs()


func _categories() -> Array:
	var cats: Array = UpgradeDB.categories()
	if cats.is_empty():
		cats = ["рост"]
	return cats


func _tab_title(cat: String) -> String:
	if cat == "днк":
		return "ДНК"
	return cat.capitalize()


func _paint_tabs() -> void:
	for cat in _tab_buttons.keys():
		var btn: Button = _tab_buttons[cat]
		if not is_instance_valid(btn):
			continue
		var active: bool = String(cat) == _tab
		btn.add_theme_color_override("font_color", Palette.CYAN if active else Palette.TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", Palette.TEXT)
		if active:
			var s := UIKit.pill_style(Palette.fade(Palette.CYAN, 0.12), Palette.fade(Palette.CYAN, 0.30), 0.0)
			s.content_margin_left = 6.0
			s.content_margin_right = 6.0
			btn.add_theme_stylebox_override("normal", s)
		else:
			var s2 := UIKit.pill_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0)
			s2.content_margin_left = 6.0
			s2.content_margin_right = 6.0
			btn.add_theme_stylebox_override("normal", s2)


func _on_tab_pressed(cat: String) -> void:
	if _tab == cat:
		return
	_tab = cat
	_paint_tabs()
	_sfx("play_click")
	refresh()


# ---------------------------------------------------------------- покупка

func _on_card_purchase(id: String) -> void:
	var card: Control = _cards.get(id, null)
	if not GameState.is_upgrade_available(id) or not GameState.can_buy(id):
		if card != null and is_instance_valid(card):
			card.reject()
		return
	if GameState.buy_upgrade(id):
		if card != null and is_instance_valid(card):
			card.flash_purchase()
		_sfx("play_buy")
		purchased.emit(id, GameState.get_upgrade_level(id))
		refresh()
	elif card != null and is_instance_valid(card):
		card.reject()


## Вспышка на карточке после внешней покупки (например из GameState).
func flash_card(id: String) -> void:
	var card: Control = _cards.get(id, null)
	if card != null and is_instance_valid(card):
		card.flash_purchase()


# ---------------------------------------------------------------- звук

func _sfx(method: String) -> void:
	if _audio == null or not is_instance_valid(_audio):
		_audio = get_node_or_null("/root/AudioDirector")
	if _audio != null and _audio.has_method(method):
		_audio.call(method)
