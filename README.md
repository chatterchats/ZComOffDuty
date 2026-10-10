# Off Duty

[![Nexus Mods](https://img.shields.io/badge/Nexus%20Mods-Off%20Duty-d98f40)](https://www.nexusmods.com/starwarszerocompany/mods/315)
[![UE4SS](https://img.shields.io/badge/framework-UE4SS-6f42c1)](https://github.com/UE4SS-RE/RE-UE4SS)
[![License: MIT](https://img.shields.io/badge/license-MIT-2f7d4f)](LICENSE)

Off Duty is a UE4SS mod for **Star Wars: Zero Company** that adds **operator
fatigue and recovery**: operators tire from back-to-back deployments and
recover while they sit missions out, so the whole company matters, not just
your best four.

## Features

- **Fatigue from deployment.** Every operator who deploys gains fatigue (2 by
  default); every strategy turn off duty removes some (1 by default).
  Operators away on an operation are frozen.
- **Push-through, never locked out.** Fatigue sets a tier with a penalty for
  the next mission, but anyone can always deploy, so a save can't get stuck.
- **Story-safe.** Operators a mission requires go in at the tier for half
  their fatigue (rounded down); their fatigue itself is unchanged.
- **Clear at squad select.** Every squad slot shows a banner (RESTED,
  REQUIRED, TIRED, EXHAUSTED or SPENT) with a tooltip giving the fatigue,
  the exact penalties and the turns until fully rested. Roster portraits mark
  tired and required operators.
- **Visible in the mission.** The tier is a debuff under the health bar and in
  the Inspect panel; the hit chance penalty is the game's own "Penalty from
  Operation".
- **Separate from injuries.** The game's injury system is left alone.
- **Settings** through the Mixamoo Mod Config Manager: preset, fatigue per
  mission, recovery per turn, AP loss on/off.

| Tier      | Hard | Standard | Next mission                                                                 |
| --------- | ---- | -------- | ---------------------------------------------------------------------------- |
| Rested    | 0    | 0–1      | No penalty                                                                   |
| Tired     | 1–2  | 2–3      | −5% hit chance, −5% max health                                               |
| Exhausted | 3–4  | 4–5      | −10% hit chance, −10% max health, 10% chance per turn to lose 1 AP           |
| Spent     | 5–7  | 6        | −20% hit chance, −20% max health, −10% movement, 15% chance per turn to lose 1 AP |

Fatigue caps at 7 (Hard) or 6 (Standard). The numbers come from AI-vs-AI
simulations; see [docs/design.md](docs/design.md).

## Requirements

- **Star Wars: Zero Company**; tested on the Steam build
- **UE4SS** for Zero Company: the recommended build (v3.0.1 Beta, `a1e7f571`)
- Optional: **Mixamoo Mod Config Manager** for the in-game settings page

## Installation

Download the release ZIP from
[Nexus Mods](https://www.nexusmods.com/starwarszerocompany/mods/315), not
GitHub's source-code archive. It holds two components, and both are needed:

| Folder           | Contents                                   | Installs to                            |
| ---------------- | ------------------------------------------ | -------------------------------------- |
| `OffDuty`        | the UE4SS Lua mod                          | `SWZeroCompany/Binaries/Win64/ue4ss/Mods/` |
| `OffDuty_Assets` | `OffDuty_P.pak/.ucas/.utoc` (effects, tags) | `SWZeroCompany/Content/Paks/~mods/`     |

Each carries `modinfo.json` and `zcom-mod.json`, so both managers below
recognise them as a pair.

### With a mod manager

- **[Zero Mod Manager](https://github.com/stellamarislabs/zero-mod-manager)**:
  drop the ZIP on **Install**, choose **Install all components**, then check
  both are enabled under **Mods**.
- **[Zero Company Mod Command](https://github.com/EnvianMods/ZeroCompanyModCommand)**:
  drag the ZIP into the **Hangar Bay**; it adds Off Duty and Off Duty — Assets
  as two entries. Check both are enabled.

### By hand

1. Install UE4SS for Star Wars: Zero Company and close the game.
2. Extract the `OffDuty` folder into `SWZeroCompany/Binaries/Win64/ue4ss/Mods/`.
3. Copy the three files in `OffDuty_Assets` into
   `SWZeroCompany/Content/Paks/~mods/` (create `~mods` if needed).
4. If your UE4SS setup ignores the packaged `enabled.txt`, add
   `OffDuty : 1` to `ue4ss/Mods/mods.txt`.

### Updating and uninstalling

Close the game, then install the new ZIP the same way. Restart the game after
installing or updating; don't use UE4SS's Reload All Mods.

To uninstall, disable or remove both components in your mod manager, or
delete the `OffDuty` folder and the three `OffDuty_P` files. Saves stay
loadable; operators simply stop tiring.

## Compatibility

- Leaves the game's own systems in charge: fatigue is a saved gameplay effect
  on each operator, and penalties use the game's next-mission effects.
- Guest units who aren't on the roster (such as Rex) don't gain fatigue.
- Tell us about conflicts in the [issues](https://github.com/chatterchats/ZComOffDuty/issues).

## Troubleshooting

Off Duty writes `off_duty.log` beside the installed mod. `UE4SS.log` remains
the startup and crash log.

### Reporting a bug

Open an [issue](https://github.com/chatterchats/ZComOffDuty/issues) with:

- the game build and UE4SS version;
- other installed mods;
- what you were doing and the steps to reproduce it; and
- `off_duty.log` and `UE4SS.log`.

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

## Repository layout

```text
.
├── .github/workflows/release-nexus.yml   # manual Nexus release
├── CHANGELOG.md                          # player-facing notes per release
├── LICENSE
├── README.md
├── Zero_Company_UE4SS_Lua_Guide.md       # general UE4SS lessons
├── docs/
│   ├── design.md                         # decisions and working model
│   ├── phase0-findings.md                # game systems the design relies on
│   └── nexus/                            # mod page summary and BBCode description
├── src/
│   ├── OffDuty/                          # the UE4SS mod component
│   │   ├── Scripts/                      # main.lua and modules
│   │   ├── icons/                        # Zzz tier icons and the RESTED sun (PNG)
│   │   ├── MXM/settings.lua              # settings page schema
│   │   ├── README.md                     # player guide
│   │   ├── enabled.txt
│   │   ├── modinfo.json                  # Zero Company Mod Command
│   │   └── zcom-mod.json                 # Zero Mod Manager
│   ├── OffDuty_Assets/                   # the pak component: committed build + manifests
│   └── OffDutyProbe/                     # developer probe; never packaged
├── unreal/
│   ├── OffDuty/                          # Unreal plugin: Off Duty's gameplay effects and tags
│   └── scripts/                          # create_effects.py (assets), draw_icons.py (PNGs)
├── tests/                                # LuaJIT tests with UE4SS fakes
└── tools/
    ├── build_plugin.sh                   # cook + package the paks into src/OffDuty_Assets (SWZC Merged Kit)
    ├── bump_version.py                   # version bump + changelog promotion
    ├── nexus_changelog.py                # a release's notes as Nexus text
    ├── package.py                        # release ZIP (adds LICENSE)
    ├── run-tests.sh
    ├── simtest.py                        # AI-vs-AI balance sims (docs/simtest-handoff.txt)
    └── sync_instances.sh                 # update the simtest game copies
```

`tools/package.py` zips `src/OffDuty` (with the LICENSE, checking every script
is reachable from `main.lua`) and `src/OffDuty_Assets` (checking the committed
paks against `BUILD.sha256` and the sources they were built from).

## Development

1. Clone the repository and copy `src/OffDuty` into the game's `ue4ss/Mods`
   folder.
2. Run the tests (needs `luajit`):

   ```bash
   tools/run-tests.sh            # every test
   tools/run-tests.sh bootstrap  # selected tests
   ```

3. Restart the game and test in game; the tests only fake UE4SS and the
   game's objects.

`src/OffDutyProbe` is a separate diagnostic mod for answering open questions
about the game (see its README). Install it on its own, on a throwaway save.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)
(`feat(fatigue): …`, `fix(squad-select): …`, `chore(release): v1.0.0`).

## Releasing

The manually run **Release to Nexus Mods** workflow publishes a release; use
`tools/package.py` for a local, package-only build.

1. If `unreal/scripts/create_effects.py` or the tags changed, rebuild the paks
   with `tools/build_plugin.sh` (needs the SWZC Merged Kit) and commit
   `src/OffDuty_Assets`.
2. Add player-facing notes under `## [Unreleased]` in
   [`CHANGELOG.md`](CHANGELOG.md), grouped as Added / Changed / Fixed /
   Removed.
3. Bump the version with `patch`, `minor` or `major`:

   ```bash
   python3 tools/bump_version.py minor
   ```

   It updates both components' `modinfo.json` and `zcom-mod.json`, the MXM
   settings, `Scripts/main.lua` and the player README title, and turns
   `[Unreleased]` into the new version.

4. Run `tools/run-tests.sh` and `python3 tools/package.py`, then check
   `dist/OffDuty-#.#.#.zip` with a mod manager and a clean manual install.
   A built version is immutable: the packager refuses to overwrite a ZIP with
   different contents.
5. Commit (`chore(release): v#.#.#`), merge to `main` and push.
6. Run **Release to Nexus Mods** from the **Actions** tab. It needs the
   `NEXUSMODS_API_KEY` repository secret.

The workflow:

- requires both components' `modinfo.json` and `zcom-mod.json`, `main.lua` and
  the player README title to hold the same `#.#.#` version;
- reads that version's notes from `CHANGELOG.md`;
- runs the tests and builds the ZIP with `tools/package.py`; and
- uploads it to Nexus as `OffDuty v#.#.#.zip`, finding the mod and its single
  active file through the API (exactly one active file is required, so the
  first file must be uploaded by hand).

## Contributing

Bug reports, compatibility findings and focused pull requests are welcome
through [Issues](https://github.com/chatterchats/ZComOffDuty/issues) and
[Pull Requests](https://github.com/chatterchats/ZComOffDuty/pulls). Keep the
game's own systems as the source of truth, and refuse unrecognized state
rather than guessing.

## Support

- Downloads: [Nexus Mods](https://www.nexusmods.com/starwarszerocompany/mods/315)
- Changes: [`CHANGELOG.md`](CHANGELOG.md)
- Bugs and requests: [GitHub Issues](https://github.com/chatterchats/ZComOffDuty/issues)

## License

[MIT](LICENSE) © 2026 Chatter Chats. The release ZIP includes the license.
