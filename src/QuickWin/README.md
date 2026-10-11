# QuickWin (dev tool)

Never ships. **Ctrl+Shift+W** in a tactical mission wins it through the game's own
`BRGameMissionActor::CompleteMissionCheat`, so the normal success flow runs. Use it to test Off Duty's
loop without playing missions out. Output goes to `UE4SS.log` with the `[QuickWin]` prefix.

**Wait for Off Duty first.** It applies tiers and fatigue once the mission is fully ready, which took
about 30 seconds in testing. Win before then and the squad's characters are gone when it tries: the log
shows "Skipped delayed action | group=mission_start" and the mission doesn't count (no fatigue, and
nobody is marked as deployed). Wait until `off_duty.log` has a `Mission start | <name> | fatigue …` line
for each operator, then press Ctrl+Shift+W.

Install: symlink this folder into `ue4ss/Mods/QuickWin` (it loads through `enabled.txt`).
