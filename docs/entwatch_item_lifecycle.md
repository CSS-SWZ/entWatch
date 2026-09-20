# entWatch Item Lifecycle

> Справка по жизненному циклу айтемов в entWatch: владение, использование,
> синхронизация с движком.

---

## Структуры данных

### Config (include/entWatch/Config.inc)
Статическая конфигурация айтема из cfg-файла карты.
- `Weapon_HammerId`, `Button_HammerId`, `Trigger_HammerId`, `Compare_HammerId`, `Relay_HammerId`
- `Mode` — режим кнопки (PROTECT=0, COOLDOWN=1, MAXUSES=2, MAXUSESCD=3, CHARGESCD=4)
- `Cooldown` — кулдаун из конфига
- `Maxuses` — макс. число использований
- `Slot` — слот оружия (NONE=0, PRIMARY=1, SECONDARY=2, KNIFE=3, GRENADES=4)
- `Filter` — targetname для DispatchKeyValue при использовании

### Item (include/entWatch/Item.inc)
Рантайм-состояние экземпляра айтема.
- `Config` — индекс в Configs[]
- `Weapon`, `Button`, `Trigger`, `Compare`, `Relay` — entity indices
- `Owner` — индекс игрока (0 = нет владельца)
- `Uses` — счётчик использований
- `Cooldown` — timestamp когда кулдаун истечёт
- `Wait` — timestamp когда кнопка (m_flWait) разблокируется
- `Transfered` — был ли передан админом
- `RemovedButton` — кнопка была удалена (entity destroyed)

---

## Owner lifecycle

### Установка Owner
- `OnWeaponPickup` (sdkhook.sp) — SDKHook_WeaponEquipPost → `Items[item].Owner = client`

### Очистка Owner
- `OnWeaponDrop` (sdkhook.sp) — SDKHook_WeaponDropPost → `Items[item].Owner = 0`
- `ItemDrop()` (items.sp) — SDKHooks_DropWeapon + `Owner = 0`
  **НО**: отказывается для SLOT_NONE и SLOT_KNIFE (return false, Owner НЕ очищается!)
- `ClientLostHandleAction()` (client.sp) — вызывает ItemDrop для каждого предмета игрока
  Вызывается из: `OnPlayerDeath`, `OnPlayerDisconnect`

### ВАЖНО: проблема с SLOT_KNIFE
`ItemDrop()` возвращает false для ножей → Owner остаётся установленным.
`ClientLostHandleAction()` при смерти/дисконнекте вызывает ItemDrop, но для ножей
Owner не сбрасывается. Теоретически оружие уничтожится (OnEntityDestroyed → ItemClear),
но если между смертью и уничтожением entity проходит время, Owner указывает на игрока,
который уже мёртв / в спеках / отключился.

Это может быть причиной ошибки `Timer_Hud() : owner item #%i isnt T or CT` —
HUD-таймер видит `Items[i].Owner != 0`, но игрок уже в спеках (team=1 → team-1=0).

---

## Использование (Use)

### Обычная кнопка (func_button через SDKHook_Use)
1. SDKHook_Use → `OnButtonPress()` (sdkhook.sp:51)
2. Проверки: owner, restrict, ItemIsReady
3. Если Compare || Relay → Plugin_Continue (обработка через output hooks)
4. Иначе: `APIOnClientItemUse()`, `ItemReload()`, `PrintToChatItemAction()`, Plugin_Continue
5. Движок: ButtonUse() → OnPressed (если AT_BOTTOM)

### Compare / Relay
- `Compare_OnEqualTo` — hook на output "OnEqualTo" у logic_compare
- `Relay_OnTrigger` — hook на output "OnTrigger" у logic_relay
- Оба: проверяют Owner, вызывают APIOnClientItemUse + ItemReload + PrintToChat

### AssistUse (assist_use.sp)
- Автоматически нажимает кнопку за игрока при E, если он не смотрит в другую кнопку
- Работает через `AcceptEntityInput(button, "Use", owner, owner)`
- Условия: один предмет у игрока, не нажимал другую кнопку в этом тике, CD 0.1 сек
- Тоже проходит через SDKHook_Use → OnButtonPress

---

## Регистрация entity

### По HammerID (конфиг)
`ItemsOnEntitySpawned()` — при появлении entity проверяет hammerid по Configs[]

### Автодетект кнопки (Timer_ItemFindButton)
Если weapon зарегистрирован, но button нет — через 0.5 сек ищет child-entity:
- `StrContains(classname, "button")` → func_button, func_rot_button, momentary_rot_button
- `== "func_physbox_multiplayer"` → physbox
- `StrContains(classname, "door")` → func_door, func_door_rotating
Приоритет: button > physbox > door

---

## Тайминг / синхронизация

- `GetGameTime()` = `gpGlobals->curtime` — правильный выбор для синхронизации с движком
- `Items[item].Wait` — таймер по m_flWait + маржа 5 тиков (ItemReload)
- `Items[item].Cooldown` — таймер по Config.Cooldown (ItemReload)
- `m_toggle_state` — авторитетный источник готовности кнопки в движке (проверяется в ItemIsReady)
- `m_bLocked` — блокировка кнопки (проверяется в ItemIsReady)
