# DK Force — Putrefy rotational cue

Design for a new feature: glow Putrefy while Dark Transformation is active,
desaturate it while it is not.

Putrefy is castable at any time — Blizzard does not gate it. Casting it outside
Dark Transformation is simply a DPS loss. This is therefore a **rotational**
cue, not a usability one, and no amount of `IsSpellUsable` will produce it.

## Goal

Make one button answer "is pressing this right now correct?" at a glance, for a
player who drives the whole Dark Transformation → Putrefy chain from a single
`/castsequence` macro:

```
#showtooltip
/castsequence reset=20/shift/combat dark transformation,putrefy,putrefy,…
```

## Behaviour

The rule is **glow when the next cast is the right thing to press, desaturate
when it is not**. Which test applies depends on which spell the button is about
to cast:

| Next cast | Glow when | Desaturate when |
| --- | --- | --- |
| Putrefy | the Dark Transformation buff is active | it is not |
| Dark Transformation | Dark Transformation is off cooldown and usable | it is not |
| anything else, or unknown | — | — (undecorated) |

Resources are deliberately **not** part of the test. Being short on runes reports
`isUsable = false, insufficientPower = true`; that counts as allowed. Runes cycle
several times per rotation, and folding them in would make the button flicker
between glowing and grey continuously. Blizzard already shades an unaffordable
button.

The glow is combat-only; the desaturation is not. Confirmed with the author, and
it follows the rule already documented in `Festering.lua`: a glow is an
interrupt and demands attention now, so out of combat it is noise, while a
desaturation reads as a standing "not this one" and is useful while setting up.
Out of combat the button is therefore either greyed or plain, never glowing.

### The decision is per frame, not per feature

Every existing feature decides once and applies the answer everywhere. This one
cannot. When the sequence sits on Dark Transformation with DT off cooldown, the
action-bar button should glow while the Cooldown Manager's Putrefy icon should
be grey — Putrefy genuinely is not the right press yet. They are showing
different spells, so they get different answers **in the same tick**.

This is the one structural novelty in the feature, and it is the case the spec
must pin down.

## Detection

### Is Dark Transformation active?

Watch the visibility of its Cooldown Manager buff icon. Confirmed present in the
target setup:

```
BuffIcon  cooldownID=1233448  itemID=1233448  shown=false  Dark Transformation
```

Not by reading the aura. Lesser Ghoul stacks and the Death and Decay buff both
went secret in 12.1, and both features were rewritten onto icon visibility for
exactly this reason. Not by timing from the cast either: that is what the
deleted Putrefy feature did, it drifts whenever a talent changes the duration,
and it is wrong after a reload mid-buff.

Three states, as in `EvaluateGhoulState`:

- `nil` — no buff row ever registered. Nothing is known, so nothing is claimed.
- `false` — registered and hidden. Dark Transformation is down.
- `true` — registered and shown. Dark Transformation is up.

**The buff row reports the ability ID (1233448), not an aura ID.** An ability row
for Dark Transformation would report the same value, exactly as Soul Reaper
appears twice in the dump (`Essential 343294` and `BuffIcon 343294`).
`CDMHook.IsBuffViewerItem` already disambiguates by viewer ownership — written
when Death and Decay hit this — and Putrefy reuses it rather than assuming the
row is unique.

### Is Dark Transformation off cooldown?

`C_Spell.IsSpellUsable(1233448)` and `C_Spell.GetSpellCooldown(1233448)`,
both under `pcall`. Neither is protected, and neither needs a Cooldown Manager
entry — which matters, because the target setup has no Dark Transformation
*ability* row, only the buff row. A cooldown `duration <= 1.5` is the global
cooldown and does not count.

### What will this button cast next?

`ButtonScanner`'s private `GetButtonSpellID` already answers this: for a macro
action slot it calls `GetMacroSpell`, which returns the spell the
`/castsequence` is *currently* on. It becomes public. Putrefy calls it per
tracked button per tick; for one to three buttons at 10 Hz that is noise.

### Finding the button at all

Spell-ID matching cannot find this button reliably. The scan runs at login and
on rescans, so whether the macro resolves to Dark Transformation or Putrefy at
that instant is a matter of timing.

`ButtonScanner` therefore also reads `GetMacroBody` for macro slots and matches
it against spells that opt in with a new `macroMatch` field on their `SPELLS`
entry, case-insensitively. **Only Putrefy opts in.** Dark Transformation must
not, or the same button would be tracked under two keys.

## Architecture

### New: `Dim.lua`

`addon:NewDimGroup(spec)`, parallel to `addon:NewGlowGroup` in `Glow.lua`. It
owns what `ScourgeDim.lua` owns today — the bar and CDM record tables,
`AttachDimTexture`, `CacheIcon`, `ApplyDim` — plus the same lifecycle the glow
group has: `Show`, `Hide`, `ClearBarOverlays`, `BuildBarOverlays`,
`RegisterCDMFrame`, `UnregisterCDMFrame`.

`ScourgeDim.lua` becomes a thin feature file declaring one group, as
`SuddenDoom.lua` now does. **This half is a pure move. Any behavioural
difference in the Scourge Strike desaturation is a defect.**

`GlowGroup` and `DimGroup` are deliberately **not** unified behind a shared
base. Their payloads differ in a way that reaches the lifecycle: a glow overlay
is a child Frame that gets `SetParent(nil)` on teardown, while a dim texture
cannot be unparented at all and is cached on the button for reuse across
rescans. With two instances the shared base would be thinner than the
difference. A third decoration type is when to revisit.

### Changed: `Glow.lua` and `Dim.lua` — an optional predicate on `Show`

```lua
group:Show(shouldDecorate)   -- nil predicate means "all", as today
```

The predicate receives the **target frame**, not the overlay or the record, so
callers stay independent of each group's internal shape. Frames the predicate
rejects are cleared and hidden — the generalisation of the existing
`clearHiddenTargets` behaviour.

Additive: a nil predicate preserves today's behaviour exactly, and the existing
171 checks hold that in place.

### New: `Putrefy.lua`

Owns one glow group, one dim group, the 0.1 s watcher, the Dark Transformation
buff-row registration, and the pure predicate:

```lua
-- nextCast: "putrefy" | "darkTransformation" | nil
-- dtBuffShown: true | false | nil   (nil = no buff row registered)
-- dtReady: is Dark Transformation usable and off cooldown
function addon:EvaluatePutrefyState(settings, nextCast, dtBuffShown, dtReady, inCombat)
    -> glow, dim   -- always real booleans, never a stray nil from an `and` chain
end
```

A method rather than a file-local so the spec can call it directly, exactly as
`EvaluateGhoulState` is. `glow` and `dim` are never both true.

### Changed: `ButtonScanner.lua`

- `GetButtonSpellID` becomes `addon:GetButtonSpellID`.
- Macro slots additionally match `GetMacroBody` against `SPELLS` entries
  carrying `macroMatch`.
- `ScanAllButtons` calls `addon:CreatePutrefyOverlays`.

### Changed: `CDMHook.lua`

- `addon:IsPutrefyEnabled()` joins `AnyFeatureWantsCDM`.
- `Classify` gains two branches: `putrefy` for spell 1247378, and
  `darkTransformationBuff` for 1233448 **when `IsBuffViewerItem` confirms it**.
- `DISPATCH` gains `addon:RegisterCDMPutrefyFrame` and
  `addon:RegisterCDMDarkTransformationBuffFrame`.

### Changed: `Core.lua`

- `SPELLS.PUTREFY = { id = 1247378, name = "Putrefy", key = "putrefy",
  macroMatch = "putrefy" }`.
- `DEFAULT_DB.putrefy` (below).
- `addon:StopAll` stops the Putrefy cues.

### Changed: `Config.lua`

A Putrefy page following the existing `BuildGlowPage` shape: enable, separate
glow and desaturate toggles, colour, Test.

The Test button ignores both the combat gate and the Dark Transformation state,
as every other Test here does: it is a preview of what the cue looks like, not a
reminder. It lights every visible target and reports the count.

## Settings

```lua
putrefy = {
    enabled     = false,   -- new features ship off, as bloodDndMissing does
    glow        = true,
    dim         = true,
    nativeColor = true,
    color       = { r = 0.0, g = 0.9, b = 0.2 },
}
```

`nativeColor` defaults true and is the setting that matters: passing any colour
to LibCustomGlow desaturates the artwork before tinting it, so only a nil colour
looks like Blizzard's own proc glow. The `color` values are the same green the
other glow features default to, and are only reached if `nativeColor` is turned
off.

Separate `glow` and `dim` toggles mirror `lesserGhoulGlow` / `lesserGhoulDim`:
either, both or neither, so someone who finds the grey heavy can keep just the
glow. `enabled` is the master switch, and `CDMHook` gates registration on it —
the same switch the display reads from, never a second copy.

## Data flow, per tick

```
if not enabled           -> clear both groups, done
dtBuffShown = buffRow and buffRow:IsShown()        -- nil when unregistered
dtReady     = usable(DT) and not onRealCooldown(DT)

for each decorated frame:
    nextCast = frame is a CDM Putrefy icon and "putrefy"
               or classify(addon:GetButtonSpellID(button))
    glow, dim = addon:EvaluatePutrefyState(settings, nextCast,
                                           dtBuffShown, dtReady,
                                           InCombatLockdown())

glowGroup:Show(frame -> decision[frame].glow)
dimGroup:Show(frame -> decision[frame].dim)
```

## Testing

`verify.sh` check 7 runs every `tests/*_spec.lua`, so new specs need no edit to
the harness.

### `tests/scourge_dim_spec.lua` — written and mutation-tested BEFORE the move

`ScourgeDim.lua` has zero coverage today and the extraction moves its guts. This
is the same standard the glow-group extraction was held to: a pure move is only
verifiable if a spec exists to verify it against.

Requires teaching `tests/wow_stub.lua` about textures — `CreateTexture`,
`SetDesaturated`, `SetTexCoord`, `SetVertexColor`, `GetDrawLayer`, and
`AddMaskTexture` / `GetNumMaskTextures`. The mask inheritance is the part that
took longest to get right and is the part most worth protecting.

### `tests/putrefy_spec.lua`

- the predicate as a pure function: every row of the behaviour table above
- **the divergence case** — sequence on Dark Transformation with DT ready: the
  action-bar button glows while the Cooldown Manager's Putrefy icon is grey, in
  one tick. This is why the per-frame predicate exists.
- glow and dim are never both applied to one frame
- no Dark Transformation buff row registered → silent, not wrong
- the combat gate on the glow, and its absence on the desaturation
- macro-body matching: a button whose macro mentions Putrefy is tracked, one
  that does not is not, and Dark Transformation does not claim the same button
- lifecycle: rescan, duplicate CDM registration, disabled registration, Test

Every assertion proven to fail against a deliberately broken copy before the
spec is trusted, via the `DKFORCE_*_SOURCE` overrides.

## `removed-symbols.txt`

The deleted Putrefy feature left 26 entries. Retire **only** the names this
design reuses:

```
CreatePutrefyOverlays
RegisterCDMPutrefyFrame
PUTREFY_SPELL_ID
putrefyOverlays
cdmPutrefyOverlays
BuildPutrefyPage
```

Everything else stays: `ShowPutrefyHoldWarning`, `putrefyDurationTimer`,
`DARK_TRANSFORMATION_BASE_DURATION` and the rest describe the warning-window
approach, which stays dead and must keep failing the gate if it reappears.

Removing a line from that file is a deliberate act, which is why it is listed
here rather than done quietly during implementation.

## Implementation phasing

Two halves, each independently verifiable, in this order:

1. **The `Dim.lua` extraction.** Spec `ScourgeDim.lua` first, mutation-test that
   spec, then move. Ends with `verify.sh` green and the Scourge Strike
   desaturation behaving identically. Nothing about Putrefy is touched.
2. **The Putrefy feature.** Everything else.

Half one is a pure move that stands on its own; half two depends on it. Keeping
them separate means a regression in the Scourge Strike desaturation cannot hide
inside a new feature's diff.

## Out of scope

- Unifying `GlowGroup` and `DimGroup`.
- Any behaviour change to the Scourge Strike desaturation.
- The Blightfall chain prompt, which also keys off Dark Transformation but
  answers a different question and stays as it is.
- Reacting to the macro being edited mid-session. A rescan picks it up; the
  existing rescan triggers are enough.

## Risks

**The buff row flipping to `shown = true` while Dark Transformation is active
is confirmed**, verified in game on 2026-08-30 — `shown = false` with no buff
up, `shown = true` with it. The whole detection rests on this, so it was checked
rather than assumed. The Death and Decay reminder rests on the same property.

**`GetMacroBody` returns nil for a macro that does not exist yet.** Handled the
way everything else here is: `pcall`, and treat a failure as "not a match".

**A second macro mentioning Putrefy** would also be tracked. That is arguably
correct, and the per-frame decision handles it: each button is judged on what it
is about to cast.
