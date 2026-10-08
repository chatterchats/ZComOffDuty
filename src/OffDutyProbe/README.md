# Off Duty Probe (dev tool)

A throwaway UE4SS mod that answers the open questions in
`docs/phase0-findings.md`. It doesn't ship.

Install it like any UE4SS mod (copy this folder into `ue4ss/Mods/` as
`OffDutyProbe`, keeping `enabled.txt`). Output goes to `off_duty_probe.log` beside the mod, and to `UE4SS.log`.
Keys avoid F10 (ConsoleEnablerMod's console) and F11 (fullscreen toggle).

- **Ctrl+Shift+D** dumps every roster operator (or player unit, in a mission):
  AP, movement, accuracy and health attributes, injury count, availability,
  and stack counts of `GE_Injured` and the next-mission penalty effects. It also
  retries the squad-select / roster-tile hooks.
- **Ctrl+Shift+F / Ctrl+Shift+G** add / remove one `GE_OffDuty_Fatigue` stack on every
  roster operator who has a live actor (needs the OffDuty plugin, `tools/build_plugin.sh --install`).
  Writes to your save once you save, so **use a throwaway save**.
- **Ctrl+Shift+T** calls `AddNextMissionCharacterEffect` on one operator (see
  `Scripts/config.lua`). This is the probe's only write to the game. **Use a throwaway save.**

Always on: logs calls to turn begin/end, mission complete/fail,
`CanAssignToMissionSquad`, the next-mission effect functions, and the squad-select
clicks once their screen has loaded.

## Test run (about 15 minutes, throwaway save)

1. Load a mid-campaign save at the hub. Press **Ctrl+Shift+D**.
   → base AP values (Q2), whether roster actors carry attribute sets, injury stacks.
2. Open squad select for any mission, press **Ctrl+Shift+D** again, then add/remove a
   couple of operators. → whether `IsRosterTileSelectable` / `CanAssignToMissionSquad`
   fire (Q3).
3. Back at the hub, press **Ctrl+Shift+T**. Note the operator it names. Check the mission
   briefing for a listed penalty.
4. Deploy that operator. In the first player turn, press **Ctrl+Shift+D** and note their
   `AccuracyReduction` / stack count. Compare the displayed hit chance on one target
   against a squadmate with the same weapon (Q1, and whether magnitude = stacks).
5. Finish (or auto-resolve) the mission, return to the hub, end a turn, then
   **Ctrl+Shift+D**. → when next-mission effects are cleared (Q4).
6. Optional: deploy an astromech in step 4 to check droids (Q6).

Send me `off_duty_probe.log` afterwards.

## Run 4: the fatigue effect (throwaway save; uninstall test last)

Needs `SWZeroCompany/Mods/OffDuty/` (`tools/build_plugin.sh --install`). It's a **Linux** cook, so
step 1 also tells us whether that works in the Windows game.

1. Start the game, load a throwaway save at the hub, press **Ctrl+Shift+D**. Look for
   `Off Duty fatigue class | loaded`. If it says `NOT FOUND`, stop and send the log.
2. Press **Ctrl+Shift+F** twice: every operator at the hub should log `stacks now 2`.
3. **Save**, quit to the main menu, load that save, **Ctrl+Shift+D**: `OD_Fatigue=2`? (survives a save)
4. Deploy some of them on a mission (bench the rest). In the mission, **Ctrl+Shift+D**. Finish the
   mission, and back at the hub, **Ctrl+Shift+D**: deployed *and* benched operators still at 2?
5. Uninstall test: quit, move `SWZeroCompany/Mods/OffDuty` out of the game folder (keep the
   probe), start, load the step-3 save. Does it load? **Ctrl+Shift+D**. Then put the folder back,
   restart, load the same save, **Ctrl+Shift+D** again.
