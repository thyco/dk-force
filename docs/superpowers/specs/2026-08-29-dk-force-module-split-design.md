# DK Force — Core.lua module split

Design for phase two of the DK Force fork: breaking the surviving `Core.lua`
into per-feature modules. Deferred by
`2026-08-29-dk-force-design.md` under **Out of scope** until a working build
existed to diff against. That condition is now met — every feature has been
verified in game, and `verify.sh` gained a behavioural spec for the one feature
the fork exists to protect.

## Goal

`Core.lua` is 1466 lines holding five unrelated features plus shared
infrastructure. Splitting it into named modules makes each feature small enough
to hold in view, and makes it obvious which file a change belongs in.

**This is a pure move. No behaviour changes.** Any behavioural difference after
the split is a defect, not an improvement.

## Scope

In scope: `Core.lua` only.

Out of scope: `Config.lua` (947 lines). It just lost 148 lines of dead code and
its entire glow-slider subsystem, so it is already smaller; splitting two large
files in one change doubles the surface area of a restructure that cannot be
verified by eye. Revisit separately if it still grates.

## Target layout

| File | Responsibility | ~lines |
| --- | --- | --- |
| `Core.lua` | `SPELLS`, `DEFAULT_DB`, spec helpers, CDM rescan entry points, `StopAll`, the event dispatcher, welcome popup, DB init, slash commands | ~420 |
| `Glow.lua` | `GLOW_TYPES`, `GLOW_TYPE_MAP`, `GetGlowTypeByID`, `CreateOverlay` | ~80 |
| `Festering.lua` | Festering Scythe overlays, timers, Lesser Ghoul watcher, cast handlers | ~255 |
| `SuddenDoom.lua` | Sudden Doom overlays, `IsSuddenDoomActive`, show/stop, the 0.1s watcher | ~145 |
| `BloodDnD.lua` | The Stand In Death and Decay subsystem, including its watcher | ~175 |
| `Blightfall.lua` | Talent ids, the chain state machine, the icon frame, `/dkf blight` | ~290 |

## Move map

Line ranges refer to `Core.lua` at commit `1c426dc` and are a guide, not a
contract; the authority is the named definition.

| Current lines | Definitions | Destination |
| --- | --- | --- |
| 1–62 | `LCG`, `addon.SPELLS` | `Core.lua` |
| 64–102 | `GLOW_TYPES`, `GLOW_TYPE_MAP` | `Glow.lua` |
| 103–168 | `DEFAULT_GLOW_SETTINGS`, `DEFAULT_DB` | `Core.lua` |
| 169–174 | `GetGlowTypeByID` | `Glow.lua` |
| 176–181 | shared declaration block | split across `Festering.lua`, `SuddenDoom.lua`, `BloodDnD.lua` |
| 183–196 | `GetActiveSpecID`, `IsBloodSpec`, `IsUnholySpec` | `Core.lua` |
| 198–221 | `BLIGHTFALL_TALENT_ID`, `IsBlightfallTalented`, `SOUL_REAPER_TALENT_ID`, `IsSoulReaperTalented` | `Blightfall.lua` |
| 223–238 | `GetSuddenDoomOverlaySettings`, `SuddenDoomEnabled` | `SuddenDoom.lua` |
| 240–263 | `CreateOverlay` | `Glow.lua` |
| 265–287 | `CreateFesteringOverlays` | `Festering.lua` |
| 289–317 | `CreateSuddenDoomOverlays`, `RegisterCDMSuddenDoomFrame` | `SuddenDoom.lua` |
| 319–324 | `RegisterCDMDnDBuffFrame` | `BloodDnD.lua` |
| 326–333 | `RegisterCDMFesteringFrame` | `Festering.lua` |
| 335–345 | `CreateCDMOverlays`, `CreateCDMOverlaysAdditive` | `Core.lua` |
| 347–569 | Festering constants, timers, glow control, cast handlers, ghoul watcher | `Festering.lua` |
| 571–654 | `IsSuddenDoomActive`, show/stop/refresh/test | `SuddenDoom.lua` |
| 656–660 | `StopAll` | `Core.lua` |
| 662–829 | Stand In Death and Decay, including `dndMissingWatcher` | `BloodDnD.lua` |
| 831–1092 | Blightfall chain state, icon frame, cast handler, test | `Blightfall.lua` |
| 1094–1122 | `castFrame` event dispatcher | `Core.lua` |
| 1124–1138 | `suddenDoomWatcher` | `SuddenDoom.lua` |
| 1140–1201 | `ShowWelcomePopup` | `Core.lua` |
| 1203–end | `initFrame` DB init, slash commands | `Core.lua` |

The `/dkf blight` diagnostic currently sits inside the slash handler in the
tail. Its body moves to `Blightfall.lua` as `addon:PrintBlightfallDiagnostic()`,
because it reads `blightState` and `blightIconFrame`, which become file-locals
there. The slash handler keeps the `elseif cmd == "blight"` branch and calls it.

## Cross-module coupling

Only two names cross a module boundary today. Both are file-locals that must
become methods on the shared `addon` table.

**`CreateOverlay`** — defined in `Core.lua`, called from Festering, Sudden Doom
and Blood D&D code at seven sites. Becomes
`addon:CreateOverlay(targetFrame, spellKey)` in `Glow.lua`.

**Festering locals reached from Core** — `StopAll` calls the local
`StopFesteringGlow`, and the event dispatcher calls the locals
`OnFesteringCombatStart` and `OnFesteringCombatEnd`. All three become `addon:`
methods. This makes Festering consistent with its siblings, which already expose
`addon:StopSuddenDoomGlows` and `addon:StopDnDMissingGlow`.

Everything else already crosses through the `addon` table. The shared
declaration block at lines 176–181 splits cleanly: each of
`festeringOverlays`, `cdmFesteringOverlays`, `suddenDoomOverlays`,
`cdmSuddenDoomOverlays`, `suddenDoomActive` and `bloodDnDBuffFrame` is used by
exactly one feature, and moves into that feature's file as a file-local.

## The event dispatcher

A single `castFrame` in `Core.lua` registers `UNIT_SPELLCAST_SUCCEEDED`,
`PLAYER_REGEN_ENABLED`, `PLAYER_REGEN_DISABLED` and `PLAYER_TALENT_UPDATE`, then
fans out to Festering, Blightfall and Sudden Doom.

**It stays in `Core.lua` as a thin dispatch layer.** The handler body is
explicit about ordering — within one `UNIT_SPELLCAST_SUCCEEDED` it runs the
Festering handlers and then the Blightfall one — and a reader can see the whole
fan-out in one place.

Rejected: giving each module its own event frame. It is more decoupled on paper,
but several frames would register the same events and the order in which
features respond would become an accident of TOC load order rather than a
statement in code. For a restructure whose stated goal is no behaviour change,
preserving explicit ordering outweighs the decoupling.

## Load order

```
Core.lua          -- SPELLS, DEFAULT_DB, spec helpers
Glow.lua          -- needs nothing; provides GLOW_TYPES and CreateOverlay
Festering.lua
SuddenDoom.lua
BloodDnD.lua
Blightfall.lua
ButtonScanner.lua
Config.lua        -- reads addon.GLOW_TYPES, so must follow Glow.lua
MinimapButton.lua
CDMHook.lua
```

Module bodies only *define* functions and create frames; nothing calls across
modules at load time, so this order is a readability choice rather than a
dependency chain — with the single exception of `Config.lua`, which iterates
`addon.GLOW_TYPES` when building the panel.

## Verification

The existing harness covers most of the risk of a pure move:

- **Checks 2 and 3** enforce TOC/disk agreement in both directions, so a new
  file that is not listed — meaning it would silently never load in game — fails
  immediately.
- **Check 8, leaked globals**, catches a function moved without its declaration.
  That is the single most likely defect in this restructure: a file-local left
  behind reads as a global at runtime, and both `grep` and `luac -p` miss it.
- **Check 7, the D&D behavioural spec**, is repointed from `Core.lua` to
  `BloodDnD.lua` and must still pass all ten assertions. This is the strongest
  evidence available without loading the game.
- **Check 5 must not be used here.** It fails if any name in
  `removed-symbols.txt` appears anywhere under `DKForce/`. The promoted names —
  `StopFesteringGlow`, `OnFesteringCombatStart`, `OnFesteringCombatEnd` — still
  exist, as methods, so listing them would fail the build. Nothing is deleted by
  this move, so `removed-symbols.txt` is not touched at all.

Beyond the harness: an in-game smoke test of each of the five features, since
"it parses and the D&D logic is unchanged" does not prove that, say, the
Festering timer still fires.

## Risks

**A local moved without its declaration.** Mitigated by check 8, which was built
for exactly this and has caught it before.

**The D&D spec silently testing nothing.** It locates the subsystem by a header
comment and the first `end)` after it. If the header is reworded during the
move, the slice fails loudly by design rather than passing vacuously — this was
proven by mutation test before the check was trusted.

**Load-order mistakes.** Low: nothing runs across modules at load time except
`Config.lua`'s read of `addon.GLOW_TYPES`.

## Out of scope

- `Config.lua`, as above.
- Any behaviour change, tidy-up or renaming beyond the promotions in
  **Cross-module coupling**.
- Further test coverage. The other four features have no behavioural spec; adding
  them is worthwhile but is its own piece of work, not part of this move.
