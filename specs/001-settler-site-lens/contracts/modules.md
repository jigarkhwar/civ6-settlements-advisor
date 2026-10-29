# Contract: модули логики (`Scripts/`)

Публичные функции модулей, которые тестируются автономно (принцип VI). Код в `Scripts/`
не обращается к `Controls`, `ContextPtr` и UI-событиям. Доступ к игре идёт только через `SA_World`.
Типы описаны в [data-model.md](../data-model.md).

## SA_World — доступ к игре

| Функция | Возвращает | Примечание |
|---|---|---|
| `SA_World.Snapshot(plotIndex)` | PlotSnapshot | кэш до смены `Version` |
| `SA_World.Ring(plotIndex, r)` | `{plotIndex}` отсортировано | клетки на расстоянии 1..r |
| `SA_World.Distance(a, b)` | int | гекс-расстояние |
| `SA_World.Cities()` | `{ {Player, Plot} }` | видимые города всех игроков |
| `SA_World.LocalPlayer()` | int | |
| `SA_World.MarkDirty(plotIndex, radius)` | — | |
| `SA_World.Version()` | int | растёт при любом изменении |

В тестах `SA_World` заменяется поддельным миром (`tests/fake/world.lua`) с теми же функциями.

## SA_Rules — правила из данных игры

| Функция / поле | Смысл |
|---|---|
| `SA_Rules.Param(name)` | `GlobalParameters` (числа) |
| `SA_Rules.BaseYields(snapshot)` | доход клетки без улучшения |
| `SA_Rules.BestImprovement(snapshot, player)` | `{Improvement, Yields, RemovesFeature}` (R13) |
| `SA_Rules.SiteDistricts(player)` | отсортированный список специализированных районов цивилизации (FR-017) |
| `SA_Rules.MutuallyExclusive(a, b)` | bool |
| `SA_Rules.YIELD_PRICES` | цены FR-007 |
| `SA_Rules.Price(yields)` | число в ценах |

## SA_Prior — неоткрытые клетки

| Функция | Возвращает |
|---|---|
| `SA_Prior.Estimate(plotIndex)` | PlotPrior (R15) |
| `SA_Prior.GENERATOR` | доли генератора со ссылками на файл:строку |

## SA_Candidates

| Функция | Возвращает |
|---|---|
| `SA_Candidates.Check(plotIndex)` | `Legal, RefusalReason\|nil` (FR-010) |

## SA_Tiles — обрабатываемые клетки

| Функция / поле | Возвращает |
|---|---|
| `SA_Tiles.Plan(siteIndex, needed, excludedPlots)` | WorkPlan (R22): точный выбор при ограничении по еде и жилью |
| `SA_Tiles.LowlandFactor(snapshot)` | множитель 0..1 для клетки-низины по текущему шагу подъёма моря (R23) |
| `SA_Tiles.LOWLAND` | константы модели для затоплений, с обоснованием |

Инвариант: еда центра + еда выбранных клеток ≥ `Citizens × CITY_FOOD_CONSUMPTION_PER_POPULATION`;
на малых случаях ответ равен полному перебору наборов.

## SA_Coarse — грубая оценка (уровень 1)

| Функция | Возвращает |
|---|---|
| `SA_Coarse.Score(plotIndex)` | Site с `Status = "coarse"`. Все слагаемые; «районы» — оценка сверху по одиночным значениям |

## SA_DMT — DMT с исправлениями

| Функция | Возвращает | Примечание |
|---|---|---|
| `SA_DMT.Init()` | ok, err | include, снятие 3+11 подписок, кэш модификаторов (R9) |
| `SA_DMT.RefreshModifiers()` | — | при загрузке и в начале хода |
| `SA_DMT.WithSite(siteIndex, fn)` | результат `fn` | ставит воображаемый центр в слой, гарантированно снимает (`pcall`) |
| `SA_DMT.Single(siteIndex, district, plot)` | `Legal, Yields, ToolTip` | через `SingleCache`; исправления R10 применены |
| `SA_DMT.Evaluate(siteIndex, placements)` | `Legal, Total, PerPlacement` | точная оценка раскладки |

Инварианты:
- после любого выхода из `WithSite` и `Evaluate` слой пуст, глобальные функции DMT восстановлены;
- настоящие метки игрока и данные `DMT_MapPinSubjects` не меняются.

## SA_Layout — решатель (уровень 2)

| Функция | Возвращает |
|---|---|
| `SA_Layout.Bound(siteIndex)` | верхняя граница раскладки по задаче о назначениях (R12, шаг 3), без ветвления |
| `SA_Layout.Solve(siteIndex, budgetNodes, warmStart)` | Layout (R11, R12); `warmStart` — раскладка соседнего места или nil; можно продолжить с сохранённого дерева |

## SA_Rank — доказуемая тройка

| Функция | Возвращает |
|---|---|
| `SA_Rank.Top(sites)` | `Top, TopProven` (R21) |
| `SA_Rank.NeedsRefine(site, top)` | bool: `site.Upper > Lower` третьего места |

Инварианты:
- одинаковый вход даёт одинаковый Layout (принцип IV);
- `Value ≤ Bound`;
- `Proven` означает, что `Value` — максимум по точной оценке DMT;
- на малых случаях результат совпадает с полным перебором (тест).

## SA_Score

| Функция | Возвращает |
|---|---|
| `SA_Score.Combine(site, layout)` | Site с `Status = "ready"`; `Score = Σ Components.Value` (FR-013) |

## SA_Scheduler — фон по кадрам

| Функция | Смысл |
|---|---|
| `SA_Scheduler.Enqueue(plotIndex, priority)` | |
| `SA_Scheduler.Tick(ops)` | вызывать из работы; уступает кадр при исчерпании квоты (не внутри `pcall`) |
| `SA_Scheduler.Step()` | один кадр; вызывает `SetUpdate` главного контекста |
| `SA_Scheduler.OPS_PER_FRAME` | константа, калибруется на этапе 1 |

## SA_Explain

| Функция | Возвращает |
|---|---|
| `SA_Explain.Lines(site, top1)` | `{string}` строк подсказки (формат — [ui.md](ui.md)); при `site ~= top1` — с разницей |
| `SA_Explain.Diff(site, top1)` | Diff (R24); `Σ ByComponent = Total` |
| `SA_Explain.Refusal(reason)` | string |

## Инструменты разработки (`tools/`)

| Команда | Что делает |
|---|---|
| `tuner.py serve` | держит соединение с игрой, пишет вывод в `logs/tuner.log` |
| `tuner.py exec <lua>` | выполняет Lua в контексте мода, возвращает структурированный ответ |
| `tuner.py assert <lua> <ожидание>` | проверка из quickstart; код выхода 0/1 |
| `tuner.py snapshot <имя>` | снимок открытой части карты в JSON (R26) |
| `tuner.py mismatches` | собирает строки `SA_MISMATCH` в `docs/dmt-mismatches.md` (R27) |
| `snapshot_to_fixture.py <имя>` | JSON → `tests/fixtures/maps/<имя>.lua` |
| `export_gameinfo.py` | `DebugGameplay.sqlite` → `tests/fixtures/gameinfo.lua` |
