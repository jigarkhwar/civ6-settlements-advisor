# Data Model: Линза мест при выборе Поселенца

Phase 1 для [plan.md](plan.md). Сущности из [spec.md](spec.md) (Key Entities), в виде Lua-таблиц
главного контекста. Все списки отсортированы по индексу клетки (принцип IV).

## PlotSnapshot

Снимок клетки за ход. Модуль `SA_World` — единственный, кто читает игру.

| Поле | Тип | Источник / правило |
|---|---|---|
| `Index` | int | `plot:GetIndex()` |
| `X`, `Y` | int | координаты |
| `Revealed` | bool | видимость для игрока |
| `Terrain`, `Feature`, `Resource` | string\|nil | только если `Revealed`; ресурс — только если видим игроку (FR-008) |
| `ResourceCount` | int | `plot:GetResourceCount()` |
| `River`, `Lake`, `Coastal`, `FreshWater` | bool | `IsRiver`, `IsLake`, `IsCoastalLand`, `Features.AddsFreshWater` у соседей |
| `Owner` | int\|-1 | владелец клетки |
| `CityPlayer` | int\|nil | на клетке видимый город |
| `District`, `Improvement` | string\|nil | уже построенное |
| `Flooded` | bool | `TerrainManager.IsFlooded` |
| `Lowland` | `"1M"` \| `"2M"` \| `"3M"` \| nil | `TerrainManager.GetCoastalLowlandType` → `CoastalLowlands` (R23) |
| `Latitude` | number | для `SA_Prior` |

Правило: при `Revealed = false` поля местности пустые, и клетку оценивает `SA_Prior`.

## PlotPrior

Ожидаемая ценность неоткрытой клетки (`SA_Prior`, research R15).

| Поле | Тип | Смысл |
|---|---|---|
| `Expected` | `{[yield] = number}` | ожидаемый доход с лучшим улучшением |
| `Max` | `{[yield] = number}` | лучший правдоподобный вариант |
| `LuxuryChance`, `StrategicChance` | number | вероятность ресурса класса |
| `Reasons` | `{string}` | «вероятно равнина: 4 из 5 соседей» |

`Min` всегда нулевой: неоткрытая клетка ничего не даёт (FR-009).

## Site (место, кандидат)

| Поле | Тип | Правило |
|---|---|---|
| `Index` | int | клетка центра |
| `Legal` | bool | FR-010 |
| `Refusal` | RefusalReason\|nil | при `Legal = false` |
| `Score` | number | ожидаемый балл = сумма `Components[i].Value` (FR-013) |
| `Min`, `Max` | number | диапазон (FR-009); без неоткрытых клеток `Min = Max = Score` |
| `Unrevealed` | int | неоткрытые клетки в радиусе 3 |
| `LowData` | bool | `Unrevealed > половины радиуса 3` → не попадает в лучшие три |
| `Components` | `{Component}` | фиксированный порядок: Tiles, Water, Luxury, Strategic, OneTime, Districts |
| `Work` | WorkPlan | обрабатываемые клетки (R22) |
| `Layout` | Layout\|nil | после уровня 2 |
| `Lower`, `Upper` | number | границы балла для доказуемой тройки (R21): `Lower` — найденная раскладка и минимум диапазона, `Upper` — граница по задаче о назначениях и максимум диапазона |
| `Status` | `"coarse"` \| `"refining"` \| `"ready"` | FR-026; `coarse` и `refining` показываются как «уточняется» |
| `Version` | int | номер версии снимка, по которому посчитано; устаревшие места пересчитываются |

Переходы `Status`:

```
(нет) ─[грубая оценка]→ coarse ─[старт раскладки]→ refining ─[раскладка закончена]→ ready
  ▲                                                                                 │
  └──────────────────────────[участок помечен грязным]──────────────────────────────┘
```

## WorkPlan (обрабатываемые клетки)

| Поле | Тип | Правило |
|---|---|---|
| `Needed` | int | P = 3k − 2 по раскладке (k — специализированные районы) |
| `FoodLimit` | int | наибольшее n, при котором еды хватает (R22) |
| `Citizens` | int | `min(Needed, FoodLimit, свободных клеток)`; жильё не ограничивает (R14) |
| `Plots` | `{plotIndex}` | выбранные клетки, `#Plots = Citizens` |
| `Limiter` | `"food"` \| `"plots"` \| nil | что ограничило; для причины в подсказке |
| `Eaten` | number | `Citizens × CITY_FOOD_CONSUMPTION_PER_POPULATION`, вычитается из «клеток» |
| `LowlandPenalty` | number | снято за риск затопления (R23); уже внутри ценности клеток, причина — для объяснения |

Жильё места (`SA_Tiles.Housing`): `Water` (вода и Акведук), `Kind`, `Aqueduct`, `Improvements`,
`Total`. Слагаемое «вода и жильё» = `Total × SA_Rules.HousingValue()` (R14).

Правило: еда центра + Σ еды `Plots` ≥ `Citizens × CITY_FOOD_CONSUMPTION_PER_POPULATION`.

## Diff (разница с № 1)

| Поле | Тип | Правило |
|---|---|---|
| `Total` | number | `site.Score − top1.Score` |
| `ByComponent` | `{[Key] = number}` | Σ = `Total` (SC-011) |
| `Reasons` | `{Reason}` | до 3 с наибольшим |вкладом|; ключ сопоставления — (слагаемое, клетка или ресурс) (R24) |

## Component (слагаемое)

| Поле | Тип | Правило |
|---|---|---|
| `Key` | `"Tiles"` \| `"Water"` \| `"Luxury"` \| `"Strategic"` \| `"OneTime"` \| `"Districts"` | |
| `Value` | number | доход за ход в ценах FR-007 |
| `Min`, `Max` | number | вклад неопределённости |
| `Reasons` | `{Reason}` | хотя бы одна причина при `Value ~= 0` (история 2, сценарий 1) |

## Reason

| Поле | Тип | Смысл |
|---|---|---|
| `Key` | string | ключ сопоставления для разницы (R24): слагаемое + клетка или ресурс, например `Tiles:1234`, `Luxury:RESOURCE_WINE` |
| `Text` | LOC-ключ + параметры | например, `LOC_SA_REASON_FLOODPLAIN` + `{2, "FOOD"}` |
| `Value` | number | вклад причины |
| `Plot` | int\|nil | клетка, к которой относится |

Причины в подсказке сортируются по |Value| по убыванию, затем по индексу клетки.

## RefusalReason (перечисление)

`TOO_CLOSE_TO_CITY`, `FOREIGN_TERRITORY`, `WATER`, `MOUNTAIN`, `IMPASSABLE`, `FEATURE_FORBIDS`,
`UNREVEALED`, `FLOODED`, `NATURAL_WONDER`.

Каждому значению соответствует ключ `LOC_SA_REFUSAL_<NAME>`.

## Layout (раскладка районов)

| Поле | Тип | Правило |
|---|---|---|
| `Placements` | `{Placement}` | по типу района |
| `Unplaced` | `{DistrictType}` | возможны, но не поместились (FR-021) |
| `Excluded` | `{DistrictType → reason}` | невозможны по географии / лимит империи / взаимоисключение (FR-017) |
| `Aqueduct`, `Dam` | Decision | FR-017a |
| `Value` | number | сумма бонусов соседства в ценах |
| `Bound` | number | верхняя оценка (R12) |
| `Proven` | bool | перебор закончен (FR-020) |
| `Gap` | number | `Bound − Value`, 0 при `Proven` |

Правила:
- все `Placements` законны по DMT с исправлениями (FR-017b, FR-019);
- клетки различны и не совпадают с центром.

## Placement

| Поле | Тип |
|---|---|
| `District` | string (`DISTRICT_*`, уникальный — свой тип) |
| `Plot` | int |
| `Yields` | `{[yield] = number}` от DMT |
| `ToolTip` | string от DMT (источники бонуса) |

## Decision (Акведук / Дамба)

| Поле | Тип | Смысл |
|---|---|---|
| `Include` | bool | |
| `Plot` | int\|nil | |
| `Reason` | LOC-ключ | «нет пресной воды, +жильё», «мало пойменных клеток», «нет подходящей клетки» |
| `Value` | number | польза минус стоимость клетки |

## SettlerView

Состояние для выделенного Поселенца (не хранится в сохранении).

| Поле | Тип | Правило |
|---|---|---|
| `UnitKey` | `{player, unitID}` | |
| `Origin` | int | клетка Поселенца |
| `Nearby` | `{Site}` | законные места в радиусе 8 (FR-005) |
| `Thresholds` | `{q1, q2, q3}` | четверти баллов `Nearby` (FR-004) |
| `Top` | `{Site, Site, Site}` | три лучших из `Nearby`, без `LowData`; при равенстве — меньший индекс клетки |
| `TopProven` | bool | ни у одного другого места из `Nearby` `Upper` не превышает `Lower` третьего места (R21) |
| `Hovered` | Site\|nil | место под курсором; если законно, раскладка рисуется вокруг него |
| `Message` | LOC-ключ\|nil | «рядом нет подходящих мест» и т. п. |

## SiteCache и DirtySet

| Сущность | Поля | Правило |
|---|---|---|
| `SiteCache` | `[plotIndex] → Site` | общий; читается подсказкой через `ExposedMembers.SettlementsAdvisor` |
| `SingleCache` | `[(district, plot, neighbourCode, centerAdj)] → {Legal, Yields}` | общий для мест; `centerAdj` — центр рядом с клеткой, от него зависит законность Акведука (R9, R12 шаг 7) |
| `DirtySet` | `{plotIndex}` | по событиям R7; при пересчёте у места растёт `Version` |
| `Queue` | упорядоченная очередь работ (место + уровень: грубая оценка или раскладка) | приоритеты по FR-025: 1 — раскладка места под курсором, если её нет; 2 — места выделенного Поселенца, чья `Upper` больше `Lower` третьего (R21), по убыванию `Upper`; 3 — остальные места в радиусе 8 от выделенного Поселенца; 4 — места в радиусе 8 от других Поселенцев игрока; 5 — грубая оценка остальной открытой карты; 6 — раскладка остальных мест, по мере свободного времени. Равенства — по индексу клетки. Порядок влияет только на скорость, не на результат (R12, R21) |
| `PairCache` | `[(districtA, plotP, districtB, plotQ, centerAdj)] → gain` | парные надбавки по клеткам (R12, шаг 2); общий для мест |
