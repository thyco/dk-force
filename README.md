# DK Force

A personal Death Knight addon for World of Warcraft Retail.

Derived from [DK Assist Community](https://github.com/thyco/dk-assist-community),
itself a fork of **DK Assist** by ZachoWOW. Distributed under the MIT license
with original copyright notices preserved.

Built for personal use. Not distributed, and not tracking upstream.

## Features

- **Festering Scythe warning** — action bar or Cooldown Manager glow when
  Festering Strike becomes Festering Scythe, with expiry timing, a combat-start
  reminder, and an optional Lesser Ghoul reminder.
- **Sudden Doom glows** — separate configurable glows for Death Coil and
  Epidemic when Sudden Doom procs.
- **Blightfall & Soul Reaper prompt** — an icon showing the next spell in the
  chain with a countdown, ready glow, and optional spoken callout. Shown only
  when Blightfall is talented.
- **Stand In Death and Decay (Blood)** — glows Death and Decay whenever you are
  in combat and not standing in your own patch, regardless of its cooldown. A
  short grace period stops the buff that Cleaving Strikes briefly re-grants from
  making the glow flicker.
- **Four glow styles** — Pixel Glow, Autocast Shine, Button Glow and Proc
  Border, each with independent colours, animation and opacity.
- **Action Bar or Cooldown Manager** targeting, with Rescan Bars and Test tools.

## Installation

Copy the `DKForce` folder into `World of Warcraft/_retail_/Interface/AddOns/`,
then `/reload`. Open settings with `/dkf` or the minimap button.
