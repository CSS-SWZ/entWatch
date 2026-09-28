# Текущее состояние кода

Снимок закоммиченного `master` (`e6d2630`, версия `1.1.1`), без незакоммиченного черновика
с `DATABASE`. Таблица зависимостей в конце сгенерирована разбором `tools/symbols.py` по всем
сочетаниям define'ов. После первых же переносов она устареет — ориентируйтесь по именам
символов, а не по файлам.

## Порядок include'ов и почему он такой

```
entWatch.sp: define'ы модулей (HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE), bool Late
  database.sp     ← первым: client.sp читает глобальную DBLoaded
  colors.sp
  config.sp       ← Configs[], MODE_*/SLOT_*/DISPLAY_* нужны всем ниже
  items.sp        ← Items[], RoundStarted
  client.sp       ← Clients[]
  chat.sp
  assist_use.sp   (#endinput без ASSIST_USE)
  halfzombie.sp   (#endinput без HALFZOMBIE; #tryinclude <zombiereloaded>)
  sdkhook.sp
  dump.sp
  hud.sp          (#endinput без HUD)
  restrict.sp
  transfer.sp
  helpers.sp
  admin_menu.sp   (#endinput без ADMIN_MENU)
  spawn.sp
  api.sp
  stripper.sp
```

Ограничение одно: глобальная переменная, define, тип или константа enum должны быть объявлены
раньше первого использования. Функции можно вызывать из любого места. Нарушений на `HEAD`
нет (проверено скриптом).

## Где смешаны обязанности

### Рестрикты размазаны по шести файлам

| Файл | Что в нём от рестриктов | Где должно быть |
|---|---|---|
| `database.sp` | соединение, схема `ebans`, `DB`/`DBLoaded`/`SQLite`, `DB_Query`, `SQL_Callback_CreateTables` (он же переавторизует игроков и шлёт `entWatch_OnDatabaseLoaded`) | во встроенной системе рестриктов: база, кроме неё, никому не нужна |
| `client.sp` | `SELECT_BANS`, вторая половина `ClientAuth()` (временный рестрикт, гейт по `DBLoaded`, запрос), `SQL_Callback_SelectBans` | в рестриктах; `ClientAuth()` вызывает одну функцию фасада |
| `admin_menu.sp` | пункты `eban`/`vieweban`, 8 функций меню (`BanMenu` … `BannedPlayerMenu_Handler`), прямое чтение `Restricts[].Admin/Duration/Expires/Temporary` | в рестриктах; `Restricts[]` снаружи никто не читает |
| `api.sp` | `Native_IsDatabaseLoaded` читает `DBLoaded` | через функцию фасада |
| `helpers.sp` | `UTIL_GetAccountIDFromSteamID` (нужна только `sm_addeban`/`sm_deleban`), `UTIL_GetSteamIDFromAccountID` (не используется, `stock`) | в рестриктах |
| `entWatch.sp` | `RestrictInit()`, `DatabaseConnect()`, `RestrictOnMapEnd()` | вызовы фасада |

Сам `restrict.sp` (1059 строк) — это команды, загрузка, выдача, снятие, офлайн-выдача и
офлайн-снятие, временные рестрикты и утилиты в одном файле; SQL всех процессов — define'ами
в шапке.

Внутри `restrict.sp` важно: глобальная `LastQueryEBanNotCompleted` — **одна** блокировка на
выдачу, снятие, `sm_addeban` и `sm_deleban` (её читают и пишут 11 функций). При разнесении по
файлам она остаётся общей и объявляется раньше всех них.

Нормальные потребители, их трогать не нужно: `RestrictClientHasRestrict()` из `sdkhook.sp`
(горячий путь, `SDKHook_Touch`), `assist_use.sp`, `transfer.sp` и меню передачи.

### Админ-меню — пять подсистем в одном файле (1235 строк)

- корень меню и `Reload` (`Command_Admin`, `AdminMenu`, `AdminMenu_Handler`), `AddMenuItem2`;
- меню рестриктов — 8 функций (см. выше);
- меню передачи — `TransferMenu` … `TransferByTargetMenu_Handler`, 6 функций;
- принудительное использование — `UseItemsMenu`, `UseItemMenu_Handler` (под `ASSIST_USE`);
- редактор конфигов — `EditClientConfig`, `EditClientsConfigs[]`, `AdminConfigEditorInit/Get`,
  `ConfigsMenu`, `ConfigMenu` и обработчики, `AdminOnClientPutInServer`,
  `AdminOnClientSayCommand`;
- **запись конфига карты** — `AdminConfigSave`, `AdminConfigBrowseItems`. Это формат конфига,
  а не меню: по `CLAUDE.md` новый ключ правится в `ConfigBrowseKeyGFL`, `ConfigBrowseKeyUNLOZE`
  (`config.sp`) и `AdminConfigBrowseItems` (здесь).

### Конфиги и предметы

- `helpers.sp` — склад разного: `RemoveConfig` (конфиги), `RemoveItemByConfig` и
  `AreEntitiesRelated` (предметы), `UTIL_*` (рестрикты), `StringToLowercase` (общее).
- `items.sp` (705 строк) — массив и жизненный цикл, привязка сущностей по Hammer ID с таймером
  поиска кнопки, поиск предметов, владение и готовность **и строка HUD** (`ItemFormat`,
  единственный вызывающий — `hud.sp`).
- `config.sp` — чтение обоих форматов вместе с хранилищем и поиском; запись — в `admin_menu.sp`.

### Медиатор

По `CLAUDE.md` все форварды SourceMod объявляет `entWatch.sp`. На деле четыре форварда
клиента — `OnClientPutInServer`, `OnClientDisconnect`, `OnClientCookiesCached`,
`OnClientSayCommand` — объявлены в `client.sp` и сами раздают вызовы модулям (HUD, assist_use,
admin_menu, рестрикты).

### Что не смешано и остаётся

`chat.sp`, `colors.sp`, `hud.sp`, `assist_use.sp`, `transfer.sp`, `spawn.sp`, `stripper.sp`,
`dump.sp`, `halfzombie.sp`, `api.sp`, `sdkhook.sp`.

Замечено, но сознательно не трогается (это не структура, а поведение или вкус):

- `HalfZombie[]` читают напрямую `sdkhook.sp` и `transfer.sp` под `#if defined HALFZOMBIE`.
  Форма связи та же, что у рестриктов, но мест три и гейт единый — фасад добавил бы больше
  кода, чем убрал.
- Проверка «игрок может держать предмет» (`Authorized`, рестрикт, half-zombie) повторена
  в `OnWeaponTouch`, `OnButtonPress`, `OnTriggerTouch`, передаче и меню — **с разными наборами
  условий**. Объединение изменило бы поведение; это вопрос аудита, не рефакторинга.
- `sdkhook.sp` назван по механизму, а не по смыслу (защита предметов). Переименование — только
  если владелец попросит.

## Инициализация: что от чего зависит

`OnPluginStart()` на `HEAD`, по порядку:

```
LoadTranslations ×2
HudInit()            [HUD]        RegClientCookie + sm_hud
RestrictInit()                    Reg*Cmd ×5
TransferInit()                    RegAdminCmd
SpawnInit()                       RegAdminCmd
StripperInit()                    RegServerCmd ×3
DatabaseConnect()                 MySQL — асинхронно; SQLite — SQLite_UseDatabase синхронно,
                                  CREATE TABLE — потоковый запрос, колбэк на следующих кадрах
DumpInit()                        RegAdminCmd
ColorsInit()                      colors.cfg, SetFailState без него
HookEvent player_spawn/team  [HALFZOMBIE]
HookEvent death/disconnect/round_start/round_end, mp_restartgame
AssistUseInit()      [ASSIST_USE] Reg*Cmd, HookEntityOutput ×4
AdminMenuInit()      [ADMIN_MENU] sm_eadmin, сентинелы редактора конфигов
цикл OnClientPutInServer по игрокам в игре
```

Для перестановок важно (проверено чтением кода на `HEAD`):

- регистрации команд, куки и хуков событий друг от друга не зависят;
- куки HUD должна быть зарегистрирована до цикла `OnClientPutInServer` (он читает её через
  `HudOnClientPutInServer`); сентинелы редактора тоже ставятся до цикла;
- `DatabaseConnect()` не зависит от команд, `ColorsInit()` и событий. Колбэк создания таблиц
  приходит после завершения `OnPluginStart()`: `Database.Query` потоковый, результат
  доставляется в основной поток позже. Это поведение SourceMod по памяти, по исходникам
  в этом процессе не перепроверялось;
- `HudClientReadCookie()` не читает ничего из того, что выставляют `GetClientAuthId`,
  `SDKHook` и `ClientAuth()` в `OnClientPutInServer`.

## Межфайловые зависимости

Для каждого файла — символы, которые используются в других файлах, и кто именно их использует.
Символы, которые используются только внутри своего файла, не показаны.

### `entWatch.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `Late` | global | `admin_menu.sp`: AdminMenu_Handler; `items.sp`: ItemsOnMapStart, ItemsRegisterItemEntity |
| `OnPluginEnd` | func | `admin_menu.sp`: AdminMenu_Handler |
| `OnMapStart` | func | `admin_menu.sp`: AdminMenu_Handler |
| `OnRoundEnd` | func | `admin_menu.sp`: AdminMenu_Handler |

### `entWatch/admin_menu.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `AdminMenuInit` | func | `entWatch.sp`: OnPluginStart |
| `AdminOnClientPutInServer` | func | `client.sp`: OnClientPutInServer |
| `AdminOnClientSayCommand` | func | `client.sp`: OnClientSayCommand |

### `entWatch/api.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `APIInit` | func | `entWatch.sp`: AskPluginLoad2 |
| `APIOnConfigLoaded` | func | `config.sp`: ConfigParse |
| `APIOnDatabaseLoaded` | func | `database.sp`: SQL_Callback_CreateTables |
| `APIOnClientLoaded` | func | `client.sp`: SQL_Callback_SelectBans |
| `APIOnClientItemUse` | func | `sdkhook.sp`: Compare_OnEqualTo, OnButtonPress, Relay_OnTrigger |
| `APIOnClientItemDrop` | func | `items.sp`: ItemReleaseOwner; `sdkhook.sp`: OnWeaponDrop |
| `APIOnClientItemPickup` | func | `sdkhook.sp`: OnWeaponPickup |

### `entWatch/assist_use.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `AssistUseInit` | func | `entWatch.sp`: OnPluginStart |
| `AssistUseAdmin` | func | `admin_menu.sp`: UseItemMenu_Handler |
| `AssistUseConfigLoad` | func | `config.sp`: ConfigLoad |
| `AssistUseOnPlayerRunCmdPost` | func | `entWatch.sp`: OnPlayerRunCmdPost |
| `AssistUseOnClientDisconnect` | func | `client.sp`: OnClientDisconnect |

### `entWatch/chat.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `ACTION_PICK` | enum | `sdkhook.sp`: OnWeaponPickup |
| `ACTION_DROP` | enum | `sdkhook.sp`: OnWeaponDrop |
| `ACTION_USE` | enum | `sdkhook.sp`: Compare_OnEqualTo, OnButtonPress, Relay_OnTrigger |
| `ACTION_DEATH` | enum | `entWatch.sp`: OnPlayerDeath |
| `ACTION_DISCONNECT` | enum | `entWatch.sp`: OnPlayerDisconnect |
| `PrintToChatItemAction` | func | `client.sp`: ClientLostHandleAction; `sdkhook.sp`: Compare_OnEqualTo, OnButtonPress, OnWeaponDrop, OnWeaponPickup, Relay_OnTrigger |
| `PrintToTeam` | func | `assist_use.sp`: AssistUseAdmin |
| `PrintToChat2` | func | `admin_menu.sp`: BanLengthMenu_Handler, BanMenu_Handler, BannedPlayerMenu_Handler, BannedPlayersMenu_Handler, ConfigsMenu_Handler, TransferByMapMenu_Handler, TransferByTargetMenu_Handler, TransferMenu_Handler, UseItemMenu_Handler; `assist_use.sp`: Command_AssistUse; `hud.sp`: HudToggleClientHud; `restrict.sp`: Command_Status, RestrictAddBan, RestrictClientBan, RestrictClientTempBan, RestrictClientUnBan, RestrictDeleteBan, RestrictSendInfoToAdmins, SQL_Callback_AddBan, SQL_Callback_AddBanLookup, SQL_Callback_BanClient, SQL_Callback_DeleteBanClient, SQL_Callback_DeleteBanLookup, SQL_Callback_UnBan |
| `PrintToChatAll2` | func | `restrict.sp`: RestrictClientTempBan, RestrictClientUnBan, SQL_Callback_BanClient, SQL_Callback_UnBan; `spawn.sp`: SpawnItem; `transfer.sp`: TransferItem |

### `entWatch/client.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `Clients` | global | `admin_menu.sp`: BanMenu, BannedPlayerMenu, BannedPlayersMenu, TransferByTargetMenu, TransferMenu, UseItemsMenu; `api.sp`: Native_IsClientLoaded; `chat.sp`: PrintToChatItemAction; `restrict.sp`: Command_Status, RestrictAddBan, RestrictClearCacheByBanKey, RestrictClientBan, RestrictClientInitTemp, RestrictClientTempBan, RestrictClientUnBan, RestrictLoadClientSummBans; `sdkhook.sp`: OnWeaponTouch; `transfer.sp`: Command_Transfer, TransferItem |
| `OnClientPutInServer` | func | `entWatch.sp`: OnPluginStart |
| `ClientAuth` | func | `database.sp`: SQL_Callback_CreateTables |
| `ClientLostHandleAction` | func | `entWatch.sp`: OnPlayerDeath, OnPlayerDisconnect |
| `ClientGetByAccount` | func | `restrict.sp`: SQL_Callback_AddBan, SQL_Callback_DeleteBanClient |
| `ClientGetUserId` | func | `restrict.sp`: RestrictAddBan, RestrictClientBan, RestrictClientUnBan, RestrictDeleteBan |

### `entWatch/colors.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `COLOR_TAG` | enum | `chat.sp`: SendMessage |
| `COLOR_NAME` | enum | `assist_use.sp`: AssistUseAdmin; `chat.sp`: PrintToChatItemAction; `spawn.sp`: SpawnItem; `transfer.sp`: TransferItem |
| `COLOR_OTHER` | enum | `admin_menu.sp`: BannedPlayerMenu_Handler, BannedPlayersMenu_Handler, ConfigsMenu_Handler, TransferByMapMenu_Handler, TransferMenu_Handler, UseItemMenu_Handler; `assist_use.sp`: AssistUseAdmin; `chat.sp`: PrintToChatItemAction, SendMessage; `spawn.sp`: SpawnItem; `transfer.sp`: TransferItem |
| `COLOR_ITEM` | enum | `config.sp`: ConfigBrowseKeyGFL, ConfigBrowseKeyUNLOZE, ConfigClear |
| `Colors` | global | `admin_menu.sp`: BannedPlayerMenu_Handler, BannedPlayersMenu_Handler, ConfigsMenu_Handler, TransferByMapMenu_Handler, TransferMenu_Handler, UseItemMenu_Handler; `assist_use.sp`: AssistUseAdmin; `chat.sp`: PrintToChatItemAction, SendMessage; `config.sp`: ConfigBrowseKeyGFL, ConfigBrowseKeyUNLOZE, ConfigClear; `spawn.sp`: SpawnItem; `transfer.sp`: TransferItem |
| `ColorsInit` | func | `entWatch.sp`: OnPluginStart |
| `ColorNameToColorCode` | func | `config.sp`: ConfigBrowseKeyGFL |

### `entWatch/config.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `MAX_CONFIGS` | define | `admin_menu.sp`: ConfigsMenu_Handler |
| `DISPLAY_CHAT` | define | `admin_menu.sp`: AdminConfigBrowseItems, AdminOnClientSayCommand; `chat.sp`: PrintToChatItemAction; `transfer.sp`: TransferItem |
| `DISPLAY_USE` | define | `admin_menu.sp`: AdminConfigBrowseItems, AdminOnClientSayCommand; `assist_use.sp`: AssistUseAdmin; `chat.sp`: PrintToChatItemAction |
| `DISPLAY_HUD` | define | `admin_menu.sp`: AdminConfigBrowseItems, AdminOnClientSayCommand; `hud.sp`: Timer_Hud |
| `SLOT_NONE` | define | `admin_menu.sp`: AdminOnClientSayCommand; `items.sp`: ItemDrop; `transfer.sp`: TransferIsValidItem |
| `SLOT_PRIMARY` | define | `admin_menu.sp`: AdminConfigBrowseItems |
| `SLOT_SECONDARY` | define | `admin_menu.sp`: AdminConfigBrowseItems |
| `SLOT_KNIFE` | define | `items.sp`: ItemDrop; `transfer.sp`: TransferIsValidItem |
| `SLOT_GRENADES` | define | `admin_menu.sp`: AdminOnClientSayCommand |
| `MODE_PROTECT` | define | `admin_menu.sp`: AdminOnClientSayCommand; `items.sp`: ItemIsReady |
| `MODE_COOLDOWN` | define | `items.sp`: ItemFormat, ItemIsReady, ItemReload |
| `MODE_MAXUSES` | define | `items.sp`: ItemFormat, ItemIsReady, ItemReload |
| `MODE_MAXUSESCD` | define | `items.sp`: ItemFormat, ItemIsReady, ItemReload |
| `MODE_CHARGESCD` | define | `admin_menu.sp`: AdminOnClientSayCommand; `items.sp`: ItemFormat, ItemIsReady, ItemReload |
| `SLOT_DEFAULT` | define | `admin_menu.sp`: AdminOnClientSayCommand |
| `CONFIG_TYPE_GFL` | define | `admin_menu.sp`: AdminConfigBrowseItems |
| `CONFIG_TYPE_UNLOZE` | define | `admin_menu.sp`: AdminConfigBrowseItems, ConfigsMenu_Handler |
| `Configs_Count` | global | `admin_menu.sp`: AdminConfigBrowseItems, ConfigsMenu, ConfigsMenu_Handler; `api.sp`: Native_GetConfig, Native_GetConfigsCount, Native_IsConfigLoaded; `dump.sp`: Command_Dump; `helpers.sp`: RemoveConfig; `hud.sp`: HudCreateTimer; `items.sp`: ItemsRegisterGetKeyValues |
| `Configs` | global | `admin_menu.sp`: AdminConfigBrowseItems, AdminOnClientSayCommand, ConfigMenu, ConfigsMenu, TransferByMapMenu, TransferByTargetMenu, UseItemsMenu; `api.sp`: Native_GetConfig; `assist_use.sp`: AssistUseAdmin; `chat.sp`: PrintToChatItemAction; `dump.sp`: Command_Dump; `helpers.sp`: RemoveConfig; `items.sp`: ItemDrop, ItemFormat, ItemIsReady, ItemReload, ItemsGetByName, ItemsGetByShortName, ItemsGetByWeaponHammerID, ItemsRegisterGetKeyValues, Timer_ItemFindButton; `sdkhook.sp`: OnButtonPress; `spawn.sp`: SpawnItem; `stripper.sp`: Command_SetCooldown, Command_SetMaxuses; `transfer.sp`: TransferIsValidItem, TransferItem |
| `ConfigOnMapStart` | func | `entWatch.sp`: OnMapStart |
| `ConfigOnMapEnd` | func | `entWatch.sp`: OnMapEnd |
| `ConfigGetByWeaponHammerId` | func | `stripper.sp`: Command_SetCooldown, Command_SetMaxuses |
| `ConfigGetByShortName` | func | `spawn.sp`: Command_Spawn |
| `ConfigInit` | func | `admin_menu.sp`: ConfigsMenu_Handler |
| `ConfigGetDisplay` | func | `admin_menu.sp`: AdminConfigBrowseItems; `assist_use.sp`: AssistUseAdmin; `chat.sp`: PrintToChatItemAction; `hud.sp`: Timer_Hud; `transfer.sp`: TransferItem |

### `entWatch/database.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `DBLoaded` | global | `api.sp`: Native_IsDatabaseLoaded; `client.sp`: ClientAuth; `restrict.sp`: RestrictAddBan, RestrictClientHasDatabaseRestrict, RestrictDeleteBan |
| `DB` | global | `restrict.sp`: RestrictAddBan, RestrictClientBan, RestrictClientUnBan, RestrictDeleteBan, RestrictFormatDeleteQuery, RestrictFormatLookupQuery, SQL_Callback_AddBanLookup, SQL_Callback_DeleteBanLookup |
| `DB_Query` | func | `client.sp`: ClientAuth; `restrict.sp`: RestrictClientBan, RestrictClientUnBan, RestrictLoadClientSummBans, SQL_Callback_AddBanLookup |
| `DatabaseConnect` | func | `entWatch.sp`: OnPluginStart |

### `entWatch/dump.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `DumpInit` | func | `entWatch.sp`: OnPluginStart |

### `entWatch/halfzombie.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `HalfZombie` | global | `sdkhook.sp`: OnButtonPress, OnTriggerTouch, OnWeaponTouch; `transfer.sp`: TransferIsValidReceiver |
| `HalfZombieInit` | func | `entWatch.sp`: OnMapStart, OnRoundStart |
| `HalfZombieClientInit` | func | `entWatch.sp`: OnPlayerSpawn, OnPlayerTeam |
| `HalfZombieDeterminate` | func | `entWatch.sp`: OnConfigsExecuted |

### `entWatch/helpers.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `UTIL_GetAccountIDFromSteamID` | func | `restrict.sp`: RestrictAddBan, RestrictDeleteBan |
| `RemoveConfig` | func | `admin_menu.sp`: ConfigMenu_Handler |
| `AreEntitiesRelated` | func | `items.sp`: ItemsRegisterItemEntity |
| `StringToLowercase` | func | `admin_menu.sp`: AdminConfigSave; `config.sp`: ConfigOnMapStart |

### `entWatch/hud.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `HudInit` | func | `entWatch.sp`: OnPluginStart |
| `HudConfigLoad` | func | `config.sp`: ConfigLoad |
| `HudOnMapStart` | func | `entWatch.sp`: OnMapStart |
| `HudOnMapEnd` | func | `entWatch.sp`: OnMapEnd |
| `HudOnClientPutInServer` | func | `client.sp`: OnClientPutInServer |
| `HudOnClientCookiesCached` | func | `client.sp`: OnClientCookiesCached |
| `HudOnClientDisconnect` | func | `client.sp`: OnClientDisconnect |

### `entWatch/items.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `Items_Count` | global | `admin_menu.sp`: TransferByMapMenu; `api.sp`: Native_GetItem, Native_GetItemsCount; `dump.sp`: Command_Dump; `helpers.sp`: RemoveItemByConfig; `hud.sp`: Timer_Hud; `transfer.sp`: TransferDropAllTransferedItems |
| `Items` | global | `admin_menu.sp`: TransferByMapMenu, TransferByMapMenu_Handler, TransferByTargetMenu, TransferByTargetMenu_Handler, UseItemMenu_Handler, UseItemsMenu; `api.sp`: Native_GetItem; `assist_use.sp`: AssistUse, AssistUseAdmin, AssistUseFindClientItem, AssistUseGetClientItemsCount, AssistUseInputByName; `chat.sp`: PrintToChatItemAction; `dump.sp`: Command_Dump; `helpers.sp`: RemoveItemByConfig; `hud.sp`: Timer_Hud; `sdkhook.sp`: Compare_OnEqualTo, OnButtonPress, OnWeaponDrop, OnWeaponPickup, Relay_OnTrigger; `stripper.sp`: Command_DecUses; `transfer.sp`: TransferDropAllTransferedItems, TransferIsValidItem, TransferItem |
| `RoundStarted` | global | `admin_menu.sp`: AdminMenu_Handler; `assist_use.sp`: AssistUseOnPlayerRunCmdPost; `sdkhook.sp`: Compare_OnEqualTo, OnButtonPress, OnTriggerTouch, Relay_OnTrigger |
| `ItemsOnMapStart` | func | `entWatch.sp`: OnMapStart |
| `ItemsOnRoundStart` | func | `entWatch.sp`: OnRoundStart |
| `ItemsOnRoundEnd` | func | `entWatch.sp`: OnRoundEnd |
| `ItemsOnPluginEnd` | func | `entWatch.sp`: OnPluginEnd |
| `ItemsOnEntitySpawned` | func | `entWatch.sp`: OnEntitySpawned, SDKHook_OnEntitySpawnPost |
| `ItemsOnEntityDestroyed` | func | `entWatch.sp`: OnEntityDestroyed |
| `ItemsGetByShortName` | func | `assist_use.sp`: Command_Use; `transfer.sp`: Command_Transfer |
| `ItemsGetByWeaponHammerID` | func | `stripper.sp`: Command_DecUses |
| `ItemsGetByWeapon` | func | `sdkhook.sp`: OnWeaponDrop, OnWeaponPickup, OnWeaponTouch |
| `ItemGetRef` | func | `admin_menu.sp`: TransferByMapMenu, TransferByTargetMenu, UseItemsMenu |
| `ItemsGetByRef` | func | `admin_menu.sp`: TransferByMapMenu_Handler, TransferByTargetMenu_Handler, UseItemMenu_Handler |
| `ItemsGetByButton` | func | `assist_use.sp`: AssistUseIsValidTarget; `sdkhook.sp`: OnButtonPress |
| `ItemsGetByCompare` | func | `sdkhook.sp`: Compare_OnEqualTo |
| `ItemsGetByRelay` | func | `sdkhook.sp`: Relay_OnTrigger |
| `ItemFindClientItem` | func | `admin_menu.sp`: TransferByTargetMenu, UseItemsMenu; `api.sp`: Native_ClientHasItem; `assist_use.sp`: AssistUseFindClientItem, AssistUseGetClientItemsCount, Command_Use; `client.sp`: ClientLostHandleAction; `transfer.sp`: Command_Transfer |
| `ItemReleaseOwner` | func | `client.sp`: ClientLostHandleAction |
| `ItemDrop` | func | `client.sp`: ClientLostHandleAction; `transfer.sp`: TransferDropAllTransferedItems, TransferItem |
| `ItemIsReady` | func | `assist_use.sp`: AssistUseAdmin; `sdkhook.sp`: OnButtonPress |
| `ItemReload` | func | `sdkhook.sp`: Compare_OnEqualTo, OnButtonPress, Relay_OnTrigger |
| `ItemFormat` | func | `hud.sp`: Timer_Hud |
| `ItemRemove` | func | `helpers.sp`: RemoveItemByConfig |
| `ItemClear` | func | `helpers.sp`: RemoveItemByConfig |
| `ItemUnhook` | func | `helpers.sp`: RemoveItemByConfig |

### `entWatch/restrict.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `Restricts` | global | `admin_menu.sp`: BannedPlayerMenu |
| `RestrictInit` | func | `entWatch.sp`: OnPluginStart |
| `RestrictCacheClientBan` | func | `client.sp`: SQL_Callback_SelectBans |
| `RestrictLoadClientSummBans` | func | `client.sp`: SQL_Callback_SelectBans |
| `RestrictOnClientDisconnect` | func | `client.sp`: OnClientDisconnect |
| `RestrictClientBan` | func | `admin_menu.sp`: BanLengthMenu_Handler |
| `RestrictClientTempBan` | func | `admin_menu.sp`: BanLengthMenu_Handler |
| `RestrictClientUnBan` | func | `admin_menu.sp`: BannedPlayerMenu_Handler |
| `RestrictClientHasRestrict` | func | `admin_menu.sp`: BanLengthMenu_Handler, BanMenu, BanMenu_Handler, BannedPlayerMenu_Handler, BannedPlayersMenu, BannedPlayersMenu_Handler, TransferByMapMenu_Handler, TransferByTargetMenu_Handler, TransferMenu, TransferMenu_Handler; `assist_use.sp`: AssistUseOnPlayerRunCmdPost; `sdkhook.sp`: OnButtonPress, OnTriggerTouch, OnWeaponTouch; `transfer.sp`: Command_Transfer, TransferIsValidReceiver |
| `RestrictClientInitTemp` | func | `client.sp`: ClientAuth |
| `RestrictOnMapEnd` | func | `entWatch.sp`: OnMapEnd |

### `entWatch/sdkhook.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `OnWeaponTouch` | func | `client.sp`: OnClientPutInServer |
| `OnWeaponPickup` | func | `client.sp`: OnClientPutInServer |
| `OnWeaponDrop` | func | `client.sp`: OnClientPutInServer |
| `OnButtonPress` | func | `items.sp`: ItemUnhook, ItemsOnEntityDestroyed, ItemsRegisterItemEntity |
| `Compare_OnEqualTo` | func | `items.sp`: ItemUnhook, ItemsRegisterItemEntity |
| `Relay_OnTrigger` | func | `items.sp`: ItemUnhook, ItemsRegisterItemEntity |
| `OnTriggerTouch` | func | `items.sp`: ItemUnhook, ItemsRegisterItemEntity |

### `entWatch/spawn.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `SpawnInit` | func | `entWatch.sp`: OnPluginStart |
| `SpawnItem` | func | `admin_menu.sp`: ConfigMenu_Handler |

### `entWatch/stripper.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `StripperInit` | func | `entWatch.sp`: OnPluginStart |

### `entWatch/transfer.sp`

| Символ | Вид | Кто использует снаружи |
|---|---|---|
| `TransferInit` | func | `entWatch.sp`: OnPluginStart |
| `TransferIsValidItem` | func | `admin_menu.sp`: TransferByMapMenu, TransferByTargetMenu |
| `TransferItem` | func | `admin_menu.sp`: TransferByMapMenu_Handler, TransferByTargetMenu_Handler |
| `TransferOnRoundEnd` | func | `entWatch.sp`: OnRoundEnd |
| `TransferOnPluginEnd` | func | `entWatch.sp`: OnPluginEnd |
