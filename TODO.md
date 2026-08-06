# TODO

What is left, and what was deliberately left alone. History of completed work lives in
`WORK-STATE.md`; the audit report itself is `AUDIT.md`.

## Verification debt

Everything since `1.0.3` is verified **by compilation only**. Neither `1.1.0` nor `1.1.1` has
been exercised on the live server. Worth walking through once:

- temporary restrictions — grant with `sm_eban <player>` and no duration, check `sm_status`,
  lift with `sm_uneban`, confirm they survive a reconnect and die on a map change;
- the config editor — open, edit a field, save, reopen; confirm a second admin is told it is
  busy and that the lock releases when the first one leaves.

## Planned

- **Redesign the `ebans` schema** — normalized and indexed, fit for the planned web panel. The
  table is owned by this plugin alone, so there is no legacy to preserve and the layout may
  change freely.
- **Continue the restyle** towards the target SourcePawn style, surgically rather than in one
  sweep. The codebase is transitional: `#pragma semicolon 1` is still missing, indentation mixes
  tabs and spaces.

## From the cooldown / map-sync study

The study concluded with **no code change**: there is no general way to observe whether an item
actually fired, so the plugin keeps predicting. Details and the reasoning are in
`entwatch-cooldown-sync.md`. What remains open:

- **Measure before changing anything.** How often does the engine silently drop a press the
  plugin allowed? Hook `OnPressed` on the item button, compare against what was allowed, log the
  misses with the button state. Nothing in the study justifies a code change until that number
  exists.
- **`Configs[].Cooldown` versus what the map really does** is the suspected main source of false
  cooldowns — especially on maps with per-level items, where the real cooldown varies while the
  config carries a single number. Where a map exposes its own logic, moving such items onto
  `compareid` / `relayid` replaces the guess with an observation.
- **Do not gate readiness on `m_toggle_state` alone.** A toggle button (`spawnflags & 32`) rests
  at `TS_AT_TOP`; the rule "ready only at `TS_AT_BOTTOM`" has already killed items on
  `ze_industrial_dejavu`. The full acceptance rule is in the knowledge base,
  `engine/func-button.md`.
- **Mind which clock a timestamp came from.** `GetGameTime()` inside `SDKHook_Use` is the
  *player's* clock, up to 120 ms ahead of the server tick, while timers and entity-output hooks
  run on the server's. `Items[].Cooldown` is therefore written and read on different clocks
  depending on the path — knowledge base, `engine/player-timebase.md`.

## Small things

- `{name}` colours are resolved only in GFL-format config blocks; UNLOZE blocks take `color`
  literally (`entWatch/config.sp`). Most likely an oversight rather than a decision.
- The HUD marker `[D]` means two different things: "uses spent" and "the button entity is gone".
- `CLAUDE.md` still states the version is `1.0.1`.

## Deliberately not done

- `OnTriggerTouch` suppresses `EndTouch` — left as is.
- Build-time warts (`REEQUIRE_PLUGIN`, `HALFZOMBIE` without ZR, `#warning`) — left as is.
- Dead code, marked but kept: `ItemsGetByName`, `ConfigGetByName`, `ConfigGetByNames`.
- Duplicate keys in `entWatch.phrases.txt` (`Map`, `Unban item`) — pre-existing.
- Old `ebans` rows with `pname` / `aname` swapped are not migrated; only the code was fixed.
