# Эволюция

Расслабляющая 2D-инкременталка про эволюцию: вы растите биолюминесцентную жизнь в тёмном океане, от первой искры до разумного организма. Всё в игре процедурное — фон, существо, звук, интерфейс. Ни одного внешнего ассета.

![Кадр игры](docs/preview.png)

Эры IX «Разум» и IV «Медуза», первый запуск и окно статистики — в [docs/screens](docs/screens).

## Как играть

- **Клик / тап по воде** — всплеск биомассы (сила клика растёт от ДНК и апгрейдов). Подсказка первого запуска гаснет сама после первого клика.
- **Панель справа** — 31 апгрейд в четырёх вкладках: *Рост*, *Мутации*, *Симбиоз*, *ДНК*. Карточка сама показывает состояние: «готово к покупке», «не хватает N», «закрыто» и требуемый порог.
- **Порог эры** (чип слева сверху) — накопленная биомасса. При переходе играет баннер «НОВАЯ ЭРА», существо плавно перестраивается (2 c), меняется палитра океана и аккорд эмбиента.
- **10 эр**: Искра → Капля → Амёба → Медуза → Полип → Колония → Странник → Симбионт → Разум → Сверхорганизм.
- **ДНК-престиж** (блок снизу слева) — сброс прогресса за ДНК: `floor(sqrt(total / 500 000))`. Каждая ДНК даёт +15 % к производству навсегда.
- **Оффлайн-прогресс** — 50 % скорости за отсутствие, максимум 8 часов; при возврате показывается тост.
- **Автосейв** каждые 15 секунд. В редакторе — в `res://save/save.json` (рядом с проектом), в собранном приложении — в `user://save.json` (`%APPDATA%\Godot\app_userdata\Эволюция`), потому что `res://` внутри `.exe` только для чтения.

Кнопки внизу справа: звук, статистика (там же двойное подтверждение сброса прогресса), сброс.

## Запуск

**Готовое приложение.** Скачайте `Evolution.exe` со страницы [Releases](https://github.com/konem-popolam-sketch/evolution/releases) и запустите двойным кликом — ничего устанавливать не нужно, Godot внутри. Один файл, рядом ничего не требуется; сейв и логи лежат в `%APPDATA%\Godot\app_userdata\Эволюция`.

**Из исходников.** Godot 4.7.2, Forward+. Открыть папку проекта и нажать F5, либо:

```
Godot_v4.7.2-stable_win64.exe --path .
```

**Своя сборка.**

```
# 1) один раз: шаблоны экспорта Godot 4.7.2 (Editor → Manage Export Templates,
#    либо скачать Godot_v4.7.2-stable_export_templates.tpz и распаковать в
#    %APPDATA%\Godot\export_templates\4.7.2.stable)
# 2) экспорт (пресет «Windows Desktop» уже в export_presets.cfg)
Godot_v4.7.2-stable_win64.exe --headless --path . --export-release "Windows Desktop" build\Evolution.exe
```

Скрипт `Tools` не обязателен: `tools/Godot_v4.7.2-stable_win64.exe` в репозиторий не входит (180 МБ) — положите свой билд рядом или добавьте `godot` в `PATH`.

## Структура

```
scenes/main.tscn              корневая сцена (WorldEnvironment + слои)
scripts/core/                 game_state.gd (автолоад), upgrade_db.gd, evolution_db.gd, palette.gd
scripts/visual/               backdrop.gd (шейдерный океан), creature.gd (процедурное существо)
shaders/backdrop.gdshader     океан: fbm-каустика, аврора, боке, виньетка, дизеризация
scripts/fx/                   floating_text, burst, ripple, motes
scripts/ui/                   game_hud, upgrade_panel, upgrade_card, stats_panel, evolution_banner, theme_builder
scripts/audio/audio_director.gd  процедурный эмбиент (AudioStreamGenerator) + синтезированные SFX
tests/                        headless-проверки: smoke, content, audio, ui, creature, visual, qa_acceptance
docs/CONTRACT.md              контракт сборки: API, владение файлами, правила
export_presets.cfg            пресет Windows Desktop (embed pck, иконка приложения)
icon.ico                      иконка .exe (сгенерирована из icon.svg)
build/Evolution.exe           результат экспорта (в git не входит)
```

Ключевые API: `GameState` (сигналы `biomass_changed`, `rate_changed`, `stage_changed`, `upgrade_purchased`, `prestige_done`), `Backdrop.set_stage()/pulse()/set_focus()`, `CreatureVisual.play_stage_morph()/play_tap()`, `AudioDirector.set_stage()/play_click()/play_buy()`.

## Проверки

Headless, без открытия окна (из корня проекта):

```
--headless --script tests/smoke_test.gd
--headless --script tests/content_probe.gd
--headless --script tests/audio_probe.gd
--headless --script tests/ui_probe.gd
--headless --script tests/creature_probe.gd
--headless --script tests/visual_backdrop_probe.gd
--headless --script tests/qa_acceptance.gd
```

`qa_acceptance.gd` — приёмочный прогон на настоящей сцене (240 кадров): клик, покупка, отказ при нулевой биомассе, переход эры, престиж, сейв → порча → лоад.

Всего в наборе 81 проверка HUD/панелей, контентный баланс-симулятор, аудио-проба (пик/CPU/мьют) и проверки существа с мембраной. Живые замеры: 165 FPS, 7.4 мс на кадр, 560 draw call, 0 orphan-узлов.

## Разработка

- Автолоад `McpInteractionServer` нужен только для live-отладки через плагин godot-bridge. Для чистой сборки удалите строку `McpInteractionServer="*res://autoload/mcp_interaction_server.gd"` из `[autoload]` в `project.godot` и папку `autoload/`.
- Глобальные `class_name` (`Palette`, `UIKit`, `UpgradeDB`, …) резолвятся через `.godot/global_script_class_cache.cfg`; после добавления нового класса с `class_name` пересоберите кэш (или откройте проект в редакторе один раз).
- `save/save.backup-*.json` — снимки состояния от прогонов приёмки, игру не затрагивают.

## Команда

Собрано агентами AgentTeams из ростера DSGS: капитан (архитектура, ядро, интеграция), Спайк (шейдерный фон), Шото (существо и FX), Харуки (аудио), Кэйко (HUD и панели), Лайт (контент и баланс), Мисаки (приёмка), Какаши (ревью).
