extends Node
## Автолоад GameState: состояние, экономика, апгрейды, эры, престиж, сохранения.
## Контракт API — docs/CONTRACT.md. Все покупки/клики идут через этот узел.

signal biomass_changed(value: float)
signal rate_changed(rate: float)
signal upgrade_purchased(id: String, level: int)
signal upgrade_unlocked(id: String)
signal stage_changed(stage_index: int)
signal prestige_done(gained_dna: int, count: int)
signal stats_changed()
signal game_loaded(first_time: bool, offline_gain: float, offline_seconds: float)

const SAVE_DIR_RES := "res://save"
const SAVE_FILE_RES := "res://save/save.json"
const SAVE_FILE_USER := "user://save.json"
const AUTOSAVE_INTERVAL := 15.0
const MAX_OFFLINE_SECONDS := 8.0 * 3600.0
const OFFLINE_EFFICIENCY := 0.5
## База ДНК-престижа: порог = BASE * (dna_earned + 1)^2.
const PRESTIGE_BASE := 500_000.0

const UPGRADE_DB_PATH := "res://scripts/core/upgrade_db.gd"
const EVOLUTION_DB_PATH := "res://scripts/core/evolution_db.gd"

## Запасные пороги эр — на случай, если EvolutionDB ещё не написан
## (параллельная работа команды). Как только файл появится, он главнее.
const FALLBACK_THRESHOLDS := [
	0.0, 750.0, 12_000.0, 120_000.0, 900_000.0,
	6_000_000.0, 45_000_000.0, 320_000_000.0, 2_400_000_000.0, 18_000_000_000.0,
]

var biomass: float = 0.0
var total_biomass: float = 0.0
var dna: int = 0
var dna_earned: int = 0
var stage_index: int = 0
var prestige_count: int = 0
var manual_clicks: int = 0
var playtime: float = 0.0
var muted: bool = false

var _levels: Dictionary = {}          # id -> int
var _unlocked_cache: Dictionary = {}  # id -> bool
var _autosave_timer: float = 0.0
var _last_stage: int = 0
var _last_saved_unix: int = 0
# In an exported build res:// is read-only, so the writable user:// path must be
# tried first there; in the editor the project folder stays the primary target
# (that is what the headless probes assert on).
func _save_paths() -> Array:
	if OS.has_feature("template"):
		return [SAVE_FILE_USER, SAVE_FILE_RES]
	return [SAVE_FILE_RES, SAVE_FILE_USER]
var _loaded: bool = false
var _items_cache: Array = []
var _stages_cache: Array = []

# --- кэш базовых значений, чтобы не пересчитывать каждый кадр ---
var _rate_cache: float = 0.0
var _click_cache: float = 1.0
var _mult_cache: float = 0.0
var _rate_dirty: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	load_game()
	if not _loaded:
		load_game()


func _process(delta: float) -> void:
	playtime += delta
	var rate := get_rate()
	if rate > 0.0:
		_add_biomass(rate * delta, false)
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game()
	_check_stage()


# ================================================================
# Публичное API
# ================================================================

func get_rate() -> float:
	_ensure_base_cache()
	if _rate_dirty:
		_recalc()
	return _rate_cache


func get_click_power() -> float:
	_ensure_base_cache()
	if _rate_dirty:
		_recalc()
	return _click_cache


func tap(_world_pos: Vector2) -> float:
	var gained := get_click_power()
	manual_clicks += 1
	_add_biomass(gained, true)
	_check_stage()
	return gained


func get_upgrade_level(id: String) -> int:
	return int(_levels.get(id, 0))


func get_upgrade_cost(id: String) -> float:
	var item := _item(id)
	if item.is_empty():
		return INF
	var level := get_upgrade_level(id)
	var max_level := int(item.get("max_level", 999))
	if level >= max_level:
		return INF
	var base := float(item.get("base_cost", 10.0))
	var growth := float(item.get("cost_growth", 1.15))
	return base * pow(growth, float(level))


func can_buy(id: String) -> bool:
	var item := _item(id)
	if item.is_empty() or not is_upgrade_available(id):
		return false
	var level := get_upgrade_level(id)
	if level >= int(item.get("max_level", 999)):
		return false
	var cost := get_upgrade_cost(id)
	if cost == INF:
		return false
	if String(item.get("currency", "biomass")) == "dna":
		return float(dna) >= cost
	return biomass >= cost


func buy_upgrade(id: String) -> bool:
	if not can_buy(id):
		return false
	var item := _item(id)
	var cost := get_upgrade_cost(id)
	if String(item.get("currency", "biomass")) == "dna":
		dna -= int(round(cost))
	else:
		biomass -= cost
	var level := get_upgrade_level(id) + 1
	_levels[id] = level
	_rate_dirty = true
	_unlocked_cache.clear()
	upgrade_purchased.emit(id, level)
	rate_changed.emit(get_rate())
	biomass_changed.emit(biomass)
	stats_changed.emit()
	_check_stage()
	save_game()
	return true


func is_upgrade_available(id: String) -> bool:
	var item := _item(id)
	if item.is_empty():
		return false
	if _unlocked_cache.has(id):
		return bool(_unlocked_cache[id])
	var ok := true
	var unlock_stage := int(item.get("unlock_stage", 0))
	if stage_index < unlock_stage:
		ok = false
	if ok:
		var unlock_total := float(item.get("unlock_total", 0.0))
		if unlock_total > 0.0 and total_biomass < unlock_total:
			ok = false
	_unlocked_cache[id] = ok
	return ok


func get_upgrade_multiplier() -> float:
	_ensure_base_cache()
	if _rate_dirty:
		_recalc()
	return 1.0 + _mult_cache


func stage_progress() -> float:
	var cur := float(_threshold_at(stage_index))
	var nxt := next_stage_threshold()
	if nxt <= 0.0:
		return 1.0
	var span := nxt - cur
	if span <= 0.0:
		return 1.0
	return clampf((total_biomass - cur) / span, 0.0, 1.0)


func next_stage_threshold() -> float:
	return _threshold_at(stage_index + 1)


func can_prestige() -> bool:
	return prestige_gain_preview() > 0


func prestige_gain_preview() -> int:
	var gain := int(floor(sqrt(total_biomass / PRESTIGE_BASE))) - dna_earned
	return maxi(0, gain)


## Порог биомассы, с которого следующий престиж даёт хотя бы одну ДНК.
## Единственный источник правды: HUD/UI не должны считать эту формулу сами.
func prestige_threshold() -> float:
	return PRESTIGE_BASE * pow(float(dna_earned + 1), 2.0)


func do_prestige() -> int:
	var gained := prestige_gain_preview()
	if gained <= 0:
		return 0
	dna += gained
	dna_earned += gained
	prestige_count += 1
	biomass = 0.0
	total_biomass = 0.0
	stage_index = 0
	_last_stage = 0
	_levels.clear()
	_unlocked_cache.clear()
	_rate_dirty = true
	prestige_done.emit(gained, prestige_count)
	stage_changed.emit(0)
	biomass_changed.emit(biomass)
	rate_changed.emit(get_rate())
	stats_changed.emit()
	save_game()
	return gained


func reset_progress() -> void:
	biomass = 0.0
	total_biomass = 0.0
	dna = 0
	dna_earned = 0
	stage_index = 0
	_last_stage = 0
	prestige_count = 0
	manual_clicks = 0
	playtime = 0.0
	_levels.clear()
	_unlocked_cache.clear()
	_rate_dirty = true
	stage_changed.emit(0)
	biomass_changed.emit(0.0)
	rate_changed.emit(get_rate())
	stats_changed.emit()
	save_game()


func format_number(v: float) -> String:
	var neg := v < 0.0
	var a := absf(v)
	var out := ""
	if a < 1000.0:
		if a == floorf(a):
			out = str(int(a))
		else:
			out = "%.1f" % a
	elif a < 1_000_000.0:
		out = "%.1f тыс." % (a / 1000.0) if a < 100_000.0 else "%.0f тыс." % (a / 1000.0)
	elif a < 1_000_000_000.0:
		out = "%.2f млн" % (a / 1_000_000.0) if a < 100_000_000.0 else "%.1f млн" % (a / 1_000_000.0)
	elif a < 1e12:
		out = "%.2f млрд" % (a / 1e9) if a < 1e11 else "%.1f млрд" % (a / 1e9)
	elif a < 1e15:
		out = "%.2f трлн" % (a / 1e12)
	else:
		out = "%.2e" % a
	return ("-" + out) if neg else out


func stage_name() -> String:
	var stages := _db_stages()
	if stage_index >= 0 and stage_index < stages.size():
		return String(stages[stage_index].get("name", "Эра %d" % (stage_index + 1)))
	return "Эра %d" % (stage_index + 1)


func save_game() -> void:
	var data := {
		"v": 2,
		"biomass": biomass,
		"total_biomass": total_biomass,
		"dna": dna,
		"dna_earned": dna_earned,
		"stage_index": stage_index,
		"prestige_count": prestige_count,
		"manual_clicks": manual_clicks,
		"playtime": playtime,
		"muted": muted,
		"levels": _levels.duplicate(),
		"saved_at": int(Time.get_unix_time_from_system()),
	}
	var text := JSON.stringify(data)
	_last_saved_unix = int(data["saved_at"])
	for path in _save_paths():
		if String(path).begins_with("res://") and not DirAccess.dir_exists_absolute(SAVE_DIR_RES):
			DirAccess.make_dir_recursive_absolute(SAVE_DIR_RES)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			return


func load_game() -> void:
	var text := ""
	for path in _save_paths():
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				text = f.get_as_text()
				f.close()
				break
	if text.is_empty():
		_loaded = true
		game_loaded.emit(true, 0.0, 0.0)
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_loaded = true
		game_loaded.emit(true, 0.0, 0.0)
		return
	var d: Dictionary = parsed
	biomass = float(d.get("biomass", 0.0))
	total_biomass = float(d.get("total_biomass", 0.0))
	dna = int(d.get("dna", 0))
	dna_earned = int(d.get("dna_earned", 0))
	stage_index = int(d.get("stage_index", 0))
	prestige_count = int(d.get("prestige_count", 0))
	manual_clicks = int(d.get("manual_clicks", 0))
	playtime = float(d.get("playtime", 0.0))
	muted = bool(d.get("muted", false))
	_levels.clear()
	var lv: Variant = d.get("levels", {})
	if typeof(lv) == TYPE_DICTIONARY:
		for k in lv.keys():
			_levels[String(k)] = int(lv[k])
	_last_stage = stage_index
	_last_saved_unix = int(d.get("saved_at", 0))
	_loaded = true
	_rate_dirty = true
	_unlocked_cache.clear()
	# оффлайн-прогресс
	var offline_seconds := 0.0
	var offline_gain := 0.0
	if _last_saved_unix > 0:
		offline_seconds = clampf(float(Time.get_unix_time_from_system()) - float(_last_saved_unix), 0.0, MAX_OFFLINE_SECONDS)
		if offline_seconds > 5.0:
			offline_gain = get_rate() * offline_seconds * OFFLINE_EFFICIENCY
			if offline_gain > 0.0:
				_add_biomass(offline_gain, false)
	_check_stage(false)
	biomass_changed.emit(biomass)
	rate_changed.emit(get_rate())
	stats_changed.emit()
	game_loaded.emit(false, offline_gain, offline_seconds)


# ================================================================
# Внутреннее
# ================================================================

func _add_biomass(amount: float, from_click: bool) -> void:
	if amount <= 0.0:
		return
	biomass += amount
	total_biomass += amount
	biomass_changed.emit(biomass)


func _check_stage(emit_signal_now: bool = true) -> void:
	var idx := _stage_at(total_biomass)
	if idx != stage_index:
		var direction := 1 if idx > stage_index else -1
		stage_index = idx
		_last_stage = idx
		_unlocked_cache.clear()
		if emit_signal_now:
			stage_changed.emit(idx)
			stats_changed.emit()


func _recalc() -> void:
	_rate_dirty = false
	var ps_add := 0.0
	var ps_mult := 1.0
	var click_add := 0.0
	var click_mult := 1.0
	var all_mult := 1.0
	var auto_click := 0.0
	for item in _db_items():
		var id := String(item.get("id", ""))
		var level := get_upgrade_level(id)
		if level <= 0:
			continue
		var value := float(item.get("value", 0.0))
		var effect := String(item.get("effect", ""))
		match effect:
			"ps_add":
				ps_add += value * level
			"ps_mult":
				ps_mult *= pow(1.0 + value, level)
			"click_add":
				click_add += value * level
			"click_mult":
				click_mult *= pow(1.0 + value, level)
			"all_mult":
				all_mult *= pow(1.0 + value, level)
			"auto_click":
				auto_click += value * level
	# ДНК даёт постоянный бонус, сохраняется между престижами
	var dna_bonus := 1.0 + 0.15 * float(dna_earned)
	_mult_cache = (all_mult * dna_bonus) - 1.0
	var base_ps := 0.0
	_rate_cache = (base_ps + ps_add) * ps_mult * all_mult * dna_bonus
	_rate_cache += auto_click * (1.0 + click_add) * click_mult * all_mult * dna_bonus
	_click_cache = maxf(1.0, (1.0 + click_add)) * click_mult * all_mult * dna_bonus


func _ensure_base_cache() -> void:
	if _loaded:
		return
	_loaded = true


func _item(id: String) -> Dictionary:
	for item in _db_items():
		if String(item.get("id", "")) == id:
			return item
	return {}


func _db_items() -> Array:
	if not _items_cache.is_empty():
		return _items_cache
	if ResourceLoader.exists(UPGRADE_DB_PATH):
		var script: Script = load(UPGRADE_DB_PATH)
		if script != null and script.can_instantiate():
			var inst: Object = script.new()
			if inst != null and inst.has_method("all"):
				var arr: Variant = inst.call("all")
				if typeof(arr) == TYPE_ARRAY:
					_items_cache = arr
					if inst is RefCounted:
						pass
					return _items_cache
	return _items_cache


func _db_stages() -> Array:
	if not _stages_cache.is_empty():
		return _stages_cache
	if ResourceLoader.exists(EVOLUTION_DB_PATH):
		var script: Script = load(EVOLUTION_DB_PATH)
		if script != null and script.can_instantiate():
			var inst: Object = script.new()
			if inst != null and inst.has_method("all"):
				var arr: Variant = inst.call("all")
				if typeof(arr) == TYPE_ARRAY:
					_stages_cache = arr
					return _stages_cache
	return _stages_cache


func _threshold_at(index: int) -> float:
	var stages := _db_stages()
	if index >= 0 and index < stages.size():
		return float(stages[index].get("threshold", 0.0))
	if index < 0:
		return 0.0
	if index < FALLBACK_THRESHOLDS.size():
		return float(FALLBACK_THRESHOLDS[index])
	return 0.0


func _stage_at(total: float) -> int:
	var stages := _db_stages()
	if not stages.is_empty():
		var best := 0
		for i in stages.size():
			if total >= float(stages[i].get("threshold", 0.0)):
				best = i
			else:
				break
		return mini(best, stages.size() - 1)
	var best2 := 0
	for i in FALLBACK_THRESHOLDS.size():
		if total >= float(FALLBACK_THRESHOLDS[i]):
			best2 = i
		else:
			break
	return best2
