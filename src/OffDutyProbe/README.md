# Off Duty Probe (dev tool)

A throwaway UE4SS mod that answers the open questions in
`docs/phase0-findings.md`. It doesn't ship.

Install it like any UE4SS mod (copy this folder into `ue4ss/Mods/`, keeping
`enabled.txt`). Output goes to `off_duty_probe.log` beside the mod, and to `UE4SS.log`.

- **Shift+F10** dumps every roster operator (or player unit, in a mission):
  AP, movement, accuracy and health attributes, injury count, availability,
  and stack counts of `GE_Injured` and the next-mission penalty effects. It also
  retries the squad-select / roster-tile hooks.
- **Shift+F11** calls `AddNextMissionCharacterEffect` on one operator (see
  `Scripts/config.lua`). This is the probe's only write to the game. **Use a throwaway save.**

Always on: logs calls to turn begin/end, mission complete/fail,
`CanAssignToMissionSquad`, the next-mission effect functions, and the squad-select
clicks once their screen has loaded.

## Test run (about 15 minutes, throwaway save)

1. Load a mid-campaign save at the hub. Press **Shift+F10**.
   → base AP values (Q2), whether roster actors carry attribute sets, injury stacks.
2. Open squad select for any mission, press **Shift+F10** again, then add/remove a
   couple of operators. → whether `IsRosterTileSelectable` / `CanAssignToMissionSquad`
   fire (Q3).
3. Back at the hub, press **Shift+F11**. Note the operator it names. Check the mission
   briefing for a listed penalty.
4. Deploy that operator. In the first player turn, press **Shift+F10** and note their
   `AccuracyReduction` / stack count. Compare the displayed hit chance on one target
   against a squadmate with the same weapon (Q1, and whether magnitude = stacks).
5. Finish (or auto-resolve) the mission, return to the hub, end a turn, then
   **Shift+F10**. → when next-mission effects are cleared (Q4).
6. Optional: deploy an astromech in step 4 to check droids (Q6).

Send me `off_duty_probe.log` afterwards.
