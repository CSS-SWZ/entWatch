# Целевая раскладка

Принцип — как в RestrictCore: у модуля файл `X.sp` и, если модуль большой, папка `X/`,
в ней по файлу на процесс. Файл модуля сначала объявляет глобальные переменные и define'ы,
которыми пользуются файлы папки, потом подключает их, потом определяет свои функции.
Раскладка по фичам, не по слоям: меню рестриктов лежит в рестриктах, а не в «меню».

## Дерево

```
scripting/
  entWatch.sp                 медиатор: myinfo, все форварды SourceMod, BOTOX_SM, bool Late
  entWatch/
    modules.sp                define'ы модулей + ModulesInit()
    colors.sp
    config.sp                 Configs[], константы, жизненный цикл, поиск, RemoveConfig
    config/
      parse.sp                чтение карты: ConfigParse … ConfigBrowseKeyUNLOZE
      save.sp                 запись карты: AdminConfigSave, AdminConfigBrowseItems [ADMIN_MENU]
    items.sp                  Items[], жизненный цикл, ItemRemove/Init/Clear/Unhook, RemoveItemByConfig
    items/
      register.sp             привязка сущностей по Hammer ID, поиск кнопки, AreEntitiesRelated
      search.sp               ItemsGetBy*, ItemGetRef, ItemFindClientItem
      state.sp                владение и готовность: ItemReleaseOwner, ItemDrop, ItemIsReady, ItemReload
    client.sp                 Clients[], ClientAuth, ClientsOnClientPutInServer/Disconnect, поиск
    chat.sp
    assist_use.sp
    halfzombie.sp
    sdkhook.sp
    dump.sp
    hud.sp                    + ItemFormat (строка HUD)
    restrict.sp               контракт подсистемы + выбор реализации
    restrict/
      none.sp                 без рестриктов (заглушки)
      builtin.sp              встроенная система: общие данные, include'ы, функции фасада
      builtin/
        database.sp           соединение, схема ebans, DB_Query, RestrictIsDatabaseLoaded
        temp.sp               временные рестрикты (до смены карты)
        load.sp               загрузка при авторизации: RestrictOnClientAuth, SELECT_BANS, сводка
        ban.sp                выдача: онлайн и временная
        unban.sp              снятие
        offline.sp            sm_addeban / sm_deleban
        commands.sp           обработчики команд
        menu.sp               меню рестриктов [ADMIN_MENU]
        utils.sp              проверки и форматирование, UTIL_* SteamID
      core.sp                 ← интеграция с RestrictCore, пишет владелец (не в этом процессе)
    transfer.sp
    helpers.sp                общие утилиты: StringToLowercase
    admin_menu.sp             корень меню, Reload, AddMenuItem2
    admin_menu/
      transfer.sp             меню передачи
      use.sp                  принудительное использование [ASSIST_USE]
      config_editor.sp        редактор конфигов
    spawn.sp
    api.sp
    stripper.sp
```

`database.sp` в корне исчезает — он переезжает в `restrict/builtin/database.sp`.

## `modules.sp`

По образцу `RestrictCore/modules.sp`: define'ы с комментарием «закомментируйте, чтобы собрать
без …» и функция инициализации модулей.

```sourcepawn
// Закомментируйте define, чтобы собрать плагин без модуля.
#define HUD
#define ASSIST_USE
#define ADMIN_MENU
#define HALFZOMBIE

// Встроенная система рестриктов: своя база ebans и временные рестрикты.
// Без define'а рестриктов нет (restrict/none.sp).
#define RESTRICT_BUILTIN

void ModulesInit()
{
	#if defined HUD
	HudInit();
	#endif
	…
}
```

- `BOTOX_SM` остаётся в `entWatch.sp`: это выбор платформы (форк SourceMod), а не модуль.
- `modules.sp` подключается первым: define'ы должны быть видны всем файлам ниже.
- В `ModulesInit()` уходят вызовы из `OnPluginStart()`, стоящие под `#if` модуля:
  `HudInit()`, `HookEvent("player_spawn"/"player_team")` для HALFZOMBIE, `AssistUseInit()`,
  `AdminMenuInit()`. Порядок внутри — как был в `OnPluginStart()`. Вызов `ModulesInit()` — на
  месте бывшего `AssistUseInit()`, то есть перед циклом `OnClientPutInServer`. Почему это
  безопасно — `inventory.md`, «Инициализация».
- Жизненный цикл модулей в других форвардах (`OnMapStart`, `OnRoundStart` и т. д.) остаётся
  в `entWatch.sp` под `#if` — медиатор, как и сейчас.
- Вызов `RestrictInit()` остаётся в `OnPluginStart()` без `#if`: фасад рестриктов есть во всех
  сборках.
- Define для RestrictCore владелец добавит сам, агент его не пишет.

## Подсистема рестриктов

### Контракт

Шапка `restrict.sp` перечисляет функции, которые обязана определить **каждая** реализация.
Остальной плагин вызывает только их — и ничего больше из рестриктов не видит.

| Функция | Кто вызывает | Что обязана делать |
|---|---|---|
| `void RestrictInit()` | `OnPluginStart()` | регистрация команд, подключение к хранилищу |
| `void RestrictOnClientAuth(int client)` | `ClientAuth()` | в итоге выставить `Clients[client].Authorized = true`; когда загрузка состоялась — `APIOnClientLoaded(client)` |
| `void RestrictOnClientDisconnect(int client)` | `OnClientDisconnect` | сбросить состояние слота |
| `void RestrictOnMapEnd()` | `OnMapEnd()` | то, что живёт до смены карты |
| `bool RestrictClientHasRestrict(int client)` | `sdkhook.sp`, `assist_use.sp`, `transfer.sp`, меню | горячий путь (`SDKHook_Touch` каждый тик): без запросов и проходов по спискам |
| `bool RestrictIsDatabaseLoaded()` | `Native_IsDatabaseLoaded` | значение натива `entWatch_IsDatabaseLoaded` |

Выбор реализации — только здесь:

```sourcepawn
#if defined RESTRICT_BUILTIN
	#include "restrict/builtin.sp"
#else
	#include "restrict/none.sp"
#endif
```

Владелец потом добавит ветку `#elseif defined <define RestrictCore>` с `restrict/core.sp` —
и больше нигде ничего не поменяет, кроме пунктов админ-меню (см. ниже).

Путь include'а: SourcePawn ищет `"..."` сначала относительно каталога текущего файла
(так устроены include'ы папок в RestrictCore: `database.sp` подключает `"database/utils.sp"`).
Значит, `restrict.sp` пишет `"restrict/builtin.sp"`, а `builtin.sp` — `"builtin/load.sp"`.

### `restrict/none.sp` — сборка без рестриктов

Повторяет то, что делает встроенная система, когда база недоступна (fail-open), — новой
семантики не придумывает:

| Функция | Тело |
|---|---|
| `RestrictInit` | пусто: команд `sm_status`/`sm_eban`/… нет |
| `RestrictOnClientAuth` | `Clients[client].Authorized = true;` — форвард `entWatch_OnClientLoaded` не шлётся, как во встроенной системе при `!DBLoaded` |
| `RestrictOnClientDisconnect`, `RestrictOnMapEnd` | пусто |
| `RestrictClientHasRestrict` | `return false;` |
| `RestrictIsDatabaseLoaded` | `return false;` — натив регистрируется и отвечает «базы нет»; `entWatch_OnDatabaseLoaded` не шлётся никогда |

Пункты `eban`/`vieweban` админ-меню в этой сборке не рисуются.

### `restrict/builtin.sp` и `builtin/`

Куда уходит каждый символ. Источник — `restrict.sp`, если не указано иное.

| Файл | Символы |
|---|---|
| `builtin.sp` | `enum struct Restrict`, `Restricts[]`, `LastQueryEBanNotCompleted` (общая блокировка всех запросов на запись); include'ы папки; `RestrictInit` (+ вызов `DatabaseConnect()`, перенесённый из `OnPluginStart`), `RestrictOnClientDisconnect`, `RestrictClientHasRestrict`, `RestrictClientHasDatabaseRestrict` |
| `builtin/database.sp` | весь `database.sp`: `MYSQL_CHARSET`, `DBLoaded`, `DB`, `SQLite`, `DB_Query`, `DatabaseConnect`, `ConnectCallBack`, `SQL_Callback_CreateTables`, `SQL_Callback_CheckError`; **новая** `RestrictIsDatabaseLoaded()` |
| `builtin/temp.sp` | `MAX_TEMP_RESTRICTS`, `TempRestricts[]`, `TempRestricts_Count`, `RestrictClientInitTemp`, `RestrictOnMapEnd`, `RestrictFindTempRestrict`, `RestrictHasTempRestrict`, `RestrictAddTempRestrict`, `RestrictRemoveTempRestrict` |
| `builtin/load.sp` | из `client.sp`: `SELECT_BANS`, `SQL_Callback_SelectBans`; **новая** `RestrictOnClientAuth()`; `SELECT_SUMM_BANS`, `RestrictCacheClientBan`, `RestrictLoadClientSummBans`, `SQL_Callback_SelectSummBans`, `RestrictSendInfoToAdmins` |
| `builtin/ban.sp` | `INSERT_BAN`, `RestrictClientBan`, `RestrictClientTempBan`, `SQL_Callback_BanClient` |
| `builtin/unban.sp` | `DELETE_BAN`, `RestrictClientUnBan`, `SQL_Callback_UnBan`, `RestrictClearCacheByBanKey` |
| `builtin/offline.sp` | `INSERT_ADD_BAN`, `SELECT_BAN_ID_IP`, `SELECT_BAN_ID`, `SELECT_BAN_IP`, `DELETE_BAN_ID_IP`, `DELETE_BAN_ID`, `DELETE_BAN_IP`, `RestrictFormatLookupQuery`, `RestrictFormatDeleteQuery`, `RestrictAddBan`, `SQL_Callback_AddBanLookup`, `SQL_Callback_AddBan`, `RestrictDeleteBan`, `SQL_Callback_DeleteBanLookup`, `SQL_Callback_DeleteBanClient` |
| `builtin/commands.sp` | `Command_Status`, `Command_Ban`, `Command_UnBan`, `Command_AddBan`, `Command_DeleteBan` (регистрация остаётся в `RestrictInit`) |
| `builtin/menu.sp` | из `admin_menu.sp`: `BanMenu`, `BanMenu_Handler`, `BanLengthMenu`, `BanLengthMenu_Handler`, `BannedPlayersMenu`, `BannedPlayersMenu_Handler`, `BannedPlayerMenu`, `BannedPlayerMenu_Handler`. Файл начинается с `#if !defined ADMIN_MENU / #endinput / #endif` — эти функции и сейчас собираются только с `ADMIN_MENU` |
| `builtin/utils.sp` | `RestrictIsValidDuration`, `RestrictGetExpireValue`, `RestrictFormatDuration`, `RestrictIsValidIP`; из `helpers.sp`: `UTIL_GetAccountIDFromSteamID`, `UTIL_GetSteamIDFromAccountID` (с комментарием `// R1KO` над ними) |

Порядок include'ов внутри `builtin.sp`: `database` → `utils` → `temp` → `load` → `ban` →
`unban` → `offline` → `commands` → `menu`. Первыми идут файлы с глобальными переменными
(`database`, `temp`); скрипт проверки подтвердит, что ничего не используется до объявления.

`RestrictOnClientAuth()` — это вторая половина нынешнего `ClientAuth()`, начиная с вызова
`RestrictClientInitTemp(client)`, вместе с комментариями, текст без изменений. `ClientAuth()`
после правки:

```sourcepawn
void ClientAuth(int client)
{
    Clients[client].Account = GetSteamAccountID(client);

    RestrictOnClientAuth(client);
}
```

`SQL_Callback_CreateTables()` по-прежнему зовёт `ClientAuth(i)`: повторное чтение аккаунта —
текущее поведение, его не меняем.

`ClientGetByAccount` и `ClientGetUserId` остаются в `client.sp`: это поиск по игрокам, хотя
вызывают их только рестрикты.

### Админ-меню и рестрикты

Корень меню (`AdminMenu`, `AdminMenu_Handler`) оставляет пункты `eban`/`vieweban` и ветки
`case 'e'`/`case 'v'` у себя, но под `#if defined RESTRICT_BUILTIN` — так же, как сейчас
пункт `use` стоит под `#if defined ASSIST_USE`. Функций-хуков вида «рестрикты, добавьте свои
пункты» не вводим: для одного потребителя это лишний интерфейс.

## Админ-меню

| Файл | Символы (источник — `admin_menu.sp`) |
|---|---|
| `admin_menu.sp` | `#if !defined ADMIN_MENU` / `#endinput`, include'ы папки, `AdminMenuInit`, `Command_Admin`, `AdminMenu`, `AdminMenu_Handler`, `AddMenuItem2` |
| `admin_menu/transfer.sp` | `TransferMenu`, `TransferMenu_Handler`, `TransferByMapMenu`, `TransferByMapMenu_Handler`, `TransferByTargetMenu`, `TransferByTargetMenu_Handler` |
| `admin_menu/use.sp` | блок `#if defined ASSIST_USE` … `#endif` целиком: `UseItemsMenu`, `UseItemMenu_Handler` |
| `admin_menu/config_editor.sp` | `EditClientConfig`, `EditClientsConfigs[]`, `AdminConfigEditorInit`, `AdminConfigEditorGet`, `ConfigsMenu`, `ConfigsMenu_Handler`, `ConfigMenu`, `ConfigMenu_Handler`, `AdminOnClientPutInServer`, `AdminOnClientSayCommand` |
| `config/save.sp` | `AdminConfigSave`, `AdminConfigBrowseItems` — под `#if defined ADMIN_MENU`, как сейчас |

Файлы `admin_menu/` подключаются из `admin_menu.sp` после его `#endinput`, поэтому сами
гейт `ADMIN_MENU` не повторяют. `use.sp` сохраняет свой `#if defined ASSIST_USE`.

Имена `AdminConfigSave`/`AdminConfigBrowseItems` не меняются, хотя теперь живут в `config/`:
переименование — не в этом процессе.

## Конфиги, предметы, HUD

| Файл | Символы |
|---|---|
| `config.sp` | define'ы `MAX_CONFIGS`, `DISPLAY_*`, `SLOT_*`, `MODE_*`, `*_DEFAULT`, `CONFIG_TYPE_*`; `Configs_Count`, `Configs[]`; include'ы папки; `ConfigOnMapStart`, `ConfigOnMapEnd`, `ConfigClearAll`, `ConfigGetBy*`, `ConfigInit`, `ConfigClear`, `ConfigGetDisplay`; из `helpers.sp`: `RemoveConfig` |
| `config/parse.sp` | `ConfigParse`, `ConfigLoad`, `ConfigBrowse`, `ConfigBrowseKey`, `ConfigGetType`, `ConfigBrowseKeyGFL`, `ConfigBrowseKeyUNLOZE` |
| `config/save.sp` | см. «Админ-меню» |
| `items.sp` | `MAX_ITEMS`, enum `REGISTER_*`, `Items_Count`, `Items[]`, `RoundStarted`; include'ы папки; `ItemsOnMapStart`, `ItemsOnRoundStart`, `ItemsOnRoundEnd`, `ItemsOnPluginEnd`, `ItemsClear`, `ItemsOnEntityDestroyed`, `ItemRemove`, `ItemInit`, `ItemClear`, `ItemUnhook`; из `helpers.sp`: `RemoveItemByConfig` |
| `items/register.sp` | `ItemsOnEntitySpawned`, `ItemsRegisterGetKeyValues`, `ItemsRegisterItemEntity`, `ItemsInitiateItem`, `ItemProcessCheckButton`, `Timer_ItemFindButton`, `ItemsGetButtonByPriority`; из `helpers.sp`: `AreEntitiesRelated` |
| `items/search.sp` | `ItemsGetByName`, `ItemsGetByShortName`, `ItemsGetByWeaponHammerID`, `ItemsGetByWeapon`, `ItemGetRef`, `ItemsGetByRef`, `ItemsGetByButton`, `ItemsGetByCompare`, `ItemsGetByRelay`, `ItemFindClientItem` |
| `items/state.sp` | `ItemReleaseOwner`, `ItemDrop`, `ItemIsReady`, `ItemReload` |
| `hud.sp` | из `items.sp`: `ItemFormat` (`stock`; попадает под `#endinput` без `HUD` — там он и так не используется) |
| `helpers.sp` | `StringToLowercase` |

`config.sp` и `items.sp` подключают свои папки после своих глобальных переменных и define'ов.

## Медиатор и клиент

Четыре форварда клиента переезжают из `client.sp` в `entWatch.sp`; логика клиента остаётся
в `client.sp` в функциях жизненного цикла модуля. Порядок вызовов — прежний.

```sourcepawn
// entWatch.sp
public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client))
        return;

    #if defined ADMIN_MENU
    AdminOnClientPutInServer(client);
    #endif

    #if defined HUD
    HudOnClientPutInServer(client);
    #endif

    ClientsOnClientPutInServer(client);
}
```

- `ClientsOnClientPutInServer(client)` (`client.sp`) — `GetClientAuthId`, три `SDKHook`,
  `ClientAuth(client)` в прежнем порядке. `HudOnClientPutInServer` переставляется раньше
  `GetClientAuthId` — безопасно, см. `inventory.md`, «Инициализация».
- `OnClientDisconnect`: HUD, assist_use, `ClientsOnClientDisconnect(client)`
  (= `Clients[client].Clear();`), `RestrictOnClientDisconnect(client)` — порядок прежний.
- `OnClientCookiesCached` и `OnClientSayCommand` переезжают без изменений.
- Цикл `OnClientPutInServer(i)` в `OnPluginStart()` не меняется.

## Порядок include'ов после всех этапов

```
entWatch.sp
  modules.sp
  colors.sp
  config.sp        → config/parse.sp, config/save.sp
  items.sp         → items/register.sp, items/search.sp, items/state.sp
  client.sp
  chat.sp
  assist_use.sp
  halfzombie.sp
  sdkhook.sp
  dump.sp
  hud.sp
  restrict.sp      → restrict/builtin.sp → builtin/*.sp   |  restrict/none.sp
  transfer.sp
  helpers.sp
  admin_menu.sp    → admin_menu/transfer.sp, use.sp, config_editor.sp
  spawn.sp
  api.sp
  stripper.sp
```

`database.sp` больше не первый: после этапа 2 глобальные переменные базы читает только
код внутри `restrict/builtin/`.
