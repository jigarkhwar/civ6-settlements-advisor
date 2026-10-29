---

description: "Task list for Settler Site Lens (001-settler-site-lens)"
---

# Tasks: Линза мест при выборе Поселенца

**Input**: Design documents from `/specs/001-settler-site-lens/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/modules.md, contracts/ui.md,
quickstart.md

**Tests**: обязательны — конституция, принцип VI (NON-NEGOTIABLE). Тесты пишутся до кода
задачи и сначала падают. Запуск: `.tools/lua51/bin/lua tests/run.lua`.

**Organization**: задачи сгруппированы по историям из spec.md.
- US1 (P1) — лучшие места при выборе Поселенца;
- US2 (P1) — объяснение на любой клетке;
- US3 (P2) — предпросмотр раскладки районов;
- US4 (P3) — свежие данные без ожидания.

**Правила для всех задач**:
- Код мода — Lua 5.1, без `table.unpack`, `//`, `goto`. Комментарии и идентификаторы — английские.
- Код других модов не копировать (принцип X). DMT только подключается через `include`.
- Перебор — только по отсортированным массивам; равенства решаются меньшим индексом клетки
  (принцип IV).
- Модули `SettlementsAdvisor/Scripts/*` не обращаются к `Controls`, `ContextPtr`, `Events`;
  доступ к игре — только через `SA_World` (принцип VI).
- Числа правил — из `GameInfo` / `GlobalParameters` (принцип V); собственные константы модели —
  в одном месте модуля с комментарием-обоснованием.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно делать параллельно (другие файлы, нет зависимостей от незавершённых задач)
- **[Story]**: история из spec.md (US1…US4)

## Path Conventions

- Мод: `SettlementsAdvisor/` (в `Mods/` игры — символической ссылкой)
- Тесты: `tests/` (раннер, поддельный мир, фикстуры, `tests/unit/test_*.lua`)
- Инструменты: `tools/`; документация: `docs/`

---

## Phase 1: Setup (общая инфраструктура)

**Purpose**: структура проекта, среда тестов, инструменты разработки

- [X] T001 Create directory layout from plan.md: `SettlementsAdvisor/{Config,Text,UI,Scripts}`, `tests/{unit,fake,fixtures/maps}`, `tools/`, `logs/` and a root `.gitignore` ignoring `.tools/`, `logs/`, `tests/saves/`, `.DS_Store`
- [X] T002 Write `tools/setup_lua.sh` that installs Lua 5.1.5 into `.tools/lua51` via `pipx run hererocks .tools/lua51 -l 5.1 -r latest`, is idempotent, and prints `lua -v`; `specs/001-settler-site-lens/quickstart.md` already calls `bash tools/setup_lua.sh`
- [X] T003 [P] Write test runner `tests/run.lua`: discover `tests/unit/test_*.lua` in sorted order, run each `test_*` function in isolation with `pcall`, provide helpers `eq(a,b)`, `near(a,b,eps)`, `deepeq(a,b)`, `truthy(x)`, `raises(fn)`, print a summary, exit code 1 on any failure; optional filter argument by file name
- [X] T004 [P] Write `tools/export_gameinfo.py` (Python 3, `-I` safe, sqlite opened with `mode=ro` URI) that exports from `~/Library/Application Support/Sid Meier's Civilization VI/Firaxis Games/Sid Meier's Civilization VI/Cache/DebugGameplay.sqlite` into `tests/fixtures/gameinfo.lua` the tables: Terrains, Features, Resources, Improvements, Districts, Districts_XP2, DistrictReplaces, ExcludedDistricts, MutuallyExclusiveDistricts, District_Adjacencies, Adjacency_YieldChanges, District_RequiredFeatures, Terrain_YieldChanges, Feature_YieldChanges, Resource_YieldChanges, Improvement_YieldChanges, Improvement_BonusYieldChanges, Improvement_ValidTerrains, Improvement_ValidFeatures, Improvement_ValidResources, Improvement_Adjacencies, Resource_ValidTerrains, Resource_ValidFeatures, Resource_Harvests, Resource_Consumption, Feature_Removes, CoastalLowlands, RandomEvents, GameSpeeds, GlobalParameters, Units (UnitType, FoundCity, Cost), Units_XP2, Civilizations, CivilizationTraits, Leaders, LeaderTraits, Traits, TraitModifiers, Happinesses; column names read via `pragma table_info`; refuse to run if `DISTRICT_CANAL` is absent (not Gathering Storm)
- [X] T005 [P] Write `SettlementsAdvisor/SettlementsAdvisor.modinfo`: id (new GUID), version 1, `AffectsSavedGames=0`, `CompatibleVersions 1.2,2.0`, `<Dependencies>` on Detailed Map Tacks `4ecfcc62-5471-4435-b295-590df213e8d8`, `<LocalizedText>` with mod name/teaser/description in en_US and ru_RU, `FrontEndActions/UpdateText` and `InGameActions` (`UpdateText` for both text files, `ImportFiles` for `Scripts/*.lua`, `AddUserInterfaces` for `UI/SA_Main.xml` in context `InGame`, `ReplaceUIScript` for LuaContext `PlotToolTip` with `UI/SA_PlotToolTip.lua`, LoadOrder above Expansion2's) per contracts/ui.md
- [X] T006 [P] Create `SettlementsAdvisor/Text/SA_Text_en_US.xml` and `SettlementsAdvisor/Text/SA_Text_ru_RU.xml` in `<GameData><LocalizedText><Replace Tag="…" Language="…"><Text>…</Text></Replace>` format with mod name keys and the message keys `LOC_SA_MSG_NO_SITES`, `LOC_SA_MSG_NO_SITES_NEARBY`, `LOC_SA_MSG_RULESET`, `LOC_SA_MSG_NO_DMT`; separators with spaces go inside format strings (pitfall: game trims `<Text>`)
- [X] T007 [P] Write `tools/deploy.sh`: create/verify the symlink `~/Library/Application Support/Sid Meier's Civilization VI/Sid Meier's Civilization VI/Mods/SettlementsAdvisor` → `SettlementsAdvisor/`, validate every XML with `xmllint --noout`, refuse if a non-symlink folder with that name exists
- [X] T008 [P] Write own FireTuner client `tools/tuner.py` (no code from other mods): frame = uint32 LE length + uint32 LE tag + UTF-8 text with NUL; one connection to 127.0.0.1:4318; commands `serve` (own the connection, append output to `logs/tuner.log` with timestamps, local control socket), `exec <lua>` (run in the mod's Lua state, extract JSON printed with marker `SA_JSON:`), `assert <lua> <expected>` (exit 0/1); never edits `AppOptions.txt` — prints instructions if the tuner port is closed
- [X] T009 [P] Write `docs/pitfalls.md` in own words: numbered list of game pitfalls known from analysis (mod name in FrontEndActions; external text XML format; silent XML attribute failures; `GetMapPin(x,y)` creates a pin; stale pin objects crash; hidden context stops `SetUpdate`; DMT modifier cache must be rebuilt in own state; `gsub` with `^` replaces more than once; plots unreachable through foreign territory; flooded lowlands; `Hex_Coloring_Placement` ignores colors; column names from `DebugGameplay.sqlite`; macOS has no `Lua.log`)
- [X] T010 [P] Create `docs/dmt-patches.md` (table: patch, DMT location, reproduction, test) and `docs/dmt-mismatches.md` (empty log header) per research R10 and R27

---

## Phase 2: Foundational (блокирует все истории)

**Purpose**: проверки этапа 0 в игре, поддельный мир, доступ к игре, правила, планировщик

**⚠️ CRITICAL**: истории начинаются только после этой фазы

- [X] T011 Write minimal main context `SettlementsAdvisor/UI/SA_Main.xml` and `SettlementsAdvisor/UI/SA_Main.lua`: include `Scripts/*` modules, ruleset check `GameConfiguration.GetRuleSet() == "RULESET_EXPANSION_2"` (else show `LOC_SA_MSG_RULESET` and stop, FR-028), print `SA_READY` on `LoadScreenClose`, subscribe `Events.UnitSelectionChanged` and print whether the head selected unit has `GameInfo.Units[...].FoundCity`; the context is never hidden (no popup queue)
- [X] T012 Write minimal `SettlementsAdvisor/UI/SA_PlotToolTip.lua`: `include("PlotToolTip_Expansion2")`, keep the base `GetDetails`, append lines from `ExposedMembers.SettlementsAdvisor.GetLines(plotIndex)` only when `ExposedMembers.SettlementsAdvisor.Active` is true, otherwise return the base result unchanged (FR-015)
- [X] T013 Write stage-0 probe script `tools/probes/stage0.lua` (run via `python3 -I tools/tuner.py exec`) that checks and prints as `SA_JSON:` every «[проверить в игре]» item: `UnitManager.CanStartOperation(unit, UnitOperationTypes.FOUND_CITY, …)` for a plot other than the unit's; whether MinimapPanel re-enables `Hex_Coloring_Water_Availablity` after we toggle it off; `ExposedMembers` visible from the PlotToolTip context and our ReplaceUIScript applied after Expansion2; Aqueduct housing with/without fresh water vs `CITY_POPULATION_AQUEDUCT_MIN/BOOST`; Dam two-river-edge rule; `FeatureRemovedFromMap` parameters; one-time yields scaling by game speed; how to read the current sea-level step from UI and map it to `CoastalLowlands.FloodedEvent/SubmergedEvent`; `CityManager.GetOperationTargets` call shape for a district; which functions DMT calls to check the player's techs and civics for adjacency rows (`PrereqTech`, `PrereqCivic`, `ObsoleteTech`) and whether they can be wrapped in our Lua state to evaluate «all techs and civics» (research R9, «Горизонт технологий»)
- [ ] T014 Run T013 in game on a Gathering Storm save and record results in the section «Результаты проверки в игре» of `specs/001-settler-site-lens/plan.md` (принцип VI); update affected decisions in research.md (R3, R5, R7, R8, R9, R11, R14, R23, R27) if a probe contradicts them
- [X] T015 Write fake game environment `tests/fake/world.lua`: builds `GameInfo` (indexable by type and by row, iterable in sorted order) from `tests/fixtures/gameinfo.lua`, plus fake `Map`, plots (`GetIndex`, `GetX/Y`, terrain/feature/resource getters, `IsRiver`, `IsLake`, `IsCoastalLand`, owner, appeal), `Players`, `GameConfiguration`, `TerrainManager` (lowland type, flooded), visibility per player, from a map table `{width, height, plots = {…}, cities = {…}, player = {…}}`
- [X] T016 [P] Create handmade maps in `tests/fixtures/maps/basic.lua`: (a) river with floodplains and hills, (b) coast with lowlands 1/2/3 m and a shipwreck, (c) desert with oasis and little food, (d) area with half the 3-ring unrevealed, (e) foreign territory and a city at distance 3 and 4, (f) mountain next to center for Aqueduct
- [X] T017 [P] Write tests `tests/unit/test_world.lua` for `SA_World` per contracts/modules.md: `Snapshot` fields from data-model PlotSnapshot; unrevealed plots return nil terrain/feature/resource; resource hidden from the player is nil (FR-008); `Ring(i, r)` sorted and excludes center; `Distance`; `Lowland` is `"1M"|"2M"|"3M"|nil`; `Version` increases after `MarkDirty`
- [X] T018 Implement `SettlementsAdvisor/Scripts/SA_World.lua` to pass T017 (the only module that reads game globals; caches snapshots until `Version` changes)
- [X] T019 [P] Write tests `tests/unit/test_rules.lua` for `SA_Rules`: `Param` reads GlobalParameters; `BaseYields`; `BestImprovement` picks the resource improvement when a resource is present and the best eventual improvement otherwise, unique improvements only for own traits, all `Improvement_BonusYieldChanges` included (R13); `SiteDistricts(player)` returns sorted specialty districts with unique replacements and without `MaxPerPlayer = 1` (FR-017); `MutuallyExclusive("DISTRICT_ENTERTAINMENT_COMPLEX","DISTRICT_WATER_ENTERTAINMENT_COMPLEX")` is true; `YIELD_PRICES` equals `{FOOD=1, PRODUCTION=1, SCIENCE=1, CULTURE=1, GOLD=0.5, FAITH=0.5}` (FR-007); `STRATEGIC_UNIT_VALUE` exists with a justification comment (plan.md Complexity Tracking)
- [X] T020 Implement `SettlementsAdvisor/Scripts/SA_Rules.lua` to pass T019 (FR-011)
- [X] T021 [P] Write tests `tests/unit/test_scheduler.lua`: jobs run in priority then index order; `Tick(ops)` yields when `OPS_PER_FRAME` is exhausted; results are identical for quotas 1, 7 and 10 000 (принцип IV); a raised priority preempts queued work; no yield inside `pcall` (error if attempted)
- [X] T022 Implement `SettlementsAdvisor/Scripts/SA_Scheduler.lua` (coroutines, `Enqueue(plotIndex, priority)`, `Tick(ops)`, `Step()`, constant `OPS_PER_FRAME` with a comment that it is calibrated in T075) and wire `ContextPtr:SetUpdate(SA_Scheduler.Step)` in `SettlementsAdvisor/UI/SA_Main.lua`

**Checkpoint**: этап 0 закрыт, тестовая база и основа готовы

---

## Phase 3: User Story 1 — Лучшие места при выборе Поселенца (Priority: P1) 🎯 MVP

**Goal**: при выделении Поселенца сразу видна окраска мест в 4 ступени и номера трёх лучших мест
в радиусе 8 клеток; слагаемое «районы» пока не считается (появится в US3).

**Independent Test**: quickstart, проверки 1, 2, 13, 15; тесты T023–T029 зелёные.

### Tests for User Story 1

- [X] T023 [P] [US1] Write `tests/unit/test_candidates.lua`: each `RefusalReason` value `TOO_CLOSE_TO_CITY`, `FOREIGN_TERRITORY`, `WATER`, `MOUNTAIN`, `IMPASSABLE`, `FEATURE_FORBIDS`, `UNREVEALED`, `FLOODED`, `NATURAL_WONDER` on maps from T016; distance uses `CITY_MIN_RANGE` (≤ range refused, range+1 allowed), not a hardcoded 3 (FR-010)
- [X] T024 [P] [US1] Write `tests/unit/test_prior.lua`: `Estimate` returns `Expected`, `Max`, `LuxuryChance`, `StrategicChance`, `Reasons`; `Min` is always 0; terrain guess follows the majority of revealed neighbours within 2 and the latitude band; probabilities use `Resources.Frequency` restricted by `Resource_ValidTerrains/Features`; the start-area boost applies only around capitals visible to the player (принцип IX); every constant in `SA_Prior.GENERATOR` has a source comment `file:line` (FR-009, R15)
- [X] T025 [P] [US1] Write `tests/unit/test_tiles.lua`: `SA_Tiles.Plan` satisfies «еда центра + Σ еды Plots ≥ Citizens × CITY_FOOD_CONSUMPTION_PER_POPULATION»; `Citizens = min(Needed, FoodLimit, свободных клеток)` (housing is not a cap, R14 revised 2026-10-29); `Limiter` is `"food"|"plots"|nil`; `Eaten = Citizens × consumption`; `CenterYields` drops a removable feature; `Housing` = water + Aqueduct where possible + improvement housing; result equals brute force over all subsets on maps with ≤ 12 plots; desert map (T016 c) is food-limited (FR-006a, R22); `LowlandFactor` is 1 for non-lowland and decreases 3M > 2M > 1M, using `CoastalLowlands` steps and the current sea-level step (FR-010a, R23)
- [X] T026 [P] [US1] Write `tests/unit/test_coarse.lua`: `SA_Coarse.Score` returns a Site with `Status = "coarse"`, `Components` in fixed order `Tiles, Water, Luxury, Strategic, OneTime, Districts`, `Score = Σ Components.Value` (FR-013), `Min ≤ Score ≤ Max`, `Unrevealed` count, `LowData` when unrevealed > half of the 3-ring, every non-zero component has at least one Reason with a `Key`; water housing from `CITY_POPULATION_RIVER_LAKE/COAST/NO_WATER`; conversions per research R14: one housing is worth `min(Buildings.Cost/Housing) × production price / HORIZON_TURNS` (R14 revised 2026-10-29); eaten food is a negative Tiles reason; one amenity is worth the `NonFoodYieldModifier` slope from `Happinesses` at the Content/Displeased boundary (5 % per amenity) of the city's non-food yields plus `GrowthModifier`; a new luxury serves `min(Resources.Happiness, player cities + 1)` cities, a duplicate one city; strategic per turn = `ImprovedExtractionRate × STRATEGIC_UNIT_VALUE`; each converted component has a reason line stating its rule (FR-007); one-time yields spread over 50 turns × `GameSpeeds.CostMultiplier`/100
- [X] T027 [P] [US1] Write `tests/unit/test_rank.lua`: `SA_Rank.Top` picks the three highest `Score` among legal non-`LowData` sites within 8 plots of the settler, may be adjacent (FR-005), ties by smaller plot index; `TopProven` true only if no other site's `Upper` exceeds the third site's `Lower` (R21); quartile thresholds `{q1,q2,q3}` from sites within 8 plots (FR-004)
- [X] T028 [P] [US1] Write `tests/unit/test_determinism.lua`: the same map scored twice, and with shuffled job order, gives identical scores, tiers and top three (SC-008) (FR-027)

### Implementation for User Story 1

- [X] T029 [P] [US1] Implement `SettlementsAdvisor/Scripts/SA_Candidates.lua` (`Check(plotIndex) → Legal, RefusalReason|nil`) to pass T023
- [X] T030 [P] [US1] Implement `SettlementsAdvisor/Scripts/SA_Prior.lua` with `SA_Prior.GENERATOR` constants sourced from `DLC/Expansion2/Maps/Utility/{ResourceGenerator,FeatureGenerator,TerrainGenerator,AssignStartingPlots}.lua` (start-area boost only around visible capitals) to pass T024
- [X] T031 [P] [US1] Implement `SettlementsAdvisor/Scripts/SA_Tiles.lua` (`Plan` as exact DP over food surplus, `LowlandFactor`, `SA_Tiles.LOWLAND` model constant with justification) to pass T025
- [X] T032 [US1] Implement `SettlementsAdvisor/Scripts/SA_Coarse.lua` using SA_Candidates, SA_Prior, SA_Tiles, SA_Rules; component `Districts` is 0 with reason `LOC_SA_REASON_DISTRICTS_PENDING` until US3 (to pass T026)
- [X] T033 [US1] Implement `SettlementsAdvisor/Scripts/SA_Score.lua` (`Combine(site, layout)`; with `layout = nil` keeps coarse values) and `SettlementsAdvisor/Scripts/SA_Rank.lua` (`Top`, `NeedsRefine`, thresholds) to pass T027 and T028
- [X] T034 [US1] Create `SettlementsAdvisor/Config/SA_Colors.xml` with colors `COLOR_SA_TIER_1..4` and `COLOR_SA_LOW_DATA` and add it to `InGameActions` in `SettlementsAdvisor/SettlementsAdvisor.modinfo`
- [X] T035 [US1] In `SettlementsAdvisor/UI/SA_Main.lua`: on game load enqueue coarse scoring of every revealed land plot via SA_Scheduler (FR-025 priority 4 within 8 plots of any own settler, else 5; on settler selection its sites within 8 move to priority 3; FR-022) and store results in `SiteCache`
- [X] T036 [US1] In `SettlementsAdvisor/UI/SA_Main.lua`: build `SettlerView` on `UnitSelectionChanged` for own units with `FoundCity` (Nearby within 8, Thresholds, Top, TopProven, Message), clear it on deselect or other unit (FR-001, FR-002)
- [X] T037 [US1] In `SettlementsAdvisor/UI/SA_Main.lua`: color plots on layer `Hex_Coloring_Government` with `UILens.SetLayerHexesColoredArea` by tier and `LowData`, leave illegal plots uncolored, toggle off `Hex_Coloring_Water_Availablity` after the game turns it on, redraw on `Events.LensLayerOn`, restore both layers on clear (FR-003, R3; adjust per T014 results)
- [X] T038 [US1] Add a `WorldAnchor` instance for numbers 1–3 and the message line to `SettlementsAdvisor/UI/SA_Main.xml`; position with `UI.GridToWorld(plotIndex)` and `SetWorldPositionVal`; show `LOC_SA_MSG_NO_SITES` / `LOC_SA_MSG_NO_SITES_NEARBY` when applicable; fewer than three legal sites → fewer numbers
- [X] T039 [US1] When a site's result changes while a settler is selected, update colors and numbers without reselection and show «уточняется» while any `Top` site has `Status ~= "ready"` (FR-026)

**Checkpoint**: US1 работает: выделил Поселенца — видно окраску и тройку

---

## Phase 4: User Story 2 — Объяснение на любой клетке (Priority: P1)

**Goal**: при выделенном Поселенце подсказка клетки показывает балл, слагаемые с причинами,
диапазон, разницу с № 1, причину отказа; на карте отмечены обрабатываемые клетки.

**Independent Test**: quickstart, проверки 3, 4, 5, 14, 16, 17, 18, 19; тесты T040–T042 зелёные.

### Tests for User Story 2

- [X] T040 [P] [US2] Write `tests/unit/test_explain.lua`: `SA_Explain.Lines` follows the format in contracts/ui.md (title with «уточняется», «Против № 1» line, range line only with unrevealed plots, one line per component, ≤ 3 reasons per component plus «и ещё N», food/housing limiter line, lowland line, prices line); numbers with one decimal and a decimal comma in ru_RU; component lines sum to the title number (SC-004); `Diff(site, top1)` has `Σ ByComponent = Total` and ≤ 3 reasons by |value| (SC-011, R24); no diff line for top1; `Refusal(reason)` gives «Город здесь основать нельзя: …» for every RefusalReason (FR-014) (FR-012a)
- [X] T041 [P] [US2] Write `tests/unit/test_text.lua`: every `LOC_SA_*` key used in `SettlementsAdvisor/**/*.lua` exists in both `SA_Text_en_US.xml` and `SA_Text_ru_RU.xml`, and both files have the same key set (SC-010) (FR-029)
- [X] T042 [P] [US2] Write `tests/unit/test_hover.lua` for the pure helper `SA_Explain.PreviewTarget(view, hoveredPlot)`: returns the hovered site if legal, else `Top[1]`; returns nil without a settler view

### Implementation for User Story 2

- [X] T043 [US2] Implement `SettlementsAdvisor/Scripts/SA_Explain.lua` (`Lines`, `Diff`, `Refusal`, `PreviewTarget`, locale-aware number formatting) to pass T040 and T042
- [X] T044 [US2] Add all reason, refusal, component, limiter, lowland, diff and status keys (`LOC_SA_REASON_*`, `LOC_SA_REFUSAL_*`, `LOC_SA_COMP_*`, `LOC_SA_DIFF_*`, `LOC_SA_STATUS_*`) to `SettlementsAdvisor/Text/SA_Text_en_US.xml` and `SettlementsAdvisor/Text/SA_Text_ru_RU.xml` to pass T041
- [X] T045 [US2] In `SettlementsAdvisor/UI/SA_Main.lua`: publish `ExposedMembers.SettlementsAdvisor = { Active, GetLines }` (Active only while a settler is selected; GetLines uses SA_Explain with the current Top[1]); call `LuaEvents.PlotInfo_UpdatePlotTooltip()` when the hovered site's data changes
- [X] T046 [US2] Finish `SettlementsAdvisor/UI/SA_PlotToolTip.lua`: append lines from `GetLines` joined like the base tooltip; unchanged when `Active` is false (FR-012, FR-015)
- [X] T047 [US2] In `SettlementsAdvisor/UI/SA_Main.lua`: input handler on `MouseEvents.MouseMove` reading `UI.GetCursorPlotID()` (done as a per-frame read of `UI.GetCursorPlotID()` in `OnUpdate`: never swallows input), reacting only when the plot changes, returning false so input passes through; store `SettlerView.Hovered`
- [X] T048 [US2] Add a worked-tile `WorldAnchor` instance (small food/production icon, lower alpha than district icons) to `SettlementsAdvisor/UI/SA_Main.xml` and draw `site.Work.Plots` for `PreviewTarget` (FR-016a, R25)

**Checkpoint**: US1 и US2 работают вместе; подсказка объясняет каждое число

---

## Phase 5: User Story 3 — Предпросмотр раскладки районов (Priority: P2)

**Goal**: вокруг лучшего места и места под курсором — раскладка всех специализированных районов
с Акведуком и Дамбой по пользе, бонусы как у DMT, исправления DMT, доказанный оптимум или разрыв;
слагаемое «районы» и доказуемая тройка.

**Independent Test**: quickstart, проверки 6, 7, 8, 9, 20; тесты T049–T055 зелёные.

### Tests for User Story 3

- [X] T049 [P] [US3] Write fake DMT `tests/fake/dmt.lua` with the same global functions as DMT (`GetBonusYields`, `CanPlacePin`, `GetMapPinSubject`, `UpdateMapPinSubject`, `GetRealizedPlotFeatures`, `UpdatePinYields`, `InitializeModifierCalculator`, `CacheEffectiveModifiers`, `IsValidAqueductPosition`, `IsValidDamPosition`, `DMT_Initialize` that subscribes 3 LuaEvents + 11 Events) and simple adjacency rules (mountain +1 Campus, +0.5 per adjacent district, river +2 Commercial Hub), including its known bugs (unremovable resource dropped, shipwreck as sea resource, no flood check)
- [X] T050 [P] [US3] Write `tests/unit/test_dmt.lua` for `SA_DMT`: `Init` removes exactly the 3 LuaEvents and 11 Events subscribed by `DMT_Initialize`; `WithSite` puts a hypothetical `DISTRICT_CITY_CENTER` in the layer and restores the original globals after normal return and after an error; real pins and `DMT_MapPinSubjects` are never written; `SingleCache` key includes `centerAdj` and an Aqueduct legal at one site is not reused as legal at another; each fix from R10 (unremovable resource, flooded lowland, shipwreck, unreachable plot, unrevealed plot) — fails without the wrapper, passes with it (FR-030)
- [ ] T051 [P] [US3] Write `tests/unit/test_dmt_real.lua`: if installed DMT exists at `~/Library/Application Support/Steam/steamapps/workshop/content/289070/2428969051/ui/`, load it (read-only, never copied into the repo) with the fake world and check that `SA_DMT.Single` matches `GetBonusYields` of DMT on 20 placements; skip with a notice otherwise (FR-018, SC-005)
- [ ] T052 [P] [US3] Write `tests/unit/test_layout.lua`: on cases with ≤ 4 districts and ≤ 12 plots `SA_Layout.Solve` equals exhaustive search through the (fake) DMT and reports `Proven = true` (SC-007); `Bound(site) ≥` exact value for 1 000 random layouts; `Value ≤ Bound`, `Gap = Bound − Value`; identical output on repeat (принцип IV); with a node budget too small to prove, the result is identical with and without a warm start and for any order in which neighbour sites were solved (R12 step 4); among equal-value layouts the lexicographically smallest by plot indices in district-type order is returned (R12 step 5); a warm start that proves the optimum returns the same layout as the canonical start; mutually exclusive districts never both placed; `Placements` plots distinct and ≠ center; `Unplaced` and `Excluded` filled per data-model Layout (FR-021)
- [ ] T053 [P] [US3] Write `tests/unit/test_aqueduct_dam.lua`: Aqueduct included only when legal and value > 0 with reasons «нет пресной воды, +жильё» / «нет подходящей клетки»; Dam only when legal (floodplains, river edges) and useful, else reason «мало пойменных клеток» (FR-017a, FR-017b, R11)
- [ ] T054 [P] [US3] Write `tests/unit/test_rank_proof.lua`: refining every site fully yields the same Top three as the R21 stopping rule; the same Top three and `TopProven` with a shuffled queue order (принцип IV); the number of refined sites is recorded
- [X] T055 [P] [US3] Write `tests/unit/test_districts_component.lua`: after layout, the `Districts` component equals `Layout.Value` (with lowland factor on district plots, FR-010a) and its reasons list placements with yields and «оптимум доказан» or «можно ещё не больше +X» (FR-020)

### Implementation for User Story 3

- [X] T056 [US3] Implement `SettlementsAdvisor/Scripts/SA_DMT.lua` (`Init`, `RefreshModifiers`, `WithSite`, `Single`, `Evaluate`, layer replacing `GetMapPinSubject`/`UpdateMapPinSubject`/`GetRealizedPlotFeatures`, cache clear via `UpdatePinYields(pid, {})`, `pcall` on every DMT call with error = not placeable, `SingleCache` and `PairCache` keys per data-model) to pass T050 and T051
- [ ] T057 [US3] Implement the R10 fixes inside `SettlementsAdvisor/Scripts/SA_DMT.lua` and document each in `docs/dmt-patches.md` with DMT location and test name (FR-019)
- [ ] T058 [US3] Implement `SettlementsAdvisor/Scripts/SA_Layout.lua`: singles, per-plot pair gains (R12 step 2), `Bound` via Hungarian assignment (R12 step 3), canonical start = greedy + local search; warm start only to speed up proof, discarded and re-solved from the canonical start if the budget ends unproven (step 4); branching order and canonical tie rule (step 5); symmetry pruning for districts without own yields (step 6); exact evaluation memo (step 7); node budget, continuing only from the canonical start with a larger budget (step 8) — to pass T052 (FR-017c: maximize the joint value of all districts)
- [ ] T059 [US3] Add Aqueduct/Bath and Dam decisions to `SettlementsAdvisor/Scripts/SA_Layout.lua` (value = housing value from R11 + adjacency given to others − tile cost) to pass T053
- [ ] T060 [US3] Integrate layouts into scoring: `SA_Score.Combine` fills the `Districts` component and sets `Status = "ready"`; `SA_Rank` uses `Lower`/`Upper` from layout value and bound; the scheduler refines in FR-025 order: priority 2 for sites where `SA_Rank.NeedsRefine` is true in descending `Upper` (R21), then priority 3 and 4 sites, then priority 6 for the rest of the map — files `SettlementsAdvisor/Scripts/SA_Score.lua`, `SettlementsAdvisor/Scripts/SA_Rank.lua`, `SettlementsAdvisor/UI/SA_Main.lua` — to pass T054 and T055
- [X] T061 [US3] Call `SA_DMT.Init()` and `SA_DMT.RefreshModifiers()` on load and `LocalPlayerTurnBegin` in `SettlementsAdvisor/UI/SA_Main.lua`; if `Init` fails show `LOC_SA_MSG_NO_DMT` and keep coarse scoring without districts (R16)
- [X] T062 [US3] Add a district-icon `WorldAnchor` instance (icon `ICON_<DistrictType>`, yield text, semi-transparent) to `SettlementsAdvisor/UI/SA_Main.xml` and draw `Layout.Placements` for `PreviewTarget`, redrawing on hover changes; if the hovered legal site has no layout, enqueue it at FR-025 priority 1 and show «уточняется» until ready (FR-016, история 3 сценарий 2, SC-003)
- [ ] T063 [US3] Add tooltip lines for districts, Aqueduct/Dam decisions, «тройка доказана / уточняется» and proof status to `SettlementsAdvisor/Scripts/SA_Explain.lua` and new text keys to both text files (contracts/ui.md)
- [ ] T064 [US3] Developer mode flag `SA_Rules.DEV = false`; when true, on `CityAddedToMap` of an own city at a site with a cached layout compare DMT legality with `CityManager.GetOperationTargets` for owned plots and print `SA_MISMATCH:` lines (no game state change); add `mismatches` command to `tools/tuner.py` that appends them to `docs/dmt-mismatches.md` (R27)

**Checkpoint**: US1–US3 работают; раскладка видна и совпадает с DMT


---

## Phase 5a: Метки после основания и подсказка словами (добавлено 2026-10-29, FR-012b, FR-030–FR-032)

**Goal**: после основания города на клетках раскладки стоят метки DMT; мод переставляет только свои
метки, когда план меняется; подсказка начинается словами «почему здесь».

- [X] T082 [US3] `SettlementsAdvisor/Scripts/SA_Explain.lua`: строки «почему здесь» словами (вода и рост, производство, районы с бонусами, роскошь) перед числами; тест в `tests/unit/test_explain.lua` (FR-012b)
- [X] T083 [US3] `SettlementsAdvisor/Scripts/SA_Pins.lua`: план меток города из раскладки (тип района → значок `ICON_<DistrictType>`, имя-признак мода), разница «что поставить / что убрать» против текущих меток мода; метки игрока не трогаются; тест `tests/unit/test_pins.lua` (FR-031, FR-032)
- [X] T084 [US3] `SettlementsAdvisor/UI/SA_Main.lua`: на `Events.CityAddedToMap` своего города — раскладка с учётом построенного, метки через `PlayerConfigurations[pid]:GetMapPin` и `Network.BroadcastPlayerInfo` (ловушки 4, 5) (FR-031)
- [X] T085 [US3] `SettlementsAdvisor/UI/SA_Main.lua`: пересчёт раскладки городов с метками мода на `DistrictAddedToMap`, `BuildingAddedToMap` (чудо), `ResourceVisibilityChanged`, `FeatureRemovedFromMap`, смену границ; переставлять только изменившиеся метки (FR-032)
- [X] T086 [US3] Дамба в раскладке: `SA_Coarse.LayoutDistricts` добавляет `DISTRICT_DAM` при пойме на реке в радиусе 3, законность — DMT; связка с Промзоной и Акведуком — соседство DMT; тест `test_dam_and_industrial_zone_stack` (FR-017b; просьба пользователя 2026-10-29)
- [X] T087 [US3] Стакинг районов: `SA_Layout.STACK_WEIGHT` — подсказка поиску за каждое касание район–район и район–центр (бонус «+1 за 2 района» округляется вниз и жадный поиск без неё не собирает кучу); финальный проход без подсказки; тест `test_districts_stack_on_flat_land`
- [X] T089 [US3] Районы-заполнители (`SA_Rules.IsFiller`: без своих правил соседства и без бонусов другим — Военный лагерь, Аэродром, Икханда) платят полную ценность клетки и не входят в кучу; тест `test_filler_districts_take_worst_plots` (просьба пользователя 2026-10-29)

- [X] T088 Правительственная площадь и общий план городов: `SA_Empire` (города планируются по очереди, районы соседей — занятые клетки с учётом соседства; площадь — на клетке, куда дотягивается больше всего городов, лучшая из 6 кандидатов по общей раскладке; повторный поиск только при смене списка городов); `tests/unit/test_empire.lua`. В игре проверено на 1 городе (площадь не планируется, план совпал с метками); с 2–3 городами — не проверено
- [X] T090 [US3] Классический треугольник первых трёх городов (просьба пользователя 2026-10-29): при 1–2 городах `SA_Empire.Triangle` выбирает места городов 2 и 3 (4–6 клеток от всех городов, 20 лучших мест, пары по оценке, площадь — где сходятся все три) и площадь; метки мест городов и площади ставятся у столицы, когда есть Поселенец; поиск заново при загрузке, в начале хода, при новом Поселенце или городе; тест `test_triangle_from_the_capital`
- [X] T091 [US3] Города 4+ вне треугольника, но стакаются с соседями: раскладка места для Поселенца видит спланированные районы соседних городов (`SA_Coarse.Layout` opts.fixed), засчитывается только прибавка их соседства (`FixedGain`)
- [X] T092 [US3] Заполнители не занимают клетки у площади и у центров (штраф `SA_Coarse.FILLER_PLAZA_SPOT` = 4, `FILLER_CENTER_SPOT` = 1)
- [X] T093 [US3] Акведук только рядом со своим центром (`SA_Layout`), тест `test_aqueduct_only_next_to_own_center`; цена клетки против запасной минус вырубка/сбор (`SA_Coarse.PlotCost`), тест `test_plot_cost_against_replacement` (просьба пользователя 2026-10-29)
- [X] T094 [US3] Уникальное у всех наций (просьба пользователя 2026-10-29): тест `tests/unit/test_civs.lua` по всем цивилизациям и лидерам — уникальный район вместо базового (исправлен Тхань Вьетнама: `RequiresPopulation = 0`), чужие уникальные районы и улучшения не планируются (`SA_Rules.CanUseImprovement`), Совон Кореи (−1 за соседний район) вне кучи (`SA_Rules.AvoidsStack`). Способности наций и лидеров в соседстве считает DMT по активным модификаторам игрока; уникальные здания на место районов не влияют и не учитываются
- [X] T095 [US3] Метки без имени (просьба пользователя: «подписи мешают»): новые метки без `SetName`, старые метки мода с именем пересоздаются при следующем пересчёте
- [X] T096 [US3] Уникальные улучшения (кампонг, польдер, ступенчатый колодец…): условия соседства из данных (`SA_Rules.ImprovementFitsNeighbours`: `ValidAdjacentTerrainAmount` + `Improvement_ValidAdjacentTerrains`, `Improvement_InvalidAdjacentFeatures`, `Improvement_ValidAdjacentResources`, `RequiresAdjacentBonusOrLuxury`); метки уникальных улучшений в плане города (`SA_Empire.ImprovementPins`: только где уникальное лучше всего, без соседства одинаковых при `SameAdjacentValid = 0`, одно на город при `OnePerCity`); тест `test_unique_improvement_pins`. В выгрузке правил для тестов нет таблиц соседства — польдер офлайн не проверен (просьба пользователя 2026-10-29)
- [X] T097 [US3] Уникальные улучшения всегда в приоритете там, где их можно поставить (выбор пользователя 2026-10-29); кроме Великой стены, фейтории и горной дороги — их правила в данных не записаны
- [X] T098 [US4] Пересчёт мест при открытии клеток (`PlotVisibilityChanged` → сброс кэша клеток и оценка мест в радиусе 3, у Поселенцев первыми; места с раскладкой тоже). В игре на 1-м ходу устаревшие пометки «мало данных» не пускали лучшее место в тройку
- [ ] T099 [US1] Ход Поселенца (R28, просьба пользователя 2026-10-29): `SA_World.TurnsTo` по `UnitManager.GetMoveToPathEx`, `SA_Rank.Effective`/`Top`/`Thresholds` с travel, строка «Дорога» в `SA_Explain.Lines` — готово с тестами (`test_travel_penalty_and_unreachable`, `test_travel_line`); подключено в `SA_Main.lua`; осталось проверить в игре
- [ ] T100 [US3] Устойчивость советов (R29, просьба пользователя 2026-10-29: «точки перепрыгивают, игра тормозит»): липкие метки (`SA_Layout.KEEP_BONUS`, тест `test_pinned_district_stays_unless_clearly_worse`), треугольник держится (`SA_Empire.TRIANGLE_SWITCH`, `test_kept_triangle_holds`), тройка держится (`SA_Rank.KEEP_MARGIN`, `test_numbered_sites_hold_their_place`), устаревшие раскладки показываются до пересчёта, сброс снимков только при загрузке и в начале хода, уступка кадра в поиске треугольника, путь игры только для 12 лучших мест, замеры `SA_SLOW`; осталось проверить в игре







---

## Phase 6: User Story 4 — Свежие данные без ожидания (Priority: P3)

**Goal**: после открытия клеток, основания или потери городов, изменений районов, улучшений,
особенностей, технологий и начала хода пересчитываются только затронутые места, а игра
не тормозит.

**Independent Test**: quickstart, проверки 10, 11, 12; тесты T065–T066 зелёные.

### Tests for User Story 4

- [ ] T065 [P] [US4] Write `tests/unit/test_dirty.lua`: each event from research R7 marks the documented radius (plot + 3; city ± `CITY_MIN_RANGE + 3`; …); affected sites get `Version` increased and `Status` reset to `coarse`; unaffected sites keep results and proofs
- [ ] T066 [P] [US4] Write `tests/unit/test_queue.lua`: priority order from FR-025 / data-model `Queue` (1 — hovered site without layout; 2 — sites of the selected settler with `Upper` above third `Lower`, by descending `Upper`; 3 — other sites within 8 of the selected settler; 4 — within 8 of other own settlers; 5 — coarse scoring of the rest; 6 — layouts of the rest; ties by index); selecting another settler reorders without losing finished work

### Implementation for User Story 4

- [ ] T067 [US4] Subscribe in `SettlementsAdvisor/UI/SA_Main.lua` to `PlotVisibilityChanged`, `ResourceVisibilityChanged`, `CityAddedToMap`, `CityRemovedFromMap`, `CityTileOwnershipChanged`, `DistrictAddedToMap`, `DistrictRemovedFromMap`, `ImprovementAddedToMap`, `ImprovementRemovedFromMap`, `ImprovementChanged`, `FeatureRemovedFromMap`, `ResearchCompleted`, `CivicCompleted`, `LocalPlayerTurnBegin`, `LoadGameViewStateDone` and map them to `SA_World.MarkDirty` per R7 (FR-024) to pass T065
- [ ] T068 [US4] Implement the priority rules of T066 in `SettlementsAdvisor/Scripts/SA_Scheduler.lua` and the re-enqueue of dirty sites in `SettlementsAdvisor/UI/SA_Main.lua`
- [ ] T069 [US4] Batch event handling: collect dirty plots during a turn and flush on `GameCoreEventPublishComplete` or the next `Step` to avoid recomputing per event, in `SettlementsAdvisor/UI/SA_Main.lua`

**Checkpoint**: все истории работают и не мешают друг другу

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: снимки реальных карт, замеры, финальная проверка

- [ ] T070 [P] Add `snapshot <name>` to `tools/tuner.py`: runs Lua in game that exports only revealed plots (terrain, feature, visible resource, river edges, owner, cities, lowland, visibility) and player data (civilization, traits, techs, civics, owned resources) to `logs/snapshots/<name>.json` (R26)
- [ ] T071 [P] Write `tools/snapshot_to_fixture.py` converting `logs/snapshots/<name>.json` into `tests/fixtures/maps/<name>.lua` for `tests/fake/world.lua`
- [ ] T072 Take snapshots `early`, `mid`, `coast` from the user's saves (quickstart) and add `tests/unit/test_real_maps.lua` checking invariants on them: sums (SC-004, SC-011), `Value ≤ Bound`, food constraint (SC-012), determinism (SC-008), proven top three when budgets allow
- [ ] T073 Run quickstart checks 1–20 in game (including SC-005 tack comparison and SC-006 engine legality) and record results (date, check, pass/fail, notes) in the section «Результаты проверки в игре» of `specs/001-settler-site-lens/plan.md` (принцип VI)
- [ ] T074 Measure SC-001 (selection response), SC-002 (average frame rate on the same camera route without the mod and with the mod during background work; frames > 100 ms) and SC-003 (sites near settlers fully ready ≤ 10 s, coarse whole map ≤ 60 s, hovered site layout ≤ 2 s) on `mid` with `tools/tuner.py` timestamps; record numbers in `docs/accuracy.md`
- [ ] T075 Calibrate `SA_Scheduler.OPS_PER_FRAME` from T074 and, if SC-003 is missed, apply research R19 measures or the future ideas 8–9 from `docs/architecture.md` §12; re-measure (FR-023)
- [ ] T076 [P] Measure solver quality on real snapshots against an own simple beam-search baseline `tests/bench/beam.lua` (own code, принцип X): share of proven optima, average gap, value vs beam, number of refined sites per settler (R21), assignment bound vs independent-sum bound tightness (R20); record in `docs/accuracy.md`
- [ ] T077 [P] Measure `SA_Prior` accuracy (R20): take two snapshots of the same game at different turns, compare expected values for plots unrevealed in the first and revealed in the second; record mean error and range coverage in `docs/accuracy.md`
- [ ] T078 Derive `SA_Rules.STRATEGIC_UNIT_VALUE` from game data where possible: for units with `Units_XP2.ResourceCost > 0`, production saved versus the previous unit of the same class (`Units.Cost` difference) per resource unit, priced by `YIELD_PRICES`; take the median, document the derivation in `docs/accuracy.md`, replace the constant if stable and update plan.md Complexity Tracking
- [ ] T079 SC-009 check with the user: 3 players who have not seen the mod explain from the tooltip why place № 1 is better than № 2; record the outcome in the section «Результаты проверки в игре» of `specs/001-settler-site-lens/plan.md`
- [ ] T080 [P] Update `docs/architecture.md` (stages 0–2 done, deviations found in stage 0) and `docs/pitfalls.md` with new pitfalls found during implementation
- [ ] T081 Final run of `.tools/lua51/bin/lua tests/run.lua` and `tools/deploy.sh` validation; all green

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: без зависимостей. T002 до любых тестов; T004 до T015.
- **Foundational (Phase 2)**: после Setup.
  - T011–T014 (этап 0) идут первыми: их результаты могут изменить R3, R5, R7, R8, R11, R14,
    R23, R27.
  - T015 до T017, T019, T021.
- **US1 (Phase 3)**: после Foundational.
- **US2 (Phase 4)**: после US1. Подсказка объясняет баллы US1; тесты T040–T042 можно писать
  параллельно с US1.
- **US3 (Phase 5)**: после US1. Нужны SA_Score/SA_Rank. Тесты T049–T055 можно писать параллельно
  с US1/US2; T062 зависит от T047 (наведение из US2).
- **US4 (Phase 6)**: после US1. Независима от US2 и US3, но T068 учитывает приоритет R21 из T060,
  если US3 готова.
- **Polish (Phase 7)**: после всех историй. T070–T071 можно сделать раньше, сразу после T008.

### Within Each User Story

- Тесты пишутся первыми и падают, потом реализация.
- Модули `Scripts/` — до интеграции в `UI/`.
- Каждая история заканчивается проверкой из quickstart.

### Parallel Opportunities

- Setup: T003–T010 параллельно после T001.
- Foundational: T016, T017, T019, T021 параллельно после T015.
- US1: тесты T023–T028 параллельно; реализация T029–T031 параллельно.
- US2: тесты T040–T042 параллельно.
- US3: тесты T049–T055 параллельно.
- US4: T065, T066 параллельно.
- Polish: T070, T071, T076, T077, T080 параллельно.

---

## Parallel Example: User Story 1

```bash
# Тесты US1 одновременно:
Task: "Write tests/unit/test_candidates.lua"
Task: "Write tests/unit/test_prior.lua"
Task: "Write tests/unit/test_tiles.lua"
Task: "Write tests/unit/test_coarse.lua"
Task: "Write tests/unit/test_rank.lua"
Task: "Write tests/unit/test_determinism.lua"

# Независимые модули US1 одновременно:
Task: "Implement SettlementsAdvisor/Scripts/SA_Candidates.lua"
Task: "Implement SettlementsAdvisor/Scripts/SA_Prior.lua"
Task: "Implement SettlementsAdvisor/Scripts/SA_Tiles.lua"
```

## Parallel Example: User Story 3

```bash
Task: "Write fake DMT tests/fake/dmt.lua"
Task: "Write tests/unit/test_layout.lua"
Task: "Write tests/unit/test_aqueduct_dam.lua"
Task: "Write tests/unit/test_rank_proof.lua"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1: Setup.
2. Phase 2: Foundational, включая этап 0 в игре (T013–T014).
3. Phase 3: US1.
4. **STOP and VALIDATE**: quickstart, проверки 1, 2, 13, 15.

### Incremental Delivery

1. Setup + Foundational → основа.
2. US1 → окраска и тройка (MVP).
3. US2 → подсказка с объяснением, разницей с № 1 и отметками клеток.
4. US3 → раскладка районов, Акведук и Дамба, доказуемая тройка. Это первая играбельная версия
   по architecture.md.
5. US4 → свежесть при изменениях карты.
6. Polish → реальные карты, замеры, калибровка.

---

## Notes

- [P] — разные файлы, нет зависимостей от незавершённых задач.
- Не коммитить без запроса пользователя; git ещё не инициализирован.
- Изменение `AppOptions.txt` (FireTuner) и сохранения игрока — только с согласия пользователя.
- При расхождении с конституцией — остановиться и предложить поправку, а не обходить.
