# Офлайн-тесты

Тесты гоняют модули мода вне игры: карта и правила подменяются фейками (`tests/fake/`), правила
берутся из настоящей базы игры.

## Один раз: выгрузить правила игры

Таблиц базы игры (данные Firaxis) в репозитории нет — каждый выгружает их из своей установленной
игры в `tests/fixtures/gameinfo.lua` (файл в `.gitignore`):

1. Запусти Civilization VI с Gathering Storm и начни или загрузи любую партию — игра создаст кэш
   `DebugGameplay.sqlite`.
2. Выгрузи правила:

   ```bash
   python3 -I tools/export_gameinfo.py
   ```

   На Windows укажи путь к кэшу:

   ```bash
   python3 -I tools/export_gameinfo.py --db "%USERPROFILE%\Documents\My Games\Sid Meier's Civilization VI\Cache\DebugGameplay.sqlite"
   ```

## Запуск

Нужен Lua 5.1 (`tools/setup_lua.sh` ставит его в `.tools/lua51`):

```bash
.tools/lua51/bin/lua tests/run.lua           # все тесты
.tools/lua51/bin/lua tests/run.lua layout    # только файлы, в имени которых есть «layout»
```
