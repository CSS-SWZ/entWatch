# func_button — справка по исходникам движка

> Источник: `hl2_src-leak-2017`
> - buttons.cpp / buttons.h — CBaseButton, CRotButton, CMomentaryRotButton
> - doors.cpp / doors.h — CBaseDoor, CRotDoor
> - basetoggle.h / subs.cpp — CBaseToggle (datadesc, m_toggle_state, m_flWait)
> - baseentity.h — enum TOGGLE_STATE

---

## Иерархия классов

```
CBaseEntity
  └─ CBaseToggle            // m_toggle_state, m_flWait, LinearMove/AngularMove
       ├─ CBaseButton       // func_button
       │    └─ CRotButton   // func_rot_button
       │         └─ CMomentaryRotButton  // momentary_rot_button (!)
       └─ CBaseDoor         // func_door
            └─ CRotDoor     // func_door_rotating

CBaseEntity
  └─ CBreakable
       └─ CPhysBox          // func_physbox_multiplayer (НЕ CBaseToggle!)
```

---

## TOGGLE_STATE (baseentity.h:249)

```cpp
enum TOGGLE_STATE
{
    TS_AT_TOP,       // 0 — нажата / открыта
    TS_AT_BOTTOM,    // 1 — отпущена, ГОТОВА
    TS_GOING_UP,     // 2 — движется вверх
    TS_GOING_DOWN    // 3 — возвращается
};
```

Поле `m_toggle_state` объявлено в `CBaseToggle` (basetoggle.h:25), datadesc —
`FIELD_INTEGER` (subs.cpp:136). Доступно через `Prop_Data "m_toggle_state"`.

### Когда движок принимает Use

| Состояние | func_button (не-toggle) | func_button (toggle) | func_door |
|---|---|---|---|
| AT_BOTTOM (1) | ✅ OnPressed | ✅ OnPressed | ✅ DoorActivate |
| GOING_UP (2) | ❌ тихий return | ❌ тихий return | зависит от spawnflags |
| AT_TOP (0) | ❌ тихий return | ✅ OnPressed + Return | ✅ только NO_AUTO_RETURN |
| GOING_DOWN (3) | ❌ тихий return | ❌ тихий return | зависит от spawnflags |

---

## m_flWait

- Хранится в `CBaseToggle::m_flWait` (FIELD_FLOAT, Prop_Data "m_flWait")
- Значение `0` → принудительно `1` при Spawn (buttons.cpp:398)
- Значение `-1` → `m_fStayPushed = true`, кнопка остаётся нажатой навсегда
- Это задержка **наверху** (в AT_TOP), а НЕ полный кулдаун

### Полный цикл кнопки

```
Полный кулдаун = t_move_up + m_flWait + t_move_down
```

Для SF_BUTTON_DONTMOVE — анимации ≈ 0, но Think-цикл занимает 2–3 тика.

### Цепочка функций

```
ButtonUse() [state=AT_BOTTOM] → OnPressed → ButtonActivate()
  state := GOING_UP → LinearMove → TriggerAndWait()
    state := AT_TOP → OnIn → SetNextThink(curtime + m_flWait)
      ButtonReturn() [Think]
        state := GOING_DOWN → LinearMove → ButtonBackHome()
          state := AT_BOTTOM → OnOut → готова
```

---

## Spawnflags (buttons.cpp:24–32)

| Флаг | Значение | Описание |
|---|---|---|
| SF_BUTTON_DONTMOVE | 1 | Кнопка не двигается |
| SF_BUTTON_TOGGLE | 32 | Toggle — остаётся нажатой до повторного Use |
| SF_BUTTON_TOUCH_ACTIVATES | 256 | Активируется касанием |
| SF_BUTTON_DAMAGE_ACTIVATES | 512 | Активируется уроном |
| SF_BUTTON_USE_ACTIVATES | 1024 | Активируется E (Use) — нужен для ButtonUse |
| SF_BUTTON_LOCKED | 2048 | Изначально заблокирована |
| SF_BUTTON_SPARK_IF_OFF | 4096 | Искрит в выключенном состоянии |
| SF_BUTTON_JIGGLE_ON_USE_LOCKED | 8192 | Дрожит при Use заблокированной |

---

## Inputs / Outputs

### Inputs
- `Lock` → m_bLocked = true
- `Unlock` → m_bLocked = false
- `Press` → toggle нажатие (BUTTON_PRESS)
- `PressIn` → форсировать нажатие (BUTTON_ACTIVATE)
- `PressOut` → форсировать возврат (BUTTON_RETURN)

### Outputs
- `OnPressed` — кнопка нажата (до начала движения)
- `OnDamaged` — получен урон
- `OnUseLocked` — попытка Use заблокированной (антифлуд 0.5 сек)
- `OnIn` — достигла верхней позиции (TriggerAndWait)
- `OnOut` — вернулась в нижнюю позиции (ButtonBackHome)

---

## Lock / Unlock нюансы

- `Lock`/`Unlock` только устанавливают `m_bLocked`. НЕ сбрасывают `m_toggle_state`.
- Если заблокировать в AT_TOP → разблокировать → кнопка НЕ вернётся сама
  (Think уже не запланирован). Нужно `PressOut`.
- `ButtonUse` при locked: `OnUseLocked()` → звук + output (раз в 0.5 сек)

---

## momentary_rot_button — отличия

CMomentaryRotButton наследует CRotButton → CBaseButton → CBaseToggle, но:

- **Spawn() НЕ вызывает CBaseButton::Spawn()** → `m_toggle_state` не инициализируется
  (остаётся 0 = AT_TOP навсегда)
- **Не использует toggle state machine** вообще
- Работает как **непрерывный вентиль**: Use каждый тик пока E зажата
  (`FCAP_CONTINUOUS_USE | FCAP_USE_IN_RADIUS`)
- `OnPressed` — только при НАЧАЛЕ удержания (первый фрейм, `!m_lastUsed`)
- `OnUnpressed` — при отпускании E (UseMoveDone)
- Output `Position` (0.0–1.0) — текущий угол

**Для SourceMod**: `HasEntProp(entity, Prop_Data, "m_toggle_state")` → TRUE
(поле унаследовано), но значение бессмысленно. Нужно исключать по classname.

---

## func_physbox_multiplayer

CPhysBox → CBreakable → CBaseEntity. **НЕ наследует CBaseToggle**.
`HasEntProp(entity, Prop_Data, "m_toggle_state")` → FALSE.

---

## SDKHook_Use и ButtonUse

SDKHooks `Hook_Use` (extension.cpp:1664) — **pre-hook** на виртуальную `CBaseEntity::Use`.
- `Plugin_Handled` → `MRES_SUPERCEDE` → оригинальный ButtonUse **не вызывается**
- `Plugin_Continue` → `MRES_IGNORED` → движок вызывает ButtonUse как обычно

Порядок: SDKHook callback → (если Plugin_Continue) → ButtonUse → OnPressed / тихий return.

---

## Проблема рассинхронизации entWatch (исправлена)

### Суть
entWatch использовал приближённый таймер `Items[item].Wait = GetGameTime() + tick*5 + m_flWait`
для определения готовности кнопки. Полный цикл движка длиннее (+ анимация + Think-тайминг).
При спаме E entWatch считал кнопку готовой раньше движка → фантомное использование
(чат + forward без реального OnPressed).

### Решение
Проверять `GetEntProp(button, Prop_Data, "m_toggle_state") != 1` в ItemIsReady().
С исключением momentary_rot_button (по classname) и func_physbox_multiplayer (HasEntProp=false).

### GetGameTime vs другие
- `GetGameTime()` = `gpGlobals->curtime` — правильный выбор, тот же тайминг что и у движка
- `GetEngineTime()` = realtime — не подходит
- `GetTime()` = Unix time — не подходит
