# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## What this is

**entWatch** — a SourceMod plugin for **CS:S zombie-escape servers** that takes control of the
map's *special items* (a.k.a. "materia"). Repository `CSS-SWZ/entWatch`, version lives in
`myinfo` in `entWatch.sp` (currently `1.0.1`).

A *special item* is a map-placed weapon (usually a pistol; a knife for zombies and for some
human items) wired to map entities: an invisible `func_button`, a `trigger_*`, and optionally
`logic_compare` / `logic_relay`. The plugin binds those entities by Hammer ID and then:

- tracks who owns each item (pickup / drop / death / disconnect / admin transfer);
- **blocks non-owners from firing the item** — the original reason this plugin exists;
- enforces cooldowns / limited uses / charges, staying in sync with the map's own logic;
- announces pick / drop / use in team chat and shows a live HUD of items and owners;
- restricts ("ebans") players from taking items at all, persisted in a database;
- exposes an API (natives + forwards) that other plugins on the server already consume.

The plugin is deliberately **format-universal**: it reads the per-map configs of both the *GFL*
and the *UNLOZE* entWatch variants as-is, so server operators never have to convert existing map
configs into a third format.

This code has been running in production for years and players do not complain. Treat it as
mature: prefer targeted, well-argued fixes over rewrites, and be conservative about behaviour
that map authors may depend on.

## How to change this code

Because the plugin is mature and live, these are conditions, not preferences.

- **Every change carries a trigger line** — who executes it, in what state, along which code
  path. If the trigger cannot be written, there is no change: the finding stays in the report as
  a hypothesis. A one-line change needs the same justification as a hundred; being cheap to
  write is not a reason to write it.
- **Fixing wrong code is not the same as armouring correct code.** A broken loop bound, a
  chained comparison, swapped arguments, a missing counter decrement — fix those. Adding
  `if (x == -1)` to a path that has not been shown to be reachable is not a fix; it is noise
  that conceals not knowing the real state of the code.
- **Audit and fixing are separate phases with different evidence bars.** In an audit
  "plausible, worth reporting" is enough; in fixing, only "proven" is. A finding marked
  unverified never becomes a code change — stop and say so instead.
- **Recompute after each edit**: one fix often makes the next finding unreachable. Say that
  explicitly instead of applying both.
- **Batches of at most five changes**, then show the diff and stop. Accumulating work to present
  it all at once destroys the reviewer's chance to catch a bad pattern while it is still cheap.

## Target environment

- **Game: CS:S only.** The Protobuf branch in `entWatch/chat.sp` (`SendMessage()`) is dead code
  and is scheduled for removal — CS:GO is not a target.
- Server runs **BotoX's SourceMod 1.13 fork** (build 7214). `#define BOTOX_SM` in `entWatch.sp`
  selects the production path (`OnEntitySpawned`). The `#else` path (`OnEntityCreated` +
  `SDKHook_SpawnPost`) exists for stock SourceMod and must keep compiling.
- Optional dependency: **zombiereloaded** (the SWZ-edition fork, `C:\develop\sg-zr-swzedition`),
  pulled via `#tryinclude` in the `HALFZOMBIE` module only.
- `clientprefs` (HUD toggle cookie), `sdkhooks`, `sdktools`.

## Build

No build script; the plugin is compiled manually. **The user compiles — do not run `spcomp`
unless explicitly asked.** Entry point `addons/sourcemod/scripting/entWatch.sp`, output
`entWatch.smx`; the plugin's own includes live in `scripting/include`, so the include path must
be passed:

```
spcomp -i"addons/sourcemod/scripting/include" addons/sourcemod/scripting/entWatch.sp
```

There are no tests. Verification = clean compile, then testing on the live server.

Feature `#define`s in `entWatch.sp` — `HUD`, `ASSIST_USE`, `ADMIN_MENU`, `HALFZOMBIE` — are all
enabled in production, but they exist so subsystems *can* be switched off. When touching a gated
module, keep both builds (gate on and off) compiling warning-free.

## Git / workflow

This is a serious, long-running project — work in a **feature branch off `master`**, never
commit directly to `master`. Commit and push **only when asked**. Bump `myinfo.version` (SemVer)
once per completed piece of work, not once per micro-fix.

## Code style

Legacy transitional codebase. The target style is `~/.claude/rules/sourcepawn.md`; the policy
here is to **migrate towards it gradually and surgically**, not in one sweep.

Current state, so you know what you are looking at:

- `#pragma newdecls required` is set, `#pragma semicolon 1` is **not**.
- Indentation mixes tabs and spaces between (and inside) files.
- Globals and functions are PascalCase (`Items_Count`, `Configs[]`, `ItemsGetByWeapon`);
  callbacks use underscores (`Command_Ban`, `SQL_Callback_SelectBans`, `Timer_Hud`).
- Module entry points already follow the `<Module>Init` / `<Module>On<Forward>` convention.

Match the style of the file you are editing; do not reformat adjacent code unprompted. Code
comments are in Russian.

## Architecture

### One plugin, many files

Everything compiles into a single `.smx`. `entWatch.sp` is a **mediator**: it declares *all*
SourceMod forwards and fans each one out to module functions (`ItemsOnRoundStart()`,
`ConfigOnMapStart()`, `HudOnClientDisconnect()`, …). To hook a module onto a lifecycle event,
add its call to the matching forward in `entWatch.sp`.

It is one translation unit — globals and functions are visible across files, so **include order
in `entWatch.sp` is dependency order**: `config.sp` (declares `Configs[]`, `MODE_*`, `SLOT_*`,
`DISPLAY_*`) comes before `items.sp`, which comes before everything that touches `Items[]`.

Late load is handled with the global `Late` flag (set in `AskPluginLoad2`, cleared at the end of
`OnMapStart`); it lets `ItemsRegisterItemEntity()` adopt weapons that already have an owner.

### Data model

Two flat arrays plus counts, no dynamic containers:

- `Configs[MAX_CONFIGS]` (`config.sp`, 50) — static, parsed from the map config.
- `Items[MAX_ITEMS]` (`items.sp`, 200) — runtime instances; `Items[i].Config` indexes `Configs[]`.

Both structs are declared in `scripting/include/entWatch/` because the API copies them out to
other plugins.

**Indices are not stable.** `ItemRemove()` and `RemoveConfig()` shift the arrays down, while item
indices are handed to timers, menu item data and API forwards. Any new code that stores an item
index across frames must account for this.

### Entity binding

Items are recognised by `m_iHammerID`. On round start `ItemsOnRoundStart()` clears everything and
re-scans all entities; afterwards `OnEntitySpawned` feeds new entities in one by one.
`ItemsRegisterGetKeyValues()` maps a Hammer ID to (config, role) where role is one of
`REGISTER_WEAPON / TRIGGER / BUTTON / COMPARE / RELAY`.

If a config has no `buttonid`, `Timer_ItemFindButton` (0.5 s after the weapon appears) scans
entities parented to the weapon and picks one by priority: `*button*` → `func_physbox_multiplayer`
→ `*door*`. Buttons and triggers are also validated against the weapon through
`AreEntitiesRelated()` (walks `m_pParent`), because several items of the same kind can exist on
one map.

Hooks per role: `SDKHook_Use` on the button, `StartTouch`/`EndTouch`/`Touch` on the trigger,
entity outputs `OnEqualTo` on `logic_compare` and `OnTrigger` on `logic_relay`.

### Per-map configs

`configs/entwatch/<map>.cfg`, map name lowercased (`ConfigOnMapStart`). Format is auto-detected
per key block in `ConfigGetType()`:

| | GFL | UNLOZE |
|---|---|---|
| weapon key | `hammerid` | `weaponid` |
| short name | `shortname` | `short` |
| filter | `filtername` | `filter` |
| display | `chat` / `activate` / `hud` flags | `display` bitmask |
| slot | derived from `allowtransfer`/`forcedrop` | `slot` |
| mode | `mode` (1-based) | `mode` (0-based) |

Both formats are live on production maps. **Adding a config key means touching three places**:
`ConfigBrowseKeyGFL()`, `ConfigBrowseKeyUNLOZE()` and `AdminConfigBrowseItems()` (the in-game
config editor's save path, which writes the format the config was read as).

## Domain rules that matter

These are the non-obvious contracts. Do not "clean them up" without understanding them.

1. **Ownership protection ("E spam").** Two players stand next to each other; one holds the item.
   The other aims at the item's *invisible button* — which sits on the owner's body — and presses
   E, firing the item without owning it. Before entWatch, players deliberately faced walls to
   avoid triggering their own items. The guard is `Items[item].Owner != activator` in
   `OnButtonPress()`. Note that `Compare_OnEqualTo()` and `Relay_OnTrigger()` only check that the
   item *has* an owner — they never compare `activator` with it, so on those paths the invariant
   holds only indirectly, through the button press being blocked first. Every new use path must
   keep this guard.
2. **Restricted players.** An ebanned player must not obtain an item by any route: pickup is
   denied in `OnWeaponTouch()`, button presses in `OnButtonPress()`, and touching the item's
   trigger (maps put strip- or teleport-triggers next to knife items to hand them over) is
   blocked in `OnTriggerTouch()`. The same applies to ZR "half-zombie" classes (`HALFZOMBIE`).
3. **Map-side legacy protection must keep working.** Many maps still implement their own owner
   check: on `OnPressed` the map fires `TestActivator` at a `filter_*` entity that compares
   `targetname`. So before letting a press through, `OnButtonPress()` writes `Configs[].Filter`
   into the owner's `targetname` — and deliberately never resets it. Some maps also implement
   per-player item levels by rewriting the player's `classname`. Both are map-side hacks the
   plugin must not fight.
4. **Cooldown sync — direction matters.** entWatch's view of an item's readiness must never be
   *ahead* of the map's. The dangerous failure is: entWatch thinks the item is ready, allows the
   press, announces and counts a use — while the map is still on cooldown and nothing actually
   fires. Hence `ItemReload()` adds `GetTickInterval() * 5.0` ("fix ghost using") and `ItemIsReady()`
   honours the button's `m_flWait` and `m_bLocked`. All item timing uses `GetGameTime()`; keep one
   time base. The suspected residual risk is E-spam right at the readiness boundary.
5. **Knife items are never moved.** `SLOT_KNIFE` and `SLOT_NONE` items cannot be dropped or
   transferred (`ItemDrop()`, `TransferIsValidItem()`) — zombies carry only knives.
6. **Modes** (`Configs[].Mode`): `PROTECT` (ownership only, no cooldown, use messages suppressed),
   `COOLDOWN`, `MAXUSES`, `MAXUSESCD`, `CHARGESCD` (N charges, then one shared cooldown).
7. When an item has a `Compare` or a `Relay`, the button press is passed through and the *use* is
   counted from the entity output instead — that is how maps with conditional activation report a
   real use rather than an attempted one.

## Subsystems

| File | Responsibility |
|---|---|
| `entWatch.sp` | mediator: forwards, feature `#define`s, module includes |
| `entWatch/config.sp` | per-map config parsing (GFL + UNLOZE), `Configs[]`, `MODE_*`/`SLOT_*`/`DISPLAY_*` |
| `entWatch/items.sp` | `Items[]`, entity binding, readiness/reload, HUD line formatting |
| `entWatch/sdkhook.sp` | all gameplay hooks: pickup/drop/touch, button press, compare/relay outputs |
| `entWatch/client.sp` | `Clients[]`, per-client hooks, DB auth, item loss on death/disconnect |
| `entWatch/restrict.sp` | ebans: commands, SQL, per-client restrict state |
| `entWatch/database.sp` | connection (`databases.cfg` block `entwatch`, else SQLite), schema, `DB_Query()` |
| `entWatch/hud.sp` | `KeyHintText` HUD, 1 s timer, per-team paged buffers, `sm_hud` cookie |
| `entWatch/chat.sp` | team-scoped announcements, `SayText2` wrapper, colour tags |
| `entWatch/colors.sp` | `configs/entwatch/colors.cfg` + named-colour → hex map |
| `entWatch/assist_use.sp` | forced button press on E (see below) |
| `entWatch/transfer.sp` | admin item transfer, drop of transferred items on round end |
| `entWatch/spawn.sp` | spawning items from a map `point_template` via `env_entity_maker` |
| `entWatch/admin_menu.sp` | admin UI: ebans, transfer, forced use, live config editor |
| `entWatch/stripper.sp` | server commands for stripper/map configs: `sm_setcooldown`, `sm_setmaxuses`, `sm_decuses` |
| `entWatch/halfzombie.sp` | ZR integration: half-zombie classes may not hold items |
| `entWatch/api.sp` | natives and global forwards |
| `entWatch/helpers.sp`, `dump.sp` | shared utilities; `sm_edump` diagnostics |

**assist_use** deserves a note: pressing E does not reliably activate an item (the crosshair may
hit a wall, the button may need a jump to line up), so the module fires the button for the player
on E. It must not fire when the player is aiming at a *real* map button or door (that would
double-trigger), when the player pressed a non-item button in the same tick, or when the player
holds more than one item (`ze_castlevania`, `ze_paranoid`).

**HUD**: one shared timer builds up to `MAX_PAGES` pages per team (index 0 = all/spectators,
1 = T, 2 = CT), rotating every 5 ticks, sent as `KeyHintText`. `HudClientReadCookie()` intends to
give SourceTV the HUD and deny it to other bots, but `OnClientPutInServer()` returns on
`IsFakeClient` before the HUD is set up, so in practice no bot — SourceTV included — receives it.
Per-client visibility is a `clientprefs` cookie (`entwatch_display`, `sm_hud`).

**Admin config editor**: `sm_eadmin` → Configs lets admins edit a config live and save it;
`AdminConfigSave()` uses `configs/entwatch/empty.cfg` as a KeyValues template and writes
`configs/entwatch/<map>.cfg`. `configs/entwatch/colors.cfg` is mandatory — the plugin
`SetFailState`s without it.

## Database

Table `ebans`, created on connect. MySQL if `databases.cfg` has an `entwatch` block, otherwise
SQLite (`SQLite_UseDatabase("entwatch")`).

- The table is currently owned by this plugin alone; a web panel is planned, so the schema may be
  **changed freely** — there is no legacy to preserve. A normalized, properly indexed schema is
  wanted.
- **Threaded queries only.** `RestrictAddBan()` / `RestrictDeleteBan()` currently do a blocking
  `SQL_LockDatabase` + `SQL_Query` on the main thread — this is a defect to fix, not a compromise.
- Restricts are matched by both Steam account ID and IP.
- **No database → no restricts** (fail-open) is intended behaviour.

## Public API

`scripting/include/entWatch.inc` — 8 natives, 6 forwards. It is consumed by other plugins on the
server: **do not break existing native/forward signatures.** `entWatch_GetConfig()` /
`entWatch_GetItem()` copy the `Config` / `Item` enum structs out and check `sizeof` at runtime, so
changing either struct forces every consumer to recompile — treat struct layout as part of the
API.

## Commands

| Command | Access | Purpose |
|---|---|---|
| `sm_status [target]` | all | own/target restrict status |
| `sm_hud` | all | toggle the HUD (saved in a cookie) |
| `sm_eban <target> <minutes>` / `sm_uneban <target>` | `generic` | restrict / unrestrict an online player |
| `sm_addeban <minutes> [steamid] [ip]` / `sm_deleban [steamid] [ip]` | `rcon` | offline restrict management |
| `sm_eadmin` | `generic` | admin menu (ebans, transfer, forced use, config editor) |
| `sm_etransfer <owner\|$item> <receiver>` | `generic` | transfer an item |
| `sm_espawn <shortname> [receiver]` | `ban` | spawn an item from its `point_template` |
| `sm_euse <owner\|$item>` | `ban` | force-use someone's item |
| `sm_assistuse` | `rcon` | toggle the assist-use module |
| `sm_edump` | `rcon` | dump configs and live items to console |
| `sm_setcooldown` / `sm_setmaxuses` / `sm_decuses` | server cmd | runtime tuning from stripper/map configs |

## Direction / planned work

Decided; do not undo or re-litigate these:

- Remove the Protobuf path in `chat.sp` (CS:S only).
- Make every query asynchronous; eliminate blocking SQL.
- Redesign the `ebans` schema — normalized, indexed, suitable for a web panel.
- Add **map-only (temporary) restricts** that work without a database, so restricting still works
  when the DB is down.
- Continue the gradual restyle towards `~/.claude/rules/sourcepawn.md`.
- A deep, multi-axis audit is planned (entity lifecycle, item sync, anti-cheat surfaces, game
  time, database). Correctness under adversarial player behaviour is the priority.

player can have more than 1 item (weapon_deagle and weapon_mp5 for example).