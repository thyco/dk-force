# DK Force — design

Date: 2026-08-29
Status: approved for planning

## Purpose

`dk-force` is a personal Death Knight addon derived from **DK Assist Community**
(itself a fork of **DK Assist** by ZachoWOW). It exists for two reasons:

1. **The Stand In Death and Decay reminder must keep working.** The upstream
   author declined the contribution, and upstream's own implementation of the
   same idea does not work. Every future upstream merge is therefore a standing
   risk to the one feature that motivated the fork.
2. **Most of upstream is unwanted.** Roughly two thirds of the codebase serves
   features and a settings shell that will never be used.

`dk-force` is not intended for distribution, and carries no obligation to track
upstream. Upstream work may be cherry-picked when it is wanted; nothing is
merged wholesale.

## Scope

### In

| Feature | Spec | Origin |
|---|---|---|
| Festering Scythe glow — action bar or Cooldown Manager, expiry timing, combat-start reminder | Unholy | current fork |
| Lesser Ghoul reminder (glow variant) | Unholy | current fork |
| Sudden Doom glows — Death Coil and Epidemic | Unholy | current fork |
| Blightfall & Soul Reaper icon prompt | Unholy / San'layn | ported from upstream v2.0.0 |
| **Stand In Death and Decay** | Blood | current fork, preserved verbatim |
| Four glow styles — Pixel, Autocast Shine, Button, Proc Border | shared | current fork |
| Action Bar ↔ Cooldown Manager targeting, Rescan Bars, Test | shared | current fork |
| Settings window, minimap button, addon compartment, DataBroker, `/dkf` | shared | current fork |

### Out

Festering Scythe WA-style text alert; Sudden Doom WA-style text alert; Putrefy
hold warning; Runic Power cap warning; Death and Decay tracker window; Soul
Reaper glow control; Gargoyle tracker; Dark Transformation tracker; Bone Shield
reminder; Blood D&D readiness glow; all six alternate themes; all timeline
displays.

Two exclusions are deliberate reversals of upstream behaviour:

- **The Blood D&D readiness glow is dropped.** Glowing because Death and Decay
  is off cooldown is not wanted. The only wanted signal is "you are not standing
  in it", independent of cooldown.
- **All timeline lanes are dropped**, for both Blightfall and Death and Decay.

## Approach

**Strip-down fork.** Copy the working `DKAssist/` tree, rename the addon, delete
the excluded features, then port Blightfall's icon mode from upstream.

The alternative — a clean modular rewrite — was rejected on risk. The Stand In
Death and Decay subsystem depends on subtle Cooldown Manager frame-recycling and
aura-visibility behaviour that took real effort to get right, and reproducing it
from scratch is the most plausible route back to the upstream bug. A strip-down
concentrates all risk in deletions of features nobody wants, where a mistake is
cheap and immediately visible.

Splitting the surviving `Core.lua` into modules is deferred to an optional phase
two, after the addon has been played with and can be diffed against a known-good
build.

## Identity and coexistence

- Folder `DKForce/`, manifest `DKForce.toc`, title `DK Force`
- SavedVariables `DKForceDB`
- Slash command `/dkf`
- Addon compartment and minimap entries renamed to match

The namespace is disjoint from DK Assist's throughout, so both addons may be
installed simultaneously without either reading or writing the other's settings.

**No settings migration from `DKAssistDB`.** Settings are reconfigured once by
hand. A migration path would have to carry keys that are being deleted, for a
one-time benefit.

The MIT license is preserved with attribution to ZachoWOW for the original DK
Assist and to the community fork lineage.

## File layout

```
DKForce/
  DKForce.toc
  Libs/
    LibStub/LibStub.lua                  unchanged
    LibCustomGlow-1.0/...                unchanged
  Core.lua              ~2607 → ~1100 lines
  ButtonScanner.lua     unchanged
  CDMHook.lua           trimmed (both registration paths)
  Config.lua            ConfigV2.lua renamed, themes stripped: ~1861 → ~650 lines
  MinimapButton.lua     string renames only
  Media/Icon.png
```

Deleted without replacement:

| File | Size | Reason |
|---|---|---|
| `Config.lua` (legacy) | 68 KB | Dead panel superseded by `ConfigV2.lua`; byte-identical to upstream |
| `RunicPower.lua` | 8.7 KB | Runic Power cap warning is out of scope |
| `Enhancements.lua` | 5 KB | Not listed in the TOC — never loaded |

`ConfigV2.lua` is renamed to `Config.lua` once the legacy panel is gone, so the
surviving file carries the honest name.

## Core.lua deletions

Section boundaries in the current `DKAssist/Core.lua`:

| Lines | Section | Action |
|---|---|---|
| 1686–1967 | Death and Decay Tracker | delete |
| 1968–2143 | Death and Decay Buff Reminder (Blood) | **preserve** |
| 2144–~2238 | Soul Reaper Glow Suppression | delete |

Also removed: the text-alert subsystem (`DefaultTextAlert`, `EnsureTextAlertFrame`,
`RefreshTextAlert`, the Festering ticker and countdown, `SetFesteringGhoulTextAlert`,
`TestTextAlert`, `ShowTemporaryTextAlert`) and the Putrefy subsystem
(`CreatePutrefyOverlays`, `ShowPutrefyWarning`, `StopPutrefyWarning`,
`ShowPutrefyHoldWarning`, `RefreshPutrefyWarnings`, `TestPutrefyWarning`,
`OnDarkTransformationCast`, `RefreshDarkTransformationWindow`,
`OnDarkTransformationExtended`, `AttachCrossToOverlay`, `UpdateCrossAppearance`),
plus the Bone Shield reminder (`StopBloodBoneOverlay`, `StopBloodBoneReminder`,
`RefreshBloodBoneReminder`, `TestBloodBoneReminder`,
`RegisterCDMBloodBoneAbilityFrame`, `cdmBloodBoneOverlays`, the `bloodBone` DB key).

The Lesser Ghoul reminder has two independent outputs. `lesserGhoulGlow` drives
the action-bar/CDM glow and is kept; `ghoulMissingWarning` lives inside the text
alert settings and is removed with them.

## Stand In Death and Decay — preservation contract

This subsystem is the reason the project exists. It ships unchanged apart from
the two edits named below.

**Preserved verbatim:**

- `dndMissingWatcher` and its 10 Hz poll
- `DND_MISSING_GLOW_DELAY = 0.5` — the Cleaving Strikes grace period
- The detection expression:
  ```lua
  local missing = DnDMissingEnabled() and addon:IsBloodSpec() and bloodDnDBuffFrame
      and InCombatLockdown() and not bloodDnDBuffFrame:IsShown() or false
  ```
- `DnDMissingSettings`, `DnDMissingEnabled`, `ClearDnDMissingGlow`,
  `ApplyDnDMissingGlow`, `ShowDnDMissingGlow`, `StopDnDMissingGlow`,
  `CreateDnDMissingOverlays`, `RegisterCDMDnDMissingFrame`,
  `ClearCDMDnDMissingFrame`, `RefreshDnDMissingGlows`, `TestDnDMissingGlow`
- Both overlay tables, `dndMissingBarOverlays` and `cdmDnDMissingOverlays`
- The per-tick re-apply of `ShowDnDMissingGlow`. Its original justification —
  the readiness glow claiming and releasing the shared icon — disappears with
  that feature, but Cooldown Manager frames still recycle independently. It is
  retained deliberately as free insurance.

**Edit 1 — detection plumbing kept, readiness glow removed.**
`RegisterCDMBloodDnDBuffFrame` is the only part of the readiness feature this
subsystem needs: it captures `bloodDnDBuffFrame`, whose visibility *is* the
signal. It is renamed `RegisterCDMDnDBuffFrame` and keeps its
`ClearCDMDnDMissingFrame` call, which guarantees the detection source is never
decorated. Its readiness-overlay cleanup half is dropped along with
`cdmBloodDnDOverlays`.

Everything else in the readiness feature is deleted: `RefreshBloodDnDReminder`,
`StopBloodDnDReminder`, `TestBloodDnDReminder`, `StopBloodDnDOverlay`,
`RegisterCDMBloodDnDAbilityFrame`, `bloodDnDWatcher`, `bloodDnDReady`,
`bloodDnDReadyTimer`, `BLOOD_DND_COOLDOWN`, the Crimson Scourge aura check, and
the `bloodDnd` DB key and config page.

**Edit 2 — the yield guard is removed.**
`BloodDnDGlowActiveOn` and the `shared` parameter in `ShowDnDMissingGlow` exist
only to surrender the shared Cooldown Manager icon to the readiness glow. With
no readiness glow, the missing-glow always owns the icon. This is a behavioural
improvement: one fewer condition under which the warning goes silent.

## Blightfall & Soul Reaper — port

Ported from upstream `Core.lua` (v2.0.0), icon display only.

**Kept:** the Soul Reaper → Blightfall chain state machine; `soulReaperDelay` and
`blightfallDelay`; `BLIGHTFALL_GRACE`; `UpdateBlightfallIcon` with spell icon,
countdown, `NOW` state and ready-glow; optional TTS callout via
`BlightfallSpeak` with its `PlaySound` fallback; icon size, font size, lock,
glow style, colour, animation speed and opacity.

**Dropped:** the `blightFrame` timeline lane and everything serving it —
`timelineOrientation`, `showSpellNames`, the marker and its glow target, and the
timeline half of `ApplyBlightfallSettings`.

**Gate changed from hero spec to talent.** Upstream restricts the tracker to the
San'layn hero specialization:

```lua
C_ClassTalents.GetActiveHeroTalentSpec() == 31
```

This is a proxy that fails in one direction: a San'layn build that has not
talented Blightfall still receives prompts to press a spell it does not have.
`dk-force` gates on the talent itself:

```lua
IsPlayerSpell(1271967)   -- Blightfall
```

This is the same idiom upstream already uses for the Gargoyle tracker
(`IsPlayerSpell(GARGOYLE_TALENT_ID)`), and it survives a hero-spec renumbering.

The gate must be re-evaluated on loadout changes. `PLAYER_SPECIALIZATION_CHANGED`
is already registered but does not fire on a same-spec talent swap, so
`TRAIT_CONFIG_UPDATED` is added.

`addon.SPELLS` retains `SOUL_REAPER` (343294) and gains `BLIGHTFALL`
(id 1271967, icon 5976940). `addon:IsSanlaynHeroSpec` is not ported.

## Config window

`ConfigV2.lua` becomes `Config.lua`. The sidebar is spec-aware:

```
Unholy                          Blood
------                          -----
Festering Scythe                Stand In Death and Decay
Sudden Doom
Death Coil (Sudden Doom)
Epidemic (Sudden Doom)
Blightfall & Soul Reaper
```

The Classic theme becomes the only theme. `THEME_ITEMS`, the theme dropdown and
the six alternate palettes are removed, along with the pages for every
out-of-scope feature. Live previews, sliders, value fields and Esc-to-close are
kept.

## CDMHook

`CDMHook.lua` has two parallel registration paths — Blizzard's Cooldown Manager
(`RegisterItem`) and EllesmereUI's (`RegisterEllesmereItem`). Every deletion must
be applied to both, symmetrically.

Surviving calls: `RegisterCDMFesteringFrame`, `RegisterCDMSuddenDoomFrame`,
`RegisterCDMLesserGhoulFrame`, `RegisterCDMDnDMissingFrame`,
`RegisterCDMDnDBuffFrame`.

Removed calls: `RegisterCDMPutrefyFrame`, `RegisterCDMBloodDnDAbilityFrame`,
`RegisterCDMBloodBoneAbilityFrame`.

## Deletion hazards

Deletions are not self-contained. These cross-boundary references must be
handled or the addon will throw errors in features that are being kept.

**Text alerts are called from features that survive.** Removing the text-alert
subsystem leaves dangling calls to `addon:SetTextAlertVisible` in two kept
subsystems:

| Call site | Belongs to | Status |
|---|---|---|
| `Core.lua` 1234, 1324, 1327, 1358 — `"festeringScythe"` | Festering Scythe glow (#1) | **kept** |
| `Core.lua` 1621–1623, 1645–1647 — `"deathCoil"`, `"epidemic"`, `"suddenDoom"` | Sudden Doom glows (#4) | **kept** |

Left in place these error on every Festering Scythe trigger and every Sudden
Doom proc. Each call must be deleted from the surviving subsystem, not merely
orphaned. The Sudden Doom sites are pure bookkeeping — they suppress legacy
per-spender alerts so one proc yields one message — so removing them changes no
glow behaviour.

`ConfigV2.lua` also calls `RefreshTextAlert` and `TestTextAlert` from roughly
twenty sites. All but two sit inside the `festeringwa` and `suddendoomwa` pages
being removed; the two at lines 1817 and 1819 are outside those pages and need
checking individually.

**Verified safe:** `AttachCrossToOverlay` and `UpdateCrossAppearance` are
Putrefy-only. All four call sites (964, 976, 1041, 1094) populate
`putrefyOverlays` or `cdmPutrefyOverlays`, so the cross leaves with Putrefy.

**Method.** After each deletion batch, grep the tree for references to every
symbol just removed before reloading. A symbol with surviving callers is either
a kept dependency or a call that must be deleted alongside it.

## Verification

WoW addons cannot be meaningfully unit-tested, so verification is staged manual
testing with a `/reload` after each batch:

1. **Rename and load.** Addon appears in the list, loads with no Lua errors,
   `/dkf` opens settings.
2. **After each deletion batch.** No Lua errors on load, no errors entering or
   leaving combat, every surviving feature still fires from its Test button.
3. **Blightfall port.** Verify the icon appears only when Blightfall is
   talented; swap loadouts in place to confirm `TRAIT_CONFIG_UPDATED` re-gates
   it; confirm chain alternation, countdown, `NOW` glow and TTS.
4. **Stand In Death and Decay — tested last and most carefully.** On a target
   dummy in Blood: glow appears when stepping out of Death and Decay in combat,
   clears immediately on stepping back in, does not appear out of combat, and
   does not appear in another specialization. With Cleaving Strikes talented,
   confirm the 0.5s grace still suppresses the flicker when the buff is briefly
   re-granted. Confirm it glows both the action-bar button and the Cooldown
   Manager icon, and that it now glows regardless of Death and Decay's cooldown.

Item 4 is the acceptance test for the whole project.

## Out of scope

- **Phase two: module split.** Breaking the surviving `Core.lua` into
  `Glow.lua`, `Festering.lua`, `SuddenDoom.lua`, `Blightfall.lua` and
  `BloodDnD.lua`. Deliberately deferred until a working build exists to diff
  against.
- **Settings migration** from `DKAssistDB`.
- **Distribution** — no CurseForge packaging, no release automation.
- **Upstream tracking** — no merge relationship. Future upstream features are
  cherry-picked individually if wanted.
