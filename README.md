# Off Duty

[![Nexus Mods](https://img.shields.io/badge/Nexus%20Mods-Off%20Duty-d98f40)](https://www.nexusmods.com/starwarszerocompany/mods/315)
[![UE4SS](https://img.shields.io/badge/framework-UE4SS-6f42c1)](https://github.com/UE4SS-RE/RE-UE4SS)
[![License: MIT](https://img.shields.io/badge/license-MIT-2f7d4f)](LICENSE)

Off Duty is a UE4SS mod for **Star Wars: Zero Company** that adds **operator
fatigue and recovery**: operators tire from back-to-back deployments and
recover while they sit missions out, so the whole company matters, not just
your best four.

Players should download the release ZIP from
[Nexus Mods](https://www.nexusmods.com/starwarszerocompany/mods/315) or the
[GitHub releases](https://github.com/chatterchats/ZComOffDuty/releases); the mod page text, with
the rules and install steps, is in [`docs/nexus/`](docs/nexus/) and the in-ZIP player guide is
`src/OffDuty/README.md`.

## Commands

`make help` lists everything. The usual loop: edit, `make test`, `make install`, restart the game.

| Target | Does |
| --- | --- |
| `make test` | the LuaJIT tests (UE4SS fakes) and the script-reachability test |
| `make install` / `make uninstall` | link `src/OffDuty` into `ue4ss/Mods` and `src/OffDuty_Assets` into `~mods`, or remove the links |
| `make package` | `dist/ZComOffDuty-X.Y.Z.zip`, laid out as the game's `SWZeroCompany` folder; refuses stale paks |
| `make bump V=X.Y.Z` | set the version everywhere (both components, the player README title), date the changelog |
| `make release` | check, test, tag, push; CI publishes to GitHub and Nexus (mod 315) |
| `make build-plugin` | cook the gameplay effects and tags with the SWZC Merged Kit into `src/OffDuty_Assets` (`ARGS=--install` also copies them into the game) |
| `make simtest ARGS='…'` | AI-vs-AI balance sims through ZC Sandbox on a game copy ([docs/simtest-handoff.txt](docs/simtest-handoff.txt)) |
| `make sync-instances` | copy the scripts and paks into the simtest game copies |
| `make check` / `make sync` | drift from the standard / fetch the latest shared files |

## Layout

The standard layout (see `../ModTemplate/STANDARD.md`). Specific to this repo:

- Two shipped folders: `src/OffDuty/` (the UE4SS mod: `Scripts/`, the tier `icons/`,
  `MXM/settings.lua`) and `src/OffDuty_Assets/` (the committed paks with their own manifests).
  The ZIP puts them at `Binaries/Win64/ue4ss/Mods/OffDuty` and
  `Content/Paks/~mods/OffDuty_Assets`: Vortex's Zero Company extension needs both `Binaries` and
  `Content` at the root to install it as one combo mod, and each component keeps its manifests so
  Zero Mod Manager and Mod Command install the pair as two entries.
- `src/OffDuty_Assets/BUILD.sha256` records the paks and the sources they were cooked from
  (`unreal/scripts/create_effects.py`, the tags `.ini`); it doesn't ship. CI can't cook, so
  after changing either source run `make build-plugin` and commit the new paks.
- `unreal/OffDuty/` is the Unreal plugin (gameplay effects and tags); `unreal/scripts/` holds
  `create_effects.py` (assets) and `draw_icons.py` (the tier PNGs).
- `dev/OffDutyProbe/` answers open questions about the game (see its README; install it on its
  own, on a throwaway save). `dev/QuickWin/` wins the current tactical mission with
  Ctrl+Shift+W. Neither ships; link them into `ue4ss/Mods` by hand.
- `tools/minidump.py` reads a crash dump's module and stack.
- `docs/`: [design](docs/design.md), [phase 0 findings](docs/phase0-findings.md), penalty
  theorycraft and the simtest notes.

## How it works

- **Fatigue** is a stacking gameplay effect (`GE_OffDuty_Fatigue`) on each
  operator, tagged `BitReactor.GameplayEffect.Persists` so the hub save keeps
  it like an injury.
- **Mission start** (`UBrunoGameStatics::ApplyNextMissionEffectsToCharacter`,
  once the mission is ready): the tier's effect plus the game's
  `GE_Lose_NextMission_RangedAccuracy` stacks, a saved "deployed" marker that
  records the starting tier (so in-mission save loads restore it), then the
  mission's fatigue. Required operators come from
  `UBrunoStrategyStatics::GetRequiredCharactersForCurrentMission`.
- **Strategy turn end** (`EndStrategyTurn`): everyone who didn't deploy and
  isn't away recovers.
- **AP loss** rolls at each player turn start for Exhausted and Spent.
- **UI**: the in-mission debuff fills the game's status list from Off Duty's
  `OffDuty.Status.*` tags; squad select copies the injury banner and portrait
  marker widgets.

The research behind each piece is in
[docs/phase0-findings.md](docs/phase0-findings.md).

## Testing in game

Restart the game after `make install`. Off Duty writes `off_duty.log` beside the installed mod;
`UE4SS.log` remains the startup and crash log. Test on a copy or a save the user names, never a
real campaign; sims run in ZC Sandbox's own forked campaign at speed 4.

## License

[MIT](LICENSE), copyright 2026 Chatter Chats.
