# Off Duty: Phase 0 findings

Desk research against `ZeroCompany_RE_Reference_v2` (UHT headers, JMAP CDO values,
asset index). Nothing here has been tested in game yet. See "Open questions".

## How injuries work today

`/Game/Game/GameData/Abilities/ResultEffects/GE_Injured`

- Infinite duration, `AggregateByTarget` stacking, **stack limit 2**.
- One modifier: `BitReactorCombatSet.AccuracyReduction` AddBase **+3** per stack.
- Grants tag `BitReactor.Status.Character.Injured`.
- Components: asset tags, target tags, `BRG_StatusEffectUIData` (native status UI),
  `BRG_InjuryNotificationComponent`.
- Applied by `GE_DownedAppliesInjury` (instant, conditional) when a unit goes down;
  removed by `GE_RemoveInjured` (Medbay recipes `Medbay_Bed*_InjuryRecover`,
  `Medbay_BactaTank_InjuryRecover`).
- Queries: `UBitReactorGameStatics_Unit::IsUnitInjured / GetUnitInjuryCount`.

Exhaustion should stay separate from this. Reusing injuries stacks with the
downed → injury → death pressure the game already has.

## Persistence: strategy characters' effects are saved

- `FAbilityActorInfo.ASCInfo` → `FAbilitySystemComponentInfo` saves
  `AttributeSetsAndValues`, `ActiveEffects` (`FActiveGameplayEffectInfo`: full
  `FGameplayEffectSpec` + context bytes) and `GameplayTags`. That's how injuries
  survive save/load.
- **Implication:** a custom infinite, stacking `GE_OffDuty_Fatigue` Blueprint on the
  strategy character should save the same way. The stack count can serve as the
  fatigue counter, so no sidecar file is needed. *Must verify:* that a GE class living
  in a mod pak reloads cleanly, and what happens to the save if the mod is removed.

## Existing "next mission only" effect pipeline (Tired penalty)

`UBrunoGameStatics` (all BlueprintCallable, Lua-callable):

- `AddNextMissionCharacterEffect(WCO, CharacterID, EffectClass, PrimaryMagnitude)`
- `ApplyNextMissionEffectsToCharacter(Character)`, `ClearNextMissionEffects(WCO)`
- also `AddRosterEffect`, `AddNextMissionEffect` (whole roster)

Stored in `FBrunoStrategyData.NextMissionCharacterEffects : TMap<FGuid, FBrunoRosterEffects>`
(soft class + magnitude), which is part of the strategy save. `UBrunoMissionViewModel`
exposes `NextMissionEffectVMs`, so the briefing likely lists them natively.

Existing classes in `/Game/Game/GameData/Progression/NextMissionGameplayEffects/`:

| Effect | Modifier |
|---|---|
| `GE_Lose_NextMission_RangedAccuracy` | AccuracyReduction +1 /stack (limit 99) |
| `GE_Lose_NextMission_LoseMaxHealth` | MaxHealth −2 /stack (limit 99) |
| `GE_Reward_NextMission_FirstMoveSpeed` | MovementPerAP +25 |
| `GE_Reward_NextMission_Dodge` | Strikes +2 |

The penalty effects all carry `GEC_StrategyRewardText` + `BrunoGameEffectUIData`, so
they come with native text.

Probed `GE_Lose_NextMission_RangedAccuracy` (GameAssetProbe, 2026-10-08):

- Infinite, `AggregateByTarget`, limit 99, `NeverRefresh`, `ClearEntireStack`.
- `DurationChangeEventTriggerTags = BitReactor.AbilityTrigger.StrategyStart`: its
  duration is re-evaluated when the strategy layer starts. **Likely answer to Q4:** these
  effects clear on returning to the hub, so they last one mission. To confirm in game.
- `GEC_StrategyRewardText`: `Modifier Value Per Stack = 1.0`, `Reward Value Format =
  Reward_FlatValue_Format`, name key `Progression_Lose_RangedAttackAccuracy_Name`
  (`Design_Progression_Strings`). The game describes it per stack, so
  **`PrimaryMagnitude` is probably the stack count**. The string table's text isn't
  reflected, so the exact wording needs the in-game check.
- `BrunoGameEffectUIData`: `NotificationTag = UI.Notification.StatusEffect.Negative`,
  tactical description key `Progression_Lose_RangedAttackAccuracy_Tactical`.

This means a v0 prototype needs **zero new assets**: apply `GE_Lose_NextMission_*`
stacks to tired characters. A custom Blueprint GE comes later, for custom text
and icons and a dedicated tag.

## Attributes available for penalties (`BitReactorCombatSet`)

`ActionPoints, RefreshActionPoints, MovementActionPoints, RefreshMovementActionPoints,
MovementPerAP, Aim, Accuracy, MaxAccuracy (CDO 1.0), AccuracyReduction, CriticalHitCount,
SpecialActionPoints, ClassTacticPoints, …`. `BitReactorHealthSet`: `MaxHealth`, `IncomingDamageMultiplier`, ….
`GE_ModifyMovementDistance` modifies `MovementPerAP` by SetByCaller (reusable).

## Deployment gating / story safety

- `ABrunoMissionCentral::CanAssignToMissionSquad(MissionID, CharacterID)` (native)
- `ABrunoMissionCentral::GetRequiredMissionCharacter(CharacterID, MissionID, out FRequiredMissionCharacter)`
  → `{CharacterID, SpawnerTags, bBlockingRequirement}`. **Story exemption check.**
- `GetCharacterIDsOnMission(MissionID)`, `GetCurrentMissionID()`. Use these to find who deployed.
- `UBrunoMissionSquadSlotViewModel_Settings.RequiredCharacterID`
- UI: `WBP_RosterTile_C:IsRosterTileSelectable` (BP), `UVM_SquadSelect_C` (`LastSquad` memory).
- Mission results: `UBRGameMissionToHubData` (`MissionStatus`, `KilledPlayerCharacterIDs`,
  `EndingInjuredPlayerCharacterIDs`, `TotalTacticalRounds`).

## Recovery clock

- `ABrunoStrategyTurnManager.OnStrategyTurnBegin(int32 Turn)` / `GetStrategyTurn()`.
- Roster "Away" state (`ABrunoRosterManager.AwayCharacters`, `OnRosterCharacterSentAway/Returned`)
  is an existing unavailability state, for future multi-cycle field tasks.

## In-game probe run 1 (2026-10-08, strategy turn 28, skirmish SK_Brentaal_030)

- **Q2 answered: the turn budget is 1 action + 1 move.** Every deployed operator (Hawks,
  Kabb Uppercut, Kara Nova, BR-1) had `RefreshActionPoints=1`,
  `RefreshMovementActionPoints=1`, `SpecialActionPoints=1`, `ClassTacticPoints=1`.
  Losing one AP would cost a whole action or the whole move, so **AP penalties are out**.
- Base `Accuracy=8` with `MaxAccuracy=1` and `AccuracyReduction=0` on all four. What a
  point of `AccuracyReduction` does to displayed hit chance is still open (Q1).
- `MaxHealth` base 28 for everyone; current 62–97 after upgrades/class effects.
- **Mission start is hookable from Lua.** The game calls
  `UBrunoGameStatics::ApplyNextMissionEffectsToCharacter` once per deployed operator
  (tactical actors, e.g. `Char_Hero_HAWKS_Control_C`) through ProcessEvent, so a
  post-hook sees every squad member as the mission loads.
- Droids share the flow: BR-1 has `BitReactorCombatSet`/`HealthSet` and receives
  `ApplyNextMissionEffectsToCharacter` like humanoids (Q6, mostly).
- `GameInstance.StrategyData.NextMissionCharacterEffects` was 0 at the hub and in the mission.
- Squad-select Blueprint hooks (`IsRosterTileSelectable`, `VM_SquadSelect` clicks)
  installed once their classes were loaded at the hub, but no calls were logged.
  `CanAssignToMissionSquad` was never seen either.
- Probe bug: `GetRoster` came back empty, so the roster dump and the test apply
  found nobody. Fixed by accepting plain Lua tables from UFunction returns and falling
  back to `ABrunoRosterManager.Roster`. Needs run 2.

## In-game probe run 2 (2026-10-08, turn 28 → 29, same skirmish)

- **The roster fix works.** `GetRoster` returns a plain Lua table: 10 operators at the hub
  (two without a live hub actor, one of them Away), 4 in the mission (the squad only).
- **Test apply works, and the game shows it natively.** `AddNextMissionCharacterEffect(Hawks,
  GE_Lose_NextMission_RangedAccuracy, 5)` → in the mission Hawks had **1 stack** and
  `AccuracyReduction` 0 → 1. The hit breakdown listed **"PENALTY FROM OPERATION −5%"**, and
  shots that would have been 100% showed 95%.
  - So `PrimaryMagnitude` is **not** the stack count (5 gave 1 stack).
  - Most likely **1 `AccuracyReduction` = −5 percentage points of hit chance**. That would make
    an injury stack (+3) −15%. Run 3 (magnitude 1, applied twice) confirms both.
- **Q4 answered: next-mission effects last exactly one mission.** After the mission and
  `EndStrategyTurn` (turn 29), Hawks had 0 stacks and `NextMissionCharacterEffects` was
  empty. `ClearNextMissionEffects` / `CompleteMission` never logged, so the clearing is native.
- `EndStrategyTurn` fires through ProcessEvent (hookable); `BeginStrategyTurn` didn't log.
- **Q3 answered (negatively): squad select can't be hooked this way.** Adding/removing
  operators produced no calls to `IsRosterTileSelectable`, the `VM_SquadSelect` click
  functions or `CanAssignToMissionSquad`, though the hooks were installed. The push-through
  model doesn't need to block deployment, so this only affects a later squad-select UI.

### What this means for v0

Every piece of the core loop is now proven hookable or callable from Lua:

1. **Who deployed:** post-hook `ApplyNextMissionEffectsToCharacter` (one call per squad
   member at mission load) → `GetActorCharacterID`.
2. **Recovery clock:** post-hook `EndStrategyTurn`.
3. **Penalty:** `AddNextMissionCharacterEffect` with the shipped accuracy effect. It shows
   natively in the hit breakdown and clears itself after one mission. Re-add it each cycle
   for operators who are still tired.
4. **Fatigue storage (v0):** a sidecar file keyed by `FBrunoStrategyData.CampaignTelemetryID`
   (a per-campaign GUID). In v1 this becomes the custom `GE_OffDuty_Fatigue` stack on the
   strategy character.

## In-game probe run 3 (2026-10-08, turn 29)

- Same game session as run 2, so the probe still had `test_magnitude = 5` (config only
  reloads on restart). Two `Ctrl+Shift+T` presses on Hawks → the hit breakdown showed
  **"PENALTY FROM OPERATION −10%"**. `NextMissionCharacterEffects` stayed at 1 entry (one
  per character).
- **Q1 answered:** each `AddNextMissionCharacterEffect` call adds one stack, and each stack
  (`AccuracyReduction` +1) is **−5 percentage points** of hit chance. `PrimaryMagnitude`
  doesn't scale this effect (5 → one −5% stack in run 2). An injury stack (+3) is
  therefore −15%.
- Design consequence: penalty size = number of applications. Placeholder: Tired 1 stack
  (−5%), Exhausted 2 stacks (−10%), deeper exhaustion 3 stacks (−15%), capped below an
  injury's single-stack weight.

## Save/uninstall test (user, 2026-10-08, fresh save)

Applied 4 stacks at the hub → saved → reloaded that save → mission: **−20%** ("Penalty from
Operation"). Next mission: no penalty.

- Queued next-mission effects are **stored in the save** (`FBrunoStrategyData.NextMissionCharacterEffects`).
- The game has **no stack cap of its own** (4 × −5% = −20%). Any cap is Off Duty's choice.
- **Uninstall safety:** with the mod removed, a leftover penalty lasts at most one mission,
  then the game clears it.

## Open questions (need game/probe testing)

1. *(Answered in run 3: −5% hit chance per point; one point per application.)* **AccuracyReduction units.** Injury = 3, reward = 1–2, `MaxAccuracy` CDO = 1.0. What
   does +1 do to displayed hit chance? Test by stacking `GE_Lose_NextMission_RangedAccuracy`.
2. *(Answered in run 1: 1 action + 1 move.)* **Base AP budget** for operators (CDO is 0; set by an init effect or data). Codex
   assumed 3 and ChatGPT assumed 2. Read `ActionPoints` on a live unit.
3. *(Answered in run 2: no.)* Is `CanAssignToMissionSquad` reached through ProcessEvent (hookable from Lua), or
   only native? Disassemble `WBP_RosterTile` / `VM_SquadSelect`.
4. *(Answered in run 2: after one mission.)* When are `NextMissionCharacterEffects` consumed/cleared? (After any mission, or only
   after that character deploys?) That decides whether Tired survives being benched.
5. *(Next-mission penalties: answered by the save/uninstall test.)* Mod-pak GE class reload safety and uninstall behavior, still open for v1's custom effect.
6. Droids: do astromechs share `BitReactorCombatSet` / the same roster flow?

## Static Blueprint inspection (blocked)

Tried 2026-10-08 with `AI+/tools/asset_audit.py package --disassemble` (GameAssetProbe,
patched 5.6.1 Linux editor, scratch workspace). Both packages crash the editor
(signal 11) during load, before inspection:

| Package | Fatal dependency |
|---|---|
| `/Game/Game/UI/Strategy/SquadSelect/BPs/VM_SquadSelect` | `AkAudioEvent /Game/WwiseAudio/UI/Strategy/SquadSelect/UI_STR_SquadSelect_CharSlot_Appear` |
| `/Game/Game/UI/Strategy/_Common/Widgets/WBP_RosterTile` | `AkAudioEvent /Game/WwiseAudio/UI/Strategy/SquadSelect/UI_STR_SquadSelect_Add` |

This is the known missing-Wwise blocker (`AI+/BLOCKERS.md`): any UI package that
references Wwise UI sounds can't be loaded in the SDK. Q3 stays with the in-game
probe (`src/OffDutyProbe`). Data-only packages (GameplayEffects, recipes) without
audio references should still probe fine.
