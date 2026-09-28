# План

Подготовка (этап 0) и пять этапов, в каждом — шаги. Шаг ≤ 5 изменений; после шага агент показывает дифф и
отчёт и **останавливается** до ответа владельца. После каждого шага плагин компилируется во
всех сочетаниях define'ов — поэтому шаги идут в таком порядке, что ни один из них не
оставляет сборку сломанной.

Куда какой символ переезжает — `target.md`. Здесь — порядок, разрешённые правки и проверка.

## Как выполнять шаг

1. Перенести символы как указано: вырезать блок целиком (с комментарием над ним и пустой
   строкой-разделителем) и вставить в новый файл в том же порядке, что в источнике.
   Стиль отступов переносимого кода не менять, даже если в новом файле он смешается.
2. Сделать правки, перечисленные в шаге как «не перенос». Больше никаких.
3. Запустить из корня репозитория:
   ```
   python docs/restructure/tools/symbols.py --allow <символы из шага>
   ```
   База — `HEAD` (по умолчанию): каждый принятый шаг закоммичен, поэтому шаг начинается с
   чистого дерева. Если на старте шага `git status` не пуст — стоп и вопрос владельцу.
   Скрипт должен закончиться строкой `ИТОГ: только перенос…` (код 0).
4. Прочитать дифф глазами (`git diff`, для новых файлов — сами файлы) и сверить с шагом.
5. Отчёт владельцу:
   - что перенесено (файл → файл, символы);
   - правки «не перенос» — дословно, с причиной из плана;
   - вывод скрипта целиком;
   - что замечено по дороге и **не** тронуто;
   - строка «Проверено: скрипт `symbols.py` и чтение. Не компилировалось».
6. **Стоп.** Ждать ответа владельца. Замечания — исправить в рамках шага и показать заново.
7. После «ок»: обновить таблицу «Состояние» в `README.md`, затем
   `git add -A -- addons/sourcemod/scripting docs/restructure` и коммит
   `refactor: <что сделано> (step N.M)` — Conventional Commits, на английском. Не пушить.
   Коммит без «ок» владельца не делается никогда.

Если что-то не сходится с планом (символа нет на месте, скрипт показывает незапланированное
расхождение, перенос требует правки, которой нет в плане), — не импровизировать: стоп и
вопрос владельцу.

## Этап 0. Черновик, ветка, документы

Удаление черновика владелец одобрил (2026-09-28). Оно необратимо, поэтому выполняется
**только** если состояние дерева в точности совпадает с ожидаемым.

### Шаг 0.1 — проверка состояния

`git branch --show-current` — `master`. `git status --porcelain` — ровно эти строки
(порядок не важен):

```
 M addons/sourcemod/scripting/entWatch.sp
 M addons/sourcemod/scripting/entWatch/admin_menu.sp
 M addons/sourcemod/scripting/entWatch/api.sp
 M addons/sourcemod/scripting/entWatch/client.sp
 M addons/sourcemod/scripting/entWatch/database.sp
 M addons/sourcemod/scripting/entWatch/restrict.sp
?? addons/sourcemod/scripting/entWatch/restrict/
?? docs/restructure/
```

Дополнительно: `git diff --stat` — 6 файлов, около 40 добавленных строк, все про
`DATABASE`; `entWatch/restrict/` содержит только `utils.sp`. Любое отличие (другая ветка,
лишний файл, другой объём правок) — **стоп**, показать владельцу `git status` и
`git diff --stat` и ждать.

### Шаг 0.2 — удаление черновика

```
git restore -- addons/sourcemod/scripting/entWatch.sp addons/sourcemod/scripting/entWatch/admin_menu.sp addons/sourcemod/scripting/entWatch/api.sp addons/sourcemod/scripting/entWatch/client.sp addons/sourcemod/scripting/entWatch/database.sp addons/sourcemod/scripting/entWatch/restrict.sp
git clean -fd -- addons/sourcemod/scripting/entWatch/restrict/
```

Никаких других `restore`/`clean`/`reset`: неотслеживаемая `docs/restructure/` должна
остаться на месте. После — `git status --porcelain` показывает только `?? docs/restructure/`.

### Шаг 0.3 — ветка и документы

```
git switch -c refactor/structure
git add docs/restructure
git commit -m "docs: add restructure plan and verification script"
```

Затем самопроверка скрипта: `python docs/restructure/tools/symbols.py` — ноль расхождений
(дерево совпадает с `HEAD`).

Отчёт владельцу: вывод `git status`, `git log --oneline -3`, итог скрипта. Стоп до «ок»,
затем — шаг 1.1. Таблицу «Состояние» обновить в коммите шага 1.1.

## Этап 1. `modules.sp`

### Шаг 1.1

- Создать `entWatch/modules.sp`. Перенести из `entWatch.sp` define'ы `HUD`, `ASSIST_USE`,
  `ADMIN_MENU`, `HALFZOMBIE`; над ними — комментарий в духе RestrictCore («закомментируйте,
  чтобы собрать без модуля»).
- `entWatch.sp`: `#include "entWatch/modules.sp"` — первым из include'ов модулей (до
  `database.sp`). `BOTOX_SM` остаётся в `entWatch.sp`.
- **Не перенос:** в `modules.sp` новая `void ModulesInit()`; в неё переезжают из
  `OnPluginStart()` блоки под `#if`: `HudInit()`, `HookEvent("player_spawn")` и
  `HookEvent("player_team")` (HALFZOMBIE), `AssistUseInit()`, `AdminMenuInit()` — в этом
  порядке, каждый со своим `#if`.
- **Не перенос:** в `OnPluginStart()` на месте бывшего `AssistUseInit()` (перед циклом
  `OnClientPutInServer`) — вызов `ModulesInit();`.

Перестановка безопасна (`inventory.md`, «Инициализация»): регистрации независимы, куки HUD и
сентинелы редактора по-прежнему ставятся до цикла по игрокам.

Проверка: `--allow OnPluginStart --allow ModulesInit`. Define'ы модулей скрипт не видит (он
перебирает их сам), их перенос сверить глазами.

## Этап 2. Рестрикты

### Шаг 2.1 — встроенная система в свой файл

- Весь текст `entWatch/restrict.sp` → `entWatch/restrict/builtin.sp` (побайтно).
- `entWatch/restrict.sp` теперь содержит только `#include "restrict/builtin.sp"`.

Проверка: без `--allow`; все символы должны оказаться в «Перенесены без изменений».

### Шаг 2.2 — временные рестрикты, утилиты, команды

- `builtin/temp.sp`, `builtin/utils.sp` (вместе с `UTIL_*` из `helpers.sp`),
  `builtin/commands.sp` — состав в `target.md`.
- `builtin.sp` подключает их после своих глобальных переменных (`Restrict`, `Restricts[]`,
  `LastQueryEBanNotCompleted`). Эти три объявления, если они сейчас стоят не в начале файла,
  поднимаются в начало — это перенос внутри файла, текст не меняется.

Проверка: без `--allow`.

### Шаг 2.3 — процессы

- `builtin/load.sp`, `builtin/ban.sp`, `builtin/unban.sp`, `builtin/offline.sp`; SQL-define'ы —
  вместе с функциями, которые выполняют запрос (`target.md`).
- В `builtin.sp` остаются глобальные переменные, include'ы, `RestrictInit`,
  `RestrictOnClientDisconnect`, `RestrictClientHasRestrict`, `RestrictClientHasDatabaseRestrict`.

Проверка: без `--allow`.

### Шаг 2.4 — загрузка рестрикта уходит из `client.sp`

- `SELECT_BANS` и `SQL_Callback_SelectBans` из `client.sp` → `builtin/load.sp`.
- **Не перенос:** новая `void RestrictOnClientAuth(int client)` в `builtin/load.sp`; её тело —
  часть `ClientAuth()` после строки с `GetSteamAccountID`, текст и комментарии без изменений.
- **Не перенос:** `ClientAuth()` — присвоение `Account`, затем `RestrictOnClientAuth(client);`.

Проверка: `--allow ClientAuth --allow RestrictOnClientAuth`. Скрипт на этом шаге подтвердит,
что `DBLoaded` и `DB_Query` не стали использоваться раньше объявления (`database.sp` ещё
подключается первым).

### Шаг 2.5 — база внутрь встроенной системы

- `entWatch/database.sp` → `restrict/builtin/database.sp` целиком. `entWatch.sp` больше его не
  подключает; `builtin.sp` подключает его первым из файлов папки.
- **Не перенос:** в `builtin/database.sp` новая
  `bool RestrictIsDatabaseLoaded() { return DBLoaded; }` (в стиле файла).
- **Не перенос:** `Native_IsDatabaseLoaded` (`api.sp`) возвращает `RestrictIsDatabaseLoaded()`.
- **Не перенос:** вызов `DatabaseConnect();` убирается из `OnPluginStart()` и ставится
  последней строкой `RestrictInit()`. Подключение сдвигается раньше `TransferInit`,
  `SpawnInit`, `StripperInit` — они только регистрируют команды, от базы не зависят и её не
  используют.

Проверка: `--allow Native_IsDatabaseLoaded --allow RestrictIsDatabaseLoaded --allow OnPluginStart --allow RestrictInit`.
Главное здесь — отсутствие «использования раньше объявления»: если что-то вне `builtin/`
ещё читает `DB`/`DBLoaded`, скрипт это покажет.

### Шаг 2.6 — меню рестриктов

- `BanMenu` … `BannedPlayerMenu_Handler` (8 функций) из `admin_menu.sp` →
  `builtin/menu.sp`. Файл начинается с
  ```sourcepawn
  #if !defined ADMIN_MENU
  	#endinput
  #endif
  ```
  — как `admin_menu.sp`, откуда функции пришли. `builtin.sp` подключает его последним.

Проверка: без `--allow`. Функции должны остаться в тех же сборках (только с `ADMIN_MENU`) —
скрипт сравнивает и это.

### Шаг 2.7 — выбор реализации

- **Не перенос:** `modules.sp` — `#define RESTRICT_BUILTIN` с комментарием (`target.md`).
- **Не перенос:** `restrict.sp` — шапка-комментарий с контрактом (таблица из `target.md`
  коротко: функция — кто зовёт — что обязана) и выбор
  `#if defined RESTRICT_BUILTIN` → `restrict/builtin.sp`, `#else` → `restrict/none.sp`.
- **Не перенос:** `restrict/none.sp` — шесть функций контракта с телами из `target.md`, у
  каждой короткий комментарий, почему так.
- **Не перенос:** `admin_menu.sp` — пункты `eban`/`vieweban` в `AdminMenu` и ветки
  `case 'e'`/`case 'v'` в `AdminMenu_Handler` под `#if defined RESTRICT_BUILTIN`, по образцу
  соседнего `#if defined ASSIST_USE`.

Проверка — два прогона:

1. `--fix RESTRICT_BUILTIN=1` без `--allow`: продакшн-сборки не изменились ни на символ.
   (Строки `#if`/`#endif` внутри функций скрипт в текст не включает, поэтому `AdminMenu`
   остаётся неизменной.)
2. `--fix RESTRICT_BUILTIN=0 --verbose`: ожидаемо «удалены» все символы встроенной системы и
   «изменён текст» у функций контракта (заглушки). Незапланированным здесь считается любое
   расхождение **вне** `restrict/`, кроме `AdminMenu` и `AdminMenu_Handler`: изменения
   этих двух функций прямо предусмотрены этим шагом (исчезают пункты и ветки рестриктов).
   Любая новая ошибка порядка объявления или строка в разделе «Используется символ,
   которого нет в этой сборке» недопустима. Код выхода 1 здесь ожидаем: скрипт не знает
   этот перечень запланированных удалений. Список расхождений сверить вручную и приложить
   к отчёту. Уточнено при выполнении 2026-09-28; алгоритм symbols.py не меняется.

После этапа 2 предложить владельцу проверить сборку с закомментированным `RESTRICT_BUILTIN`:
это единственный этап, который создаёт новое сочетание define'ов.

## Этап 3. Админ-меню

### Шаг 3.1

- `admin_menu/transfer.sp`, `admin_menu/use.sp`, `admin_menu/config_editor.sp` — состав
  в `target.md`. `admin_menu.sp` подключает их после своего `#endinput`-гейта.

Проверка: без `--allow`.

### Шаг 3.2 — запись конфига к конфигам

- `AdminConfigSave`, `AdminConfigBrowseItems` → `config/save.sp` с гейтом
  `#if !defined ADMIN_MENU` / `#endinput`. `config.sp` подключает `config/save.sp` после своих
  define'ов и глобальных переменных.

Проверка: без `--allow`.

## Этап 4. Конфиги, предметы, HUD

### Шаг 4.1 — конфиги

- `config/parse.sp` — чтение (`target.md`); `config.sp` подключает его рядом с `save.sp`.
- `RemoveConfig` из `helpers.sp` → `config.sp`.

Проверка: без `--allow`.

### Шаг 4.2 — предметы

- `items/register.sp` (+ `AreEntitiesRelated` из `helpers.sp`), `items/search.sp`,
  `items/state.sp`; `RemoveItemByConfig` из `helpers.sp` → `items.sp`.
- `items.sp` подключает папку после `Items[]`, `Items_Count`, `RoundStarted` и enum
  `REGISTER_*`.

Проверка: без `--allow`.

### Шаг 4.3 — строка HUD

- `ItemFormat` из `items.sp` → `hud.sp`.

Проверка: `--allow ItemFormat`. Ожидаемо: `ItemFormat` «выпал» из сборок без `HUD` — он
`stock` и там не вызывается. Других расхождений быть не должно.

## Этап 5. Медиатор

### Шаг 5.1

- `OnClientCookiesCached` и `OnClientSayCommand` из `client.sp` → `entWatch.sp` без
  изменений.
- **Не перенос:** `OnClientPutInServer` переезжает в `entWatch.sp` в форме из `target.md`;
  в `client.sp` — новая `ClientsOnClientPutInServer(client)`: `GetClientAuthId`, три
  `SDKHook`, `ClientAuth` в прежнем порядке.
- **Не перенос:** `OnClientDisconnect` переезжает в `entWatch.sp`; в `client.sp` — новая
  `ClientsOnClientDisconnect(client)` с `Clients[client].Clear();`. Порядок: HUD, assist_use,
  `ClientsOnClientDisconnect`, `RestrictOnClientDisconnect` — как был.

Проверка: `--allow OnClientPutInServer --allow OnClientDisconnect --allow ClientsOnClientPutInServer --allow ClientsOnClientDisconnect`.

### Шаг 5.2 — документация

- **Не перенос:** `CLAUDE.md` проекта — таблица «Subsystems», абзац «One plugin, many
  files» (порядок include'ов, `modules.sp`, контракт рестриктов), упоминание `database.sp`
  в разделе «Database». Язык и стиль `CLAUDE.md` сохранить (он на английском).
- `README.md` этой папки — все этапы «сделано».

Версию в `myinfo` агент не меняет: поведение не менялось, решение о версии — за владельцем.

## Риски, которые не снимает скрипт

- **Предупреждения компилятора в новых сочетаниях.** Без `RESTRICT_BUILTIN` не вызываются
  `APIOnDatabaseLoaded` (`api.sp`) и `ClientGetUserId` (`client.sp`) — обе не `stock`.
  Выдаёт ли `spcomp` на них «symbol is never used», в этом процессе не проверено: исходников
  компилятора в `dependencies/` нет. Если выдаёт — решение за владельцем (`stock`, `#if` или
  принять).
- **Пути include'ов.** Поиск `"..."` относительно каталога текущего файла подтверждён только
  примером RestrictCore, который компилируется. Если сборка не найдёт файл — первым делом
  проверить путь.
- **Порядок инициализации** — единственное место, где рефакторинг меняет порядок вызовов
  (шаги 1.1, 2.5, 5.1). Обоснования в плане опираются на чтение кода, а не на запуск.
