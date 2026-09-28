# Отчёт о реструктуризации entWatch

Базовый коммит документов: `2977470`; исходники плагина в нём совпадают с `e6d2630`.
После принятого шага 1.1 владелец разрешил продолжить без пауз на одобрение.
Проверки статические; компилятор и сервер не запускались. Версия и публичный API сохраняются.

## Шаг 1.1 — modules.sp

Перенесены четыре define и условные блоки HudInit, HALFZOMBIE HookEvent, AssistUseInit,
AdminMenuInit из entWatch.sp в entWatch/modules.sp, без изменения текста блоков.
Не перенос: комментарий над define, include modules.sp, новая void ModulesInit() и вызов
ModulesInit(); перед циклом игроков. Основание: шаг 1.1; cookie HUD и сентинелы редактора
инициализируются до цикла. Независимое чтение GPT-6 Sol: отклонений нет.

Команда: `python docs/restructure/tools/symbols.py --allow OnPluginStart --allow ModulesInit`.
Код выхода: 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Расхождения:
  func      ModulesInit                              добавлен или попал в эту сборку, во всех сборках  (разрешено)
  func      OnPluginStart                            изменён текст, во всех сборках  (разрешено)

ИТОГ: только перенос; незапланированных расхождений нет.
```

Наблюдения: дополнительных замечаний нет. git diff --check чист.
Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 2.1

Весь entWatch/restrict.sp перенесён побайтно в restrict/builtin.sp; restrict.sp содержит только include встроенной реализации.

Не перенос: Нет.

Наблюдения: Незапланированных изменений не обнаружено.

Проверка: `python docs/restructure/tools/symbols.py `; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  define DELETE_BAN                               entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define DELETE_BAN_ID                            entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define DELETE_BAN_ID_IP                         entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define DELETE_BAN_IP                            entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define INSERT_ADD_BAN                           entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define INSERT_BAN                               entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define MAX_TEMP_RESTRICTS                       entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define SELECT_BAN_ID                            entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define SELECT_BAN_ID_IP                         entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define SELECT_BAN_IP                            entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  define SELECT_SUMM_BANS                         entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   Command_AddBan                           entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   Command_Ban                              entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   Command_DeleteBan                        entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   Command_Status                           entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   Command_UnBan                            entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictAddBan                           entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictAddTempRestrict                  entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictCacheClientBan                   entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictClearCacheByBanKey               entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictClientBan                        entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictClientHasDatabaseRestrict        entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictClientHasRestrict                entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictClientInitTemp                   entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictClientTempBan                    entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictClientUnBan                      entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictDeleteBan                        entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictFindTempRestrict                 entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictFormatDeleteQuery                entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictFormatDuration                   entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictFormatLookupQuery                entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictGetExpireValue                   entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictHasTempRestrict                  entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictInit                             entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictIsValidDuration                  entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictIsValidIP                        entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictLoadClientSummBans               entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictOnClientDisconnect               entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictOnMapEnd                         entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictRemoveTempRestrict               entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   RestrictSendInfoToAdmins                 entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   SQL_Callback_AddBan                      entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   SQL_Callback_AddBanLookup                entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   SQL_Callback_BanClient                   entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   SQL_Callback_DeleteBanClient             entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   SQL_Callback_DeleteBanLookup             entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   SQL_Callback_SelectSummBans              entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  func   SQL_Callback_UnBan                       entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  global LastQueryEBanNotCompleted                entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  global Restricts                                entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  global TempRestricts                            entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  global TempRestricts_Count                      entWatch/restrict.sp -> entWatch/restrict/builtin.sp
  type   Restrict                                 entWatch/restrict.sp -> entWatch/restrict/builtin.sp

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 2.2

Из builtin.sp в builtin/temp.sp перенесены временные рестрикты и их данные, в builtin/utils.sp — проверки/форматирование, в builtin/commands.sp — пять команд. UTIL_* с комментарием // R1KO перенесены из helpers.sp в utils.sp. Общие Restrict, Restricts[] и LastQueryEBanNotCompleted подняты перед include; текст символов сохранён.

Не перенос: Нет.

Наблюдения: Незапланированных изменений не обнаружено.

Проверка: `python docs/restructure/tools/symbols.py `; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  func   UTIL_GetAccountIDFromSteamID             entWatch/helpers.sp -> entWatch/restrict/builtin/utils.sp
  func   UTIL_GetSteamIDFromAccountID             entWatch/helpers.sp -> entWatch/restrict/builtin/utils.sp
  func   Command_AddBan                           entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/commands.sp
  func   Command_Ban                              entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/commands.sp
  func   Command_DeleteBan                        entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/commands.sp
  func   Command_Status                           entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/commands.sp
  func   Command_UnBan                            entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/commands.sp
  define MAX_TEMP_RESTRICTS                       entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  func   RestrictAddTempRestrict                  entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  func   RestrictClientInitTemp                   entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  func   RestrictFindTempRestrict                 entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  func   RestrictHasTempRestrict                  entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  func   RestrictOnMapEnd                         entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  func   RestrictRemoveTempRestrict               entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  global TempRestricts                            entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  global TempRestricts_Count                      entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/temp.sp
  func   RestrictFormatDuration                   entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/utils.sp
  func   RestrictGetExpireValue                   entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/utils.sp
  func   RestrictIsValidDuration                  entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/utils.sp
  func   RestrictIsValidIP                        entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/utils.sp

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 2.3

Группы load, ban, unban, offline вместе с SQL define перенесены из builtin.sp в одноимённые файлы builtin/. В builtin.sp остались общие данные, include и четыре функции фасада/проверки.

Не перенос: Нет.

Наблюдения: По ревью добавлена пустая строка между группами из restrict.sp и helpers.sp в utils.sp, без правки символов. В 2.2 SQL define сдвинулись ниже вследствие разрешённого подъёма трёх globals и вставки include; их взаимный порядок был сохранён. Повторная проверка 2.3 после разделителя прошла.

Проверка: `python docs/restructure/tools/symbols.py `; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  define INSERT_BAN                               entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/ban.sp
  func   RestrictClientBan                        entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/ban.sp
  func   RestrictClientTempBan                    entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/ban.sp
  func   SQL_Callback_BanClient                   entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/ban.sp
  define SELECT_SUMM_BANS                         entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/load.sp
  func   RestrictCacheClientBan                   entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/load.sp
  func   RestrictLoadClientSummBans               entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/load.sp
  func   RestrictSendInfoToAdmins                 entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/load.sp
  func   SQL_Callback_SelectSummBans              entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/load.sp
  define DELETE_BAN_ID                            entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  define DELETE_BAN_ID_IP                         entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  define DELETE_BAN_IP                            entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  define INSERT_ADD_BAN                           entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  define SELECT_BAN_ID                            entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  define SELECT_BAN_ID_IP                         entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  define SELECT_BAN_IP                            entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  func   RestrictAddBan                           entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  func   RestrictDeleteBan                        entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  func   RestrictFormatDeleteQuery                entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  func   RestrictFormatLookupQuery                entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  func   SQL_Callback_AddBan                      entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  func   SQL_Callback_AddBanLookup                entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  func   SQL_Callback_DeleteBanClient             entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  func   SQL_Callback_DeleteBanLookup             entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/offline.sp
  define DELETE_BAN                               entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/unban.sp
  func   RestrictClearCacheByBanKey               entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/unban.sp
  func   RestrictClientUnBan                      entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/unban.sp
  func   SQL_Callback_UnBan                       entWatch/restrict/builtin.sp -> entWatch/restrict/builtin/unban.sp

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 2.4

SELECT_BANS и SQL_Callback_SelectBans перенесены из client.sp в builtin/load.sp.

Не перенос: Новая void RestrictOnClientAuth(int client) содержит прежнюю вторую половину ClientAuth побайтно, включая комментарии; в ClientAuth после чтения Account оставлен вызов RestrictOnClientAuth(client);. Основание: шаг 2.4.

Наблюдения: Незапланированных изменений не обнаружено.

Проверка: `python docs/restructure/tools/symbols.py --allow ClientAuth --allow RestrictOnClientAuth`; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  define SELECT_BANS                              entWatch/client.sp -> entWatch/restrict/builtin/load.sp
  func   SQL_Callback_SelectBans                  entWatch/client.sp -> entWatch/restrict/builtin/load.sp

Расхождения:
  func      ClientAuth                               изменён текст, во всех сборках  (разрешено)
  func      RestrictOnClientAuth                     добавлен или попал в эту сборку, во всех сборках  (разрешено)

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 2.5

database.sp целиком перенесён в restrict/builtin/database.sp; его include убран из медиатора и поставлен первым среди include builtin.sp.

Не перенос: Добавлена bool RestrictIsDatabaseLoaded() { return DBLoaded; }; Native_IsDatabaseLoaded возвращает RestrictIsDatabaseLoaded();. DatabaseConnect(); перенесён из OnPluginStart последней строкой RestrictInit. Основание: шаг 2.5; TransferInit/SpawnInit/StripperInit только регистрируют команды.

Наблюдения: Ревью уточнило обоснование отсрочки DB.Query по локальному форку css-swz/sourcemod 366cf73e. Fallback синхронного callback существует при выгрузке, но не в обычном OnPluginStart. inventory.md уточнён с путями и границами доказательства. Код SQL и callback не менялся.

Проверка: `python docs/restructure/tools/symbols.py --allow Native_IsDatabaseLoaded --allow RestrictIsDatabaseLoaded --allow OnPluginStart --allow RestrictInit`; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  define MYSQL_CHARSET                            entWatch/database.sp -> entWatch/restrict/builtin/database.sp
  func   ConnectCallBack                          entWatch/database.sp -> entWatch/restrict/builtin/database.sp
  func   DB_Query                                 entWatch/database.sp -> entWatch/restrict/builtin/database.sp
  func   DatabaseConnect                          entWatch/database.sp -> entWatch/restrict/builtin/database.sp
  func   SQL_Callback_CheckError                  entWatch/database.sp -> entWatch/restrict/builtin/database.sp
  func   SQL_Callback_CreateTables                entWatch/database.sp -> entWatch/restrict/builtin/database.sp
  global DB                                       entWatch/database.sp -> entWatch/restrict/builtin/database.sp
  global DBLoaded                                 entWatch/database.sp -> entWatch/restrict/builtin/database.sp
  global SQLite                                   entWatch/database.sp -> entWatch/restrict/builtin/database.sp

Расхождения:
  func      Native_IsDatabaseLoaded                  изменён текст, во всех сборках  (разрешено)
  func      OnPluginStart                            изменён текст, во всех сборках  (разрешено)
  func      RestrictInit                             изменён текст, во всех сборках  (разрешено)
  func      RestrictIsDatabaseLoaded                 добавлен или попал в эту сборку, во всех сборках  (разрешено)

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 2.6

Восемь функций BanMenu … BannedPlayerMenu_Handler перенесены из admin_menu.sp в builtin/menu.sp с прежним ADMIN_MENU-гейтом. include menu.sp добавлен последним в builtin.sp; текст функций и набор сборок сохранены.

Не перенос: Нет.

Наблюдения: Незапланированных изменений не обнаружено.

Проверка: `python docs/restructure/tools/symbols.py `; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  func   BanLengthMenu                            entWatch/admin_menu.sp -> entWatch/restrict/builtin/menu.sp
  func   BanLengthMenu_Handler                    entWatch/admin_menu.sp -> entWatch/restrict/builtin/menu.sp
  func   BanMenu                                  entWatch/admin_menu.sp -> entWatch/restrict/builtin/menu.sp
  func   BanMenu_Handler                          entWatch/admin_menu.sp -> entWatch/restrict/builtin/menu.sp
  func   BannedPlayerMenu                         entWatch/admin_menu.sp -> entWatch/restrict/builtin/menu.sp
  func   BannedPlayerMenu_Handler                 entWatch/admin_menu.sp -> entWatch/restrict/builtin/menu.sp
  func   BannedPlayersMenu                        entWatch/admin_menu.sp -> entWatch/restrict/builtin/menu.sp
  func   BannedPlayersMenu_Handler                entWatch/admin_menu.sp -> entWatch/restrict/builtin/menu.sp

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.
