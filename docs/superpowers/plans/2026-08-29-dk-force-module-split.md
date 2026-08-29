# DK Force Core.lua Module Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Break `DKForce/Core.lua` (1466 lines) into five per-feature modules plus a shared core, with no behaviour change.

**Architecture:** Each World of Warcraft addon file receives the same `addon` table via `local addonName, addon = ...`, so modules communicate through that table and load in the order `DKForce.toc` lists. Code moves out of `Core.lua` one feature at a time; each task leaves the addon loadable and `./verify.sh` green. Only two names cross a module boundary today, and both are promoted from file-locals to `addon:` methods.

**Tech Stack:** Lua 5.1 (WoW client) / Lua 5.4 (desktop, for `luac -p` and the test harness), bash for `verify.sh`, LibCustomGlow-1.0.

**Spec:** `docs/superpowers/specs/2026-08-29-dk-force-module-split-design.md`

## Global Constraints

- **This is a pure move. No behaviour changes.** Any behavioural difference after the split is a defect. The only permitted edits are the three promotions named in Task 1 and Task 2, and the extraction in Task 5.
- **Scope is `Core.lua` only.** `Config.lua` is explicitly out of scope.
- **`./verify.sh` must pass after every task**, all 8 checks. If a check fires, fix the code, not the check.
- **Every new `.lua` file under `DKForce/` must be added to `DKForce/DKForce.toc`.** An unlisted file never loads in game; `verify.sh` check 3 fails on this.
- **Tests live in `tests/`, never under `DKForce/`** — check 3 requires everything under `DKForce/` to be TOC-listed.
- **Never run `git commit` yourself.** The user's global settings hard-deny it. Run `git add`, then give the user a paste-ready `! git commit -m '...'` line using **single** quotes.
- Line numbers below refer to `Core.lua` at commit `1c426dc`. They are a guide; the authority is always the named definition. Numbers shift as earlier tasks remove code — re-grep rather than trusting an offset.

## A note on testing in this plan

This plan does not follow a red-green TDD cycle, and that is deliberate rather than an oversight. There is no new behaviour to specify: every task moves existing code between files. The test that matters already exists and already passes — `./verify.sh`, whose eight checks include a behavioural spec for the Stand In Death and Decay reminder (`tests/dnd_missing_spec.lua`, 10 assertions) and a leaked-globals scan that catches the single most likely defect here, a function moved without its declaration.

So each task's cycle is: **move → `./verify.sh` → commit.** Writing a new failing test per task would mean inventing behaviour that is not changing.

---

### Task 1: Extract Glow.lua

Shared glow infrastructure, moved first because every feature module depends on `addon:CreateOverlay`.

**Files:**
- Create: `DKForce/Glow.lua`
- Modify: `DKForce/Core.lua` (remove lines 64–102, 169–181, 240–263; update 6 call sites)
- Modify: `DKForce/DKForce.toc`

**Interfaces:**
- Consumes: nothing.
- Produces: `addon.GLOW_TYPES` (array of one table with fields `id`, `name`, `description`, `start(frame, opts)`, `stop(frame)`); `addon.GLOW_TYPE_MAP` (id → entry); `addon:GetGlowTypeByID(id)` returning an entry, never nil; `addon:CreateOverlay(targetFrame, spellKey)` returning an overlay frame.

- [ ] **Step 1: Create `DKForce/Glow.lua` with the standard header**

```lua
local addonName, addon = ...
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
```

`Core.lua` line 4 declares `LCG` the same way; `Glow.lua` needs its own copy because file-locals do not cross files. Check `Core.lua:4` and copy its exact form.

- [ ] **Step 2: Move the glow tables and lookup**

Cut from `Core.lua` and paste into `Glow.lua`, in this order and unmodified:
- lines 64–102: the `addon.GLOW_TYPES = { ... }` table with its leading comment block, and the `addon.GLOW_TYPE_MAP` loop that follows it
- lines 169–181: the `-- The `or` fallback is why...` comment and `function addon:GetGlowTypeByID(id)`

- [ ] **Step 3: Move `CreateOverlay` and promote it to a method**

Cut `Core.lua` lines 240–263 into `Glow.lua`, changing only the declaration line:

```lua
-- was: local function CreateOverlay(targetFrame, spellKey)
function addon:CreateOverlay(targetFrame, spellKey)
```

The body is unchanged. It does not reference `self`.

- [ ] **Step 4: Update all six call sites in `Core.lua`**

Re-grep first — `grep -n "CreateOverlay(" DKForce/Core.lua` — then rewrite each to the method form:

```lua
-- line 283
festeringOverlays[button] = addon:CreateOverlay(button, spellKey)
-- line 306
suddenDoomOverlays[button] = addon:CreateOverlay(button, spellKey)
-- line 314
local overlay = addon:CreateOverlay(frame, spellKey)
-- line 330
local overlay = addon:CreateOverlay(frame, "festeringScythe")
-- line 745
dndMissingBarOverlays[button] = addon:CreateOverlay(button, "deathAndDecay")
-- line 754
cdmDnDMissingOverlays[frame] = addon:CreateOverlay(frame, "deathAndDecay")
```

- [ ] **Step 5: Add `Glow.lua` to the TOC**

In `DKForce/DKForce.toc`, immediately after `Core.lua`:

```
Core.lua
Glow.lua
ButtonScanner.lua
Config.lua
MinimapButton.lua
CDMHook.lua
```

`Config.lua` iterates `addon.GLOW_TYPES` when building the settings panel, so `Glow.lua` must precede it.

- [ ] **Step 6: Verify**

Run: `./verify.sh`
Expected: `RESULT PASS`, all 8 checks.

If **leaked globals** fails naming `CreateOverlay`, a call site was missed — grep again. If **Stand In Death and Decay behaviour** fails, the D&D overlay creation calls were broken; that spec exercises them.

- [ ] **Step 7: Commit**

```bash
git add DKForce/Glow.lua DKForce/Core.lua DKForce/DKForce.toc
```

Then give the user:

```
! git commit -m 'Extract Glow.lua from Core.lua'
```

---

### Task 2: Extract Festering.lua

**Files:**
- Create: `DKForce/Festering.lua`
- Modify: `DKForce/Core.lua` (remove the Festering definitions; update `StopAll` and the event dispatcher)
- Modify: `DKForce/DKForce.toc`

**Interfaces:**
- Consumes: `addon:CreateOverlay(targetFrame, spellKey)` from Task 1.
- Produces: `addon:StopFesteringGlow()`, `addon:OnFesteringCombatStart()`, `addon:OnFesteringCombatEnd()`, plus the already-public `addon:CreateFesteringOverlays()`, `addon:RegisterCDMFesteringFrame(frame)`, `addon:RegisterCDMLesserGhoulFrame(frame)`, `addon:RefreshFesteringGlowStyle()`, `addon:RefreshFesteringGlows()`, `addon:TestFesteringGlow()`, `addon:OnFesteringScytheCast()`, `addon:OnFesteringStrikeCast()`, `addon:CancelFesteringCombatGlow()`.

- [ ] **Step 1: Create `DKForce/Festering.lua` with the standard header**

```lua
local addonName, addon = ...
```

- [ ] **Step 2: Move the Festering file-locals**

From the shared declaration block (`Core.lua` 176–177), move into `Festering.lua`:

```lua
local festeringOverlays    = {}
local cdmFesteringOverlays = {}
```

Leave `suddenDoomOverlays`, `cdmSuddenDoomOverlays`, `bloodDnDBuffFrame` and `suddenDoomActive` in `Core.lua` for now; later tasks claim them.

- [ ] **Step 3: Move the Festering definitions**

Cut these from `Core.lua` into `Festering.lua`, preserving their order and their comments:
- `addon:CreateFesteringOverlays` (265–287)
- `addon:RegisterCDMFesteringFrame` and its leading comment (326–333)
- everything from `local FESTERING_BUFF_DURATION = 25` (347) through `addon:TestFesteringGlow` (ends ~569), which includes `HideFesteringGlow`, `CancelFesteringGrace`, `StopFesteringGlow`, `ShowFesteringGlow`, `ApplyFesteringGlow`, `SetFesteringReason`, `addon:RefreshFesteringGlowStyle`, `StartFesteringTimer`, `addon:OnFesteringScytheCast`, `addon:OnFesteringStrikeCast`, `OnFesteringCombatEnd`, `OnFesteringCombatStart`, `addon:CancelFesteringCombatGlow`, `addon:RegisterCDMLesserGhoulFrame`, the `ghoulWatcher` frame and its OnUpdate, and `addon:RefreshFesteringGlows`

- [ ] **Step 4: Promote the three locals Core still calls**

In `Festering.lua`, change three declarations:

```lua
-- was: local function StopFesteringGlow()
function addon:StopFesteringGlow()

-- was: local function OnFesteringCombatEnd()
function addon:OnFesteringCombatEnd()

-- was: local function OnFesteringCombatStart()
function addon:OnFesteringCombatStart()
```

Then update every **internal** caller within `Festering.lua` to the method form. Grep inside the new file for each name; `StopFesteringGlow` in particular is called from more than one place. None of the three bodies uses `self`.

- [ ] **Step 5: Update the two callers left in `Core.lua`**

In `addon:StopAll()` (was line 657):

```lua
function addon:StopAll()
    addon:StopFesteringGlow()
    addon:StopSuddenDoomGlows()
    addon:StopDnDMissingGlow()
end
```

In the `castFrame` event handler (was lines 1118 and 1120):

```lua
        addon:OnFesteringCombatEnd()
        -- and, in the PLAYER_REGEN_DISABLED branch:
        addon:OnFesteringCombatStart()
```

- [ ] **Step 6: Add `Festering.lua` to the TOC, after `Glow.lua`**

```
Core.lua
Glow.lua
Festering.lua
ButtonScanner.lua
Config.lua
MinimapButton.lua
CDMHook.lua
```

- [ ] **Step 7: Verify**

Run: `./verify.sh`
Expected: `RESULT PASS`.

The likely failure is **leaked globals** naming `StopFesteringGlow`, `OnFesteringCombatEnd`, `OnFesteringCombatStart`, `festeringOverlays` or `cdmFesteringOverlays` — that means a reference was left behind in `Core.lua`, or an internal caller in `Festering.lua` was not updated in Step 4.

- [ ] **Step 8: Commit**

```bash
git add DKForce/Festering.lua DKForce/Core.lua DKForce/DKForce.toc
```

```
! git commit -m 'Extract Festering.lua from Core.lua'
```

---

### Task 3: Extract SuddenDoom.lua

**Files:**
- Create: `DKForce/SuddenDoom.lua`
- Modify: `DKForce/Core.lua`
- Modify: `DKForce/DKForce.toc`

**Interfaces:**
- Consumes: `addon:CreateOverlay(targetFrame, spellKey)` from Task 1.
- Produces: `addon:CreateSuddenDoomOverlays()`, `addon:RegisterCDMSuddenDoomFrame(frame, spellKey)`, `addon:IsSuddenDoomActive()`, `addon:StopSuddenDoomGlows()`, `addon:ShowSuddenDoomGlows()`, `addon:RefreshSuddenDoomGlows()`, `addon:TestSuddenDoomGlow(spellKey)`.

- [ ] **Step 1: Create `DKForce/SuddenDoom.lua` with the standard header**

```lua
local addonName, addon = ...
```

- [ ] **Step 2: Move the Sudden Doom file-locals**

From the shared declaration block, move into `SuddenDoom.lua`:

```lua
local suddenDoomOverlays    = {}
local cdmSuddenDoomOverlays = {}
local suddenDoomActive      = false
```

- [ ] **Step 3: Move the Sudden Doom definitions**

Cut from `Core.lua` into `SuddenDoom.lua`, preserving order and comments:
- `GetSuddenDoomOverlaySettings` and `SuddenDoomEnabled` with their comment block (223–238)
- `addon:CreateSuddenDoomOverlays` and `addon:RegisterCDMSuddenDoomFrame` (289–317)
- `local SUDDEN_DOOM_AURA_ID = 81340` through `addon:TestSuddenDoomGlow` (571–654)
- the `suddenDoomWatcher` frame with its leading comment (1124–1138)

- [ ] **Step 4: Add `SuddenDoom.lua` to the TOC, after `Festering.lua`**

- [ ] **Step 5: Verify**

Run: `./verify.sh`
Expected: `RESULT PASS`.

`addon:StopAll` in `Core.lua` calls `addon:StopSuddenDoomGlows()`, which is already a method — no change needed there. `CDMHook.lua` calls `addon:RegisterCDMSuddenDoomFrame`, also already a method.

- [ ] **Step 6: Commit**

```bash
git add DKForce/SuddenDoom.lua DKForce/Core.lua DKForce/DKForce.toc
```

```
! git commit -m 'Extract SuddenDoom.lua from Core.lua'
```

---

### Task 4: Extract BloodDnD.lua and repoint the behavioural spec

This moves the feature the whole fork exists to preserve. The spec in `tests/` is what proves the move was clean, so it is repointed in the same task.

**Files:**
- Create: `DKForce/BloodDnD.lua`
- Modify: `DKForce/Core.lua`
- Modify: `DKForce/DKForce.toc`
- Modify: `tests/dnd_missing_spec.lua` (one line)

**Interfaces:**
- Consumes: `addon:CreateOverlay(targetFrame, spellKey)` from Task 1.
- Produces: `addon:RegisterCDMDnDBuffFrame(frame)`, `addon:StopDnDMissingGlow()`, `addon:ShowDnDMissingGlow()`, `addon:CreateDnDMissingOverlays()`, `addon:RegisterCDMDnDMissingFrame(frame)`, `addon:ClearCDMDnDMissingFrame(frame)`, `addon:RefreshDnDMissingGlows()`, `addon:TestDnDMissingGlow()`.

- [ ] **Step 1: Confirm the spec passes before the move**

Run: `./verify.sh`
Expected: `Stand In Death and Decay behaviour OK`.

This is the baseline. If it is not green before you start, stop and fix that first — otherwise you cannot tell whether the move broke anything.

- [ ] **Step 2: Create `DKForce/BloodDnD.lua` with the standard header**

```lua
local addonName, addon = ...
```

- [ ] **Step 3: Move the file-local and the subsystem**

Move `local bloodDnDBuffFrame = nil` from the shared declaration block, then cut into `BloodDnD.lua`:
- `addon:RegisterCDMDnDBuffFrame` (319–324)
- the entire block from the banner comment `-- Death and Decay Buff Reminder (Blood)` (662) through the line that is exactly `end)` closing `dndMissingWatcher` (829)

**Move the banner comment verbatim.** `tests/dnd_missing_spec.lua` locates the subsystem by matching the line `-- Death and Decay Buff Reminder (Blood)` exactly, then the first `end)` after it. Rewording that line makes the spec fail loudly — by design, but it will block you.

- [ ] **Step 4: Add `BloodDnD.lua` to the TOC, after `SuddenDoom.lua`**

- [ ] **Step 5: Repoint the behavioural spec**

In `tests/dnd_missing_spec.lua`, change the default source path:

```lua
-- was: local SOURCE = os.getenv("DKFORCE_DND_SOURCE") or "DKForce/Core.lua"
local SOURCE = os.getenv("DKFORCE_DND_SOURCE") or "DKForce/BloodDnD.lua"
```

Also update the file's header comment, which says it "slices the real subsystem out of Core.lua", to name `BloodDnD.lua`.

- [ ] **Step 6: Verify, and confirm the spec is still really testing something**

Run: `./verify.sh`
Expected: `RESULT PASS` with `Stand In Death and Decay behaviour OK`.

A pass here is only meaningful if the spec found the code. Prove it did, by breaking the moved copy on purpose:

```bash
sed 's/^local DND_MISSING_GLOW_DELAY = 0.25/local DND_MISSING_GLOW_DELAY = 0/' \
  DKForce/BloodDnD.lua > /tmp/dnd-mutant.lua
DKFORCE_DND_SOURCE=/tmp/dnd-mutant.lua lua tests/dnd_missing_spec.lua
```

Expected: **FAIL**, naming the grace-period and blink assertions. If this passes, the spec is not reaching the moved code and the task is not done.

- [ ] **Step 7: Commit**

```bash
git add DKForce/BloodDnD.lua DKForce/Core.lua DKForce/DKForce.toc tests/dnd_missing_spec.lua
```

```
! git commit -m 'Extract BloodDnD.lua from Core.lua'
```

---

### Task 5: Extract Blightfall.lua

**Files:**
- Create: `DKForce/Blightfall.lua`
- Modify: `DKForce/Core.lua` (including the `/dkf blight` slash branch)
- Modify: `DKForce/DKForce.toc`

**Interfaces:**
- Consumes: `addon.GLOW_TYPES` and `addon:GetGlowTypeByID(id)` from Task 1 — `StopBlightfallReadyGlow` iterates the former and `StartBlightfallReadyGlow` calls the latter. It does **not** use `addon:CreateOverlay`: the Blightfall prompt is a standalone movable frame, not a button overlay.
- Produces: `addon:IsBlightfallTalented()`, `addon:IsSoulReaperTalented()`, `addon:OnBlightfallChainSpellCast(spellID)`, `addon:RefreshBlightfallTracker()`, `addon:TestBlightfallTracker()`, `addon:StopBlightfallTest()`, `addon:PrintBlightfallDiagnostic()`.

- [ ] **Step 1: Create `DKForce/Blightfall.lua` with the standard header**

```lua
local addonName, addon = ...
```

- [ ] **Step 2: Move the talent gates**

Cut `Core.lua` 198–221 into `Blightfall.lua`, comments included: `BLIGHTFALL_TALENT_ID`, `addon:IsBlightfallTalented`, `SOUL_REAPER_TALENT_ID`, `addon:IsSoulReaperTalented`.

Those comments record in-game findings that cost a debugging round trip — that the Blightfall cast id and talent id differ, and that Soul Reaper's do not. Do not trim them.

- [ ] **Step 3: Move the chain subsystem**

Cut the block from the banner `-- Unholy chain prompt: Soul Reaper -> Blightfall` (831) through `addon:StopBlightfallTest` (ends ~1092) into `Blightfall.lua`. This includes `BLIGHTFALL_TEST_HOLD`, the `blightIconFrame` / `blightState` / `blightTest` file-locals, `BlightfallSettings`, `BlightfallDelays`, `InitialBlightfallStep`, `ResolveBlightfallStep`, `BlightfallStepInfo`, `StopBlightfallReadyGlow`, `StartBlightfallReadyGlow`, `UpdateBlightfallIcon`, `CreateBlightfallIconFrame`, `ApplyBlightfallSettings`, `addon:OnBlightfallChainSpellCast`, `addon:RefreshBlightfallTracker`, `addon:TestBlightfallTracker` and `addon:StopBlightfallTest`.

- [ ] **Step 4: Extract the `/dkf blight` diagnostic**

The diagnostic reads `blightState` and `blightIconFrame`, which are now file-locals in `Blightfall.lua`, so its body must move with them.

In `Blightfall.lua`, add at the end:

Locate the exact block first — do not count lines by hand:

```bash
s=$(grep -n 'elseif cmd == "blight" then' DKForce/Core.lua | cut -d: -f1)
e=$(grep -n 'elseif cmd == "minimap" then' DKForce/Core.lua | cut -d: -f1)
sed -n "$((s+1)),$((e-1))p" DKForce/Core.lua
```

That prints the whole branch body: the `local function say`, `local function yn`
and `local function spellKnown` helpers, the `say("--- Blightfall diagnostic ---")`
line, every subsequent `say(...)` call, and the `blightState` / `blightTest` /
`blightIconFrame` reporting. Wrap that output, unmodified and with its
indentation reduced by one level, as the body of:

```lua
-- Body of the `/dkf blight` slash command.  It lives here because it reads
-- blightState and blightIconFrame, which are file-locals in this module.
function addon:PrintBlightfallDiagnostic()
    <the printed block, verbatim>
end
```

In `Core.lua`, the slash branch (was line 1382, ending where `elseif cmd == "minimap" then` begins at 1446) collapses to:

```lua
    elseif cmd == "blight" then
        addon:PrintBlightfallDiagnostic()
```

The diagnostic also references `BLIGHTFALL_TALENT_ID`, which moved in Step 2 — so it resolves correctly in the new file and would have broken had it stayed in `Core.lua`.

- [ ] **Step 5: Add `Blightfall.lua` to the TOC, after `BloodDnD.lua`**

Final order:

```
Core.lua
Glow.lua
Festering.lua
SuddenDoom.lua
BloodDnD.lua
Blightfall.lua
ButtonScanner.lua
Config.lua
MinimapButton.lua
CDMHook.lua
```

- [ ] **Step 6: Verify**

Run: `./verify.sh`
Expected: `RESULT PASS`.

Watch **leaked globals** for `blightState`, `blightIconFrame`, `blightTest` or `BLIGHTFALL_TALENT_ID` — any of those means part of the diagnostic or the state machine was left behind in `Core.lua`.

- [ ] **Step 7: Commit**

```bash
git add DKForce/Blightfall.lua DKForce/Core.lua DKForce/DKForce.toc
```

```
! git commit -m 'Extract Blightfall.lua from Core.lua'
```

---

### Task 6: Final review and in-game smoke test

**Files:**
- Modify: `DKForce/Core.lua` (comment header only, if warranted)

- [ ] **Step 1: Confirm the shape**

Run: `wc -l DKForce/*.lua | grep -v Libs`

Expected, roughly: `Core.lua` ~420, `Glow.lua` ~80, `Festering.lua` ~255, `SuddenDoom.lua` ~145, `BloodDnD.lua` ~175, `Blightfall.lua` ~290. A file far off its estimate means code landed in the wrong module — check against the move map in the spec.

- [ ] **Step 2: Confirm nothing became dead in the move**

Run this scan, which is the same one that found the dead code removed in `1c426dc`:

```bash
python3 - <<'PY'
import re, glob
files = [f for f in glob.glob("DKForce/*.lua") if "Libs" not in f]
srcs = {f: open(f).read() for f in files}
allsrc = "\n".join(srcs.values())
found = False
for f, src in srcs.items():
    for pat in (r'^local function (\w+)', r'^function addon:(\w+)', r'^local (\w+)\s*='):
        for m in re.finditer(pat, src, re.M):
            name = m.group(1)
            if name == "addonName": continue
            if len(re.findall(r'\b' + name + r'\b', allsrc)) <= 1:
                print(f"  {f}:{src[:m.start()].count(chr(10))+1}  {name}")
                found = True
print("  none" if not found else "")
PY
```

Expected: `none`. A name appearing here after the split is one that lost its only caller during the move — investigate rather than delete.

- [ ] **Step 3: Update the `Core.lua` header comment**

`Core.lua` is now the shared core, not the whole addon. If its top-of-file comment describes it as holding the features, rewrite it to say what it now owns — spell data, defaults, spec helpers, event dispatch, DB init and slash commands — and that each feature lives in its own file.

- [ ] **Step 4: Full verification**

Run: `./verify.sh`
Expected: `RESULT PASS`, all 8 checks.

- [ ] **Step 5: In-game smoke test**

`verify.sh` proves the addon parses, leaks no globals, and that the D&D reminder still decides correctly. It cannot prove the other four features still fire. Load the addon and check each:

1. **Festering Scythe** — glow appears with under 5 seconds on the buff; the Lesser Ghoul reminder still works if enabled.
2. **Sudden Doom** — Death Coil and Epidemic glow on proc, in both Action Bar and Cooldown Manager modes.
3. **Blightfall / Soul Reaper** — cast Dark Transformation; the Soul Reaper icon counts to 7 and glows; casting Soul Reaper swaps to the Blightfall icon still counting to 13; the icon persists out of combat with the glow off.
4. **Stand In Death and Decay** — glow on stepping out of your own D&D in combat, clearing on stepping back in.
5. **Settings panel** — opens from both `/dkf` and Blizzard's AddOns page; every page renders; Test and Rescan Bars work.

- [ ] **Step 6: Commit**

```bash
git add DKForce/Core.lua
```

```
! git commit -m 'Update Core.lua header for the module split'
```

---

## Rollback

Each task is one commit touching whole definitions, so `git revert <sha>` restores any single module to `Core.lua` cleanly. If the addon fails to load in game and the cause is not obvious, revert the most recent extraction first — a missing TOC entry or a file-local left behind are the two likely causes, and both produce a load-time error naming the file.
