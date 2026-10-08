# Off Duty: penalty theorycraft

Working notes for choosing **how fatigue builds** and **what it costs**. Numbers are for discussion;
everything ends up configurable.

## Ground truth from the game

| Fact | Source |
|---|---|
| A turn is **3 AP** for moving, shooting and abilities (hub values show 1) | probe run 2 in-mission dump |
| `AccuracyReduction` +1 = **−5% hit chance** | runs 2–3, hit breakdown "Penalty from Operation" |
| Injury: −15% hit chance per stack (max 2 stacks) | `GE_Injured`: `AccuracyReduction` +3 |
| Disoriented: −20% hit chance | `GE_Disoriented`: +4 |
| Overwatch penalty: −5% per stack | `GE_OverwatchPenaltyStack`: +1 |
| Shipped next-mission HP loss: −2 max HP per stack | `GE_Lose_NextMission_LoseMaxHealth` |
| Operator max HP: 57–97 (base 28 + upgrades/class) | probe dumps, turn 28 |
| Movement: 500 per move (600–700 with upgrades); Shocked halves it | `MovementPerAP`, `GE_Shocked` ×0.5 |
| Base hit chance 100%, minus range/cover (e.g. −25% range, −35% cover) | hit-breakdown screenshots |

Losing 1 AP costs a third of a turn (see §7–8).

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
- **Tiers on fatigue points: 1 / 3 / 5** (Tired / Exhausted / Spent), **cap 7**: the first turn off
  doesn't drop a tier, and four missions in a row keep an operator Spent for two turns off.
- **Operations are left alone:** operators on an operation neither gain nor recover fatigue. Operations
  range from restful to strenuous, and classifying each by hand isn't worth it. (Away operators also
  have no hub actor, so their stacks couldn't be changed anyway.)

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

### The chosen rules: 1/3/5, cap 7, +2 per mission, −1 per turn off

| Squad habit (Ready / Tired / Exhausted / Spent at deployment) | Result |
|---|---|
| Same 4 every mission (10 operators) | 0 / 0 / 0 / 100% |
| Two squads alternating (10) | 0 / 0 / 0 / 100% |
| Freshest 4 each mission (10) | 0 / 18% / 50% / 32% |
| Freshest 4 each mission (12) | 100% / 0 / 0 / 0 |
| Three squads rotating (12) | 100% / 0 / 0 / 0 |

Recovery: 1 mission → 2 turns off to Ready; 2 in a row → 4; 3 → 6; 4 → 7.

**12 operators is the line**: fully fresh at 12, about a third of deployments Spent at 10 even with
perfect rotation. These rules become the **Hard** preset (meant for long campaigns and big rosters);
a **Standard** preset (2/4/6, cap 6) keeps a 10-operator campaign mostly at Tired/Exhausted. Gain,
recovery, thresholds and cap are all settings.

## 6. Feel test setup (2026-10-08)

- `GE_OffDuty_Exhausted` (MaxHealth ×0.9) and `GE_OffDuty_Spent` (MaxHealth ×0.8, MovementPerAP ×0.9)
  copy the game's next-mission penalty pattern: removed when combat ends, not saved, tags
  `TemporaryPenalty` + `StatusEffect.Negative`, briefing text through `BrunoGameEffectUIData`.
  They don't stack: `MultiplyAdditive` magnitudes are multiplied by the stack count (two ×0.9 stacks
  would read as ×1.8).
- Accuracy is the game's `GE_Lose_NextMission_RangedAccuracy`, queued 1/2/3 times.
- The probe's **Ctrl+Shift+1/2/3** queue Tired/Exhausted/Spent on every roster operator not away.

## 7. Idea: chance to lose an action point each turn (Long War Rebalance style)

In LW Rebalance (XCOM: EW), deploying fatigued gives a chance each turn to lose 1 AP (2 when exhausted)
instead of a flat penalty; fatigue gain scales with mission length.

**Zero Company version.** A turn is 3 AP for moving, shooting and abilities, so losing 1 AP costs a
third of a turn: the operator can still move and shoot but not also use an ability. The game's own
`GE_Lethargy` (`ActionPoints` −1) is the precedent.

Odds over a 6-turn mission:

| Chance per turn | ≥1 lost turn | ≥2 lost turns | Expected lost turns |
|---|---|---|---|
| 10% | 47% | 11% | 0.6 |
| 15% | 62% | 22% | 0.9 |
| 20% | 74% | 34% | 1.2 |
| 25% | 82% | 47% | 1.5 |
| 30% | 88% | 58% | 1.8 |

A **streak breaker** (no two lost turns in a row) trims 20% → 1.03 and 25% → 1.24 expected.

- **Pros:** class-neutral (supports and melee feel it too, unlike accuracy); visible; LW-style drama.
- **Cons:** variance; a lost action feels bad. Mitigate: announce it at turn start, streak breaker,
  never on the first turn.
- **Feasibility:** each unit's `UBitReactorAbilitySystemComponent::OnTeamTurnStarted(Team)` is bound
  to `UTurnEventDispatcher`'s dynamic delegate (ProcessEvent, hookable from Lua); game effects already
  remove points (`GE_Lethargy`, `GE_SetActionPoints`, `GE_SetMovementPoints`); 15 effects use
  `TargetTeamTurnStart` triggers. No game effect uses a chance to apply, so the roll is Lua. To verify:
  the hook fires, and our deduction lands after the turn-start refresh (`GE_ResetActionPoints`).
- **Mission length:** in-mission, the chance could rise in long fights (e.g. +5% per round after
  round 6); between missions, gain could add +1 for long missions (`UBRGameMissionToHubData.TotalTacticalRounds`).
- **Recovery modifiers:** no Will in Zero Company; candidates are Medbay facilities/upgrades, bonds,
  and traits. Later.

## 8. Working ladder (2026-10-08, user's proposal)

| Tier | Penalty | Combat power (model) |
|---|---|---|
| Tired | −5% hit | 91% |
| Exhausted | −10% hit, −5% max HP, 5% chance per turn to lose 1 AP | 77% |
| Spent | −15% hit, −10% max HP, 10% chance per turn to lose 1 AP, −5% movement | 64% |

Model: a lost AP removes a third of that turn's output. Previous ladder (HP/move, no AP): 91 / 74 / 59%.
Hard rules on 10 operators: average operator strength 76% (was 73%).

- Accuracy still carries most of the cost; −5/−10% max HP is 3–10 HP and −5% movement is 500 → 475,
  so those are flavor that touches every class.
- AP loss is occasional: 5% per turn = 26% chance of any lost AP in a 6-turn mission (0.3 expected);
  10% = 47% (0.6). For a felt Long War mechanic, 10%/20% would be the step up.
- Effects to rebuild: Exhausted MaxHealth ×0.95; Spent MaxHealth ×0.9, MovementPerAP ×0.95. The AP roll
  is Lua on `UBitReactorAbilitySystemComponent::OnTeamTurnStarted` (to verify with the probe) plus an
  instant `ActionPoints` −1 effect applied after the turn-start refresh.
