---

description: "Задачи: специализация городов и темп основания"
---

# Tasks: Специализация городов и темп основания

**Input**: Design documents from `/specs/002-city-specialization/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: обязательны (конституция, принцип VI): в каждой истории тесты пишутся первыми и
сначала падают.

**Organization**: задачи сгруппированы по историям; каждая история проверяется отдельно.

**Правило проекта**: файлы `SettlementsAdvisor/UI/*` (`SA_Main.lua`, `SA_Main.xml`) правятся только
при закрытой игре (`pgrep Civ6_Exe_Child` пусто; иначе быстрое сохранение и выход).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно параллельно (разные файлы, нет зависимостей)
- **[Story]**: история (US1–US4)

---

## Phase 1: Setup

**Purpose**: правила для тестов и каркас модулей

- [X] T001 Добавить в `TABLES` выгрузки таблицы `Modifiers`, `ModifierArguments`, `DynamicModifiers`, `Building_YieldChanges`, `AiLists`, `AiFavoredItems`, `Victories` (R8) в tools/export_gameinfo.py
- [X] T002 Выгрузить правила заново из кэша игры **с загруженной партией Gathering Storm** в tests/fixtures/gameinfo.lua (файл не в git) и убедиться, что все тесты 001 зелёные: `.tools/lua51/bin/lua tests/run.lua`
- [X] T003 [P] Добавить **все** константы модели 002 из таблицы Model Constants плана с комментариями-обоснованиями — `FORECAST_TURNS`, `TEMPO_HALF_LIFE`, `HERE_MARGIN`, `HOUSING_ERA_MAX`, `STRATEGY_MIN`, `SIGNAL_WEIGHT`, `ROLE_WEIGHT`, `KEY_MIN_ADJ`, `REGIONAL_WEIGHT`, `VICTORY_DISTRICTS`, `EFFECT_WORDS` — и `SA_Rules.SpeedScale()` (`CostMultiplier / 100` текущей скорости) в SettlementsAdvisor/Scripts/SA_Rules.lua (FR-023, принцип V: другие модули их только читают)
- [X] T004 [P] Создать пустые модули `SA_Growth`, `SA_Strategy`, `SA_Specialize` (таблица модуля и `Reset()`) и прописать их в `ImportFiles`/`Files` в SettlementsAdvisor/SettlementsAdvisor.modinfo и в SettlementsAdvisor/Scripts/SA_Growth.lua, SA_Strategy.lua, SA_Specialize.lua. Новые файлы в `ImportFiles` игра видит только после **полного перезапуска**, загрузки сохранения мало (ловушка из 001)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: доступ к игре, нужный всем историям (принцип VI: только через `SA_World`)

- [X] T005 [P] Поддельный мир: население городов (`cities[i].population`), включённые победы (`map.victories`), черты лидера и цивилизации игрока (`map.leader`, `map.civilization`) в tests/fake/world.lua
- [X] T006 `SA_World.CityPopulation(plot)`, `SA_World.EnabledVictories()` (по `Game.IsVictoryEnabled`, отсортированы), `SA_World.PlayerTraits(pid)` (черты лидера и цивилизации из `PlayerConfigurations`, отсортированы) в SettlementsAdvisor/Scripts/SA_World.lua

**Checkpoint**: тесты 001 зелёные, новые функции мира доступны в тестах.

---

## Phase 3: User Story 1 — «Основывай здесь» (Priority: P1) 🎯 MVP

**Goal**: ранние ходы весят больше; при выборе Поселенца — вердикт «Основывай здесь» или «Иди на № 1».

**Independent Test**: сохранение с Поселенцем на приличной клетке и чуть лучшим местом в 3 ходах
— «Основывай здесь»; заметно лучшее место в 1 ходе — «Иди на № 1: +N, 1 ход» (quickstart, шаг 2).

### Tests for User Story 1 ⚠️

- [X] T007 [P] [US1] Тесты темпа и вердикта в tests/unit/test_rank.lua: `TempoLoss` 1/3/5 ходов ≈ 2,5/7,4/12,1 % и масштаб скоростью; задержка 5 ходов дороже линейной (US1, сценарий 4); `Verdict` — «here» при отставании ≤ `HERE_MARGIN`, «next», если порог проходит только клетка с задержкой 1, «go» при большем (SC-001), `LowData`, недостижимые места не участвуют, липкость перехода here↔go (`KEEP_MARGIN`)
- [X] T008 [P] [US1] Тесты строк вердикта в tests/unit/test_explain.lua и ключей `LOC_SA_VERDICT_*` в обоих языках в tests/unit/test_text.lua

### Implementation for User Story 1

- [X] T009 [US1] `SA_Rank.TempoLoss(turns)` по R1 вместо линейного `TravelPenalty`, `Effective` через неё; старый тест линейного штрафа переписать в SettlementsAdvisor/Scripts/SA_Rank.lua
- [X] T010 [US1] `SA_Rank.Verdict(sites, here, travel, previous)` → сущность Verdict с видами `here`/`next`/`go` (data-model, R2) в SettlementsAdvisor/Scripts/SA_Rank.lua
- [X] T011 [P] [US1] Тексты `LOC_SA_VERDICT_HERE`, `LOC_SA_VERDICT_HERE_WHY`, `LOC_SA_VERDICT_NEXT`, `LOC_SA_VERDICT_GO`, `LOC_SA_VERDICT_LOW_DATA` в SettlementsAdvisor/Text/SA_Text_ru_RU.xml и SA_Text_en_US.xml
- [X] T012 [US1] Строка вердикта первой в блоке мода на клетке «здесь» (`opts.Verdict`) в SettlementsAdvisor/Scripts/SA_Explain.lua
- [X] T013 [US1] (игра закрыта) В `buildView`: кандидаты «здесь» (клетка под Поселенцем и законные клетки с задержкой 0) и «рядом» (задержка 1), `m_view.Verdict`, сообщение над Поселенцем (после «уточняется»), отметка клетки для «Основывай в 1 ходе», `opts.Verdict` в `tooltipLines` в SettlementsAdvisor/UI/SA_Main.lua
- [ ] T014 [US1] Проверка в игре по quickstart (шаг 2) на macOS и Windows; результат в «Validation in Game» в specs/002-city-specialization/plan.md — macOS проверен 2026-10-29 (вердикт «Основывай здесь: это лучшее место рядом»), Windows и вердикты «в 1 ходе» / «Иди на № 1» ещё нет

**Checkpoint**: вердикт работает на текущей модели 001 (все районы) — уже полезен сам по себе.

---

## Phase 4: User Story 2 — Реальный размер города и число районов (Priority: P1)

**Goal**: прогноз населения места и лимит районов по правилу игры; в раскладку, балл и метки идут
только районы в лимите.

**Independent Test**: сытое и голодное место на тестовой карте — у голодного меньше прогноз, лимит и
районов; подсказка «Город вырастет примерно до N жит. → K район.» (quickstart, шаг 3).

### Tests for User Story 2 ⚠️

- [X] T015 [P] [US2] tests/unit/test_growth.lua: `Threshold(pop)` по `GlobalParameters` (R3), `Limit` 1→1, 3→1, 4→2, 7→3 по `DISTRICT_POPULATION_REQUIRED_PER`; `Forecast` сытое > голодное; жильё останавливает рост (`LimitedBy = "housing"`); в жильё идут только здания до `HOUSING_ERA_MAX` (Амбар — да, Канализация — нет) и с районом-условием в плане; `opts.current` не уменьшает прогноз; неоткрытые клетки идут в прогноз только ожиданием `SA_Prior`, не настоящими данными (FR-022)
- [X] T016 [P] [US2] Тесты лимита в tests/unit/test_layout.lua и tests/unit/test_coarse.lua: районов с `RequiresPopulation = 1` в раскладке не больше лимита (SC-003); Акведук и Дамба сверх лимита; построенные районы города остаются при превышении (US2, сценарий 2); метки только под районы плана (FR-009) в tests/unit/test_pins.lua

### Implementation for User Story 2

- [X] T017 [US2] `SA_Growth.Threshold`, `SA_Growth.Limit`, `SA_Growth.Forecast` (R3: план клеток `SA_Tiles.Plan`, жильё `SA_Tiles.Housing` + здания жилья по правилу `HOUSING_ERA_MAX` и району-условию, торможение роста по `CITY_HOUSING_LEFT_*`, горизонт × `SpeedScale`) в SettlementsAdvisor/Scripts/SA_Growth.lua
- [X] T018 [US2] `SA_Specialize.Select(layout, strategy, limit, keep)` без стратегии (все районы второстепенные): отбор `limit` районов с `RequiresPopulation = 1` по соседству, районы без лимита — всегда, `keep` с запасом `SA_Layout.KEEP_BONUS`; `Dropped` с причинами в SettlementsAdvisor/Scripts/SA_Specialize.lua
- [X] T019 [US2] Раскладка в два прохода (все районы → `Select` → отобранные) в `SA_Coarse.Layout` и `SA_Coarse.CityLayout`; лимит из `Forecast` (у своего города — не меньше текущего населения); `Forecast` в причинах `Score` в SettlementsAdvisor/Scripts/SA_Coarse.lua
- [X] T020 [US2] План империи и метки только по отобранным районам: `prefer` из записи меток передаётся как `keep` в `Select` в SettlementsAdvisor/Scripts/SA_Empire.lua
- [X] T021 [P] [US2] Строка роста `LOC_SA_WHY_GROWTH` (+ «упирается в жильё / еду») в SettlementsAdvisor/Scripts/SA_Explain.lua и текстах SettlementsAdvisor/Text/SA_Text_ru_RU.xml, SA_Text_en_US.xml
- [ ] T022 [US2] Проверка в игре: `GetGrowthThreshold()` на 3 размерах и 2 скоростях = `SA_Growth.Threshold`, `GetNumAllowedDistrictsRequiringPopulation()` = `SA_Growth.Limit`; поправить R3 при расхождении; результат в «Validation in Game» в specs/002-city-specialization/plan.md — 2026-10-29: прогноз, лимит и строка роста в игре работают; сверка с игрой ждёт партии с городами

**Checkpoint**: US1 и US2 работают вместе; меток под районы, которых не будет, больше нет.

---

## Phase 5: User Story 3 — Стратегия империи и специализация (Priority: P2)

**Goal**: победа и ключевые районы из черт лидера и цивилизации; ключевые районы — в городах с
наибольшим соседством; Промзона и Развлекательный комплекс — с покрытием региональных зданий.

**Independent Test**: одна карта за научного и религиозного лидера — разные ключевые районы и
специализация столицы; в империи из трёх городов Промзона покрывает все три (quickstart, шаг 4).

### Tests for User Story 3 ⚠️

- [X] T023 [P] [US3] tests/unit/test_strategy.lua: у **каждого** лидера выгрузки — победа или «сбалансированная» и ≥ 1 причина (SC-004); уникальный район даёт сигнал веса 3 на заменяемый район; порядок сигналов детерминирован; выбор игрока заменяет победу, уникальные районы остаются ключевыми; неизвестный `SA_Victory` → `AUTO`; сигнал `FAVOR` ведёт к `VICTORY_DIPLOMATIC`, золото победы не задаёт; стратегия читает только черты своего игрока (FR-022)
- [X] T024 [P] [US3] tests/unit/test_specialize.lua: `Select` с ролями — ключевой с соседством < `KEY_MIN_ADJ` выпадает раньше сильного второстепенного; `Assign` против полного перебора на малых картах (≤ 5 %, SC-005); `RegionalCover` — радиус из `Buildings.RegionalRange`, уже покрытые города не считаются (SC-006), у Развлекательного комплекса ценность покрытия > 0 за счёт довольства; `Label` — равенство по типу района

### Implementation for User Story 3

- [X] T025 [US3] `SA_Strategy.Signals`, `SA_Strategy.Auto`, `SA_Strategy.Get` (R4: уникальные районы и здания, аргументы и типы эффектов модификаторов, ИИ-списки; константы `STRATEGY_MIN`, `SIGNAL_WEIGHT`, `VICTORY_DISTRICTS`, `EFFECT_WORDS` читаются из `SA_Rules`) в SettlementsAdvisor/Scripts/SA_Strategy.lua
- [X] T026 [US3] Роли в `SA_Specialize.Select` (`SA_Rules.ROLE_WEIGHT`, `SA_Rules.KEY_MIN_ADJ`), `SA_Specialize.Assign` (наибольшая суммарная ценность ключевых районов при лимитах, без городов ниже `KEY_MIN_ADJ`: жадно по соседству + обмены пар, R5), `SA_Specialize.Label` в SettlementsAdvisor/Scripts/SA_Specialize.lua
- [X] T027 [US3] `SA_Specialize.RegionalCover` и `opts.regional` в цели поиска: ценность покрытого города = доход здания (`Building_YieldChanges`) × цена + довольство (`Buildings.Entertainment`) × цена единицы довольства по `Happinesses`, как роскошь в 001; итог × `SA_Rules.REGIONAL_WEIGHT` (R6) в SettlementsAdvisor/Scripts/SA_Specialize.lua и SettlementsAdvisor/Scripts/SA_Layout.lua
- [X] T028 [US3] `SA_Empire.Plan(pid, opts.strategy)`: `Assign` перед раскладкой городов, `regional` с центрами городов и мест треугольника, `Specialization` в плане в SettlementsAdvisor/Scripts/SA_Empire.lua
- [X] T029 [US3] Роли стратегии в отборе районов места и ярлык специализации места в `SA_Coarse.Layout`/`SA_Coarse.Score` в SettlementsAdvisor/Scripts/SA_Coarse.lua
- [X] T030 [US3] (игра закрыта) Стратегия считается при загрузке и в начале хода, передаётся в план и раскладки мест в SettlementsAdvisor/UI/SA_Main.lua
- [X] T031 [P] [US3] Строки `LOC_SA_WHY_STRATEGY`, `LOC_SA_WHY_SPECIALIZATION`, названия побед и «сбалансированная» в SettlementsAdvisor/Scripts/SA_Explain.lua и текстах SettlementsAdvisor/Text/SA_Text_ru_RU.xml, SA_Text_en_US.xml

**Checkpoint**: план империи различается у лидеров с разным уклоном; метки следуют специализации.

---

## Phase 6: User Story 4 — Объяснение и выбор победы на верхней панели (Priority: P3)

**Goal**: выпадающий список победы на верхней панели игры; выбор меняет план и сохраняется в партии.

**Independent Test**: сменить «Авто» на «Религиозная» — в течение хода появляются метки Святилищ,
подсказка называет новую стратегию; после загрузки сохранения выбор тот же (quickstart, шаг 5).

### Tests for User Story 4 ⚠️

- [ ] T032 [P] [US4] Порядок строк блока мода по contracts/ui.md (вердикт, рост, стратегия, специализация, затем строки 001) и сумма слагаемых = заголовок в tests/unit/test_explain.lua; ключи `LOC_SA_VICTORY_*` в обоих языках в tests/unit/test_text.lua

### Implementation for User Story 4

- [ ] T033 [US4] (игра закрыта) `PullDown` (`PullDownBlue`) и запасной контейнер в SettlementsAdvisor/UI/SA_Main.xml
- [ ] T034 [US4] (игра закрыта) Список на `LoadScreenClose`: `ChangeParent` в `/InGame/TopPanel/RightContents` (иначе запасной контейнер), пункты «Авто: …» + `EnabledVictories`, текст кнопки и подсказка со стратегией в SettlementsAdvisor/UI/SA_Main.lua
- [ ] T035 [US4] (игра закрыта) `SA_Victory`: чтение при загрузке, запись при выборе, пересчёт стратегии, плана (`requestEmpire(nil, true)`) и вида в SettlementsAdvisor/UI/SA_Main.lua
- [ ] T036 [US4] (игра закрыта) Выгрузка контекста: список возвращается в свой контекст до `ClearUpdate`; ловушка «чужой стек держит элемент мёртвого контекста» в docs/pitfalls.md и SettlementsAdvisor/UI/SA_Main.lua
- [ ] T037 [P] [US4] Тексты `LOC_SA_VICTORY_BUTTON`, `LOC_SA_VICTORY_AUTO` в SettlementsAdvisor/Text/SA_Text_ru_RU.xml и SA_Text_en_US.xml
- [ ] T038 [US4] Проверка в игре по quickstart (шаг 5): список виден, выбор меняет метки за ход, переживает сохранение и загрузку; результат в specs/002-city-specialization/plan.md

**Checkpoint**: все истории работают; выбор победы управляет планом.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T039 [P] Описать темп, лимит районов, стратегию, специализацию и региональные здания в docs/algorithm.md; отметить сделанные идеи в docs/comparison-civ6-optimizer.md
- [ ] T040 [P] Пометить R28 (линейный штраф дороги) как заменённый R1 из 002 в specs/001-settler-site-lens/research.md
- [ ] T041 Проверка производительности: сначала починить замер `SA_SLOW` — `os.clock` в игре идёт шагами по 1 с (ловушка 24), мерить длительность кадра разницей `UI.GetElapsedTime()` между вызовами `OnUpdate` в SettlementsAdvisor/UI/SA_Main.lua; затем после всех историй в логе нет новых `SA_SLOW`, отбор районов не более чем удваивает время раскладки места (замер в tests/bench/)
- [ ] T042 Калибровка (принцип VIII): прогноз населения против фактического размера городов в проверочной партии; ошибка прогноза и итоговые `FORECAST_TURNS`/`TEMPO_HALF_LIFE` в docs/accuracy.md
- [ ] T043 Полная проверка quickstart на Windows с `tools/collect_diagnostics.cmd`; SC-002 (≤ 3 ходов от Поселенца до основания) в проверочной партии; SC-008 — вердикт, подсказка и выпадающий список визуально на русском и английском, без нераскрытых ключей; результат в specs/002-city-specialization/plan.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (1)** → **Foundational (2)** → истории.
- T002 требует запущенной партии GS (ручной шаг); без него тесты US3 (`test_strategy`) не на чем гонять.
- **US1 (P1)** — после фазы 2; не зависит от других историй.
- **US2 (P1)** — после фазы 2; `Select` из T018 расширяется в US3.
- **US3 (P2)** — после US2 (отбор районов по лимиту — основа ролей).
- **US4 (P3)** — после US3 (список меняет стратегию).
- **Polish** — после нужных историй.

### Within Each User Story

- Тесты пишутся первыми и падают.
- Логика `Scripts/` → тексты → `SA_Main` (при закрытой игре) → проверка в игре.

### Parallel Opportunities

- T003 и T004; T005 параллельно T003/T004.
- US1 и US2 параллельно после фазы 2 (разные файлы, кроме `SA_Explain`/текстов — их править по очереди).
- В каждой истории тесты [P] — параллельно; тексты [P] — параллельно логике.

---

## Parallel Example: User Story 2

```bash
Task: "tests/unit/test_growth.lua: Threshold, Limit, Forecast"
Task: "Тесты лимита в tests/unit/test_layout.lua, test_coarse.lua, test_pins.lua"
Task: "Строка роста LOC_SA_WHY_GROWTH в SA_Explain.lua и текстах"
```

---

## Implementation Strategy

### MVP First

1. Фазы 1–2.
2. US1 (вердикт и темп) — сразу лечит «ждал лучшего места»; проверить в игре.
3. US2 (лимит районов) — честные баллы и метки; проверить в игре.

### Incremental Delivery

1. US1 → проверка → коммит.
2. US2 → проверка → коммит.
3. US3 → проверка на двух лидерах → коммит.
4. US4 → проверка списка на верхней панели → коммит.

---

## Notes

- Константы модели — только в `SA_Rules`, `SA_Strategy`, `SA_Specialize` с обоснованием (plan.md,
  Model Constants).
- Липкость меток 001 (R29) сохраняется во всех историях (FR-016).
- Перед правкой `UI/` — проверить, что игра закрыта.
