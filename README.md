# entWatch

A SourceMod plugin for **Counter-Strike: Source** zombie-escape servers that takes control of
the map's *special items* — the map-placed weapons players call "materia".

A special item is an ordinary map weapon (usually a pistol, or a knife for zombies) wired to a
set of map entities: an invisible `func_button`, sometimes a `trigger_*`, and optionally a
`logic_compare` or `logic_relay`. The map itself has no idea who is allowed to fire it.
entWatch binds those entities by Hammer ID and then owns the item's lifecycle.

- **Ownership protection.** Only the player actually holding the item can fire it.
- **Cooldowns, limited uses and charges**, kept in step with the map's own logic.
- **Live HUD** of every item and its owner, plus team-scoped chat announcements.
- **Restrictions** ("ebans") that stop a player from taking items at all.
- **Admin tools**: transfer an item, force a use, spawn an item, edit the map config in game.
- **API** — natives and forwards for other plugins on the server.

The plugin is deliberately **format-universal**: it reads the per-map configs of both the *GFL*
and the *UNLOZE* entWatch variants as they are, so existing map configs never have to be
converted.

---

## Table of contents

- [How an item is recognised](#how-an-item-is-recognised)
- [Item modes](#item-modes)
- [Map configuration](#map-configuration)
- [Colors](#colors)
- [HUD](#hud)
- [Chat announcements](#chat-announcements)
- [Restrictions](#restrictions)
- [Admin menu and the live config editor](#admin-menu-and-the-live-config-editor)
- [Spawning items](#spawning-items)
- [Runtime tuning from map configs](#runtime-tuning-from-map-configs)
- [Commands](#commands)
- [Optional subsystems](#optional-subsystems)
- [API](#api)

---

## How an item is recognised

Everything is keyed on `m_iHammerID`. On every round start the plugin clears its state and
rescans the entity list; after that, new entities are picked up as they spawn.

| Role | Bound by | What the plugin does with it |
|---|---|---|
| Weapon | `hammerid` / `weaponid` | the item itself — ownership follows this entity |
| Button | `buttonid` | `SDKHook_Use` — the ownership and readiness gate |
| Trigger | `triggerid` | `StartTouch`/`Touch`/`EndTouch` — blocks restricted players |
| Compare | `compareid` | hooks the `OnEqualTo` output of a `logic_compare` |
| Relay | `relayid` | hooks the `OnTrigger` output of a `logic_relay` |

Only the weapon key is mandatory. Everything else is optional and, in practice, most configs
carry just the weapon.

**Button auto-detection.** If a config has no `buttonid`, half a second after the weapon appears
the plugin scans entities parented to it and picks one by priority:

1. any classname containing `button` (`func_button`, `func_rot_button`, `momentary_rot_button`)
2. `func_physbox_multiplayer`
3. any classname containing `door` (`func_door`, `func_door_rotating`)

Buttons and triggers found by Hammer ID are additionally validated against the weapon by walking
the parent chain, because several items of the same kind can exist on one map.

**Compare and relay change how a use is counted.** When an item has either of them, the button
press is passed straight through and the use is counted from the entity output instead. That is
how maps with conditional activation report a *real* use rather than an attempted one — if the
map's condition fails, no output fires and nothing is counted.

**Legacy map-side protection keeps working.** Many maps implement their own owner check: on
`OnPressed` they fire `TestActivator` at a `filter_*` entity that compares `targetname`. Before
letting a press through, entWatch writes the config's `filter` value into the owner's
`targetname`, so those maps keep functioning unchanged.

---

## Item modes

`mode` decides what the plugin enforces beyond ownership, and what the HUD shows.

| Mode | GFL `mode` | UNLOZE `mode` | Behaviour |
|---|---|---|---|
| `PROTECT` | 1 | 0 | Ownership only. No cooldown, no use limit. Use messages are forced off. |
| `COOLDOWN` | 2 | 1 | `cooldown` seconds after every use. |
| `MAXUSES` | 3 | 2 | `maxuses` uses in total, no cooldown. |
| `MAXUSESCD` | 4 | 3 | `maxuses` uses in total, plus `cooldown` between them. |
| `CHARGESCD` | 5 | 4 | `maxuses` charges, then one shared `cooldown`; the charges refill together. |

Any value above the last mode falls back to `PROTECT`. GFL configs are 1-based, UNLOZE configs
are 0-based — the plugin converts while reading, so a config written for either variant means
what its author intended.

HUD status markers per mode:

| Mode | While ready | While on cooldown | When spent |
|---|---|---|---|
| `PROTECT` | `[N/A]` | — | — |
| `COOLDOWN` | `[R]` | `[seconds]` | — |
| `MAXUSES` | `[used/max]` | — | `[D]` |
| `MAXUSESCD` | `[used/max]` | `[seconds]` | `[D]` |
| `CHARGESCD` | `[used/max]` | `[seconds]` | — |

An item whose button entity has been destroyed by the map is shown as `[D]` regardless of mode.

Readiness also honours the button itself: a locked button (`m_bLocked`) is never ready, and the
button's own `wait` is respected on top of the configured cooldown.

---

## Map configuration

One file per map: `addons/sourcemod/configs/entwatch/<mapname>.cfg`, the map name lowercased.
No file means the plugin simply has no items on that map.

Each subkey is one item. **The format is detected per block**, so a single file may mix them:

- the block has `hammerid` greater than zero → *GFL* format
- otherwise the block has `weaponid` greater than zero → *UNLOZE* format
- neither → the block is ignored

### Item keys

| Purpose | GFL | UNLOZE |
|---|---|---|
| Weapon Hammer ID | `hammerid` | `weaponid` |
| Trigger Hammer ID | `triggerid` | `triggerid` |
| Button Hammer ID | `buttonid` | `buttonid` |
| `logic_compare` Hammer ID | `compareid` | `compareid` |
| `logic_relay` Hammer ID | `relayid` | `relayid` |
| Full name | `name` | `name` |
| Short name (HUD, commands) | `shortname` | `short` |
| Colour | `color` | `color` |
| Filter targetname | `filtername` | `filter` |
| `point_template` name | `spawn` | `spawn` |
| Mode | `mode` (1-based) | `mode` (0-based) |
| Use limit | `maxuses` | `maxuses` |
| Cooldown, seconds | `cooldown` | `cooldown` |
| Announcements | `chat`, `activate`, `hud` | `display` (bitmask) |
| Weapon slot | `allowtransfer`, `forcedrop` | `slot` |

`cooldown` accepts fractions.

### Announcements

GFL blocks carry three independent switches, each defaulting to `1`:

| Key | Effect |
|---|---|
| `chat` | announce pick-up and drop |
| `activate` | announce every use |
| `hud` | show the item on the HUD |

UNLOZE blocks pack the same three into one `display` bitmask, defaulting to `7`:

| Bit | Value | Effect |
|---|---|---|
| 1 | 1 | chat |
| 2 | 2 | use |
| 3 | 4 | HUD |

`PROTECT` items always have the use announcement cleared, in either format.

### Slots

| Slot | UNLOZE `slot` | Can be dropped or transferred |
|---|---|---|
| None | 0 | no |
| Primary | 1 | yes |
| Secondary | 2 | yes (default) |
| Knife | 3 | **no** |
| Grenades | 4 | yes |

GFL blocks have no `slot` key — the slot is derived: if either `allowtransfer` or `forcedrop` is
set the item becomes *secondary*, otherwise *knife*.

Knife and none-slot items are never moved: zombies carry only knives, and dropping or
transferring one would take it away from its team for good.

### Per-map switches

Two keys sit at the **root** of the file, outside any item block:

| Key | Default | Effect |
|---|---|---|
| `hud` | 1 | HUD on this map |
| `assist_use` | 1 | assisted button pressing on this map |

### Example

```
"entities"
{
	"hud"		"1"
	"assist_use"	"1"

	// GFL format
	"Laser Gun"
	{
		"name"		"Laser Gun"
		"shortname"	"Laser"
		"color"		"{red}"
		"hammerid"	"119771"
		"buttonid"	"119773"
		"filtername"	"laser"
		"spawn"		"LaserSpawn"
		"mode"		"2"
		"cooldown"	"65"
		"chat"		"1"
		"activate"	"1"
		"hud"		"1"
		"allowtransfer"	"1"
	}

	// UNLOZE format
	"Frost Nova"
	{
		"name"		"Frost Nova"
		"short"		"Frost"
		"color"		"66CCFF"
		"weaponid"	"204411"
		"filter"	"frost"
		"mode"		"4"
		"maxuses"	"3"
		"cooldown"	"90"
		"display"	"7"
		"slot"		"2"
	}
}
```

---

## Colors

`addons/sourcemod/configs/entwatch/colors.cfg` is **mandatory** — the plugin refuses to load
without it. It sets the palette of every chat message:

| Key | Used for |
|---|---|
| `tagcolor` | the `[entWatch]` tag |
| `nickcolor` | player names |
| `othercolor` | the rest of the sentence |
| `itemcolor` | default item colour when a config gives none |

Values are six hex digits without a leading `#`.

An item's `color` accepts the same six hex digits, or a **named colour in braces** such as
`{red}`, `{gold}`, `{immortal}`. Over a hundred and fifty names are recognised, including the
team colours and the TF2 and Dota rarity palettes. An unknown name falls back to `itemcolor`.

Named colours are resolved in **GFL-format blocks only**; UNLOZE blocks take the hex value
literally.

---

## HUD

A single one-second timer builds the display for all clients as `KeyHintText`.

- Only items that have an owner and the HUD flag are listed.
- One line per item: `<shortname><status>: <owner>`.
- Three separate buffers are built — one for spectators and everyone, one for T, one for CT — so
  a team never sees the other side's items.
- Each buffer holds up to four pages; the pages rotate every five seconds.
- Visibility is per client, saved in the `entwatch_display` cookie and toggled with `sm_hud`.
- Bots, SourceTV included, do not receive it.

---

## Chat announcements

Announcements are scoped to the owner's team, coloured with the item's colour, and gated by the
item's display flags.

| Event | Gated by |
|---|---|
| picked up | chat |
| dropped | chat |
| used | use (always off for `PROTECT`) |
| owner died | chat |
| owner disconnected | chat |

Admin actions — transfer, spawn, forced use — announce separately and are not silenced by these
flags.

---

## Restrictions

A restricted ("ebanned") player must not obtain an item by **any** route, so the check sits on
every path at once:

- picking the weapon up off the ground,
- pressing the item's button,
- touching the item's trigger (maps often use a strip- or teleport-trigger to hand over knives),
- receiving an item through an admin transfer.

The same applies to zombiereloaded "half-zombie" classes when that integration is compiled in.

### Two kinds of restriction

**Database-backed.** `sm_eban <player> <minutes>` for an online player, `sm_addeban` for someone
who is not connected. Matched by both Steam account ID and IP, so a reconnect or a name change
does not shake it off. The duration is either `-1`, which never expires, or a length under a
year — anything else is refused.

**Temporary — until the map changes.** `sm_eban <player>` with no duration. These live in memory
only, never reach the database, and therefore keep working when the database is down. They are
keyed by account, so rejoining does not clear one. `sm_uneban` removes a temporary restriction
without touching the database.

**No database means no restrictions.** If the connection fails, restriction checks pass everyone
— an item server that cannot reach its database should still be playable.

### Storage

Table `ebans`, created on connect. MySQL is used when `databases.cfg` contains an `entwatch`
block; otherwise the plugin falls back to SQLite.

| Column | Meaning |
|---|---|
| `pid` | player's Steam account ID (`0` for an IP-only entry) |
| `pname` | player's name at the time |
| `pip` | player's IP |
| `aid` | admin's Steam account ID |
| `aname` | admin's name |
| `duration` | length in minutes |
| `expires` | Unix time when it lapses, or `-1` for permanent |

`sm_status` reports your own restriction, or someone else's with a target argument.

---

## Admin menu and the live config editor

`sm_eadmin` opens the admin menu: restrictions, item transfer, forced use, and the config editor.

The editor changes `Configs[]` in place — the item you are editing reacts immediately — and can
write the result back to `addons/sourcemod/configs/entwatch/<mapname>.cfg`. It saves each block
in the format that block was read as, so editing a GFL config does not silently convert it.

Only one admin may hold the editor at a time; a second one is told it is busy. The lock is
released when the menu is closed or the admin leaves.

---

## Spawning items

If a config has a `spawn` key naming a `point_template` on the map, the item can be created on
demand: `sm_espawn <shortname> [receiver]` builds an `env_entity_maker` at the receiver's feet,
fires it once and removes it. Without a receiver the item is spawned on the admin.

This works only for maps that keep their items in a template — `spawn` names that template, not
the weapon.

---

## Runtime tuning from map configs

Three server commands let a map config or a stripper config adjust items after the map has
loaded. They are server-console only and every rejection is written to the SourceMod log, since
nobody would see a chat error.

| Command | Effect |
|---|---|
| `sm_setcooldown <weapon hammerid> <seconds>` | change an item's cooldown |
| `sm_setmaxuses <weapon hammerid> <count>` | change an item's use limit |
| `sm_decuses <weapon hammerid>` | give one use back to a live item |

`sm_setcooldown` and `sm_setmaxuses` address the *config* by the weapon's Hammer ID and so work
before the item exists; `sm_decuses` addresses a *live* item and needs one on the map.

---

## Commands

| Command | Access | Purpose |
|---|---|---|
| `sm_status [target]` | everyone | own or target's restriction status |
| `sm_hud` | everyone | toggle the HUD, remembered per client |
| `sm_eban <target> [minutes]` | generic | restrict a player; no duration means until the map changes |
| `sm_uneban <target>` | generic | lift a restriction |
| `sm_addeban <minutes> [steamid] [ip]` | rcon | restrict someone who is not connected |
| `sm_deleban [steamid] [ip]` | rcon | lift a restriction offline |
| `sm_eadmin` | generic | admin menu |
| `sm_etransfer <owner\|$shortname> <receiver>` | generic | move an item to another player |
| `sm_euse <owner\|$shortname>` | ban | fire someone's item for them |
| `sm_espawn <shortname> [receiver]` | ban | spawn an item from its template |
| `sm_assistuse` | rcon | toggle assisted button pressing |
| `sm_edump` | rcon | dump configs and live items to console |
| `sm_setcooldown` / `sm_setmaxuses` / `sm_decuses` | server console | runtime tuning, see above |

`$shortname` addresses an item directly instead of naming its owner — useful when the item is
lying on the floor.

---

## Optional subsystems

Four subsystems are compile-time switches. All are on in the shipped build; each can be turned
off without affecting the rest.

| Switch | What it adds |
|---|---|
| `HUD` | the `KeyHintText` display and `sm_hud` |
| `ASSIST_USE` | assisted button pressing, `sm_assistuse`, `sm_euse` |
| `ADMIN_MENU` | `sm_eadmin` and the live config editor |
| `HALFZOMBIE` | zombiereloaded integration: half-zombie classes may not hold items |

**Assisted use** is worth a note. Pressing `+USE` does not reliably activate an item — the
crosshair may land on a wall, or the button may need a jump to line up. With this subsystem the
plugin presses the button for the player. It stands down when the player is aiming at a real map
button or door (that would double-trigger it), when a non-item button was pressed in the same
tick, and when the player is carrying more than one item.

---

## API

`addons/sourcemod/scripting/include/entWatch.inc`

```sourcepawn
#include <entWatch>
```

### Natives

| Native | Returns |
|---|---|
| `entWatch_IsConfigLoaded()` | whether the current map has a config with at least one item |
| `entWatch_IsDatabaseLoaded()` | whether the database is connected and the schema is ready |
| `entWatch_IsClientLoaded(int client)` | whether this client's restriction lookup has finished |
| `entWatch_GetConfigsCount()` | number of item configs on this map |
| `entWatch_GetItemsCount()` | number of live items right now |
| `entWatch_GetConfig(int config, any[] cache, int size = sizeof(Config))` | copies a config out; `false` on a bad index or size |
| `entWatch_GetItem(int item, any[] cache, int size = sizeof(Item))` | copies a live item out; `false` on a bad index or size |
| `entWatch_ClientHasItem(int client)` | whether the client owns at least one item |

### Forwards

| Forward | Fired when |
|---|---|
| `entWatch_OnConfigLoaded()` | the map's item config has been parsed |
| `entWatch_OnDatabaseLoaded()` | the database is connected and ready |
| `entWatch_OnClientLoaded(int client)` | a client's restriction state is known |
| `entWatch_OnClientItemUse(int client, int item)` | an item was used |
| `entWatch_OnClientItemDrop(int client, int item)` | an item left its owner — dropped, died, disconnected, or transferred |
| `entWatch_OnClientItemPickup(int client, int item)` | an item was picked up |

### Structures

`entWatch_GetConfig` and `entWatch_GetItem` copy these out by value.

`Config` — static, parsed from the map config:

| Field | Meaning |
|---|---|
| `Type` | which format the block was read as |
| `Weapon_HammerId`, `Trigger_HammerId`, `Button_HammerId`, `Compare_HammerId`, `Relay_HammerId` | entity bindings |
| `Name`, `ShortName` | display names |
| `Color` | chat colour, `#RRGGBB` |
| `Filter` | targetname written to the owner for map-side filters |
| `Display` | announcement bitmask |
| `Slot` | weapon slot |
| `Mode`, `Maxuses`, `Cooldown` | usage rules |
| `Template` | `point_template` name for spawning |

`Item` — runtime state:

| Field | Meaning |
|---|---|
| `Config` | index into the config list |
| `Weapon`, `Trigger`, `Button`, `Compare`, `Relay` | entity indices, `0` when absent |
| `Owner` | client index, `0` when nobody holds it |
| `Uses` | uses or charges spent |
| `Cooldown` | game time at which the cooldown lapses |
| `Wait` | game time at which the button's own wait lapses |
| `Transfered` | whether an admin moved it |
| `RemovedButton` | whether its button entity is gone |

### Example

```sourcepawn
#include <sourcemod>
#include <entWatch>

public void entWatch_OnClientItemUse(int client, int item)
{
    Item info;

    if (!entWatch_GetItem(item, info, sizeof(info)))
        return;

    Config cfg;

    if (!entWatch_GetConfig(info.Config, cfg, sizeof(cfg)))
        return;

    PrintToChatAll("%N used %s (%i uses spent)", client, cfg.Name, info.Uses);
}
```

### Compatibility

Item indices are **not stable** — removing an item shifts the list, so an index handed to a
timer or stored across frames may mean a different item by the time it is read. Resolve indices
when you need them rather than keeping them.

Both structures are copied out by value with a runtime size check, which makes their layout part
of the API: if a field is ever added or reordered, every consuming plugin has to be rebuilt.
Native and forward signatures do not change.
