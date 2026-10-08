# Off Duty: design (working draft)

## Decisions so far (2026-10-07)

- **Exhaustion is separate from injuries.** It doesn't apply or remove `GE_Injured`.
- **Push-through model.** Exhausted operators can always deploy. The cost is a bigger
  penalty plus extra recovery afterwards. Hard locks are out of scope (no save can get stuck).
- **Logic Blueprints are allowed** (Modkit). No art or level assets.
- **Built to work alongside Aranthar's Long War campaign mod** and standalone on vanilla.

## Working model (numbers are playtest placeholders)

| Fatigue | State | In-mission effect |
|---|---|---|
| 0 | Ready | none |
| 1 | Tired | −5% hit chance (1 stack) |
| 2+ | Exhausted | −10% (2 stacks), −15% at the cap; deploying adds +1 extra fatigue afterwards |

- Gain: +1 per deployment; +1 for a long mission (`TotalTacticalRounds` threshold) or for going down.
- Recover: −1 for each strategy turn the operator sits out.
- Story-required operators (`GetRequiredMissionCharacter`) can always deploy. Whether
  they take the penalty is a setting.
- Droids use the same system ("needs maintenance" wording).
- The squad-select screen must show the exact penalty and what pushing will cost.

## Implementation plan

1. **v0 (no assets):** fatigue counter in a Lua-managed store; penalty applied through
   `UBrunoGameStatics::AddNextMissionCharacterEffect` with the shipped
   `GE_Lose_NextMission_*` effects. Proves the loop end to end.
2. **v1:** custom `GE_OffDuty_Fatigue` Blueprint (infinite, stacking, own tag and UI data)
   on the strategy character as the saved counter, plus a custom next-mission
   penalty GE. Roster-tile badge and squad-select warning.
3. Settings through MXM (if present), with sensible defaults when it isn't.

Open questions and evidence: `phase0-findings.md`. Probe: `../src/OffDutyProbe/`.
