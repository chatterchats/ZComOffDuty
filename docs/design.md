# Off Duty: design (working draft)

## Decisions so far (2026-10-07)

- **Exhaustion is separate from injuries.** It doesn't apply or remove `GE_Injured`.
- **Push-through model.** Exhausted operators can always deploy. The cost is a bigger
  penalty plus extra recovery afterwards. Hard locks are out of scope (no save can get stuck).
- **Logic Blueprints are allowed** (Modkit). No art or level assets.
- **Built to work alongside Aranthar's Long War campaign mod** and standalone on vanilla.
- **Fatigue is stored in the save** as stacks of a custom `GE_OffDuty_Fatigue` (2026-10-08). The
  sidecar-file plan is dropped: it couldn't follow save reloads.

## Working model (decided 2026-10-08; see penalty-theorycraft.md)

- **Starting cycle:** fatigue only counts after cycle 5 (setting, 1–20); the early roster is too small to
  rotate. Until then, missions add no fatigue and apply no tier. The game's strategy turn runs one behind
  the cycle it displays (turn 5 is "Cycle 6", verified 2026-10-11), so the setting compares against the
  turn directly.
- **Fatigue points:** +2 per mission played, cap 7. Operators on an operation are frozen (no gain,
  no recovery).
- **Recovery per strategy turn off** is what the presets change: Easy −3, Standard −2 (default),
  Hard −1.5. It halves once the operator cap (Crew Quarters, the game's
  `Facts.Values.MaximumRosterCount`) reaches 12: three squads are then needed to stay rested, so a big
  roster still gets used. Fractions are banked as quarter points in `GE_OffDuty_RestCredit` (0–3 stacks).
  Tuned for two squads (2026-10-11): by cycle 5 the roster holds at most 7 operators and late game 13,
  so a three-squad rotation isn't realistic. With +2 / −2, two squads alternating stay rested, and each
  back-to-back mission is one tier worse. The first tuning (+2 / −1) only stayed level with three squads.
- **Tiers** (every preset): Tired at 2, Exhausted at 4, Spent at 6; fatigue caps at 7.

| Tier      | Next-mission penalty                                  |
| --------- | ----------------------------------------------------- |
| Ready     | none                                                  |
| Tired     | −5% hit chance (HC), −5% max HP                       |
| Exhausted | −10% HC, −10% max HP, 10% chance/turn -1 AP           |
| Spent     | −20% HC, −20% max HP, 15% chance/turn -1 AP, −10% Move |

A turn is 3 AP (moving, shooting, abilities); see penalty-theorycraft.md §8.
Retuned 2026-10-10 after AI-vs-AI sims (Outlaw 1, 4x, ~26 runs per tier): with the first numbers only
Spent moved the win rate (77% → 50%); Tired and Exhausted were inside the noise.

Verified 2026-10-11 with the retuned numbers (326 runs, Outlaw 1, 4x, two game instances, no runs excluded;
`dist/simtest/20261011T020022Z-i23-results.csv`):

| Tier      | Runs | Win rate | Downed | Health lost | AP lost |
| --------- | ---- | -------- | ------ | ----------- | ------- |
| Baseline  | 82   | 82% ±8   | 2.2    | 70%         | 0       |
| Tired     | 82   | 71% ±10  | 2.5    | 75%         | 0       |
| Exhausted | 81   | 54% ±11  | 3.0    | 84%         | 3.4     |
| Spent     | 81   | 33% ±10  | 3.3    | 89%         | 5.1     |

Each tier costs roughly 10-20 points of win rate over the one before. Exhausted and Spent differ from the
tier below them at about 98-99% confidence; Tired vs baseline (-11 points) at about 90%.

- Push-through: any tier can deploy; story-required operators are never blocked.
- Required operators (the mission can't launch without them) go in at the tier for half their fatigue,
  rounded down. Their fatigue itself is unchanged and the mission adds the usual gain.
- Droids use the same system ("needs maintenance" wording).
- Squad select should show the tier and penalty before you commit.

## Implementation plan

1. **Fatigue storage:** `GE_OffDuty_Fatigue`, a Blueprint `UBitReactorGameplayEffect` in the
   `OffDuty` plugin (`unreal/OffDuty`, built with `tools/build_plugin.sh` in the SWZC Merged Kit),
   shipped as `Content/Paks/~mods/OffDuty_P.*`; in game it is `/Game/OffDuty/Effects/GE_OffDuty_Fatigue`.
   It copies the save pattern of the game's `GE_Injured`: infinite, `AggregateByTarget`,
   `bIncludeInSaveData = true`, `bTerminateWithCombat = false`, asset tag
   `BitReactor.GameplayEffect.Persists` (what the hub save keeps), no modifiers. Lua reads and changes
   its stack count on the strategy character. Survives a hub save → load and a mission round trip; uninstalling leaves saves loadable
   (verified 2026-10-08).
2. **Penalty:** `UBrunoGameStatics::AddNextMissionCharacterEffect` with the shipped
   `GE_Lose_NextMission_RangedAccuracy` (−5% per stack, shown natively, cleared after the mission).
3. **Loop:** mission start (`ApplyNextMissionEffectsToCharacter`) records who deployed; turn end
   (`EndStrategyTurn`) adds/removes fatigue and queues next cycle's penalties.
4. Roster badge and squad-select warning; settings through MXM when present.

Open questions and evidence: `phase0-findings.md`. Probe: `../src/OffDutyProbe/`.
