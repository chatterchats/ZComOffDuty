# Off Duty v1.0.0 — Operator Fatigue and Recovery for Star Wars: Zero Company

Tired of sending the same four operators on every mission? With Off Duty,
operators **get tired from back-to-back deployments** and **recover while
they're off duty**, so the rest of your company gets a chance to shine.

## How it works

- **Fatigue starts at cycle 5** (adjustable), once your roster is big enough to
  rotate. Before that, missions add no fatigue.
- **Every mission adds fatigue** to each operator who deploys (2 by default).
- **Every strategy turn off duty removes some** (1 by default). Operators away
  on an operation neither gain nor recover.
- **Fatigue sets a tier** for the next mission. You can always deploy anyone;
  a tired operator just fights worse.

| Tier      | Easy | Standard (default) | Hard | Next mission                                                   |
| --------- | ---- | ------------------ | ---- | -------------------------------------------------------------- |
| Rested    | 0–2  | 0–1                | 0    | No penalty                                                     |
| Tired     | 3–4  | 2–3                | 1–2  | −5% hit chance, −5% max health                                 |
| Exhausted | 5–6  | 4–5                | 3–4  | −10% hit chance, −10% max health, 10% chance a turn to lose 1 AP |
| Spent     | 7    | 6–7                | 5–7  | −20% hit chance, −20% max health, −10% movement, 15% chance a turn to lose 1 AP |

Fatigue caps at 7.

- **Story-required operators go in at half their fatigue.** When a mission
  can't launch without someone, their tier comes from half their fatigue
  (rounded down). Their fatigue itself isn't changed, and the mission still
  adds to it as usual.
- **Squad select shows it before you commit.** Every squad slot gets a banner:
  RESTED, REQUIRED, TIRED, EXHAUSTED or SPENT. Hover it for the operator's
  fatigue, the exact penalties and how many turns until they're fully rested.
  Roster portraits get a small marker for anyone tired or required.
- **In the mission**, the tier shows as a debuff under the health bar and in
  the Inspect panel. The hit chance penalty shows in the hit breakdown as
  "Penalty from Operation".
- **Separate from injuries.** The game's own injuries work exactly as before.

## Settings

With the [Mixamoo Mod Config Manager](https://www.nexusmods.com/starwarszerocompany/mods/149) installed, Off Duty has an in-game
settings page:

- **Preset:** Easy (tiers at 3 / 5 / 7), Standard (2 / 4 / 6) or Hard (1 / 3 / 5).
- **Fatigue per mission:** 0–4.
- **Recovery per turn off duty:** 0–3.
- **Fatigue starts at cycle:** 1–20 (5 by default).
- **AP loss:** turn the chance to lose an AP on or off.

Without it, Off Duty uses the defaults (Standard, 2, 1, cycle 5, AP loss on). Changes apply
from the next mission or strategy turn.

## What you need

- Star Wars: Zero Company
- UE4SS for Star Wars Zero Company (Nexus Mods)
- Optional: [Mixamoo Mod Config Manager](https://www.nexusmods.com/starwarszerocompany/mods/149), for the settings page

## Installing

The download has two parts, and both are needed:

- **OffDuty**: the mod itself.
- **OffDuty_Assets**: its gameplay effects and status tags.

### With a mod manager

Install the downloaded ZIP with **Zero Mod Manager** or **Zero Company Mod
Command**, install both parts, and make sure they're switched on.

### By hand

1. Close the game.
2. Drag the **OffDuty** folder into the UE4SS mods folder:
   `SWZeroCompany/Binaries/Win64/ue4ss/Mods/`
3. Copy the three files inside **OffDuty_Assets** (`OffDuty_P.pak`,
   `OffDuty_P.ucas` and `OffDuty_P.utoc`) into:
   `SWZeroCompany/Content/Paks/~mods/` (create `~mods` if it's missing)
4. Start the game.

## Updating

Close the game, then install the new version the same way. Restart the game
after installing or updating rather than using UE4SS's "Reload All Mods".

## Uninstalling

Switch both parts off or remove them in your mod manager, or delete the
**OffDuty** folder and the three `OffDuty_P` files. Saves stay loadable without the
mod; operators simply stop tiring.

## Good to know

- Guest units who aren't on your roster (such as Rex) don't gain fatigue.
- Loading a save made during a mission restores everyone's tier without
  adding fatigue again.

## Found a problem?

Let us know what happened and which other mods you use, and attach
`off_duty.log` from the **OffDuty** folder. It only contains technical
details about what the mod did. It may mention folder paths on your PC, so
feel free to look it over before sending.
