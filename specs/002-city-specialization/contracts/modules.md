# Contract: модули логики 002

Все функции — чистая логика в `Scripts/` (принцип VI); доступ к игре — только через `SA_World`.
Сущности — в [../data-model.md](../data-model.md). Контракты 001 — в
[../../001-settler-site-lens/contracts/modules.md](../../001-settler-site-lens/contracts/modules.md).

## SA_Growth (новый)

| Функция | Вход | Выход | Тест |
|---|---|---|---|
| `Threshold(pop)` | население | еда до следующего жителя по `GlobalParameters` | формула R3 на 1, 5, 10 |
| `Forecast(site, pid, opts)` | клетка центра; `opts.current` — текущее население своего города | `Forecast` | сытое место > голодного; жильё останавливает рост; `current` не уменьшается |
| `Limit(pop)` | население | лимит районов с `RequiresPopulation = 1` | 1→1, 3→1, 4→2, 7→3 |

## SA_Strategy (новый)

| Функция | Вход | Выход | Тест |
|---|---|---|---|
| `Signals(pid)` | игрок | список сигналов R4, детерминированно отсортирован | у всех лидеров выгрузки — без ошибок; уникальный район даёт сигнал веса 3 |
| `Auto(pid)` | игрок | победа или `"BALANCED"`, причины | для 100 % лидеров есть ответ (SC-004) |
| `Get(pid, choice)` | игрок, `"AUTO"` или `VICTORY_*` | `Strategy` | выбор игрока заменяет победу; уникальные районы остаются ключевыми |

## SA_Specialize (новый)

| Функция | Вход | Выход | Тест |
|---|---|---|---|
| `Select(layout, strategy, limit, keep)` | полная раскладка 001, стратегия, лимит, районы на метках | отобранные районы и `Dropped` | не больше лимита; ключевой с соседством < `KEY_MIN_ADJ` выпадает раньше второстепенного с большим; `keep` даёт запас |
| `Assign(cities, strategy)` | города с лимитами и соседством ключевых районов | `{ [city] = список районов }` | совпадает с полным перебором на малых картах или отстаёт ≤ 5 % (SC-005) |
| `RegionalCover(plot, district, centers, covered)` | клетка, район, центры городов и мест, уже покрытые | число новых покрытых городов | радиус из данных; уже покрытые не считаются (SC-006) |
| `Label(spec, strategy)` | специализация | ярлык | равенство — по типу района |

## Изменения модулей 001

| Модуль | Изменение |
|---|---|
| `SA_Rank` | `TempoLoss(turns)` по R1, `TravelPenalty(score, turns) = max(0, score) × TempoLoss(turns)`; `Verdict(sites, travel, top, previous)` → `Verdict` (кандидаты «здесь» и «рядом» — клетки с точной дорогой 0 и 1 ход) |
| `SA_Coarse` | `Layout`/`CityLayout`: второй проход по отобранным районам; `Score` берёт районы отбора и добавляет в причины `Forecast` |
| `SA_Layout` | `opts.regional = function(plot, district) → value` в цели поиска (как `cost`, с обратным знаком) |
| `SA_Empire` | `Plan(pid, opts.strategy)`: `Assign` перед раскладкой городов; специализация в плане |
| `SA_Explain` | `VerdictText(verdict)` → строка вердикта или nil; `Lines(..., opts.Verdict, opts.Forecast, opts.Strategy, opts.Specialization)` → строки R9 (вердикт — только на клетке `Verdict.Here`) |
| `SA_World` | `CityPopulation(plot)`, `EnabledVictories()` |
