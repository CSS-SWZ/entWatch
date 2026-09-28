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

## Шаг 2.7

Введён выбор встроенной реализации или отсутствия рестриктов; builtin остаётся включён по умолчанию.

Не перенос: RESTRICT_BUILTIN с комментарием в modules.sp; контракт и #if выбора в restrict.sp; шесть функций none.sp по target.md; #if RESTRICT_BUILTIN вокруг eban/vieweban и case e/v. В новой RestrictIsDatabaseLoaded добавлен пустой разделитель перед функцией, без правки её текста.

Наблюдения: ON: 64 сочетания, exit 0 без allow. OFF: 64 сочетания, ожидаемый exit 1 с 78 различиями; вручную и по объявлениям сверены ровно 70 исключённых builtin-символов, шесть функций контракта и две функции AdminMenu/Handler. Ошибок порядка и отсутствующих символов нет. Уточнено противоречие plan.md: две функции меню вне restrict/ меняются по прямому требованию шага. symbols.py не изменялся. Требуется пользовательская компиляция с включённым и выключенным RESTRICT_BUILTIN; предупреждения компилятора не проверены.

Проверка: `python docs/restructure/tools/symbols.py --fix RESTRICT_BUILTIN=1`; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 64 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included; зафиксировано RESTRICT_BUILTIN=1)

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверка: `python docs/restructure/tools/symbols.py --fix RESTRICT_BUILTIN=0 --verbose`; код 1.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 64 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included; зафиксировано RESTRICT_BUILTIN=0)

Расхождения:
  func      AdminMenu                                изменён текст, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      AdminMenu_Handler                        изменён текст, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      BanLengthMenu                            удалён или выпал из этой сборки, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      BanLengthMenu_Handler                    удалён или выпал из этой сборки, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      BanMenu                                  удалён или выпал из этой сборки, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      BanMenu_Handler                          удалён или выпал из этой сборки, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      BannedPlayerMenu                         удалён или выпал из этой сборки, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      BannedPlayerMenu_Handler                 удалён или выпал из этой сборки, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      BannedPlayersMenu                        удалён или выпал из этой сборки, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      BannedPlayersMenu_Handler                удалён или выпал из этой сборки, в 32 из 64 сборок
            {ADMIN_MENU}
            {ADMIN_MENU, _zr_included}
            {ADMIN_MENU, HALFZOMBIE}
            {ADMIN_MENU, HALFZOMBIE, _zr_included}
            {ASSIST_USE, ADMIN_MENU}
            {ASSIST_USE, ADMIN_MENU, _zr_included}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE}
            {ASSIST_USE, ADMIN_MENU, HALFZOMBIE, _zr_included}
            … ещё 24
  func      Command_AddBan                           удалён или выпал из этой сборки, во всех сборках
  func      Command_Ban                              удалён или выпал из этой сборки, во всех сборках
  func      Command_DeleteBan                        удалён или выпал из этой сборки, во всех сборках
  func      Command_Status                           удалён или выпал из этой сборки, во всех сборках
  func      Command_UnBan                            удалён или выпал из этой сборки, во всех сборках
  func      ConnectCallBack                          удалён или выпал из этой сборки, во всех сборках
  global    DB                                       удалён или выпал из этой сборки, во всех сборках
  global    DBLoaded                                 удалён или выпал из этой сборки, во всех сборках
  func      DB_Query                                 удалён или выпал из этой сборки, во всех сборках
  define    DELETE_BAN                               удалён или выпал из этой сборки, во всех сборках
  define    DELETE_BAN_ID                            удалён или выпал из этой сборки, во всех сборках
  define    DELETE_BAN_ID_IP                         удалён или выпал из этой сборки, во всех сборках
  define    DELETE_BAN_IP                            удалён или выпал из этой сборки, во всех сборках
  func      DatabaseConnect                          удалён или выпал из этой сборки, во всех сборках
  define    INSERT_ADD_BAN                           удалён или выпал из этой сборки, во всех сборках
  define    INSERT_BAN                               удалён или выпал из этой сборки, во всех сборках
  global    LastQueryEBanNotCompleted                удалён или выпал из этой сборки, во всех сборках
  define    MAX_TEMP_RESTRICTS                       удалён или выпал из этой сборки, во всех сборках
  define    MYSQL_CHARSET                            удалён или выпал из этой сборки, во всех сборках
  type      Restrict                                 удалён или выпал из этой сборки, во всех сборках
  func      RestrictAddBan                           удалён или выпал из этой сборки, во всех сборках
  func      RestrictAddTempRestrict                  удалён или выпал из этой сборки, во всех сборках
  func      RestrictCacheClientBan                   удалён или выпал из этой сборки, во всех сборках
  func      RestrictClearCacheByBanKey               удалён или выпал из этой сборки, во всех сборках
  func      RestrictClientBan                        удалён или выпал из этой сборки, во всех сборках
  func      RestrictClientHasDatabaseRestrict        удалён или выпал из этой сборки, во всех сборках
  func      RestrictClientHasRestrict                изменён текст, во всех сборках
  func      RestrictClientInitTemp                   удалён или выпал из этой сборки, во всех сборках
  func      RestrictClientTempBan                    удалён или выпал из этой сборки, во всех сборках
  func      RestrictClientUnBan                      удалён или выпал из этой сборки, во всех сборках
  func      RestrictDeleteBan                        удалён или выпал из этой сборки, во всех сборках
  func      RestrictFindTempRestrict                 удалён или выпал из этой сборки, во всех сборках
  func      RestrictFormatDeleteQuery                удалён или выпал из этой сборки, во всех сборках
  func      RestrictFormatDuration                   удалён или выпал из этой сборки, во всех сборках
  func      RestrictFormatLookupQuery                удалён или выпал из этой сборки, во всех сборках
  func      RestrictGetExpireValue                   удалён или выпал из этой сборки, во всех сборках
  func      RestrictHasTempRestrict                  удалён или выпал из этой сборки, во всех сборках
  func      RestrictInit                             изменён текст, во всех сборках
  func      RestrictIsDatabaseLoaded                 изменён текст, во всех сборках
  func      RestrictIsValidDuration                  удалён или выпал из этой сборки, во всех сборках
  func      RestrictIsValidIP                        удалён или выпал из этой сборки, во всех сборках
  func      RestrictLoadClientSummBans               удалён или выпал из этой сборки, во всех сборках
  func      RestrictOnClientAuth                     изменён текст, во всех сборках
  func      RestrictOnClientDisconnect               изменён текст, во всех сборках
  func      RestrictOnMapEnd                         изменён текст, во всех сборках
  func      RestrictRemoveTempRestrict               удалён или выпал из этой сборки, во всех сборках
  func      RestrictSendInfoToAdmins                 удалён или выпал из этой сборки, во всех сборках
  global    Restricts                                удалён или выпал из этой сборки, во всех сборках
  define    SELECT_BANS                              удалён или выпал из этой сборки, во всех сборках
  define    SELECT_BAN_ID                            удалён или выпал из этой сборки, во всех сборках
  define    SELECT_BAN_ID_IP                         удалён или выпал из этой сборки, во всех сборках
  define    SELECT_BAN_IP                            удалён или выпал из этой сборки, во всех сборках
  define    SELECT_SUMM_BANS                         удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_AddBan                      удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_AddBanLookup                удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_BanClient                   удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_CheckError                  удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_CreateTables                удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_DeleteBanClient             удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_DeleteBanLookup             удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_SelectBans                  удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_SelectSummBans              удалён или выпал из этой сборки, во всех сборках
  func      SQL_Callback_UnBan                       удалён или выпал из этой сборки, во всех сборках
  global    SQLite                                   удалён или выпал из этой сборки, во всех сборках
  global    TempRestricts                            удалён или выпал из этой сборки, во всех сборках
  global    TempRestricts_Count                      удалён или выпал из этой сборки, во всех сборках
  func      UTIL_GetAccountIDFromSteamID             удалён или выпал из этой сборки, во всех сборках
  func      UTIL_GetSteamIDFromAccountID             удалён или выпал из этой сборки, во всех сборках

ИТОГ: 78 незапланированных расхождений.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 3.1

Из admin_menu.sp перенесены шесть меню передачи в admin_menu/transfer.sp, целый блок #if ASSIST_USE с двумя меню использования в admin_menu/use.sp, enum struct EditClientConfig, массив и функции редактора в admin_menu/config_editor.sp. Include после ADMIN_MENU-гейта; тексты и сочетания define сохранены.

Не перенос: Нет.

Наблюдения: Незапланированных изменений не обнаружено.

Проверка: `python docs/restructure/tools/symbols.py `; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  func   AdminConfigEditorGet                     entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  func   AdminConfigEditorInit                    entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  func   AdminOnClientPutInServer                 entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  func   AdminOnClientSayCommand                  entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  func   ConfigMenu                               entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  func   ConfigMenu_Handler                       entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  func   ConfigsMenu                              entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  func   ConfigsMenu_Handler                      entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  global EditClientsConfigs                       entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  type   EditClientConfig                         entWatch/admin_menu.sp -> entWatch/admin_menu/config_editor.sp
  func   TransferByMapMenu                        entWatch/admin_menu.sp -> entWatch/admin_menu/transfer.sp
  func   TransferByMapMenu_Handler                entWatch/admin_menu.sp -> entWatch/admin_menu/transfer.sp
  func   TransferByTargetMenu                     entWatch/admin_menu.sp -> entWatch/admin_menu/transfer.sp
  func   TransferByTargetMenu_Handler             entWatch/admin_menu.sp -> entWatch/admin_menu/transfer.sp
  func   TransferMenu                             entWatch/admin_menu.sp -> entWatch/admin_menu/transfer.sp
  func   TransferMenu_Handler                     entWatch/admin_menu.sp -> entWatch/admin_menu/transfer.sp
  func   UseItemMenu_Handler                      entWatch/admin_menu.sp -> entWatch/admin_menu/use.sp
  func   UseItemsMenu                             entWatch/admin_menu.sp -> entWatch/admin_menu/use.sp

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 3.2

AdminConfigSave и AdminConfigBrowseItems перенесены из admin_menu.sp в config/save.sp с ADMIN_MENU-гейтом. config.sp подключает save.sp после своих define и глобальных данных; имена функций и формат записи конфигов сохранены.

Не перенос: Нет.

Наблюдения: Незапланированных изменений не обнаружено.

Проверка: `python docs/restructure/tools/symbols.py `; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  func   AdminConfigBrowseItems                   entWatch/admin_menu.sp -> entWatch/config/save.sp
  func   AdminConfigSave                          entWatch/admin_menu.sp -> entWatch/config/save.sp

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 4.1

Семь функций чтения форматов карты перенесены из config.sp в config/parse.sp; RemoveConfig перенесена из helpers.sp в config.sp. Include parse/save стоят после констант и Configs[]. Тексты символов сохранены.

Не перенос: Нет.

Наблюдения: Незапланированных изменений не обнаружено.

Проверка: `python docs/restructure/tools/symbols.py `; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  func   ConfigBrowse                             entWatch/config.sp -> entWatch/config/parse.sp
  func   ConfigBrowseKey                          entWatch/config.sp -> entWatch/config/parse.sp
  func   ConfigBrowseKeyGFL                       entWatch/config.sp -> entWatch/config/parse.sp
  func   ConfigBrowseKeyUNLOZE                    entWatch/config.sp -> entWatch/config/parse.sp
  func   ConfigGetType                            entWatch/config.sp -> entWatch/config/parse.sp
  func   ConfigLoad                               entWatch/config.sp -> entWatch/config/parse.sp
  func   ConfigParse                              entWatch/config.sp -> entWatch/config/parse.sp
  func   RemoveConfig                             entWatch/helpers.sp -> entWatch/config.sp

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 4.2

Из items.sp перенесены привязка сущностей в items/register.sp, поиск в items/search.sp, владение и готовность в items/state.sp. AreEntitiesRelated перенесена из helpers.sp в register.sp, RemoveItemByConfig — в items.sp. Include стоят после всех общих данных, включая REGISTER_* и RoundStarted. Текст символов сохранён.

Не перенос: Нет.

Наблюдения: Незапланированных изменений не обнаружено.

Проверка: `python docs/restructure/tools/symbols.py `; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  func   RemoveItemByConfig                       entWatch/helpers.sp -> entWatch/items.sp
  func   AreEntitiesRelated                       entWatch/helpers.sp -> entWatch/items/register.sp
  func   ItemProcessCheckButton                   entWatch/items.sp -> entWatch/items/register.sp
  func   ItemsGetButtonByPriority                 entWatch/items.sp -> entWatch/items/register.sp
  func   ItemsInitiateItem                        entWatch/items.sp -> entWatch/items/register.sp
  func   ItemsOnEntitySpawned                     entWatch/items.sp -> entWatch/items/register.sp
  func   ItemsRegisterGetKeyValues                entWatch/items.sp -> entWatch/items/register.sp
  func   ItemsRegisterItemEntity                  entWatch/items.sp -> entWatch/items/register.sp
  func   Timer_ItemFindButton                     entWatch/items.sp -> entWatch/items/register.sp
  func   ItemFindClientItem                       entWatch/items.sp -> entWatch/items/search.sp
  func   ItemGetRef                               entWatch/items.sp -> entWatch/items/search.sp
  func   ItemsGetByButton                         entWatch/items.sp -> entWatch/items/search.sp
  func   ItemsGetByCompare                        entWatch/items.sp -> entWatch/items/search.sp
  func   ItemsGetByName                           entWatch/items.sp -> entWatch/items/search.sp
  func   ItemsGetByRef                            entWatch/items.sp -> entWatch/items/search.sp
  func   ItemsGetByRelay                          entWatch/items.sp -> entWatch/items/search.sp
  func   ItemsGetByShortName                      entWatch/items.sp -> entWatch/items/search.sp
  func   ItemsGetByWeapon                         entWatch/items.sp -> entWatch/items/search.sp
  func   ItemsGetByWeaponHammerID                 entWatch/items.sp -> entWatch/items/search.sp
  func   ItemDrop                                 entWatch/items.sp -> entWatch/items/state.sp
  func   ItemIsReady                              entWatch/items.sp -> entWatch/items/state.sp
  func   ItemReleaseOwner                         entWatch/items.sp -> entWatch/items/state.sp
  func   ItemReload                               entWatch/items.sp -> entWatch/items/state.sp

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 4.3

Stock-функция ItemFormat перенесена побайтно из items.sp в hud.sp под существующий HUD-гейт.

Не перенос: Нет.

Наблюдения: Ожидаемо ItemFormat исключена из 64 сочетаний без HUD, где не вызывается. По независимому ревью завершён перенос комментария про приоритет кнопки к ItemsGetButtonByPriority: в исходнике комментарий отделялся пустой строкой и скрипт не связывал его с функцией. Исправление переноса 4.2 записано здесь без переписывания истории; текст комментария сохранён. Повторная проверка после исправления прошла.

Проверка: `python docs/restructure/tools/symbols.py --allow ItemFormat`; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  func   ItemFormat                               entWatch/items.sp -> entWatch/hud.sp

Расхождения:
  func      ItemFormat                               удалён или выпал из этой сборки, в 64 из 128 сборок  (разрешено)

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.

## Шаг 5.1

OnClientPutInServer, OnClientDisconnect, OnClientCookiesCached и OnClientSayCommand перенесены из client.sp в entWatch.sp.

Не перенос: Новые ClientsOnClientPutInServer(int client) с GetClientAuthId, тремя SDKHook и ClientAuth, и ClientsOnClientDisconnect(int client) с Clients[client].Clear();. Форварды вызывают эти делегаты; в PutInServer HUD перемещён перед GetClientAuthId по target.md. Fake-client guard, порядок ADMIN_MENU→HUD→клиент и HUD→ASSIST_USE→очистка→рестрикты сохранены по плану.

Наблюдения: Независимое чтение GPT-6 Sol этапов 3–5 подтвердило layout, гейты и порядок клиентского жизненного цикла. HudClientReadCookie не использует SteamID/Account. Других замечаний нет.

Проверка: `python docs/restructure/tools/symbols.py --allow OnClientPutInServer --allow OnClientDisconnect --allow ClientsOnClientPutInServer --allow ClientsOnClientDisconnect`; код 0.

```text
База: HEAD; сравнивается: рабочее дерево; сравнено сборок: 128 (перебор BOTOX_SM, HUD, ASSIST_USE, ADMIN_MENU, HALFZOMBIE, RESTRICT_BUILTIN, _zr_included)

Перенесены без изменений:
  func   OnClientCookiesCached                    entWatch/client.sp -> entWatch.sp
  func   OnClientSayCommand                       entWatch/client.sp -> entWatch.sp

Расхождения:
  func      ClientsOnClientDisconnect                добавлен или попал в эту сборку, во всех сборках  (разрешено)
  func      ClientsOnClientPutInServer               добавлен или попал в эту сборку, во всех сборках  (разрешено)
  func      OnClientDisconnect                       изменён текст, во всех сборках  (разрешено)
  func      OnClientPutInServer                      изменён текст, во всех сборках  (разрешено)

ИТОГ: только перенос; незапланированных расхождений нет.
```

Проверено: скрипт `symbols.py` и чтение. Не компилировалось.
