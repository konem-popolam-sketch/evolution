# ЭВОЛЮЦИЯ — контракт сборки (читать полностью перед работой)

Проект: `C:\Users\Igor\Downloads\increment` — Godot **4.7.2**, GDScript, рендер **Forward+**, `hdr_2d=true`.
Игра: **расслабляющая 2D-инкременталка про эволюцию**. Центр экрана — живое существо
(процедурная амёба → рыба → зверь → разум), вокруг биолюминесцентный океан. Клик по миру даёт
биомассу, апгрейды ускоряют рост, на порогах биомассы наступает новая эра с красивым переходом.

Тон: **красиво, спокойно, дорого**. Много мягкого свечения, плавных кривых, медленных дыханий,
никакой резкости и «дешёвых» прямоугольников без скруглений.

## Жёсткие правила

1. Работай только со своими файлами (см. «Владение файлами»). Чужие файлы **не создавай и не правь**.
2. Никаких внешних ассетов: только код, процедурная графика, шрифт темы Godot по умолчанию
   (`ThemeDB.fallback_font`, кириллица поддерживается). Никаких .png/.ttf/.wav в репозитории.
3. Запускать Godot через shell (`pwsh`/`bash`) **запрещено** — только через `godot_*` инструменты
   (`godot_validate_script`, `godot_run_headless`, `godot_run_project`). Проверяй каждый свой скрипт:
   `godot_validate_script(script_path="...")` → `error_count == 0`.
4. GDScript 4: отступы табами, типизация где уместно, `@onready`, `Tween`, `Callable`. Никаких
   `yield`, `OS.get_ticks_msec` для анимаций — только `delta`/`TIME`.
5. UI-текст на русском, числа форматируй через `GameState.format_number()`.
6. `class_name` — только те, что указаны в контракте. Не добавляй автолоады.
7. Не ломай кадровый бюджет: не создавай/удаляй узлы каждый кадр, не грузи шейдеры в `_process`,
   кэшируй материалы. Цель — стабильные 60 FPS.
8. Если файла-зависимости ещё нет (капитан пишет параллельно) — пиши код под интерфейс из этого
   документа, не создавай зависимость сам, дождись её появления и провалидируй ещё раз.

## Файловая структура

```
project.godot                     [капитан]
scenes/main.tscn                  [капитан]
scripts/core/palette.gd           [капитан]
scripts/core/game_state.gd        [капитан, автолоад GameState]
scripts/core/upgrade_db.gd        [капитан, class_name UpgradeDB]
scripts/core/evolution_db.gd      [капитан, class_name EvolutionDB]
scripts/game/main.gd              [капитан]
shaders/*.gdshader                [ВИЗУАЛ]
scripts/visual/backdrop.gd        [ВИЗУАЛ, class_name Backdrop]
scripts/visual/creature.gd        [ВИЗУАЛ, class_name CreatureVisual]
scripts/fx/floating_text.gd       [ВИЗУАЛ, class_name FloatingText]
scripts/fx/burst.gd               [ВИЗУАЛ, class_name Burst]
scripts/fx/ripple.gd              [ВИЗУАЛ, class_name Ripple]
scripts/fx/motes.gd               [ВИЗУАЛ, class_name Motes]
scripts/audio/audio_director.gd   [ЗВУК, автолоад AudioDirector]
scripts/ui/*.gd                   [UI]
tests/smoke_test.gd               [капитан]
```

## Палитра

Всегда используй `Palette` (`scripts/core/palette.gd`): `Palette.TEXT`, `TEXT_DIM`, `CYAN`,
`AQUA`, `GOLD`, `PINK`, `VIOLET`, `GREEN`, `CARD_BG`, `CARD_BG_HOVER`, `CARD_BORDER`, `PANEL_BG`,
`BG_DEEP`, `BG_MID`. Хелперы: `Palette.glow(c, strength)`, `Palette.fade(c, alpha)`.

## GameState (автолоад, `GameState.*`)

Состояние и экономика. UI и визуал **только читают** его и слушают сигналы; покупки/клики делает
GameState.

```gdscript
signal biomass_changed(value: float)
signal rate_changed(rate: float)
signal upgrade_purchased(id: String, level: int)
signal upgrade_unlocked(id: String)
signal stage_changed(stage_index: int)
signal prestige_done(gained_dna: int, count: int)
signal stats_changed()
signal game_loaded(first_time: bool, offline_gain: float, offline_seconds: float)

# состояние (можно читать напрямую)
var biomass: float          # текущая биомасса
var total_biomass: float    # всего за эту жизнь
var dna: int                # доступная ДНК (валюта престижа)
var dna_earned: int         # всего заработано ДНК
var stage_index: int        # 0..9, текущая эра
var prestige_count: int
var manual_clicks: int
var playtime: float         # секунды
var muted: bool

# методы
func get_rate() -> float                 # биомасса/сек
func get_click_power() -> float          # биомасса за клик
func tap(world_pos: Vector2) -> float     # добавить клик, вернуть сколько дало
func get_upgrade_level(id: String) -> int
func get_upgrade_cost(id: String) -> float   # INF если максимум
func can_buy(id: String) -> bool
func buy_upgrade(id: String) -> bool
func is_upgrade_available(id: String) -> bool
func get_upgrade_multiplier() -> float   # общий множитель (для UI)
func stage_progress() -> float           # 0..1 до следующей эры
func next_stage_threshold() -> float     # биомасса следующей эры (0 если максимум)
func can_prestige() -> bool
func prestige_gain_preview() -> int
func do_prestige() -> int
func reset_progress() -> void            # полный сброс (с подтверждением в UI)
func format_number(v: float) -> String   # "1 234", "12.4 тыс.", "3.1 млн"
func stage_name() -> String              # имя текущей эры
func save_game() -> void
func load_game() -> void
```

## UpgradeDB (`class_name UpgradeDB`)

```gdscript
# ITEMS: Array[Dictionary], каждая запись:
# { id:String, name:String, desc:String, category:String, icon:String,
#   currency:"biomass"|"dna", base_cost:float, cost_growth:float, value:float,
#   effect:String, max_level:int, unlock_stage:int, unlock_total:float, color:Color }
# category: "рост" | "мутации" | "симбиоз" | "днк"
# effect: "ps_add" | "ps_mult" | "click_add" | "click_mult" | "all_mult" | "auto_click"
static func all() -> Array
static func by_id(id: String) -> Dictionary
static func by_category(cat: String) -> Array
static func categories() -> Array            # ["рост","мутации","симбиоз"] (+"днк" после престижа)
```

## EvolutionDB (`class_name EvolutionDB`)

10 эр. Пороги по `total_biomass`.

```gdscript
# STAGES: Array[Dictionary]:
# { index:int, name:String, subtitle:String, threshold:float,
#   color_a:Color, color_b:Color, accent:Color, glow:Color,
#   creature: Dictionary }  # параметры формы существа, схема ниже
static func all() -> Array
static func stage_at(total: float) -> int
static func get_stage(i: int) -> Dictionary
static func next_threshold(i: int) -> float     # 0 если последняя
static func count() -> int
```

`creature` параметры (процедурная форма, все с плавной интерполяцией между эрами):
```
body_radius: float      # 40..120
lobes: int              # 1..7 долей тела
tentacles: int          # 0..14 щупалец
tentacle_len: float     # 0.3..2.2
eyes: int               # 0..4
tail: float             # 0..1
fins: int               # 0..4
spikes: int             # 0..20
translucency: float     # 0..1
```

## Как капитан собирает сцену (`scripts/game/main.gd`)

```
Main (Node2D)
├── WorldEnvironment      # glow, tonemap
├── Backdrop              # class_name Backdrop, full-rect шейдерный фон
├── Motes                 # class_name Motes, ambient-частицы
├── Creature              # class_name CreatureVisual, в центре мира
├── FXLayer (Node2D)      # FloatingText / Burst / Ripple сюда
└── CanvasLayer
    └── GameHUD           # class_name GameHUD, full-rect Control
```

### Backdrop
```gdscript
class_name Backdrop
extends Node2D
func setup() -> void                              # строит ColorRect+шейдер по размеру вьюпорта
func set_stage(index: int, animated: bool = true) -> void   # плавно меняет палитру фона (2.0 c)
func pulse(strength: float = 1.0) -> void         # короткий всплеск свечения (клик/эра)
```
Фон обязан тянуться на весь вьюпорт при ресайзе (anchors/full rect).

### CreatureVisual
```gdscript
class_name CreatureVisual
extends Node2D
func setup() -> void
func play_tap() -> void                 # squash&stretch + вспышка ауры
func play_stage_morph(index: int) -> void   # морф формы за ~2 c, без телепорта
```
Рисуется процедурно (`_draw`, градиентные слои, аддитивное свечение), дышит, щупальца колышутся,
глаза моргают. Цвета берёт из `EvolutionDB`. Обязательно реагирует на `GameState.stage_changed`.

### FX (статические хелперы)
```gdscript
class_name FloatingText
extends Node2D
static func spawn(parent: Node, global_pos: Vector2, text: String, color: Color,
                  size: int = 30, crit: bool = false) -> void
# всплывает вверх, растворяется, лёгкий разлёт; crit — крупнее и с искрами

class_name Burst
extends Node2D
static func burst(parent: Node, global_pos: Vector2, color: Color,
                  count: int = 16, speed: float = 180.0, size: float = 4.0) -> void

class_name Ripple
extends Node2D
static func ripple(parent: Node, global_pos: Vector2, color: Color,
                   start_radius: float = 20.0, end_radius: float = 160.0,
                   duration: float = 0.9) -> void
```

### Motes
```gdscript
class_name Motes
extends Node2D
func setup() -> void    # сам создаёт CPUParticles2D/свои частицы, тянется на вьюпорт
```

### GameHUD (свой файл на каждый узел)
```gdscript
class_name GameHUD
extends Control
signal reset_requested
func bind() -> void     # вызывается после add_child
```
HUD сам строит детей. Требования:
* верх слева — чип эры: «ЭРА III · Амёба», под ним тонкий прогресс-бар до следующей эры и
  подпись «до следующей: 12.4 тыс.»;
* верх по центру — крупная биомасса (мягкое свечение) + строка «+N/сек»;
* справа — панель 400 px: заголовок, 3–4 вкладки (рост / мутации / симбиоз / днк после престижа),
  прокручиваемый список карточек апгрейдов;
* низ слева — кнопка ДНК-престижа (появляется когда `can_prestige()`), с превью награды;
* низ справа — маленькие круглые кнопки: звук, статистика, полный сброс;
* карточка апгрейда: иконка, имя, «ур. N», описание, цена; состояния: доступно / не хватает /
  заблокировано / MAX; hover и press анимации, покупка — вспышка и всплеск;
* `EvolutionBanner` — при `stage_changed` полноэкранный SOFT-переход (затемнение, кольцо, заголовок
  «НОВАЯ ЭРА», имя эры, подпись, автоскрытие ~2.8 c), не блокирует ввод после себя;
* `StatsPanel` — модалка со статистикой и кнопкой сброса (двойное подтверждение), закрытие по клику;
* тост «Пока тебя не было…» по сигналу `game_loaded`, если `offline_gain > 0`;
* HUD не перекрывает центр: существо живёт в левой/центральной части, панель справа.
* Все обновления — из `_process` с троттлингом ~0.08 c (не на каждый кадр пересобирай текст),
  плюс мгновенный отклик на `upgrade_purchased`/`stage_changed`/`biomass_changed`.

### AudioDirector (автолоад)
```gdscript
func play_click() -> void
func play_buy() -> void
func play_stage_up() -> void
func play_prestige() -> void
func set_stage(index: int) -> void   # смена аккорда/настроения
func set_muted(m: bool) -> void
func is_muted() -> bool
```
Всё синтезируется в рантайме (`AudioStreamGenerator` для эмбиента, `AudioStreamWAV` из PCM для
одноразовых эффектов). Эмбиент: тёплые пэды, квинты, медленное LFO, тихий «океан» из
отфильтрованного шума, редкие колокольчики. Без щелчков (envelope), без клиппинга (мягкий лимитер),
общий уровень тихий и расслабляющий. Автозапуск после первого клика (браузерная политика не нужна,
но инициализацию делай в `_ready`).

## Проверка

0. Проект создан без редактора, поэтому глобальные `class_name` берутся из
   `.godot/global_script_class_cache.cfg`. Если при валидации чужого/своего файла видишь
   `Identifier "Palette" not declared in the current scope` — это **не ошибка кода**: капитан
   пересобирает кэш (`tools/gen_class_cache.ps1`, либо просьба капитану). Свои файлы не править.

1. `godot_validate_script` на каждый свой файл — 0 ошибок.
2. Для визуала/звука — проверь headless-запуск сцены, если это возможно без ассетов:
   `godot_run_headless(script="tests/<твой>.gd", timeout_ms=30000)`; тестовые скрипты клади в
   `tests/` с префиксом своего модуля (например `tests/visual_probe.gd`), в конце — `quit()`.
3. В финальном отчёте: список созданных файлов, что реализовано, что осталось / риски.
