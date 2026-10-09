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
  fatigue counter, so no sidecar file is needed. _Must verify:_ that a GE class living
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

| Effect                                 | Modifier                               |
| -------------------------------------- | -------------------------------------- |
| `GE_Lose_NextMission_RangedAccuracy`   | AccuracyReduction +1 /stack (limit 99) |
| `GE_Lose_NextMission_LoseMaxHealth`    | MaxHealth −2 /stack (limit 99)         |
| `GE_Reward_NextMission_FirstMoveSpeed` | MovementPerAP +25                      |
| `GE_Reward_NextMission_Dodge`          | Strikes +2                             |

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

- ~~Q2 answered: the turn budget is 1 action + 1 move.~~ **Wrong: those were hub values; a mission turn is 3 AP (see Correction below).** Every deployed operator (Hawks,
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

1. _(Answered in run 3: −5% hit chance per point; one point per application.)_ **AccuracyReduction units.** Injury = 3, reward = 1–2, `MaxAccuracy` CDO = 1.0. What
   does +1 do to displayed hit chance? Test by stacking `GE_Lose_NextMission_RangedAccuracy`.
2. _(Answered: **3 AP per turn** in missions, for moving, shooting and abilities; see the correction below.)_ **Base AP budget** for operators (CDO is 0; set by an init effect or data). Codex
   assumed 3 and ChatGPT assumed 2. Read `ActionPoints` on a live unit.
3. _(Answered in run 2: no.)_ Is `CanAssignToMissionSquad` reached through ProcessEvent (hookable from Lua), or
   only native? Disassemble `WBP_RosterTile` / `VM_SquadSelect`.
4. _(Answered in run 2: after one mission.)_ When are `NextMissionCharacterEffects` consumed/cleared? (After any mission, or only
   after that character deploys?) That decides whether Tired survives being benched.
5. _(Next-mission penalties: answered by the save/uninstall test.)_ Mod-pak GE class reload safety and uninstall behavior, still open for v1's custom effect.
6. Droids: do astromechs share `BitReactorCombatSet` / the same roster flow?

## Static Blueprint inspection (blocked)

Tried 2026-10-08 with `AI+/tools/asset_audit.py package --disassemble` (GameAssetProbe,
patched 5.6.1 Linux editor, scratch workspace). Both packages crash the editor
(signal 11) during load, before inspection:

| Package                                                 | Fatal dependency                                                                           |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `/Game/Game/UI/Strategy/SquadSelect/BPs/VM_SquadSelect` | `AkAudioEvent /Game/WwiseAudio/UI/Strategy/SquadSelect/UI_STR_SquadSelect_CharSlot_Appear` |
| `/Game/Game/UI/Strategy/_Common/Widgets/WBP_RosterTile` | `AkAudioEvent /Game/WwiseAudio/UI/Strategy/SquadSelect/UI_STR_SquadSelect_Add`             |

This is the known missing-Wwise blocker (`AI+/BLOCKERS.md`): any UI package that
references Wwise UI sounds can't be loaded in the SDK. Q3 stays with the in-game
probe (`src/OffDutyProbe`). Data-only packages (GameplayEffects, recipes) without
audio references should still probe fine.

## Fatigue storage: a custom saved effect (2026-10-08)

### Which effects the game saves

`UBitReactorGameplayEffect` has `bIncludeInSaveData` and `bTerminateWithCombat` (UHT header; the
Modkit's proxy lacked all 5 of the class's properties). Across 674 game effects, 148 set
`bIncludeInSaveData`:

| Effect                  | `bIncludeInSaveData` | `bTerminateWithCombat` | Lifetime                     |
| ----------------------- | -------------------- | ---------------------- | ---------------------------- |
| `GE_Injured`            | true                 | false                  | saves and missions           |
| `GE_Lose_NextMission_*` | false                | true                   | one mission (explains run 2) |
| `GE_Shocked`            | true                 | true                   | in-mission status            |

No shipped saved effect is inert and stackable (the 6 infinite, modifier-free ones grant tags such as
Cloaked, Away or Dismissed), so Off Duty needs its own class.

### Tooling

- **SWZC Merged Kit** (`ZComMods/SWZCMergedKit/merge.py`): the SDK's complete classes plus the
  Modkit's mod pipeline. Builds on Linux; `GameAssetProbe` reads game effects identically to the SDK.
- `unreal/scripts/create_effects.py` authors the plugin's assets headlessly;
  `tools/build_plugin.sh` cooks, packages and assembles `SWZeroCompany/Mods/OffDuty/` like Mod
  Studio releases (`OffDuty.uplugin`, `AssetRegistry.bin`, `Content/Paks/OffDuty_P.*`).
- **The Linux editor can't cook for Windows** (target platform list: Linux, Android only; the same
  limit is recorded in AI+ backlog #10). The plugin is cooked for Linux. `GE_OffDuty_Fatigue` has
  no shaders, textures or platform-specific data, so the Linux cook should load in the Windows game.
  **Probe run 4 verifies this**, plus save persistence, a mission round trip and uninstall.
- Build notes: UAT needs `NuGetAudit=false` (new advisories for its bundled Magick.NET fail the
  script build), `UnrealPak` had to be built for Linux, and `UnrealPak -Extract` is broken on Linux.

### Probe run 4, step 1 (2026-10-08): the "Content Mod" layout doesn't load

With `SWZeroCompany/Mods/OffDuty/` (a Modkit "Content Mod", content mounted at `/OffDuty/`) the
game reported `Off Duty fatigue class | NOT FOUND`. The shipping game writes no log, but the Modkit
explains it: Content Mods in `Mods/` need a mod loader to mount and activate them, and the game's
`UBitReactorModRuntimeSubsystem` is native-only (its config maps official DLC entitlements).

**Switched to a Modkit "override" mod.** `unreal/OffDuty/Config/DefaultOffDuty.ini` sets
`RemapPluginContentToGame=True`; UAT passes `-RemapPluginContentToGame` and IoStore renames every
package `/OffDuty/<rest>` → `/Game/<rest>` through the container header's `PackageRedirects`
(the directory index keeps plugin paths). The effect is authored at
`/OffDuty/OffDuty/Effects/GE_OffDuty_Fatigue`, so in game it is
**`/Game/OffDuty/Effects/GE_OffDuty_Fatigue`**, and the pak ships as
`Content/Paks/~mods/OffDuty_P.{pak,ucas,utoc}`, mounted at startup like other `~mods` paks (and
supported by Zero Mod Manager). Override mods need no `GameFeatureData`. Run 4 restarts from step 1.

### Run 4, step 1 retries (2026-10-08)

- With the `~mods` pak, UE4SS `LoadAsset("/Game/OffDuty/Effects/GE_OffDuty_Fatigue")` returned an
  object, so the pak mounts and the remapped package resolves. But the class wasn't findable, and
  touching the returned object crashed the game. Most likely `LoadAsset` goes through the asset
  registry, which never merges a `~mods` pak's registry, and returns a bogus pointer. Saves don't use
  UE4SS: the engine resolves the effect class itself.
- The probe now loads classes the engine's way (`KismetSystemLibrary.MakeSoftClassPath` →
  `Conv_SoftClassPathToSoftClassRef` → `LoadClassAsset_Blocking`) and never touches unverified objects.
- **Step 1 passed (2026-10-08, turn 28):** `Off Duty fatigue class | loaded: BlueprintGeneratedClass
/Game/OffDuty/Effects/GE_OffDuty_Fatigue.GE_OffDuty_Fatigue_C`. **A Linux cook of a shader-free
  Blueprint loads in the Windows game**, so no Windows cooking is needed for Off Duty's plugin.
  `GetGameplayEffectCount` accepts the class (`OD_Fatigue=0` on all 8 operators with a hub actor).
  The `convert_struct_to_lua_table: Skipping field 'SubPathString'` line is UE4SS converting the
  soft path struct; harmless.

### Run 4, step 3 (2026-10-08): fatigue stacks did not survive save → load

Two stacks on every hub operator were back to 0 after saving and loading. What the headers show:

- `FAbilitySystemComponentInfo` (`ActiveEffects`) is used only by `BrunoTacticalSaveGame`, so
  **`bIncludeInSaveData` governs mid-mission (tactical) saves**, not the hub.
- The strategy save (`UBrunoStrategySaveGame.CharacterInfos`) stores each hub character as opaque
  native `ArchiveBytes`; which ability-system state goes in isn't visible from headers.
- `UTrackedPreloadObjects` keeps per-class "derivative" class lists for strategy and tactical,
  likely classes the save must preload to resolve references.

Next diagnostic: the dump prints the live default-object flags of `GE_OffDuty_Fatigue` and
`GE_Injured` and whether our class was already in memory; **Ctrl+Shift+I** applies one
`GE_Injured` the same way the probe applies fatigue, as a control for the save test.

### Run 4, step 3 diagnostic result (2026-10-08)

- Live default objects: `GE_OffDuty_Fatigue_C` and `GE_Injured_C` both `bIncludeInSaveData=true
bTerminateWithCombat=false DurationPolicy=1 (Infinite) StackingType=2 (AggregateByTarget)`. The
  cooked flags are right.
- After save → load, Hawks's control `GE_Injured` (applied by the probe exactly like fatigue)
  **survived**; fatigue on all 8 operators **didn't**. The hub save does keep probe-applied effects.
- Our class reported `loaded now` after the load: **it had been unloaded**. Nothing in the game
  references it, so a map change's garbage collection purges it, and the save (which seems to resolve
  effect classes only among loaded classes; cf. `UBrunoSaveGameSubsystem.TrackedPreloadObjects`)
  drops the effect. `GE_Injured` is always resident.
- UE4SS has no `AddToRoot`. Next: pre-hooks on the save subsystem's delegate-bound
  `OnPostLoadMap` / `OnWorldMatchStarting` and `UBrunoStrategySaveGame::ApplySaveInfo` load the
  class just before the save is applied, and log the load order.
- Retest with the save-flow pre-hooks: all six installed (`OnPreLoadMap`, `OnPostLoadMap`,
  `OnWorldMatchStarting`, `SaveGame`, `GatherSaveInfo`, `ApplySaveInfo`) but **none fired** on save or
  load: the save system calls them natively, outside ProcessEvent. Fatigue reset again (`loaded now`).
- Next: keep the class resident instead of loading it just in time. The probe can append it
  (**Ctrl+Shift+K**) to the game's own keep-loaded list, `UBrunoSaveGameSubsystem.TrackedPreloadObjects
.CachedObjects` (a transient `TArray<UObject*>` on a game-instance subsystem), and dumps report that
  list's size and whether our class is in it.
- Keep-loaded retest: the append worked (259 → 260, class PRESENT), but after the load
  `CachedObjects` was **0**: it's a temporary preload cache, filled for a load and then emptied.

### The hub save's real filter: the `Persists` asset tag (2026-10-08)

Saves live in the Proton prefix: `.../AppData/Local/SWZeroCompany/Saved/SaveGames/*.sav`. Each is
a **ZIP**: `SaveGame` (tagged-property data), `SaveGameTrackedClasses` (the preload lists),
`SaveGameSpawnedActors`, metadata, a screenshot and portraits.

The test save made 6 s after applying fatigue (`HUB_Root_2026.10.08-13.53.37.sav`) contains **no
trace of `GE_OffDuty_Fatigue`**: the effect was dropped while _saving_. Character effects are stored as
tagged `FGameplayEffectSpec`s with `Def = "/Game/.../GE_X.Default__GE_X_C"`, so effect classes are
loaded by path (they aren't on the preload lists, which cover rewards, customization, gear,
abilities, recipes and characters).

The 21 effect classes in that save: 19 have `bIncludeInSaveData=false`, so that flag isn't the hub
filter. **All 21 carry the asset tag `BitReactor.GameplayEffect.Persists`** (in
`InheritableGameplayEffectTags`); 52 other game effects have it too (Away, Dismissed, other
cross-training) and simply weren't on anyone. `GE_OffDuty_Fatigue` had no components and no tags.

**Fix:** the authoring script now adds an `AssetTagsGameplayEffectComponent` with
`BitReactor.GameplayEffect.Persists` (the class isn't exposed to Python, so it's loaded by path and its
`InheritableAssetTags` set by Unreal name; the tag text can't include `ParentTags`) and also sets the
deprecated `InheritableGameplayEffectTags`. The cooked package now names the component and the tag.

- **Verified in game (2026-10-08): with the `Persists` tag, fatigue survives a hub save → load.**
  One stack on all 8 operators with a hub actor, saved, loaded: `OD_Fatigue=1` on all 8, and the class
  was `already in memory` after the load (the save loads it by path). No preload or keep-loaded work is
  needed. Remaining run 4 checks: mission round trip (deployed and benched) and uninstall.
- **Mission round trip (2026-10-08): passes.** Fatigue stacks on deployed and benched operators survive
  a mission and the return to the hub.
- **Uninstall (2026-10-08): safe.** With `~mods/OffDuty_P.*` removed, the save made with fatigue loads
  normally and the probe shows `OD_Fatigue=0` (the game skips the effect it can't resolve). Putting the
  pak back and loading the same save restores the stacks: the save keeps the data until it's
  overwritten. (Saving while the mod is removed would drop fatigue for good, which is fine.)

**Phase 0 is complete.** Every piece of the design is verified in game: fatigue is stored as saved
stacks of `GE_OffDuty_Fatigue`, the penalty uses the game's next-mission accuracy effect, mission start
(`ApplyNextMissionEffectsToCharacter`) shows who deployed, `EndStrategyTurn` drives recovery, and
removing the mod can't break a save.

### Correction (2026-10-08): a turn is 3 AP

Run 1 concluded "1 action + 1 move" from **hub** attribute values (`ActionPoints=1`). The tactical
budget is different: run 2's in-mission dump shows `ActionPoints=3` on every deployed operator, and a
Zero Company turn is 3 AP spent on moving, shooting and abilities. Losing 1 AP costs a third of a
turn, so AP penalties are back on the table (see `penalty-theorycraft.md` §7–8).

### Probe run 5 (2026-10-08): tier penalties in a mission

Spent was queued on 9 roster operators (Ctrl+Shift+3) before a mission, with `test_ap_loss_chance = 0.5`.

- **Accuracy:** `AccuracyReduction` 0 → 3 (−15%) on every deployed Spent operator.
- **Max HP ×0.9 works**, and operators start at the reduced maximum: Jae Mordant 73 → 66,
  Cly Kullervo 85 → 77, Tesh Hawks 97 → 87 (Health equal to MaxHealth at mission start). The
  multiplier applies to the aggregated value, not to the base of 28.
- **Movement ×0.95 works:** `MovementPerAP` 500 → 475, 700 → 665.
- **The AP loss works (3 → 2), but it rolled twice per round.** Each round starts team turns for
  `WorldTeam_PrePlayer` and then `PlayerTeam`, and the probe's substring match on "player" caught both.
  At `PrePlayer` the AP isn't refilled yet (the hook saw 1 or 2); at `PlayerTeam` it is already 3.
  Fixed: match `/Game/Game/GameData/Teams/PlayerTeam.PlayerTeam_C` exactly.
- **Rex was not penalized** because he isn't in the roster list the tier was queued on (a story/guest
  unit). Real Off Duty should track whoever deploys, and decide whether guest units take fatigue at all.
- **Nothing shows in the briefing or squad select.** Next-mission effects aren't surfaced there,
  even the game's own `GE_Lose_NextMission_*`; the only native display is the "Penalty from
  Operation" line in the hit breakdown. Off Duty needs its own UI (roster badge, squad-select warning).

### Squad-select injury banner (2026-10-08, Ctrl+Shift+U)

Each squad slot (`WBP_CharacterSlot_C`) has a `WBP_InjuryWarningEntry` ("1 INJURY"). It binds a
`BrunoGameplayEffectListViewModel` whose `EffectQuery` is only `EffectTagQuery` = any of
`UI.Notification.Injury` (tokens `0 1 1 1 0`); the banner shows the matched effects' stack count.
`GE_Injured` carries that asset tag plus `Persists`, `StatusEffect.Negative`, `Strike.Injured`,
`Status.Character.Injured` and `br.UI.Effect.CoreCondition`, grants `Status.Character.Injured`,
and has `BRG_StatusEffectUIData` and `BRG_InjuryNotificationComponent`.

So fatigue can't borrow the banner by tag (it would read "N INJURY" and count as an injury).
Plan: a second copy of the same widget per slot, driven from Lua (Ctrl+Shift+B prototype).

### Injuries: 3 is death (user, 2026-10-08)

A third `GE_Injured` stack kills the operator. Test tooling must never apply more than 2 (the probe
caps both Ctrl+Shift+I and `config.test_squad` at 2), and Off Duty must never add injuries.

### Banner colour (2026-10-08)

`WBP_InjuryWarningEntry`'s design-time colours are the palette's AccentYellow (0.98, 0.45, 0.07) and it
carries a `T_UI_Strategy_HighRiskInjury` icon, so it has a yellow warning look too. At runtime its
state animation (`States`) sets AccentRed1 (0.45, 0.01, 0.03): a copy's colours set at creation were
back to red a frame later, and the glow's opacity animates. Banner images are plain colour tints
(no material, no palette tag). Palette (`UBitReactorColorBank`): AccentRed1/2, AccentYellow, Blue1-3,
Grey1-3, OffWhite, Foreground, PositiveTeal, Player.*, Enemy.*.
**Result:** `StopAllAnimations` on the copy, then `SetColorAndOpacity` on Back/PillBack/EndCapBG/GlowBack/
PillBack_Highlight (100 ms after creation), holds: the fatigue banner renders in AccentYellow next to
the red injury banner. Tier label, pips (1 Tired, 2 Exhausted/Spent) and 250x34 + label sizing all
match the game's look. Verified in game 2026-10-08.

### Fatigue UI prototype verified (2026-10-08)

- **Recolour timing:** `StopAllAnimations` restores the widget's design colours on a later frame, so
  recolouring in the same call was overwritten (every tier read AccentYellow). Stop, then recolour
  ~150 ms later: Tired (0.98, 0.75, 0.07), Exhausted AccentYellow, Spent AccentRed1 all hold.
- **Tooltip:** the injury banner's `WarningTooltip` (`BitReactorTooltipBox`) renders from payload tag
  `UI.Keyword.Injured`. Clearing tags and setting one `FTooltipPaylodEntry` {HeaderText, BodyText}
  shows our own rich text (`<Bold>` works).
- **Portrait strip:** `WBP_RosterTile_C` (also used on roster screens). Its list item
  (`UserObjectListEntryLibrary.GetListItemObject`) is a `BrunoCharacterViewModel`; `GetCharacterID`
  matches roster IDs. A copy of its `WBP_HeroInjuries` (Overlay > BitReactorTooltipBox > Injury_1/2)
  in the same Overlay, aligned right, one image set to `T_UI_StatusEffect_Lethargy` and tinted,
  marks fatigue. Note: UE4SS's `UObject:GetFullName()` shadows the view model's `GetFullName`; read
  the `FullName` property.

### In-mission debuff (2026-10-08)

The Inspect panel's Debuffs list is a `BRG_ActiveStatusEffectsListViewModel` with `EffectTagQuery` = any
of `BitReactor.GameplayEffect.StatusEffect.Negative` (Buffs: `...StatusEffect.Positive`; also lists for
`GameplayEffect.Passive`, `br.UI.Effect.CoreCondition`, Backup buffs). An effect shows once it carries
`BRG_StatusEffectUIData` (GE_Injured's component; only the first UI data component counts). Verified:
the tier effect appeared under Debuffs, but named "Lethargy" with the Seer's description: the name,
description and icon come from the `StatusEffectTag`'s tag UI data (`UBitReactorTagUIDataViewModel`,
`FindOrCreateTagUIDataViewModel`), not from the component's PreviewTitle. GE_Injured's status tag is
`ImageBank.Icon.Character.Status.Injury`.

Next: own tags `OffDuty.Status.<Tier>` (Config/Tags/OffDutyTags.ini, shipped in the plugin config and in
`OffDutyTags_P.pak` at the project's Config/Tags) with their tag UI view models filled in from Lua.
The editor ignores an explicitly loaded plugin's Config/Tags, so the build copies the ini into the
kit's Config/Tags for authoring.

Result with own tags: they register at runtime (`GE_OffDuty_Tired` loads with `OffDuty.Status.Tired`), so
the Lethargy text is gone, but the status shows blank: `FindOrCreateTagUIDataViewModel` returns nothing
for a tag without game UI data, so the status view model has no `StatusEffectTagVM` (name empty, tag
None). Next: each tier effect also carries its tag as an asset tag, and Lua constructs a
`BitReactorTagUIDataViewModel` per tier (name, description, Lethargy icon) and assigns it to our statuses'
`StatusEffectTagVM`, from a post-hook on `BRG_ActiveStatusEffectsListViewModel:GetStatusEffects` plus
timed passes after mission start.

**Verified in game (2026-10-08):** Tired, Exhausted and Spent show under Debuffs in the Inspect panel with
their own names, descriptions (rich text works) and the Lethargy icon. The post-hook on
`BRG_ActiveStatusEffectsListViewModel:GetStatusEffects` attaches the view model when a list is first read
(Spent attached when its Inspect panel opened); Lua `StaticConstructObject` of
`BitReactorTagUIDataViewModel` and setting its FText fields from `FText()` both work. Timed passes were
never needed. Tier descriptions are per tier (shared view model), so per-operator details such as
fatigue points belong in the squad-select tooltip.

### Health-bar icons and custom icons (2026-10-09)

The status icons beside the tactical health bar come from lists filtered on `br.UI.Effect.CoreCondition`
(GE_Injured and Backup Available carry it); adding it to the tier effects shows them there (verified).
The HUD portraits at the bottom of the screen show injuries only. Off Duty draws its own tier icons
(`unreal/scripts/draw_icons.py`: white Zzz glyphs, one to three Z's), imported as uncompressed UI textures
(TC_EditorIcon, no mips) and cooked into OffDuty_P. Lua sets them as a plain brush (type None,
ResourceObject = texture) on the tier view models, and on the squad-select banner and portrait markers.

Run with icons (2026-10-09): hovering the Inspect entry crashed once (null read, no Lua error; callstack
unresolvable under Proton) and not on a retry with the Ctrl+Shift+H trace on, which showed the tooltip
only calling the plain getters. Likely cause: Lua cached the tag view models it constructed, but a Lua
reference doesn't keep a UObject alive, so a freed one could be attached again. The probe now builds a
fresh view model per status and caches no UObjects. Icons: the textures cook correctly (inline
PF_B8G8R8A8, 64 KB) and are in the container, but `LoadAsset_Blocking` on
`/Game/OffDuty/Icons/T_OffDuty_Fatigue_N` returns nothing in game, under the plugin paths too, while a
control load of `GE_OffDuty_Tired_C` through the same loader works: a texture cooked on Linux doesn't
load in the Windows game (data-only Blueprints do). Icons now ship as PNGs in the Lua mod (`icons/`) and
are loaded with `KismetRenderingLibrary.ImportFileAsTexture2D`; the plugin cooks no textures.

Icon crash (2026-10-09): with the PNG imported, starting the first turn crashed twice (null+0x70, then a
garbage address) before the probe logged the tag view model it was building. `tools/minidump.py` on the
dumps (`Saved/Crashes/UECC-*/UEMinidump.dmp` in the Proton prefix) puts both inside UE4SS.dll (one in
memcpy called from it), so a Lua operation crashed, not the game's UI. Suspect: UE4SS 3.0.1 writing a
field inside a struct property (`vm.TagBrush.ResourceObject = texture`); whole-struct copies and
object-property writes on UObjects have worked. Bisect run pending (config.status_icon = "bisect").
**Bisect result:** the last line before the crash was `writing TagBrush.WeakResourceObject`; the PNG import
and the `ResourceObject` write (inside the struct) both succeeded and the Exhausted view model attached.
**Writing a soft-object property crashes UE4SS 3.0.1** (also with `nil`). Never write soft pointers from
Lua. Next run compares leaving the brush type as Texture2D against setting it to None.
**Compare result (verified in game):** with only `ResourceObject` set, a Texture2D-type brush still draws the
Lethargy icon (the soft pointer is loaded over it); setting `BrushType = None` as well draws our Zzz icon
beside the health bar, with no crash. Recipe: copy the Lethargy brush whole, then set `ResourceObject` to
the imported texture and `BrushType` to None; never write `WeakResourceObject`.

### Real mod, first loop runs (2026-10-09)

- Fatigue added on the tactical character during a mission carries back to the hub and into the hub
  autosave (decoded from `Autosave_Den`: the post-mission stacks). The deployed marker's clear at turn end
  also carries back. **One mission is one strategy turn: `EndStrategyTurn` fires as the mission ends.**
- `ApplyNextMissionEffectsToCharacter` fires before the roster can be read, and **also when a tactical
  save loads, before the save restores effects**: the first build read fatigue 0, added 2, then the
  save's stacks landed on top (9 > cap). Off Duty now waits for the mission actor to be ready
  (`bIsMissionActorReady`, `MissionStatus` Active, not ending), then uses the deployed marker to tell a
  new mission (apply tier, mark, add fatigue) from a loaded save (restore the tier only).
- Tier effects weren't kept by tactical saves (copied the game's `bIncludeInSaveData = false`); they're
  saved now. The game's accuracy stacks are topped up from the tier on a loaded save.
- **Correction:** `bIsMissionActorReady` comes before a tactical save finishes restoring effects. Processing
  then (fatigue read 0, effects added) crashed the game (access violation in SWZeroCompany.exe, 3 s after).
  Off Duty now checks `UBitReactorGameInstance::IsLoadingFromSaveGame` / `AGameGameplayMaster::IsLoadingFromSave`
  and `UBitReactorAbilityScriptingFunctions::WasLoadedFromSave(actor)`, waits until no save is loading
  (plus 500 ms), and never adds fatigue on a loaded save.
