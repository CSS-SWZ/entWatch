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
