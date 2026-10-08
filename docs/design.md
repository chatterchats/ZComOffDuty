# Off Duty: design (working draft)

## Decisions so far (2026-10-07)

- **Exhaustion is separate from injuries.** It doesn't apply or remove `GE_Injured`.
- **Push-through model.** Exhausted operators can always deploy. The cost is a bigger
  penalty plus extra recovery afterwards. Hard locks are out of scope (no save can get stuck).
- **Logic Blueprints are allowed** (Modkit). No art or level assets.
- **Built to work alongside Aranthar's Long War campaign mod** and standalone on vanilla.
- **Fatigue is stored in the save** as stacks of a custom `GE_OffDuty_Fatigue` (2026-10-08). The
  sidecar-file plan is dropped: it couldn't follow save reloads.

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
