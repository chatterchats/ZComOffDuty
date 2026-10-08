# Off Duty: penalty theorycraft

Working notes for choosing **how fatigue builds** and **what it costs**. Numbers are for discussion;
everything ends up configurable.

## Ground truth from the game

| Fact | Source |
|---|---|
| A turn is **1 action + 1 move** (plus 1 special, 1 class-tactic point) | probe run 1 |
| `AccuracyReduction` +1 = **−5% hit chance** | runs 2–3, hit breakdown "Penalty from Operation" |
| Injury: −15% hit chance per stack (max 2 stacks) | `GE_Injured`: `AccuracyReduction` +3 |
| Disoriented: −20% hit chance | `GE_Disoriented`: +4 |
| Overwatch penalty: −5% per stack | `GE_OverwatchPenaltyStack`: +1 |
| Shipped next-mission HP loss: −2 max HP per stack | `GE_Lose_NextMission_LoseMaxHealth` |
| Operator max HP: 57–97 (base 28 + upgrades/class) | probe dumps, turn 28 |
| Movement: 500 per move (600–700 with upgrades); Shocked halves it | `MovementPerAP`, `GE_Shocked` ×0.5 |
| Base hit chance 100%, minus range/cover (e.g. −25% range, −35% cover) | hit-breakdown screenshots |

Losing an action point is off the table: with 1 action + 1 move, one AP is a whole action or the whole move.

## 1. How fatigue builds (this sets the pressure)

Model: one mission per strategy turn, roster of 10, squad of 4, 24 missions, cap 3.
"Avg at deploy" is the fatigue an operator carries into a mission.

| Squad habit | R1: +1 per mission, −1 per turn off, +1 for deploying Exhausted | R3: +2 per mission, −1 per turn off |
|---|---|---|
| Same 4 every mission | 2.75 (88% of deployments at 3) | 2.83 |
| Core 3 + rotating 4th | 2.06 (core always maxed) | 2.12 |
| Two squads alternating | **0.00** (never penalized) | 1.75 (mostly 2) |
| Freshest 4 each mission | **0.00** | 1.21 |

- **R1 is a nudge:** "don't run the same people every mission." Two squads of 4 never feel it.
- **R3 is real roster management:** even two alternating squads live at Exhausted; staying fresh
  needs roughly three squads' worth of operators, so recruiting matters.
- Slower recovery (e.g. "−1 per 2 turns off") has a trap if counted as consecutive turns: operators
  who sit out one turn at a time never recover. Use a fractional rate (0.5 per turn off) instead.
- **Open:** how many missions does a strategy turn usually hold? More missions per turn make
  per-turn recovery relatively slower and push every row toward R3.

## 2. What each penalty does

### Accuracy (shipped effect, native "Penalty from Operation" in the hit breakdown)

Relative loss of expected hits, by base hit chance of the shot:

| Penalty per level | Level | 85% shot | 65% shot | 40% shot |
|---|---|---|---|---|
| **−5% / level** | 1 / 2 / 3 | −6% / −12% / −18% | −8% / −15% / −23% | −13% / −25% / −38% |
| **−10% / level** | 1 / 2 / 3 | −12% / −24% / −35% | −15% / −31% / −46% | −25% / −50% / −75% |

- Hurts **risky shots** most, so it nudges tired operators toward good positioning. Thematic.
- −10%/level reaches Disoriented (−20%) at level 2 and beats an injury at level 2. Too harsh for a
  mod where you can always push someone through. **−5%/level keeps fatigue below an injury.**
- Class skew: only hit-rolled attacks care. Assists are auto-hits; AoE, heals, buffs and (likely)
  some melee/Force abilities ignore it. Support-heavy operators become "fatigue-proof." (Which
  abilities roll to hit isn't verified per class yet.)

### Max health

| Penalty per level | On a 97 HP operator, levels 1 / 2 / 3 | On a 57 HP operator |
|---|---|---|
| Shipped effect, −2 per stack | −2 / −4 / −6 (≈2–6%) | −2 / −4 / −6 |
| Custom effect, **−10% / level** | −10 / −19 / −29 | −6 / −11 / −17 |

- **Class-neutral:** everyone needs HP. The fairest single axis.
- Shrinks the safety margin rather than the toolkit (the Chaos Gate model): more downs, so more
  injuries and more death risk. Fatigue then *feeds* the injury system without touching it.
- Less visible: a shorter health bar, unless the briefing lists it (the shipped effect has strategy
  text; a custom one needs our own, English-only, name).
- The shipped −2 is too small to matter; a percentage version needs a custom effect (`MaxHealth`
  `MultiplyAdditive`), which the build pipeline can now make.

### Movement

| Penalty per level | 500 base: levels 1 / 2 / 3 |
|---|---|
| **−10% / level** | 450 / 400 / 350 |

- Never lethal by itself; it costs flanks, cover options and reach.
- Skewed the other way: melee and flankers (Kabb, Tel-Rea) feel it most, snipers barely.
- Needs a custom effect (no shipped penalty version); low visibility.

### Other levers (not yet researched in depth)

- **Crit chance down:** hits crit builds only.
- **Incoming damage up:** like HP loss but harsher and spikier.
- **Advantage generation down:** hits Zero Company's core loop; unclear how per-operator it is.
- **Higher injury chance when downed:** very thematic ("tired bodies get hurt"), reuses the injury
  system's own roll; needs research into how the injury roll is modified (`GE_TraumaKit_InjuryPreventChance_20` suggests a hook).

## 3. Candidate packages

| Package | Tired (1) | Exhausted (2) | Spent (3) | Strengths | Weaknesses |
|---|---|---|---|---|---|
| **A. Shaky aim** | −5% hit | −10% hit | −15% hit | Native, visible, simplest | Support/melee shrug it off |
| **B. Worn down** | −10% max HP | −20% | −30% | Fair to every class | Hidden; drives injuries/deaths |
| **C. Tiered mix** | −5% hit | −10% hit, −10% max HP | −15% hit, −20% max HP, −10% move | Gentle start, every class feels the top tiers | Most to explain; needs 2 custom effects |
| **D. Class-aware** | axis per role: shooters aim, melee movement, support HP | | | Fairest | Needs reliable role detection; later |

## 4. Recommendation

- **Default: package C on rule R1.** Tired is a light, visible nudge; only operators run into the
  ground reach the bundled penalties, and every class feels Spent.
- **"Hard" preset: package C on rule R3**, for long campaigns (and Aranthar's Long War mod, where
  bigger rosters are the point).
- Expose the choice of package and rule set in MXM settings.
- Keep the cap at **Spent = −15% hit**, so fatigue never outweighs a single injury (−15%) or Disoriented (−20%).

Decisions needed: pressure level (R1 nudge vs R3 roster management), package, and the
missions-per-turn question above.

## 5. Decisions so far (2026-10-08)

- **Accumulation: the hard rule.** +2 fatigue per mission played, −1 per strategy turn off
  (a strategy turn holds one played mission). No extra "push" penalty; +2 is already the hard version.
- **Penalty: the tiered mix** (Tired −5% hit; Exhausted −10% hit, −10% max HP; Spent −15% hit,
  −20% max HP, −10% movement). Tired is meant to be an inconvenience; Spent is the deterrent.
- Proposed, pending: **operations freeze fatigue** (operators Away neither gain nor recover; they also
  have no hub actor, so their stacks can't be changed while away).

### Tier thresholds on fatigue points: 2/4/6 vs 1/3/5

Both recover one tier per two turns off; 2/4/6 drops the first tier on the first turn off, 1/3/5 on
the second.

| Squad habit (share at Ready / Tired / Exhausted / Spent) | 2/4/6 | 1/3/5 |
|---|---|---|
| Same 4 every mission | 0 / 0 / 0 / 100% | 0 / 0 / 0 / 100% |
| Two squads alternating (10 operators) | 0 / 0 / 100% / 0 | 0 / 0 / 0 / 100% |
| Freshest 4 each mission (10 operators) | 0 / 42% / 57% / 0 | 0 / 18% / 62% / 20% |
| Three squads rotating (12 operators) | 100% / 0 / 0 / 0 | 100% / 0 / 0 / 0 |

Recommendation: **2/4/6**. With +2 per mission, 1/3/5 makes Spent the steady state for two-squad
play; 2/4/6 reserves Spent for a third consecutive mission. Optional stickiness: cap points at 7, so
four missions in a row keep an operator Spent through the first turn off.
