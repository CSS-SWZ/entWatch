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
