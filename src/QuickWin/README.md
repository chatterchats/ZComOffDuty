# QuickWin (dev tool)

Never ships. **Ctrl+Shift+W** in a tactical mission wins it through the game's own
`BRGameMissionActor::CompleteMissionCheat`, so the normal success flow runs. Use it to test Off Duty's
loop without playing missions out. Wait for the first player turn first: Off Duty applies fatigue a few
seconds into the mission. Output goes to `UE4SS.log` with the `[QuickWin]` prefix.

Install: symlink this folder into `ue4ss/Mods/QuickWin` (it loads through `enabled.txt`).
