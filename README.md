# DK Force

A personal Death Knight addon for World of Warcraft Retail (Interface 120100).

Derived from [DK Assist Community](https://github.com/thyco/dk-assist-community),
itself a fork of **DK Assist** by ZachoWOW. Distributed under the MIT license
with original copyright notices preserved.

Built for personal use. Not distributed, and not tracking upstream.

## Features

### Unholy

- **Festering Scythe warning** — glows Festering Strike on your action bars, or
  its Cooldown Manager icon, when the buff is about to expire. Configurable
  warning time, an optional combat-start reminder with its own delay, and an
  optional reminder when Lesser Ghoul is missing (this one needs Lesser Ghoul
  present in the Cooldown Manager, under Tracked Buffs or Tracked Bars).
- **Sudden Doom glows** — one switch enables the proc glow; Death Coil and
  Epidemic then each have their own style, colour and appearance page.
- **Blightfall & Soul Reaper prompt** — a movable icon showing the next spell in
  the chain with a countdown, a ready glow, and an optional spoken callout.
  Dark Transformation starts the Soul Reaper countdown; casting Soul Reaper
  starts the Blightfall one. It runs only while **Blightfall is talented** — it
  is gated on the talent itself, not on a hero specialisation.

### Blood

- **Stand In Death and Decay** — glows Death and Decay whenever you are in
  combat and not standing in your own patch, regardless of its cooldown. It
  reads the Death and Decay *buff* from the Cooldown Manager, so both Death and
  Decay and its buff must be tracked there. A short delay stops the buff that
  Cleaving Strikes briefly re-grants from making the glow flicker.

### Shared

- **Four glow styles** — Pixel Glow, Autocast Shine, Button Glow and Proc
  Border. Every glow has its own colour; the remaining sliders depend on the
  style, because that is all each one uses: Pixel Glow offers animation speed,
  lines / particles, thickness and opacity, Autocast Shine and Button Glow offer
  animation speed and opacity, and Proc Border offers opacity only.
- **Action Bar or Cooldown Manager** targeting for the Festering Scythe and
  Sudden Doom glows, with **Rescan Bars** and **Test** buttons.

There is no timeline or bar display: the Blightfall prompt's icon is the only
free-floating display the addon draws. Everything else decorates buttons you
already have.

## Settings

`/dkf` opens the settings window; the same panel is also registered under
Blizzard's AddOns settings. A **Configure** dropdown switches between the pages
offered for the selected spec:

| Spec | Pages |
| --- | --- |
| Unholy | Festering Scythe, Sudden Doom, Death Coil (Sudden Doom), Epidemic (Sudden Doom), Blightfall & Soul Reaper |
| Blood | Stand In Death and Decay |

A **Spec** dropdown picks which set is offered — *Auto* follows your current
specialisation. The window has a single built-in look; there is no theme
picker.

Other entry points: the minimap button (toggleable in the panel; the change
needs a UI reload), the addon compartment menu, and `/dkforce` as an alias for
`/dkf`.

Slash commands:

| Command | Effect |
| --- | --- |
| `/dkf` | Open the settings window |
| `/dkf scan` | Rescan action bars |
| `/dkf cdmscan` | Rescan Cooldown Manager tracked items |
| `/dkf debug` | Toggle debug logging |
| `/dkf minimap` | Show the minimap button again |

## Installation

Copy the `DKForce` folder into `World of Warcraft/_retail_/Interface/AddOns/`,
then `/reload`. Open settings with `/dkf` or the minimap button.
