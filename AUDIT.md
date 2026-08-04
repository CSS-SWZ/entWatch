# entWatch — глубокий аудит (2026-08-03)

Read-only аудит. Ничего не менялось и не компилировалось.
Метод: 8 поисковых агентов по модулям/осям → 8 adversarial-верификаторов (задача — **опровергнуть**
находку) → критик полноты. 115 сырых находок → **101 пережила проверку**, 14 опровергнуты.

Каждая находка обязана нести **trigger line** (кто выполняет, в каком состоянии, по какому пути) и
цитаты `file:line`, в т.ч. из исходников SM/движка. Находки с `confidence: hypothesis` —
**не основание для правки**, они остаются гипотезами до подтверждения на живом сервере.

## Проверенные оси

Корректность и краевые случаи · надёжность/устойчивость к крашам · безопасность (доверие данным
клиента, SQL-инъекции, валидация входа нативов) · идиоматичность SourceMod API · handles ·
async-колбэки · entity refs · late load · disconnect-семантика · БД · фиксированные массивы ·
ConVar · горячие пути.

## Проверенные инварианты проекта

- **I1** защита владения («E-spam») — `Items[item].Owner != activator`
- **I2** ebanned / half-zombie не получает предмет ни одним маршрутом
- **I3** `targetname`-фильтр для legacy-защиты карт пишется до пропуска нажатия
- **I4** готовность entWatch никогда не опережает карту (одна временная база `GetGameTime()`)
- **I5** `SLOT_KNIFE` / `SLOT_NONE` не дропаются и не передаются
- **I6** индексы `Items[]` / `Configs[]` нестабильны (сдвиг массива)
- **I7** ровно один учёт использования: кнопка **либо** compare/relay
- **I8** симметрия хуков round_start → round_end → map change
- **I9** `Config`/`Item` — часть публичного API

---

## Ключевые факты, установленные по исходникам (решают судьбу целых классов гипотез)

1. **`HookSingleEntityOutput` дедуплицирует** одинаковые (функция + entity ref):
   `sdktools/outputnatives.cpp:75-82` — `return 0` при совпадении.
   → Двойной учёт use через compare/relay при переregister'е **невозможен**.
2. **`SDKHooks::Hook` НЕ дедуплицирует**: `hooks.push_back(hook)` безусловно
   (`sdkhooks/extension.cpp:792-796`); дедуплицируется только vtable-хук (`:636-644`);
   `PopulateCallbackList` (`:500-512`) собирает все записи; `Hook_Use` берёт `max(res)` и
   supercede при `>= Pl_Handled` (`:1664-1709`).
   → Повторная регистрация `SDKHook_Use` на одной сущности **реальна и удваивает вызов**.
3. **Chained comparison в SourcePawn — это конъюнкция, а не `(a<b)<c`.**
   В компиляторе есть первоклассный `ChainedCompareExpr`:
   `sourcepawn/compiler/parser.cpp:750`, `semantics.cpp:1050` (`CheckChainedCompareExpr`),
   `code-generator.cpp:1005` (`EmitChainedCompareExpr`).
   → `RestrictIsValidDuration()`: `0 < duration < 525600` работает **правильно**.
   **Это опровергает правило в `~/.claude/rules/sourcepawn.md`** («No chained comparisons: …
   означает `(0 < x) < N`, всегда истинно») — для SourcePawn 1.11+ утверждение неверно.
   Совет по читаемости остаётся в силе, обоснование «оно сломано» — нет.
4. **`IsClientInGame(0)` — жёсткая ошибка натива**, а не `false`:
   `clients.inc:380` `@error Invalid client index`.
5. **Отсутствующая фраза в `%t` — не тихий фолбэк, а исключение**:
   `core/logic/sprintf.cpp:109/115` `ThrowNativeErrorEx(SP_ERROR_PARAM, "Language phrase \"%s\"
   not found")`; `smn_string.cpp` не оборачивает `atcprintf` в `DetectExceptions` → кадр плагина
   разматывается, следующий оператор не выполняется.

---

## Опровергнуто (14) — не чинить

| Файл | Заявка | Почему мертва |
|---|---|---|
| restrict.sp | `0 < duration < 525600` всегда истинно | SourcePawn: цепочка = конъюнкция (см. факт 3) |
| entWatch.sp | `OnPlayerDeath` не проверяет `client != 0` (×2 находки) | цепочка описана верно, но `player_death` всегда несёт живой userid |
| sdkhook.sp | `Compare_OnEqualTo`/`Relay_OnTrigger` индексируют `Items[-1]` | достижимого триггера нет… **НО см. находку C3 критика — путь всё-таки есть** |
| admin_menu.sp | «Reload» оставляет двойные output-хуки | `HookSingleEntityOutput` дедуплицирует |
| transfer.sp | `Transfered=true` при `Owner=0` через re-entry `FireEntityOutput` | `FireEntityOutput` не выполняет проводку карты синхронно |
| helpers.sp | `AreEntitiesRelated` — бесконечная рекурсия по циклу `m_pParent` | цикл в движке невозможен, триггер не написан |
| halfzombie.sp | `HalfZombie[]` не чистится при disconnect | утечка состояния есть, достижимых последствий нет |
| client.sp | `ClientGetByAccount(0)` возвращает живой слот | триггера нет |
| items.sp | `ItemsInitiateItem` инкрементит счётчик при неудачной регистрации | единственная падающая ветка недостижима |
| config.sp | Конфиги сверх `MAX_CONFIGS` отбрасываются без лога | запрос на логирование, а не дефект |
| entWatch.inc | API не документирует время жизни индексов | Doxygen — вне области аудита |
| entWatch.sp | Мёртвый guard в `OnRestartGame` | триггера нет, на живом пути ведёт себя верно |
| hud.sp | `Items[].Owner` как индекс клиента без валидации | автор сам не смог написать триггер |

---

## CRITICAL (2)

### 1. ItemsClear() never unhooks: duplicate SDKHook_Use on every button for a map's first round

- **id**: `itemsclear-no-unhook-double-sdkhook` | **место**: `addons/sourcemod/scripting/entWatch/items.sp:69` -> `ItemsClear()`
- **ось/инвариант**: invariant-I8 | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** ItemsClear() (items.sp:69-79) only zeroes the struct fields via ItemClear(); it never calls ItemUnhook(). The design survives this only because CS:S normally destroys the hooked entities between two registrations (SDKHooks removes an entity's hooks on delete). On the FIRST round of a map that is not true: the same live entity is registered twice, and SDKHooks stacks duplicate registrations of the same (entity, type, callback) - it dedupes only the vtable hook, then pushes the pawn callback unconditionally (extension.cpp:636-644 vs 792-796), and PopulateCallbackList (extension.cpp:500-512) collects every entry, so Hook_Use executes OnButtonPress twice and returns max(res) with MRES_SUPERCEDE for >= Pl_Handled (extension.cpp:1664-1709). For a MODE_COOLDOWN item the 1st invocation passes ItemIsReady, fires the API forward, ItemReload()s and announces the use; the 2nd invocation sees the cooldown it just set (items.sp:465), returns Plugin_Handled (sdkhook.sp:70-71), the max supercedes the engine Use, so the map's button never fires. That is exactly the I4 'ghost use' failure: announced and counted, never executed. For MODE_MAXUSES it burns two uses and prints two chat lines per press. Compare/relay paths are NOT affected because HookSingleEntityOutput dedupes identical (function, entity_ref) hooks (outputnatives.cpp:75-82); trigger touch hooks are doubled but idempotent.

**Триггер.** Any player, on the first round of any map with a cooldown item, pressing the item button. Path: entWatch.sp:110-124 OnMapStart -> ItemsOnMapStart (items.sp:17-20) -> ItemsOnRoundStart (items.sp:22-31) sets RoundStarted=true and SDKHooks the map's original button (items.sp:183). CS:S then restarts round 1 (m_flRestartRoundTime=0.1f, cs_gamerules.cpp:581; Think -> RestartRound, 2971-3004) -> CleanUpMap (2740) removes and re-parses every non-preserved map entity (4554-4593; func_button/trigger_*/logic_* are not in s_PreserveEnts, 257-299); the recreated entities go through DispatchSpawn (mapentities.cpp:270) -> gEntList.NotifySpawn (util.cpp:1906) -> entity listener (entitylist.cpp:1143) -> SDKHooks OnEntitySpawned forward (extension.cpp:942-961, 1889-1913) -> entWatch.sp:189-192 -> ItemsOnEntitySpawned, and RoundStarted is STILL true (items.sp:83), so the new button is hooked. RestartRound then fires round_start (cs_gamerules.cpp:2806) -> entWatch.sp:173-180 -> ItemsOnRoundStart -> ItemsClear() (no unhook) -> full rescan -> the SAME live button is hooked a second time.

**Доказательства.** items.sp:69-79 (ItemClear only), items.sp:22-31, items.sp:83-84, items.sp:183, items.sp:451/465 (ItemIsReady), sdkhook.sp:51-84; entWatch.sp:110-124, 173-180, 188-192. SDKHooks: C:/develop/sm1.13-botox/source/sourcemod/extensions/sdkhooks/extension.cpp:636-644 (vtable dedupe only), :792-796 (unconditional hooks.push_back), :500-512 (PopulateCallbackList, no dedupe), :1664-1709 (Hook_Use, max(res) -> MRES_SUPERCEDE), :1932 (hooks auto-removed only when the entity is deleted). Entity outputs DO dedupe: extensions/sdktools/outputnatives.cpp:75-82. Engine: cs_gamerules.cpp:581, 2740, 2806, 4554-4593, 257-299; mapentities.cpp:270; util.cpp:1906; entitylist.cpp:1143-1153.

**Исправление.**

```
Unhook before clearing:

void ItemsClear()
{
    for(int i = 0; i < Items_Count; i++)
    {
        ItemUnhook(i);
        ItemClear(i);
    }
    Items_Count = 0;
}

(ItemUnhook already guards every field, items.sp:638-658.) Note the intended side effect: after this, item buttons are no longer hooked between round_end and round_start, so the `if(!RoundStarted) return Plugin_Handled;` guard in OnButtonPress (sdkhook.sp:53-54) stops blocking presses in that window - verify that is acceptable, or unhook only in ItemsOnRoundStart. Live check: first round of a map, use a cooldown item; today it announces the use while the map does nothing.
```

> **Поправка верификатора.** Two scope corrections, neither of which kills the finding. (a) Only items whose config carries an explicit `buttonid` are double-hooked. When the button is discovered by Timer_ItemFindButton (no buttonid), the button entity is never matched by ItemsRegisterGetKeyValues, so no scan hooks it; the first timer to fire registers it and every later timer returns at the `Items[item].Button` guard (items.sp:242, 250) - one hook. (b) The trigger line can be stated much more simply and does not depend on CleanUpMap at all: `RoundStarted` is set true by OnMapStart (entWatch.sp:113 -> items.sp:19-25) and is never cleared before the map's first round_start, so any button registered in that window is registered a second time by the round_start rescan. Residual uncertainty worth stating to the maintainer: this predicts dead cooldown items for the whole first round of every map with a buttonid config, which is in tension with 'production for years, no complaints' - most likely explanation is that the live configs rely on button auto-discovery (immune per (a)), or the server issues mp_restartgame at map start (which sets RoundStarted=false through the hook in entWatch.sp:219-223 and closes the window). Verify on the live server before treating it as universal.

### 2. GetClientUserId(admin) throws for admin==0: console/RCON eban commands die and wedge the module

- **id**: `eban-console-getclientuserid-zero` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:277` -> `RestrictClientBan / RestrictClientUnBan / RestrictAddBan / RestrictDeleteBan()`
- **ось/инвариант**: api-use | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** All four eban entry points store the issuing admin as `pack.WriteCell(GetClientUserId(admin))` (restrict.sp:277, :375, :479, :613) without guarding admin == 0. On a dedicated server an admin command run from the server console or over RCON reaches the callback with client == 0 (the admin-flag check is explicitly bypassed for client 0). GetClientUserId(0) is a hard native error. Note the code clearly *intends* to support the console — the callbacks all branch on `if(!console || ...)` (restrict.sp:306, :396, :516, :640) where `console` is the raw index written at :276/:374/:478/:612 — but execution never gets there. Worse, LastQueryEBanNotCompleted was already set true at :258/:364/:440/:561, so the abort also permanently locks the whole eban subsystem (see eban-callback-isclientingame-zero). For sm_addeban/sm_deleban this is the *primary* usage path: they are ADMFLAG_RCON commands normally typed in the server console, so they are effectively 100% broken there — and RestrictAddBan/RestrictDeleteBan have already run their blocking SELECT and leaked its result set by then.

**Триггер.** Dedicated server console (or an RCON tool) executes `sm_addeban 60 STEAM_1:0:12345`. ConCmdManager dispatches with client = 0 (admin check bypassed). Command_AddBan(0, 2) -> RestrictAddBan(60, "STEAM_...", "", 0) -> :440 flag=true -> :456-458 blocking SELECT -> :473 new DataPack -> :479 GetClientUserId(0) -> ThrowNativeError("Client index 0 is invalid") -> command aborted, no ban written, DBResultSet leaked, flag stuck true. Identical for `sm_eban` (:277), `sm_uneban` (:375), `sm_deleban` (:613) from the console.

**Доказательства.** restrict.sp:277 `pack.WriteCell(GetClientUserId(admin));` (admin comes from Command_Ban(client,...) at :101); :375, :479, :613 identical. Native: C:/develop/sm-1.13/include/clients.inc:358-364 "@error If the client is not connected or the index is invalid"; core impl smn_players.cpp:710-724 `IGamePlayer *pPlayer = playerhelpers->GetGamePlayer(client); if (!pPlayer) return pContext->ThrowNativeError("Client index %d is invalid", client);` and PlayerManager.cpp:1380-1387 `GetPlayerByIndex` returns NULL for `client < 1`. Console reaches the callback with 0: ConCmdManager.cpp:253 `if (client && hook->admin && !CheckAccess(...))` — admin checks are skipped for client 0 — and :233 keeps client == 0 on a dedicated server. (For contrast, GetClientName(0) is safe: smn_players.cpp:292-309 special-cases index 0 and returns the `hostname` cvar — which is why restrict.sp:268 does not throw first, and also why the DB records the server hostname as the admin name.)

**Исправление.**

```
Store 0 for the console instead of calling the native:
```
pack.WriteCell(admin ? GetClientUserId(admin) : 0);
```
in all four places (277, 375, 479, 613); GetClientOfUserId(0) already returns 0 in the callbacks, and the existing `if(!console || (admin && IsClientInGame(admin)))` branches then work as written. PrintToChat2(0, ...) is safe — it routes to PrintToConsole(0), which SM explicitly allows (smn_console.cpp:106-128 permits index 0).
```

> **Поправка верификатора.** Add to the consequences: the abort also leaks the DataPack allocated one line earlier (restrict.sp:473 / :607) in addition to the DBResultSet from the synchronous SELECT (restrict.sp:457 / :579) — the SP runtime error unwinds the call frame but does not free plugin-owned handles. Keep severity critical for sm_addeban/sm_deleban (server console / RCON is their normal invocation path, so they are 100% broken there and wedge everything else on first use); sm_eban/sm_uneban are only affected when driven from the console rather than in-game.

## MAJOR (34)

### 3. Timer_ItemFindButton carries a raw item index across 0.5 s while ItemRemove() shifts the array

- **id**: `timer-findbutton-stale-item-index` | **место**: `addons/sourcemod/scripting/entWatch/items.sp:245` -> `ItemProcessCheckButton / Timer_ItemFindButton()`
- **ось/инвариант**: invariant-I6 | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** ItemProcessCheckButton passes the array index as timer data (items.sp:245) and Timer_ItemFindButton uses it 0.5 s later (items.sp:248-291). ItemRemove() (items.sp:606-613) shifts every higher index down, so the pending index silently retargets another item, or points past Items_Count into a stale slot. Two damages: (a) the item that actually needed a button never gets one - with Button==0 nothing calls SDKHook_Use, so OnButtonPress never runs for it, ItemsGetByButton returns -1 and any player who reaches the map's button fires the item (I1 hole) and no cooldown/uses are accounted; (b) if the stale index lands on a slot >= Items_Count, ItemsRegisterItemEntity (items.sp:288) hooks a button and stores it in a dead slot - a live SDKHook_Use that no item owns. The guard at items.sp:250 only catches Config==-1/Weapon==0, not 'index no longer means this item'. The timer is also created without TIMER_FLAG_NO_MAPCHANGE, so one created shortly before a map change fires on the next map against a completely different Items[] population.

**Триггер.** Two items registered; the lower-indexed item's weapon entity is destroyed inside the 0.5 s window. Concretely on every map load: OnMapStart registers items 0..N and queues their button timers (items.sp:169->245); ~0.1 s later CS:S RestartRound -> CleanUpMap destroys the item weapons in gEntList order (cs_gamerules.cpp:2740, 4587-4590) -> OnEntityDestroyed -> ItemsOnEntityDestroyed -> ItemUnhook/ItemClear/ItemRemove (items.sp:308-314) shifts the array under the pending timers, which then fire against re-numbered slots. The same happens mid-round on any map that removes an item weapon (strip/respawn) while another item is within 0.5 s of spawning.

**Доказательства.** items.sp:240-246 (CreateTimer(0.5, Timer_ItemFindButton, item)), items.sp:248-291 (uses the index directly: 250, 266, 269, 288), items.sp:606-613 (ItemRemove shifts, decrements Items_Count), items.sp:304-315 (weapon destroyed -> ItemRemove). CLAUDE.md 'Indices are not stable' is the documented contract this violates. Engine: cs_gamerules.cpp:581/2740/4587-4590.

**Исправление.**

```
Key the timer by something stable and resolve it in the callback, e.g. pass EntIndexToEntRef(Items[item].Weapon) and start with `int item = ItemsGetByWeapon(EntRefToEntIndex(ref)); if(item == -1) return Plugin_Stop;`. Add TIMER_FLAG_NO_MAPCHANGE to the CreateTimer call.
```

> **Поправка верификатора.** The stated trigger ('on every map load') is wrong and self-healing: every re-registration of a weapon creates a FRESH timer (items.sp:169 -> 245), and CleanUpMap recreates map entities preserving their indices (cs_gamerules.cpp:4554-4560), so at map load the stale indices land on the same items and the extra timers are harmless no-ops. The reachable trigger is a MID-ROUND ItemRemove inside the 0.5 s window: (a) a map strip trigger / player_weaponstrip destroying an item weapon (CBasePlayer::RemoveAllItems -> UTIL_Remove -> OnEntityDestroyed -> items.sp:308-314), or (b) the owner of a lower-indexed item disconnecting (CMultiplayRules::ClientDisconnected -> RemoveAllItems, multiplay_gamerules.cpp:602-620), while another item's weapon was registered less than 0.5 s earlier (map respawn / point_template / sm_espawn). Also note damage (a) in the report ('the item that needed a button never gets one') is only true for that same mid-round case - state it as the dead-slot hook, which is the demonstrable one. Fix as proposed (resolve from EntIndexToEntRef of the weapon in the callback, plus TIMER_FLAG_NO_MAPCHANGE).

### 4. Dead owner can fire his item: assist_use has no IsPlayerAlive check

- **id**: `assist-dead-owner-can-fire` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:140` -> `AssistUseOnPlayerRunCmdPost()`
- **ось/инвариант**: invariant-I1 | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** AssistUseOnPlayerRunCmdPost never checks that the client is alive. The engine itself makes a dead player's +USE harmless: CBasePlayer::PlayerUse() takes the IsObserver() branch and returns before FindUseEntity (baseplayer_shared.cpp:1281-1290), so without this module a corpse can never touch a func_button. assist_use bypasses that entirely by calling AcceptEntityInput(Button,"Use",Owner,Owner). Combined with ItemDrop() silently failing for SLOT_KNIFE/SLOT_NONE (items.sp:436-437 returns false WITHOUT clearing Items[].Owner) and CS:S never dropping or removing the knife on death (CCSPlayer::DropWeapons drops C4/defuser/shield/best gun/grenades only, cs_player.cpp:6787-6910), the dead player keeps Items[].Owner and the weapon (plus its parented button) stays alive. Result: a dead player presses E in spectator mode and fires a live map item; OnButtonPress accepts it because Owner == activator.

**Триггер.** Zombie/human P owns a knife item (GFL config with allowtransfer 0 + forcedrop 0 -> SLOT_KNIFE at config.sp:149, or UNLOZE `slot 3`). P dies -> OnPlayerDeath -> ClientLostHandleAction(P, ACTION_DEATH) -> ItemDrop() returns false at items.sp:436 leaving Items[i].Owner == P. P, now an observer, holds +USE -> OnPlayerRunCmdPost -> AssistUseOnPlayerRunCmdPost (no alive check) -> AssistUseGetClientItemsCount(P)==1 -> AssistUse -> AssistUseInputByName -> AcceptEntityInput(Button,"Use",P,P) -> CBaseEntity::InputUse -> virtual Use -> SDKHook_Use -> OnButtonPress: Owner==activator passes, item fires, use is announced and counted.

**Доказательства.** assist_use.sp:140-190 (no IsPlayerAlive anywhere in the function); assist_use.sp:209 AcceptEntityInput(Items[item].Button,"Use",Items[item].Owner,Items[item].Owner); sdkhook.sp:51-84 OnButtonPress has no alive check either; items.sp:434-445 ItemDrop returns false for SLOT_KNIFE/SLOT_NONE before clearing Owner; C:/develop/sm-1.13/include/sdktools_entinput.inc:51 AcceptEntityInput; C:/develop/hl2_src-leak-2017/src/game/server/baseentity.cpp:1906,4009-4012 ("Use" input -> virtual Use); C:/develop/hl2_src-leak-2017/src/game/shared/baseplayer_shared.cpp:1274-1290 (observer +USE returns early); C:/develop/hl2_src-leak-2017/src/game/server/cstrike/cs_player.cpp:6787-6910 (knife is never dropped on death).

**Исправление.**

```
Guard the module entry point:

void AssistUseOnPlayerRunCmdPost(int client, int buttons)
{
	if(!RoundStarted)
		return;
	if(!IsPlayerAlive(client))
		return;
	...

A second, independent barrier in sdkhook.sp OnButtonPress (`if(!IsPlayerAlive(activator)) return Plugin_Handled;`) closes the same hole for any other forced-press route; note that fixing ItemDrop to clear Owner would also remove this particular trigger, so recompute before applying both.
```

> **Поправка верификатора.** Two preconditions must be stated that the finding omits, and they are why I downgrade critical->major: (1) the config must map the item to SLOT_KNIFE or SLOT_NONE (GFL `allowtransfer 0`+`forcedrop 0` at config.sp:149, or UNLOZE `slot 0`/`slot 3`); (2) the weapon must survive CCSPlayer::DropWeapons — always true for a weapon_knife, but a SLOT_KNIFE *pistol* is dropped by DropPistol(true) (cs_player.cpp:6848-6849) unless the player also carries a rifle, and that drop goes through CBasePlayer::Weapon_Drop, firing SDKHook_WeaponDropPost -> OnWeaponDrop (sdkhook.sp:36-49) which clears Owner. Note DropWeapons runs at cs_player.cpp:1177, i.e. BEFORE the player_death event, so the ordering is consistent. The proposed fix is sound; the finder's own note is right that fixing ItemDrop makes the assist_use guard redundant for this trigger — but not for sm_euse (assist_use.sp:74/78-99), which is a second dead-owner route with the same missing alive check.

### 5. Pickup denied when DB auth never completes (fail-closed, contradicts fail-open intent)

- **id**: `weapontouch-auth-fail-closed` | **место**: `addons/sourcemod/scripting/entWatch/sdkhook.sp:9` -> `OnWeaponTouch()`
- **ось/инвариант**: reliability | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** OnWeaponTouch blocks item pickup whenever Clients[client].Authorized is false. Authorized is set in exactly one place - SQL_Callback_SelectBans (client.sp:75) - and every failure path leaves it false forever for that session: ClientAuth() returns early when GetSteamAccountID() yields 0 (documented as "Steam account ID or 0 if not available") or when GetClientIP fails (client.sp:49-50), and the callback returns early on any SQL error (client.sp:57-61). There is no retry. This is the opposite of the documented intent: RestrictClientHasRestrict() deliberately fails open (`return (DBLoaded && ...)`, restrict.sp:664-667), and CLAUDE.md states "No database -> no restricts (fail-open)". A player who is not restricted at all can be locked out of every item on the map, and every player is locked out for the whole duration of the auth query after joining.

**Триггер.** Player joins; OnClientPutInServer -> ClientAuth -> GetSteamAccountID(client) returns 0 because backend validation has not completed yet (or the Steam backend is down) -> ClientAuth returns at client.sp:50 without ever issuing the query -> Clients[].Authorized stays false. The player then walks over the map item: SDKHook_WeaponCanUse -> OnWeaponTouch -> ItemsGetByWeapon finds the item -> `if(!Clients[client].Authorized) return Plugin_Handled;` -> pickup refused for the rest of his session. Same outcome on a transient MySQL error (LogError + return at client.sp:59-60).

**Доказательства.** sdkhook.sp:9-10; client.sp:41-53 ClientAuth early returns; client.sp:55-77 SQL_Callback_SelectBans (error path returns before setting Authorized); restrict.sp:664-667 RestrictClientHasRestrict fails open; C:/develop/sm-1.13/include/clients.inc:343-354 GetSteamAccountID "Steam account ID or 0 if not available"; C:/develop/sm-1.13/include/sdkhooks.inc:212,264 SDKHook_WeaponCanUse callback `Action (int client, int weapon)` where a non-Continue return blocks the pickup.

**Исправление.**

```
Make the pickup path fail open like the restrict path: drop the Authorized gate from OnWeaponTouch and rely on RestrictClientHasRestrict() alone, or make Authorized mean "auth attempted" by setting it on every terminal path (error branch and the early returns in ClientAuth) and re-running ClientAuth from OnClientPostAdminCheck so a client whose SteamID was not ready at PutInServer is retried.
```

> **Поправка верификатора.** The finding's own headline trigger is REFUTED and must be replaced. DB == null is retried: database.sp:107-113 SQL_Callback_CreateTables re-runs ClientAuth() for every in-game non-fake client once the table exists, so the MySQL-connect window self-heals; and database.sp:31-34 SetFailStates if the connect fails outright, so DB is never null for long. The surviving triggers are: (1) client.sp:49-50 — GetSteamAccountID(client) returns 0 (Steam backend not validated at OnClientPutInServer / sv_lan) -> ClientAuth returns without issuing the query and nothing ever retries -> that player cannot pick up ANY item for his whole session; (2) client.sp:57-61 — a transient SQL error returns before setting Authorized, with no retry, same permanent outcome; (3) client.sp:21-22 — OnClientPutInServer returns early for fake clients, so bots are permanently pickup-blocked. Also note the same gate is duplicated in transfer.sp:17, so an unauthorized client cannot even receive an admin transfer. The fix should keep the gate for the normal auth race (it is a deliberate guard against grabbing an item before the eban query lands) and only add a terminal/retry state on the error paths.

### 6. OnButtonPress does not check HalfZombie[] - a half-zombie can fire an item he was given

- **id**: `halfzombie-button-press-unblocked` | **место**: `addons/sourcemod/scripting/entWatch/sdkhook.sp:51` -> `OnButtonPress()`
- **ось/инвариант**: invariant-I2 | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** CLAUDE.md domain rule 2 requires the half-zombie block on all three routes (pickup, button press, trigger touch). OnWeaponTouch (sdkhook.sp:15-18) and OnTriggerTouch (sdkhook.sp:129-132) both have the `#if defined HALFZOMBIE if(HalfZombie[...]) return Plugin_Handled;` block; OnButtonPress has only the restrict check and no half-zombie check at all. Any route that hands an item to a client without going through SDKHook_WeaponCanUse therefore leaves a half-zombie able to fire it - and the admin transfer route is exactly such a route: it validates the receiver against RestrictClientHasRestrict and Clients[].Authorized but not against HalfZombie[].

**Триггер.** Admin (ADMFLAG_GENERIC) runs `sm_etransfer <owner> <halfzombie>` -> Command_Transfer accepts the receiver (transfer.sp:17 checks restrict + Authorized only) -> TransferItem -> EquipPlayerWeapon(receiver, weapon) (transfer.sp:84) -> SDKHook_WeaponEquipPost -> OnWeaponPickup sets Items[item].Owner = receiver (sdkhook.sp:30). WeaponCanUse is never consulted on this path. The half-zombie then presses E -> OnButtonPress: RoundStarted ok, Owner == activator ok, not restricted, ItemIsReady ok -> Plugin_Continue, item fires and the use is counted.

**Доказательства.** sdkhook.sp:51-84 (no HalfZombie check) vs sdkhook.sp:15-18 and sdkhook.sp:129-132 (checks present); transfer.sp:15-18 receiver validation without HalfZombie; transfer.sp:84 EquipPlayerWeapon; halfzombie.sp:11 `bool HalfZombie[MAXPLAYERS + 1]`; CLAUDE.md "Restricted players ... button presses in OnButtonPress() ... The same applies to ZR half-zombie classes".

**Исправление.**

```
Mirror the guard already used in the other two hooks, immediately after the restrict check in OnButtonPress:

	if(RestrictClientHasRestrict(activator))
		return Plugin_Handled;

	#if defined HALFZOMBIE
	if(HalfZombie[activator])
		return Plugin_Handled;
	#endif

(The receiver check in transfer.sp is a separate, complementary fix owned by that file.)
```

> **Поправка верификатора.** Trigger should say ADMFLAG_GENERIC (transfer.sp:3 RegAdminCmd("sm_etransfer", ..., ADMFLAG_GENERIC)), and should note the route requires an admin action — this is not a player-reachable exploit. The claimed sm_espawn route does NOT work as an independent path: spawn.sp:38-78 SpawnItem only fires a point_template near the receiver, it never sets Owner; the receiver still has to physically pick the weapon up, which goes through OnWeaponTouch and IS half-zombie blocked.

### 7. prop_d prefix match also catches prop_dynamic / prop_detail, disabling the assist on ordinary props

- **id**: `assist-propd-prefix-overbroad` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:262` -> `AssistUseIsValidTarget()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** `strncmp(classname, "prop_d", 6, false)` is meant to catch the +USE-able door class prop_door_rotating (the module hooks exactly that class at assist_use.sp:32), but a 6-character prefix also matches prop_dynamic, prop_dynamic_override and prop_detail - the most common decorative entities in ZE maps, none of which can be +USEd. Aiming at any of them suppresses the assist. Together with the infinite ray this makes the suppression fire across most of a map's geometry.

**Триггер.** Player holds one item, crosshair rests on any solid prop_dynamic (a crate, a statue, a rock - any distance, because the ray is infinite). He presses E -> AssistUseIsValidTarget -> GetEntityClassname returns "prop_dynamic" -> `!strncmp(classname, "prop_d", 6, false)` is true -> return false -> the assist never fires and the item does not activate.

**Доказательства.** assist_use.sp:262-265; assist_use.sp:32 `HookEntityOutput("prop_door_rotating", "OnOpen", AssistUseOnPropDoorOpen);` showing the intended target class; assist_use.sp:252 the infinite ray that widens the blast radius of the mismatch.

**Исправление.**

```
Match the door classes explicitly instead of a truncated prefix:

if(!strncmp(classname, "prop_door", 9, false))
	return false;

(prop_door_rotating and prop_door_rotating_checkpoint are both covered; prop_dynamic/prop_detail are not.)
```

### 8. Assist "Use" on a non-+USEable func_door counts a use the map never performs

- **id**: `assist-door-use-counted-without-effect` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:226` -> `AssistUseInputByName()`
- **ось/инвариант**: invariant-I4 | **уверенность**: likely | **вердикт верификатора**: UNCERTAIN

**Проблема.** For an item whose bound button is a func_door, AssistUseInputByName unconditionally sends the "Use" input. CBaseEntity::InputUse calls the virtual Use(), so SDKHook_Use -> OnButtonPress runs FIRST and (for a non-Compare/Relay item) calls APIOnClientItemUse + ItemReload + PrintToChatItemAction and returns Plugin_Continue - and only then does CBaseDoor::Use execute and immediately bail out, because the activator is a player and the door lacks SF_DOOR_PUSE (256), or because the toggle state does not allow use. entWatch has now announced a use, fired the API forward and started the cooldown for an activation the map never performed. This is precisely the I4 failure direction CLAUDE.md warns about (entWatch ahead of the map). Note that a real player press cannot produce this: CBaseDoor::ObjectCaps only advertises FCAP_IMPULSE_USE when SF_DOOR_PUSE is set, so the engine would never route a genuine +USE to such a door.

**Триггер.** Map item whose button is resolved to a func_door (Timer_ItemFindButton's door priority, items.sp:281-299, or an explicit buttonid) and whose door has no "Use Opens" flag, or is currently open/moving. Owner presses E -> AssistUseOnPlayerRunCmdPost -> AssistUse -> AssistUseInputByName func_door branch -> AcceptEntityInput(door,"Use",Owner,Owner) -> CBaseEntity::InputUse -> CBaseDoor::Use -> SDKHook_Use fires OnButtonPress (counts + announces + ItemReload) -> CBaseDoor::Use returns at doors.cpp:725-730 having only played a locked sound. Item shows a cooldown in the HUD; nothing happened in the map.

**Доказательства.** assist_use.sp:226-231 (func_door branch, unconditional "Use"); sdkhook.sp:79-83 (use counted before the engine acts); C:/develop/hl2_src-leak-2017/src/game/server/baseentity.cpp:4009-4012 InputUse -> virtual Use; doors.cpp:718-730 `if ( m_hActivator != NULL && m_hActivator->IsPlayer() && HasSpawnFlags( SF_DOOR_PUSE ) == false ) { PlayLockSounds(...); return; }`; doors.cpp:733-750 (bAllowUse only for TS_AT_BOTTOM / NO_AUTO_RETURN+TS_AT_TOP); doors.h:30 `#define SF_DOOR_PUSE 256`; doors.h:67-73 ObjectCaps adds FCAP_IMPULSE_USE only with SF_DOOR_PUSE.

**Исправление.**

```
Refuse the forced press when the door cannot answer it, in the func_door branch:

if(strncmp(classname, "func_door", 9, false) == 0)
{
	if(!(GetEntProp(Items[item].Button, Prop_Data, "m_spawnflags") & 256)) // SF_DOOR_PUSE
		return false;

	AcceptEntityInput(Items[item].Button, "Use", Items[item].Owner, Items[item].Owner);
	return true;
}

(The same spawnflag test is already used correctly at assist_use.sp:267-275.)
```

> **Поправка верификатора.** The finding conflates two different holes and only one is assist-specific. (a) The SF_DOOR_PUSE half IS assist-specific — the engine would never route a player +USE to such a door. (b) The 'door is open/moving' half (doors.cpp:732-750, bAllowUse false for TS_GOING_UP / TS_AT_TOP without SF_DOOR_NO_AUTO_RETURN) is NOT assist-specific: a genuine +USE on a PUSE door in that state reaches CBaseDoor::Use, fires SDKHook_Use, and entWatch counts the use just the same. If (b) matters it is a general ItemIsReady/func_door defect in items.sp:447-489, not an assist_use bug, and the proposed spawnflag-only fix would not address it.

### 9. Half-zombie detection ignores ZR's mother-zombie class substitution

- **id**: `halfzombie-mother-class-mismatch` | **место**: `addons/sourcemod/scripting/entWatch/halfzombie.sp:62` -> `HalfZombieDeterminateClient()`
- **ось/инвариант**: invariant-I2 | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** HalfZombieDeterminateClient decides from ZR_GetZombieClass(client) - the class the player selected - but ZR applies a different class for mother zombies: ClassOnClientInfected() replaces classindex with a random or configured mother class when motherzombie is true (and stashes the selected one in ClassSelectedNext). entWatch is called from ZR_OnClientInfect, which receives motherInfect as a parameter and ignores it. So for a mother infect the flag is computed from a class the player will not be playing. Half-zombie classes are not excluded from the random mother pick either - ZR's own code treats ZR_CLASS_FLAG_HALF_ZOMBIE as separate from ZR_CLASS_SPECIALFLAGS (classevents.inc:674) while the random mother filter only denies ZR_CLASS_SPECIALFLAGS (classevents.inc:566).

**Триггер.** zr_classes_default_mother_zombie is "random" (or "motherzombies"). Player P has a non-frazzle zombie class selected. Round starts, ZR picks P as mother zombie -> ZR_OnClientInfect(P, ..., motherInfect=true) -> entWatch's HalfZombieDeterminateClient reads ZR_GetZombieClass(P) = the non-frazzle selected class -> HalfZombie[P] = false. ZR then substitutes a random zombie class that happens to be a frazzle/half-zombie class (classevents.inc:578-588). P is now a half-zombie whom entWatch does not recognise: OnWeaponTouch and OnTriggerTouch let him take items. The mirror case (selected class is frazzle, mother class is not) wrongly locks a normal mother zombie out of items.

**Доказательства.** halfzombie.sp:55-69 (uses ZR_GetZombieClass, ignores the motherInfect parameter available at halfzombie.sp:30); C:/develop/sg-zr-swzedition/addons/sourcemod/scripting/include/zr/class.zr.inc:76-83 ZR_GetZombieClass = "current zombie class index that the player is using"; zr/playerclasses/classevents.inc:531-589 ClassOnClientInfected replaces classindex for mother zombies; classevents.inc:566 (random mother filter denies only ZR_CLASS_SPECIALFLAGS) vs classevents.inc:674 (ZR_CLASS_SPECIALFLAGS + ZR_CLASS_FLAG_HALF_ZOMBIE treated as distinct); ZR's own half-zombie test uses the ACTIVE class: apply.inc:41-52 ClassGetActiveIndex + ZR_GetClassDisplayName + "frazzle".

**Исправление.**

```
Determine the flag after ZR has applied the class rather than in the pre-forward - e.g. re-evaluate in ZR_OnClientInfected/post (or one frame later via RequestFrame) using the active class, which is what ZR itself compares:

// after the class is applied
ZR_GetClassDisplayName(ZR_GetActiveClass(client), buffer, sizeof(buffer), ZR_CLASS_CACHE_MODIFIED);

If the pre-forward must stay, at minimum honour motherInfect and re-check the class once the infection has actually completed.
```

> **Поправка верификатора.** One evidence citation is wrong and must not be repeated in the fix write-up: classevents.inc:~674 (`ZR_CLASS_SPECIALFLAGS + ZR_CLASS_FLAG_HALF_ZOMBIE`) sits inside a block that is COMMENTED OUT in this fork — the whole half-zombie-ratio section (classevents.inc ~641-694) is wrapped in /* ... */, so it proves nothing about live behaviour. The correct citation for 'HALF_ZOMBIE is not a special flag' is playerclasses.inc:68 vs :71. Also note ZR's own half-zombie test at zr/playerclasses/apply.inc:41-52 uses ZR_GetClassDisplayName(ClassGetActiveIndex(...)) — the ACTIVE class — which is the behaviour entWatch should mirror. Finally, halfzombie.sp:65 passes cacheType 1 explicitly, which is ZR_CLASS_CACHE_MODIFIED (class.zr.inc:32), i.e. the same default ZR uses — that part is fine.

### 10. entWatch_OnClientItemDrop never fires for death / disconnect / transfer / round-end drops

- **id**: `itemdrop-bypasses-drop-hook-api-forward-lost` | **место**: `addons/sourcemod/scripting/entWatch/sdkhook.sp:36` -> `OnWeaponDrop()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** APIOnClientItemDrop() is called from exactly one place, OnWeaponDrop (sdkhook.sp:48), which is the SDKHook_WeaponDropPost callback hooked at client.sp:35. Every plugin-initiated drop goes through ItemDrop() (items.sp:434-445), which calls SDKHooks_DropWeapon(owner, weapon, NULL_VECTOR, NULL_VECTOR) with only four arguments - and that native's `bypassHooks` parameter DEFAULTS TO TRUE. With bypassHooks set, the extension calls SH_MCALL(pPlayer, Weapon_Drop), i.e. SourceHook's call-the-original path, which skips every hook on Weapon_Drop. So OnWeaponDrop does not run, and the public forward entWatch_OnClientItemDrop is never fired for a drop caused by death, disconnect, admin transfer, or the round-end drop of transferred items. Consumer plugins (the include is documented as already consumed by other plugins on the server) therefore see entWatch_OnClientItemPickup with no matching drop. entWatch's own state is fine - ItemDrop clears Owner and Transfered itself at items.sp:441-442 - which is why this has stayed invisible.

**Триггер.** Any player holding a droppable (SLOT_PRIMARY/SECONDARY/GRENADES) item dies: player_death -> entWatch.sp:157-161 OnPlayerDeath -> client.sp:102-111 ClientLostHandleAction(client, ACTION_DEATH) -> items.sp:434-445 ItemDrop -> items.sp:439 SDKHooks_DropWeapon(...) with 4 args -> sdkhooks/natives.cpp:292-295 `if (params[0] < 5 || params[5] != 0) SH_MCALL(pPlayer, Weapon_Drop)(...)` -> SDKHook_WeaponDropPost is bypassed -> sdkhook.sp:36-49 OnWeaponDrop never runs -> sdkhook.sp:48 APIOnClientItemDrop is never reached -> api.sp:55 forward not fired. Same on disconnect (entWatch.sp:163-171 -> ACTION_DISCONNECT), on transfer (transfer.sp:66 ItemDrop) and at round end (transfer.sp:106-116 TransferDropAllTransferedItems).

**Доказательства.** sdkhook.sp:36-49 (OnWeaponDrop, the sole caller of APIOnClientItemDrop at :48); client.sp:35 `SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop)`; items.sp:439 `SDKHooks_DropWeapon(Items[item].Owner, Items[item].Weapon, NULL_VECTOR, NULL_VECTOR);` - four arguments; C:/develop/sm-1.13/include/sdkhooks.inc:441-452 `@param bypassHooks If true, bypass SDK hooks on Weapon Drop` / `native void SDKHooks_DropWeapon(int client, int weapon, const float vecTarget[3]=NULL_VECTOR, const float vecVelocity[3]=NULL_VECTOR, bool bypassHooks = true);`; C:/develop/sm1.13-botox/source/sourcemod/extensions/sdkhooks/natives.cpp:292-296; api.sp:55 APIOnClientItemDrop; include/entWatch.inc:51 `forward void entWatch_OnClientItemDrop(int client, int item);`.

**Исправление.**

```
Fire the forward from the place that actually performs the drop, leaving the hook bypassed so chat behaviour does not change:

// items.sp, in ItemDrop(), after SDKHooks_DropWeapon
int owner = Items[item].Owner;
Items[item].Owner = 0;
Items[item].Transfered = false;
APIOnClientItemDrop(owner, item);

The alternative - passing `false` as the fifth argument to SDKHooks_DropWeapon - also works but must be recomputed first: with the hook no longer bypassed, OnWeaponDrop would additionally run PrintToChatItemAction(item, ACTION_DROP) (sdkhook.sp:45), so ClientLostHandleAction would print both ACTION_DEATH and ACTION_DROP, and transfer.sp:66 would emit an unsuppressed drop line because its DISPLAY_CHAT suppression at transfer.sp:82-83 only starts after the ItemDrop call.
```

### 11. RemoveConfig() shifts Configs[] down but never decrements Configs_Count, and reads one element past the live range

- **id**: `helpers-removeconfig-no-count-decrement` | **место**: `addons/sourcemod/scripting/entWatch/helpers.sp:26` -> `RemoveConfig()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** RemoveConfig (helpers.sp:26-34) is the deletion counterpart of ItemRemove (items.sp:606-613) and is written the same way -- `for(int i = config; i < Configs_Count; i++) Configs[i] = Configs[i + 1];` -- except that ItemRemove ends with `Items_Count--` (items.sp:612) and RemoveConfig has no `Configs_Count--`. Two consequences follow. (1) The delete does not delete: the array is compacted but the count is not, so the tail slot Configs[Configs_Count - 1] is overwritten with the contents of the never-initialised slot Configs[Configs_Count] and remains counted. Every subsequent `for(i = 0; i < Configs_Count; i++)` walk still visits it -- admin_menu.sp:770-779 (config list, which renders it as "Unknown item" because ShortName and Name are empty), admin_menu.sp:1035 (AdminConfigBrowseItems, which writes a junk block into the saved map config), api.sp:88 entWatch_GetConfigsCount, dump.sp:11. Repeated deletions leave a growing tail of phantom configs and permanently consume slots, so after MAX_CONFIGS deletions admin_menu.sp:807 `if(Configs_Count < MAX_CONFIGS)` refuses to add any new config for the rest of the map. (2) The final iteration always reads Configs[Configs_Count], which is out of bounds when Configs_Count == MAX_CONFIGS; SourcePawn emits a bounds check for a runtime-indexed fixed array, so on a map with 50 configs the delete aborts with 'Array index is out of range' after having already shifted part of the array. The paired function proves this is a missing decrement rather than a design choice -- CLAUDE.md's own list of fixable defects names 'a missing counter decrement' explicitly.

**Триггер.** An admin with ADMFLAG_GENERIC runs sm_eadmin -> Configs -> picks any config -> selects the first entry of the config menu (delete). AdminMenuInit -> ConfigsMenu -> ConfigsMenu_Handler -> ConfigMenu_Handler MenuAction_Select case 0 (admin_menu.sp:900-905) -> RemoveConfig(EditClientsConfigs[client].Config) -> helpers.sp:28-32 shifts Configs[] down and returns with Configs_Count unchanged. The admin immediately sees the config list (admin_menu.sp:770) still N entries long with a blank "Unknown item" at the end, and if they then Save (AdminConfigSave -> AdminConfigBrowseItems, admin_menu.sp:1032-1086) that blank block is written into configs/entwatch/<map>.cfg.

**Доказательства.** helpers.sp:26-34 `stock void RemoveConfig(int config) { for(int i = config; i < Configs_Count; i++) { Configs[i] = Configs[i + 1]; } RemoveItemByConfig(config); }` -- no `Configs_Count--`; contrast items.sp:606-613 `void ItemRemove(int item) { for(int i = item; i < Items_Count; i++) { Items[i] = Items[i + 1]; } Items_Count--; }`. Caller: admin_menu.sp:903. Count consumers that then see the phantom entry: admin_menu.sp:770-779, admin_menu.sp:1035, api.sp:88, dump.sp:11, hud.sp:35. Slot exhaustion: admin_menu.sp:807. Array bound: config.sp:1 `#define MAX_CONFIGS 50`, config.sp:33 `Config Configs[MAX_CONFIGS];`.

**Исправление.**

```
Add `Configs_Count--;` after the shift loop and stop the loop one short of the end so the out-of-range read disappears: `for(int i = config; i < Configs_Count - 1; i++) Configs[i] = Configs[i + 1]; Configs_Count--;` (mirroring ItemRemove, whose loop has the same one-past-the-end read at items.sp:610 and should be fixed in the same batch). Note the recompute rule: with the count fixed, RemoveItemByConfig's re-basing of Items[].Config (helpers.sp:46-49) becomes correct as written, so do not touch it in the same change -- but its ItemClear-without-ItemUnhook at helpers.sp:42 leaves the deleted config's SDKHook_Use installed on a button that ItemsGetByButton can no longer find, which is a separate finding and needs its own trigger line.
```

### 12. IsClientInGame(0) in the ban/unban callbacks throws and locks the eban module permanently

- **id**: `eban-callback-isclientingame-zero` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:316` -> `SQL_Callback_BanClient / SQL_Callback_UnBan()`
- **ось/инвариант**: async | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The callbacks resolve the target with GetClientOfUserId() (restrict.sp:291, :387) but never test the result before restrict.sp:316 `if(IsClientInGame(client))` / restrict.sp:405 `if(IsClientInGame(client))`. GetClientOfUserId returns 0 when the player has left, and IsClientInGame(0) is a hard native error, not a false. The throw aborts the callback before `LastQueryEBanNotCompleted = false` (restrict.sp:334 / :413), so the module-wide serialization flag stays true forever (it is a plain global, restrict.sp:228, never reset on map start). Every later sm_eban / sm_uneban / sm_addeban / sm_deleban then bails at restrict.sp:252/359/435/556 with "The last request has not been completed yet" until the plugin is reloaded. The ban itself is already committed in the DB, but the "Ban success" announcement (restrict.sp:324) and the Restricts[] cache update never happen.

**Триггер.** Admin runs `sm_eban #12 60` on player P. RestrictClientBan() (restrict.sp:230) sets LastQueryEBanNotCompleted=true at :258 and queues the INSERT at :284 with P's userid in the DataPack. P disconnects (ragequit after being restricted, or the threaded INSERT is delayed by a busy/reconnecting MySQL worker) before the callback runs. SQL_Callback_BanClient -> GetClientOfUserId(P) == 0 -> IsClientInGame(0) -> ThrowNativeError -> callback aborted -> flag stuck. Same path via sm_uneban -> SQL_Callback_UnBan:405.

**Доказательства.** restrict.sp:291 `int client = GetClientOfUserId(pack.ReadCell());`; restrict.sp:316 `if(IsClientInGame(client))`; restrict.sp:334 `LastQueryEBanNotCompleted = false;` (only reached after :316); restrict.sp:387/:405/:413 the identical shape in SQL_Callback_UnBan. Native semantics: C:/develop/sm-1.13/include/clients.inc — IsClientInGame documents "@error Invalid client index"; core impl C:/develop/sm1.13-botox/source/sourcemod/core/logic/smn_players.cpp:467-473 `if ((index < 1) || (index > playerhelpers->GetMaxClients())) return pCtx->ThrowNativeError("Client index %d is invalid", index);`. Contrast with the correct shape in client.sp:63-66 which returns on `client == 0`.

**Исправление.**

```
Validate before use in both callbacks, and reset the gate first so an abort cannot wedge the module:
```
LastQueryEBanNotCompleted = false;   // move to the top of the callback, before any client work
...
int client = GetClientOfUserId(pack.ReadCell());
...
if(client && IsClientInGame(client))
{
    Restricts[client].Admin = adminid;
    ...
}
```
Apply the same to SQL_Callback_UnBan (restrict.sp:405).
```

> **Поправка верификатора.** Severity: major, not critical. The trigger is a race, not a deterministic path — the target must leave between the DB_Query at restrict.sp:284 (DBPrio_High) and the callback, i.e. inside one threaded round-trip. On a local SQLite backend that is one or two frames; on a loaded/remote MySQL it can be hundreds of ms, and the same window exists for the DELETE in RestrictClientUnBan (restrict.sp:379, DBPrio_Normal). Everything else in the finding — the mechanism, the permanent wedge, the fix, and the observation that the *error* branches at :306/:396 are already correctly guarded with `admin &&` — checks out. Note the fix must also keep the announcement: moving the flag reset to the top is right, but `PrintToChatAll2` at :324 must still run, so the guard belongs on the `Restricts[client]` write only.

### 13. `strlen(ip) == 16` on a char[16] is unsatisfiable - IP-only ebans/unebans are impossible

- **id**: `addban-ip-never-valid` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:429` -> `RestrictAddBan / RestrictDeleteBan()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** `bool ipIsValid = (strlen(ip) == 16);` (restrict.sp:429 and :550). The buffer is `char ip[16]` filled by `GetCmdArg(3, ip, sizeof(ip))` (:143) / `GetCmdArg(2, ip, sizeof(ip))` (:160), so strlen(ip) is at most 15 — the predicate is unsatisfiable and ipIsValid is a compile-time-constant false. Therefore: the `id && ipIsValid` branches (:446, :567, :597) and the ip-only branches (:454, :575, :605) are dead code; an admin supplying only an IP always gets "Invalid SteamID and IP-adress" (:432/:553); and the documented `sm_addeban <minutes> [steamid] [ip]` / `sm_deleban [steamid] [ip]` IP forms do not exist. Combined steamid+ip still "works" only by accident, because the INSERT at :486 passes `ip` regardless of ipIsValid. A latent second-order effect: if ipIsValid is ever fixed without touching the callbacks, id may then legitimately be 0 and `ClientGetByAccount(0)` (:525, :649) matches the first client whose Account is still 0 (a bot or a not-yet-authorized player), writing the restrict onto the wrong slot.

**Триггер.** Admin (rcon) runs `sm_deleban "" 84.17.45.1` to lift a restrict recorded only by IP. Command_DeleteBan:159-161 -> RestrictDeleteBan("", "84.17.45.1", admin) -> :549 id = 0 -> :550 ipIsValid = false (strlen == 10 != 16) -> :551 `if(!id && !ipIsValid)` -> "Invalid SteamID and IP-adress" and return. The eban stays in the DB with no way to remove it in game.

**Доказательства.** restrict.sp:429 and :550 `bool ipIsValid = (strlen(ip) == 16);`; buffers declared at :139 `char ip[16];` and :158 `char steamid[64], ip[16];`; filled at :143 and :160 with sizeof(ip). GetCmdArg writes at most maxlength-1 chars: core impl C:/develop/sm1.13-botox/source/sourcemod/core/smn_console.cpp:852-868 `pContext->StringToLocalUTF8(params[2], params[3], arg ? arg : "", &length)` (and it stores "" for a missing argument, so ip is never uninitialized).

**Исправление.**

```
Validate the string, not its buffer size — e.g. `bool ipIsValid = (strlen(ip) > 6 && StrContains(ip, ".") != -1);` or a proper dotted-quad check. If the fix makes id == 0 reachable, also guard ClientGetByAccount: `int client = id ? ClientGetByAccount(id) : 0;` at :525 and :649.
```

### 14. SQL_LockDatabase + SQL_Query on the main thread stalls the server for the round-trip

- **id**: `blocking-sql-main-thread` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:456` -> `RestrictAddBan / RestrictDeleteBan()`
- **ось/инвариант**: database | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** restrict.sp:456-458 and :578-580 take the connection lock and run a synchronous query on the game thread. Per the include, the lock itself blocks: if a threaded query is in flight the main thread *pauses until it finishes*, and only then does the synchronous SELECT round-trip run. Everything else in this module is already threaded (DB_Query / DB.Query), so this pair is the only place that can freeze the tick — and it sits behind two remote round trips on a MySQL backend. This is the defect CLAUDE.md already records ("Threaded queries only… this is a defect to fix, not a compromise"); confirmed here with exact lines. Note the failure path is also silently wrong in RestrictAddBan: if SQL_Query returns null because the query errored, `if(results && results.RowCount)` (:460) falls into the else branch and inserts a duplicate ban as if no ban existed.

**Триггер.** Any rcon admin runs `sm_addeban 60 STEAM_1:0:12345` or `sm_deleban STEAM_1:0:12345` while another entWatch query (a joining player's SELECT_BANS, client.sp:52) is being serviced by the DB worker: SQL_LockDatabase(DB) at :456/:578 parks the main thread until that finishes, then SQL_Query adds its own full round trip. On a remote/loaded MySQL this is tens to hundreds of ms of frozen server per invocation.

**Доказательства.** restrict.sp:456-458 `SQL_LockDatabase(DB); DBResultSet results = SQL_Query(DB, buffer); SQL_UnlockDatabase(DB);`; restrict.sp:578-580 identical. C:/develop/sm-1.13/include/dbi.inc:955-969 SQL_LockDatabase: "If the lock cannot be acquired, the main thread will pause until the threaded operation has concluded… Leaving a lock on a database and then executing a threaded query results in a dead lock!". Working async template already present in the same file: restrict.sp:284 DB_Query(...) and :615 DB.Query(...).

**Исправление.**

```
Convert both to the async shape used everywhere else: issue the existence SELECT with DB_Query()/DB.Query() carrying the DataPack, and perform the INSERT/DELETE from inside that callback (chained queries), releasing LastQueryEBanNotCompleted in the terminal callback. That also removes the result-set leak below and the null-result mis-branch at :460.
```

> **Поправка верификатора.** Scope note, not a defect correction: the blocking-SQL half of this is already recorded in CLAUDE.md ("Database" section: "RestrictAddBan() / RestrictDeleteBan() currently do a blocking SQL_LockDatabase + SQL_Query on the main thread — this is a defect to fix") and in "Direction / planned work". It survives as a valid finding because CLAUDE.md files it as a known defect, not as intended behaviour — but it is not a discovery. The part worth acting on first is the null-result mis-branch at restrict.sp:460, which is NOT documented anywhere.

### 15. DBResultSet from the synchronous SQL_Query is leaked on the normal path of both functions

- **id**: `sqlquery-resultset-leak` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:467` -> `RestrictAddBan / RestrictDeleteBan()`
- **ось/инвариант**: handles | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** SQL_Query returns an owned handle that the plugin must close (unlike threaded callbacks, whose result set SourceMod destroys automatically). RestrictAddBan deletes it only inside the "a ban already exists" branch (restrict.sp:467); on the *normal* path — a non-null result set with 0 rows — the else branch at :469-487 returns without deleting, so every successful sm_addeban leaks one handle. RestrictDeleteBan (:579) never deletes it on any path: neither the `!results || !results.RowCount` branch (:582-589) nor the delete branch (:590-616). Handles accumulate for the process lifetime and count against the plugin's handle limit.

**Триггер.** Any rcon admin runs `sm_addeban 60 <new steamid>` (target not yet banned): :457 allocates the DBResultSet, :460 `results.RowCount` is 0 so control goes to :469, the function returns at :487 with the handle still open. Or any `sm_deleban <steamid>`: :579 allocates, both branches return without delete. Repeat per admin action.

**Доказательства.** restrict.sp:457 `DBResultSet results = SQL_Query(DB, buffer);` and :467 `delete results;` (only inside `if(results && results.RowCount)`); restrict.sp:579 with no `delete results` anywhere in :582-616. C:/develop/sm-1.13/include/dbi.inc:707-710 SQL_Query: "A new Query Handle on success… The Handle must be freed with CloseHandle()." Contrast dbi.inc:408-409 (Database.Query): "The result handle returned through the callback is temporary and destroyed at the end of the callback" — which is why the threaded callbacks in this file correctly do not delete `results`.

**Исправление.**

```
Preferably remove both synchronous queries (see blocking-sql-main-thread). If kept as-is, add `delete results;` on every exit path — one `delete results;` immediately after the RowCount decision in each function, before the branch bodies use anything else from it.
```

### 16. INSERT_BAN writes the admin's name into `pname` and the target's name into `aname`

- **id**: `insert-ban-name-columns-swapped` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:284` -> `RestrictClientBan()`
- **ось/инвариант**: database | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** names[0] is the ADMIN (restrict.sp:268 `GetClientName(admin, names[0], ...)`) and names[1] is the TARGET (:269). namesDb[0]/namesDb[1] are their escaped copies (:271-272). The INSERT then binds pname <- namesDb[0] (admin) and aname <- namesDb[1] (target) while pid <- Clients[client].Account (target) and aid <- Clients[admin].Account (admin). So the identifier columns and the name columns describe different people: every row in `ebans` records the banning admin as the banned player's name and vice versa. The DataPack/chat/log path is consistent (`Ban success`, names[0]=admin then names[1]=target — translations/entWatch.phrases.txt:113-118), which is exactly why nobody noticed: only the DB is wrong, and `pname` is the sole human-readable record of who was restricted. CLAUDE.md plans a web panel over this table, so it will surface there.

**Триггер.** Admin "hEl" runs `sm_eban Vasya 60`. RestrictClientBan:268-269 fills names[0]="hEl", names[1]="Vasya" -> :284 INSERT (pid=Vasya's account, pname='hEl', pip=Vasya's ip, aid=hEl's account, aname='Vasya'). Every ban row is written that way. With admin == 0 (console) pname additionally becomes the server hostname, since GetClientName(0) returns the `hostname` cvar (smn_players.cpp:292-309).

**Доказательства.** restrict.sp:2 `#define INSERT_BAN "INSERT INTO `ebans` (`pid`, `pname`, `pip`, `aid`, `aname`, `duration`, `expires`) VALUES (%i, '%s', '%s', %i, '%s', %i, %i);"`; restrict.sp:268-272 name/escape order; restrict.sp:284 `DB_Query(SQL_Callback_BanClient, pack, DBPrio_High, INSERT_BAN, Clients[client].Account, namesDb[0], ip, Clients[admin].Account, namesDb[1], duration * 60, expires);`. Column order from database.sp:64-71 / :80-88.

**Исправление.**

```
Swap the two escaped names at the call site (keep the DataPack order, which the chat/log messages depend on):
```
DB_Query(SQL_Callback_BanClient, pack, DBPrio_High, INSERT_BAN,
         Clients[client].Account, namesDb[1], ip,
         Clients[admin].Account, namesDb[0], duration * 60, expires);
```
```

### 17. INSERT_ADD_BAN interpolates the admin's player name and the typed IP unescaped

- **id**: `addban-unescaped-name-ip` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:486` -> `RestrictAddBan()`
- **ось/инвариант**: security | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** RestrictClientBan carefully escapes both names with DB.Escape (restrict.sp:271-272), but RestrictAddBan does not: `name` comes straight from GetClientName (:472) and `ip` straight from GetCmdArg (:143), and both are pasted into single-quoted `'%s'` slots (:486). A single apostrophe in the admin's Steam name terminates the string literal and the INSERT fails with a syntax error — the eban is silently not written and the admin only sees "Query failed" (SQL_Callback_AddBan:513-522). Beyond the accidental case, this is a genuine injection point: `ip` is fully attacker-controlled text (up to 15 chars) and `name` is a 31-char field the admin controls freely by renaming. Access is ADMFLAG_RCON, which lowers the security impact, but the same unescaped pattern is one copy-paste away from a lower-privilege command. The synchronous SELECTs at :446-455 and :567-575 interpolate `ip` the same way (currently unreachable only because ipIsValid is always false — see addban-ip-never-valid; fixing that makes those two WHERE clauses injectable).

**Триггер.** An in-game admin holding ADMFLAG_RCON whose Steam name is `O'Neill` runs `sm_addeban 60 STEAM_1:0:12345`. RestrictAddBan:472 name="O'Neill" -> :486 the query becomes `... aname = 'O'Neill' ...` -> MySQL/SQLite syntax error -> SQL_Callback_AddBan:513 error path -> "Query failed", no ban recorded. Deliberate variant: rename to `x', 0, 0, 0, -1); -- ` or pass a crafted `ip` argument to inject values.

**Доказательства.** restrict.sp:4 `#define INSERT_ADD_BAN "... VALUES (%i, '%s', %i, '%s', %i, %i);"`; restrict.sp:472 `GetClientName(admin, name, sizeof(name));` (no DB.Escape); restrict.sp:486 `DB_Query(SQL_Callback_AddBan, pack, DBPrio_Normal, INSERT_ADD_BAN, id, ip, Clients[admin].Account, name, duration * 60, expires);`. Correct pattern in the same file: restrict.sp:271-272 `DB.Escape(names[0], namesDb[0], sizeof(namesDb[]));`. C:/develop/sm-1.13/include/dbi.inc:367-386 Database.Escape — "If user input has a single quote in it, the quote needs to be escaped… SourceMod only guarantees properly escaped strings when the query encloses the string in single quotes."

**Исправление.**

```
Escape before formatting, exactly as RestrictClientBan does:
```
char nameDb[MAX_NAME_LENGTH * 2 + 1];
char ipDb[33];
DB.Escape(name, nameDb, sizeof(nameDb));
DB.Escape(ip,   ipDb,   sizeof(ipDb));
DB_Query(SQL_Callback_AddBan, pack, DBPrio_Normal, INSERT_ADD_BAN, id, ipDb, Clients[admin].Account, nameDb, duration * 60, expires);
```
and do the same for the `ip` interpolations at :446/:454/:567/:575/:597/:605 (or switch those to DB.Format, which escapes %s by default — dbi.inc:388-396).
```

> **Поправка верификатора.** Two corrections to the trigger and the impact statement. (1) The console variant of the injection is currently UNREACHABLE — restrict.sp:479 `GetClientUserId(admin)` throws for admin == 0 before :486 is ever reached (see eban-console-getclientuserid-zero), so the `name` = server-hostname case cannot fire today. The reachable trigger is exactly the one the finder gives second: an IN-GAME admin holding ADMFLAG_RCON whose Steam name contains an apostrophe runs `sm_addeban 60 <steamid>` -> restrict.sp:472 -> :486 -> syntax error -> SQL_Callback_AddBan:513-522 "Query failed", ban silently not written. (2) The `ip` interpolations at restrict.sp:446/:454/:567/:575/:597/:605 are dead today (ipIsValid is a constant false — see addban-ip-never-valid), so the only live unescaped `ip` is the one at :486. That means fixing addban-ip-never-valid first WITHOUT fixing this one opens six new injectable WHERE/DELETE clauses — the two findings must be fixed in the opposite order to the one the report lists them in.

### 18. Connect paths pass swapped `data` values, so a real MySQL connection is treated as SQLite

- **id**: `db-driver-flag-inverted` | **место**: `addons/sourcemod/scripting/entWatch/database.sp:38` -> `DatabaseConnect / ConnectCallBack()`
- **ось/инвариант**: database | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** DatabaseConnect passes data = 0 for the databases.cfg connection (database.sp:19) — the one case where the driver is unknown and must be probed — and data = 1 for the SQLite_UseDatabase path (:25), where the driver is sqlite by construction (dbi.inc:503-514 hardcodes `kv.SetString("driver", "sqlite")`). ConnectCallBack then runs its driver probe under `if(data == 1)` (:38-56), i.e. only on the branch that can never be anything but sqlite, and the `else` (:57-60) — reached by every databases.cfg connection — sets `SQLite = true` unconditionally. Result on a MySQL-backed server: the SQLite DDL branch (:64-71) creates the table (it happens to be valid MySQL, so nothing errors and the mistake stays invisible) *without* `DEFAULT CHARSET=utf8mb4`, and the whole MySQL branch — `SET NAMES utf8mb4`, `SET CHARSET utf8mb4`, `DB.SetCharset(utf8mb4)` (:76-78) — is skipped. Combined with db-charset-downgrade below, the connection ends up on 3-byte utf8.

**Триггер.** Server operator adds an `entwatch` MySQL block to databases.cfg (the documented production setup, CLAUDE.md "Database"). OnPluginStart:71 -> DatabaseConnect -> :17 SQL_CheckConfig("entwatch") true -> :19 Database.Connect(ConnectCallBack, "entwatch", 0) -> ConnectCallBack(db, "", 0) -> :38 `if(data == 1)` false -> :59 SQLite = true -> :62 `if(SQLite)` true -> the SQLite CREATE TABLE runs against MySQL and the charset setup at :76-78 is never executed.

**Доказательства.** database.sp:19 `Database.Connect(ConnectCallBack, "entwatch", 0);`; database.sp:25 `ConnectCallBack(DB, buffer, 1);`; database.sp:38-60 the probe/else; database.sp:62 `if(SQLite)`. SQLite_UseDatabase is a fixed-driver stock: C:/develop/sm-1.13/include/dbi.inc:503-514. The `SQLite` global has no other reader (grep: database.sp:5,46,50,59,62 only), so the blast radius is exactly the DDL + charset choice.

**Исправление.**

```
Swap the two literals — pass 1 from Database.Connect (probe the driver) and 0 from the SQLite_UseDatabase call (known sqlite) — or, clearer, drop the `data` flag entirely and always probe:
```
DBDriver driver = DB.Driver;
char ident[16];
driver.GetIdentifier(ident, sizeof(ident));
SQLite = (strcmp(ident, "sqlite", false) == 0);
```
```

### 19. Unconditional DB.SetCharset("utf8") at the end of ConnectCallBack undoes the utf8mb4 setup

- **id**: `db-charset-downgrade` | **место**: `addons/sourcemod/scripting/entWatch/database.sp:92` -> `ConnectCallBack()`
- **ось/инвариант**: database | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** After the MySQL branch has set the connection charset to MYSQL_CHARSET (`utf8mb4`) three ways (database.sp:76, :77, :78), line 92 runs on *every* path and sets it back to `"utf8"` — MySQL's 3-byte utf8mb3. Any 4-byte UTF-8 sequence then cannot be transmitted: MySQL rejects the statement with error 1366 "Incorrect string value" under the default STRICT_TRANS_TABLES, or truncates the name in non-strict mode. Player names with emoji are extremely common on a public CS:S ZE server, and the name is written on the main eban path (INSERT_BAN, restrict.sp:284), so the restrict simply fails to persist and the admin sees "Query failed". This is independent of db-driver-flag-inverted — even with that fixed, line 92 still downgrades the connection.

**Триггер.** MySQL backend. Admin runs `sm_eban <player with a 🔥 in the Steam name> 60`. RestrictClientBan:269 GetClientName -> :272 DB.Escape (escaping does not alter the 4-byte sequence) -> :284 INSERT over a connection whose charset was forced to utf8mb3 at database.sp:92 -> MySQL 1366 -> SQL_Callback_BanClient:303 error path -> "Query failed" + LogError, no restrict written. The player keeps taking items.

**Доказательства.** database.sp:1 `#define MYSQL_CHARSET "utf8mb4"`; database.sp:76-78 `DB.Query(..., "SET NAMES 'utf8mb4'"); DB.Query(..., "SET CHARSET 'utf8mb4'"); DB.SetCharset(MYSQL_CHARSET);`; database.sp:92 `DB.SetCharset("utf8");` outside both branches. Native: C:/develop/sm-1.13/include/dbi.inc:358-365 Database.SetCharset — "Sets the character set of the connection. Like SET NAMES .. in mysql, but stays after connection problems." Writer of the affected column: restrict.sp:284 (pname/aname).

**Исправление.**

```
Delete database.sp:92. The MySQL branch already sets MYSQL_CHARSET at :78; SQLite ignores SetCharset. If a post-branch call is wanted for clarity, make it `DB.SetCharset(MYSQL_CHARSET);` and keep it inside the non-SQLite branch.
```

> **Поправка верификатора.** The claim "This is independent of db-driver-flag-inverted — even with that fixed, line 92 still downgrades the connection" is NOT established and I could not reproduce it. The `SET NAMES 'utf8mb4'` and `SET CHARSET 'utf8mb4'` at database.sp:76-77 are THREADED (DB.Query), so they are executed by the DB worker thread after ConnectCallBack has already returned, i.e. after line 92 — on a hypothetically-fixed MySQL branch the live session would end up utf8mb4 anyway, and line 92 would only govern the reconnect path (per dbi.inc:358-360, SetCharset "stays after connection problems"). The consequence that is real TODAY flows entirely through db-driver-flag-inverted: the SQLite branch is taken, no SET NAMES is ever issued, and SetCharset("utf8") at :92 is the only charset action on the connection. Practical implication: fixing db-driver-flag-inverted alone is not sufficient (line 92 still poisons reconnects) and fixing line 92 alone is not sufficient (the SET NAMES statements are still skipped) — both must be done together. Also note the MySQL branch is the only one where this matters at all; SQLite's driver ignores the character set.

### 20. `duration`/`expires` declared UNSIGNED but the code writes the -1 permanent sentinel

- **id**: `db-unsigned-permanent-sentinel` | **место**: `addons/sourcemod/scripting/entWatch/database.sp:70` -> `ConnectCallBack (schema)()`
- **ось/инвариант**: database | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** Both DDL variants declare `duration INTEGER UNSIGNED NOT NULL` and `expires INTEGER UNSIGNED NOT NULL` (database.sp:70-71 and :86-87), while the permanent-restrict sentinel is -1: RestrictGetExpireValue returns -1 for duration == -1 (restrict.sp:676) and `duration * 60` is then -60. Every SELECT also matches on that sentinel (`expires` = -1, restrict.sp:1,3,446,450,454,567,571,575,597,601,605 and client.sp:1). On SQLite this is harmless (INTEGER affinity, no range constraint), which is why it survives in production; on MySQL an unsigned column rejects -1 with error 1264 "Out of range value" under the default strict sql_mode, and silently clamps it to 0 in non-strict mode — in which case the row is stored with expires = 0, i.e. permanently expired, and the SELECT that looks for `expires = -1` never matches it. Either way permanent ebans do not work on MySQL. The same applies to any negative `duration * 60` produced by the chained-comparison hole above.

**Триггер.** MySQL backend (databases.cfg `entwatch` block). Admin runs `sm_eban Player -1` (permanent) or picks the last option in the admin menu (admin_menu.sp:230 passes -1). RestrictClientBan:261 expires = -1, :284 INSERT with duration = -60, expires = -1 -> strict mode: error 1264 -> SQL_Callback_BanClient:303 -> "Query failed", no ban; non-strict: stored as 0/0 -> the ban is invisible to SELECT_BANS (client.sp:1 `expires` = -1 OR `expires` > time) and to RestrictClientHasRestrict (restrict.sp:666).

**Доказательства.** database.sp:70-71 `\`duration\` INTEGER UNSIGNED NOT NULL, \`expires\` INTEGER UNSIGNED NOT NULL` and database.sp:86-87 the MySQL twin; restrict.sp:676 `return duration != -1 ? (time + duration * 60):-1;`; restrict.sp:284/:486 write those values; restrict.sp:666 and client.sp:1 read the -1 sentinel back. CLAUDE.md explicitly permits a schema redesign here ("the schema may be changed freely").

**Исправление.**

```
Drop UNSIGNED (signed INT holds the -1 sentinel and any epoch through 2038):
```
`duration` INT NOT NULL,
`expires`  INT NOT NULL,
```
in both DDL blocks. If the planned redesign happens, prefer an explicit nullable `expires` (NULL = permanent) plus an index on (`pid`, `expires`) and (`pip`, `expires`) — every lookup query filters on exactly those.
```

> **Поправка верификатора.** One clause is refuted: "The same applies to any negative `duration * 60` produced by the chained-comparison hole above" — there is no chained-comparison hole (see duration-chained-comparison; RestrictIsValidDuration rejects 0, negatives other than -1, and anything >= 525600), so -1/-60 from the deliberate permanent sentinel is the ONLY way a negative value reaches these columns. Also worth stating in the finding: because db-driver-flag-inverted forces the SQLite DDL onto MySQL, it is database.sp:70-71 — not :86-87 — that is actually executed against MySQL today, and it declares `INTEGER UNSIGNED` too, so the defect stands whichever DDL runs and cannot be dodged by fixing only one block.

### 21. A database error makes the plugin fail CLOSED (nobody can pick up items), not fail-open

- **id**: `db-error-fails-closed-on-pickup` | **место**: `addons/sourcemod/scripting/entWatch/database.sp:97` -> `SQL_Callback_CreateTables()`
- **ось/инвариант**: reliability | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The DB-loading state machine has no failure state and no retry. If CREATE TABLE errors, SQL_Callback_CreateTables logs and returns (database.sp:97-101) without setting DBLoaded and without ever re-authorizing clients — but DB is already non-null (:36), so every subsequent OnClientPutInServer still calls ClientAuth (client.sp:38 -> :43-52), whose SELECT_BANS then errors too (client.sp:57-61) and returns without setting Clients[].Authorized. And the item-pickup gate is `if(!Clients[client].Authorized) return Plugin_Handled;` (sdkhook.sp:9-10) — so a DB problem does not merely disable restricts, it stops every player on the server from picking up any special item, for the rest of the session, with no retry path. CLAUDE.md states the intent is the reverse: "No database -> no restricts (fail-open) is intended behaviour". Only the total-connect-failure case actually fails open, and only because SetFailState kills the plugin outright (database.sp:31-35).

**Триггер.** MySQL restarts, hits max_connections, or the account lacks CREATE on the schema. Case A: entWatch loads, ConnectCallBack:36 sets DB, the CREATE TABLE at :80 fails -> :97-101 logs and returns -> DBLoaded stays false -> a player joins -> client.sp:38 ClientAuth -> :52 SELECT_BANS against a non-existent table -> client.sp:57 LogError + return -> Authorized stays false -> the player touches the item weapon -> sdkhook.sp:9-10 Plugin_Handled -> nothing on the map can be picked up. Case B (no CREATE failure needed): the DB drops mid-map; every player who joins afterwards gets a failed SELECT_BANS and is locked out of items until they reconnect after the DB recovers.

**Доказательства.** database.sp:95-101 (error -> LogError -> return, DBLoaded untouched, no retry, APIOnDatabaseLoaded never fired); database.sp:36 `DB = db;` (DB non-null regardless); client.sp:43-44 `if(DB == null) return;` (passes), client.sp:55-61 (error -> return, Authorized untouched), client.sp:75 `Clients[client].Authorized = true;` only on the success path; sdkhook.sp:9-10 `if(!Clients[client].Authorized) return Plugin_Handled;`. Contrast restrict.sp:666 `return (DBLoaded && ...)` which *is* fail-open.

**Исправление.**

```
Give the auth attempt a terminal state instead of leaving it pending forever — mark the client as "auth finished, no restrict" on the SQL error path so the fail-open rule holds end to end:
```
// client.sp, SQL_Callback_SelectBans
if(error[0])
{
    LogError("SQL_Callback_SelectBans() : %s", error);
    int c = GetClientOfUserId(userid);
    if(c) Clients[c].Authorized = true;   // fail-open: no DB answer -> no restrict
    return;
}
```
and in database.sp add a bounded retry (or at minimum a one-shot re-run of the CREATE + the client loop) on the SQL_Callback_CreateTables error path so the plugin can recover without a map change. Note this also interacts with the planned "map-only restricts" item in CLAUDE.md.
```

### 22. SQL callback tests error[0] instead of results != null, then dereferences results

- **id**: `selectbans-checks-error-not-results` | **место**: `addons/sourcemod/scripting/entWatch/client.sp:68` -> `SQL_Callback_SelectBans()`
- **ось/инвариант**: database | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** client.sp:57 guards only on `error[0]` and client.sp:68 immediately calls `results.FetchRow()`. The SourceMod include is explicit that this is the wrong test: dbi.inc:334-337 documents the callback's `results` as 'Result object, or null on failure' and 'The error could be empty even if an error condition exists, so it is important to check the actual results value instead.' On the failure-with-empty-error path, results is null and FetchRow() is a null-object call - a runtime error in the callback, which also means the client never reaches client.sp:75 and never becomes Authorized.

**Триггер.** A player connects; ClientAuth (client.sp:52) queues SELECT_BANS; the MySQL connection is dropped or reset by the server before the result set is built, so SourceMod delivers the callback with results == null and an empty error string. client.sp:57 `if(error[0])` is false -> client.sp:68 `results.FetchRow()` on null -> runtime error logged, Clients[client].Authorized stays false, and OnWeaponTouch (sdkhook.sp:9-10) then blocks every item pickup for that player for the rest of his session.

**Доказательства.** client.sp:55-77 (only error[0] is checked, results is dereferenced at :68); dbi.inc:334-337 typedef SQLQueryCallback docs; sdkhook.sp:9-10 uses Clients[client].Authorized as a hard pickup gate. The same pattern exists in restrict.sp:185/196 (out of this scope).

**Исправление.**

```
public void SQL_Callback_SelectBans(Database db, DBResultSet results, const char[] error, int userid)
{
    if(results == null)
    {
        LogError("SQL_Callback_SelectBans() : %s", error);
        return;
    }
    ...
}

(and see finding client-auth-no-retry: the early return must not leave the player permanently un-authorized)
```

> **Поправка верификатора.** Minor precision on the trigger: the failure need not be 'the MySQL connection is dropped before the result set is built' specifically — the include makes no promise about WHICH failures leave the error string empty, so the honest trigger is 'any threaded query failure that delivers results == null with an empty error'. Also note the same pattern is not limited to the two restrict.sp sites the finder listed: database.sp:97 (SQL_Callback_CreateTables) and database.sp:118 (SQL_Callback_CheckError) test error[0] too, though those two never dereference results, so only client.sp:68 and restrict.sp:196 actually deref.

### 23. Any ClientAuth failure leaves Authorized false forever - item pickup fails closed

- **id**: `client-auth-no-retry` | **место**: `addons/sourcemod/scripting/entWatch/client.sp:57` -> `ClientAuth / SQL_Callback_SelectBans()`
- **ось/инвариант**: reliability | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** Clients[].Authorized is set in exactly one place, client.sp:75, and only on the fully successful path. Every earlier exit leaves it false with no retry scheduled: DB == null (client.sp:43), Steam account not yet available so GetSteamAccountID returns 0 (client.sp:47-50; clients.inc:351 '@return Steam account ID or 0 if not available'), GetClientIP failure (client.sp:49), and any SQL error (client.sp:57-61). ClientAuth has only two callers - OnClientPutInServer (client.sp:38) and the one-shot schema-ready loop (database.sp:107-113) - so after the schema callback has run there is no mechanism that ever retries. Meanwhile sdkhook.sp:9-10 uses !Authorized as a hard block on picking up ANY item. The result contradicts the documented policy 'No database -> no restricts (fail-open)': restricts do fail open (RestrictClientHasRestrict returns false when !DBLoaded, restrict.sp:666), but item pickup fails CLOSED - the affected player simply cannot take any materia for the rest of the map, with nothing in chat explaining why.

**Триггер.** Two concrete paths. (a) A transient SQL error: player connects, ClientAuth queues SELECT_BANS (client.sp:52), MySQL returns a lock-wait timeout / connection-lost error -> client.sp:57-61 LogError + return -> Authorized stays false -> OnWeaponTouch (sdkhook.sp:6-10) returns Plugin_Handled on every item for that player until he reconnects. (b) Steam auth not finished at PutInServer time (Steam outage, sv_lan, slow validation): client.sp:47 GetSteamAccountID returns 0 -> client.sp:49-50 early return -> ClientAuth is never called again for that client on that map -> same permanent lockout. (c) Server-wide variant: the CREATE TABLE query errors (database.sp:97-101 LogError + return), DBLoaded stays false, database.sp:107-113 never runs, and no player on the server can pick up any item.

**Доказательства.** client.sp:41-53 ClientAuth (guards at :43, :49 with no rescheduling); client.sp:55-77 SQL_Callback_SelectBans (error path returns before :75); client.sp:75 the sole assignment of Authorized; database.sp:107-113 the sole other ClientAuth caller, reachable once; sdkhook.sp:9-10 the pickup gate; restrict.sp:666 RestrictClientHasRestrict fail-open on !DBLoaded; clients.inc:351 GetSteamAccountID returns 0 if not available.

**Исправление.**

```
Two independent changes. (1) Move the Steam-dependent part off OnClientPutInServer to OnClientPostAdminCheck (or retry from OnClientAuthorized), so an account id that is not yet available is not a permanent verdict. (2) Make the auth outcome explicit rather than binary, so a DB failure degrades the same way restricts do:

public void SQL_Callback_SelectBans(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;

    if(results == null)
    {
        LogError("SQL_Callback_SelectBans() : %s", error);
        Clients[client].Authorized = true;   // fail-open, matching RestrictClientHasRestrict
        APIOnClientLoaded(client);
        return;
    }
    ...
}

Whichever way the policy is decided, it must be the SAME direction as the documented restrict policy; today the two halves point opposite ways. This is a policy decision, so it needs the owner's sign-off before it becomes a patch.
```

> **Поправка верификатора.** Trigger (b) should be stated more cautiously. GetSteamAccountID(client, validate=true) returning 0 at OnClientPutInServer time is documented as possible (clients.inc:351) but I did not establish that CS:S/SourceMod actually delivers PutInServer before backend validation in practice, so (b) is 'documented as possible' rather than observed. Triggers (a) and (c) are proven from the code alone and carry the finding on their own. Also, the proposed fix is correctly flagged by the finder as a policy decision, not a patch — under CLAUDE.md's rules ('Audit and fixing are separate phases') the direction (fail-open like restricts vs fail-closed) must come from the owner, and flipping it to fail-open without that sign-off would let an ebanned player pick up items during a DB outage, which is a different regression.

### 24. Permanent restricts use a -1 sentinel in columns the schema declares UNSIGNED — broken on MySQL

- **id**: `permanent-eban-negative-into-unsigned-column` | **место**: `addons/sourcemod/scripting/entWatch/client.sp:1` -> `SELECT_BANS / ClientAuth()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** The plugin encodes 'permanent' as expires = -1: client.sp:1 SELECT_BANS matches with `(expires = -1 OR expires > %i)`, restrict.sp:676 RestrictGetExpireValue returns -1 for duration == -1, and restrict.sp:666 RestrictClientHasRestrict tests `Restricts[client].Expires == -1`. But both schema branches declare the target columns unsigned: database.sp:70-71 `duration INTEGER UNSIGNED NOT NULL, expires INTEGER UNSIGNED NOT NULL` (SQLite) and database.sp:86-87 `duration int unsigned NOT NULL, expires int unsigned NOT NULL` (MySQL). The INSERT at restrict.sp:284 writes duration*60 (= -60) and expires (= -1) into them. SQLite ignores the UNSIGNED qualifier (INTEGER affinity), which is why the default deployment works and nobody has complained. MySQL does not: with the default sql_mode (STRICT_TRANS_TABLES) the INSERT is rejected out of range, and with strict mode off the values clamp to 0, after which `expires = -1` can never match the unsigned column and `expires > GetTime()` is false — the restrict silently does not exist. Either way permanent ebans do not work on a MySQL-backed server, which is the configuration CLAUDE.md documents as selected by an `entwatch` block in databases.cfg.

**Триггер.** An admin with ADMFLAG_GENERIC runs `sm_eban <player> -1` on a server whose databases.cfg contains an `entwatch` block. restrict.sp:101 Command_Ban -> RestrictClientBan(target, client, -1) -> restrict.sp:247 RestrictIsValidDuration(-1) returns true -> restrict.sp:261 RestrictGetExpireValue(time, -1) = -1 -> restrict.sp:284 DB_Query(INSERT_BAN, ..., duration*60 = -60, expires = -1) -> MySQL rejects the row (strict mode) so SQL_Callback_BanClient takes the error path at restrict.sp:303 and the eban is never stored; or, without strict mode, the row is written as 0/0 and the target's next ClientAuth (client.sp:52, SELECT_BANS at client.sp:1) finds nothing, so RestrictClientHasRestrict (restrict.sp:666) is false and the player picks up items freely at sdkhook.sp:12.

**Доказательства.** client.sp:1 `WHERE (\`expires\` = -1 OR \`expires\` > %i)`; restrict.sp:676 `return duration != -1 ? (time + duration * 60):-1;`; restrict.sp:284 INSERT_BAN bound with `duration * 60, expires`; restrict.sp:2 INSERT_BAN column list; database.sp:70-71 and database.sp:86-87 the two CREATE TABLE statements, both unsigned; restrict.sp:666 the -1 comparison on the cached value. CAVEAT: I did not run a MySQL server against this schema — the strict-mode rejection and the unsigned-comparison behaviour are standard documented MySQL semantics, not something I verified against this deployment, so treat the MySQL half as 'strongly expected' rather than observed. The SQLite half (works by accident, because SQLite ignores UNSIGNED) is certain.

**Исправление.**

```
Make the two columns signed in both CREATE TABLE statements (`duration INTEGER NOT NULL`, `expires INTEGER NOT NULL` / `int NOT NULL`). CLAUDE.md explicitly permits this: 'the schema may be changed freely — there is no legacy to preserve'. Existing SQLite databases already hold -1 correctly and need no migration; an existing MySQL table needs an ALTER before permanent ebans start working. Do NOT instead change the sentinel to 0 or to a far-future timestamp without checking every reader — restrict.sp:666, restrict.sp:68, restrict.sp:681 and client.sp:1 all hard-code the -1 meaning, so a sentinel change is a four-site edit and a behaviour change, while widening the columns is a one-file schema fix. This is a report item pending the owner's decision on schema versus sentinel, not a patch to apply unilaterally.
```

### 25. pagesCount[] never clamped to MAX_PAGES - out-of-range index into buffer[3][MAX_PAGES][256]

- **id**: `hud-pagescount-unbounded` | **место**: `addons/sourcemod/scripting/entWatch/hud.sp:130` -> `Timer_Hud()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** buffer is declared `char buffer[3][MAX_PAGES][256]` with MAX_PAGES == 4 (hud.sp:106,115). pagesCount[] is incremented every time the current page cannot hold one more line (hud.sp:130-131 for the team page, hud.sp:142-143 for the shared page 0) and is NEVER compared against MAX_PAGES. Once the accumulated text for a team exceeds MAX_PAGES pages, pagesCount[team] reaches 4 and is used to index the second rank of a size-4 array at hud.sp:133/145 (and again at hud.sp:172/177 via currentPages, which is reset with `> pagesCount[i]` at hud.sp:155 and therefore inherits the same out-of-range value). The SourcePawn compiler emits a runtime bounds check for every non-constant index, per rank (sourcepawn/compiler/code-generator.cpp:1092-1095: `__ emit(OP_BOUNDS, array_type->size() - 1)`), so this raises SP_ERROR_ARRAY_BOUNDS "Array index is out of bounds" (sourcepawn/include/sp_vm_types.h:79) and aborts the callback. Effect: the whole HUD stops updating for every player and the error is logged once per second for as long as the item count stays high. This breaks the array-bounds invariant, not merely an unarmoured path - the bound simply does not exist in the code.

**Триггер.** Any player, on a map where enough special items are held at the same time. Per-page capacity is 253 chars (the switch condition `cur + line + 2 >= 256` allows a concatenation only while cur+line <= 253), so page 0 - which accumulates every item regardless of team (hud.sp:142-145) - holds at most 4*253 = 1012 chars. ItemFormat() emits `ShortName + "[status]" + ": " + %N + "\n"` (items.sp:603) with ShortName up to 31 chars (include/entWatch/Config.inc:19) and the player name up to 31 chars, i.e. 25-75 chars per line. Path: HudOnMapStart -> HudCreateTimer -> Timer_Hud -> ItemFormat -> StrCat. That is ~14 concurrently owned DISPLAY_HUD items with long names/shortnames, ~26 with typical ones. Additionally reachable on demand: every `sm_espawn <shortname> <receiver>` clones the weapon from its point_template, and because the existing Item already has .Weapon set, ItemsRegisterItemEntity returns false and ItemsOnEntitySpawned falls through to ItemsInitiateItem (items.sp:97-106), appending another Items[] entry for the same config - so an admin with ADMFLAG_BAN can grow the owned-item count arbitrarily (up to MAX_ITEMS = 200).

**Доказательства.** hud.sp:106 `const int MAX_PAGES = 4;`; hud.sp:114-115 `int pagesCount[3]; char buffer[3][MAX_PAGES][256];`; hud.sp:130-133 and hud.sp:142-145 (increment with no upper bound, then index with it); hud.sp:155 `if(++currentPages[i] > pagesCount[i])`; hud.sp:172,177 (currentPages used as the same second-rank index). Bounds-check emission: C:/develop/sm1.13-botox/source/sourcemod/sourcepawn/compiler/code-generator.cpp:1094. Error code: C:/develop/sm1.13-botox/source/sourcemod/sourcepawn/include/sp_vm_types.h:79. Line source: items.sp:534-604 ItemFormat; include/entWatch/Config.inc:19 `char ShortName[32]`. Extra-item path: items.sp:97-106, items.sp:229-238.

**Исправление.**

```
Clamp before use, in both places, and stop accumulating once the last page is full:

    if (strlen(buffer[team][pagesCount[team]]) + strlen(line) + 2 >= sizeof(buffer[][]))
    {
        if (pagesCount[team] + 1 >= MAX_PAGES)
            continue;          // страницы кончились - остальные предметы не влезут
        pagesCount[team]++;
    }

and identically for pagesCount[0] at hud.sp:142. Clamping currentPages is then unnecessary because `currentPages[i] > pagesCount[i]` can no longer exceed MAX_PAGES-1.
```

> **Поправка верификатора.** The defect and the mechanism are right; the trigger arithmetic should be stated more conservatively. Per-page capacity is ~253 chars, so page 0 (which accumulates every DISPLAY_HUD item regardless of team, hud.sp:142-145) overflows at ~13 concurrently owned items when lines are near-maximal (ShortName 31 + status 15 + ": " + a 31-char player name, items.sp:603, Config.inc:19) and at ~35-40 with typical 25-char lines. So the honest trigger is 'an item-heavy map (MAX_CONFIGS is 50, MAX_ITEMS 200) where enough owners hold DISPLAY_HUD items at once', not 'any map'. The sm_espawn amplification is structurally right (items.sp:97-106 falls through to ItemsInitiateItem because item.Weapon is already set at items.sp:157-158, appending another Items[] entry for the same config) BUT it rests on the point_template clone preserving m_iHammerID — I did NOT verify that in the engine source, so do not lean on it as the primary trigger. The proposed fix is correct.

### 26. Off-by-one overrun writing Configs[].Color corrupts the adjacent Filter field (I3)

- **id**: `admincfg-color-overflow` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:950` -> `AdminOnClientSayCommand()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** `strcopy(Configs[cfg].Color[1], sizeof(Configs[].Color), args)` passes destLen = 16 while the destination slice `Color[1]` only has 15 usable bytes (Color is char[16] and index 0 is reserved for '#'). strcopy's destLen "includes null terminator", so a source of >=15 characters makes strcopy write byte index 15 of the slice = Color[16], i.e. one byte past the array, into the next struct member `Filter[0]`. The written byte is the NUL terminator, so the item's map-side legacy filter name (domain rule 3 / invariant I3) is silently wiped, and the colour string itself is left unterminated inside its own field.

**Триггер.** An RCON/ROOT admin opens sm_eadmin -> Configs -> picks an item -> selects the "Color" line (ConfigMenu item 4 -> ConfigMenu_Handler default -> Slot = 2) and then types a colour of 15+ characters in chat, e.g. `{cornflowerblue}` (16), `{lightsteelblue}` (16) or `{mediumslateblue}` (17) — all real names present in colors.sp. OnClientSayCommand (client.sp:113-124) -> AdminOnClientSayCommand -> case 2 (line 950) -> strcopy writes Color[16] == Filter[0] = 0. From then on OnButtonPress (sdkhook.sp:73-74) sees `Configs[..].Filter[0] == 0` and stops writing the owner's targetname, so maps that do their own TestActivator/filter_activatorname check stop letting the owner fire the item.

**Доказательства.** admin_menu.sp:950 `strcopy(Configs[cfg].Color[1], sizeof(Configs[].Color), args);`; include/entWatch/Config.inc:21-23 `char Color[16];` immediately followed by `char Filter[64];`; C:/develop/sm-1.13/include/string.inc:117-127 `native int strcopy(char[] dest, int destLen, const char[] source)` with "@param destLen Destination buffer length (includes null terminator)"; colors.sp:148,156,158,170 contain colour names of 15-20 chars; sdkhook.sp:73-74 consumes Configs[].Filter. (Note: config.sp:132 and config.sp:300 contain the same `sizeof(Configs[].Color)` pattern — root cause there belongs to config.sp.)

**Исправление.**

```
strcopy(Configs[cfg].Color[1], sizeof(Configs[].Color) - 1, args); — and, since the editor stores the raw text, also run ColorNameToColorCode(Configs[cfg].Color, sizeof(Configs[].Color)) afterwards so a typed `{name}` becomes a hex code the way ConfigBrowseKeyGFL does (config.sp:133).
```

> **Поправка верификатора.** Two sub-claims are wrong. (1) 'the colour string itself is left unterminated inside its own field' is false — the NUL is written, it just lands on Filter[0]; both `Color` and `Color[1]` still read as properly terminated strings (they borrow Filter's first byte). (2) Braced names: `cornflowerblue` is 14 chars, so it only overflows in the braced form `{cornflowerblue}` (16); the genuinely 15+ bare names in colors.sp are e.g. `mediumslateblue` (15), `mediumspringgreen` (17), `lightgoldenrodyellow` (20). The fix (`sizeof(Configs[].Color) - 1`) is correct. Note config.sp:132 (`kv.GetString("color", c.Color[1], sizeof(c.Color), ...)`), config.sp:177 and config.sp:300 carry the identical off-by-one and are hit at map load, not only from the editor.

### 27. Save rebuilds <map>.cfg from empty.cfg, destroying root-level hud/assist_use keys

- **id**: `admincfg-drops-root-keys` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:1023` -> `AdminConfigSave()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** AdminConfigSave() does not load the map's existing config; it imports the generic template `empty.cfg`, lets AdminConfigBrowseItems() write only per-item subkeys, and then exports over `configs/entwatch/<map>.cfg`. Every root-level key of the original file is therefore lost. Two such keys are live features: `hud` (hud.sp:16-19, added by commit 9275ab6 "added 'hud' parameter in mapconfig") and `assist_use` (assist_use.sp:101-104). Both are read with default 1, so after a save a map that had them disabled silently gets them enabled on the next load.

**Триггер.** On a map whose configs/entwatch/<map>.cfg contains `"hud" "0"` at root, an RCON/ROOT admin uses sm_eadmin -> Configs to change anything, then sm_eadmin -> Save (AdminMenu_Handler case 's', line 82) -> AdminConfigSave() -> AdminConfigBrowseItems() writes only the numbered item blocks -> kv.ExportToFile(<map>.cfg) at line 1028. The rewritten file has no `hud` key; at the next map load ConfigLoad -> HudConfigLoad (config.sp:67, hud.sp:18) reads `kv.GetNum("hud", 1)` = 1 and the HUD is back on against the operator's intent. Same for `assist_use`.

**Доказательства.** admin_menu.sp:1013 template path `configs/entwatch/empty.cfg`; admin_menu.sp:1023 AdminConfigBrowseItems(kv); admin_menu.sp:1032-1086 writes only per-index subkeys, never a root key; admin_menu.sp:1025-1028 exports over the map config; hud.sp:16-19 `HudConfigLoad` reads root key "hud"; assist_use.sp:101-104 `AssistUseConfigLoad` reads root key "assist_use"; config.sp:66-72 calls both on the freshly imported map config.

**Исправление.**

```
Import the existing configs/entwatch/<map>.cfg as the base when it exists (fall back to empty.cfg only for a brand-new file), or explicitly re-emit the root keys before export: kv.SetNum("hud", hud_enabled ? 1:0); kv.SetNum("assist_use", AssistUse_Toggle ? 1:0); (both globals are in scope in this translation unit).
```

> **Поправка верификатора.** The proposed fix is not compilable as written: `hud_enabled` is declared `static bool` at hud.sp:5 and is referenced nowhere outside hud.sp; a `static` global in SourcePawn is file-scoped, so admin_menu.sp cannot read it (AssistUse_Toggle at assist_use.sp:20 is non-static and would be visible). The correct fix is the first alternative the finder offers — base the save on the existing configs/entwatch/<map>.cfg when it exists and fall back to empty.cfg only for a new file — or add a `HudConfigSave(kv)` accessor in hud.sp. Also worth stating: since empty.cfg is absent from the repo its exact content is unknown, so which value the root keys end up with cannot be predicted; what is certain is that the live values are not round-tripped.

### 28. Saving a GFL config turns a knife item into a droppable/transferable item

- **id**: `admincfg-gfl-slot-lost` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:1066` -> `AdminConfigBrowseItems()`
- **ось/инвариант**: invariant-I5 | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** For CONFIG_TYPE_GFL the writer emits `allowtransfer`/`forcedrop` ONLY when Slot is SLOT_PRIMARY or SLOT_SECONDARY (lines 1066-1070). For SLOT_KNIFE (and SLOT_NONE / SLOT_GRENADES) it writes nothing at all — but the GFL reader defaults both keys to 1: `c.Slot = (kv.GetNum("allowtransfer", 1) || kv.GetNum("forcedrop", 1)) ? SLOT_SECONDARY:SLOT_KNIFE;`. A knife item therefore comes back as SLOT_SECONDARY after a save, and TransferIsValidItem()/ItemDrop() stop rejecting it — invariant I5 ("SLOT_KNIFE and SLOT_NONE items are never dropped or transferred") is broken for the rest of that map config's life. The keys are also never written as 0, so the state is unrecoverable through the editor.

**Триггер.** Map config in GFL format contains a zombie knife item with `"allowtransfer" "0"` and `"forcedrop" "0"` (parsed to SLOT_KNIFE at config.sp:149). An RCON/ROOT admin presses sm_eadmin -> Save. AdminConfigBrowseItems() writes that item's block with no allowtransfer/forcedrop key (the block is created fresh by `kv.JumpToKey(key, true)` at line 1039 for any index the template does not already contain). Next map load: config.sp:149 defaults 1||1 -> SLOT_SECONDARY. An admin can now sm_etransfer the zombie knife, and ItemDrop() (items.sp:436) will drop it on death.

**Доказательства.** admin_menu.sp:1066-1070 conditional write; config.sp:149 `c.Slot = (kv.GetNum("allowtransfer", 1) || kv.GetNum("forcedrop", 1)) ? SLOT_SECONDARY:SLOT_KNIFE;`; admin_menu.sp:1039 `kv.JumpToKey(key, true)` creates the block when absent; transfer.sp:52 and items.sp:436 are the two places that enforce I5 off Configs[].Slot. Caveat: if empty.cfg happens to ship a block containing allowtransfer 0 for that exact index the value would survive — empty.cfg is not in the repo, so this could not be checked.

**Исправление.**

```
Always write both keys for GFL:\nint transferable = (Configs[i].Slot == SLOT_PRIMARY || Configs[i].Slot == SLOT_SECONDARY);\nkv.SetNum("allowtransfer", transferable);\nkv.SetNum("forcedrop", transferable);
```

> **Поправка верификатора.** One nuance to add: the writer also unconditionally emits `forcedrop 1` for SLOT_SECONDARY, so a GFL config that had `allowtransfer 1` + `forcedrop 0` loses the `forcedrop 0`. That half is harmless inside entWatch because config.sp:149 ORs the two keys, so the parsed Slot is unchanged — the only behaviour-changing loss is KNIFE/NONE/GRENADES -> SECONDARY, as reported.

### 29. "[Remove item]" leaves editor state on the freed index; next chat line edits wrong config

- **id**: `admin-remove-keeps-editstate` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:900` -> `ConfigMenu_Handler()`
- **ось/инвариант**: invariant-I6 | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** case 0 clears the EditedConfigs lock and calls RemoveConfig(), but never calls EditClientsConfigs[client].Clear(). Config keeps the removed index and Slot keeps whatever field was selected before, so IsEdit() still returns true. RemoveConfig() (helpers.sp:26-34) shifts Configs[] down, so that index now holds a DIFFERENT config. The very next chat message from that admin is consumed by AdminOnClientSayCommand (returns true -> client.sp:123 returns Plugin_Handled, the message never reaches chat) and written into the neighbouring config, after which ConfigMenu(client) re-opens the editor on that wrong config. EditedConfigs[] is also not shifted by the removal, so a concurrent editor's lock now guards the wrong index.

**Триггер.** RCON/ROOT admin: sm_eadmin -> Configs -> pick config 3 -> select "Mode" (ConfigMenu item 9 -> ConfigMenu_Handler default -> Slot = 7) -> instead of typing, press key 1 = "[Remove item]" (index 0) -> line 902-904 clears EditedConfigs[3], RemoveConfig(3) shifts old config 4 into index 3, ConfigsMenu(client) is shown, EditClientsConfigs[client] still = {Config 3, Slot 7}. The admin now types anything in chat, e.g. "lol" -> OnClientSayCommand -> AdminOnClientSayCommand -> case 7 -> `Configs[3].Mode = StringToInt("lol")` = 0 on the shifted-in config, the chat line is swallowed, and the editor menu re-opens over the ConfigsMenu.

**Доказательства.** admin_menu.sp:900-905 case 0 (no Clear()); admin_menu.sp:886-887 shows that Clear() is the intended teardown (done only on MenuAction_Cancel); admin_menu.sp:930-931 IsEdit() gate; admin_menu.sp:934,970 slot dispatch; admin_menu.sp:1002-1007 unconditional `return true`; client.sp:122-123 `if(AdminOnClientSayCommand(...)) return Plugin_Handled;`; helpers.sp:26-34 RemoveConfig shifts Configs[] (and also never decrements Configs_Count — separate defect owned by helpers.sp, which additionally leaves a phantom duplicate entry that AdminConfigBrowseItems will then write to disk).

**Исправление.**

```
case 0:\n{\n    int cfg = EditClientsConfigs[client].Config;\n    EditedConfigs[cfg] = false;\n    EditClientsConfigs[client].Clear();\n    RemoveConfig(cfg);\n    ConfigsMenu(client);\n}\nand shift EditedConfigs[] alongside Configs[] (or key the lock by something stable).
```

> **Поправка верификатора.** Two additions to the evidence, both real: (a) helpers.sp:28-32 `for(int i = config; i < Configs_Count; i++) Configs[i] = Configs[i+1];` reads Configs[Configs_Count] on the last iteration — with Configs_Count == MAX_CONFIGS (50) that is Configs[50], outside `Config Configs[MAX_CONFIGS]` (config.sp:33), i.e. a bounds-checked out-of-array read that will throw at runtime; below 50 it copies an untouched zeroed slot in, leaving a Type == CONFIG_TYPE_UNKNOWN entry that AdminConfigBrowseItems then writes to disk as a keyless junk block (neither switch arm at admin_menu.sp:1053-1083 runs for UNKNOWN). (b) Both of these live in helpers.sp, so the fix is split across two files.

### 30. "Use item" is offered to every ADMFLAG_GENERIC admin while sm_euse requires ADMFLAG_BAN

- **id**: `admin-use-flag-gap` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:31` -> `AdminMenu()`
- **ось/инвариант**: security | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** AdminMenu() gates "eban"/"vieweban" behind BAN|RCON|ROOT (line 24) and "configs"/"save"/"reload" behind RCON|ROOT (line 33), but adds the forced-use entry unconditionally (line 31), while the equivalent command is registered as `RegAdminCmd("sm_euse", Command_Use, ADMFLAG_BAN)`. sm_eadmin itself only needs ADMFLAG_GENERIC (line 7), so any generic-level admin gains a capability the command system denies them. AdminMenu_Handler does not re-check flags on selection either — it dispatches purely on the info string's first character — so the gate is the menu construction and nothing else.

**Триггер.** An admin holding only ADMFLAG_GENERIC (e.g. a trial moderator with `b` not set) types sm_eadmin -> Command_Admin -> AdminMenu: line 24 hides the eban entries, line 33 hides the config entries, but line 31 adds "use". Selecting it -> AdminMenu_Handler case 'u' -> UseItemsMenu -> UseItemMenu_Handler -> AssistUseAdmin(item, client), i.e. they force-fire any player's item — which sm_euse would have refused them.

**Доказательства.** admin_menu.sp:7 `RegAdminCmd("sm_eadmin", Command_Admin, ADMFLAG_GENERIC);`; admin_menu.sp:24,33 the two flag gates; admin_menu.sp:30-32 the ungated forced-use item; assist_use.sp:28 `RegAdminCmd("sm_euse", Command_Use, ADMFLAG_BAN);`; admin_menu.sp:43-99 handler dispatches on buffer[0] with no re-check. CLAUDE.md commands table lists sm_euse as `ban`.

**Исправление.**

```
Wrap the entry in the same gate the command uses:\n#if defined ASSIST_USE\nif(flags & (ADMFLAG_BAN | ADMFLAG_RCON | ADMFLAG_ROOT))\n    AddMenuItem2(menu, _, "use", "%t", "Use item");\n#endif\nand, for defence in depth, re-check GetUserFlagBits(client) inside UseItemMenu_Handler before AssistUseAdmin().
```

### 31. RemoveConfig() shifts Configs[] down but never decrements Configs_Count

- **id**: `removeconfig-no-count-decrement` | **место**: `addons/sourcemod/scripting/entWatch/helpers.sp:26` -> `RemoveConfig()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The shift loop `for(int i = config; i < Configs_Count; i++) Configs[i] = Configs[i + 1];` moves every later config one slot down, but `Configs_Count` is never decremented. Compare the sibling function ItemRemove() (items.sp:606-613) which does exactly the same shift and *does* do `Items_Count--`. This is a missing counter decrement, not a missing defensive check. After one removal, Configs_Count is one too high and the last live slot Configs[Configs_Count-1] is a copy of the stale slot Configs[Configs_Count] (a ConfigClear'd entry: Name/ShortName empty, all HammerIds 0, Type=CONFIG_TYPE_UNKNOWN). Every iteration over Configs_Count then walks a phantom config: ConfigsMenu (admin_menu.sp:770-779, shows 'Unknown item'), AdminConfigBrowseItems (admin_menu.sp:1035) which WRITES the phantom into configs/entwatch/<map>.cfg on Save, ItemsRegisterGetKeyValues (items.sp:111), ConfigGetByName/ConfigGetByShortName (config.sp:234-256). Repeated removals empty the whole table while Configs_Count stays at its original value.

**Триггер.** An admin with ADMFLAG_RCON|ROOT runs `sm_eadmin` -> 'Configs item' -> ConfigsMenu -> picks any config -> ConfigMenu -> item 0 '[Remove item]'. Path: ConfigMenu_Handler (admin_menu.sp:900-905) -> RemoveConfig(EditClientsConfigs[client].Config) (admin_menu.sp:903) -> helpers.sp:28-32. Then 'Save item' -> AdminConfigSave() (admin_menu.sp:1010) -> AdminConfigBrowseItems() loops `i < Configs_Count` (admin_menu.sp:1035) and writes an extra empty key block into the map cfg.

**Доказательства.** helpers.sp:26-34 (no `Configs_Count--`); items.sp:606-613 shows the correct pattern with `Items_Count--`; caller admin_menu.sp:903; consumers admin_menu.sp:770, admin_menu.sp:1035, items.sp:111, config.sp:225/237/249; Configs_Count declared config.sp:32, only ever incremented at config.sp:162/203 and admin_menu.sp:812, and reset to 0 only in ConfigClearAll (config.sp:220).

**Исправление.**

```
Bound the loop to the last live element and decrement the count:
```
stock void RemoveConfig(int config)
{
	for(int i = config; i < Configs_Count - 1; i++)
		Configs[i] = Configs[i + 1];

	Configs_Count--;
	ConfigClear(Configs_Count);   // очистить освободившийся слот
	RemoveItemByConfig(config);
}
```
```

> **Поправка верификатора.** Core defect is real and the fix is right, but two details in the write-up are wrong. (1) The phantom slot is NOT necessarily 'a ConfigClear'd entry'. ConfigClearAll (config.sp:216-220) only clears 0..Configs_Count-1, so Configs[Configs_Count] is either all-zero (fresh plugin load) or whatever a previous map left in that index. Either way the invariant it violates is the same: after the shift, Configs[Configs_Count-1] is a duplicate of a slot that was never a live config of this map. (2) The 'writes the phantom into configs/entwatch/<map>.cfg' consequence is conditional: AdminConfigSave (admin_menu.sp:1013-1021) bails out with LogMessage("File %s not founded") unless configs/entwatch/empty.cfg exists, and that file is NOT present in this repo (only colors.cfg is). On a server that does have empty.cfg the claim holds — kv.JumpToKey(key, true) at admin_menu.sp:1039 creates the missing numbered block. Severity downgraded from critical to major: the path is rcon-admin-only, no player can reach it, and it does not crash — it corrupts the in-memory config table and (conditionally) the saved file.

### 32. RemoveItemByConfig() leaves live Items[] slots with Config == -1, so Configs[-1] gets indexed

- **id**: `removeitembyconfig-zombie-items` | **место**: `addons/sourcemod/scripting/entWatch/helpers.sp:42` -> `RemoveItemByConfig()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** For every item belonging to the removed config the function calls only `ItemClear(i)`. ItemClear (items.sp:622-636) sets Items[i].Config = -1 and zeroes the entity fields, but the slot stays inside 0..Items_Count-1: neither ItemRemove() nor ItemUnhook() is called. Two consequences. (1) Any code that dereferences `Configs[Items[i].Config]` while iterating Items_Count now indexes Configs[-1]; the SourcePawn BOUNDS check is an unsigned compare, so -1 (0xFFFFFFFF) is above the limit and throws SP_ERROR_ARRAY_BOUNDS, aborting whatever callback is running. Two reachable victims inside this audit's scope: dump.sp:21 (`Configs[Items[i].Config].Name` and `.Maxuses`, unguarded) and transfer.sp:52 (TransferIsValidItem reads `Configs[Items[item].Config].Slot`), which admin_menu.sp:480 calls for every i in 0..Items_Count-1. hud.sp survives only by accident, because ItemClear also zeroes Owner and Timer_Hud short-circuits on `!Items[i].Owner` (hud.sp:121). (2) The item's SDKHook_Use on its button and its OnEqualTo/OnTrigger output hooks are never removed — ItemUnhook (items.sp:638-658) is not called — so the hooks survive with no owning item (I8).

**Триггер.** An rcon admin runs `sm_eadmin` -> Configs -> a config that currently has a live item on the map -> '[Remove item]'. Path: ConfigMenu_Handler (admin_menu.sp:903) -> RemoveConfig() (helpers.sp:33) -> RemoveItemByConfig() -> ItemClear(i) (helpers.sp:42). Then either (a) the same or another rcon admin runs `sm_edump` -> Command_Dump -> dump.sp:21 -> Configs[-1].Name -> array-index-out-of-bounds, or (b) any admin opens `sm_eadmin` -> Transfer -> 'Map' -> TransferByMapMenu (admin_menu.sp:478-487) -> TransferIsValidItem(i) -> transfer.sp:52 -> Configs[-1].Slot -> same error, and the transfer menu never opens.

**Доказательства.** helpers.sp:36-52; ItemClear items.sp:622-636 (Config = -1); ItemRemove/ItemUnhook exist and are unused here (items.sp:606-613, 638-658); victims dump.sp:21 and transfer.sp:52 reached from admin_menu.sp:480; hud.sp:121 shows the accidental guard; unsigned BOUNDS check sourcepawn/vm/x86/jit_x86.cpp:1193-1199.

**Исправление.**

```
Remove the slot properly and re-check the same index (ItemRemove shifts the array down):
```
stock void RemoveItemByConfig(int config)
{
	for(int i = 0; i < Items_Count; )
	{
		if(Items[i].Config == config)
		{
			ItemUnhook(i);
			ItemClear(i);
			ItemRemove(i);
			continue;              // индексы сдвинулись — i не увеличиваем
		}

		if(Items[i].Config > config)
			Items[i].Config--;

		i++;
	}
}
```
```

> **Поправка верификатора.** The defect is real but one of the two named victims is wrong and the more damaging victim was missed.

REFUTED sub-claim: transfer.sp:52 is NOT reachable with Config == -1. TransferIsValidItem's FIRST guard is `if(Items[item].Weapon == 0) return false;` (transfer.sp:46-47), and ItemClear zeroes Weapon (items.sp:625) on exactly the slots it leaves behind. So admin_menu.sp:480 (`if(!TransferIsValidItem(i) || Items[i].Owner) continue;`) short-circuits before Configs[Items[item].Config].Slot is ever evaluated. The transfer menu does not die.

CONFIRMED victims: (a) dump.sp:21 — `Configs[Items[i].Config].Name` and `.Maxuses`, unguarded, inside a loop over Items_Count; (b) items.sp:361 ItemsGetByShortName — `strncmp(Configs[Items[i].Config].ShortName, ...)`, unguarded, reached from transfer.sp:24 (`sm_etransfer $x <receiver>`, ADMFLAG_GENERIC — a far lower bar than rcon) and from assist_use.sp:73 (`sm_euse $x`).

MISSED and worse: the leftover OUTPUT hooks are not harmless. ItemClear zeroes Compare/Relay without UnhookSingleEntityOutput, so the hook survives on the logic_compare/logic_relay entity. Compare_OnEqualTo (sdkhook.sp:91-94) does `int item = ItemsGetByCompare(...); if(!Items[item].Owner)` with NO item == -1 guard, and Relay_OnTrigger (sdkhook.sp:107-110) is identical — so every subsequent firing of that map entity evaluates Items[-1].Owner and throws SP_ERROR_ARRAY_BOUNDS, repeatedly, for the rest of the round. The leftover SDKHook_Use on the button, by contrast, IS harmless: OnButtonPress guards `if(item == -1) return Plugin_Continue;` (sdkhook.sp:61-62). The proposed fix (ItemUnhook + ItemClear + ItemRemove, re-checking the same index) is correct and also closes the output-hook leak.

### 33. Transfer hands an item to a ZR half-zombie — the half-zombie pickup gate is bypassed

- **id**: `transfer-halfzombie-bypass` | **место**: `addons/sourcemod/scripting/entWatch/transfer.sp:17` -> `Command_Transfer / TransferItem()`
- **ось/инвариант**: invariant-I2 | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** I2 requires that a ZR half-zombie cannot obtain an item by ANY route. The half-zombie pickup gate lives solely in OnWeaponTouch (sdkhook.sp:15-18), which is SDKHook_WeaponCanUse. Transfer never touches that hook: TransferItem equips the weapon with EquipPlayerWeapon (transfer.sp:84), which SDKCalls the virtual CBasePlayer::Weapon_Equip, while SDKHook_WeaponCanUse hooks the *different* virtual CBaseCombatCharacter::Weapon_CanUse — so the CanUse gate simply does not run. Command_Transfer validates the receiver against RestrictClientHasRestrict and Clients[].Authorized (transfer.sp:17) but never against HalfZombie[]. The equip does fire SDKHook_WeaponEquipPost -> OnWeaponPickup (sdkhook.sp:23-34), which sets Items[item].Owner = half-zombie; from then on OnButtonPress accepts that owner (sdkhook.sp:64) and the half-zombie can fire the item. The same gap exists on both admin-menu transfer paths (admin_menu.sp:527, 625 check restrict but not HalfZombie), because the check is missing from TransferIsValidItem/TransferItem rather than from one call site.

**Триггер.** ZR half-zombie mode active (HalfZombieEnabled true, halfzombie.sp:39-53) and player B is on a 'frazzle' class so HalfZombie[B] == true (halfzombie.sp:60-68). An admin with ADMFLAG_GENERIC types `sm_etransfer A B`. Path: Command_Transfer (transfer.sp:15-17, restrict/auth pass, no half-zombie check) -> ItemFindClientItem(A) -> TransferItem(item, B, admin) -> TransferIsValidItem (transfer.sp:44-56, checks only Weapon!=0, Owner!=receiver, slot) -> EquipPlayerWeapon(B, weapon) (transfer.sp:84) -> SDKHook_WeaponEquipPost -> OnWeaponPickup -> Items[item].Owner = B. B presses E -> OnButtonPress passes the `Items[item].Owner != activator` guard and fires the item.

**Доказательства.** transfer.sp:17 (receiver validation, no HalfZombie), transfer.sp:44-56 (TransferIsValidItem does not look at the receiver's state), transfer.sp:84 (EquipPlayerWeapon); sdkhook.sp:15-18 is the only pickup-side HalfZombie check, sdkhook.sp:129-132 the only trigger-side one; halfzombie.sp:11,55-68; EquipPlayerWeapon -> CBasePlayer::Weapon_Equip: sdktools_functions.inc:330, extensions/sdktools/vnatives.cpp:1393-1414 (`CreateBaseCall("WeaponEquip", ValveCall_Player, ...)`), gamedata/sdktools.games/game.cstrike.txt:114-120 ("WeaponEquip" vtable 267/268); SDKHook_WeaponCanUse hooks a different virtual: extensions/sdkhooks/extension.cpp:66 ("WeaponCanUse", "DT_BaseCombatCharacter"), :190 SH_DECL_MANUALHOOK1(Weapon_CanUse...), :747-748.

**Исправление.**

```
Move the receiver validation into TransferItem so every path (command, map menu, target menu) is covered:
```
bool TransferItem(int item, int receiver, int admin)
{
    if(!TransferIsValidItem(item, receiver))
        return false;

    if(RestrictClientHasRestrict(receiver))
        return false;

    #if defined HALFZOMBIE
    if(HalfZombie[receiver])
        return false;
    #endif
    ...
```
(halfzombie.sp is included before transfer.sp in entWatch.sp:26/31, so HalfZombie[] is visible.)
```

### 34. sm_etransfer does not require the receiver to be alive or on a playing team

- **id**: `transfer-receiver-not-alive` | **место**: `addons/sourcemod/scripting/entWatch/transfer.sp:17` -> `Command_Transfer()`
- **ось/инвариант**: api-use | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** Command_Transfer accepts any target FindTarget resolves — including a dead player and a spectator — and validates only `receiver <= 0`, RestrictClientHasRestrict and Clients[].Authorized (transfer.sp:15-18). Every menu-driven transfer path in the plugin does check IsPlayerAlive (admin_menu.sp:399, 448, 527, 625), so the command path diverges from the plugin's own contract. EquipPlayerWeapon does not reject a dead-but-in-game client: the sdktools decoder only rejects not-connected and not-in-game (vdecoder.cpp:382-409), so Weapon_Equip runs on a corpse/spectator, OnWeaponPickup records them as Owner (sdkhook.sp:30), and the item is out of play — it cannot be pressed (OnButtonPress requires the owner as activator) and it is not on the ground for anyone else to pick up. On the next respawn the engine's RemoveAllItems path destroys the weapon, at which point OnEntityDestroyed -> ItemsOnEntityDestroyed removes the item entirely for the round.

**Триггер.** An admin with ADMFLAG_GENERIC types `sm_etransfer A B` while B is dead (or spectating). Path: Command_Transfer -> FindTarget(client, "B", true, false) returns B (ProcessTargetString returns in-game clients regardless of alive state) -> transfer.sp:17 passes -> TransferItem -> ItemDrop(A's item) -> EquipPlayerWeapon(B, weapon) (transfer.sp:84, no throw) -> OnWeaponPickup sets Owner = B. Item is now unusable for the rest of the round.

**Доказательства.** transfer.sp:15-18 (no IsPlayerAlive / GetClientTeam check); contrast admin_menu.sp:399, admin_menu.sp:448, admin_menu.sp:527, admin_menu.sp:625 which all check IsPlayerAlive before calling TransferItem; FindTarget returns any in-game client (helpers.inc:163-195 via ProcessTargetString); EquipPlayerWeapon accepts a not-alive in-game client — extensions/sdktools/vdecoder.cpp:382-409 rejects only !IsConnected() and !IsInGame(); ownership is then set by sdkhook.sp:23-34.

**Исправление.**

```
Validate the receiver where the other paths do, i.e. inside TransferItem (same edit site as the half-zombie fix):
```
    if(!IsClientInGame(receiver) || !IsPlayerAlive(receiver))
        return false;
```
```

### 35. `strlen(ip) == 16` can never be true — every IP-matching branch of the offline restrict commands is dead code

- **id**: `restrict-ip-never-valid` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:429` -> `RestrictAddBan / RestrictDeleteBan()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** Both offline restrict entry points decide whether an IP argument is usable with `bool ipIsValid = (strlen(ip) == 16);` (restrict.sp:429 and restrict.sp:550). The buffer that IP arrives in is `char ip[16]` — declared at restrict.sp:139 for sm_addeban and restrict.sp:158 for sm_deleban — and GetCmdArg writes at most maxlength-1 characters plus the terminator, so strlen(ip) is bounded by 15 and the comparison is unconditionally false. (The longest possible IPv4 string, "255.255.255.255", is 15 characters, so even a full address cannot reach 16.) Three consequences, all silent: the `if(id && ipIsValid)` branches at restrict.sp:444-447 and restrict.sp:565-568 — the ones that match on Steam ID AND IP together — can never execute; an IP-only restrict is impossible, because with an empty/absent steamid UTIL_GetAccountIDFromSteamID returns 0 and the guard `if(!id && !ipIsValid)` at restrict.sp:430/551 rejects the command outright; and when a steamid IS supplied the plugin falls into the `else if(id)` branch and issues a SteamID-only SELECT/DELETE while still writing the ip column on INSERT, so a ban created with both keys can only ever be found by one of them. CLAUDE.md states as a domain fact that 'Restricts are matched by both Steam account ID and IP', and the SELECT_SUMM_BANS / SELECT_BANS / DELETE_BAN statements at restrict.sp:1-3 do match on `pid OR pip` — so the online path honours the contract and only these two offline commands do not. This is wrong code (a comparison that can never hold), not a missing defensive check.

**Триггер.** An rcon admin wants to restrict a player who is offline and whose Steam ID he does not have, so he runs `sm_addeban 60 "" 1.2.3.4`. Path: Command_AddBan (restrict.sp:130-146, args == 3) -> GetCmdArg(2, buffer, 64) yields "" and GetCmdArg(3, ip, 16) yields "1.2.3.4" -> RestrictAddBan(60, "", "1.2.3.4", client) -> UTIL_GetAccountIDFromSteamID("") returns 0 (helpers.sp:18, neither strncmp branch matches) -> `ipIsValid = (strlen("1.2.3.4") == 16)` == false (restrict.sp:429) -> `if(!id && !ipIsValid)` at restrict.sp:430 is true -> PrintToChat2(admin, "Invalid SteamID and IP-adress") and return. The restrict is never created and the admin is told his valid IP is invalid. The same line kills `sm_deleban "" 1.2.3.4` at restrict.sp:550-555.

**Доказательства.** restrict.sp:429 and restrict.sp:550 (`bool ipIsValid = (strlen(ip) == 16);`); buffers declared `char ip[16]` at restrict.sp:139 and restrict.sp:158; the unreachable both-keys branches at restrict.sp:444-447 and restrict.sp:565-568; the reject guard at restrict.sp:430 and restrict.sp:551. GetCmdArg is documented to write at most maxlength bytes including the terminator — console.inc GetCmdArg(int argnum, char[] buffer, int maxlength), so strlen <= maxlength-1 == 15. The plugin's own SQL proves IP matching is intended: SELECT_SUMM_BANS/INSERT_BAN/DELETE_BAN at restrict.sp:1-3 all key on `pid` OR `pip`, and RestrictLoadClientSummBans passes the client IP at restrict.sp:180. Found while verifying the two call sites of UTIL_GetAccountIDFromSteamID for the helpers-steamid-short-read finding.

**Исправление.**

```
Validate the IP as an IP instead of by an impossible length, e.g. require at least three dots and a non-empty first octet, or at minimum replace both occurrences with a plausible bound:
```
bool ipIsValid = (strlen(ip) >= 7);   // "1.2.3.4"
```
Both restrict.sp:429 and restrict.sp:550 must change together; changing only one leaves add and delete matching on different key sets. Note this fix makes the currently-dead `id && ipIsValid` branches live for the first time, so their SQL should be re-read before shipping.
```

### 36. RemoveItemByConfig() clears item slots without ItemUnhook(), leaving hooks on live entities

- **id**: `removeitembyconfig-no-unhook` | **место**: `addons/sourcemod/scripting/entWatch/helpers.sp:42` -> `RemoveItemByConfig()`
- **ось/инвариант**: invariant-I8 | **уверенность**: proven | **вердикт верификатора**: CRITIC

**Проблема.** Every other teardown path pairs ItemUnhook() with ItemClear(): ItemsOnEntityDestroyed does ItemUnhook(i); ItemClear(i); ItemRemove(i) (items.sp:310-312). RemoveItemByConfig calls only ItemClear(i) (helpers.sp:42), which zeroes Items[i].Button/Trigger/Compare/Relay (items.sp:626-629) while those entities are still ALIVE and still hooked. Hook symmetry (I8) breaks in the one direction the audit did not cover: an in-round teardown with no entity destruction to bail the plugin out. Two concrete consequences. (a) The logic_compare's OnEqualTo and the logic_relay's OnTrigger hooks stay installed; when the map next fires them, Compare_OnEqualTo / Relay_OnTrigger run, ItemsGetByCompare/ByRelay now return -1 (items.sp:401-410, 412-421) and sdkhook.sp:93 / sdkhook.sp:109 evaluate Items[-1].Owner -> OP_BOUNDS array-index error, aborting the callback. That is a REACHABLE trigger for the surviving minor finding compare-relay-missing-item-guard, and it contradicts the refutation of compare-relay-negative-index, which argued no trigger exists because 'in CS:S every logic_compare is DESTROYED AND RECREATED each round' - true across a round boundary, irrelevant to a removal WITHIN a round. (b) The trigger keeps SDKHook_StartTouch/EndTouch/Touch, so OnTriggerTouch (sdkhook.sp:118-135) goes on returning Plugin_Handled for restricted players and half-zombies on a trigger entWatch no longer manages, for the rest of the round.

**Триггер.** An ADMFLAG_RCON/ROOT admin, mid-round, on a map whose config has a compareid (or relayid): sm_eadmin -> the 'configs' entry is offered only to RCON|ROOT (admin_menu.sp:33-38) -> ConfigsMenu -> selects the item -> ConfigMenu -> selects '[Remove item]' (menu index 0) -> ConfigMenu_Handler case 0 (admin_menu.sp:900-905) -> RemoveConfig(cfg) (helpers.sp:26) -> RemoveItemByConfig(cfg) (helpers.sp:33) -> ItemClear(i) at helpers.sp:42 for the live item, whose Compare entity is untouched and still hooked (hooked at items.sp:209). The next time the map fires OnEqualTo on that logic_compare -> Compare_OnEqualTo (sdkhook.sp:86) -> ItemsGetByCompare returns -1 -> sdkhook.sp:93 Items[-1].Owner.

**Доказательства.** helpers.sp:36-52 (RemoveItemByConfig; ItemClear at :42, no ItemUnhook); items.sp:638-658 (ItemUnhook exists and handles all four hook kinds); items.sp:304-315 (the correct pairing, for comparison); items.sp:622-636 (ItemClear zeroes the entity fields); items.sp:183,198-200,209,219 (where the hooks are installed); sdkhook.sp:91-93 and 107-109 (the unguarded -1 index); admin_menu.sp:900-905 (the only caller of RemoveConfig). Native semantics: SDKHooks removes pawn hooks only when the ENTITY is deleted (extensions/sdkhooks/extension.cpp, HandleEntityDeleted -> Unhook(pEntity)), which never happens here; UnhookSingleEntityOutput is the only way to drop an output hook on a live entity (sdktools/outputnatives.cpp).

**Исправление.**

```
Unhook before clearing, exactly as ItemsOnEntityDestroyed does:

stock void RemoveItemByConfig(int config)
{
    for(int i = 0; i < Items_Count; i++)
    {
        if(Items[i].Config == config)
        {
            ItemUnhook(i);
            ItemClear(i);
            continue;
        }
        if(Items[i].Config > config)
            Items[i].Config--;
    }
}

Note for the fixing phase: this makes the -1 index in Compare_OnEqualTo/Relay_OnTrigger unreachable again from THIS path, so do not apply it and the compare-relay guard as if they were independent - recompute after the edit. It does NOT fix the zombie slot (Config == -1 inside the live range) that removeitembyconfig-zombie-items reports; that is a separate defect.
```

## MINOR (71)

### 37. ItemsOnPluginEnd() unhooks at most one entity category per item (continue chain)

- **id**: `pluginend-continue-chain` | **место**: `addons/sourcemod/scripting/entWatch/items.sp:41` -> `ItemsOnPluginEnd()`
- **ось/инвариант**: invariant-I8 | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The four `if(...) { ...; continue; }` blocks (items.sp:43-64) are mutually exclusive, so an item that has a Button never gets its Trigger/Compare/Relay unhooked, an item with a Trigger never gets Compare/Relay unhooked, and so on. ItemUnhook() (items.sp:638-658) does the same job correctly with four independent ifs - the continues are a copy-paste defect. On a real plugin unload the leak is harmless (SDKHooks drops every hook owned by the context, extension.cpp:427-429, and sdktools tracks output hooks per plugin, outputnatives.cpp:97-107), but the function is also called manually while the plugin stays loaded, where nothing cleans up after it.

**Триггер.** Admin with rcon/root: sm_eadmin -> Reload. AdminMenu_Handler case 'r' (admin_menu.sp:86-94) calls OnPluginEnd() -> ItemsOnPluginEnd() directly (entWatch.sp:104-108) with the plugin still loaded, then OnRoundEnd() -> ItemsClear() (which also does not unhook, see itemsclear-no-unhook-double-sdkhook), then OnMapStart() -> full rescan re-hooking the same still-alive entities. For every item that has both a Button and a Trigger, the trigger keeps its old StartTouch/EndTouch/Touch hooks and gains a second set; each further reload adds another set, and duplicates stack (extension.cpp:792-796).

**Доказательства.** items.sp:39-67 (the continue chain) versus items.sp:638-658 (ItemUnhook, correct); entWatch.sp:104-108; admin_menu.sp:86-94; sdkhooks extension.cpp:427-429 (per-plugin cleanup runs only on real unload), :792-796, :500-512.

**Исправление.**

```
Replace the whole body with the already-correct helper:

void ItemsOnPluginEnd()
{
    for(int i = 0; i < Items_Count; i++)
        ItemUnhook(i);
}
```

> **Поправка верификатора.** The functional consequence is smaller than stated. (1) Compare/Relay are never doubled: HookSingleEntityOutput refuses an identical (function, entity_ref) pair (outputnatives.cpp:66-82), so 'an item with a Trigger never gets Compare/Relay unhooked' leaks bookkeeping only. (2) Duplicated StartTouch/EndTouch/Touch callbacks are idempotent - OnTriggerTouch (sdkhook.sp:118-134) is a pure function of state and Hook_* keeps max(res), so two identical returns change nothing. So the real defect is accumulation of redundant touch callbacks on every sm_eadmin -> Reload (and the function silently doing less than its name promises), not double counting. Severity minor is right; the fix (replace the body with ItemUnhook(i)) is right.

### 38. ItemRemove() shift loop reads Items[Items_Count] - out of bounds when the array is full

- **id**: `itemremove-reads-past-live-range` | **место**: `addons/sourcemod/scripting/entWatch/items.sp:608` -> `ItemRemove()`
- **ось/инвариант**: correctness | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** `for(int i = item; i < Items_Count; i++) Items[i] = Items[i + 1];` - the last iteration (i == Items_Count-1) reads Items[Items_Count], one past the live range. Normally that is a harmless read of an unused slot, but when Items_Count == MAX_ITEMS the index is 200 on `Item Items[200]`, i.e. a genuine out-of-bounds array read; SourcePawn bounds-checks the access and raises a runtime error that aborts the current callback (here, the OnEntityDestroyed forward). The bound must be `i < Items_Count - 1`.

**Триггер.** A map/config combination that fills the array to MAX_ITEMS (ItemsInitiateItem stops adding at items.sp:231, so Items_Count can sit at exactly 200), then any item weapon entity is destroyed -> OnEntityDestroyed -> ItemsOnEntityDestroyed (items.sp:308-313) -> ItemRemove(i) -> read of Items[200]. Duplicated items are realistic (point_template clones keep the template's m_iHammerID, which is why ItemsOnEntitySpawned loops over several items per config, items.sp:97-104), but I did not find a production map that reaches 200.

**Доказательства.** items.sp:606-613; items.sp:1 (MAX_ITEMS = 200); items.sp:13 (Item Items[MAX_ITEMS]); items.sp:229-238 (Items_Count can reach exactly MAX_ITEMS).

**Исправление.**

```
for(int i = item; i < Items_Count - 1; i++)
    Items[i] = Items[i + 1];
Items_Count--;
```

> **Поправка верификатора.** Reachability is NOT established - it needs Items_Count to sit at exactly 200, which I could not construct either (configs are capped at 50, and multi-instance items require repeated point_template clones that keep the template hammerid). Report it as a latent off-by-one with an unproven trigger, not as an actionable crash. Worth flagging in the same breath: helpers.sp:28-32 (RemoveConfig) has the identical off-by-one over Configs[] AND never decrements Configs_Count - the second half of that is a plain missing-decrement bug, which is more likely to bite than this one.

### 39. ItemsGetByShortName()/ItemsGetByName() index Configs[] with Config == -1

- **id**: `getbyname-missing-config-guard` | **место**: `addons/sourcemod/scripting/entWatch/items.sp:361` -> `ItemsGetByShortName / ItemsGetByName()`
- **ось/инвариант**: correctness | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** Both loops dereference Configs[Items[i].Config] for every i < Items_Count without checking Config != -1, while the sibling lookup ItemsGetByWeaponHammerID does check it (items.sp:372) - the author already knows cleared slots can live inside Items_Count. A cleared slot has Config == -1 (items.sp:624), so the lookup performs Configs[-1] and SourcePawn's bounds check aborts the calling command.

**Триггер.** Admin (rcon/root): sm_eadmin -> Configs -> pick a config -> '[Remove item]'. ConfigMenu_Handler case 0 (admin_menu.sp:900-905) -> RemoveConfig (helpers.sp:26-34) -> RemoveItemByConfig (helpers.sp:36-52) which calls ItemClear(i) in place, leaving Config == -1 slots inside Items_Count (it never removes them and never touches Items_Count). Any admin then running `sm_etransfer $<short> <player>` (transfer.sp:24) or `sm_euse $<short>` (assist_use.sp:73) hits ItemsGetByShortName -> Configs[-1].ShortName -> runtime error, command aborted.

**Доказательства.** items.sp:344-354 and 356-366 (no guard) versus items.sp:368-377 (guard present); items.sp:622-636 (ItemClear sets Config = -1); helpers.sp:36-52 (RemoveItemByConfig clears in place, Items_Count unchanged); transfer.sp:24; assist_use.sp:73.

**Исправление.**

```
Guard both loops the way ItemsGetByWeaponHammerID does: `if(Items[i].Config == -1) continue;` before the strncmp. (The deeper defect - RemoveItemByConfig leaving live-range slots cleared, and RemoveConfig never decrementing Configs_Count - is in helpers.sp and belongs to that file's owner.)
```

> **Поправка верификатора.** Two corrections. (1) ItemsGetByName (items.sp:344-354) has no callers anywhere in the plugin - it is a `stock`, so it is not compiled and is not part of the bug; only ItemsGetByShortName matters (callers: transfer.sp:24, assist_use.sp:73). (2) The same admin action leaves other live-range wreckage that the guard does not cover, so the guard alone is a band-aid: RemoveItemByConfig clears items WITHOUT ItemUnhook, so the removed item's logic_compare/logic_relay output hooks and its button SDKHook stay live (see my 'missed' finding compare-relay-missing-item-guard), and RemoveConfig never decrements Configs_Count. Fix at the source (ItemUnhook + proper removal in RemoveItemByConfig) rather than only adding `if(Items[i].Config == -1) continue;`.

### 40. mp_restartgame <n> kills every item for n seconds of live gameplay

- **id**: `restartgame-disables-items-for-the-delay` | **место**: `addons/sourcemod/scripting/entWatch.sp:219` -> `OnRestartGame()`
- **ось/инвариант**: invariant-I1 | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** OnRestartGame treats any 0 -> non-(-1) transition of mp_restartgame as a round end and calls OnRoundEnd immediately (entWatch.sp:219-223) -> ItemsOnRoundEnd -> RoundStarted = false + ItemsClear (items.sp:33-37). But mp_restartgame's value is the delay in SECONDS before the restart (CheckRestartRound: m_flRestartRoundTime = curtime + iRestartDelay, cs_gamerules.cpp:3646-3668). For the whole delay the round is still running: every hooked button now returns Plugin_Handled at the top of OnButtonPress (sdkhook.sp:53-54) - blocking the legitimate owner as well - trigger touches are blocked too (sdkhook.sp:120-121), and no newly spawned entity is registered (items.sp:83-84). With `mp_restartgame 5` that is five seconds of live play with every materia dead. The `StringToInt(newValue) != -1` half of the condition is dead code (mp_restartgame is never -1); it is harmless only because SourceMod suppresses change hooks when the value did not actually change (ConVarManager.cpp:627-631), so a repeated `mp_restartgame 0` does not wipe the round.

**Триггер.** Any admin or map/plugin executing `mp_restartgame 5` (or any delay > ~1 s) mid-round: ConVar change hook -> entWatch.sp:219-223 -> OnRoundEnd -> ItemsOnRoundEnd -> ItemsClear; for the next 5 s every item press is refused by sdkhook.sp:53-54.

**Доказательства.** entWatch.sp:219-223; entWatch.sp:182-186; items.sp:33-37, 83-84; sdkhook.sp:51-54, 118-121. Engine: cs_gamerules.cpp:3646-3668 (mp_restartgame is a delay in seconds), 2971-3004 (the restart happens later, from Think). SM: core/ConVarManager.cpp:625-631 (same-value writes never reach the plugin); tier1/convar.cpp:755-794 (the engine itself does not filter them).

**Исправление.**

```
Do not clear on the announcement; clear when the restart actually happens. Either react only to round_start/round_end, or schedule the wipe: `float delay = StringToFloat(newValue); if(StringToInt(oldValue) == 0 && delay > 0.0) CreateTimer(delay, ...)` - simplest correct option is to drop the hook entirely and rely on the round_start rescan, which already rebuilds everything.
```

> **Поправка верификатора.** Three corrections. (1) `StringToInt(newValue) != -1` is NOT dead code: mp_restartgame is declared without bounds (multiplay_gamerules.cpp:96), so `mp_restartgame -1` is settable and produces no restart at all (CheckRestartRound acts only on > 0, cs_gamerules.cpp:3649-3651) - the guard correctly ignores exactly that value. (2) The dead window is delay + up to 1 s, not exactly the delay, because CheckRestartRound only runs once per second (cs_gamerules.cpp:3007-3010). (3) The suggested fix 'simplest correct option is to drop the hook entirely and rely on the round_start rescan' is WRONG and would be a regression: an mp_restartgame restart fires round_start but never round_end, so this hook is the only thing that clears RoundStarted before CleanUpMap re-creates the item entities - remove it and every mp_restartgame reproduces the duplicate SDKHook_Use of finding itemsclear-no-unhook-double-sdkhook. Correct fix: keep reacting to the cvar but defer the wipe by the announced delay (timer), or unhook on clear so the dead window stops blocking presses.

### 41. sm_euse $<name> passes ItemsGetByShortName's -1 sentinel straight into Items[]

- **id**: `euse-shortname-negative-index` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:74` -> `Command_Use()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** ItemsGetByShortName (items.sp:356-366) documents its miss by returning -1, and transfer.sp:24-27 checks it. Command_Use does not: assist_use.sp:73-74 assigns the result and calls AssistUseAdmin(item, client) unconditionally, whose first statement dereferences Items[item] (assist_use.sp:80). With item == -1 that is Items[-1].Button - a negative array index, which SourcePawn bounds-checks and turns into a runtime error that aborts the command. The same lookup also matches on a prefix of length strlen(name), so an empty name matches item 0.

**Триггер.** Admin with ADMFLAG_BAN types `sm_euse $qqq` in console/chat where no live item's shortname starts with 'qqq' (or types it on a map with no items at all): Command_Use (assist_use.sp:42) -> buffer[0]=='$' so mode=false -> ItemsGetByShortName(buffer[1]) returns -1 (items.sp:365) -> AssistUseAdmin(-1, client) -> `Items[-1].Button` (assist_use.sp:80) -> array-index runtime error, command aborted, error logged. Second variant: `sm_euse $` -> buffer[1] is "" -> len 0 -> strncmp(...,0,...) == 0 on the first iteration -> returns item 0 -> an arbitrary item is force-used.

**Доказательства.** items.sp:356-366 (returns -1; strncmp with len = strlen(name), no empty-name rejection); assist_use.sp:73-74 (no check) versus transfer.sp:24-27 (`if(item != -1)`); assist_use.sp:80 `if(!Items[item].Button || !Items[item].Owner)`.

**Исправление.**

```
Guard the caller: `item = ItemsGetByShortName(buffer[1]); if(item == -1) return Plugin_Handled;` before line 74. Optionally make ItemsGetByShortName return -1 for an empty name (`if(!len) return -1;`) so `$` alone stops resolving to item 0.
```

### 42. Compare/Relay output callbacks index Items[] with the -1 miss from ItemsGetByCompare/ByRelay

- **id**: `compare-relay-missing-item-guard` | **место**: `addons/sourcemod/scripting/entWatch/sdkhook.sp:93` -> `Compare_OnEqualTo / Relay_OnTrigger()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** Compare_OnEqualTo does `int item = ItemsGetByCompare(logic_compare); if(!Items[item].Owner)` (sdkhook.sp:91-93) and Relay_OnTrigger the same (sdkhook.sp:107-109), without testing the -1 that both lookups return on a miss (items.sp:401-421). A miss is reachable because an item can be cleared in place while its entity-output hook stays live: RemoveItemByConfig calls ItemClear(i) (helpers.sp:36-52), which zeroes Items[i].Compare/Relay but never calls ItemUnhook/UnhookSingleEntityOutput (items.sp:622-658 are separate functions). The hook therefore keeps firing for the rest of the round with no item behind it.

**Триггер.** Admin with rcon/root: sm_eadmin -> Configs -> pick a config that has `compareid` (or `relayid`) -> '[Remove item]'. ConfigMenu_Handler case 0 (admin_menu.sp:900-905) -> RemoveConfig (helpers.sp:26-34) -> RemoveItemByConfig -> ItemClear, leaving the logic_compare still hooked. Any player then activates that map's item logic (the map's own button path is untouched) -> the engine fires OnEqualTo -> Compare_OnEqualTo -> RoundStarted is true and activator is a player, so both early returns pass -> ItemsGetByCompare returns -1 -> `Items[-1].Owner` -> array-index runtime error, repeated on every activation.

**Доказательства.** sdkhook.sp:86-100 and 102-116 (no `item == -1` test, unlike sdkhook.sp:61-62 in OnButtonPress); items.sp:401-421 (both lookups return -1); helpers.sp:36-52 (ItemClear in place, no unhook); items.sp:650-657 (UnhookSingleEntityOutput lives only in ItemUnhook); sdktools outputnatives.cpp:66-82 (the hook is per (function, entity_ref) and survives until explicitly unhooked or the entity dies).

**Исправление.**

```
Add `if(item == -1) return;` after the lookup in both callbacks, and make RemoveItemByConfig call ItemUnhook(i) before ItemClear(i) so the stale output/SDKHook registrations are actually released.
```

### 43. sm_euse $<unknown> passes item == -1 into AssistUseAdmin -> Items[-1] out of bounds

- **id**: `euse-shortname-negative-index` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:73` -> `Command_Use()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** In the `$item` branch the return of ItemsGetByShortName() is used without the -1 check that the other branch has (the `while((item = ItemFindClientItem(...)) != -1)` loop). AssistUseAdmin then does Items[item].Button with item == -1. SourcePawn's bounds check is an UNSIGNED compare (`if (size_t(regs_.pri()) > limit)`), so a negative index does not silently read memory - it raises SP_ERROR_ARRAY_BOUNDS and aborts the command callback with an error log. Either way the command path is broken code, not merely unarmoured code: the sibling branch is guarded, this one is not.

**Триггер.** Any admin holding ADMFLAG_BAN types `sm_euse $xy` where `xy` is not the shortname of a currently-live item (wrong map, item already destroyed, typo) -> Command_Use -> ItemsGetByShortName returns -1 (items.sp:365) -> AssistUseAdmin(-1, client) -> Items[-1].Button -> runtime error "Array index is out of bounds" in errors_*.log, command silently does nothing.

**Доказательства.** assist_use.sp:73-74 `item = ItemsGetByShortName(buffer[1]); AssistUseAdmin(item, client);` vs the guarded branch at assist_use.sp:62-68; assist_use.sp:80 `if(!Items[item].Button || !Items[item].Owner)`; items.sp:356-366 ItemsGetByShortName returns -1; C:/develop/sm1.13-botox/source/sourcemod/sourcepawn/vm/interpreter.cpp:673-680 (unsigned bounds compare -> ReportOutOfBoundsError); C:/develop/sm1.13-botox/source/sourcemod/sourcepawn/compiler/code-generator.cpp:1094-1097 ("vm uses unsigned compare, this protects against negative indices").

**Исправление.**

```
item = ItemsGetByShortName(buffer[1]);

if(item != -1)
	AssistUseAdmin(item, client);

return Plugin_Handled;

(Note for the fixer: `sm_euse $` with an empty name currently resolves to item 0 because ItemsGetByShortName does strncmp with len 0 - that root cause is in items.sp, not here.)
```

> **Поправка верификатора.** Severity is minor, not major: the outcome is a runtime error in errors_*.log and the command doing nothing — no memory corruption (the bounds check is what makes it safe) and no gameplay state change. The finder's parenthetical about `sm_euse $` resolving to item 0 via strncmp with len 0 is also correct and is the more user-visible half of the bug (it force-uses an arbitrary item), and it lives in items.sp:356-366, not here.

### 44. "Am I aiming at a real button/door" test uses an infinite ray instead of the +USE radius

- **id**: `assist-trace-infinite-range` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:252` -> `AssistUseIsValidTarget()`
- **ось/инвариант**: correctness | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** The exclusion test traces with RayType_Infinite, so ANY func_button/door anywhere along the crosshair line - hundreds or thousands of units away, far outside the range at which the player could ever +USE it - makes the function return false and silently suppresses the assist. The engine's +USE search is bounded by PLAYER_USE_RADIUS (80 units): CBasePlayer::FindUseEntity uses `dist < PLAYER_USE_RADIUS`, a CEntitySphereQuery of that radius and `searchCenter + forward * PLAYER_USE_RADIUS`. The purpose of the test - "do not fire the item when the player is really pressing a map button" - only makes sense inside that radius; beyond it the module disables itself for no reason, which is exactly the failure it exists to prevent.

**Триггер.** Player holds one item and stands anywhere in a ZE map with his crosshair on a distant door or button (extremely common: corridor doors, boss-room buttons, elevator doors). He presses E -> AssistUseOnPlayerRunCmdPost -> AssistUseIsValidTarget -> TR_TraceRayFilter(..., RayType_Infinite, ...) hits that far entity -> classname contains "button" (or is a PUSE func_door) -> returns false -> assist skipped, item does not fire even though the player's own +USE could not reach anything.

**Доказательства.** assist_use.sp:252 `TR_TraceRayFilter(origin, angles, MASK_SOLID, RayType_Infinite, TraceFilter);` and assist_use.sp:256-275; C:/develop/sm-1.13/include/sdktools_trace.inc:161-165 (RayType_Infinite = "from the start position to infinity"), :370-376 TR_TraceRayFilter; C:/develop/hl2_src-leak-2017/src/game/shared/baseplayer_shared.h:15 `#define PLAYER_USE_RADIUS 80.f`; baseplayer_shared.cpp:1132,1182,1230 (all +USE searches bounded by PLAYER_USE_RADIUS).

**Исправление.**

```
Bound the ray to the engine's use range, e.g. compute the endpoint and use RayType_EndPoint:

float origin[3], angles[3], fwd[3], endpoint[3];
GetClientEyePosition(client, origin);
GetClientEyeAngles(client, angles);
GetAngleVectors(angles, fwd, NULL_VECTOR, NULL_VECTOR);
ScaleVector(fwd, 80.0);
AddVectors(origin, fwd, endpoint);
TR_TraceRayFilter(origin, endpoint, MASK_SOLID, RayType_EndPoint, TraceFilter);
```

> **Поправка верификатора.** Two corrections. (1) The ray is not literally infinite — it is MAX_TRACE_LENGTH long (trnatives.cpp:174); cosmetic, but the fix's rationale should say 'bounded to 80 units' rather than 'bounded at all'. (2) Severity is minor, not major: the failure mode is a false negative in a convenience module (the item simply is not auto-fired; nothing is miscounted, no state is corrupted, no invariant is broken). This is a tuning divergence from intent, not mechanically wrong code — under this project's 'wrong code vs unarmoured code' bar it is the weakest of the assist findings, and it should be fixed together with the prop_d prefix, not separately.

### 45. An item with both compareid and relayid counts one press twice if the map fires both

- **id**: `compare-and-relay-double-count` | **место**: `addons/sourcemod/scripting/entWatch/sdkhook.sp:76` -> `OnButtonPress()`
- **ось/инвариант**: invariant-I7 | **уверенность**: hypothesis | **вердикт верификатора**: UNCERTAIN

**Проблема.** OnButtonPress passes the press through whenever EITHER Compare or Relay is set, and the use is then counted by whichever output fires. Nothing prevents both from being set on the same item - config.sp reads compareid and relayid independently in both formats - and nothing dedupes the two callbacks. If the map wires button -> logic_compare -> logic_relay (a very ordinary Hammer pattern), one physical press runs Compare_OnEqualTo AND Relay_OnTrigger, each calling APIOnClientItemUse + ItemReload + PrintToChatItemAction. In MODE_MAXUSES/MODE_CHARGESCD that consumes two charges for one activation; in MODE_COOLDOWN it double-announces and re-arms the cooldown twice.

**Триггер.** Map config sets both `compareid` and `relayid` for one item and the map's logic_compare OnEqualTo triggers the logic_relay. Owner presses E -> OnButtonPress returns Plugin_Continue at sdkhook.sp:77 -> button OnPressed -> logic_compare OnEqualTo -> Compare_OnEqualTo counts use #1 -> the compare's output triggers the relay -> Relay_OnTrigger counts use #2 for the same press.

**Доказательства.** sdkhook.sp:70,76-77 (both branches treat Compare/Relay as interchangeable, no exclusivity); sdkhook.sp:86-116 (the two callbacks are identical and independent); config.sp:142-143 and config.sp:186-187 (compareid and relayid parsed independently, both may be non-zero); items.sp:204-223 (an item can hold both Compare and Relay).

**Исправление.**

```
Make the accounting single-source: when an item has a Compare, ignore its Relay output (and vice versa). E.g. in Relay_OnTrigger add `if(Items[item].Compare) return;` so the compare is authoritative, or record the last accounted GetGameTime() on the item and drop a second output in the same tick. Confirm against a live config first - if no production config sets both keys, leave it and note it.
```

### 46. Flag is set in ZR's pre-forward, so a blocked infection leaves a human wrongly flagged

- **id**: `halfzombie-flag-set-before-infection-confirmed` | **место**: `addons/sourcemod/scripting/entWatch/halfzombie.sp:30` -> `ZR_OnClientInfect()`
- **ось/инвариант**: invariant-I2 | **уверенность**: likely | **вердикт верификатора**: UNCERTAIN

**Проблема.** ZR_OnClientInfect is a blockable pre-forward - ZR's own documentation says "Plugin_Handled to block infection". entWatch calls HalfZombieDeterminateClient() from it unconditionally, before knowing whether the infection will happen. If any other plugin blocks it, the player stays human but keeps HalfZombie[client] == true, and ZR_OnClientHumanPost (the only per-client reset besides player_spawn and round start) never fires because he never stopped being human.

**Триггер.** Any third-party plugin (spawn protection, event/boss logic, an anti-infect zone) returns Plugin_Handled from ZR_OnClientInfect for client P, and entWatch's handler ran first with P's selected zombie class containing "frazzle". P remains an alive human with HalfZombie[P] == true. He then walks over an item: OnWeaponTouch -> `if(HalfZombie[client]) return Plugin_Handled;` (sdkhook.sp:16-17) - pickup refused; and OnTriggerTouch blocks the map's item trigger (sdkhook.sp:130-131) - until his next player_spawn or the next round_start clears the flag.

**Доказательства.** halfzombie.sp:30-35 (unconditional HalfZombieDeterminateClient in the pre-forward); C:/develop/sg-zr-swzedition/addons/sourcemod/scripting/include/zr/infect.zr.inc:100-113 ("Here you can modify any variable or block the infection entirely ... Plugin_Handled to block infection"); halfzombie.sp:24-28 (reset only via ZR_OnClientHumanPost); entWatch.sp:143-155 and entWatch.sp:177-179 (other resets are player_spawn / round start).

**Исправление.**

```
Set the flag once the infection is real - from ZR's post event (ZR_OnClientInfected) or one frame later - instead of in the blockable pre-forward. This is the same edit as the mother-zombie finding; do them together, not twice.
```

> **Поправка верификатора.** The fix note is right that this is the same edit as halfzombie-mother-class-mismatch and must be done once, not twice — and that finding IS proven, so the edit is justified by it regardless of this one. Do not present this finding as independent justification for the change.

### 47. #define REEQUIRE_PLUGIN typo leaves REQUIRE_PLUGIN undefined for every later include

- **id**: `halfzombie-requireplugin-typo` | **место**: `addons/sourcemod/scripting/entWatch/halfzombie.sp:8` -> `(file scope)()`
- **ось/инвариант**: api-use | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The standard optional-dependency idiom is `#undef REQUIRE_PLUGIN` / `#tryinclude <lib>` / `#define REQUIRE_PLUGIN`. Here the restore is misspelled REEQUIRE_PLUGIN, so REQUIRE_PLUGIN - which core.inc defines by default - stays undefined for the remainder of the translation unit. Today the impact is nil because every include after halfzombie.sp is a local .sp with no SharedPlugin block, but the file order in entWatch.sp puts sdkhook.sp, hud.sp, restrict.sp, transfer.sp, admin_menu.sp, spawn.sp, api.sp and stripper.sp after it: the first time any of them pulls in a third-party plugin include, that dependency will silently be marked optional and its natives left unresolved at runtime instead of failing at load.

**Триггер.** Compile-time/latent: spcomp processes entWatch.sp -> entWatch/halfzombie.sp:6-8 undefines REQUIRE_PLUGIN and never restores it -> every subsequent `#include "entWatch/*.sp"` (entWatch.sp:27-36) is compiled with REQUIRE_PLUGIN undefined.

**Доказательства.** halfzombie.sp:6-8 `#undef REQUIRE_PLUGIN / #tryinclude <zombiereloaded> / #define REEQUIRE_PLUGIN`; C:/develop/sm-1.13/include/core.inc:321-322 `#define REQUIRE_EXTENSIONS` / `#define REQUIRE_PLUGIN`; C:/develop/sg-zr-swzedition/addons/sourcemod/scripting/include/zombiereloaded.inc:40-49 (SharedPlugin required = 1 only `#if defined REQUIRE_PLUGIN`); entWatch.sp:26-36 (include order).

**Исправление.**

```
#define REQUIRE_PLUGIN
```

> **Поправка верификатора.** Impact is strictly latent and should be stated as such: I grepped every addons/sourcemod/scripting/entWatch/*.sp file for `#include` and found ZERO — no module file pulls any third-party include, and all of <sourcemod>/<sdkhooks>/<sdktools>/<clientprefs>/<entWatch> are already resolved at entWatch.sp:1-6, before halfzombie.sp. So today nothing whatsoever changes; the risk is entirely future. Fix it because it is a one-character typo with a clear correct value, not because anything is currently broken.

### 48. Restricted-player early return skips prevButtons, defeating the +USE edge detector

- **id**: `assist-restrict-return-skips-prevbuttons` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:155` -> `AssistUseOnPlayerRunCmdPost()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** Five of the six return paths in the function write `prevButtons[client] = buttons;` before returning; the restrict path does not. Consequently, for a restricted player holding +USE, prevButtons keeps the last value written (without IN_USE), so the `prevButtons[client] & IN_USE` edge test passes on every single tick instead of once per press, and the full precondition chain (including RestrictClientHasRestrict -> GetTime()) runs every tick for the whole time the key is held. It is an inconsistency in a per-tick forward, not a security hole - the restrict check itself still blocks the assist.

**Триггер.** An ebanned player holds +USE. Each tick: OnPlayerRunCmdPost -> AssistUseOnPlayerRunCmdPost -> edge test passes because prevButtons was never refreshed -> RestrictClientHasRestrict(client) true -> return without writing prevButtons -> repeats next tick, indefinitely.

**Доказательства.** assist_use.sp:148-156 vs the writes at assist_use.sp:151,165,172,180,189; restrict.sp:664-667 for the check itself; C:/develop/sm-1.13/include/entity_prop_stocks.inc:105 `#define IN_USE (1 << 5)`.

**Исправление.**

```
if(RestrictClientHasRestrict(client))
{
	prevButtons[client] = buttons;
	return;
}
```

### 49. Double-fire guard records only func_button OnPressed, not func_rot_button

- **id**: `assist-presstime-classname-gaps` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:29` -> `AssistUseInit()`
- **ось/инвариант**: invariant-I7 | **уверенность**: hypothesis | **вердикт верификатора**: CONFIRMED

**Проблема.** PressButtonTime - the guard that stops the assist from re-firing a button the player has just pressed for real (`diffAnyUse <= tick`) - is fed only by HookEntityOutput("func_button","OnPressed") and the two door OnOpen hooks. SourceMod's classname output hooks are an exact-name trie lookup, so func_rot_button is not covered, even though AssistUseInputByName explicitly supports func_rot_button item buttons. For such an item a genuine press that already ran OnButtonPress does not set PressButtonTime, and the assist sends a second "Use" in the same tick, producing a second OnButtonPress. Whether the second one is counted depends on ItemIsReady: it is blocked when a cooldown or m_flWait was armed, but MODE_PROTECT and MODE_MAXUSES with m_flWait <= 0 have nothing to block it, so Uses is incremented twice (or the API forward fires twice) for one physical press. The func_door variant has a related hole: OnOpen does not fire if the door is already open, so the guard misses there too.

**Триггер.** Item whose button is a func_rot_button, mode MAXUSES, button m_flWait 0. The owner aims at his own button (jump/look-down, the situation the module exists for) and presses E: engine PlayerUse -> CBaseButton::Use -> SDKHook_Use -> OnButtonPress counts use #1; the func_rot_button's OnPressed is not hooked, so PressButtonTime[client] is unchanged; the same tick's OnPlayerRunCmdPost -> AssistUse -> AcceptEntityInput("Use") -> OnButtonPress runs again, ItemIsReady still true -> use #2 counted for one press.

**Доказательства.** assist_use.sp:29-32 (only func_button/func_door/func_door_rotating/prop_door_rotating hooked); assist_use.sp:213-218 (func_rot_button explicitly handled by the forced press); assist_use.sp:161-167 (the diffAnyUse guard that depends on PressButtonTime); C:/develop/sm1.13-botox/source/sourcemod/extensions/sdktools/outputnatives.cpp:60-65 (classname hooks are looked up by the entity's exact classname); items.sp:447-489 ItemIsReady / items.sp:491-532 ItemReload (Wait only armed when m_flWait > 0).

**Исправление.**

```
HookEntityOutput("func_rot_button", "OnPressed", AssistUseOnButtonPressed);

added next to the existing func_button hook. (A stronger alternative is to stamp PressButtonTime[activator] from OnButtonPress itself, which covers every button class the plugin binds.)
```

> **Поправка верификатора.** The required state is narrower than stated and must be in the trigger line: the second press is only *counted* when the button's m_flWait <= 0. items.sp:498-504 ItemReload arms Items[].Wait only `if(wait > 0.0)`, and items.sp:451-452 ItemIsReady blocks on `Items[item].Wait >= time`. With the Hammer default 'Delay Before Reset' of 3s the second press is correctly rejected; the hole needs wait = -1 (a one-shot button, which is common) or 0. Under MODE_PROTECT the second press is harmless (ItemReload has no PROTECT case, items.sp:506-531, and use messages are suppressed), so the concrete damage is MODE_MAXUSES/MODE_CHARGESCD burning two charges and entWatch_OnClientItemUse firing twice for one physical press. Severity minor rather than major, because the finder's own confidence was 'hypothesis' and this repo ships no map config proving a func_rot_button item button exists; the stronger of the two suggested fixes (stamp PressButtonTime from OnButtonPress itself) is the right one since it covers every button class the plugin can bind.

### 50. Optional zombiereloaded dependency does not actually compile when absent

- **id**: `halfzombie-tryinclude-does-not-compile` | **место**: `addons/sourcemod/scripting/entWatch/halfzombie.sp:38` -> `HalfZombieDeterminate()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** halfzombie.sp declares zombiereloaded an OPTIONAL dependency (`#tryinclude <zombiereloaded>` at :7) and gates HalfZombieDeterminate() behind `#if defined _zr_included` (:38-53, :69). But entWatch.sp:126-131 calls HalfZombieDeterminate() gated only on `#if defined HALFZOMBIE`, which is defined unconditionally at entWatch.sp:15. With the ZR include missing the #tryinclude silently succeeds, _zr_included stays undefined, the function is never emitted, and the call becomes an undefined symbol. The module is therefore not optional at all: it hard-requires the include it claims to try. The correct idiom is an absent-guard in the module file: `#if !defined _zr_included` -> `#undef HALFZOMBIE` -> `#endinput`. The same file also emits `#warning "Halfzombie module: not included"` at :2 whenever HALFZOMBIE is undefined, so the gate-off build is not warning-free either, which CLAUDE.md's Build section requires.

**Триггер.** Anyone compiling the plugin on a machine without zombiereloaded.inc on the include path (a fresh clone, CI, or a server operator who does not run ZR): spcomp -i"addons/sourcemod/scripting/include" addons/sourcemod/scripting/entWatch.sp -> entWatch.sp:15 defines HALFZOMBIE -> entWatch/halfzombie.sp:7 #tryinclude fails silently -> :38 `#if defined _zr_included` excludes HalfZombieDeterminate -> entWatch.sp:129 references it -> error 017: undefined symbol "HalfZombieDeterminate". Mirror case: compiling with HALFZOMBIE commented out at entWatch.sp:15 succeeds but emits a warning from halfzombie.sp:2.

**Доказательства.** halfzombie.sp:1-8 (`#if !defined HALFZOMBIE / #warning ... / #endinput`, then `#undef REQUIRE_PLUGIN / #tryinclude <zombiereloaded>`); halfzombie.sp:38-53 and :69 (`#if defined _zr_included` ... `#endif` wrapping HalfZombieDeterminate); entWatch.sp:126-131 (`public void OnConfigsExecuted()` -> `#if defined HALFZOMBIE / HalfZombieDeterminate(); / #endif`); entWatch.sp:15 (`#define HALFZOMBIE`). CLAUDE.md 'Target environment': 'Optional dependency: zombiereloaded ... pulled via #tryinclude in the HALFZOMBIE module only'; CLAUDE.md 'Build': 'When touching a gated module, keep both builds (gate on and off) compiling warning-free.'

**Исправление.**

```
In halfzombie.sp, immediately after the #tryinclude, add the absent-guard so the module truly self-disables:

#undef REQUIRE_PLUGIN
#tryinclude <zombiereloaded>
#define REQUIRE_PLUGIN

#if !defined _zr_included
    #undef HALFZOMBIE
    #endinput
#endif

This also fixes the REEQUIRE_PLUGIN typo in the same three lines - one edit, not two. Separately, drop the `#warning` at :2 so the gate-off build is warning-free; the #endinput alone is the whole mechanism.
```

### 51. The restrict / half-zombie guard also supersedes EndTouch, stranding the player in the trigger's touch list

- **id**: `triggertouch-blocks-endtouch-desync` | **место**: `addons/sourcemod/scripting/entWatch/sdkhook.sp:118` -> `OnTriggerTouch()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** OnTriggerTouch is registered for SDKHook_StartTouch, SDKHook_EndTouch AND SDKHook_Touch (items.sp:198-200), and returns Plugin_Handled for a restricted or half-zombie activator on all three. SDKHooks supersedes the original on Pl_Handled, so blocking EndTouch means CBaseTrigger::EndTouch never runs. That function is what removes the player from m_hTouchingEntities and fires m_OnEndTouch and, when the list empties, OnEndTouchAll. Blocking StartTouch and EndTouch together is self-consistent only if the player's state does not change while he is inside the trigger - but it can. If he entered un-restricted (so CBaseTrigger::StartTouch added him to m_hTouchingEntities) and becomes restricted or half-zombie before he leaves, his removal is suppressed and the map's trigger believes he is inside it for the rest of the round. Blocking EndTouch buys no protection at all - the item hand-over the guard exists to stop happens on StartTouch/Touch, never on leaving.

**Триггер.** Player P, not ebanned, walks into an entWatch-registered item trigger: SDKHook_StartTouch -> sdkhook.sp:118-134 OnTriggerTouch returns Plugin_Continue -> triggers.cpp:480-502 CBaseTrigger::StartTouch adds P to m_hTouchingEntities and fires OnStartTouch/OnStartTouchAll. While P is still inside, an admin runs `sm_eban P 30` -> restrict.sp SQL_Callback_BanClient sets Restricts[P].Expires so restrict.sp:664-667 RestrictClientHasRestrict(P) is now true. P walks out -> SDKHook_EndTouch -> sdkhook.sp:126-127 returns Plugin_Handled -> sdkhooks/extension.cpp:1041-1045 Hook_EndTouch RETURN_META(MRES_SUPERCEDE) -> triggers.cpp:510-560 CBaseTrigger::EndTouch never executes -> P stays in m_hTouchingEntities, OnEndTouch and OnEndTouchAll never fire for that trigger. Identical path via HALFZOMBIE: P is inside the trigger when ZR infects him as a frazzle class -> halfzombie.sp:30-35 sets HalfZombie[P] -> sdkhook.sp:130-131 blocks his EndTouch.

**Доказательства.** sdkhook.sp:118-134 (single handler, no distinction between the three hook types); items.sp:198-200 `SDKHook(entity, SDKHook_StartTouch/EndTouch/Touch, OnTriggerTouch)`; C:/develop/sm1.13-botox/source/sourcemod/extensions/sdkhooks/extension.cpp:1041-1045 `void SDKHooks::Hook_EndTouch(...) { cell_t result = Call(...); if(result >= Pl_Handled) RETURN_META(MRES_SUPERCEDE); }`; C:/develop/hl2_src-leak-2017/src/game/server/triggers.cpp:510-522 (`m_hTouchingEntities.FindAndRemove( hOther ); m_OnEndTouch.FireOutput(...)`) and :524-560 (the OnEndTouchAll sweep); triggers.cpp:480-502 CBaseTrigger::StartTouch for the asymmetry; restrict.sp:664-667 for the mid-touch state change.

**Исправление.**

```
Give EndTouch its own pass-through instead of sharing the guarded handler:

public Action OnTriggerEndTouch(int entity, int activator)
{
    return Plugin_Continue;
}

and register it at items.sp:199 in place of OnTriggerTouch, unhooking it symmetrically at items.sp:51 and items.sp:647. Blocking EndTouch protects nothing - the item hand-over happens on StartTouch/Touch.
```

### 52. sm_euse announces a forced use that OnButtonPress refused

- **id**: `assistuseadmin-reports-success-when-press-blocked` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:207` -> `AssistUseInputByName()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** AssistUseInputByName returns true unconditionally after AcceptEntityInput for func_button, func_rot_button and func_door (assist_use.sp:207-231). It ignores AcceptEntityInput's return value, and more importantly it cannot see that OnButtonPress superseded the press: SDKHook_Use is a PRE hook, so a Plugin_Handled from sdkhook.sp:65/68/71 stops the button firing but leaves AcceptEntityInput's own return unaffected. AssistUseAdmin then takes the `if(result)` branch and broadcasts 'Assist use admin <item>' to the owner's team for something that never happened. This is the same failure direction CLAUDE.md rule 4 warns about - entWatch reporting an activation the map did not perform - just via chat rather than the cooldown.

**Триггер.** Admin with ADMFLAG_BAN runs `sm_euse <owner>` (or `sm_euse $<short>`) while the item is on cooldown or out of uses: assist_use.sp:42-76 Command_Use -> :78-99 AssistUseAdmin (passes, Button and Owner are both set) -> :87 AssistUse -> :200 AssistUseInputByName -> :209 AcceptEntityInput(Button,"Use",Owner,Owner) -> sdkhook.sp:51 OnButtonPress -> :70-71 `if(!Items[item].Compare && !Items[item].Relay && !ItemIsReady(item)) return Plugin_Handled;` -> the button does not fire, nothing is counted -> control returns to assist_use.sp:211 `return true` -> :93-97 PrintToTeam '<admin> Assist use admin <item>'. Same outcome when the owner is ebanned (sdkhook.sp:67-68) or the button is m_bLocked (items.sp:454-455).

**Доказательства.** assist_use.sp:207-231 (three branches, each `AcceptEntityInput(...); return true;` with no result inspection); assist_use.sp:87-98 (`bool result = AssistUse(item); ... if(result) { PrintToTeam(...); return true; }`); sdkhook.sp:64-71 (the three Plugin_Handled exits); C:/develop/sm1.13-botox/source/sourcemod/extensions/sdkhooks/extension.cpp:729-731 (SDKHook_Use is SH_ADD_MANUALVPHOOK(..., false), i.e. a PRE hook, so the block happens inside AcceptEntityInput and is invisible to its caller); C:/develop/sm-1.13/include/sdktools_entinput.inc AcceptEntityInput (reports whether the entity accepted the input, not whether a Use hook allowed it).

**Исправление.**

```
Make the forced-press path report what happened rather than what was attempted: set a module-local flag from OnButtonPress on the accepted path (sdkhook.sp:79-82) and read it back in AssistUseAdmin after AssistUse() returns, e.g.

bool AssistUseAccepted;
...
AssistUseAccepted = false;
bool result = AssistUse(item);
if(result && !AssistUseAccepted && !Items[item].Compare && !Items[item].Relay)
    result = false;

Do not try to infer it from Items[].Wait/Cooldown - ItemReload has no MODE_PROTECT case (items.sp:506-531), so a PROTECT item would be reported as refused when it actually fired.
```

### 53. DISPLAY_USE suppression is restored before the compare/relay use message is emitted

- **id**: `assistuseadmin-display-suppression-misses-compare-relay` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:85` -> `AssistUseAdmin()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** AssistUseAdmin clears DISPLAY_USE on the config (assist_use.sp:85), calls AssistUse, and restores it at :91 - the intent being that the normal 'X used <item>' line is replaced by the 'Assist use admin' line. That works only when the use is announced synchronously inside AcceptEntityInput. For an item with a Compare or Relay it is not: sdkhook.sp:76-77 returns Plugin_Continue without announcing, and the announcement comes later from Compare_OnEqualTo (sdkhook.sp:99) or Relay_OnTrigger (:115) - the map's logic_compare/logic_relay chain routinely runs through the delayed event queue, i.e. after AssistUseAdmin has already restored the flag at :91. The result is both messages, which is exactly what the suppression exists to prevent, and it is silently mode-dependent.

**Триггер.** Admin with ADMFLAG_BAN runs `sm_euse $<short>` on an item whose config sets compareid or relayid: assist_use.sp:83-85 saves and clears DISPLAY_USE -> :87 AssistUse -> AcceptEntityInput -> sdkhook.sp:51 OnButtonPress -> :76-77 `if(Items[item].Compare || Items[item].Relay) return Plugin_Continue;` (no announcement) -> control returns, assist_use.sp:89-92 restores DISPLAY_USE -> :95 prints 'Assist use admin' -> the map's button OnPressed drives the logic_compare, whose OnEqualTo fires (immediately or after the configured output delay) -> sdkhook.sp:86-100 Compare_OnEqualTo -> :99 PrintToChatItemAction(item, ACTION_USE) -> chat.sp:47-53 sees DISPLAY_USE set again and prints the ordinary use line as well.

**Доказательства.** assist_use.sp:83-92 (`bool showUse = ConfigGetDisplay(...); Configs[...].Display &= ~(DISPLAY_USE); bool result = AssistUse(item); if(showUse) Configs[...].Display |= DISPLAY_USE;`); sdkhook.sp:76-77 (compare/relay pass-through with no announcement); sdkhook.sp:96-99 and :112-115 (the deferred APIOnClientItemUse + ItemReload + PrintToChatItemAction); chat.sp:47-53 (ACTION_USE gated on DISPLAY_USE at call time); CLAUDE.md domain rule 7 (with a Compare or Relay the use is counted from the entity output instead of the press).

**Исправление.**

```
Suppress per item and per pending use rather than per config-and-window: add a one-shot 'suppress next use announcement' flag set in AssistUseAdmin and consumed in PrintToChatItemAction's ACTION_USE case, so it survives until the compare/relay callback actually announces. Note that putting the flag on the Item enum struct changes a layout that include/entWatch.inc treats as public API (entWatch_GetItem does a runtime sizeof check), forcing every consumer to recompile - a parallel module-local array indexed the same way avoids that, at the cost of the I6 index-stability problem, so a file-scope `int AssistUseSuppressItem = -1;` reset on the next round start is the safer form.
```

### 54. prevButtons survives the client slot, swallowing the new occupant's first E press

- **id**: `assist-prevbuttons-not-reset-on-disconnect` | **место**: `addons/sourcemod/scripting/entWatch/assist_use.sp:237` -> `AssistUseOnClientDisconnect()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** AssistUseOnClientDisconnect resets PressButtonTime and AssistUseTime but not prevButtons, the static edge-detector array declared inside AssistUseOnPlayerRunCmdPost at :148. If the departing client's last processed usercmd had IN_USE set, the slot keeps that bit. The next player to take the slot fails the rising-edge test at :149 on his first +USE and the assist is skipped; it only recovers after he releases E once, because that branch does write prevButtons back at :151. Same class of per-client state leak as the restrict-path omission already reported, in the same function, and the fix belongs in the same edit.

**Триггер.** Player P holds +USE at the moment he disconnects (rage-quit mid-activation, or a timeout while the key is down): the last OnPlayerRunCmdPost leaves prevButtons[P] with IN_USE set -> client.sp:86-99 OnClientDisconnect -> assist_use.sp:237-241 AssistUseOnClientDisconnect clears only PressButtonTime and AssistUseTime. New player Q connects into slot P, spawns, picks up an item, presses and holds E -> entWatch.sp:212-217 OnPlayerRunCmdPost -> assist_use.sp:149 `prevButtons[client] & IN_USE` is true from P -> :151 writes back, :152 returns -> the assist does not fire for that press; Q must release E and press again.

**Доказательства.** assist_use.sp:148 `static int prevButtons[MAXPLAYERS + 1];`; assist_use.sp:149-153 (the edge test and the write-back); assist_use.sp:237-241 AssistUseOnClientDisconnect (resets PressButtonTime and AssistUseTime only); client.sp:92-94 (the only caller); C:/develop/sm-1.13/include/entity_prop_stocks.inc:105 `#define IN_USE (1 << 5)`. Contrast client.sp:96 `Clients[client].Clear()` and client.sp:98 RestrictOnClientDisconnect, which do clear their per-client state.

**Исправление.**

```
Hoist prevButtons to file scope next to PressButtonTime/AssistUseTime and clear it with them:

float PressButtonTime[MAXPLAYERS + 1];
float AssistUseTime[MAXPLAYERS + 1];
int prevButtons[MAXPLAYERS + 1];

void AssistUseOnClientDisconnect(int client)
{
	PressButtonTime[client] = 0.0;
	AssistUseTime[client] = 0.0;
	prevButtons[client] = 0;
}

Do this in the same edit as the restrict-path prevButtons omission at assist_use.sp:155-156 - they are one defect in two places.
```

### 55. GFL parser yields Mode = -1 for a missing/zero `mode`; only the upper bound is clamped

- **id**: `config-gfl-mode-minus-one` | **место**: `addons/sourcemod/scripting/entWatch/config.sp:151` -> `ConfigBrowseKeyGFL()`
- **ось/инвариант**: invariant-I1 | **уверенность**: likely | **вердикт верификатора**: UNCERTAIN

**Проблема.** `c.Mode = kv.GetNum("mode") - 1;` (config.sp:151) uses GetNum's default of 0 (keyvalues.inc:166 `public native int GetNum(const char[] key, int defvalue=0)`), so a GFL block without a `mode` key (or with `mode 0`) produces Mode = -1. The clamp that follows only bounds the top end (`if(c.Mode > MODE_CHARGESCD) c.Mode = MODE_PROTECT;`, config.sp:153-154) — there is no lower clamp, so -1 (and any negative `mode` value) survives into Configs[]. -1 is not one of MODE_PROTECT..MODE_CHARGESCD (config.sp:17-21) yet it is load-bearing in two places. (a) items.sp:250 explicitly aborts button auto-detection when `Configs[...].Mode == -1`, so an item whose config also omits `buttonid` never gets a button bound -> SDKHook_Use is never installed (items.sp:183 is only reached through REGISTER_BUTTON) -> OnButtonPress never runs for that item -> the ownership guard of domain rule 1 (I1) is silently absent and any player can fire the item from the owner's body. (b) With `buttonid` present the button IS hooked, but ItemIsReady falls into `default: return true` (items.sp:483-486) and ItemReload's switch has no matching case (items.sp:506-531), so the item is permanently 'ready', no cooldown/uses are ever recorded, and because Mode != MODE_PROTECT the DISPLAY_USE bit is not cleared (config.sp:156-157) so every press is announced as a use — entWatch's readiness is unconditionally ahead of the map's, which is exactly the dangerous direction of I4.

**Триггер.** (a) Server loads a map whose configs/entwatch/<map>.cfg is in GFL format and one item block has `hammerid` but neither `mode` nor `buttonid`. ConfigOnMapStart -> ConfigParse -> ConfigLoad -> ConfigBrowse -> ConfigBrowseKey -> ConfigBrowseKeyGFL sets Mode=-1. Round start: ItemsOnRoundStart -> ItemsOnEntitySpawned -> ItemsInitiateItem -> ItemsRegisterItemEntity(REGISTER_WEAPON) -> ItemProcessCheckButton -> CreateTimer(0.5, Timer_ItemFindButton) -> the timer returns at items.sp:250 because Mode == -1 -> Items[item].Button stays 0 -> no SDKHook_Use -> any non-owner pressing E on the item's invisible button fires it. (b) Same config but with `buttonid` set: the button is hooked, OnButtonPress -> ItemIsReady returns true through the default branch every single press, ItemReload records nothing, PrintToChatItemAction(ACTION_USE) announces every press.

**Доказательства.** config.sp:151 `c.Mode = kv.GetNum("mode") - 1;`; config.sp:153-154 upper clamp only; config.sp:156-157 PROTECT-only DISPLAY_USE suppression; keyvalues.inc:166 (GetNum defvalue=0); items.sp:250 `... || Configs[Items[item].Config].Mode == -1) return Plugin_Continue;`; items.sp:483-486 `default: return true;`; items.sp:506-531 (ItemReload switch has no default); items.sp:183 SDKHook(entity, SDKHook_Use, OnButtonPress) reachable only via REGISTER_BUTTON; CLAUDE.md domain rules 1 and 4.

**Исправление.**

```
Decide the intent of -1 FIRST — it is currently an accident that items.sp:250 leans on. Either (1) make it explicit: add `#define MODE_NONE -1` next to the other MODE_* defines, keep the GFL arithmetic, add a lower clamp `if(c.Mode < MODE_NONE) c.Mode = MODE_NONE;` plus a LogError naming the config block, and clear DISPLAY_USE for MODE_NONE so a mode-less item does not announce phantom uses; or (2) treat a missing key as the documented default: `c.Mode = kv.GetNum("mode", MODE_DEFAULT + 1) - 1; if(c.Mode < MODE_PROTECT || c.Mode > MODE_CHARGESCD) c.Mode = MODE_PROTECT;` — but option (2) makes the guard at items.sp:250 dead and it must be removed in the same change, not left behind.
```

> **Поправка верификатора.** Keep the finding as a HYPOTHESIS, not a major defect, and reframe it. The only part that is unambiguously wrong code is that the clamp is one-sided: config.sp:153 catches Mode > MODE_CHARGESCD but nothing catches Mode < -1, so `mode -1` or lower in a file produces Mode <= -2, which items.sp:250 (`== -1`) does NOT recognise while items.sp:483-486 still returns 'always ready' -- i.e. the two out-of-range directions are asymmetric in safety (high side falls back to MODE_PROTECT, the safest mode; low side falls back to always-ready + DISPLAY_USE set, the I4-dangerous direction). The correct fix is therefore NOT to remove -1 (that would kill the deliberate guard at items.sp:250 and break the admin-editor round-trip at admin_menu.sp:1064) but at most: (a) name it -- `#define MODE_NONE -1` -- and (b) clamp `if(c.Mode < MODE_NONE) c.Mode = MODE_PROTECT;`, plus optionally clear DISPLAY_USE for MODE_NONE at config.sp:156 so a mode-less item cannot announce a use it never counted. Do not apply any of this before reading a real production GFL config; the same one-sided clamp exists in the UNLOZE branch at config.sp:194-195.

### 56. itemcolor read with an empty default and absent from colors.cfg: fallback colour is a bare '#'

- **id**: `colors-itemcolor-missing-default` | **место**: `addons/sourcemod/scripting/entWatch/colors.sp:29` -> `ColorsInit()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** colors.sp:29 reads `itemcolor` with GetString's implicit `defvalue=""` (keyvalues.inc:159), and the shipped configs/entwatch/colors.cfg contains only tagcolor/nickcolor/othercolor — no itemcolor. Colors[COLOR_ITEM] is therefore the empty string, and every path that relies on it produces a colour token with no hex digits: ConfigClear (config.sp:298-300) leaves Color = "#"; the GFL parser's default for a missing `color` key (config.sp:132) leaves Color = "#"; and ColorNameToColorCode's fallback for an unknown colour name (colors.sp:53 `FormatEx(color, size, "#%s", Colors[COLOR_ITEM])`) also yields "#". Consumers print `Configs[...].Color[1]` — the string with the '#' stripped — directly after a \x07 escape (chat.sp:68-74, transfer.sp:71/77, spawn.sp:76, assist_use.sp:95), so the message contains a \x07 escape immediately followed by the item name instead of \x07RRGGBB. The colour escape then consumes the characters that follow it, mangling the item name in every pick/drop/use/transfer/spawn announcement for any config that does not carry its own colour. Note also that the three keys that ARE present are read into char[32] with a hard-coded 32 rather than sizeof(Colors[]) — correct today, fragile if the array is resized.

**Триггер.** Any server running the repository's configs/entwatch/colors.cfg (no `itemcolor` key). OnPluginStart -> ColorsInit -> Colors[COLOR_ITEM] = "". Then any map whose entwatch config has an item block without a `color` key: ConfigBrowseKeyGFL (config.sp:132) leaves Color = "#" -> a player picks the item up -> ClientTakeItem -> PrintToChatItemAction(item, ACTION_PICK) -> chat.sp:68 formats "\x07%s%s" with Color[1] == "" -> SendMessage -> SayText2 carries a \x07 with no hex payload. Same for the unknown-colour-name fallback at colors.sp:53 when a config uses e.g. "{fuscia}".

**Доказательства.** colors.sp:29 `hKeyValues.GetString("itemcolor", Colors[COLOR_ITEM], 32);`; keyvalues.inc:159 `public native void GetString(const char[] key, char[] value, int maxlength, const char[] defvalue="")`; addons/sourcemod/configs/entwatch/colors.cfg (only tagcolor/nickcolor/othercolor); colors.sp:53 fallback; config.sp:132 and config.sp:298-300 (both use Colors[COLOR_ITEM] as the default); chat.sp:68-74 `"\x07%s%N (%s) \x07%s%t \x07%s%s"` with Configs[...].Color[1]; transfer.sp:71, spawn.sp:76, assist_use.sp:95. (The precise CS:S rendering of a \x07 escape without 6 hex digits is engine behaviour I did NOT verify from a first-party source; the code-level defect — an empty string where a 6-digit hex payload is required — is proven.)

**Исправление.**

```
Give the key a usable default at the single point of truth: `hKeyValues.GetString("itemcolor", Colors[COLOR_ITEM], sizeof(Colors[]), "FFFFFF");` (and use sizeof(Colors[]) for the other three reads too), and add `"itemcolor" "FFFFFF"` to configs/entwatch/colors.cfg so an existing installation is fixed without a plugin update.
```

> **Поправка верификатора.** Severity is minor, not major: the failure is purely cosmetic (chat text mangling). No ownership, restrict, cooldown or use-accounting path reads Configs[].Color -- I checked every consumer (chat.sp:73, transfer.sp:71/77, spawn.sp:76, assist_use.sp:95, admin_menu.sp:1043) and all of them are display-only. Also drop the `sizeof(Colors[])` remark from the finding: colors.sp:10 declares `char Colors[COLOR_TOTAL][32]`, so the hard-coded 32 at colors.sp:26-29 is exactly right and is a style point, not a defect (and style is out of scope). The fix stands: give colors.sp:29 a real default ("FFFFFF") and add the key to the shipped colors.cfg so existing installs heal without a plugin update.

### 57. KeyValues handle leaked when ImportFromFile fails

- **id**: `config-kv-leak-importfail` | **место**: `addons/sourcemod/scripting/entWatch/config.sp:63` -> `ConfigLoad()`
- **ось/инвариант**: handles | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** ConfigLoad creates the KeyValues at config.sp:61 and returns at config.sp:64 when ImportFromFile fails, skipping the only `delete kv` (config.sp:75). One KeyValues handle is leaked per map load whose config file exists but does not parse. Unlike the SetFailState path in colors.sp (where the plugin is evicted and its handles are released), the plugin keeps running here, so the leak accumulates for the lifetime of the server process.

**Триггер.** Server changes to a map for which configs/entwatch/<map>.cfg exists but is malformed (unbalanced braces, truncated file, a config half-written by a crashed AdminConfigSave). OnMapStart -> ConfigOnMapStart -> ConfigParse -> ConfigLoad: FileExists(path) is true, `kv.ImportFromFile(path)` returns false, the function returns false at line 64 with `kv` still open. Repeats on every subsequent load of that map.

**Доказательства.** config.sp:61 `KeyValues kv = new KeyValues("Config");`; config.sp:63-64 `if(!kv.ImportFromFile(path)) return false;`; config.sp:75 `delete kv;` (only reached on success); keyvalues.inc:88 `public native bool ImportFromFile(const char[] file);` (returns false on parse failure). Contrast colors.sp:21-24 where the failure path calls SetFailState, which evicts the plugin (sm1.13-botox/source/sourcemod/core/logic/smn_core.cpp:550-580: EvictWithError + ReportFatalError), so the missing delete there is not a practical leak.

**Исправление.**

```
Delete before the early return: `if(!kv.ImportFromFile(path)) { delete kv; return false; }` — and log the failing path, since today a broken config is indistinguishable from an absent one.
```

> **Поправка верификатора.** Trigger must be rewritten: the only way to reach config.sp:64 is an I/O failure in the window between `FileExists(path)` (config.sp:58) and `kv.ImportFromFile(path)` (config.sp:63) -- the file is deleted/renamed by another process, or the Valve filesystem cannot open a path that SourceMod's FileExists (which tests the OS path) said was there. That makes this a genuine but near-unreachable leak; keep it as a one-line hygiene fix (`if(!kv.ImportFromFile(path)) { delete kv; return false; }`), not a reliability problem. Also drop the finder's rationale 'today a broken config is indistinguishable from an absent one' -- it is false for the reason above; a broken config silently parses as far as it can and ConfigLoad returns TRUE. (That the partial parse is itself silent is a separate observation, and see the verdict on config-silent-drops.) The colors.sp contrast the finder drew is fine but I did not need it: SetFailState evicts the plugin and its handles regardless.

### 58. Color written at offset 1 with the full sizeof: one byte past Config.Color into Config.Filter

- **id**: `config-color-getstring-oob` | **место**: `addons/sourcemod/scripting/entWatch/config.sp:132` -> `ConfigBrowseKeyGFL()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** `kv.GetString("color", c.Color[1], sizeof(c.Color), ...)` passes the buffer's full size (16) while starting one byte in, so the writable window is Color[1..16] — Color[16] is out of bounds. Config.Color is char[16] (Config.inc:21) and the next field is char Filter[64] (Config.inc:23); enum-struct fields are laid out in declaration order, so byte 16 of Color is byte 0 of Filter. SourceMod does not bounds-check the destination: smn_KvGetString passes the plugin address straight to StringToLocalUTF8, which only validates that the address lies inside plugin memory and then writes `dest[len] = '\0'` with len up to maxbytes-1 (plugin-context.cpp:319-350). The identical mistake is repeated at config.sp:177 (UNLOZE) and config.sp:300 (`strcopy(Configs[config].Color[1], sizeof(Configs[].Color), ...)`; string.inc:127 documents destLen as including the null terminator), and again at admin_menu.sp:950. The stray byte is always the NUL terminator and Filter is (re)written immediately afterwards at config.sp:135/179, so today the corruption is masked — but the arithmetic is wrong and the string it produces can be 16 characters long in a 16-byte field, i.e. it is only NUL-terminated *because* of the out-of-bounds write. The visible half of the bug is truncation: with '#' occupying Color[0], a `{name}` colour is cut at 15 characters, so every named colour of 14+ characters (cornflowerblue, blanchedalmond, darkolivegreen, lightslategray/grey, lightsteelblue, mediumvioletred, mediumslateblue, mediumturquoise, mediumaquamarine, mediumspringgreen, lightgoldenrodyellow) loses its closing brace, ColorNameToColorCode bails at colors.sp:41-42, and the raw truncated text is emitted as the chat colour.

**Триггер.** Server loads a map whose GFL-format config contains `"color" "{lightgoldenrodyellow}"` (or any name >= 14 chars). ConfigOnMapStart -> ConfigParse -> ConfigLoad -> ConfigBrowse -> ConfigBrowseKeyGFL: GetString writes 15 chars at Color[1] and the terminating NUL at Color[16] == Filter[0] (out of bounds); Color becomes "#{lightgoldenro"; ColorNameToColorCode finds no '}' and returns unchanged (colors.sp:39-42); a player then picks the item up -> PrintToChatItemAction -> chat.sp:73 prints "{lightgoldenro" as the colour payload.

**Доказательства.** config.sp:132, config.sp:177, config.sp:300 (all pass sizeof(...Color) at offset 1); Config.inc:21 `char Color[16];` immediately followed by Config.inc:23 `char Filter[64];`; keyvalues.inc:159 (maxlength = maximum length of the value buffer); string.inc:127 `native int strcopy(char[] dest, int destLen, const char[] source);` with `destLen Destination buffer length (includes null terminator)`; sm1.13-botox/source/sourcemod/core/smn_keyvalues.cpp:276-301 (smn_KvGetString -> StringToLocalUTF8(params[3], params[4], ...)); sourcepawn/vm/plugin-context.cpp:319-350 (`if (len >= maxbytes) len = maxbytes - 1; memmove(...); dest[len] = '\0';` — no array-bounds validation); colors.sp:41-42 (early return when '}' is missing).

**Исправление.**

```
Pass the remaining space, not the whole buffer, at all four sites: `kv.GetString("color", c.Color[1], sizeof(c.Color) - 1, Colors[COLOR_ITEM]);` (config.sp:132), the same at config.sp:177, `strcopy(Configs[config].Color[1], sizeof(Configs[].Color) - 1, Colors[COLOR_ITEM]);` (config.sp:300) and admin_menu.sp:950. If names longer than 13 characters must be supported, widen Config.Color — but that changes sizeof(Config) and therefore forces every API consumer to recompile (api.sp:101), so it is an API-breaking change, not a free one.
```

> **Поправка верификатора.** The finding is right but understates one site and overstates the rest. At the three config.sp sites the stray NUL IS harmless -- Filter is rewritten immediately afterwards (config.sp:135 for GFL, config.sp:179 for UNLOZE) and at config.sp:300 Filter was already zeroed at config.sp:291 and Colors[COLOR_ITEM] is 6 hex chars in practice. The one UNMASKED site is admin_menu.sp:950: `strcopy(Configs[cfg].Color[1], sizeof(Configs[].Color), args)` takes the admin's raw say-text and nothing rewrites Filter afterwards (Filter is a different menu slot, case 3 at admin_menu.sp:954). So an admin using sm_eadmin -> Configs -> Color and typing 15+ characters -- e.g. the perfectly natural `{lightgoldenrodyellow}` -- silently zeroes Configs[cfg].Filter[0], after which OnButtonPress's `if(Configs[Items[item].Config].Filter[0])` guard (sdkhook.sp:73-74) stops writing the owner's targetname. On maps that implement their own filter_activator_name owner check that is domain rule 3 (I3) silently disabled: the owner's presses stop working until the next map load. That, not the config.sp sites, is the trigger worth quoting. Fix all four sites with `sizeof(...) - 1` as proposed; note that doing so tightens named colours from 13 to 12 characters, so widening Config.Color would be the real fix -- and that is an API-breaking struct change (api.sp:101 sizeof check).

### 59. UNLOZE parser overwrites the default colour with an empty string when `color` is absent

- **id**: `config-unloze-color-no-default` | **место**: `addons/sourcemod/scripting/entWatch/config.sp:177` -> `ConfigBrowseKeyUNLOZE()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** ConfigInit -> ConfigClear has just seeded the entry with the default colour (config.sp:298-300, `Color = "#" + Colors[COLOR_ITEM]`) and `c` is a copy of it, but config.sp:177 calls `kv.GetString("color", c.Color[1], sizeof(c.Color))` without a defvalue. GetString always writes, so when the key is missing the implicit `defvalue=""` (keyvalues.inc:159) destroys the seeded default and leaves Color = "#", i.e. an empty colour payload for every consumer that prints Color[1]. The GFL branch does not have this problem because it passes Colors[COLOR_ITEM] as the default (config.sp:132) — the two parsers diverge for no stated reason. Secondly, the UNLOZE branch never calls ColorNameToColorCode, so a `{name}` colour that works in a GFL config is emitted literally from an UNLOZE config.

**Триггер.** Server loads a map whose config is in UNLOZE format (blocks keyed by `weaponid`, detected at config.sp:114) and an item block omits `color`. ConfigOnMapStart -> ConfigParse -> ConfigLoad -> ConfigBrowse -> ConfigBrowseKey -> ConfigBrowseKeyUNLOZE line 177 writes "" over the default -> a player picks the item up -> PrintToChatItemAction -> chat.sp:73 emits \x07 with no hex payload followed by the item name.

**Доказательства.** config.sp:169 `Config c; c = Configs[Configs_Count];` (copy of the freshly defaulted entry), config.sp:298-300 (the default that is destroyed), config.sp:177 (no defvalue), config.sp:132 (GFL passes Colors[COLOR_ITEM]); keyvalues.inc:159 (defvalue defaults to ""); chat.sp:73 consumption.

**Исправление.**

```
Mirror the GFL branch: `kv.GetString("color", c.Color[1], sizeof(c.Color) - 1, Colors[COLOR_ITEM]);`. Whether the UNLOZE branch should also run ColorNameToColorCode is a product decision — if named colours are meant to work in both formats, add the call; if not, leave it and say so.
```

> **Поправка верификатора.** Severity minor (cosmetic chat only, same reasoning as colors-itemcolor-missing-default -- no gameplay path reads Color). One nuance the finding misses: this defect is NOT fixed by giving colors.sp:29 a proper itemcolor default, because config.sp:177 destroys the seeded value regardless of what that value is. It must be fixed at config.sp:177 itself. Combined with the OOB finding the correct line is `kv.GetString("color", c.Color[1], sizeof(c.Color) - 1, Colors[COLOR_ITEM]);`.

### 60. strncmp with len == 0 makes an empty search string match the first config

- **id**: `config-getbyname-empty-string` | **место**: `addons/sourcemod/scripting/entWatch/config.sp:246` -> `ConfigGetByShortName()`
- **ось/инвариант**: api-use | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** ConfigGetByName (config.sp:234-244) and ConfigGetByShortName (config.sp:246-256) compute `int len = strlen(name);` and return the first entry for which `strncmp(Configs[i].<field>, name, len, false) == 0`. strncmp with num == 0 compares nothing and returns 0 (string.inc:90), so an empty search string matches config 0 instead of returning the -1 the callers check for. The lookups are also prefix-only by design, which is fine, but the zero-length case is a straight logic hole rather than a convenience.

**Триггер.** An admin with ADMFLAG_BAN runs `sm_espawn ""`. Command_Spawn (spawn.sp:6) sees args == 1 so it passes the length check, GetCmdArg(1, buffer, ...) yields an empty buffer, ConfigGetByShortName("") returns 0 instead of -1 (spawn.sp:17-20), and SpawnItem(0, client, client) spawns the first configured item of the map from its point_template.

**Доказательства.** config.sp:236 and config.sp:248 `int len = strlen(name);` followed by `strncmp(..., len, false) == 0`; string.inc:90 `native int strncmp(const char[] str1, const char[] str2, int num, bool caseSensitive=true);`; spawn.sp:14-20 (the only external caller, arg taken straight from GetCmdArg); config.sp:258-273 ConfigGetByNames chains both lookups and inherits the behaviour.

**Исправление.**

```
Guard the degenerate case once at the top of each lookup: `if(!name[0]) return -1;` in ConfigGetByName and ConfigGetByShortName.
```

> **Поправка верификатора.** Keep the finding, but move the trigger off `sm_espawn ""` (unverified engine tokenizer behaviour) onto the proven one: an admin with ADMFLAG_GENERIC running `sm_etransfer $ <player>` -> transfer.sp:24 ItemsGetByShortName("") -> items.sp:358 len == 0 -> returns item 0 -> TransferItem transfers the map's first item. The guard therefore belongs in FOUR places, not two: ConfigGetByName (config.sp:234), ConfigGetByShortName (config.sp:246), ItemsGetByName (items.sp:344) and ItemsGetByShortName (items.sp:356). Note also that config.sp:258-273 ConfigGetByNames has no caller anywhere in the plugin (it is `stock`), so fixing it there is dead-code work.

### 61. GFL slot derivation ORs two flags and cannot express SLOT_KNIFE with an absent key

- **id**: `config-gfl-slot-derivation` | **место**: `addons/sourcemod/scripting/entWatch/config.sp:149` -> `ConfigBrowseKeyGFL()`
- **ось/инвариант**: invariant-I5 | **уверенность**: hypothesis | **вердикт верификатора**: UNCERTAIN

**Проблема.** `c.Slot = (kv.GetNum("allowtransfer", 1) || kv.GetNum("forcedrop", 1)) ? SLOT_SECONDARY : SLOT_KNIFE;` folds two independent GFL flags into one slot with OR and defaults both to 1. Consequences: (a) `allowtransfer 0` is ignored whenever `forcedrop` is 1 or absent, so an item explicitly marked non-transferable becomes SLOT_SECONDARY and passes TransferIsValidItem (transfer.sp:52) and ItemDrop (items.sp:436) — the I5 protection depends entirely on both keys being present and both being 0; (b) the mapping is not round-trippable: the admin config editor writes `allowtransfer`/`forcedrop` only for SLOT_PRIMARY/SLOT_SECONDARY (admin_menu.sp:1066-1070) and starts from empty.cfg as a template, so a SLOT_KNIFE item saved through the editor comes back with both keys absent, which this line reads as SLOT_SECONDARY — a zombie knife item silently becomes droppable and transferable after one editor save.

**Триггер.** (a) Map whose GFL config has `"allowtransfer" "0"` without a `forcedrop` key (or with `"forcedrop" "1"`): ConfigBrowseKeyGFL -> Slot = SLOT_SECONDARY -> an admin runs sm_etransfer on the holder -> TransferIsValidItem passes at transfer.sp:52 -> the item is transferred against the config's stated intent. (b) Map with a GFL knife item (both keys 0) -> an admin runs sm_eadmin -> Configs -> edits any entry -> Save -> AdminConfigSave -> AdminConfigBrowseItems writes neither key for that config (admin_menu.sp:1066) -> next load of the map re-reads it as SLOT_SECONDARY. Path (b) additionally requires configs/entwatch/empty.cfg to exist, which it does not in this repository (admin_menu.sp:1013-1021 bails otherwise) — hence the hypothesis rating.

**Доказательства.** config.sp:149; keyvalues.inc:166 (GetNum defvalue used for both keys, here 1); items.sp:436 `if(Configs[...].Slot == SLOT_NONE || Configs[...].Slot == SLOT_KNIFE) return false;`; transfer.sp:52 (same test); admin_menu.sp:1066-1070 (writes allowtransfer/forcedrop only for PRIMARY/SECONDARY); admin_menu.sp:1013-1021 (empty.cfg template, absent from configs/entwatch/ in this repo); CLAUDE.md domain rule 5. I could not read a production GFL map config, so which key combinations actually occur is unverified.

**Исправление.**

```
Do not decide this from code alone — confirm against real production configs first. If SLOT_KNIFE is meant to mean 'never moved', derive it from the transfer flag alone (`c.Slot = kv.GetNum("allowtransfer", 1) ? SLOT_SECONDARY : SLOT_KNIFE;`) and make the editor's save path emit `allowtransfer 0`/`forcedrop 0` for SLOT_KNIFE/SLOT_NONE so the value round-trips. Both halves are needed; fixing only one leaves the other divergence in place.
```

> **Поправка верификатора.** Split it. Drop half (a) entirely -- it is a documented lossy mapping, not a bug, and 'the I5 protection depends on both keys being present and both being 0' is simply a restatement of the format. Keep half (b) as the finding, and re-file it against admin_menu.sp:1066-1070 (the writer that omits keys the reader defaults to 1), not against config.sp:149 (the reader, which is behaving as the GFL format specifies). Its trigger line: an admin runs sm_eadmin -> Configs -> edits any entry -> Save on a map with a GFL knife item -> AdminConfigBrowseItems writes no allowtransfer/forcedrop for that block -> next load of the map ConfigBrowseKeyGFL reads both as 1 -> SLOT_SECONDARY -> the knife can be dropped and transferred. Before touching it, confirm empty.cfg exists on the server; if it does not, the entire editor save path is already dead and the finding is moot.

### 62. entWatch_OnConfigLoaded is fired while Items[] still holds the previous map's items, whose Config indices now point into the new map's Configs[]

- **id**: `config-forward-fires-before-items-cleared` | **место**: `addons/sourcemod/scripting/entWatch/config.sp:53` -> `ConfigParse()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** ConfigParse fires the public forward at config.sp:53 (APIOnConfigLoaded -> api.sp:28-32 -> entWatch_OnConfigLoaded) at the end of parsing the NEW map's config, but Items[] and Items_Count are not touched until ItemsOnMapStart, which entWatch.sp calls on the next line (entWatch.sp:112-113). Items_Count is not reset at map end either -- ConfigOnMapEnd (config.sp:206-209) clears only Configs[], and ItemsClear runs solely from ItemsOnRoundStart/ItemsOnRoundEnd (items.sp:24, items.sp:36), neither of which is guaranteed to have run before a changelevel. So inside the forward, Items_Count still reports the previous map's items while each Items[i].Config indexes the freshly-parsed Configs[] of a different map. A consumer that calls entWatch_GetItemsCount() + entWatch_GetItem() there (api.sp:91-122) receives items pointing at unrelated configs, or at an index >= Configs_Count if the new map has fewer configs -- and entWatch_GetConfig (api.sp:96-108) does not bounds-check its `config` parameter at all, so the consumer gets a SourcePawn bounds error instead of a clean failure. This is the I6 'indices are not stable' hazard crossing the public API surface, where the plugin cannot see or fix the consumer.

**Триггер.** Any of the server's existing consumer plugins implements `public void entWatch_OnConfigLoaded()` and reads items from it. Map change: OnMapEnd -> ConfigOnMapEnd -> ConfigClearAll (Configs_Count = 0, Items[] untouched) -> OnMapStart -> ConfigOnMapStart (entWatch.sp:112) -> ConfigParse -> ConfigLoad -> ConfigBrowse populates the new Configs[] -> config.sp:53 APIOnConfigLoaded fires -> the consumer calls entWatch_GetItemsCount() (api.sp:93, returns the old map's Items_Count) and entWatch_GetItem(i, ...) (api.sp:110-122, returns a stale Item) -> ItemsOnMapStart (entWatch.sp:113) only clears Items[] after the forward has already returned.

**Доказательства.** config.sp:50-53 `if(!ConfigLoad(path)) return; APIOnConfigLoaded();`; entWatch.sp:110-113 `ConfigOnMapStart(); ItemsOnMapStart();` in that order; config.sp:206-209 ConfigOnMapEnd clears only Configs[]; items.sp:17-31 ItemsOnMapStart -> ItemsOnRoundStart -> ItemsClear is the only thing that resets Items_Count on a map change; api.sp:28-32, api.sp:91-94, api.sp:110-122; api.sp:96-108 Native_GetConfig indexes Configs[config] with no bounds check. CLAUDE.md 'Indices are not stable' and 'do not break existing native/forward signatures'.

**Исправление.**

```
Move the notification out of the parse step: have entWatch.sp call ItemsOnMapStart() before announcing, i.e. drop APIOnConfigLoaded() from ConfigParse (config.sp:53) and call it at the end of OnMapStart after ItemsOnMapStart(), so the forward observes a consistent (Configs[], Items[]) pair. This changes only when the forward fires, not its signature, so no consumer needs recompiling. Do not instead add bounds checks to api.sp -- that would hide the ordering problem rather than fix it. I did not read the consumer plugins (they are not in this repository), so whether any of them actually reads items from this forward is unverified; the ordering window itself is proven from entWatch.sp:110-113.
```

### 63. Callback dereferences `results` after checking only `error[0]`, contrary to the include's contract

- **id**: `selectsumm-null-results` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:196` -> `SQL_Callback_SelectSummBans()`
- **ось/инвариант**: database | **уверенность**: likely | **вердикт верификатора**: UNCERTAIN

**Проблема.** `if(error[0]) { ... return; }` then `results.FetchRow()` (restrict.sp:185-196). The SQLQueryCallback contract states the result object is null on failure and that the error string may be empty even when an error condition exists, so the handle — not the string — is the authoritative check. A null `results` here is a native error on the method call, which aborts the callback (harmless in this one because it holds no gate, unlike the ban callbacks). The same pattern is in client.sp:57-68 and is the standard shape in this codebase.

**Триггер.** Any condition where SourceMod delivers a null result set with an empty error string (documented as possible; I could not construct a concrete backend condition that produces it, hence 'likely' rather than 'proven'). Path: client.sp:73 RestrictLoadClientSummBans -> restrict.sp:180 DB_Query(SQL_Callback_SelectSummBans, userid) -> :196 results.FetchRow() on null.

**Доказательства.** restrict.sp:185-196; C:/develop/sm-1.13/include/dbi.inc:330-340 SQLQueryCallback: "@param results Result object, or null on failure. @param error … The error could be empty even if an error condition exists, so it is important to check the actual results value instead."

**Исправление.**

```
`if(error[0] || results == null) { LogError(...); return; }` in SQL_Callback_SelectSummBans (and the same one-token change in client.sp:57).
```

### 64. Cached restrict admin taken from Restricts[admin].Admin instead of Clients[admin].Account

- **id**: `addban-admin-account-wrong-source` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:481` -> `RestrictAddBan()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The DataPack cell that ends up in `Restricts[client].Admin` is written as `pack.WriteCell(Restricts[admin].Admin);` (restrict.sp:481) — i.e. the account of whoever restricted *the admin*, normally 0 — while the row actually stored in the DB uses `Clients[admin].Account` for `aid` (:486). The sibling function does it correctly (`pack.WriteCell(Clients[admin].Account);`, restrict.sp:280). The cached value drives the ownership check in RestrictClientUnBan (:354 `Restricts[client].Admin != Clients[admin].Account`) and the menu's enable/disable of the Unban item (admin_menu.sp:318), so after an sm_addeban of an online player neither the issuing admin nor any other generic admin can lift it in game (only RCON/ROOT), and the menu displays "Admin SteamID: [U:1:0]" (admin_menu.sp:319). It also disagrees with what the DB says, so a later reconnect (RestrictCacheClientBan:168, FetchInt(3) = aid) yields a different value than the live session had.

**Триггер.** An in-game rcon admin runs `sm_addeban 60 STEAM_1:0:12345` for a player who is currently connected. RestrictAddBan:481 writes Restricts[admin].Admin (0) -> SQL_Callback_AddBan:506 adminId = 0 -> :528 Restricts[client].Admin = 0. That same admin then opens sm_eadmin -> Banned players -> the target: admin_menu.sp:318 evaluates `Restricts[target].Admin (0) == Clients[client].Account (non-zero)` false -> the Unban item is ITEMDRAW_DISABLED; sm_uneban is refused at restrict.sp:354-357 with "Query denied".

**Доказательства.** restrict.sp:481 `pack.WriteCell(Restricts[admin].Admin);` vs restrict.sp:280 `pack.WriteCell(Clients[admin].Account);` in the equivalent position of RestrictClientBan; consumed at restrict.sp:506 and :528; read back by restrict.sp:354 and admin_menu.sp:318-319; DB counterpart written at restrict.sp:486 as `Clients[admin].Account`.

**Исправление.**

```
`pack.WriteCell(Clients[admin].Account);` at restrict.sp:481.
```

> **Поправка верификатора.** The stated consequence is partly wrong. (a) "neither the issuing admin nor any other generic admin can lift it in game" — false for the issuing admin: sm_addeban is ADMFLAG_RCON (restrict.sp:35), and RestrictClientUnBan's ownership check at restrict.sp:354 exempts `GetUserFlagBits(admin) & (ADMFLAG_RCON | ADMFLAG_ROOT)`, so whoever could issue the sm_addeban can always lift it with sm_uneban. What actually breaks: other ADMFLAG_GENERIC admins are refused at restrict.sp:354-357 with "Query denied". (b) The menu half is worse than described and worth keeping: admin_menu.sp:318 exempts only ADMFLAG_ROOT, not ADMFLAG_RCON, so even the issuing rcon-but-not-root admin sees the Unban item as ITEMDRAW_DISABLED in sm_eadmin -> Banned players — the menu and the command disagree about who may unban, independently of this bug. (c) The cosmetic half is confirmed verbatim: admin_menu.sp:319 `FormatEx(buffer, sizeof(buffer), "Admin SteamID: [U:1:%i]", Restricts[target].Admin);` renders "[U:1:0]". The one-line fix at restrict.sp:481 is correct.

### 65. On the SQLite path every connected client is authorized twice on plugin reload

- **id**: `db-duplicate-clientauth` | **место**: `addons/sourcemod/scripting/entWatch/database.sp:107` -> `SQL_Callback_CreateTables()`
- **ось/инвариант**: reliability | **уверенность**: proven | **вердикт верификатора**: UNVERIFIED

**Проблема.** SQL_Callback_CreateTables re-authorizes every in-game client unconditionally (database.sp:107-113), with no check for an auth already in flight or already completed. On the SQLite path DB is assigned synchronously (database.sp:24) *before* OnPluginStart's late-load loop runs (entWatch.sp:95-101 comes after DatabaseConnect at :71), so ClientAuth has already been issued for everyone via OnClientPutInServer -> client.sp:38; the CreateTables callback then issues a second SELECT_BANS for each of them. Each duplicate runs the whole chain again: RestrictCacheClientBan, RestrictLoadClientSummBans (a second SUMM query), and RestrictSendInfoToAdmins — so every admin receives two "X successfully authorized in the database" lines per player. With 60 players that is 4 extra queries and 60 duplicate chat lines per reload. The MySQL path avoids it only by accident (DB is still null during the late-load loop). A narrow race exists there too: a client joining between ConnectCallBack and SQL_Callback_CreateTables is authorized twice.

**Триггер.** No databases.cfg `entwatch` block (SQLite default) and a populated server: admin runs `sm plugins reload entWatch`. OnPluginStart:71 DatabaseConnect -> database.sp:24 DB assigned synchronously -> :25 ConnectCallBack queues CREATE TABLE -> entWatch.sp:95-101 calls OnClientPutInServer(i) for all -> client.sp:38 ClientAuth -> SELECT_BANS queued for each; then SQL_Callback_CreateTables:107-113 calls ClientAuth again for each.

**Доказательства.** database.sp:107-113; database.sp:24 `DB = SQLite_UseDatabase("entwatch", buffer, 256);` (synchronous — dbi.inc:503-514); entWatch.sp:71 DatabaseConnect before entWatch.sp:95-101 late-load loop; client.sp:38 ClientAuth from OnClientPutInServer; duplicate side effects at restrict.sp:202 RestrictSendInfoToAdmins.

**Исправление.**

```
Skip clients already authorized or already in flight — the cheapest correct guard reuses the existing state:
```
if(IsClientInGame(i) && !IsFakeClient(i) && !Clients[i].Authorized)
    ClientAuth(i);
```
(an in-flight duplicate remains theoretically possible in the MySQL window; add a per-client `AuthPending` flag if that matters).
```

### 66. GetCmdArg passes a hardcoded 32 for a 64-byte buffer

- **id**: `status-getcmdarg-hardcoded-size` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:45` -> `Command_Status()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** `char buffer[64];` at restrict.sp:42 but `GetCmdArg(1, buffer, 32);` at :45 — a literal instead of sizeof(buffer), inconsistent with every other command handler in the file (:94, :117, :140, :159 all use sizeof). Targets longer than 31 characters are silently truncated before FindTarget sees them. Practically benign because SM's target resolution does substring matching, so the truncated prefix still resolves — reported as a wrong-argument defect, not as a hazard.

**Триггер.** A player runs `sm_status <a target string longer than 31 chars>` (e.g. pasting a full Steam name). restrict.sp:45 truncates it, restrict.sp:46 FindTarget matches on the prefix instead of the typed string.

**Доказательства.** restrict.sp:42 `char buffer[64];`, restrict.sp:45 `GetCmdArg(1, buffer, 32);`, restrict.sp:55 `Format(buffer, 64, " (%N)", target);`. Native: C:/develop/sm-1.13/include/console.inc — GetCmdArg(argnum, buffer, maxlength); core impl smn_console.cpp:852-868 truncates to params[3].

**Исправление.**

```
`GetCmdArg(1, buffer, sizeof(buffer));` (and use sizeof(buffer) at :55 too, for consistency with the rest of the file).
```

### 67. Declaration `char ip[16]` is missing its terminating semicolon

- **id**: `deleteban-missing-semicolon` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:625` -> `SQL_Callback_DeleteBanClient()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** restrict.sp:625 reads `char ip[16]` with no semicolon, between two correctly terminated declarations. It compiles today only because `#pragma semicolon 1` is not set (CLAUDE.md, Code style) and the newline terminates the complete statement. CLAUDE.md's stated direction is a gradual restyle towards ~/.claude/rules/sourcepawn.md, which mandates `#pragma semicolon 1` — the day that pragma is added, this line becomes a compile error. Reporting it because it is a latent build breaker on a planned change, not as formatting.

**Триггер.** Anyone adding `#pragma semicolon 1` to entWatch.sp as part of the planned restyle: spcomp then fails on restrict.sp:625 with a missing-semicolon error.

**Доказательства.** restrict.sp:624-626:
```
    char steamid[40];
    char ip[16]
    char name[64];
```

**Исправление.**

```
`char ip[16];`
```

> **Поправка верификатора.** Framing correction. This is NOT the in-scope exception the audit brief carves out ("missing semicolon changing parse") — the parse is identical with or without it, there is no runtime effect, and no expression is silently absorbed into the next line. It is a latent build breaker for one specific planned change (adding `#pragma semicolon 1` as part of the restyle listed under CLAUDE.md "Direction / planned work"), which makes it a housekeeping item rather than a bug. Report it, fix it when the file is touched for another reason, but it should not consume one of the five slots in a change batch on its own.

### 68. sm_uneban deletes IP-matched rows belonging to OTHER online players but clears only the target's cache

- **id**: `uneban-ip-scope-cache-desync` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:379` -> `RestrictClientUnBan / SQL_Callback_UnBan()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** DELETE_BAN (restrict.sp:3) is scoped `WHERE (expires = -1 OR expires > %i) AND (pid = %i OR pip = '%s')` — the same OR-scope as SELECT_BANS (client.sp:1) — so unbanning player A removes every active row whose pip equals A's IP, including a row that belongs to a different account B who happens to share that IP. That deletion is defensible (the plugin matches restricts by IP on purpose, so B's row genuinely was restricting A). What is not defensible is the cache half: SQL_Callback_UnBan clears only `Restricts[client]` (restrict.sp:405-410). B's in-memory Restricts[B].Expires is untouched, so B stays blocked by RestrictClientHasRestrict (restrict.sp:664-667) for the rest of his session even though he no longer has a ban in the database. The desync survives until B disconnects (RestrictOnClientDisconnect -> Restricts[].Clear(), restrict.sp:223-226) or the map changes.

**Триггер.** Players A and B connect from the same public IP (NAT — two people in one household, routine on a ZE server). B is ebanned: restrict.sp:284 writes his row with pip = the shared IP. A joins; client.sp:52 SELECT_BANS matches B's row via `pip = '%s'` and RestrictCacheClientBan (restrict.sp:166-171) caches it onto A. An admin runs `sm_uneban A`: restrict.sp:379 DB_Query(DELETE_BAN, GetTime(), A's account, shared IP) deletes B's row; SQL_Callback_UnBan:405-410 clears Restricts[A] only; B keeps failing sdkhook.sp:12 `if(RestrictClientHasRestrict(client)) return Plugin_Handled;` on every item pickup for the rest of his session, with no ban left in the DB to explain it and no way for an admin to clear it (RestrictClientUnBan bails at restrict.sp:349-352 with "Player is not banned" because RestrictClientHasRestrict is checked before the query).

**Доказательства.** restrict.sp:3 `#define DELETE_BAN "DELETE FROM \`ebans\` WHERE (\`expires\` = -1 OR \`expires\` > %i) AND (\`pid\` = %i OR \`pip\` = '%s')"`; restrict.sp:379 `DB_Query(SQL_Callback_UnBan, pack, DBPrio_Normal, DELETE_BAN, GetTime(), Clients[client].Account, ip);`; restrict.sp:405-410 clears only Restricts[client]; client.sp:1 SELECT_BANS uses the same `pid = %i OR pip = '%s'` scope; sdkhook.sp:12 is the gate; restrict.sp:349-352 makes the state unrecoverable in game. Deadlock of the recovery path is what raises this above cosmetic.

**Исправление.**

```
After a successful DELETE, re-resolve which online players the deletion actually freed instead of assuming it was only the target — e.g. in SQL_Callback_UnBan iterate 1..MaxClients and clear Restricts[i] for every in-game client whose cached restrict came from the deleted scope (same account or same IP as the target). Cheapest correct version: capture the target's IP in the DataPack (it is already computed at restrict.sp:368) and clear any client whose GetClientIP matches it. Alternatively narrow DELETE_BAN to `pid = %i` only and accept that IP-only rows need sm_deleban — but that changes documented behaviour, so it needs a decision, not a patch.
```

### 69. A truncated "STEAM_" argument yields account id -48, which passes the validity check and is written to the DB

- **id**: `accountid-short-steamid-negative` | **место**: `addons/sourcemod/scripting/entWatch/helpers.sp:6` -> `UTIL_GetAccountIDFromSteamID (consumed by RestrictAddBan / RestrictDeleteBan)()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** `return StringToInt(steamid[10]) << 1 | (steamid[8] - 48);` reads offsets 8 and 10 after checking only that the first six characters are "STEAM_" (helpers.sp:4). For any input shorter than 9 characters the read lands past the terminator — still inside the caller's 64-byte buffer, so there is no bounds error, just a zero byte — and the expression evaluates to `(0 << 1) | (0 - 48)` = -48. The callers treat any non-zero return as a valid account: restrict.sp:430 `if(!id && !ipIsValid)` and restrict.sp:551 likewise. Because ipIsValid is a constant false (see addban-ip-never-valid), `!id` is the only gate, so -48 sails through and is written as `pid` at restrict.sp:486 into a column declared INTEGER UNSIGNED (database.sp:70) — a strict-mode MySQL error 1264, or a junk row on SQLite that no player will ever match. The admin gets "Query failed" or a bogus "Add ban success", never "Invalid SteamID".

**Триггер.** An ADMFLAG_RCON admin mistypes or pastes a truncated id: `sm_addeban 60 STEAM_1`. Command_AddBan:138-144 -> `char buffer[64]` (zero-filled by SourcePawn autozero; arg1 "60" wrote only indices 0-2, arg2 overwrote them with "STEAM_1\0", so indices 8 and 10 are still 0) -> RestrictAddBan(60, "STEAM_1", "", admin) -> helpers.sp:4 strncmp passes -> helpers.sp:6 `StringToInt(steamid[10])` = 0, `steamid[8] - 48` = -48 -> id = -48 -> restrict.sp:430 `!id` is false, so the "Invalid SteamID and IP-adress" guard at :432 is skipped -> restrict.sp:457 SELECT with `pid = -48` finds nothing -> restrict.sp:486 INSERT with pid = -48. Same path through RestrictDeleteBan:549-551 for `sm_deleban STEAM_1`, which then DELETEs on `pid = -48` and reports "Player is not banned" for a perfectly valid ban the admin was trying to lift.

**Доказательства.** helpers.sp:2-7 `if (!strncmp(steamid, "STEAM_", 6)) { return StringToInt(steamid[10]) << 1 | (steamid[8] - 48); }` — no length check, unlike the `[U:1:` branch at helpers.sp:9 which does verify the closing bracket. Callers: restrict.sp:428-434 and restrict.sp:549-555. Column type: database.sp:65 `\`pid\` INTEGER NOT NULL` (signed, so SQLite stores the junk silently) against database.sp:81 `\`pid\` int NOT NULL`. Local-array zero-init verified in the compiler, not assumed: C:/develop/sm1.13-botox/source/sourcemod/sourcepawn/compiler/code-generator.cpp:354-386, a declaration with no initialiser emits OP_INITARRAY_ALT with the full fill count when `decl->autozero()` is set, which is the case for new-syntax declarations.

**Исправление.**

```
Length-check the STEAM_ branch before indexing: `if (!strncmp(steamid, "STEAM_", 6)) { if (strlen(steamid) < 11) return 0; return StringToInt(steamid[10]) << 1 | (steamid[8] - 48); }`. This is a real out-of-string read producing a value the callers then trust, not a defensive check on an unreachable path — the trigger above is a plain typo on an RCON command.
```

### 70. The duration fragment of the broadcast eban announcement is translated for whoever the global target happened to be, not per recipient

- **id**: `bansuccess-translation-target-leak` | **место**: `addons/sourcemod/scripting/entWatch/restrict.sp:323` -> `SQL_Callback_BanClient()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** RestrictFormatDuration with translate = true resolves `%t` ("Minutes" / "Permanently") through the CURRENT global translation target (restrict.sp:679-695, FormatEx "%t"). SQL_Callback_BanClient calls it at restrict.sp:323 without setting that target first, then passes the already-rendered string into PrintToChatAll2 at restrict.sp:324, which sets SetGlobalTransTarget(i) per recipient (chat.sp:119-127) — too late, the substring is frozen. Every player therefore sees the surrounding sentence in his own language and the duration fragment in whatever language the last unrelated SetGlobalTransTarget left behind (chat.sp:102 in PrintToChat2, chat.sp:92 in PrintToTeam, or LANG_SERVER). The same pattern repeats at restrict.sp:512 and :535 in SQL_Callback_AddBan.

**Триггер.** A Russian-speaking player runs any command that reaches PrintToChat2 (chat.sp:102 SetGlobalTransTarget(client)); an admin then runs `sm_eban Vasya 60`. SQL_Callback_BanClient:323 RestrictFormatDuration(buffer, 256, 60, true) renders "60 минут" against that stale target; restrict.sp:324 PrintToChatAll2 then re-targets per client, so an English-speaking player receives "hEl gave a restriction Vasya (60 минут)". Reverse the languages and it is the other way round. The correct shape exists three hundred lines up in the same file: Command_Status calls SetGlobalTransTarget(client) at restrict.sp:67 before RestrictFormatDuration at :69.

**Доказательства.** restrict.sp:679-695 RestrictFormatDuration uses `FormatEx(buffer, size, "%t", "Minutes", duration)` / `"%t", "Permanently"`; restrict.sp:323-324 formats then broadcasts; chat.sp:115-128 PrintToChatAll2 sets the target per iteration, after the argument was already formatted; contrast restrict.sp:67-69. Phrase definitions confirming both fragments are translated: translations/entWatch.phrases.txt:113-118 ("Ban success", `"#format" "{1:s},{2:s},{3:s}"` — the duration arrives as an already-rendered %s) and :177-179 ("Minutes", `"#format" "{1:i}"`).

**Исправление.**

```
Do not pre-render a translated fragment that is then broadcast. Either pass the raw minute count into the phrase and let each recipient's %t resolve it (requires changing "Ban success" to take {3:i} plus a separate permanent phrase), or, minimally and without touching translations, build and send the message per client inside the loop rather than formatting once outside it. Note this is user-visible text only — no state is wrong — so it belongs in a cleanup batch, not alongside the eban-correctness fixes.
```

### 71. entWatch_GetConfig/GetItem never validate the index passed by the calling plugin

- **id**: `native-getconfig-getitem-no-index-validation` | **место**: `addons/sourcemod/scripting/entWatch/api.sp:98` -> `Native_GetConfig / Native_GetItem()`
- **ось/инвариант**: api-use | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** Both natives take the index straight from GetNativeCell(1) (api.sp:98, api.sp:111) and index Configs[]/Items[] with it (api.sp:107, api.sp:121). They validate only the struct size, not the index. Two distinct failures: (1) index in [Configs_Count, MAX_CONFIGS) or [Items_Count, MAX_ITEMS) passes the compiler's bounds check and is copied out with a `true` return, so the caller silently receives a dead slot - after ItemRemove() shifts the array down (items.sp:606-613) the slot at Items[Items_Count] holds whatever was one past the old tail (typically Config == -1), and a consumer that then does Configs[item.Config] indexes Configs[-1]. There is no way for a consumer to tell success from garbage. (2) index < 0 or >= MAX raises SP_ERROR_ARRAY_BOUNDS inside entWatch's own native - the compiler emits OP_BOUNDS for variable-index array access and the VM compares unsigned, so negatives are caught (code-generator.cpp:1094-1097, incl. the comment 'vm uses unsigned compare, this protects against negative indices'). That is not memory corruption, but it surfaces to the server owner as an entWatch error rather than the clean, self-describing native error the API contract in CLAUDE.md ('an out-of-range index from a third-party plugin must throw a native error') calls for.

**Триггер.** A consumer plugin caches an item index from entWatch_OnClientItemUse/Drop/Pickup (api.sp:47-69) and calls entWatch_GetItem(cachedIdx, item) one frame later, after ItemsOnEntityDestroyed -> ItemRemove (items.sp:304-342, 606-613) shifted the array down: cachedIdx is now >= Items_Count, the bounds check passes, SetNativeArray copies the dead slot, the native returns true, and the consumer reads Item.Config == -1. Equivalent path with Configs: any consumer that iterates to MAX_CONFIGS instead of entWatch_GetConfigsCount().

**Доказательства.** api.sp:96-108 Native_GetConfig (no check on `config`), api.sp:110-122 Native_GetItem (no check on `item`); api.sp:107/121 SetNativeArray(2, Configs[config]/Items[item], size); functions.inc:600-608 SetNativeArray copies `size` cells unconditionally; items.sp:606-613 ItemRemove shifts and decrements without clearing the vacated tail; items.sp:624 ItemClear sets Config = -1; code-generator.cpp:1094-1097 OP_BOUNDS with unsigned compare.

**Исправление.**

```
public any Native_GetConfig(Handle plugin, int numParams)
{
    int config = GetNativeCell(1);
    int size = GetNativeCell(3);

    if (config < 0 || config >= Configs_Count)
        return ThrowNativeError(SP_ERROR_NATIVE, "Invalid config index %i (count %i)", config, Configs_Count);

    if (size != sizeof(Config))
        return ThrowNativeError(SP_ERROR_NATIVE, "Config does not match latest (got %i expected %i)...", size, sizeof(Config));

    return (SetNativeArray(2, Configs[config], size) == SP_ERROR_NONE);
}

Same shape for Native_GetItem against Items_Count.
```

> **Поправка верификатора.** Three corrections. (1) The CLAUDE.md quote is fabricated — CLAUDE.md contains no sentence 'an out-of-range index from a third-party plugin must throw a native error'; the only relevant statement is 'do not break existing native/forward signatures' and 'Indices are not stable'. Do not cite a rule that does not exist. (2) The claim that the vacated slot 'typically' holds Config == -1 is wrong. ItemsOnEntityDestroyed calls ItemClear(i) (Config = -1) and THEN ItemRemove(i), whose loop `for(int i = item; i < Items_Count; i++) Items[i] = Items[i+1]` (items.sp:608-611) immediately overwrites that -1 with Items[i+1]. What ends up at index Items_Count after the removal is a copy of the OLD Items[Items_Count]; for a slot never used that is the zero-initialised struct, i.e. Config == 0 — a VALID config index, which is worse than -1 because the consumer gets plausible-looking garbage instead of an obvious sentinel. (3) Severity: minor, not major. There is no in-plugin trigger — every path requires a third-party plugin to pass an index it should not have kept, and the worst outcome is a wrong answer or an SP_ERROR_ARRAY_BOUNDS attributed to entWatch. Note also, since the finder leans on it: that same ItemRemove loop reads Items[Items_Count] and so reads Items[MAX_ITEMS] out of bounds when Items_Count == MAX_ITEMS (items.sp:610); helpers.sp:28-31 RemoveConfig has the identical off-by-one. Those are items.sp/helpers.sp findings, not api.sp ones, but they are the real 'wrong code' in this area.

### 72. entWatch_ClientHasItem(0) returns true whenever any item on the map is unowned

- **id**: `native-clienthasitem-client-zero` | **место**: `addons/sourcemod/scripting/entWatch/api.sp:126` -> `Native_ClientHasItem()`
- **ось/инвариант**: api-use | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** api.sp:126 takes the client index from GetNativeCell(1) with no validation and hands it to ItemFindClientItem (items.sp:423-432), which returns the first i with Items[i].Owner == client. Because 0 is entWatch's 'no owner' sentinel (items.sp:630 ItemClear, sdkhook.sp:46 OnWeaponDrop, items.sp:441 ItemDrop), client == 0 matches every unowned item and the native reports `true`. There is also no IsClientInGame check, so a stale index from a caller answers about a slot that may now hold a different player.

**Триггер.** A third-party plugin registers a command with RegConsoleCmd/RegAdminCmd and calls entWatch_ClientHasItem(client) in the handler; the server console or an RCON caller executes it, so client == 0 (the standard console-client convention). api.sp:126 GetNativeCell(1) -> 0 -> items.sp:425 loop -> first item with Owner == 0 (any item lying on the map at round start, since ItemsOnRoundStart re-scans and every freshly registered item has Owner 0) -> api.sp:129 returns 1. The console is reported as holding an item.

**Доказательства.** api.sp:124-131; items.sp:423-432 ItemFindClientItem compares Items[i].Owner == client; items.sp:630 ItemClear sets Owner = 0; sdkhook.sp:46 and items.sp:441 reset Owner to 0 on drop; entWatch.inc:45 declares the native as taking an int client with no documented precondition.

**Исправление.**

```
public int Native_ClientHasItem(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);

    if (client < 1 || client > MaxClients)
        return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %i", client);

    if (!IsClientInGame(client))
        return ThrowNativeError(SP_ERROR_NATIVE, "Client %i is not in game", client);

    return (ItemFindClientItem(client) != -1) ? 1 : 0;
}
```

> **Поправка верификатора.** Severity minor, not major. There is no path inside entWatch that reaches this — the only callers are third-party plugins, and the harm is entirely determined by what the consumer does with the wrong answer. The finder's out-of-range half is also worth stating more precisely: an index like -1 or 999 does NOT fault here, because `client` is only compared, never used as a subscript (items.sp:427) — it just returns false. So the real defect is exactly one case, client == 0, plus the absence of an IsClientInGame check for a stale index.

### 73. entWatch_IsClientLoaded indexes Clients[] with an unvalidated native cell

- **id**: `native-isclientloaded-no-validation` | **место**: `addons/sourcemod/scripting/entWatch/api.sp:83` -> `Native_IsClientLoaded()`
- **ось/инвариант**: api-use | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** api.sp:83 is a single expression, `return Clients[GetNativeCell(1)].Authorized;` - no range check, no IsClientInGame. Clients[] is MAXPLAYERS+1 (client.sp:17). An index outside [0, MAXPLAYERS] raises SP_ERROR_ARRAY_BOUNDS inside entWatch's native (OP_BOUNDS, unsigned compare, so negatives are caught too - code-generator.cpp:1094-1097), which SourceMod surfaces as an entWatch error and blames entWatch in the error log rather than the caller. Index 0 quietly answers about the never-populated console slot. Per the project's own API rules an out-of-range index from a third-party plugin must throw a described native error.

**Триггер.** A consumer plugin resolves a target with FindTarget(), which returns -1 on failure (a very common unchecked pattern), and calls entWatch_IsClientLoaded(-1). api.sp:83 -> Clients[-1] -> OP_BOUNDS unsigned compare -> SP_ERROR_ARRAY_BOUNDS raised in entWatch, native call aborts, entWatch is logged as the failing plugin.

**Доказательства.** api.sp:81-84; client.sp:17 `Client Clients[MAXPLAYERS + 1];`; code-generator.cpp:1094-1097 (bounds instruction, unsigned compare comment); entWatch.inc:38 `native bool entWatch_IsClientLoaded(int client);`.

**Исправление.**

```
public any Native_IsClientLoaded(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);

    if (client < 1 || client > MaxClients)
        return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %i", client);

    return Clients[client].Authorized;
}
```

> **Поправка верификатора.** Two corrections. (1) The citation 'code-generator.cpp:1094-1097' should be dropped or marked unverified — that file is not readable from this environment, so neither the finder nor I checked it; the claim about unsigned bounds compares is asserted from memory, which this project's standard forbids. (2) Severity minor, not major: identical reasoning to native-clienthasitem-client-zero — no in-plugin trigger, harm bounded by a buggy consumer. The FindTarget()-returns--1 trigger is plausible but hypothetical, since it names no actual consumer plugin on this server.

### 74. Connected clients are authorized twice - entWatch_OnClientLoaded fires twice per client

- **id**: `late-load-double-auth` | **место**: `addons/sourcemod/scripting/entWatch.sp:95` -> `OnPluginStart()`
- **ось/инвариант**: async | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** OnPluginStart calls DatabaseConnect() at entWatch.sp:71 and only afterwards, at entWatch.sp:95-101, replays OnClientPutInServer for already-connected clients, which calls ClientAuth (client.sp:38). On the SQLite branch DatabaseConnect assigns DB synchronously (database.sp:24) before returning, so ClientAuth's `if(DB == null) return` guard (client.sp:43) does not stop it and a SELECT_BANS is queued for every connected client. SQL_Callback_CreateTables then runs its own recovery loop (database.sp:107-113) and calls ClientAuth for the same clients a second time. Both callbacks reach client.sp:75-76, so Clients[].Authorized is set twice, RestrictLoadClientSummBans runs twice (two more queries, two RestrictSendInfoToAdmins broadcasts per player - restrict.sp:202/205-221) and APIOnClientLoaded fires entWatch_OnClientLoaded twice for the same client. Consumer plugins that treat that forward as a one-shot 'grant on load' hook double-apply.

**Триггер.** Admin runs `sm plugins reload entWatch` on a populated server configured for SQLite (no `entwatch` block in databases.cfg - the documented default). entWatch.sp:71 DatabaseConnect -> database.sp:22-26 SQLite branch sets DB and queues CREATE TABLE -> entWatch.sp:95-101 loop -> client.sp:38 ClientAuth -> client.sp:52 first SELECT_BANS queued -> database.sp:95 SQL_Callback_CreateTables -> database.sp:107-113 ClientAuth again -> second SELECT_BANS -> client.sp:76 APIOnClientLoaded called twice per client. The MySQL branch has a narrower version of the same window: any player who connects between ConnectCallBack assigning DB (database.sp:36) and SQL_Callback_CreateTables running is authorized twice.

**Доказательства.** entWatch.sp:71 DatabaseConnect() precedes entWatch.sp:95-101; database.sp:22-26 SQLite path assigns DB synchronously then calls ConnectCallBack inline; client.sp:41-53 ClientAuth guards only on DB == null; database.sp:107-113 second ClientAuth loop; client.sp:75-76 Authorized + APIOnClientLoaded with no idempotency check.

**Исправление.**

```
Make the authorization idempotent at its single owner rather than trying to order two independent triggers:

void ClientAuth(int client)
{
    if(DB == null || !DBLoaded || Clients[client].Authorized)
        return;
    ...
}

The `!DBLoaded` half also removes the SQLite race directly: before the schema exists no SELECT is issued, and database.sp:107-113 remains the single point that authorizes everyone once the table is ready.
```

> **Поправка верификатора.** The proposed fix's `!DBLoaded` half is right for the SQLite race but the `Clients[client].Authorized` half is not a sufficient guard on its own: the second ClientAuth is issued from database.sp:111 while the FIRST SELECT_BANS is still in flight, so Authorized is still false at that moment and the check would not catch it. Gating on `!DBLoaded` is what actually closes it, by making the pre-schema SELECT impossible; the Authorized check only helps against later re-entry. Also, if client-auth-no-retry is fixed first by adding a retry mechanism, recompute this one — the two interact and applying both blindly can produce either a permanent lockout or a new duplicate path.

### 75. Death/disconnect is announced for knife and no-slot items that ItemDrop refuses to release

- **id**: `clientlost-announces-undropped-items` | **место**: `addons/sourcemod/scripting/entWatch/client.sp:108` -> `ClientLostHandleAction()`
- **ось/инвариант**: invariant-I5 | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** client.sp:108-109 announces first and drops second, and discards ItemDrop's bool return. ItemDrop (items.sp:434-445) returns false without touching Items[].Owner when the config slot is SLOT_NONE or SLOT_KNIFE (items.sp:436-437) - invariant I5, knife items are never moved. So for exactly those items entWatch tells the whole team the player lost the item while its own state still records him as the owner: the HUD keeps listing him (hud.sp:121-125 skips only items with Owner == 0), and any later use path still measures against that owner.

**Триггер.** A zombie holding a SLOT_KNIFE item dies. entWatch.sp:160 ClientLostHandleAction(client, ACTION_DEATH) -> client.sp:106 ItemFindClientItem finds the knife item -> client.sp:108 PrintToChatItemAction(item, ACTION_DEATH) prints the loss to the team (chat.sp:31-37) -> client.sp:109 ItemDrop returns false at items.sp:436 -> Items[item].Owner still equals the dead player. Timer_Hud (hud.sp:119-125) keeps rendering the line until the weapon entity is destroyed and ItemsOnEntityDestroyed -> ItemRemove clears it. Same for a SLOT_NONE item on the ACTION_DISCONNECT path.

**Доказательства.** client.sp:102-111 (announce before drop, return value ignored); items.sp:434-445 ItemDrop early-returns false for SLOT_NONE/SLOT_KNIFE; config.sp:10/13 SLOT_NONE/SLOT_KNIFE; hud.sp:121 skips only Owner == 0; chat.sp:31-46 ACTION_DEATH/ACTION_DISCONNECT branches.

**Исправление.**

```
Decide which of the two statements is the truth and make the code say only that one. If the announcement is meant to mean 'ownership released', gate it on the drop:

void ClientLostHandleAction(int client, int action)
{
    int item = -1;

    while((item = ItemFindClientItem(client, item)) != -1)
    {
        if(!ItemDrop(item))
            continue;

        PrintToChatItemAction(item, action);
    }
}

If instead the announcement is meant to mean 'the holder is gone' regardless of slot (plausible for zombie knives, where the item genuinely disappears with the corpse), then the announcement is right and the ownership must be cleared alongside it. This changes player-visible chat behaviour on every map with knife items, so it needs the owner's call before it becomes a patch.
```

> **Поправка верификатора.** The finder picked the weaker of the two cases. The DEATH case is nearly harmless: the owner is still connected, so hud.sp:124 GetClientTeam(Items[i].Owner) is valid and the stale ownership expires as soon as the corpse's weapons are destroyed. The DISCONNECT case is the one worth writing up, because the stale Owner is then a FREED SLOT INDEX: (a) hud.sp:124 calls GetClientTeam on a client that is no longer in game, which clients.inc:477 documents as a native error ('@error Invalid client index, client not in game'), aborting Timer_Hud for every viewer that tick and repeating every second; and (b) if a new player connects into that slot index he satisfies `Items[item].Owner != activator` at sdkhook.sp:64 and can fire an item he never picked up — a direct I1 violation, obtained without any E-spam. IMPORTANT CAVEAT, and the reason I am not raising the severity: both consequences require the item's weapon entity to outlive the owner's removal, because otherwise OnEntityDestroyed (entWatch.sp:207) -> ItemsOnEntityDestroyed (items.sp:306-315) -> ItemRemove clears the slot first. Whether CS:S destroys or drops a disconnecting player's weapons, and in which order relative to player_disconnect, is engine behaviour I did NOT verify — the engine source is not on a readable path here. So the mismatch is proven from the code; the exploitable window is a hypothesis and must stay labelled as one.

### 76. GetClientAuthId return ignored - Clients[].SteamID can stay empty and is printed in chat

- **id**: `steamid-read-unchecked` | **место**: `addons/sourcemod/scripting/entWatch/client.sp:28` -> `OnClientPutInServer()`
- **ось/инвариант**: correctness | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** client.sp:28 calls GetClientAuthId(..., validate = true) and discards the bool result. clients.inc:338-341 documents it as returning 'True on success, false otherwise', where false is precisely the not-yet-backend-validated case. On failure the buffer keeps its previous contents, which OnClientDisconnect zeroed (client.sp:96 -> client.sp:12 SteamID[0] = 0), so Clients[client].SteamID stays an empty string for the whole session - and nothing ever retries, since this is the only place it is written. The field is not internal: it is printed to the whole team in every pick/drop/use/death message (chat.sp:70) and written into the admin audit log for transfers (transfer.sp:73, transfer.sp:79).

**Триггер.** A player joins while Steam backend validation is still pending (Steam outage, or a server running sv_lan 1). client.sp:21 IsFakeClient is false -> client.sp:28 GetClientAuthId returns false and leaves the buffer empty -> the player picks up an item -> sdkhook.sp:31 PrintToChatItemAction -> chat.sp:68-70 prints '<name> () picked up <item>' to the whole team; an admin transfer of his item logs `%N ()` with no SteamID in the LogAction audit trail (transfer.sp:73).

**Доказательства.** client.sp:28 (return discarded, and it is the only writer of SteamID); clients.inc:338-341 GetClientAuthId '@return True on success, false otherwise' with validate defaulting to true; client.sp:12 Client.Clear zeroes SteamID; client.sp:96 OnClientDisconnect calls Clear (also on every map change); chat.sp:70 and transfer.sp:73/79 consume the field.

**Исправление.**

```
Same structural answer as the account-id timing problem: read identity where it is guaranteed available. Move both identity reads into OnClientPostAdminCheck, or at minimum re-read on failure:

if(!GetClientAuthId(client, AuthId_Steam2, Clients[client].SteamID, sizeof(Clients[].SteamID), true))
    strcopy(Clients[client].SteamID, sizeof(Clients[].SteamID), "UNKNOWN");

The placeholder stops the empty parentheses in chat and makes the audit log say something, but it does not recover the real id - moving the read is the actual fix, and it should be done together with finding client-auth-no-retry since both are the same 'identity read too early, never retried' defect.
```

> **Поправка верификатора.** Two notes. The claim that failure 'keeps its previous contents' is correct in effect but I did not read the extension source to confirm SourceMod leaves the buffer untouched rather than writing an empty string; either way the observable result is the same empty field, so the finding does not depend on it. Second, this is the same root cause as trigger (b) of client-auth-no-retry — identity read at OnClientPutInServer with validate=true, never retried — and client.sp:47 GetSteamAccountID has the identical exposure. They should be treated as one defect with two symptoms and fixed together (move both reads to a point where validation is guaranteed), not as two independent patches; the strcopy 'UNKNOWN' placeholder the finder offers papers over the symptom without recovering the id and would put a fake token into the audit log.

### 77. Format-string injection: formatted buffer passed to PrintToConsole() as the format

- **id**: `chat-printtoconsole-format-injection` | **место**: `addons/sourcemod/scripting/entWatch/chat.sp:106` -> `PrintToChat2()`
- **ось/инвариант**: security | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** PrintToChat2() builds the final text into `buffer` with VFormat (chat.sp:103) and then, for client == 0, calls `PrintToConsole(client, buffer)` (chat.sp:106). PrintToConsole is variadic - its second parameter is a FORMAT string (console.inc:203-211). Any '%' specifier that survived into `buffer` - including one that came from a client-controlled player name expanded by %N - is re-interpreted as a conversion specifier with no argument behind it, and SourceMod's atcprintf raises SP_ERROR_PARAM via CHECK_ARGS (core/logic/sprintf.cpp:49-53, "String formatted incorrectly - parameter %d (total %d)"). The message is lost and a plugin error is logged. This is wrong code, not a missing guard: user data must never be a format string.

**Триггер.** A player sets his name to `Ev%sil` (or anything containing %s/%d/%i/%N). An operator on the server console (or over rcon) runs `sm_status <that player>`. sm_status is RegConsoleCmd (restrict.sp:29), and ConCmdManager dispatches server-console execution with client == 0 on a dedicated server (core/ConCmdManager.cpp:233-236 `realClient = ... client`, :261 `hook->pf->PushCell(realClient)`). Path: Command_Status(0, 1) -> restrict.sp:55 `Format(buffer, 64, " (%N)", target)` puts the crafted name into buffer -> restrict.sp:70/74/79 `PrintToChat2(0, "%t%s", ..., buffer)` -> chat.sp:100-103 VFormat produces "...(Ev%sil)" -> chat.sp:104-106 `PrintToConsole(0, buffer)` -> throw. Second, independent path: server console runs `sm_eban <player> <minutes>` -> RestrictClientBan stores admin index 0 in the DataPack (restrict.sp:274) -> SQL_Callback_BanClient -> `if(!console) PrintToChat2(console, "%t", "Ban success", names[0], names[1], buffer)` (restrict.sp:329-332), where names[] are GetClientName() results (restrict.sp:268-269).

**Доказательства.** chat.sp:98-112 (PrintToChat2, note :103 VFormat then :106 PrintToConsole(client, buffer)); C:/develop/sm-1.13/include/console.inc:203-211 (`native void PrintToConsole(int client, const char[] format, any ...)`); core/logic/sprintf.cpp:49-53 (CHECK_ARGS throws when a specifier has no argument); core/logic/smn_console.cpp:106-149 (client 0 is accepted and the string IS run through atcprintf); core/ConCmdManager.cpp:233-236,261 (server console dispatches with client 0); restrict.sp:29,44-56,62-79 (sm_status path); restrict.sp:268-274,329-332 (sm_eban path).

**Исправление.**

```
Never pass runtime text as a format:

    if(client == 0)
    {
        PrintToConsole(client, "%s", buffer);
    }

(The SayText2 branch at chat.sp:110 is unaffected - SendMessage passes `buffer` as a %s argument, chat.sp:139.)
```

> **Поправка верификатора.** Two corrections. (1) SEVERITY: minor, not major. The only reachable route is the server console / rcon (real clients go through the SendMessage branch at chat.sp:110, which passes the text as a %s argument at chat.sp:139 and is safe). Impact is one lost console line plus a logged error — no memory corruption, no gameplay effect, and %n does not exist in SourceMod's atcprintf. (2) The SECOND trigger path (`sm_eban` from the server console) is REFUTED: RestrictClientBan never reaches DB_Query with admin==0, because restrict.sp:277 `pack.WriteCell(GetClientUserId(admin))` throws first — core/logic/smn_players.cpp:710-717, GetGamePlayer(0) returns NULL and the native throws "Client index 0 is invalid". (restrict.sp:268 GetClientName(0,...) does NOT throw — smn_players.cpp:292-309 special-cases index 0 to the hostname — so the throw is specifically at :277.) Consequently SQL_Callback_BanClient is never invoked with console==0 and restrict.sp:329-332 is unreachable from the console. The same applies to sm_addeban (restrict.sp:479). The fix (`PrintToConsole(client, "%s", buffer)`) is correct.

### 78. {C} colour-code substitution runs after client-controlled names are interpolated

- **id**: `chat-colortag-injection-from-name` | **место**: `addons/sourcemod/scripting/entWatch/chat.sp:140` -> `SendMessage()`
- **ось/инвариант**: security | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** SendMessage() performs `ReplaceString(buffer, iSize, "{C}", "\x07")` (chat.sp:140) on a buffer that already contains the caller's fully expanded text - including %N-expanded player names (chat.sp:68-69). {C} is the plugin's own escape for the SayText2 hex-colour control byte (it is used nowhere else in the repo: the only occurrence of the literal is chat.sp:140). Because the substitution happens last, a player controls whether a \x07 control byte is emitted into every announcement about him. The CS:S client consumes the six characters after \x07 as an RRGGBB colour, so a name ending in `{C}` swallows the following six characters of the message (" (STEA"), corrupting the announcement for everyone on that team; a name of `{C}FF0000` simply recolours the rest of the line.

**Триггер.** Player renames himself to `{C}` or `{C}FF0000`, then picks up / drops / uses a special item, or dies or disconnects holding one. Path: OnWeaponPickup (sdkhook.sp:31) -> PrintToChatItemAction (chat.sp:68, %N expands the crafted name into the buffer) -> PrintToChat2 (chat.sp:103 VFormat) -> SendMessage (chat.sp:139 Format, chat.sp:140 ReplaceString substitutes the attacker's {C}) -> SayText2 to every teammate.

**Доказательства.** chat.sp:68-74 (%N with Items[item].Owner into the message), chat.sp:98-112 (PrintToChat2 -> VFormat -> SendMessage), chat.sp:131-141 (SendMessage: Format then ReplaceString on the same buffer). ReplaceString operates on the whole buffer with no notion of which part is user data: C:/develop/sm-1.13/include/string.inc:311-323. The colour tags themselves come from Colors[] / Configs[].Color (colors.sp:26-29, config.sp:131-133), which is why the plugin needs \x07 at all.

**Исправление.**

```
Do the {C} expansion on the caller's template before user data is merged in, e.g. in PrintToChat2/PrintToTeam/PrintToChatAll2 copy `message` into a local, ReplaceString {C} there, and VFormat from that copy; SendMessage then only prepends the tag. Alternatively strip '{'/'}' (or the literal "{C}") out of the %N result before it reaches the buffer.
```

> **Поправка верификатора.** Severity minor is right; the framing should note that the {C} escape is plausibly *intended* for map-config authors to embed colours in Configs[].Name (that is the only thing the substitution can usefully serve, since nothing else emits it), so the bug is that the expansion happens after user data is merged, not that the escape exists. Note also that the same injection reaches PrintToChatAll2 (chat.sp:124 -> 139-140), e.g. the eban announcements at restrict.sp:324/411 which interpolate GetClientName() results.

### 79. HUD timer existence and hud_enabled are decided once per map and never revisited

- **id**: `hud-timer-oneshot-decision` | **место**: `addons/sourcemod/scripting/entWatch/hud.sp:35` -> `HudCreateTimer()`
- **ось/инвариант**: reliability | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** HudCreateTimer() is called from exactly one place, HudOnMapStart() (hud.sp:21-24; the only other reference in the tree is the definition itself). It returns early when `Configs_Count == 0` (hud.sp:35) or `!hud_enabled` (hud.sp:38). Both inputs can change after that point, and nothing recreates the timer:
(a) admin_menu.sp:805-812 lets an admin create a brand-new Config at runtime (`Configs_Count++`). On a map that shipped without configs/entwatch/<map>.cfg, Configs_Count was 0 at map start, so no timer exists; after the admin adds configs the items register and work, but the HUD stays dead for the rest of the map.
(b) `hud_enabled` is a file-static (hud.sp:5) written only by HudConfigLoad (hud.sp:16-19), which config.sp:66-68 calls only after FileExists+ImportFromFile have both succeeded (config.sp:58-63). On a map with no config file the value is never refreshed and silently carries over from the previous map - so the module's own state is not reset per map, and in combination with (a) a previous map's `"hud" "0"` keeps the HUD off even after configs exist.

**Триггер.** Admin with ADMFLAG_GENERIC on a map that has no configs/entwatch/<map>.cfg: OnMapStart -> ConfigOnMapStart (Configs_Count stays 0, HudConfigLoad never runs) -> HudOnMapStart -> HudCreateTimer returns at hud.sp:35, TimerHud stays null. Admin then runs sm_eadmin -> Configs -> "Add" (admin_menu.sp:807-812) and fills in a hammerid; on the next round_start ItemsOnRoundStart binds the entities and items work, but Timer_Hud never runs.

**Доказательства.** hud.sp:21-24 and hud.sp:31-42 (only caller, both early returns); grep over addons/sourcemod/scripting shows HudCreateTimer referenced only at hud.sp:23 and hud.sp:31; admin_menu.sp:807-812 (`if(Configs_Count < MAX_CONFIGS) { ... Configs_Count++; }`); config.sp:56-68 (HudConfigLoad reached only past the FileExists/ImportFromFile guards); hud.sp:5,18 (static, never reset).

**Исправление.**

```
Reset the module state per map and re-evaluate when the config set changes: set `hud_enabled = true;` (the documented default of kv.GetNum("hud", 1)) at the top of HudOnMapStart before ConfigOnMapStart's value can apply, and call HudCreateTimer() from the admin editor's save/add path (next to admin_menu.sp:812) so a runtime config change re-arms the timer.
```

> **Поправка верификатора.** Sub-claim (b) has no INDEPENDENT trigger and should not be presented as a second bug: whenever a config file does load, HudConfigLoad runs and kv.GetNum("hud", 1) defaults to 1, so a previous map's `"hud" "0"` is always cleared; the stale value only survives when no config file loads, in which case Configs_Count == 0 blocks the timer anyway. Also, on the very first config-less map hud_enabled is false by zero-initialisation of the file static (hud.sp:5), not by carry-over. So the correct statement is: the two guards compound, and a fix must address both — otherwise re-calling HudCreateTimer() from the admin add path still returns at hud.sp:38. The finder's fix does cover both. Severity minor (admin-only, config-less map).

### 80. Owner not on T/CT: LogError every second and item dropped from every HUD page

- **id**: `hud-owner-not-t-or-ct-logspam` | **место**: `addons/sourcemod/scripting/entWatch/hud.sp:137` -> `Timer_Hud()`
- **ось/инвариант**: reliability | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** team is computed as `GetClientTeam(Items[i].Owner) - 1` (hud.sp:124), so CS:S TEAM_SPECTATOR(1) maps to 0 and TEAM_UNASSIGNED(0) maps to -1. Both fall into the `default:` arm (hud.sp:135-139), which calls LogError() and `continue`s. Two consequences: (1) the error is written on every timer tick, i.e. once per second per offending item, indefinitely - unbounded error-log growth from a condition the plugin cannot fix by logging; (2) the `continue` also skips the shared page-0 accumulation at hud.sp:142-145, so the item disappears from the spectator/all HUD as well, not just from the team pages. The message text is also wrong: it prints Items[i].Config ("owner item #%i") rather than the item index or the owner, so it does not even identify the offender.

**Триггер.** Admin with ADMFLAG_GENERIC runs `sm_etransfer <owner> <spectator>`: transfer.sp:15 resolves the receiver with FindTarget(client, buffer, true, false), which applies no team/alive filter, and transfer.sp:84 EquipPlayerWeapon(receiver, weapon) fires SDKHook_WeaponEquipPost -> OnWeaponPickup (sdkhook.sp:23-31) which sets Items[item].Owner = receiver. From the next Timer_Hud tick on, GetClientTeam(receiver) == 1 -> team == 0 -> default arm. Second path: an owner of a SLOT_KNIFE / SLOT_NONE item moves to Spectator - ClientLostHandleAction -> ItemDrop returns false at items.sp:436-437 without clearing Owner, leaving Owner pointing at a now-spectating client for as long as the weapon entity survives.

**Доказательства.** hud.sp:124 `team = GetClientTeam(Items[i].Owner) - 1;`; hud.sp:126-140 (switch with `case 1, 2` and a LogError+continue default); hud.sp:142-145 (page-0 accumulation skipped by that continue); transfer.sp:13-18,58-86 (receiver resolution with no team check, EquipPlayerWeapon); sdkhook.sp:23-34 (OnWeaponPickup sets Owner unconditionally); items.sp:434-445 (ItemDrop bails for SLOT_NONE/SLOT_KNIFE before clearing Owner).

**Исправление.**

```
Do not log per tick, and do not lose the item from page 0. Fold the classification into a plain guard, e.g.:

    int team = GetClientTeam(Items[i].Owner) - 1;
    ItemFormat(i, line, sizeof(line));
    if (team == 1 || team == 2)
    {
        ... // страница команды
    }
    // общая страница заполняется всегда

If a diagnostic is still wanted, rate-limit it or log the item index and the owner name once per state change, not once per tick.
```

> **Поправка верификатора.** Trigger correction: the finder's SECOND path (a SLOT_KNIFE/SLOT_NONE owner going to spectator) is REFUTED as a Timer_Hud trigger. ItemDrop does bail before clearing Owner (items.sp:436-437), but the moment the owner dies or leaves, the knife entity is removed and ItemsOnEntityDestroyed (items.sp:304-315) does ItemUnhook/ItemClear/ItemRemove on the whole item within the same frame; Timer_Hud only runs at 1 Hz, so it never observes that state. Only the sm_etransfer-to-spectator path survives. One link in that path I could NOT verify from source: that EquipPlayerWeapon (transfer.sp:84) actually succeeds on a spectating client and fires SDKHook_WeaponEquipPost — the rest of the chain is verified. Severity minor (admin misuse required, log growth only).

### 81. sm_hud executed from the server console throws in AreClientCookiesCached(0)

- **id**: `hud-sm_hud-from-server-console` | **место**: `addons/sourcemod/scripting/entWatch/hud.sp:94` -> `HudToggleClientHud()`
- **ось/инвариант**: api-use | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** sm_hud is registered with RegConsoleCmd (hud.sp:13) and Command_Hud passes its client parameter straight to HudToggleClientHud (hud.sp:100-104) with no client check. Executed from the server console the parameter is 0, and AreClientCookiesCached(0) throws "Client index %d is invalid" because the native rejects anything below 1 (clientprefs/natives.cpp:231-241). The callback aborts with a logged plugin error. `Hud[0]` is also flipped at hud.sp:92, which is dead state - the send loop starts at i = 1 (hud.sp:162).

**Триггер.** An operator types `sm_hud` in the server console (or issues it over rcon). ConCmdManager dispatches a RegConsoleCmd hook with realClient == client == 0 on a dedicated server (core/ConCmdManager.cpp:233-236, :261) -> Command_Hud(0, 0) -> HudToggleClientHud(0) -> hud.sp:93 PrintToChat2(0,...) succeeds (PrintToConsole accepts index 0, core/logic/smn_console.cpp:108-111,141-147) -> hud.sp:94 AreClientCookiesCached(0) -> ThrowNativeError.

**Доказательства.** hud.sp:13 `RegConsoleCmd("sm_hud", Command_Hud);`; hud.sp:90-104; C:/develop/sm1.13-botox/source/sourcemod/extensions/clientprefs/natives.cpp:231-241 (`if ((client < 1) || (client > GetMaxClients())) return pContext->ThrowNativeError("Client index %d is invalid", client);`); core/ConCmdManager.cpp:233-236,261.

**Исправление.**

```
Guard the command entry point:

    public Action Command_Hud(int client, int args)
    {
        if(!client)
            return Plugin_Handled;   // из консоли сервера настройка не имеет смысла

        HudToggleClientHud(client);
        return Plugin_Handled;
    }
```

> **Поправка верификатора.** Add the listen-server caveat for completeness: on a non-dedicated server ConCmdManager.cpp:232-234 rewrites client 0 to ListenClient(), so the throw is dedicated-server (and rcon) specific — which is the production configuration. Severity minor: one logged error per invocation, no state corruption (the toggle at hud.sp:92 has already been applied to the unused slot 0).

### 82. SourceTV does receive the HUD - CLAUDE.md's description of the bot path is wrong

- **id**: `hud-sourcetv-doc-divergence` | **место**: `addons/sourcemod/scripting/entWatch/hud.sp:59` -> `HudClientReadCookie()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: UNVERIFIED

**Проблема.** CLAUDE.md states: "HudClientReadCookie() intends to give SourceTV the HUD and deny it to other bots, but OnClientPutInServer() returns on IsFakeClient before the HUD is set up, so in practice no bot - SourceTV included - receives it." That is not what the code does. HudClientReadCookie has a second entry point: OnClientCookiesCached (client.sp:79-84) is NOT gated on IsFakeClient, and clientprefs fires that forward for fake clients. So for the SourceTV bot the function runs, sets Hud[client] = true at hud.sp:59, takes the IsFakeClient branch at hud.sp:61, finds IsClientSourceTV true and therefore does NOT clear the flag, and returns. Every other bot correctly ends up with Hud == false. Net effect: the implementation already matches the author's evident intent; the documentation is the thing that is wrong, and acting on it (e.g. "fixing" the bot path) would break working behaviour.

**Триггер.** Server with tv_enable 1. SourceTV connects -> PlayerManager authorizes fake clients and notifies every IClientListener (core/PlayerManager.cpp:717-726) -> CookieManager::OnClientAuthorized queues the SELECT with no fake-client check (extensions/clientprefs/cookie.cpp:147-165) -> SelectDataCallback runs the forward unconditionally even with zero rows (extensions/clientprefs/cookie.cpp:225-272) -> entWatch OnClientCookiesCached (client.sp:79-84) -> HudOnClientCookiesCached -> HudClientReadCookie(sourcetv) -> hud.sp:56 IsClientInGame passes, hud.sp:59 Hud = true, hud.sp:61-66 SourceTV keeps it -> Timer_Hud sends KeyHintText to the SourceTV slot every second (hud.sp:162-179).

**Доказательства.** hud.sp:44-52 (two entry points), hud.sp:54-67 (order: Hud=true, then the IsFakeClient/IsClientSourceTV branch); client.sp:19-22 (OnClientPutInServer returns on IsFakeClient - the branch CLAUDE.md describes) vs client.sp:79-84 (OnClientCookiesCached, no such guard); C:/develop/sm1.13-botox/source/sourcemod/core/PlayerManager.cpp:717-726; extensions/clientprefs/cookie.cpp:147-165 and :225-272; C:/develop/sm-1.13/include/clients.inc:422-429 (IsClientSourceTV).

**Исправление.**

```
No code change. Correct CLAUDE.md's HUD paragraph to: "HudClientReadCookie() gives SourceTV the HUD and denies it to other bots; OnClientPutInServer() returns early on IsFakeClient, but OnClientCookiesCached() has no such guard and clientprefs fires it for fake clients, so the SourceTV branch is live."
```

### 83. Page rotation period is 6 s not 5, and the rotation statics are never reset

- **id**: `hud-rotation-statics` | **место**: `addons/sourcemod/scripting/entWatch/hud.sp:151` -> `Timer_Hud()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** Three small defects in the rotation block: (1) `if(++ticksUpdatePages > TICKS_UPDATE_COUNT)` with TICKS_UPDATE_COUNT == 5 advances the page every SIXTH tick, i.e. every 6 s, not the 5 that the constant name and CLAUDE.md ("rotating every 5 ticks") state - a classic >= / > off-by-one. (2) currentPages[] and ticksUpdatePages are function statics (hud.sp:148-149) that are never reset on map start, while pagesCount[] is a local recomputed every tick (hud.sp:114). After the item count shrinks (round end, items dropped), currentPages[team] can point at a page that is now empty; hud.sp:172 then `continue`s and sends nothing at all, so the previous KeyHintText lingers on screen with stale item data until the next rotation - up to 6 s. Same when Timer_Hud early-returns on `!Items_Count` (hud.sp:111-112): the last HUD frame is never cleared. (3) hud.sp:156 `currentPages[i] = 0` has no terminating semicolon; harmless today because it is the last statement of its block and #pragma semicolon 1 is not set, but it becomes a real parse hazard the moment a line is added after it.

**Триггер.** Any round on any map with HUD items: at round_end ItemsOnRoundEnd -> ItemsClear sets Items_Count = 0 (items.sp:33-37), so the very next Timer_Hud tick returns at hud.sp:111 without sending anything, and the KeyHintText from the last tick of the round stays on the players' screens showing the pre-round-end item state. Same effect mid-round whenever the number of pages drops below currentPages[team].

**Доказательства.** hud.sp:107 `const int TICKS_UPDATE_COUNT = 5;` vs hud.sp:151 `if(++ticksUpdatePages > TICKS_UPDATE_COUNT)`; hud.sp:114 (pagesCount local) vs hud.sp:148-149 (currentPages/ticksUpdatePages static); hud.sp:111-112 and hud.sp:172 (both paths send nothing rather than clearing); hud.sp:156 (missing semicolon); items.sp:33-37 (ItemsOnRoundEnd -> ItemsClear).

**Исправление.**

```
Use `>=` (or rename the constant to TICKS_UPDATE_PERIOD and keep `>` deliberately), add the semicolon at hud.sp:156, reset currentPages[]/ticksUpdatePages in HudOnMapStart, and send an explicit empty KeyHintText once when a team's page set becomes empty so the stale HUD is cleared instead of lingering.
```

> **Поправка верификатора.** The impact is overstated and should be trimmed before this is acted on. (a) Sub-claim (1) has no functional consequence — it is a name/doc mismatch, and 'fixing' it to `>=` is a behaviour change to a mature plugin, so it belongs in the doc, not necessarily in the code. (b) 'the previous KeyHintText lingers on screen with stale item data' overstates it: KeyHintText is a fading hint element, which is precisely why the module re-sends it every second; the observable symptom is a HUD gap of up to 6 s (e.g. right after a map change when currentPages[] still holds the previous map's index), not indefinitely stale data. (c) Sub-claim (3) is currently harmless and is a hazard only for future edits. Net: one real, low-impact defect (statics not reset per map/round) plus two cosmetic observations.

### 84. sm_hud toggled before cookies are cached is neither saved nor kept — OnClientCookiesCached silently reverts it

- **id**: `hud-toggle-lost-before-cookies-cached` | **место**: `addons/sourcemod/scripting/entWatch/hud.sp:94` -> `HudToggleClientHud()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** HudToggleClientHud() flips Hud[client] (hud.sp:92) but persists it only inside `if(AreClientCookiesCached(client))` (hud.sp:94-97). There is no else-branch and no pending-write state. Independently, HudClientReadCookie() unconditionally re-seeds `Hud[client] = true` (hud.sp:59) and then overwrites it from the stored cookie (hud.sp:70-82) — and it has a second entry point, HudOnClientCookiesCached (hud.sp:49-52, wired at client.sp:79-84), which fires *after* the player is already in game and able to type commands. So a toggle made in the window between OnClientPutInServer and OnClientCookiesCached is (a) not written to the cookie and (b) discarded when the cookie callback lands. The player's explicit setting is silently reverted with no feedback, and the same loss repeats on the next map because OnClientDisconnect (client.sp:86-90) clears Hud[] and the new map re-reads the never-updated cookie.

**Триггер.** A player joins a server whose clientprefs backend is remote MySQL (or any server where the cookie SELECT has not landed by the time the map finishes loading) and types `sm_hud` in that window. Path: client.sp:19 OnClientPutInServer -> hud.sp:46 HudOnClientPutInServer -> hud.sp:54 HudClientReadCookie -> hud.sp:70 AreClientCookiesCached == false, Hud stays true; player runs sm_hud -> hud.sp:100 Command_Hud -> hud.sp:90 HudToggleClientHud -> Hud=false, hud.sp:94 false so SetClientCookie is skipped; clientprefs SELECT completes -> extensions/clientprefs/cookie.cpp:215-272 ClientConnectCallback fires cookieDataLoadedForward -> client.sp:79 OnClientCookiesCached -> hud.sp:51 HudOnClientCookiesCached -> hud.sp:59 Hud[client] = true -> hud.sp:76/80 set from the stored cookie. HUD is back on, cookie unchanged.

**Доказательства.** hud.sp:59 `Hud[client] = true;` (unconditional re-seed on both entry points, hud.sp:44-52); hud.sp:70-82 (cookie read overwrites whatever the player just chose); hud.sp:90-98 (toggle with a persist path guarded by AreClientCookiesCached and no fallback); client.sp:79-84 (OnClientCookiesCached delegate, no IsFakeClient/ordering guard); AreClientCookiesCached semantics: C:/develop/sm-1.13/include/clientprefs.inc:296-303 and C:/develop/sm1.13-botox/source/sourcemod/extensions/clientprefs/natives.cpp:231-243. Forward really does fire post-connect and asynchronously: extensions/clientprefs/cookie.cpp:147-165 (query queued at OnClientAuthorized) and :215-272 (forward executed from the threaded query callback).

**Исправление.**

```
Keep the in-memory choice authoritative once the player has expressed one: record a per-client `bool hud_user_set[MAXPLAYERS+1]` set in HudToggleClientHud and cleared in HudOnClientDisconnect; in HudClientReadCookie return early (or skip the cookie read) when it is set, and flush the pending value with SetClientCookie from HudOnClientCookiesCached. Note this and hud-timer-oneshot-decision both touch HudClientReadCookie/HudOnMapStart — apply one, then recompute.
```

### 85. \x07 emitted with an empty item colour — the CS:S client eats the first 6 characters of the item name

- **id**: `chat-empty-item-color-eats-name` | **место**: `addons/sourcemod/scripting/entWatch/chat.sp:68` -> `PrintToChatItemAction()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** chat.sp:68-74 builds the announcement as `"... \x07%s%s"` with Configs[].Color[1] followed by Configs[].Name. \x07 is the SayText2 hex-colour escape and the client consumes exactly the next six characters as RRGGBB. Configs[].Color[1] is empty whenever the map config block has no `color` key, because the fallback chain terminates in an empty string: configs/entwatch/colors.cfg (the shipped file) defines only tagcolor/nickcolor/othercolor, while ColorsInit reads `itemcolor` with no default (colors.sp:29), so Colors[COLOR_ITEM] == ""; ConfigClear then seeds Configs[].Color[1] from it (config.sp:300), ConfigBrowseKeyGFL passes it as the KeyValues default (config.sp:132) and ConfigBrowseKeyUNLOZE passes no default at all (config.sp:177). Result: \x07 is immediately followed by the item name and six characters of the name are swallowed as a colour code in every pick/drop/death/disconnect/use announcement for that item. The same expression is used at transfer.sp:71/77, spawn.sp:76 and assist_use.sp:95.

**Триггер.** Any player, on any map whose per-map config block omits `color` (or whose GFL config writes a bare colour name without braces, which ColorNameToColorCode leaves untouched — colors.sp:38-42 requires both '{' and '}'), on a server using the repository's configs/entwatch/colors.cfg. Path: player touches the item weapon -> sdkhook.sp:23 OnWeaponPickup -> chat.sp:12 PrintToChatItemAction -> chat.sp:68 with Configs[].Color[1] == "" -> chat.sp:110 SendMessage -> chat.sp:143-151 SayText2. Every teammate sees the item name with its first six characters missing.

**Доказательства.** chat.sp:68-74 (the `\x07%s%s` pair, Color[1] then Name); addons/sourcemod/configs/entwatch/colors.cfg (only tagcolor/nickcolor/othercolor — no itemcolor); colors.sp:26-29 `hKeyValues.GetString("itemcolor", Colors[COLOR_ITEM], 32);` with no default argument; config.sp:300 `strcopy(Configs[config].Color[1], sizeof(Configs[].Color), Colors[COLOR_ITEM]);`; config.sp:131-133 (GFL: default = Colors[COLOR_ITEM]) and config.sp:176-177 (UNLOZE: no default); colors.sp:36-55 ColorNameToColorCode returns unchanged when the value has no braces, and falls back to `"#%s", Colors[COLOR_ITEM]` (colors.sp:53) which is also empty. Contrast chat.sp:139, where \x07 is paired with Colors[COLOR_TAG]="FF8AAE" and renders correctly — which is what proves the six-character consumption is live.

**Исправление.**

```
Give the fallback a real value rather than armouring the call sites: add `"itemcolor" "<hex>"` to configs/entwatch/colors.cfg, and give colors.sp:29 an explicit default (`hKeyValues.GetString("itemcolor", Colors[COLOR_ITEM], 32, "FFFFFF");`) so Configs[].Color[1] can never be empty. Related but separate: config.sp:132/177/300 pass `sizeof(Configs[].Color)` (16) as the length for a write that starts at Color[1], which can write one byte past Color[] into Filter[0] (Config.inc:21-23) — worth flagging to whoever audits config.sp, not fixed here.
```

### 86. KeyValues handle leaked on every failed save (empty.cfg missing)

- **id**: `admincfg-kv-leak` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:1017` -> `AdminConfigSave()`
- **ось/инвариант**: handles | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** AdminConfigSave() creates `KeyValues kv = new KeyValues("entities")` at line 1015 and, if `kv.ImportFromFile()` fails, logs and `return`s at line 1017-1021 without `delete kv`. SourcePawn has no scope-based release, so one Handle leaks per invocation. This is the only early return in the function and it is exactly the path taken when the template file is absent — and `configs/entwatch/empty.cfg` is NOT shipped in this repository (only `configs/entwatch/colors.cfg` exists), so on any install that lacks it EVERY save leaks.

**Триггер.** An admin with ADMFLAG_RCON/ROOT types sm_eadmin -> Command_Admin -> AdminMenu (item "save", added at line 36 behind the RCON|ROOT gate) -> AdminMenu_Handler case 's' (line 82) -> AdminConfigSave(). On a server without addons/sourcemod/configs/entwatch/empty.cfg, ImportFromFile returns false, the function returns at line 1020 and the KeyValues Handle is never closed. Repeating the menu selection leaks one Handle per press for the lifetime of the plugin.

**Доказательства.** admin_menu.sp:1015 `KeyValues kv = new KeyValues("entities");`; admin_menu.sp:1017-1021 early return with no delete; admin_menu.sp:1029 the only `delete kv` is on the success path; C:/develop/sm-1.13/include/keyvalues.inc:57-58 "The Handle must be closed with CloseHandle() or delete"; keyvalues.inc:83-88 ImportFromFile returns false on failure. Repo check: only configs/entwatch/colors.cfg exists, no empty.cfg.

**Исправление.**

```
if(!kv.ImportFromFile(buffer))\n{\n    LogMessage("File %s not founded", buffer);\n    delete kv;\n    return;\n}
```

> **Поправка верификатора.** Severity is minor, not major: it is one Handle per admin key-press on an error-only path, not per-frame or per-player, and on a correctly installed server (empty.cfg present) the branch is never taken. The fix as written is correct.

### 87. Save rounds Cooldown to an int, so fractional cooldowns do not round-trip

- **id**: `admincfg-cooldown-int` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:1045` -> `AdminConfigBrowseItems()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The save path writes `kv.SetNum("cooldown", RoundToNearest(Configs[i].Cooldown))` while both parsers read it back with `kv.GetFloat("cooldown")` and the editor itself displays and accepts a float (ConfigMenu line 866 `%.1f`, AdminOnClientSayCommand case 10 `StringToFloat`). Any non-integral cooldown is destroyed by a save: 2.5 -> 3, 0.4 -> 0. Because ItemReload()/ItemIsReady() drive entWatch's readiness from Configs[].Cooldown (items.sp:510,518,527,465), a rounded-DOWN value makes entWatch's readiness run AHEAD of the map's — the exact failure direction invariant I4 forbids (press allowed, use announced and counted while the map is still on cooldown).

**Триггер.** Map config has `"cooldown" "2.5"`. An RCON/ROOT admin presses sm_eadmin -> Save (AdminMenu_Handler case 's'). AdminConfigBrowseItems writes cooldown=3 (or, for 0.4, cooldown=0). After the next map load ConfigBrowseKeyGFL/UNLOZE (config.sp:160/201) read the integer and every item of that config runs on a different cooldown than the map's own logic.

**Доказательства.** admin_menu.sp:1045 `kv.SetNum("cooldown", RoundToNearest(Configs[i].Cooldown));`; config.sp:160 and config.sp:201 `c.Cooldown = kv.GetFloat("cooldown");`; admin_menu.sp:866 the editor renders Cooldown as `%.1f`; admin_menu.sp:982 `Configs[cfg].Cooldown = StringToFloat(args);`; items.sp:465,475,480 ItemIsReady compares Items[].Cooldown against GetGameTime().

**Исправление.**

```
Write the float: char cd[16]; FloatToString(Configs[i].Cooldown, cd, sizeof(cd)); kv.SetString("cooldown", cd); (KeyValues has no SetFloat in this API surface; SetString + GetFloat round-trips exactly).
```

> **Поправка верификатора.** The fix's rationale is factually wrong: KeyValues DOES expose SetFloat — C:/develop/sm-1.13/include/keyvalues.inc:128 `public native void SetFloat(const char[] key, float value);` (legacy KvSetFloat at keyvalues.inc:387). The one-line fix is `kv.SetFloat("cooldown", Configs[i].Cooldown);`. Severity is minor rather than major: production cooldowns are overwhelmingly integral, the loss only occurs after an explicit admin Save, and the worst realistic under-shoot (sub-1s) is inside the GetTickInterval()*5.0 'ghost using' pad already added at items.sp:496.

### 88. Menu info strings carry raw Items[] indices; ItemRemove() shift makes admin act on wrong item

- **id**: `admin-menu-item-index-stale` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:523` -> `TransferByMapMenu_Handler()`
- **ось/инвариант**: invariant-I6 | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** TransferByMapMenu(), TransferByTargetMenu() and UseItemsMenu() encode the raw Items[] index into the menu info string and the handlers convert it straight back into `Items[item]` an arbitrary number of frames later. ItemsOnEntityDestroyed() -> ItemRemove() (items.sp:304-315, 606-613) shifts every entry above the removed one down by one while the menu is open, so a stored index silently renames itself to the next item. The map-transfer handler's only sanity check is `Items[item].Owner` == 0 (line 534), which any other unowned item also satisfies, so the wrong item is handed to the receiver. The target-transfer and forced-use handlers check `Items[item].Owner == target`, which does not disambiguate when the target holds two items — a documented situation ("player can have more than 1 item").

**Триггер.** Round is running, several item weapons lie unowned on the ground. Admin: sm_eadmin -> Transfer -> toggle to "Map" -> pick receiver -> TransferByMapMenu lists e.g. items 2,3,4 with info "<userid>_2", "<userid>_3", "<userid>_4". Before the admin presses a key the map (or SpawnItem's env_entity_maker Kill, spawn.sp:74) destroys the weapon entity of item 2 -> OnEntityDestroyed -> ItemsOnEntityDestroyed -> ItemRemove(2) -> old item 3 becomes index 2, old 4 becomes 3. The admin presses the key for "item 3": TransferByMapMenu_Handler line 523 decodes 3, line 534 sees Owner == 0 (true for the shifted-in item too) and line 541 TransferItem(3, receiver, client) equips the WRONG item. Same shift makes UseItemMenu_Handler (line 708) fire the wrong item of a two-item owner.

**Доказательства.** admin_menu.sp:483 `FormatEx(buffer[0], ..., "%i_%i", GetClientUserId(receiver), i);`; admin_menu.sp:523,534,541 decode + weak check + act; admin_menu.sp:573,614,631,637 same pattern for target transfer; admin_menu.sp:666,708,716,722 same for forced use; items.sp:606-613 `ItemRemove()` shifts Items[] down and decrements Items_Count; items.sp:304-315 calls it from OnEntityDestroyed; CLAUDE.md "Indices are not stable … while item indices are handed to timers, menu item data and API forwards".

**Исправление.**

```
Encode something stable in the info string and re-resolve in the handler: the weapon entity reference (`EntIndexToEntRef(Items[i].Weapon)` -> `EntRefToEntIndex` -> `ItemsGetByWeapon()`), which also catches entity-index reuse. Cheaper partial hardening: additionally verify `Items[item].Weapon` still matches the entity you listed and that `item < Items_Count`.
```

> **Поправка верификатора.** Trigger and severity need correcting. The finder never established that item weapon entities get destroyed mid-round, which is the weak part of their trigger. The provable trigger is the round boundary: all of these menus are shown with `menu.Display(client, 0)` and `0` is MENU_TIME_FOREVER (menus.inc:76), so the menu survives round_end -> entWatch.sp:182-186 OnRoundEnd -> ItemsOnRoundEnd -> ItemsClear (items.sp:33-37, Items_Count = 0) -> round_start -> ItemsOnRoundStart (items.sp:22-31) rebuilding Items[] from a fresh `FindEntityByClassname(entity, "*")` sweep whose order need not match the previous round's. The admin then presses a key encoding an index from the old round. Severity is minor, not major: the worst case is fail-safe rather than unsafe — the index can never exceed MAX_ITEMS (it was < Items_Count when written), and TransferItem -> TransferIsValidItem (transfer.sp:46-53) rejects `Weapon == 0` and knife/none slots, so the residual damage is 'the admin transfers/fires the wrong item', with no out-of-bounds access and no I5 bypass. The suggested fix (encode an entity reference and re-resolve via ItemsGetByWeapon) is correct.

### 89. Config list stores raw Configs[] indices; Reload/Remove makes admin edit wrong config

- **id**: `admin-config-index-stale` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:823` -> `ConfigsMenu_Handler()`
- **ось/инвариант**: invariant-I6 | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** ConfigsMenu() writes the loop index into the info string (line 772) and ConfigsMenu_Handler turns it back into a Configs[] index (line 823) with no validation against Configs_Count and no notion of which config it really was. Between display and selection the array can be rebuilt (AdminMenu_Handler case 'r' -> ConfigOnMapStart -> ConfigClearAll + re-parse) or shifted (RemoveConfig). The handler then Init()s and edits whatever now sits at that index — possibly a slot beyond Configs_Count, whose edits AdminConfigBrowseItems (loop `i < Configs_Count`) will never save.

**Триггер.** Admin A opens sm_eadmin -> Configs on a map with 10 configs; the list shows entries with info "0".."9". Admin B presses sm_eadmin -> Reload (case 'r'), the operator meanwhile having shortened <map>.cfg to 3 items, so Configs_Count becomes 3. Admin A now presses the key for entry "7": ConfigsMenu_Handler line 823 gives config = 7, line 829 Init(7), ConfigMenu(client) renders and edits Configs[7] — a stale block past Configs_Count that AdminConfigBrowseItems (line 1035 `i < Configs_Count`) will never write out, so the admin's edits vanish silently.

**Доказательства.** admin_menu.sp:770-779 info string = loop index; admin_menu.sp:823-830 StringToInt -> EditedConfigs[config] -> Init(config), no `config < Configs_Count` check; admin_menu.sp:86-94 the Reload entry re-parses Configs[]; helpers.sp:26-34 RemoveConfig shifts Configs[]; admin_menu.sp:1035 the save loop is bounded by Configs_Count.

**Исправление.**

```
Validate on selection and bail to ConfigsMenu(client) with a message when stale: `int config = StringToInt(buffer); if(config < 0 || config >= Configs_Count) { ConfigsMenu(client); return 0; }`. A robust fix keys the menu entry on Weapon_HammerId (stable within a map) and re-resolves through ConfigGetByWeaponHammerId().
```

> **Поправка верификатора.** A more reachable trigger than the finder's two-admin Reload race: a second admin removing a config is enough. Admin B: sm_eadmin -> Configs -> pick config 3 -> key 1 '[Remove item]' -> ConfigMenu_Handler case 0 (admin_menu.sp:900-905) -> RemoveConfig(3) (helpers.sp:26-34) shifts Configs[] down. Admin A's still-open Configs list now maps every info string >= 3 to a different config; selecting '5' edits what used to be config 6. Severity minor is right.

### 90. Save writes <map>.cfg without lowercasing while the loader lowercases before reading

- **id**: `admincfg-map-not-lowercase` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:1025` -> `AdminConfigSave()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** AdminConfigSave() builds the output path straight from GetCurrentMap() (lines 1025-1026), whereas ConfigOnMapStart() lowercases the map name before building the read path (config.sp:39-42). On a case-sensitive filesystem (production Linux servers) a map whose name contains an upper-case character is saved to a file the plugin will never read again — the admin's work is silently orphaned and the real config keeps its old content. The buffer is also char[256] rather than PLATFORM_MAX_PATH, and it is reused as both destination and format argument of BuildPath.

**Триггер.** Server runs a map whose BSP name has any upper-case letter (e.g. ze_FFVII_Mako_Reactor). RCON/ROOT admin edits configs and presses sm_eadmin -> Save -> AdminConfigSave line 1025-1028 exports to configs/entwatch/ze_FFVII_Mako_Reactor.cfg. Next map load, ConfigOnMapStart lowercases (config.sp:41) and reads configs/entwatch/ze_ffvii_mako_reactor.cfg — the untouched old file.

**Доказательства.** admin_menu.sp:1025-1026 `GetCurrentMap(buffer, sizeof(buffer)); BuildPath(Path_SM, buffer, sizeof(buffer), "configs/entwatch/%s.cfg", buffer);`; config.sp:39-42 `GetCurrentMap(map, sizeof(map)); StringToLowercase(map); ConfigParse(map);` -> config.sp:48 BuildPath. C:/develop/sm-1.13/include/files.inc:254-266 documents BuildPath but says nothing about destination/format aliasing, so the `buffer` reuse could not be verified from the includes.

**Исправление.**

```
char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];\nGetCurrentMap(map, sizeof(map));\nStringToLowercase(map);\nBuildPath(Path_SM, path, sizeof(path), "configs/entwatch/%s.cfg", map);\nkv.Rewind();\nkv.ExportToFile(path);
```

> **Поправка верификатора.** Both hedged sub-claims are wrong and should be dropped. (1) The BuildPath aliasing is safe: sm_BuildPath (core/logic/smn_filesystem.cpp:872-887) formats into a local `char path[PLATFORM_MAX_PATH]` via atcprintf FIRST and only then calls `g_pSM->BuildPath(Path_SM_Rel, buffer, params[3], "%s", path)`, so passing the destination as a format argument is fine. (2) `char buffer[256]` is not undersized — PLATFORM_MAX_PATH is 256, so the two are identical. What remains is purely the missing StringToLowercase, which makes this minor rather than a buffer issue.

### 91. The per-config edit lock is dropped by the interrupt-cancel of the say-command redisplay

- **id**: `admin-editedconfigs-lifecycle` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:1003` -> `AdminOnClientSayCommand()`
- **ось/инвариант**: correctness | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** AdminOnClientSayCommand saves and restores EditClientsConfigs[client] around ConfigMenu(client) (lines 1003-1006) because displaying a menu to a client who is already viewing one cancels the old one with MenuCancel_Interrupted, and ConfigMenu_Handler's Cancel branch wipes the editor state. The restore covers EditClientsConfigs but NOT EditedConfigs[cfg], which that same cancel set back to false after ConfigMenu had just set it true (lines 844-847 run before menu.DisplayAt at line 873). From the first chat-entered value onwards the config is unlocked, so a second admin can enter the same config concurrently. EditedConfigs[] is likewise never reset on map start and is not shifted by the Remove path.

**Триггер.** Admin A: sm_eadmin -> Configs -> config 3 (EditedConfigs[3] = true) -> select "Name" -> type a name in chat. AdminOnClientSayCommand line 1005 calls ConfigMenu(client): line 846 sets EditedConfigs[3] = true, line 873 DisplayAt interrupts the still-open menu -> ConfigMenu_Handler MenuAction_Cancel (line 886) sets EditedConfigs[3] = false and Clear()s; line 1006 restores only EditClientsConfigs. Admin B can now open config 3 at the same time (line 824 sees false) and the two admins overwrite each other's fields.

**Доказательства.** admin_menu.sp:1002-1007 save/restore of EditClientsConfigs only; admin_menu.sp:844-847 lock set, admin_menu.sp:873 DisplayAt; admin_menu.sp:884-893 Cancel branch clears the lock and the state; C:/develop/sm-1.13/include/menus.inc:104 `MenuCancel_Interrupted = -2 /**< Client was interrupted with another menu */` (the ordering of the interrupt inside Display is core behaviour, not include-documented — but the save/restore dance at 1003-1006 exists precisely because the author observed it).

**Исправление.**

```
Re-assert the lock after the redisplay: `EditClientsConfigs[client] = editItemCopy; EditedConfigs[cfg] = true;` and clear the whole EditedConfigs array in ConfigOnMapStart/AdminMenuInit so a stale lock cannot survive a map.
```

### 92. sm_eadmin from the server console throws a native error (client index 0)

- **id**: `admin-console-client0` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:18` -> `AdminMenu()`
- **ось/инвариант**: api-use | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** Command_Admin passes the command's client index straight to AdminMenu(), which calls GetUserFlagBits(client) as its first statement. Admin commands registered with RegAdminCmd are executable from the server console with client == 0, and GetUserFlagBits errors on an invalid client index, so the command aborts with a logged plugin error instead of a clean reply. (menu.Display(0, 0) further down would fail the same way.)

**Триггер.** Operator types `sm_eadmin` at the server console (or via rcon) -> ConCmd dispatch invokes Command_Admin(0, 0) -> AdminMenu(0) -> line 18 GetUserFlagBits(0) -> "Client index 0 is invalid" native error; nothing is displayed and an error is written to the SM error log.

**Доказательства.** admin_menu.sp:10-14 Command_Admin passes client through unchecked; admin_menu.sp:18 `int flags = GetUserFlagBits(client);`; C:/develop/sm-1.13/include/clients.inc:530-538 `native int GetUserFlagBits(int client);` with "@error Invalid client index, or client not connected.". The fact that RegAdminCmd commands reach the callback with client == 0 from the console is SourceMod core dispatch behaviour and is not documented in console.inc:401-417 — hence 'likely' rather than 'proven'.

**Исправление.**

```
public Action Command_Admin(int client, int args)\n{\n    if(client == 0)\n    {\n        ReplyToCommand(client, "[entWatch] sm_eadmin is in-game only.");\n        return Plugin_Handled;\n    }\n    AdminMenu(client);\n    return Plugin_Handled;\n}
```

### 93. Editor writes admin-typed Mode/Slot/Cooldown without the parser's clamps

- **id**: `admin-no-numeric-validation` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:970` -> `AdminOnClientSayCommand()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** Every numeric field is written with a bare StringToInt/StringToFloat of the chat line. Both config parsers clamp the mode (`if(c.Mode > MODE_CHARGESCD) c.Mode = MODE_PROTECT;` plus the PROTECT display strip), but the editor does not — an out-of-range Mode lands in Configs[].Mode and reaches ItemIsReady()/ItemReload()/ItemFormat(). Those switches have no matching case, so ItemIsReady falls into `default: return true` (always ready) while ItemReload does nothing (no cooldown, no use counting): entWatch's readiness is then permanently AHEAD of the map's, the exact direction invariant I4 forbids. Nothing indexes an array with Mode/Slot, so there is no out-of-bounds read — this is a validation gap, not memory unsafety. A negative Cooldown or Maxuses has the same effect on their modes.

**Триггер.** RCON/ROOT admin: sm_eadmin -> Configs -> item -> "Mode" (Slot = 7) -> types `9` (or `-1`, or a non-numeric word, which StringToInt maps to 0 = MODE_PROTECT) in chat -> AdminOnClientSayCommand case 7 (line 970) stores 9. From then on every press of that item passes ItemIsReady() through items.sp:483-486 `default: return true` and ItemReload() (items.sp:506-531) records nothing, so the item is announced and allowed at any rate regardless of the map's own cooldown. The bad value is then persisted by Save.

**Доказательства.** admin_menu.sp:956-998 all numeric cases are unguarded StringToInt/StringToFloat; config.sp:153-157 and config.sp:194-198 show the clamp + PROTECT display strip the parser applies; items.sp:457-488 ItemIsReady's `default: return true`; items.sp:506-531 ItemReload's switch has no default; admin_menu.sp:1064/1080 the unvalidated value is written back to disk.

**Исправление.**

```
Apply the parser's clamps in the editor, e.g. case 7: { int mode = StringToInt(args); if(mode < MODE_PROTECT || mode > MODE_CHARGESCD) mode = MODE_PROTECT; Configs[cfg].Mode = mode; if(mode == MODE_PROTECT) Configs[cfg].Display &= ~DISPLAY_USE; } and reject negative Cooldown/Maxuses/Slot the same way.
```

> **Поправка верификатора.** Important context the finder missed, which lowers the severity to minor: the same broken state is already reachable without the editor. config.sp:151 does `c.Mode = kv.GetNum("mode") - 1;` and the clamp at 153-154 only catches `> MODE_CHARGESCD`, so a GFL block with no `mode` key yields Mode == -1 — which then falls into the same `default: return true`. items.sp:250 (`|| Configs[Items[item].Config].Mode == -1`) shows the author already knows Mode == -1 occurs. So the editor is one of two routes into an existing hole, not the sole cause; the clamp belongs in config.sp as much as in admin_menu.sp.

### 94. Transfer and forced-use menu paths discard the failure return and show success

- **id**: `admin-menu-silent-failure` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:541` -> `TransferByMapMenu_Handler()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** TransferItem() returns false whenever TransferIsValidItem() rejects the item (transfer.sp:58-61 -> transfer.sp:44-56: weapon gone, receiver already owns it, or SLOT_NONE/SLOT_KNIFE), and AssistUseAdmin() returns false when the item has no button or no owner, or when the button input could not be fired (assist_use.sp:78-99). All three menu call sites throw the result away and fall straight through to AdminMenu(client) without a message, so the admin is told nothing and reasonably believes the action succeeded. The same handlers do print 'Materia is unavailbale' on their own pre-checks (admin_menu.sp:536, 633), which makes the silence on the real failure path inconsistent as well as wrong.

**Триггер.** RCON/GENERIC admin: sm_eadmin -> Transfer -> toggle to 'Map' -> pick a receiver -> TransferByMapMenu (admin_menu.sp:468-496) lists an unowned item. Before the admin presses the key the item's weapon entity is destroyed (map cleanup, or the round boundary) -> OnEntityDestroyed -> ItemsOnEntityDestroyed -> ItemUnhook/ItemClear/ItemRemove (items.sp:304-315), leaving that index holding a cleared item with Weapon == 0. The admin presses the key: admin_menu.sp:534 `if(Items[item].Owner)` is false so the guard passes, admin_menu.sp:541 TransferItem() -> TransferIsValidItem() -> transfer.sp:46-47 `if(Items[item].Weapon == 0) return false;` -> nothing is transferred, and admin_menu.sp:542 AdminMenu(client) redisplays the root menu with no error. Same shape at admin_menu.sp:637 (target transfer) and admin_menu.sp:722 (forced use).

**Доказательства.** admin_menu.sp:541 `TransferItem(item, receiver, client);` (bool return discarded); admin_menu.sp:637 same; admin_menu.sp:722 `AssistUseAdmin(item, client);` same; transfer.sp:58-61 `bool TransferItem(...) { if(!TransferIsValidItem(item, receiver)) return false; ... }`; transfer.sp:44-56 TransferIsValidItem; assist_use.sp:80-81 `if(!Items[item].Button || !Items[item].Owner) return false;` and assist_use.sp:93-98 which returns false when AssistUse() failed; contrast admin_menu.sp:529-531 and 633-635 which do report failure for the handlers' own checks.

**Исправление.**

```
Branch on the return at each of the three call sites, e.g. at admin_menu.sp:541: `if(!TransferItem(item, receiver, client)) { PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Materia is unavailbale"); TransferMenu(client, true); return 0; } AdminMenu(client);` and the analogous form around AssistUseAdmin() at line 722.
```

### 95. "Reload" re-arms the item subsystem between rounds by forcing RoundStarted back to true

- **id**: `admin-reload-roundstarted` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:91` -> `AdminMenu_Handler()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** entWatch deliberately disarms every item interaction while RoundStarted is false: OnButtonPress returns Plugin_Handled at sdkhook.sp:53-54, OnTriggerTouch at sdkhook.sp:120-121, Compare_OnEqualTo/Relay_OnTrigger bail at sdkhook.sp:88 and 104, and assist_use bails at assist_use.sp:142-143. The Reload menu item calls the lifecycle forwards by hand: OnRoundEnd() sets RoundStarted = false (items.sp:35) and the immediately following OnMapStart() -> ItemsOnMapStart() -> ItemsOnRoundStart() sets RoundStarted = true (items.sp:25) and re-scans every entity. Pressing Reload during the end-of-round window therefore leaves the plugin armed inside a period in which it is supposed to be disarmed, and repopulates Items[] from weapon/button entities the imminent round restart is about to delete.

**Триггер.** Round ends normally: entWatch.sp:182-186 OnRoundEnd -> ItemsOnRoundEnd -> items.sp:35 RoundStarted = false, items.sp:36 ItemsClear. During the freeze, an RCON/ROOT admin presses sm_eadmin -> Reload: AdminMenu_Handler case 'r' (admin_menu.sp:86-94) -> OnMapStart() (entWatch.sp:110-124) -> ItemsOnMapStart() -> ItemsOnRoundStart() -> items.sp:25 RoundStarted = true plus a full FindEntityByClassname sweep that re-registers and re-hooks the still-present weapons and buttons. A player still holding an item can now press it and sdkhook.sp:53 no longer blocks; assist_use.sp:142 no longer blocks either.

**Доказательства.** admin_menu.sp:86-94 (`Late = true; OnPluginEnd(); OnRoundEnd(null, "", false); OnMapStart(); ...`); items.sp:22-31 ItemsOnRoundStart with `RoundStarted = true;` at line 25; items.sp:33-37 ItemsOnRoundEnd with `RoundStarted = false;` at line 35; entWatch.sp:110-124 OnMapStart -> ItemsOnMapStart; sdkhook.sp:53-54, sdkhook.sp:120-121, sdkhook.sp:88, sdkhook.sp:104; assist_use.sp:142-143.

**Исправление.**

```
Stop calling SourceMod forwards by hand and drive the modules directly, preserving the round state across the rebuild: capture `bool wasStarted = RoundStarted;` before the teardown and restore it after ItemsOnRoundStart() has re-registered the entities (or simply refuse the reload while `!RoundStarted` and tell the admin to wait for the next round).
```

### 96. RemoveConfig() reads Configs[MAX_CONFIGS] when the map has 50 configs

- **id**: `removeconfig-oob-read` | **место**: `addons/sourcemod/scripting/entWatch/helpers.sp:30` -> `RemoveConfig()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The loop runs `i < Configs_Count` and reads `Configs[i + 1]`, so the last iteration reads Configs[Configs_Count]. Configs is declared `Config Configs[MAX_CONFIGS]` with MAX_CONFIGS = 50 (config.sp:1, config.sp:33), i.e. valid indices 0..49. Configs_Count is allowed to reach exactly 50 (the parser guard is `if(Configs_Count >= MAX_CONFIGS) return;` at config.sp:94, the admin 'Add config item' guard is `if(Configs_Count < MAX_CONFIGS)` at admin_menu.sp:807). At Configs_Count == 50 the last iteration evaluates Configs[50], which the compiler's BOUNDS check rejects (unsigned `cmp/ja` against the limit — jit_x86.cpp:1193-1199, interpreter.cpp:674-681), throwing SP_ERROR_ARRAY_BOUNDS and aborting the whole menu callback.

**Триггер.** On a map whose configs/entwatch/<map>.cfg has 50 item blocks (or an admin who pressed 'Add config item' until Configs_Count == 50), an rcon admin runs `sm_eadmin` -> Configs -> <any config> -> '[Remove item]'. Path: ConfigMenu_Handler (admin_menu.sp:903) -> RemoveConfig() -> helpers.sp:30 with i == 49 -> read of Configs[50] -> array-index-out-of-bounds error; the plugin aborts the callback and the admin menu dies.

**Доказательства.** helpers.sp:28-31; MAX_CONFIGS/Configs declared config.sp:1 and config.sp:33; ceiling reachable per config.sp:94 and admin_menu.sp:807; SourcePawn bounds semantics: sourcepawn/vm/x86/jit_x86.cpp:1193-1199 (`__ cmpl(eax, limit); __ j(above, bounds->label())` — unsigned, so both >limit and negative indices throw) and sourcepawn/vm/interpreter.cpp:674-681.

**Исправление.**

```
Same edit as `removeconfig-no-count-decrement`: change the bound to `i < Configs_Count - 1`. One fix removes both findings — do not apply two separate patches.
```

> **Поправка верификатора.** Mechanism verified exactly, but severity is minor, not major, and the finding is not independently actionable — it is the same line and the same one-character fix as removeconfig-no-count-decrement, so per CLAUDE.md's 'recompute after each edit' rule only one patch may be applied. The trigger also requires Configs_Count to be exactly MAX_CONFIGS. The parser ceiling (config.sp:94) and the admin Add ceiling (admin_menu.sp:807) do permit exactly 50, but this repo ships no map config at all (addons/sourcemod/configs/entwatch/ contains only colors.cfg), so I could not show that any production map reaches 50 item blocks; the only demonstrable route is an rcon admin pressing 'Add config item' until the count hits 50, which is contrived.

### 97. sm_espawn from the server console throws on GetClientAbsOrigin(0) and leaks an env_entity_maker

- **id**: `spawn-console-client0-leak` | **место**: `addons/sourcemod/scripting/entWatch/spawn.sp:22` -> `Command_Spawn / SpawnItem()`
- **ось/инвариант**: api-use | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** `sm_espawn <shortname>` with one argument sets `receiver = client` (spawn.sp:22). Server-console/rcon invocations arrive with client == 0 and skip the admin check entirely (ConCmdManager.cpp:253 `if (client && hook->admin && !CheckAccess(...))`), so client 0 reaches SpawnItem. GetClientAbsOrigin(0, origin) throws 'Client index 0 is invalid' — GetAbsOrigin does playerhelpers->GetGamePlayer(client) and PlayerManager::GetPlayerByIndex returns NULL for client < 1. Crucially the env_entity_maker has already been created one statement earlier (spawn.sp:61) and the native error aborts the callback, so DispatchSpawn / TeleportEntity / ForceSpawn / Kill (spawn.sp:71-74) never run: an unspawned env_entity_maker is left in the entity list for the rest of the map, and the item is not spawned. Every repeat of the command leaks another entity.

**Триггер.** Server console (or rcon) executes `sm_espawn deagle`. Path: ConCmdManager::InternalDispatch pushes realClient = 0 and bypasses CheckAccess -> Command_Spawn(0, 1) -> args == 1 so receiver stays 0 -> SpawnItem(item, 0, 0) -> point_template found -> CreateEntityByName("env_entity_maker") succeeds (spawn.sp:61) -> GetClientAbsOrigin(0, origin) (spawn.sp:66) throws -> callback aborted, maker never killed.

**Доказательства.** spawn.sp:22 (`int receiver = client;`), spawn.sp:61 (entity created), spawn.sp:66 (GetClientAbsOrigin), spawn.sp:71-74 (never reached); GetClientAbsOrigin declared clients.inc:657, implemented core/logic/smn_players.cpp:867-878 (`GetGamePlayer(client)` -> NULL -> ThrowNativeError "Client index %d is invalid"), core/PlayerManager.cpp:1380-1387 (`if (client > m_maxClients || client < 1) return NULL;`); server console bypasses admin checks and is passed as client 0 — core/ConCmdManager.cpp:233-235 and :253.

**Исправление.**

```
Validate the receiver before touching any entity, and create the maker only after the origin is known:
```
public Action Command_Spawn(int client, int args)
{
    ...
    int receiver = client;
    if(args > 1)
    {
        GetCmdArg(2, buffer, sizeof(buffer));
        receiver = FindTarget(client, buffer, false, false);
        if(receiver == -1)
            return Plugin_Handled;
    }

    if(receiver < 1 || !IsClientInGame(receiver))
    {
        ReplyToCommand(client, "%t Specify a receiver", "Tag");
        return Plugin_Handled;
    }
    ...
```
and in SpawnItem move `GetClientAbsOrigin(receiver, origin)` above the `CreateEntityByName` call.
```

> **Поправка верификатора.** Every step of the mechanism is verified, but two details need correcting and the severity is minor rather than major.
(1) The claimed secondary damage is wrong in one respect: %N with client 0 does NOT throw. core/logic/sprintf.cpp:1186-1201 substitutes the literal "Console" when the value is 0 and only errors for a non-zero invalid index. So PrintToChatAll2 at spawn.sp:76 and LogMessage at spawn.sp:77 would have been fine; GetClientAbsOrigin at spawn.sp:66 is the sole throw site, and it is reached first.
(2) Severity: the only reachable actor is the server console / rcon operator (no player and no in-game admin can produce client == 0), each invocation leaks exactly one unspawned edict, and the operator sees the native error in the console immediately. Minor.
The suggested fix is right; the simpler surgical form is to validate `receiver` before any entity is created, since moving GetClientAbsOrigin above CreateEntityByName alone still leaves the command silently doing nothing.

### 98. `sm_etransfer $ <receiver>` transfers Items[0] via an empty short-name match

- **id**: `transfer-dollar-empty-shortname` | **место**: `addons/sourcemod/scripting/entWatch/transfer.sp:24` -> `Command_Transfer()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The `$` branch passes `buffer[1]` straight to ItemsGetByShortName without checking that anything follows the `$`. ItemsGetByShortName (items.sp:356-366) computes `len = strlen(name)` and calls `strncmp(ShortName, name, len, false)`; SourceMod's strncmp forwards to strncasecmp (smn_string.cpp:97-110) and strncasecmp with n == 0 returns 0 by definition, so an empty query matches the very first entry in Items[]. The admin ends up transferring an arbitrary item instead of getting an error. The same shape means any 1-2 character query silently prefix-matches the first item whose short name begins with it, but the empty-string case is created here, in the caller.

**Триггер.** An admin with ADMFLAG_GENERIC types `sm_etransfer $ Bob` (a typo, or a leftover `$` after deleting the name). Path: Command_Transfer -> buffer == "$" -> buffer[0] == '$' -> ItemsGetByShortName(buffer[1]) with an empty string -> strncmp(..., 0) == 0 on i == 0 -> returns 0 -> TransferItem(0, Bob, admin) transfers whatever item happens to occupy Items[0].

**Доказательства.** transfer.sp:22-27; ItemsGetByShortName items.sp:356-366; strncmp -> strncasecmp core/logic/smn_string.cpp:97-110 (`return strncasecmp(str1, str2, (size_t)params[3]);`), n == 0 compares nothing.

**Исправление.**

```
```
    if(buffer[0] == '$')
    {
        if(!buffer[1])
        {
            ReplyToCommand(client, "%t %t!", "Tag", "Incorrect usage");
            return Plugin_Handled;
        }

        item = ItemsGetByShortName(buffer[1]);
        ...
```
```

### 99. sm_decuses decrements the first Items[] entry sharing the config, not the live one

- **id**: `stripper-decuses-wrong-instance` | **место**: `addons/sourcemod/scripting/entWatch/stripper.sp:64` -> `Command_DecUses()`
- **ось/инвариант**: correctness | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** ItemsGetByWeaponHammerID (items.sp:368-377) matches on `Configs[Items[i].Config].Weapon_HammerId`, i.e. on the *config*, and returns the first hit. Several Items[] entries can share one config: ItemsOnEntitySpawned (items.sp:97-106) tries to attach the new entity to an existing item and, when ItemsRegisterItemEntity refuses because that item already has a Weapon (items.sp:157-158), falls through to ItemsInitiateItem and creates a second instance with the same config. That happens whenever a map point_template respawns the item or an admin runs `sm_espawn` (spawn.sp:38-79). From then on `sm_decuses <hammerid>` always hits Items[first], which may be the stale/unowned instance, while the instance the player is actually holding keeps its Uses count. The result is that entWatch's use accounting drifts from the map's — the I4 direction that must not happen.

**Триггер.** Map with a respawnable item (or an admin used `sm_espawn`), so two Items[] entries share the config. The map's logic_relay fires the server command `sm_decuses 1234567` when it grants a use back. Path: Command_DecUses -> ItemsGetByWeaponHammerID(1234567) -> items.sp:370-373 returns the lowest index with that config (the dead/unowned instance) -> Items[that].Uses-- while the held instance is untouched.

**Доказательства.** stripper.sp:64-70; ItemsGetByWeaponHammerID items.sp:368-377 (matches config, returns first); duplicate instances created at items.sp:97-106 + items.sp:157-158 + items.sp:229-238; spawn path spawn.sp:38-79.

**Исправление.**

```
Prefer an owned instance, e.g. resolve by hammerid but pick the entry that has an Owner (falling back to the first): add a variant of ItemsGetByWeaponHammerID that skips `!Items[i].Owner` entries, or drive sm_decuses off the weapon entity's own m_iHammerID rather than the config's.
```

> **Поправка верификатора.** The code-level fact is exactly as described and the duplicate-instance trigger is real, but the framing and the fix need correcting. (1) The proposed fix's alternative — 'drive sm_decuses off the weapon entity's own m_iHammerID rather than the config's' — cannot work: duplicate instances exist precisely because a point_template copy carries the same hammerid as the original (that is why ItemsRegisterGetKeyValues recognises spawned items at all), so both instances have an identical entity hammerid. There is no signal in the command that can disambiguate them; only the 'prefer an instance that has an Owner' heuristic is implementable. (2) The I4 framing is half right: decrementing Uses on the wrong instance does push THAT item ahead of the map (dangerous direction), while the instance the map meant stays behind (safe direction). (3) Severity minor: it needs an admin sm_espawn (or a map that keeps a respawned copy alive alongside the original) to create the duplicate in the first place.

### 100. stripper commands write unvalidated values and fail completely silently

- **id**: `stripper-silent-unvalidated-writes` | **место**: `addons/sourcemod/scripting/entWatch/stripper.sp:26` -> `Command_SetCooldown / Command_SetMaxuses / Command_DecUses()`
- **ось/инвариант**: reliability | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** All three handlers return Plugin_Handled with no output on every failure path — wrong argument count (stripper.sp:10, 33, 56), unknown hammerid (stripper.sp:23, 46, 66). Because these commands are driven from stripper/map cfg files, a typo'd hammerid or a missing argument is indistinguishable from success; nothing appears in the log. In addition the parsed value is written straight into Configs[] with no bounds: StringToFloat on a non-numeric argument yields 0.0 and StringToInt yields 0, so `sm_setcooldown <id> <typo>` sets Configs[].Cooldown = 0.0, which makes ItemIsReady() (items.sp:463-467, `Items[item].Cooldown < time`) true on every press — entWatch's readiness runs ahead of the map's, the exact I4 failure direction. A negative cooldown has the same effect.

**Триггер.** A server operator puts a bad line into cfg/<map>.cfg or a stripper config, e.g. `sm_setcooldown 1234567 default`. Path: Command_SetCooldown -> GetCmdArg(2) -> StringToFloat("default") -> 0.0 -> ConfigGetByWeaponHammerId succeeds -> Configs[config].Cooldown = 0.0 (stripper.sp:26) -> ItemReload sets Items[].Cooldown = now, so ItemIsReady returns true on the very next press. Nothing is logged, so the operator never learns.

**Доказательства.** stripper.sp:8-29, 31-52, 54-73 (every early return is silent); stripper.sp:26 and :49 write without bounds; ItemIsReady items.sp:447-489, ItemReload items.sp:506-531 consume Configs[].Cooldown/Maxuses directly.

**Исправление.**

```
Log the failures and clamp the values, e.g.
```
    if(config == -1)
    {
        LogError("sm_setcooldown: hammerid %i not found in the map config", hammerid);
        return Plugin_Handled;
    }

    if(cooldown < 0.0)
        cooldown = 0.0;
```
and the same shape for sm_setmaxuses / sm_decuses.
```

> **Поправка верификатора.** Half of this finding does not survive. The 'writes unvalidated values' part is not a defect: Configs[].Cooldown = 0.0 is a legitimate value (MODE_PROTECT items have no cooldown at all, config.sp:156-157), the commands are RegServerCmd and therefore reachable only by the operator who wrote the cfg line, and the plugin writing exactly the number it was given is correct behaviour — clamping it would be armouring, not fixing. Framing it as an I4 violation is wrong: entWatch is not getting ahead of the map on its own, the operator told it to. The half that does survive is purely diagnostic: on the one code path that has no other feedback channel — a line executed from cfg/<map>.cfg or a stripper config — a wrong argument count (stripper.sp:10, :33, :56) and an unresolvable hammerid (stripper.sp:23, :46, :66) both return Plugin_Handled with nothing logged, so a typo is indistinguishable from success. Only the LogError half of the proposed fix should be applied; drop the clamping.

### 101. UTIL_GetAccountIDFromSteamID reads past the terminator on short STEAM_ strings

- **id**: `helpers-steamid-short-read` | **место**: `addons/sourcemod/scripting/entWatch/helpers.sp:4` -> `UTIL_GetAccountIDFromSteamID()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CONFIRMED

**Проблема.** The STEAM_ branch tests only the first 6 characters and then unconditionally reads steamid[8] and steamid[10] (helpers.sp:4-6). Any argument that begins with "STEAM_" but is shorter than 11 characters — or that is not a real Steam2 id at all — makes those reads land past the string's NUL, on whatever the caller's stack buffer happened to contain. Both callers pass char[64] buffers (restrict.sp:138, restrict.sp:158) filled by GetCmdArg, so the SourcePawn bounds check passes and no error is raised — the function silently returns a garbage account id which is then used verbatim in the SQL. A concrete deterministic case: the literal SourceMod auth string "STEAM_ID_PENDING" yields StringToInt("ENDING") << 1 | ('_' - 48) == 47, i.e. it bans/unbans account 47.

**Триггер.** An rcon admin (or a script) runs `sm_deleban STEAM_` or `sm_addeban 60 STEAM_ID_PENDING`. Path: Command_DeleteBan (restrict.sp:158-161) / Command_AddBan (restrict.sp:140-144) -> RestrictDeleteBan/RestrictAddBan -> UTIL_GetAccountIDFromSteamID (restrict.sp:549 / restrict.sp:428) -> helpers.sp:4-6 reads steamid[8]/steamid[10] beyond the terminator -> non-zero garbage id -> `id && !ipIsValid` path taken (restrict.sp:430/551) -> a DELETE/INSERT is issued against the wrong account.

**Доказательства.** helpers.sp:2-19; callers restrict.sp:428 and restrict.sp:549 with buffers declared at restrict.sp:138 and restrict.sp:158; the second branch is correctly short-circuit-guarded (`!strncmp(...) && steamid[strlen(steamid)-1] == ']'`, helpers.sp:9) which shows the author knew the pattern — the first branch simply lacks it.

**Исправление.**

```
```
stock int UTIL_GetAccountIDFromSteamID(const char[] steamid)
{
	int len = strlen(steamid);

	if (len > 10 && !strncmp(steamid, "STEAM_", 6) && steamid[7] == ':' && steamid[9] == ':')
	{
		return StringToInt(steamid[10]) << 1 | (steamid[8] - 48);
	}
	...
```
```

> **Поправка верификатора.** Real, but the mechanism description needs two corrections and the example is the weakest available case.
(1) It is not an out-of-bounds read in any SourcePawn sense and cannot throw. For an unsized array parameter (`const char[] steamid`) the compiler emits `OP_BOUNDS, INT_MAX` rather than a real limit — sourcepawn/compiler/code-generator.cpp:1091-1096, the `else` branch with the comment 'vm uses unsigned compare, this protects against negative indices'. So steamid[8] and steamid[10] simply read bytes 8 and 10 of the caller's 64-byte buffer.
(2) Those bytes are not arbitrary stack junk. SourcePawn zero-initialises local arrays declared without an initialiser (code-generator.cpp:316-390: EmitLocalVar -> BuildCompoundInitializer -> OP_INITARRAY_ALT with a non-zero `array.zeroes` fill whenever decl->autozero() holds). So the two call sites behave differently and BOTH are deterministic:
  - sm_deleban: `char steamid[64]` (restrict.sp:158) is used once, so a bare `sm_deleban STEAM_` gives steamid[8] == 0 and steamid[10] == 0 -> `StringToInt("") << 1 | (0 - 48)` == -48. Non-zero, so the `!id && !ipIsValid` guard at restrict.sp:551 passes and a DELETE runs for pid = -48.
  - sm_addeban: the SAME buffer is reused for argument 1 and argument 2 (restrict.sp:140 then :142), and GetCmdArg only writes up to its own terminator, so the tail still holds the duration string. `sm_addeban 1234567890123 STEAM_` leaves "890123" at bytes 7..12, giving steamid[8]=='9' and StringToInt(steamid[10])==123 -> id = 123<<1|9 = 255, and an INSERT is issued for account 255.
The 'STEAM_ID_PENDING -> 47' arithmetic in the finding is correct but that literal is never a command argument in practice; the reused-buffer case above is the realistic one. Severity minor: rcon-only, and the resulting id essentially never collides with a real account.

### 102. RemoveConfig() shifts Configs[] without invalidating the config indices the live config editor is holding

- **id**: `removeconfig-stale-editor-index` | **место**: `addons/sourcemod/scripting/entWatch/helpers.sp:26` -> `RemoveConfig()`
- **ось/инвариант**: found-by-verifier | **уверенность**: likely | **вердикт верификатора**: CONFIRMED

**Проблема.** RemoveConfig (helpers.sp:26-34) renumbers every config above the removed one, and it already knows that stored indices must be repaired — that is exactly what RemoveItemByConfig's `Items[i].Config--` (helpers.sp:46-49) is for. But two other stores of config indices are left untouched: `EditedConfigs[MAX_CONFIGS]` (admin_menu.sp:731), the per-config 'someone is editing this' lock, and `EditClientsConfigs[client].Config` (admin_menu.sp:757), the per-admin editing cursor. Neither is shifted, and the removing admin's own cursor is not even cleared — ConfigMenu_Handler case 0 (admin_menu.sp:900-905) clears EditedConfigs for the old index and calls RemoveConfig, then displays ConfigsMenu while leaving EditClientsConfigs[client].Config and .Slot exactly as they were. Because the array shifted down, that cursor now designates a different config, and AdminOnClientSayCommand (admin_menu.sp:928-1008) writes straight into `Configs[cfg]` with no re-validation. This is CLAUDE.md's I6 ('indices are not stable... any new code that stores an index across frames must account for this') violated by the very function that does the shifting.

**Триггер.** A single rcon admin, in one uninterrupted menu session on a map whose config has at least four items. (1) `sm_eadmin` -> 'Configs item' -> ConfigsMenu -> selects config #2 -> ConfigsMenu_Handler (admin_menu.sp:829) -> EditClientsConfigs[A].Init(2) -> ConfigMenu. (2) Selects 'Name' (menu index 2) -> ConfigMenu_Handler default branch (admin_menu.sp:911-915) -> EditClientsConfigs[A].Slot = 0 -> ConfigMenu redisplayed. (3) Selects '[Remove item]' (index 0) -> ConfigMenu_Handler case 0 (admin_menu.sp:900-905) -> RemoveConfig(2) shifts old configs 3,4,... down into slots 2,3,... -> ConfigsMenu(A) is displayed. MenuAction_Cancel does NOT fire (the menu ended via Select), so EditClientsConfigs[A] is still {Config = 2, Slot = 0}. (4) The admin types 'Deagle' in chat -> OnClientSayCommand (client.sp:113-127) -> AdminOnClientSayCommand -> IsEdit() is true (admin_menu.sp:930), Slot == 0 -> `strcopy(Configs[2].Name, ..., "Deagle")` (admin_menu.sp:942) renames what the admin still sees as the config he deleted but which is now the config that used to be #3. The chat line is swallowed (returns true -> Plugin_Handled at client.sp:123) so nothing hints at what happened, and ConfigMenu is reopened on the wrong config.

**Доказательства.** helpers.sp:26-34 (shifts Configs[], repairs Items[].Config via helpers.sp:46-49, repairs nothing else); admin_menu.sp:731 `bool EditedConfigs[MAX_CONFIGS];`; admin_menu.sp:757 `EditClientConfig EditClientsConfigs[MAXPLAYERS + 1];`; admin_menu.sp:900-905 (the remove branch clears EditedConfigs for the old index but never calls EditClientsConfigs[client].Clear()); admin_menu.sp:928-1008 (AdminOnClientSayCommand writes to Configs[cfg] guarded only by IsEdit() and Slot); admin_menu.sp:886-887 shows the author's own cleanup pattern on the Cancel path, which is precisely what the Select-remove path omits. A second, concurrent-admin variant follows from the same defect: admin B removing config 1 while admin A is parked on config 5 silently retargets A onto the old config 6.

**Исправление.**

```
Clear the removing admin's cursor at the call site, since RemoveConfig has no visibility of the editor's state and admin_menu.sp is where the index is stored:
```
case 0:
{
	EditedConfigs[EditClientsConfigs[client].Config] = false;
	RemoveConfig(EditClientsConfigs[client].Config);
	EditClientsConfigs[client].Clear();      // индексы сдвинулись — курсор больше не валиден
	ConfigsMenu(client);
}
```
The concurrent-admin half needs the EditedConfigs[] flags shifted the same way Items[].Config is; that is a larger change and should not be bundled with the one-liner above. Do not apply this in the same batch as the removeconfig-no-count-decrement fix without recomputing — both touch the same removal flow.
```

### 103. %t on missing phrase "Materia is unavailbale" throws and aborts the menu handler

- **id**: `phrase-materia-is-unavailbale-missing` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:536` -> `TransferByMapMenu_Handler / TransferByTargetMenu_Handler()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CRITIC

**Проблема.** Two call sites format the translation key "Materia is unavailbale" (admin_menu.sp:536 and :633). translations/entWatch.phrases.txt defines "Item is unavailbale" (line 250) - the key with the word 'Materia' is defined nowhere, in either translations file loaded at entWatch.sp:59-60. A %t whose phrase cannot be found is not a silent fallback: Translate() fails for the client language, then for the server language, then for English, and calls ThrowNativeErrorEx(SP_ERROR_PARAM, "Language phrase \"%s\" not found (arg %d)"). sm_vformat does not wrap atcprintf in a DetectExceptions guard, so the exception stays on the context and the calling plugin function is unwound. The admin therefore gets NO message AND the statement after it - TransferMenu(client) at admin_menu.sp:537 / :634 - never runs, so the menu simply disappears, and the server logs an exception every time. This is the whole class of defect the audit never ran: no auditor cross-checked %t/%T keys or #format arities against the phrases file. (Everything else checks out - I verified all 90+ %t sites and all plain-format arities; see the clean entries.)

**Триггер.** An ADMFLAG_GENERIC admin runs sm_eadmin -> 'Transfer item' -> toggles to Map mode -> picks a receiver -> TransferByMapMenu builds the list from items with no owner (admin_menu.sp:480 `!TransferIsValidItem(i) || Items[i].Owner`). Before he presses a key, an ordinary player walks over that item: SDKHook_WeaponEquipPost -> OnWeaponPickup sets Items[item].Owner = client (sdkhook.sp:30). The admin now selects it: TransferByMapMenu_Handler MenuAction_Select -> the `if(Items[item].Owner)` branch at admin_menu.sp:534 -> PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Materia is unavailbale") -> chat.sp:103 VFormat -> atcprintf case 't' -> Translate() -> phrase not found -> throw. Identical race on the by-target menu at admin_menu.sp:631-633 (owner changed between build and select).

**Доказательства.** addons/sourcemod/scripting/entWatch/admin_menu.sp:536 and :633 (the key); addons/sourcemod/translations/entWatch.phrases.txt:250-254 ("Item is unavailbale" - the key that DOES exist); entWatch.sp:59-60 (only common.phrases and entWatch.phrases are loaded). Native semantics, verified in the fork's source: C:/develop/sm1.13-botox/source/sourcemod/core/logic/sprintf.cpp:1229-1245 (case 't' -> Translate, `if (error) return 0;`), sprintf.cpp:98-116 (FindTranslation fails for client lang, then server lang, then English -> ThrowNativeErrorEx(SP_ERROR_PARAM, "Language phrase \"%s\" not found (arg %d)") at :109/:115), core/logic/smn_string.cpp:230-277 (sm_vformat calls atcprintf with no DetectExceptions guard, so the exception propagates and unwinds the plugin frame).

**Исправление.**

```
One-word fix at both sites - use the key that exists:

-  PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Materia is unavailbale");   // admin_menu.sp:536
+  PrintToChat2(client, "\x07%s%t", Colors[COLOR_OTHER], "Item is unavailbale");
-  PrintToChat2(client, "%t", "Materia is unavailbale");                              // admin_menu.sp:633
+  PrintToChat2(client, "%t", "Item is unavailbale");

(Or add a "Materia is unavailbale" block to entWatch.phrases.txt; renaming the call sites is the smaller change and keeps one key for one concept.)
```

### 104. empty.cfg is not shipped: "Save item" silently does nothing and leaks a KeyValues

- **id**: `emptycfg-not-shipped-save-is-noop` | **место**: `addons/sourcemod/scripting/entWatch/admin_menu.sp:1017` -> `AdminConfigSave()`
- **ось/инвариант**: reliability | **уверенность**: proven | **вердикт верификатора**: CRITIC

**Проблема.** AdminConfigSave() refuses to do anything unless it can ImportFromFile configs/entwatch/empty.cfg (admin_menu.sp:1013-1021). That file is not in the repository - git ls-files lists exactly one config asset, addons/sourcemod/configs/entwatch/colors.cfg - and it has never been committed (git log --all -- '*empty.cfg' is empty). So on a fresh deployment the entire persistence half of the live config editor is dead: ImportFromFile returns false, the function LogMessages and returns, the <map>.cfg is never written, the admin is bounced straight back to AdminMenu (admin_menu.sp:83-84) with no chat message and no menu-level indication, and the KeyValues created at admin_menu.sp:1015 is leaked on every press. This is what turns the already-reported admincfg-kv-leak from an edge case into the DEFAULT path. Note the asymmetry that makes this a packaging bug rather than server data: colors.cfg IS shipped and its absence is a SetFailState (colors.sp:21-24), so plugin-owned assets are expected in the repo; empty.cfg is likewise a plugin-owned KeyValues template, not per-server data like <map>.cfg. (The template is also functionally unnecessary - kv.JumpToKey(key, true) at admin_menu.sp:1039 creates the keys itself - so the file requirement could be dropped instead.)

**Триггер.** Any ADMFLAG_RCON/ROOT admin on a deployment installed from this repository: sm_eadmin -> the 'save' entry is offered to RCON|ROOT (admin_menu.sp:33-38) -> AdminMenu_Handler case 's' (admin_menu.sp:81-85) -> AdminConfigSave() -> BuildPath to <sm>/configs/entwatch/empty.cfg (admin_menu.sp:1013) -> kv.ImportFromFile returns false (admin_menu.sp:1017) -> LogMessage + return (admin_menu.sp:1019-1020), KeyValues from :1015 leaked, ExportToFile at :1028 never reached. The admin sees the main menu redisplay and believes his live edits were persisted; they are lost at the next map change (ConfigOnMapEnd -> ConfigClearAll, config.sp:206-221).

**Доказательства.** admin_menu.sp:1010-1030 (AdminConfigSave; the early return at :1019-1020 skips both delete kv and ExportToFile); `git ls-files` in the repo root returns only addons/sourcemod/configs/entwatch/colors.cfg under configs/; `git log --oneline --all -- "*empty.cfg"` returns nothing; colors.sp:19-24 (the shipped-asset precedent: colors.cfg absent => SetFailState); admin_menu.sp:1039 (JumpToKey with create=true, i.e. the template's keys are created anyway).

**Исправление.**

```
Two independent parts, both small. (1) Ship the asset: add addons/sourcemod/configs/entwatch/empty.cfg containing just `"entities"` followed by an empty brace block, so the save path works out of the box. (2) Make the failure visible and stop leaking, at admin_menu.sp:1017-1021 - add `delete kv;` before the `return;` in the ImportFromFile failure branch, and reply to the admin instead of only LogMessage. (That delete is the same one-line fix as admincfg-kv-leak - do not count it twice.) If the maintainer prefers, drop the template requirement entirely and start from `new KeyValues("entities")` with no import, since JumpToKey(create=true) builds every key.
```

### 105. Timer_ItemFindButton lacks TIMER_FLAG_NO_MAPCHANGE: item index carried into the next map

- **id**: `findbutton-timer-survives-mapchange` | **место**: `addons/sourcemod/scripting/entWatch/items.sp:245` -> `ItemProcessCheckButton()`
- **ось/инвариант**: invariant-I6 | **уверенность**: likely | **вердикт верификатора**: CRITIC

**Проблема.** CreateTimer(0.5, Timer_ItemFindButton, item) passes no flags (items.sp:245). SourceMod only kills timers that carry TIMER_FLAG_NO_MAPCHANGE at level shutdown - TimerSystem::RemoveMapChangeTimers pushes a timer onto the kill list only `if (pTimer->m_Flags & TIMER_FLAG_NO_MAPCHANGE)` (core/TimerSys.cpp:406-427) - so this one survives the map change and fires on the NEXT map, carrying a raw Items[] index that now addresses a completely different map's item table. This is a distinct path from the already-reported timer-findbutton-stale-item-index (which is about ItemRemove() shifting the array inside one round) and it has a different fix, so fixing that one does not close this one. Impact is bounded rather than catastrophic because the callback's own guards catch the common cases: `!Items[item].Weapon` catches a never-populated slot (globals start zeroed, and ItemsClear zeroed every slot it owned at items.sp:74-77) and `Items[item].Config == -1` catches a cleared slot (items.sp:250). What is NOT caught is the case where the new map has repopulated that index with a live, button-less item: the timer then runs a full 2048-entity scan (items.sp:259-283) and may bind a button to an item it was never created for, using the NEW map's Configs[Items[item].Config].Button_HammerId as the filter (items.sp:269).

**Триггер.** A ZE map that spawns an item weapon from a point_template late in the round (map logic, or an admin running sm_espawn - spawn.sp:73 AcceptEntityInput 'ForceSpawn') within 0.5 s of the level change: OnEntitySpawned (entWatch.sp:189-192) -> ItemsOnEntitySpawned -> ItemsInitiateItem (items.sp:229-238) -> ItemsRegisterItemEntity REGISTER_WEAPON -> ItemProcessCheckButton(id) (items.sp:169) -> CreateTimer(0.5, ...) at items.sp:245. mp_timelimit expires / the map vote completes before the timer elapses; LevelShutdown runs RemoveMapChangeTimers, which leaves this timer alive (TimerSys.cpp:414). On the new map OnMapStart -> ItemsOnMapStart -> ItemsOnRoundStart repopulates Items[] (items.sp:22-31); the timer then fires against Items[<old index>] of the new map.

**Доказательства.** items.sp:240-246 (ItemProcessCheckButton / CreateTimer with no flags - compare hud.sp:41, which correctly passes TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); items.sp:248-291 (Timer_ItemFindButton and its four guards at :250); items.sp:69-79 (ItemsClear leaves Config == -1 on the slots it owned, which is what makes the guard usually hold). Native semantics verified in source: C:/develop/sm-1.13/include/timers.inc:41 `#define TIMER_FLAG_NO_MAPCHANGE (1<<1) /**< Timer will not carry over mapchanges */`; C:/develop/sm1.13-botox/source/sourcemod/core/TimerSys.cpp:406-427 (RemoveMapChangeTimers kills ONLY flagged timers); C:/develop/sm1.13-botox/source/sourcemod/core/sourcemod.cpp:466-470 (OnMapEnd executes, then RemoveMapChangeTimers).

**Исправление.**

```
One line, and it is the correct fix independently of the index-stability work:

-    CreateTimer(0.5, Timer_ItemFindButton, item);
+    CreateTimer(0.5, Timer_ItemFindButton, item, TIMER_FLAG_NO_MAPCHANGE);

If the item-index instability is fixed instead by passing an entity reference (EntIndexToEntRef of the weapon) and re-resolving the item in the callback, add this flag anyway - a timer whose only purpose is to finish binding THIS map's entities has no business outliving the map.
```

### 106. The HALFZOMBIE-off build is not warning-free: the module self-gate emits #warning

- **id**: `halfzombie-gate-off-emits-warning` | **место**: `addons/sourcemod/scripting/entWatch/halfzombie.sp:2` -> `(file scope)()`
- **ось/инвариант**: correctness | **уверенность**: proven | **вердикт верификатора**: CRITIC

**Проблема.** CLAUDE.md's Build section states the feature gates 'exist so subsystems *can* be switched off. When touching a gated module, keep both builds (gate on and off) compiling warning-free.' halfzombie.sp is the only one of the four gated modules whose self-gate is noisy: it emits `#warning "Halfzombie module: not included"` before #endinput, so the HALFZOMBIE-off build always carries a compiler warning, while hud.sp:1-3, assist_use.sp:14-16 and admin_menu.sp:1-3 gate silently. Reporting this because the gate-off builds are a modality no auditor exercised, and this is the only artefact my sweep turned up in that build - everything else is clean (see the clean entries: every gated symbol's external use sites are properly #if defined-guarded, and public-function arguments never trigger warning 203/204, so the empty-bodied forwards are fine). It may well be deliberate as an installation reminder; if so, the rule in CLAUDE.md is what should change, not the code.

**Триггер.** Maintainer comments out `#define HALFZOMBIE` at entWatch.sp:15 (the documented way to switch the subsystem off) and compiles with `spcomp -i"addons/sourcemod/scripting/include" addons/sourcemod/scripting/entWatch.sp`: entWatch.sp:26 includes entWatch/halfzombie.sp -> halfzombie.sp:1 `#if !defined HALFZOMBIE` is true -> halfzombie.sp:2 `#warning` fires -> spcomp reports a user warning and the build is no longer warning-free.

**Доказательства.** addons/sourcemod/scripting/entWatch/halfzombie.sp:1-4 (the noisy gate); contrast addons/sourcemod/scripting/entWatch/hud.sp:1-3, assist_use.sp:14-16, admin_menu.sp:1-3 (silent `#if !defined X / #endinput / #endif`); entWatch.sp:15 (the gate) and entWatch.sp:26 (the include); CLAUDE.md 'Build' section, last paragraph. Note this is separate from the already-reported halfzombie-tryinclude-does-not-compile, which is the opposite build (HALFZOMBIE ON without zombiereloaded.inc): halfzombie.sp:38-69 puts HalfZombieDeterminate/HalfZombieDeterminateClient inside `#if defined _zr_included` while entWatch.sp:128-130 calls HalfZombieDeterminate() under `#if defined HALFZOMBIE` - that one is a hard compile error, this one is only a warning.

**Исправление.**

```
Drop the directive, matching the other three modules - delete line 2 of halfzombie.sp so the gate reads `#if !defined HALFZOMBIE` / `#endinput` / `#endif`. Or, if the reminder is wanted, keep it and relax CLAUDE.md's 'warning-free' condition to name this one expected warning - but do not leave the code and the documented condition contradicting each other.
```

### 107. The use path calls out to third-party plugins and then keeps using the raw item index

- **id**: `api-forward-before-index-reuse` | **место**: `addons/sourcemod/scripting/entWatch/sdkhook.sp:79` -> `OnButtonPress / Compare_OnEqualTo / Relay_OnTrigger()`
- **ось/инвариант**: invariant-I6 | **уверенность**: hypothesis | **вердикт верификатора**: CRITIC

**Проблема.** All three use paths hand control to arbitrary consumer plugins and then continue to dereference the same raw Items[] index: OnButtonPress does APIOnClientItemUse(activator, item) (sdkhook.sp:79) and only afterwards ItemReload(item) (:81) and PrintToChatItemAction(item, ACTION_USE) (:82); Compare_OnEqualTo (:96-99) and Relay_OnTrigger (:112-115) have the identical shape. CLAUDE.md states plainly that 'Indices are not stable... item indices are handed to timers, menu item data and API forwards', but the forward is dispatched BEFORE the plugin has finished using the index, which is the one ordering that makes the instability the plugin's own problem rather than the consumer's. Anything a consumer does inside entWatch_OnClientItemUse that ends the round synchronously reduces Items_Count and sets Items[item].Config to -1 while entWatch's own frame is still holding `item`; ItemReload then evaluates Configs[Items[item].Config].Mode with Config == -1 (items.sp:506) and PrintToChatItemAction evaluates ConfigGetDisplay(-1, ...) (chat.sp:19-49 -> config.sp:305), both of which are Configs[-1] and raise an array-bounds error. I am explicit that this is a HYPOTHESIS: I could not name a consumer plugin on this server that does it, and the obvious synchronous candidate is CS_TerminateRound (round_end is dispatched inline by IGameEventManager2::FireEvent, and entWatch.sp:83 hooks round_end PostNoCopy -> OnRoundEnd -> ItemsOnRoundEnd -> ItemsClear, items.sp:33-37/69-79); entity removal is NOT a candidate because UTIL_Remove defers deletion to the end of the frame. Per this project's own bar, an unproven trigger stays in the report and does not become a code change. I raise it because it is exactly the class a per-module auditor cannot see: the api.sp auditor checked the forward's signature and push order and declared it clean, the sdkhook.sp auditor checked I1/I7 on the same lines and declared them clean, and neither owns the boundary.

**Триггер.** Hypothetical, stated concretely so it can be tested: a consumer plugin registers entWatch_OnClientItemUse (entWatch.inc:50) and, on a specific item, calls CS_TerminateRound(0.0, CSRoundEnd_CTWin, false) - a plausible 'this item wins the round' integration on a ZE map. Owner presses E -> SDKHook_Use -> OnButtonPress (sdkhook.sp:51) passes the ownership, restrict and readiness gates -> sdkhook.sp:79 APIOnClientItemUse -> api.sp:47-53 Call_Finish dispatches into the consumer -> CS_TerminateRound fires round_end inline -> entWatch.sp:182-186 OnRoundEnd -> ItemsOnRoundEnd -> ItemsClear (items.sp:69-79) sets every slot's Config to -1 and Items_Count to 0 -> the consumer returns -> sdkhook.sp:81 ItemReload(item) -> items.sp:506 Configs[Items[item].Config].Mode with Config == -1.

**Доказательства.** sdkhook.sp:79-82 (forward, then ItemReload, then announce), sdkhook.sp:96-99, sdkhook.sp:112-115 (same shape); api.sp:47-53 (APIOnClientItemUse -> Call_Finish, a synchronous dispatch); items.sp:69-79 (ItemsClear zeroes Items_Count and sets Config = -1 on every slot); items.sp:506 and config.sp:303-306 (the two unguarded Configs[Items[item].Config] dereferences that follow the forward); entWatch.sp:83 and :182-186 (round_end -> ItemsOnRoundEnd); CLAUDE.md 'Data model'. NOT VERIFIED by me: that any deployed consumer does this, and that CS_TerminateRound dispatches round_end inline on this fork - I did not read cs_gamerules for it.

**Исправление.**

```
Cheap and behaviour-preserving: do entWatch's own bookkeeping first and notify last, in all three callbacks - move the APIOnClientItemUse(activator, item) call from before ItemReload/PrintToChatItemAction to after them, at sdkhook.sp:79-82, :96-99 and :112-115. This is a reordering, not a guard, so it does not fall foul of the 'armouring correct code' rule - but per the audit/fix split it must not be applied on a hypothesis alone. The decision it needs from the maintainer is a contract one: does a consumer of entWatch_OnClientItemUse observe the use BEFORE or AFTER the cooldown is charged? Today it is before; the fix makes it after.
```

---

## Заявлено «проверено, чисто» (100 пунктов)

- **[items-lifecycle] api-use (enum struct parameter aliasing)** — ItemsRegisterItemEntity(int id, Item item, ...) mutates the caller's slot: enum-struct parameters are passed by reference (non-const), and all three call sites pass a matching pair - items.sp:102 (i, Items[i]), items.sp:236 (item, Items[item]), items.sp:288 (item, Items[item]) - so `id` and `item` never diverge and ItemProcessCheckButton(id) reads the same slot the callee just wrote (items.sp:168-169). Caveat: I found no enum-struct *parameter* in C:/develop/sm-1.13/include to cite for the language rule; it is established here by the plugin's production dependence on the mutation (a button found by Timer_ItemFindButton is only ever recorded through it).
- **[items-lifecycle] entities (hook lifetime vs entity destruction)** — The missing SDKUnhook in the Trigger branch of ItemsOnEntityDestroyed (items.sp:316-320) and the missing UnhookSingleEntityOutput in the Compare/Relay branches (items.sp:329-340) are not leaks: SDKHooks calls Unhook(pEntity) right after firing the OnEntityDestroyed forward (extensions/sdkhooks/extension.cpp:1915-1933), and stale entity-output hooks are dropped as soon as the index is reused with a different reference (extensions/sdktools/output.cpp:158-167).
- **[items-lifecycle] entities (raw indices vs refs / index reuse)** — Item.Weapon/Trigger/Button/Compare/Relay are raw indices (Item.inc:11-16) but every stored index is cleared when its entity dies - ItemsOnEntityDestroyed handles all five roles (items.sp:304-342) and removes the whole item when the weapon dies - so a reused index cannot be mistaken for a live binding. Entity 0 is never confusable with the 0 = 'none' sentinel: ItemsOnEntitySpawned rejects hammerid 0 (items.sp:88-89) and every ItemsGetBy* caller passes a real entity index (sdkhook.sp:4, 25, 38, 59, 91, 107; assist_use.sp:256 filters target <= MaxClients first).
- **[items-lifecycle] api-use (INVALID_ENT_REFERENCE comparison)** — items.sp:160/177/192 compare GetEntPropEnt() against INVALID_ENT_REFERENCE. GetEntPropEnt returns -1 when there is no entity (C:/develop/sm-1.13/include/entity.inc:618-620) and INVALID_ENT_REFERENCE is 0xFFFFFFFF (halflife.inc:116), i.e. the same cell - the tests are correct.
- **[items-lifecycle] invariant-I4 (one time base, conservative boundaries)** — All item timing reads GetGameTime(): items.sp:449 (ItemIsReady), 493 (ItemReload), 541 (ItemFormat). No GetEngineTime/GetTime mixing anywhere in items.sp. Boundaries block rather than allow: Wait uses >= (items.sp:451) and cooldowns require strict Cooldown < time (items.sp:465, 475, 480), and ItemReload pads with GetTickInterval()*5.0 before storing (items.sp:496) - entWatch's readiness stays behind the map's, except where broken by the duplicate-hook finding.
- **[items-lifecycle] invariant-I5 (knife/none items never moved)** — ItemDrop refuses SLOT_NONE and SLOT_KNIFE before touching the weapon (items.sp:436-437), matching TransferIsValidItem (transfer.sp:52-53); the only other mover, TransferItem, goes through ItemDrop (transfer.sp:66).
- **[items-lifecycle] invariant-I1 (alternate use paths keep the ownership guard)** — The assist_use path does not bypass OnButtonPress: it fires AcceptEntityInput(Button, "Use", Owner, Owner) (assist_use.sp:209/215/228), which runs CBaseEntity::Use and therefore the SDKHook_Use callback, so Items[item].Owner != activator (sdkhook.sp:64) still applies. items.sp itself exposes no path that activates an item.
- **[items-lifecycle] invariant-I7 (compare/relay never double-counted by re-registration)** — Even though ItemsClear() re-registers compare/relay entities without unhooking, HookSingleEntityOutput refuses an identical (function, entity_ref) hook and returns 0 (extensions/sdktools/outputnatives.cpp:65-82), so Compare_OnEqualTo/Relay_OnTrigger cannot fire twice from duplicate registration - only SDKHook-based hooks stack.
- **[items-lifecycle] handles** — items.sp allocates no KeyValues/Menu/DBResultSet/DataPack/ArrayList/File. Its single handle-producing call is CreateTimer(0.5, Timer_ItemFindButton, item) (items.sp:245); the handle is not stored and the callback returns Plugin_Continue on a non-repeating timer, which SourceMod closes automatically. No early return in items.sp skips a delete.
- **[items-lifecycle] async (threaded SQL / userid handling)** — items.sp contains no database or client-resolving async work; its only deferred callback is Timer_ItemFindButton, which carries an item index (reported separately as timer-findbutton-stale-item-index), not a client index.
- **[items-lifecycle] correctness (MAX_ITEMS bound and Items_Count arithmetic)** — ItemsInitiateItem refuses to exceed the array (items.sp:231-232), ItemRemove is the only decrement (items.sp:612), ItemsClear resets to 0 (items.sp:78), and every consumer loops i < Items_Count (items.sp:41, 74, 97, 306, 347, 359, 370, 381, 392, 403, 414, 425). The only arithmetic defect is the off-by-one read reported as itemremove-reads-past-live-range.
- **[items-lifecycle] correctness (Timer_ItemFindButton scan bounds)** — The hardcoded `i < 2048` (items.sp:259) equals MAX_EDICTS on CS:S, and CS:S has no non-edict entities, so it covers exactly the range GetMaxEntities() would return; the loop starts at MaxClients+1 and skips invalid indices (items.sp:259-262). Not a defect on the target engine.
- **[items-lifecycle] invariant-I3 (filter written before the press is allowed through)** — OnButtonPress writes Configs[].Filter into the owner's targetname (sdkhook.sp:73-74) after the ownership/restrict/readiness checks and before returning Plugin_Continue (sdkhook.sp:77/83), and items.sp never resets targetname or classname anywhere - the map-side legacy protection ordering is intact.
- **[items-lifecycle] late load** — OnPluginStart iterates 1..MaxClients and replays OnClientPutInServer for connected players (entWatch.sp:95-101). The Late flag is set in AskPluginLoad2 (entWatch.sp:49) and cleared at the end of OnMapStart (entWatch.sp:123), i.e. after ItemsOnMapStart has run, so ItemsRegisterItemEntity's adoption branch (items.sp:160-166) sees Late == true during the late-load rescan; the adopted m_hOwnerEntity is a player index because a dropped weapon clears it (basecombatweapon_shared.cpp:716-717) and Equip sets it to the carrier (:987).
- **[gameplay-hooks] invariant-I1 (ownership guard on the forced-press route)** — The assist and admin routes do NOT bypass the guard. AssistUseInputByName passes Items[item].Owner as both activator and caller (assist_use.sp:209,215,228); AcceptEntityInput("Use") reaches CBaseEntity::InputUse which calls the virtual Use() (hl2_src-leak-2017 baseentity.cpp:1906 DEFINE_INPUTFUNC("Use", InputUse), :4009-4012), and SDKHook_Use is a vtable hook on that virtual (sm-1.13/include/sdkhooks.inc:327), so OnButtonPress runs with activator == Owner and the `Items[item].Owner != activator` test at sdkhook.sp:64 always holds. There is no path in assist_use.sp that can present a non-owner as activator.
- **[gameplay-hooks] invariant-I3 (map-side filter ordering)** — sdkhook.sp:73-74 writes Configs[].Filter into the owner's targetname after all rejection tests and before BOTH Plugin_Continue exits (the Compare/Relay early return at :76-77 and the normal exit at :83), and never resets it. Blocked presses (:65,:68,:71) return before the write, which is correct since the button never fires.
- **[gameplay-hooks] invariant-I7 (press vs entity-output accounting)** — sdkhook.sp:70 skips the readiness test and sdkhook.sp:76-77 returns Plugin_Continue before APIOnClientItemUse/ItemReload/PrintToChatItemAction whenever Items[item].Compare or .Relay is set, so a press is never counted on the button path for such items; the count comes solely from Compare_OnEqualTo/Relay_OnTrigger (sdkhook.sp:96-99,112-115). No path counts both. (The one residual risk - an item configured with both compareid and relayid - is filed separately.)
- **[gameplay-hooks] invariant-I8 (hook symmetry across round_start/round_end/map change)** — The missing ItemUnhook in ItemsClear (items.sp:69-79, called from ItemsOnRoundEnd) does NOT produce duplicate callbacks: SDKHooks removes every pawn hook for an entity when it is deleted (sm1.13-botox extensions/sdkhooks/extension.cpp:1932 `Unhook(pEntity)` inside HandleEntityDeleted), and CS:S destroys and recreates all non-preserved map entities on every round restart (hl2_src-leak-2017 cs_gamerules.cpp:4554-4596; s_PreserveEnts at :257-297 contains none of func_button/func_rot_button/trigger_*/logic_relay/logic_compare/func_door), with round_start fired only after CleanUpMap (cs_gamerules.cpp:2740 vs :2806). Entity-output hooks are additionally deduped at registration (outputnatives.cpp:75-82) and killed on index reuse before firing (output.cpp:156-167). So a second SDKHook_Use / HookSingleEntityOutput on the same surviving entity cannot double-fire OnButtonPress, OnTriggerTouch, Compare_OnEqualTo or Relay_OnTrigger.
- **[gameplay-hooks] handles** — None of the three files creates a Handle: no KeyValues/Menu/DataPack/ArrayList/File/DBResultSet/Timer is opened. AssistUseConfigLoad (assist_use.sp:101-104) only reads from a KeyValues owned and deleted by config.sp:61-75. TR_TraceRayFilter (assist_use.sp:252) uses the global trace result, not TR_TraceRayFilterEx, so there is no trace handle to close (sm-1.13/include/sdktools_trace.inc:370-376 vs :496 which returns a Handle). Nothing to leak or double-free.
- **[gameplay-hooks] async** — No threaded SQL, timers or RequestFrame callbacks exist in sdkhook.sp, assist_use.sp or halfzombie.sp, so the store-userid-not-index rule has no application here; all client indices used are the ones the forward/hook itself delivered in the same frame.
- **[gameplay-hooks] entities (validity before native calls)** — AssistUseInputByName gates every AcceptEntityInput behind `if(!GetEntityClassname(Items[item].Button, ...)) return false;` (assist_use.sp:204-205), which fails for a stale index, so the @error path of AcceptEntityInput (sm-1.13/include/sdktools_entinput.inc:49-51) is not reachable there; ItemsOnEntityDestroyed zeroes Items[].Button when the button dies (items.sp:321-328) and Items[item].Button==0 is tested first (assist_use.sp:80,194). AssistUseIsValidTarget tests `target <= MaxClients || !IsValidEntity(target)` before touching the entity (assist_use.sp:256), and TR_GetEntityIndex()'s -1 (no hit) is absorbed by that same test.
- **[gameplay-hooks] api-use (datamap properties actually exist)** — GetEntPropEnt(caller, Prop_Data, "m_hActivator") is valid for all four hooked classes: func_door/func_door_rotating derive from CBaseToggle whose datadesc declares it (hl2_src-leak-2017 subs.cpp:146), and CBasePropDoor (prop_door_rotating) declares its own (props.cpp:3538-3542). The spawnflag constant used in AssistUseIsValidTarget is also correct: doors.h:30 `#define SF_DOOR_PUSE 256 // door can be opened by player's use button` matches the comment at assist_use.sp:271. ZR_GetClassDisplayName(zombieClass, ..., 1) passes a class index with ZR_CLASS_CACHE_MODIFIED, the cache that expects a class index (zr/class.zr.inc:31-33,131-141) - not the player cache - so that call is used correctly.
- **[gameplay-hooks] entities (fixed per-client arrays and bounds)** — PressButtonTime/AssistUseTime/prevButtons (assist_use.sp:22-23,148) and HalfZombie (halfzombie.sp:11) are all [MAXPLAYERS + 1]. Every write is bounds-safe: the output callbacks clamp with `client <= 0 || client > MaxClients` (assist_use.sp:113,126) and `activator < 0 || activator > MaxClients` (assist_use.sp:134 - activator 0 writes the unused slot 0, which is in range), HalfZombieInit iterates 1..MaxClients (halfzombie.sp:15), and sdkhook.sp bounds activator with `activator <= 0 || activator > MaxClients` before indexing (sdkhook.sp:56,88,104,123). No negative or MAXPLAYERS+1 index exists on these arrays.
- **[gameplay-hooks] invariant-I6 (item index stability)** — Neither sdkhook.sp nor assist_use.sp stores an item index across a frame boundary: OnButtonPress/OnTriggerTouch/Compare_OnEqualTo/Relay_OnTrigger resolve the index from the entity on every call (sdkhook.sp:59,91,107), AssistUseOnPlayerRunCmdPost re-resolves it every tick (assist_use.sp:184), and Command_Use resolves and consumes it synchronously (assist_use.sp:62-74). No timer, DataPack or menu item data in these files carries an index, so ItemRemove()'s array shifting cannot alias them.
- **[gameplay-hooks] invariant-I2 (pickup and trigger routes)** — Both non-button routes enforce the full set: OnWeaponTouch tests RestrictClientHasRestrict and HalfZombie before returning Plugin_Continue (sdkhook.sp:12-20), and OnTriggerTouch tests the same pair on StartTouch/EndTouch/Touch (sdkhook.sp:126-134, hooks installed at items.sp:198-200). SDKHook_WeaponCanUse returning Plugin_Handled is the documented way to refuse a pickup (sm-1.13/include/sdkhooks.inc:212,264). Only the button route is missing the half-zombie half of the rule, filed as a separate finding.
- **[gameplay-hooks] correctness (assist multi-item and E-edge handling)** — The documented multi-item requirement is met: AssistUseGetClientItemsCount counts every item owned by the client that has a button and bails unless the count is exactly 1 (assist_use.sp:176-182,298-309), so a player carrying weapon_deagle + weapon_mp5 gets no forced press. The press is edge-triggered rather than per-tick (assist_use.sp:148-153) and rate-limited to one attempt per ASSIST_USE_CD (assist_use.sp:160-168), and the only per-tick work on the non-pressing path is two integer tests, so there is no per-tick trace or entity scan.
- **[config-colors] handles** — colors.sp: the KeyValues opened at colors.sp:18 is deleted at colors.sp:31 on the only path that continues (the failure path at colors.sp:21-24 calls SetFailState, which evicts the plugin — smn_core.cpp:550-580 EvictWithError + ReportFatalError — so its handles are released with the plugin). ColorsMap is deleted before every re-creation (colors.sp:59-60) and `delete` on null is safe, so InitColorsMap cannot double-free or leak on a reload. config.sp holds no other Handle-owning object: no Menu, DataPack, ArrayList, File or DBResultSet anywhere in the file (the single KeyValues leak is reported separately).
- **[config-colors] async** — Neither config.sp nor colors.sp creates a timer, a threaded query, a frame callback or any other deferred callback — the only CreateTimer touching config data lives in items.sp:245. There is therefore no client-index-versus-userid hazard and no callback that can outlive a slot in this scope; ConfigOnMapStart (config.sp:35) and ColorsInit (entWatch.sp:73) both run synchronously inside their forwards.
- **[config-colors] entities** — No entity is created, looked up, hooked or referenced in scope: config.sp only stores raw Hammer IDs as integers (config.sp:137-143, 181-187), and Hammer IDs are map-authored constants, not entity indices, so the EntIndexToEntRef/index-reuse hazard does not apply. The entity side of the binding is entirely in items.sp (items.sp:109-146).
- **[config-colors] database** — No SQL, no Database object and no external/untrusted string reaches a query from this scope; the only external input consumed here is KeyValues file content and the command argument passed to ConfigGetByShortName (config.sp:246), which is only ever used with strncmp, never as a format string or a query fragment.
- **[config-colors] invariant-I6** — config.sp never stores a config index across frames: ConfigBrowseKeyGFL/UNLOZE use `int config = Configs_Count;` only within the same call (config.sp:122-123, 167-168), and all four lookups return -1 rather than a stale index on failure (config.sp:231, 243, 255, 272). The copy-in/copy-out idiom itself is sound — ConfigInit clears Configs[Configs_Count] and sets Type before `Config c; c = Configs[Configs_Count];` copies it (config.sp:122-124), nothing writes Configs[Configs_Count] between the copy and `Configs[Configs_Count++] = c;` (config.sp:162), so no field is lost or clobbered; c.Display starts at 0 from ConfigClear (config.sp:292), which is what the |= at config.sp:145-147 relies on.
- **[config-colors] invariant-I9** — The Config struct is copied out wholesale by Native_GetConfig with a runtime sizeof gate (api.sp:96-108). The one-byte overrun reported in config-color-getstring-oob lands on Config.Filter[0] — inside the same struct instance (Config.inc:21 then :23) — so it can never spill into Configs[config+1] and no neighbouring config's data can leak through the API. Config.inc declares no field whose size disagrees with the sizes passed by the parser other than Color (Name[64]/ShortName[32]/Filter[64]/Template[64] are all read with their own sizeof at config.sp:126-135 and 171-179).
- **[config-colors] invariant-I3** — The map-side legacy filter survives parsing intact: `filtername` (GFL, config.sp:135) and `filter` (UNLOZE, config.sp:179) are both read into c.Filter with the correct sizeof(c.Filter) == 64, matching char Filter[64] (Config.inc:23), and the value is written to the owner's targetname only in sdkhook.sp:73-74 before the press is let through. config.sp neither resets nor rewrites Filter after parsing, which is the documented intent.
- **[config-colors] security** — No format-string injection surface: every config-supplied string is passed as a %s/%i argument, never as the format parameter (chat.sp:68, transfer.sp:71/77, spawn.sp:76, admin_menu.sp:856-870 all use literal formats). Map name handling is bounded — GetCurrentMap into char map[64] (config.sp:39-40; halflife.inc:251 documents maxlength) then BuildPath into char[PLATFORM_MAX_PATH] with the map name as a %s argument (config.sp:47-48); the map name comes from the engine, not from a client, so there is no traversal vector, and truncation would only mean 'config not found' for a hypothetical 64+ character map name.
- **[config-colors] correctness** — colors.sp colour table verified mechanically: all 173 ColorsMap.SetString entries have a value matching "#RRGGBB" and there are no duplicate keys, so no entry silently shadows another. ColorNameToColorCode's index arithmetic is safe on every path — symbol/symbol2 come from FindCharInString (string.inc:472, which returns an index < strlen or -1), the guard at colors.sp:41 rejects -1, symbol2 < 3 and symbol2 <= symbol, so `color[symbol2] = 0` (colors.sp:44) and `color[symbol + 1]` (colors.sp:47) are always inside the string, and both result paths (colors.sp:49 strcopy, colors.sp:53 FormatEx) respect the caller's `size`. Also checked and clean: `#define DISPLAY_DEFAULT DISPLAY_CHAT|DISPLAY_USE|DISPLAY_HUD` is unparenthesised but its single use is as a call argument (config.sp:189), where `|` binds tighter than the argument separator, so no precedence hazard exists today. Initialisation order is correct — ColorsInit runs in OnPluginStart (entWatch.sp:73) before ConfigOnMapStart in OnMapStart (entWatch.sp:112), so ConfigClear never reads an unpopulated Colors[COLOR_ITEM], and HudConfigLoad/AssistUseConfigLoad (config.sp:66-72) read root-level keys without moving the KeyValues cursor, so ConfigBrowse's GotoFirstSubKey (config.sp:82) still starts at the root.
- **[restrict-db] async — userid vs client index across the query boundary** — Every deferred payload stores a userid, never a raw index: restrict.sp:180 `DB_Query(SQL_Callback_SelectSummBans, GetClientUserId(client), ...)`, :275, :373, :479, :613 `pack.WriteCell(GetClientUserId(...))`, and each callback re-resolves with GetClientOfUserId (:191, :291, :387, :504, :633). The one raw index kept across the boundary (`console`, restrict.sp:276/374/478/612) is only ever tested for zero-ness (:306, :396, :516, :640), never used to index an array or call a client native unguarded. The resolution itself is correct; the defect is that two call sites forget to test the resolved value (see finding eban-callback-isclientingame-zero).
- **[restrict-db] handles — DataPack lifetime on all paths including error paths** — Every SQL callback reads the pack fully and deletes it before any branch that can return: restrict.sp:300 (`delete pack;` at the top of SQL_Callback_BanClient, before the error return at :313), :392 (SQL_Callback_UnBan, before :402), :510 (SQL_Callback_AddBan, before :522), :636 (SQL_Callback_DeleteBanClient, before :646). No early return skips a delete and no pack is double-freed.
- **[restrict-db] handles — threaded DBResultSet lifetime** — None of the threaded callbacks delete `results` (restrict.sp:183-203, :287-335, :382-414, :491-539, :620-662; database.sp:95-114, :116-123), which is correct: C:/develop/sm-1.13/include/dbi.inc:408-409 — "The result handle returned through the callback is temporary and destroyed at the end of the callback." The leaks reported separately are only on the synchronous SQL_Query path (dbi.inc:707-710), which has the opposite contract.
- **[restrict-db] entities — entity indices / EntIndexToEntRef** — Neither file touches an entity: restrict.sp and database.sp contain no GetEntProp/IsValidEntity/SDKHook/entity-index call of any kind (the only handle types used are Database, DBResultSet and DataPack). Invariants I1, I5, I7 and I8 are structurally out of reach of this scope.
- **[restrict-db] entities/arrays — per-client array bounds and reset** — `Restrict Restricts[MAXPLAYERS + 1];` (restrict.sp:26) is iterated 1..MaxClients at restrict.sp:207-220, cleared on disconnect at restrict.sp:223-226 via OnClientDisconnect (client.sp:98) — which also covers the map-change fake disconnect, so no state survives a map change into a reused slot. Every index reaching Restricts[] is either a validated client (restrict.sp:64, 242, 349, 528, 652 all guarded by `client > 0` / IsClientInGame / FindTarget > 0) or the in-bounds 0 slot (restrict.sp:481 with admin == 0). No negative index and no MAXPLAYERS+1 overrun exists in either file.
- **[restrict-db] security — admin flags match the documented access table** — restrict.sp:30-35: sm_status is RegConsoleCmd (all), sm_eban/sm_uneban are ADMFLAG_GENERIC, sm_addeban/sm_deleban are ADMFLAG_RCON — exactly the CLAUDE.md "Commands" table. sm_uneban additionally enforces "only the issuing admin, or RCON/ROOT" at restrict.sp:354-358.
- **[restrict-db] api-use — command argument-count validation and target processing** — Every handler checks its arity before touching arguments and replies with a syntax line otherwise: restrict.sp:87-89 (sm_eban, `args != 2`), :110-112 (sm_uneban, `args != 1`), :132-134 (sm_addeban, `args < 2`), :152-154 (sm_deleban, `args < 1`), :43 (sm_status, optional arg). Target resolution goes through FindTarget/ProcessTargetString (restrict.sp:46, 96, 119), not a manual name loop, and results are checked `> 0` before use — helpers.inc:163-188 confirms FindTarget returns -1 on error and replies to the client itself.
- **[restrict-db] security — SQL injection on the player-driven paths** — Nothing a non-admin player controls reaches a query unescaped. The values interpolated on the auth/ban paths are machine-generated: Clients[].Account from GetSteamAccountID (client.sp:47), the ip from GetClientIP (restrict.sp:177, 267, 368), and GetTime()/int durations. The only free-text values on those paths — the two player names in INSERT_BAN — are escaped through Database.Escape into MAX_NAME_LENGTH*2+1 buffers (restrict.sp:265, 271-272), which satisfies the size contract in dbi.inc:384-386 ("The buffer must be at least 2*strlen(string)+1") since a CS:S name cannot exceed the 64-byte source buffer. The unescaped values reported separately (restrict.sp:486) are ADMFLAG_RCON-only inputs.
- **[restrict-db] invariant-I2 — restricted player cannot obtain or fire an item by any route** — restrict.sp exposes a single authoritative predicate, RestrictClientHasRestrict (restrict.sp:664-667), and every documented route consults it: pickup sdkhook.sp:12, button press sdkhook.sp:67, trigger touch sdkhook.sp:126, assisted use assist_use.sp:155, transfer receiver transfer.sp:17, admin menu targets admin_menu.sp:115/154/220/399/448/527/625. Pickup additionally requires Clients[].Authorized (sdkhook.sp:9), so an unresolved auth cannot be exploited to grab an item. No route in scope bypasses the predicate.
- **[restrict-db] invariant-I6 — no item/config index is stored across frames** — restrict.sp and database.sp store no Items[]/Configs[] index anywhere: neither file references Items, Configs, Items_Count or Configs_Count (verified by grep across the scripting tree). The only cross-frame payloads are DataPacks holding userids, account ids and durations (restrict.sp:274-283, 372-377, 473-483, 607-614), all of which are stable identifiers.
- **[restrict-db] database — schema creation idempotence and column-index mapping** — Both DDL statements use CREATE TABLE IF NOT EXISTS (database.sp:64, :80), so a re-connect or plugin reload cannot fail on an existing table, and the failure of the whole statement is reported once at database.sp:97-101. The positional reads in RestrictCacheClientBan (restrict.sp:168-170: FetchInt(3)=aid, FetchInt(5)=duration, FetchInt(6)=expires) match the declared column order pid,pname,pip,aid,aname,duration,expires (database.sp:65-71 / :81-88) for the `SELECT *` in client.sp:1 — correct today, though it is a hidden coupling to the column order that the planned schema redesign must preserve or eliminate.
- **[restrict-db] reliability — DB_Query null-database guard** — database.sp:7-13 DB_Query dereferences DB without a null check, but no reachable caller can hit it with a null handle: RestrictClientBan/UnBan guard `DB == null` (restrict.sp:232, 339), RestrictAddBan/DeleteBan guard `!DBLoaded` (:418, :543) which is only ever set after DB is assigned (database.sp:36 then :103), ClientAuth guards `DB == null` (client.sp:43), and RestrictLoadClientSummBans (:173) runs only from inside a successful query callback. Reported as clean rather than as a missing defensive check, per the project rule on armouring correct code.
- **[restrict-db] strings — query buffer sizing and translation format arity** — DB_Query sizes its scratch buffer as `strlen(format_query) + 512` (database.sp:9-11) and VFormat truncates safely; the largest query, INSERT_BAN (~128 chars), substitutes at most 2x126 escaped name bytes + 15 ip bytes + ~40 digits, well under the 640-byte allocation — no truncation and no overflow. Translation arity also checks out against translations/entWatch.phrases.txt: "You have restrict" declares {1:s} and gets buffer2 with the trailing %s taking buffer (restrict.sp:70); "You have not restrict"/"You were not logged in to the database" declare no #format and the %s takes buffer (:74, :79); "Ban success"/"Add ban success" declare three {n:s} and receive exactly three (:324, :536).
- **[client-api-mediator] handles** — No Handle is created or leaked in scope. entWatch.sp/client.sp/api.sp allocate no KeyValues, Menu, DataPack, ArrayList or File. The only handle-shaped object is the threaded DBResultSet in SQL_Callback_SelectBans (client.sp:55), which SourceMod owns and destroys after the callback returns (dbi.inc:408 'The result handle returned through the callback is temporary and destroyed...'), so the absence of a delete is correct. The six GlobalForwards created in APIInit (api.sp:10-15) are framework-owned and are correctly NOT deleted in OnPluginEnd (entWatch.sp:104-108).
- **[client-api-mediator] async** — The one async callback in scope stores a userid, not a client index, and resolves and validates it before use: client.sp:52 passes GetClientUserId(client) as the query data, client.sp:63-66 does GetClientOfUserId + `if(client == 0) return`. GetClientOfUserId is documented to return 0 for a stale userid (clients.inc:787). The slot cannot go from in-game to a different player between issuing and completing the query without a disconnect, which would invalidate the userid.
- **[client-api-mediator] database** — No injection surface in scope. SELECT_BANS (client.sp:1) interpolates only an integer account id and an engine-supplied IP string obtained from GetClientIP (client.sp:46-52) - no player-controlled text reaches the query, so the missing SQL_Escape is not exploitable here. The query is threaded via DB_Query -> DB.Query (database.sp:12); there is no blocking SQL_Query or SQL_LockDatabase anywhere in client.sp, api.sp or entWatch.sp (the blocking pair lives in restrict.sp:456-458 and :578-580, outside this scope).
- **[client-api-mediator] entities** — Scope files hold no entity indices across frames. entWatch.sp:189-210 forwards entity indices straight through to items.sp within the same call, and the OnEntitySpawned signature matches the fork's declaration exactly (sdkhooks.inc:357 `forward void OnEntitySpawned(int entity, const char[] classname)`). The stock-SourceMod `#else` branch (entWatch.sp:194-204) guards both callbacks with IsValidEntity.
- **[client-api-mediator] invariant-I8** — SDKHook registration without a matching unhook is correct here, not a leak: client.sp:34-36 hooks WeaponEquipPost/WeaponDropPost/WeaponCanUse on the client, and sdkhooks.inc:400 states hooks are 'Unhooked automatically upon destruction/removal of the entity'; on plugin unload SDKHooks::Unhook(IPluginContext*) removes everything the context owns (extensions/sdkhooks/extension.cpp:838). There is also no double-hook: SDKHooks::Hook pushes the callback unconditionally with no duplicate check (extension.cpp:792-796), so a repeated OnClientPutInServer WOULD double-fire - but SourceMod never re-fires OnClientPutInServer for an already-connected client, and the only manual call (entWatch.sp:99) runs once, in OnPluginStart, for clients SourceMod will not call it for.
- **[client-api-mediator] correctness** — Late-load client handling is complete and the Late flag ordering is right. entWatch.sp:95-101 iterates 1..MaxClients and replays OnClientPutInServer for in-game clients, which is the one thing SourceMod does not replay. Cookies are covered without a manual OnClientCookiesCached call, because HudClientReadCookie tests AreClientCookiesCached itself (hud.sp:70) and is reached from HudOnClientPutInServer (hud.sp:44-47). Late is set in AskPluginLoad2 (entWatch.sp:49) and cleared at the END of OnMapStart (entWatch.sp:123), i.e. after ItemsOnMapStart (entWatch.sp:113), so ItemsRegisterItemEntity sees Late == true during the adoption scan (items.sp:160-166). The admin live-reload path sets and clears it around the same sequence (admin_menu.sp:88-93).
- **[client-api-mediator] reliability** — The OnClientDisconnect / player_disconnect split is on the right side of the map-change boundary. Per-connection state that is rebuilt on the next map is cleared in OnClientDisconnect (client.sp:86-99: Clients[].Clear, HudOnClientDisconnect, AssistUseOnClientDisconnect, RestrictOnClientDisconnect), which also fires for everyone on a map change - correct, because OnClientPutInServer (client.sp:19-39) rebuilds all of it. Item release, which must NOT run on a map change, is driven from the player_disconnect event instead (entWatch.sp:163-171), which does not fire on a map change.
- **[client-api-mediator] invariant-I9** — The exported surface matches the include exactly - no signature break. api.sp:17-25 creates 8 natives; entWatch.inc:36-45 declares the same 8 names in the same shapes; entWatch.inc:25-32 marks all 8 optional. api.sp:10-15 creates 6 GlobalForwards whose names, parameter counts and Param_Cell order match entWatch.inc:47-52 one for one, and the push order in APIOnClientItemUse/Drop/Pickup (api.sp:47-69) is (client, item) as documented. Both struct-copying natives keep the runtime sizeof guard (api.sp:101 against sizeof(Config), api.sp:115 against sizeof(Item)), and neither Config.inc nor Item.inc has a layout change pending in this scope.
- **[client-api-mediator] correctness** — Fixed player arrays in scope are sized and iterated correctly: Clients is [MAXPLAYERS + 1] (client.sp:17) and every loop over it runs 1..MaxClients (client.sp:131, api.sp reads a single index). The unguarded GetClientOfUserId in the HALFZOMBIE handlers (entWatch.sp:145, :151) is benign, unlike the player_death one: HalfZombieClientInit only writes HalfZombie[client] (halfzombie.sp:19-22) into a [MAXPLAYERS + 1] array (halfzombie.sp:11), so index 0 is in bounds and the write is discarded - there is no sentinel collision on that path.
- **[client-api-mediator] invariant-I3** — No file in this scope writes targetname or classname, so the map-side legacy protection ordering cannot be broken from here - the single writer is OnButtonPress (sdkhook.sp:73-74), which writes Configs[].Filter into the owner's targetname before returning Plugin_Continue at :77/:83, and nothing in entWatch.sp, client.sp or api.sp runs between those two points.
- **[hud-chat] handles (timer lifetime)** — hud.sp:6,26-29,31-42. TimerHud is created once per map with TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE (hud.sp:41) and nulled - not deleted - in HudOnMapEnd (hud.sp:28). That is correct, and the ordering proves it: SourceModBase::LevelShutdown runs g_pOnMapEnd->Execute() and only afterwards g_Timers.RemoveMapChangeTimers() (core/sourcemod.cpp:455-471), so the handle is still valid when OnMapEnd nulls the variable and is then freed by the timer system. On the next map HudCreateTimer's `delete TimerHud` (hud.sp:33) operates on null, which is legal. No double free, no leak, and no path where two Timer_Hud timers coexist: HudCreateTimer is called from HudOnMapStart only (entWatch.sp:115-117), OnMapStart is replayed for a late load with TimerHud freshly null, and if LevelShutdown were skipped the `delete` at hud.sp:33 would kill the surviving timer.
- **[hud-chat] handles (usermessages)** — hud.sp:175-178 and chat.sp:143-163. Every StartMessageOne is followed unconditionally by EndMessage() on the only path through the function - there is no early return or branch between them. A failure of StartMessage cannot leave a message half-open either: smn_StartMessage validates the client and throws before any message is begun (core/smn_usermsgs.cpp:412-449, the g_IsMsgInExec / client-validation block runs first), so an aborted callback cannot strand m_InExec.
- **[hud-chat] invariant-I1/I2/I4/I5/I7** — Neither file participates in any use, pickup or restrict decision. hud.sp only reads Items[]/Configs[] for rendering (hud.sp:119-146) and chat.sp only announces after the decision has already been taken by sdkhook.sp (OnButtonPress's ownership guard sdkhook.sp:64, restrict guard sdkhook.sp:67, readiness sdkhook.sp:70, ItemReload before the announce sdkhook.sp:81-82; Compare/Relay announce exactly once each at sdkhook.sp:99/115 and the button press is passed through at sdkhook.sp:76-77). PrintToChatItemAction has no side effect on Items[] or Configs[] state - it only reads Configs[].Display (chat.sp:19,26,33,41,49) - so it cannot double-count a use or leak an item across the guard.
- **[hud-chat] correctness (KeyHintText buffer vs engine limit)** — hud.sp:115,130,133,175-177. The page-switch predicate `strlen(cur) + strlen(line) + 2 >= sizeof(buffer[][])` with sizeof == 256 permits a concatenation only while cur+line <= 253, so a page string is at most 253 characters. The message is then BfWriteByte (1 byte) + BfWriteString (253 + NUL = 254 bytes) = exactly 255, which is exactly MAX_USER_MSG_DATA (C:/develop/hl2_src-leak-2017/src/public/const.h:434, /src/engine/host.h:86). The '+2' is doing real work here; the per-page sizing is deliberate and correct. `line` itself cannot overflow the page either: ItemFormat writes at most ShortName[31] + "[999/999]" + ": " + name[31] + "\n" into char line[128] with FormatEx bounded by sizeof(line) (hud.sp:117,125; items.sp:538,603).
- **[hud-chat] correctness (chat buffer sizing, client-controlled names)** — chat.sp:99-101,131-141. Buffers are `new char[strlen(format) + 255]`, which sizes the destination from the FORMAT string rather than from the output - fragile, but I could not demonstrate truncation with the shipped data. Worst case for the in-scope producer PrintToChatItemAction: the 22-char format at chat.sp:68 gives a 277-cell buffer; maximum expansion is Colors[COLOR_NAME] + %N (31, CS:S caps names at 31 bytes) + SteamID (Clients.SteamID[40], client.sp:6) + Colors[COLOR_OTHER] + the longest action phrase ("Disconnect" ru = 38 UTF-8 bytes, translations/entWatch.phrases.txt:61-65) + Configs[].Color[1] + Configs[].Name (64, include/entWatch/Config.inc:18) = ~178 bytes, plus SendMessage's tag prefix (\x01\x07 + tagcolor + "[entWatch]" + \x07 + othercolor = ~26 bytes, chat.sp:139, phrases.txt:3-7) = ~204 < 276. The same arithmetic holds for the longest external callers (transfer.sp:71, restrict.sp:70). A crafted player name therefore cannot overflow or truncate these buffers - the buffers are heap-allocated per call and every write goes through VFormat/Format/StrCat with an explicit size.
- **[hud-chat] api-use (Format aliasing)** — chat.sp:139 passes `buffer` as both the destination and the trailing %s argument of Format(). This is explicitly legal: C:/develop/sm-1.13/include/string.inc:152-155 documents FormatEx as "the same as Format(), except none of the input buffers can overlap the same memory as the output buffer. Since this security check is removed, it is slightly faster" - i.e. Format keeps that check. Using Format (not FormatEx) here is the correct choice.
- **[hud-chat] api-use (VFormat vararg positions)** — chat.sp:93 VFormat(...,3) inside PrintToTeam(int team, const char[] format, any ...); chat.sp:103 VFormat(...,3) inside PrintToChat2(int client, const char[] message, any ...); chat.sp:124 VFormat(...,2) inside PrintToChatAll2(const char[] message, any ...). All three match the documented meaning of varpos - "Argument number which contains the '...' symbol. Note: Arguments start at 1" (C:/develop/sm-1.13/include/string.inc:168-183). SetGlobalTransTarget is set per recipient before each VFormat (chat.sp:92,102,123) and again in SendMessage (chat.sp:138), so %t resolves in the right language for each client.
- **[hud-chat] correctness (team scoping and loop bounds)** — chat.sp:57-75, chat.sp:82-95, chat.sp:119-127 all iterate `for(int i = 1; i <= MaxClients; i++)` over MAXPLAYERS+1-sized arrays and check IsClientInGame(i) before touching the client (chat.sp:60,84,121). The scoping test `if(team2 > 1 && team != team2) continue;` (chat.sp:65,89) correctly restricts T/CT (CS:S team indices 2 and 3) to their own team while letting unassigned (0) and spectators (1) see everything. hud.sp:162-179 likewise iterates 1..MaxClients and hud.sp:167-170 maps GetClientTeam-1 with a `team < 0` clamp, so spectator (1->0) and unassigned (0->-1->0) both read the shared page 0, matching how page 0 is filled at hud.sp:142-145.
- **[hud-chat] async / client-state lifetime** — Neither file starts a threaded query, a DataPack timer, or any callback that outlives the frame, so the store-userid-not-index rule has nothing to bite on. The only cross-frame state is Hud[MAXPLAYERS+1] (hud.sp:8), and it is set only behind IsClientInGame (hud.sp:56-59) and cleared in HudOnClientDisconnect (hud.sp:85-88), which is wired to OnClientDisconnect (client.sp:86-90) - a forward that fires for every client on a map change as well as on a real disconnect, so the flag cannot survive a map change. Timer_Hud consequently never sends to a slot that was never put in server.
- **[hud-chat] clientprefs / cookie lifecycle** — hud.sp:12 registers the cookie exactly once from HudInit, which OnPluginStart calls once (entWatch.sp:62-64); the handle is framework-owned and correctly never deleted. Every read is gated by AreClientCookiesCached (hud.sp:70) and every write by the same check (hud.sp:94), and the module is re-entered from both OnClientPutInServer and OnClientCookiesCached (hud.sp:44-52) so whichever fires second wins - this also covers late load, where OnPluginStart replays OnClientPutInServer for connected clients (entWatch.sp:95-101) at a point where cookies are already cached. GetClientCookie into char buffer[4] with sizeof (hud.sp:72-73) cannot overflow, and an empty cookie correctly defaults to on (hud.sp:78-81).
- **[hud-chat] hot path / per-tick work** — All HUD work is on a 1.0 s repeating timer (hud.sp:41); there is no OnGameFrame or OnPlayerRunCmd work in either file, and the per-team page buffers are built once per tick and reused for every recipient (hud.sp:119-146 builds, hud.sp:162-179 sends). Chat work is purely event-driven from sdkhook.sp/client.sp. Nothing in scope runs per frame or per tick.
- **[hud-chat] entities** — Neither hud.sp nor chat.sp reads, stores or resolves an entity index or reference - the only indices they handle are client indices and Items[]/Configs[] array indices. The EntIndexToEntRef concern does not apply to this scope.
- **[hud-chat] database** — Neither file contains any SQL, Database, DBResultSet, Transaction or SQL_ call - grep over both files returns nothing. No blocking-query or escaping concern in scope.
- **[hud-chat] invariant-I9 (public API struct layout)** — Both files only read fields of Items[] and Configs[] (hud.sp:121-124, chat.sp:19-74); neither declares, extends or reorders the Item/Config enum structs, which live in include/entWatch/Item.inc and include/entWatch/Config.inc. Nothing in scope forces consumers of entWatch_GetItem/entWatch_GetConfig to recompile.
- **[hud-chat] invariant-I6 (index stability)** — hud.sp:119-146 and chat.sp:12-76 receive the item index as a parameter and consume it synchronously within the same frame - no item or config index is stored in a timer, a DataPack, a menu item, or any static in either file (the only statics are hud_enabled, TimerHud, CookieHud, Hud[], team, currentPages[], ticksUpdatePages, and SendMessage's `mode`, none of which hold an index into Items[]/Configs[]). ItemRemove()/RemoveConfig() shifting the arrays cannot invalidate anything these two files hold.
- **[hud-chat] dead code (Protobuf branch)** — chat.sp:133-137,153-161. `static int mode` is resolved once from GetUserMessageType() and, on CS:S, is always 0, so the Protobuf arm at chat.sp:153-161 never executes. Noted only; CLAUDE.md already schedules its removal, so no effort spent.
- **[admin-menu] handles** — Every Menu created in this file is released exactly once in its own MenuAction_End branch and nowhere else — no double free, no early return that skips it: AdminMenu_Handler admin_menu.sp:47-50, BanMenu_Handler:137-140, BanLengthMenu_Handler:203-206, BannedPlayersMenu_Handler:274-277, BannedPlayerMenu_Handler:350-353, TransferMenu_Handler:422-425, TransferByMapMenu_Handler:502-505, TransferByTargetMenu_Handler:593-596, UseItemMenu_Handler:687-690, ConfigsMenu_Handler:789-792, ConfigMenu_Handler:880-883. MenuAction_End fires for both the selected and the cancelled outcome (C:/develop/sm-1.13/include/menus.inc:57-59, 125-130), and Select/Cancel/End are always delivered regardless of the mask passed to the constructor (menus.inc:467-470), so the handlers that omit MenuAction_Cancel from the mask (admin_menu.sp:21) still get it. The only unreleased handle in the file is the KeyValues reported as admincfg-kv-leak.
- **[admin-menu] async** — admin_menu.sp performs no threaded SQL, no timers and no DataPacks — there is no cross-frame callback that could hold a dead client slot. Where identity must survive between menu display and selection it is stored as a USERID and re-resolved with GetClientOfUserId plus an IsClientInGame/IsPlayerAlive re-validation in the handler: admin_menu.sp:119+152-158, 177+218-224, 256+289-296, 314+365-372, 402+446-453, 483+525-532, 573+621-630, 666+714-721. That is the correct pattern; the defect is only in the ITEM index carried alongside (see admin-menu-item-index-stale).
- **[admin-menu] invariant-I1** — The admin forced-use path does not bypass the ownership guard. UseItemMenu_Handler re-resolves the owner from the userid and refuses when `Items[item].Owner != target` (admin_menu.sp:716), then calls AssistUseAdmin (assist_use.sp:78-99) -> AssistUse -> AssistUseInputByName -> AcceptEntityInput(Items[item].Button, "Use", Items[item].Owner, Items[item].Owner) (assist_use.sp:209/215/228). The activator is the OWNER, so the press re-enters OnButtonPress and satisfies `Items[item].Owner != activator` (sdkhook.sp:64) rather than skipping it. No alternate use path is introduced in this file.
- **[admin-menu] invariant-I2** — Restricted players are excluded from every menu path that hands out an item: BanMenu skips already-restricted clients (admin_menu.sp:115), TransferMenu skips restricted receivers when building the list (admin_menu.sp:399) and re-checks on selection (admin_menu.sp:448), and both transfer handlers re-check the receiver after the delay (admin_menu.sp:527, 625). The forced-use path does not check the owner's restrict state, but it does not need to: the press it generates goes through OnButtonPress, which blocks with `RestrictClientHasRestrict(activator)` at sdkhook.sp:67-68, so a player ebanned while holding an item still cannot fire it.
- **[admin-menu] invariant-I4** — Nothing in admin_menu.sp touches item timing directly — there is no GetGameTime/GetEngineTime/GetTime use on the item path and no write to Items[].Cooldown/Wait/Uses. The forced-use entry point goes through the button, so ItemIsReady() (items.sp:447-489, m_flWait + m_bLocked + GetGameTime) and ItemReload() (items.sp:491-532, with the GetTickInterval()*5.0 ghost-use margin) still gate it. The two ways this file can put entWatch AHEAD of the map are indirect and reported separately (admincfg-cooldown-int, admin-no-numeric-validation).
- **[admin-menu] invariant-I5** — Both transfer menus are built from TransferIsValidItem (admin_menu.sp:480, 569), which rejects SLOT_NONE and SLOT_KNIFE (transfer.sp:52-53), and TransferItem re-runs the same check before doing anything (transfer.sp:60-61), so a stale menu index cannot smuggle a knife item through. The only I5 breach found is the save path rewriting the slot (admincfg-gfl-slot-lost).
- **[admin-menu] invariant-I3** — admin_menu.sp never writes a player's targetname or classname and never reorders the OnButtonPress sequence that does (sdkhook.sp:73-74, filter written before the press is let through). The editor only edits the Filter STRING; the only way it damages I3 is the strcopy overrun reported as admincfg-color-overflow.
- **[admin-menu] entities** — The file performs no direct entity manipulation: the only entity-touching call is SpawnItem(EditClientsConfigs[client].Config, client, client) at admin_menu.sp:908, which passes a config index and a live client, and spawn.sp:38-78 does its own FindEntityByClassname/CreateEntityByName handling. No raw entity index is stored across frames in this file (item indices are — reported separately).
- **[admin-menu] correctness** — The editor's menu-position -> field mapping is exact end to end: ConfigMenu adds "[Remove item]" and "[Spawn item]" as items 0-1 and the 15 editable fields as items 2-16 (admin_menu.sp:854-870); ConfigMenu_Handler maps Slot = index - 2 (admin_menu.sp:913); AdminOnClientSayCommand's cases 0..14 (admin_menu.sp:940-999) line up one-for-one with those 15 lines (Name, ShortName, Color, Filter, Weapon, Button, Trigger, Mode, Slot, Maxuses, Cooldown, Display, Template, Compare, Relay). No off-by-one, and Slot cannot leave 0..14 because index >= 2 is guaranteed by the two fixed leading items.
- **[admin-menu] api-use** — String handling in the menu builders is sound apart from the one reported case: AddMenuItem2 passes varpos 5, which is correct for (menu=1, flags=2, desc=3, title=4, ...=5) per C:/develop/sm-1.13/include/string.inc:171-183; the info-string encoders fit their buffers ("%i_%i" / "%i_%i_%i" of userids and small indices into char[64]/char[256] at admin_menu.sp:483, 573, 666); the decoders use FindCharInString with the backwards flag where the field order requires it and check for -1 before slicing (admin_menu.sp:518-525, 609-623, 703-714); strcopy destinations Name/ShortName/Filter/Template all get the true sizeof of their fields (admin_menu.sp:942, 946, 954, 990). Menu.Selection is read only inside MenuAction_Select (admin_menu.sp:896), which is the documented constraint (menus.inc:455-460).
- **[admin-menu] database** — admin_menu.sp contains no SQL: the eban/unban entries delegate to RestrictClientBan/RestrictClientUnBan (admin_menu.sp:226, 374), which own the query handling in restrict.sp. No blocking query, no unescaped input, no result-set handle originates in this file.
- **[admin-menu] correctness** — Per-client editor state is bounded and is cleared on both connect and map change: EditClientsConfigs is sized [MAXPLAYERS + 1] (admin_menu.sp:757) and is only ever indexed by the client of a menu handler or of OnClientSayCommand; AdminOnClientPutInServer -> Clear() (admin_menu.sp:923-926) is called from OnClientPutInServer (client.sp:24-26), which SourceMod re-fires for every client on every map change, so the editor cannot survive a map. Bots cannot enter the state at all: client.sp:21-22 returns before the init for fake clients and client.sp:118-119 returns before AdminOnClientSayCommand for them. All client loops in the file run 1..MaxClients (admin_menu.sp:113, 250, 397, 561, 655).
- **[transfer-spawn-misc] handles** — None of the five scope files creates a Handle-backed object: no `new KeyValues/Menu/DataPack/ArrayList/File`, no DBResultSet, no Transaction. transfer.sp (116 lines), spawn.sp (79), stripper.sp (73), dump.sp (27), helpers.sp (78) read end to end — the only allocations are stack char buffers (e.g. transfer.sp:13, spawn.sp:45, stripper.sp:13, helpers.sp:11). No leak, no double free, no early return skipping a delete.
- **[transfer-spawn-misc] async** — No timers, threaded SQL or forward callbacks originate in scope. There is no CreateTimer/DB_Query/RequestFrame in transfer.sp, spawn.sp, stripper.sp, dump.sp or helpers.sp, so the store-userid-not-index rule has nothing to apply to. Every client index used (transfer.sp:15-17, spawn.sp:27-33) is resolved and consumed in the same frame.
- **[transfer-spawn-misc] invariant-I5** — SLOT_KNIFE / SLOT_NONE items are never transferred: TransferIsValidItem rejects both before anything happens (transfer.sp:52-53), TransferItem calls it as its first statement (transfer.sp:60), and ItemDrop independently refuses the same two slots (items.sp:436-437). TransferDropAllTransferedItems can only see items that already passed that gate (Transfered is set only at transfer.sp:86).
- **[transfer-spawn-misc] invariant-I8** — transfer.sp, spawn.sp, stripper.sp and dump.sp add and remove zero hooks — no SDKHook/SDKUnhook/HookSingleEntityOutput anywhere in them. A spawned item is bound by the normal path: the point_template clone spawns -> OnEntitySpawned (entWatch.sp:189-192) -> ItemsOnEntitySpawned -> ItemsRegisterItemEntity installs SDKHook_Use / touch hooks exactly once (items.sp:183, 198-200). No double hooking, no double counting from these files. (The hook leak in helpers.sp:42 is reported separately.)
- **[transfer-spawn-misc] correctness** — TransferOnRoundEnd/ItemsOnRoundEnd ordering is correct and load-bearing: entWatch.sp:182-186 calls TransferOnRoundEnd() first, and ItemsOnRoundEnd() -> ItemsClear() (items.sp:33-37, 69-79) wipes Transfered via ItemClear (items.sp:634). Reversing the two would silently stop transferred items from being dropped back. OnPluginEnd (entWatch.sp:104-108) has the safe order too — ItemsOnPluginEnd only unhooks, it does not clear.
- **[transfer-spawn-misc] correctness** — spawn.sp handles a missing point_template correctly: the scan loop sets `found` only on an exact strcmp match of Configs[config].Template against m_iName and returns false otherwise (spawn.sp:43-59); an empty Template short-circuits at spawn.sp:40. GetEntPropString returning 0 non-null bytes is handled with `continue` (spawn.sp:48-49), matching its documented return (entity.inc:673-684).
- **[transfer-spawn-misc] entities** — On the success path spawn.sp does NOT leak the env_entity_maker: it is created (spawn.sp:61), keyed, spawned, teleported, ForceSpawn'ed and then removed with AcceptEntityInput(entity, "Kill") (spawn.sp:74). CreateEntityByName failure is checked against -1 (spawn.sp:61). The only leak is the client-0 abort reported as spawn-console-client0-leak.
- **[transfer-spawn-misc] correctness** — stripper.sp does NOT suffer the strncmp prefix-matching hazard the focus list suspected: it resolves by exact integer hammerid via ConfigGetByWeaponHammerId (config.sp:223-232, `Configs[i].Weapon_HammerId == hammerid`) and ItemsGetByWeaponHammerID (items.sp:368-377), never via ConfigGetByName/ItemsGetByName. The -1 sentinel is checked before every array write (stripper.sp:23, 46, 66), so no negative index reaches Configs[] or Items[].
- **[transfer-spawn-misc] api-use** — %N with client 0 is not an error and does not need guarding in transfer.sp:71/73/77/79 or spawn.sp:76-77: sprintf.cpp:1186-1201 substitutes the literal "Console" when the index is 0 and only calls DescribePlayer for non-zero indices. LogAction documents client 0 as 'server' (logging.inc:68-78). Clients[0].SteamID (transfer.sp:73) is index 0 of a [MAXPLAYERS+1] array — in bounds, just empty.
- **[transfer-spawn-misc] correctness** — dump.sp is safe for empty state and for a console caller: both loops are guarded by `if(Configs_Count)` (dump.sp:8) and `if(Items_Count)` (dump.sp:16), so nothing is read when either count is 0; PrintToConsole with client 0 routes to the server console rather than throwing (smn_console.cpp:106-148, `if (index != 0) ... else bridge->ConPrint(buffer)`). HasEntProp(Items[i].Button == 0, ...) (dump.sp:21) resolves entity 0 = worldspawn and returns false via FindDataMapInfo without throwing (entity.inc:512-526). Format specifier/argument counts match (8 and 8).
- **[transfer-spawn-misc] invariant-I6** — No file in scope stores an item or config index across frames. Command_Transfer resolves and consumes the index in the same call (transfer.sp:20-38), Command_Spawn likewise (spawn.sp:17-33), stripper.sp resolves per invocation (stripper.sp:21, 44, 64), dump.sp only iterates locally. The cross-frame index storage that does exist is in admin_menu.sp's menu item data (admin_menu.sp:483, 573, 666) — outside this scope.
- **[transfer-spawn-misc] correctness** — Client-array indexing in scope stays in bounds: transfer.sp:17 relies on `||` short-circuiting so RestrictClientHasRestrict(receiver) and Clients[receiver] are only evaluated after `receiver <= 0` is false; spawn.sp checks `receiver == -1` (spawn.sp:29) which is FindTarget's only failure value (helpers.inc:163-195 returns target_list[0] >= 1 on success, -1 on error). helpers.sp indexes no [MAXPLAYERS+1] array at all.
- **[transfer-spawn-misc] invariant-I2** — spawn.sp does not need a restrict/half-zombie gate on the receiver: SpawnItem only creates the item at the receiver's origin (spawn.sp:65-73) — it never equips anyone. A restricted player or half-zombie standing there is still blocked from picking it up by OnWeaponTouch (sdkhook.sp:1-21) and from touching its trigger by OnTriggerTouch (sdkhook.sp:118-135). Invariant holds indirectly and correctly.
- **[transfer-spawn-misc] invariant-I1** — No file in scope opens an alternate use path: transfer.sp, spawn.sp, stripper.sp and dump.sp never call AcceptEntityInput on an item button, never invoke OnButtonPress, and never write Items[].Owner directly — ownership is only ever set through the SDKHook_WeaponEquipPost path (sdkhook.sp:30). The single ownership guard `Items[item].Owner != activator` (sdkhook.sp:64) therefore remains the sole barrier and is not bypassed by these modules. stripper.sp's sm_decuses only decrements Items[].Uses (stripper.sp:69-70); it does not fire the item.

