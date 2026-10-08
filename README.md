# Off Duty

[![Nexus Mods](https://img.shields.io/badge/Nexus%20Mods-Off%20Duty-d98f40)](https://www.nexusmods.com/starwarszerocompany/mods/315)
[![UE4SS](https://img.shields.io/badge/framework-UE4SS-6f42c1)](https://github.com/UE4SS-RE/RE-UE4SS)
[![License: MIT](https://img.shields.io/badge/license-MIT-2f7d4f)](LICENSE)

Off Duty is a UE4SS mod for **Star Wars: Zero Company** that adds **operator
fatigue and recovery**: operators tire from back-to-back deployments and
recover while they sit missions out, so the whole company matters, not just
your best four.

> **Status: in development, not released.** The current build only starts its
> runtime and logs; it makes no gameplay changes. The design is in
> [docs/design.md](docs/design.md) and the research behind it in
> [docs/phase0-findings.md](docs/phase0-findings.md).

## Planned features

- **Fatigue from deployment, not damage.** Each deployment adds fatigue; long
  missions and going down add more. A flawless squad still gets tired.
- **Recovery by resting.** Each strategy cycle an operator sits out removes
  fatigue.
- **Push-through, never locked out.** Tired means a small penalty next
  mission. Exhausted means a larger one, plus extra recovery after deploying
  anyway. No operator is ever blocked from deploying, so a save can't get
  stuck.
- **Story-safe.** Operators a mission requires can always deploy.
- **Clear at squad select.** The exact penalty, and what pushing will cost,
  are shown before you commit.
- **Separate from injuries.** The game's injury system is left alone.

| Fatigue | State | Next mission |
| --- | --- | --- |
| 0 | Ready | No penalty |
| 1 | Tired | Small accuracy penalty |
| 2+ | Exhausted | Larger penalty; deploying adds extra recovery |

Numbers are playtest placeholders.

## Requirements

- **Star Wars: Zero Company** (Steam)
- **UE4SS** for Zero Company: the recommended build (v3.0.1 Beta,
  `a1e7f571`)

No game builds have been tested yet.

## Installation

Download the release ZIP from
[Nexus Mods](https://www.nexusmods.com/starwarszerocompany/mods/315), not
GitHub's source-code archive. The ZIP keeps `OffDuty` as its top-level folder
and includes metadata for both mod managers below.

### With a mod manager

- **[Zero Mod Manager](https://github.com/stellamarislabs/zero-mod-manager)**
  (formerly ZCOM Mod Manager): open **Install**, drop in the ZIP, then
  confirm Off Duty is enabled under **Mods**.
- **[Zero Company Mod Command](https://github.com/EnvianMods/ZeroCompanyModCommand)**:
  drag the ZIP into the **Hangar Bay** and check that it's enabled.

### By hand

1. Install UE4SS for Star Wars: Zero Company.
2. Extract the `OffDuty` folder into
   `SWZeroCompany/Binaries/Win64/ue4ss/Mods/`.
3. Check that `ue4ss/Mods/OffDuty/Scripts/main.lua` exists.
4. If your UE4SS setup ignores the packaged `enabled.txt`, add
   `OffDuty : 1` to `ue4ss/Mods/mods.txt`.

### Updating and uninstalling

Close the game, then install the new ZIP the same way. Restart the game after
installing or updating; don't use UE4SS's Reload All Mods.

To uninstall, disable or remove it in your mod manager, or delete the
`OffDuty` folder.

## Compatibility

Designed to sit alongside campaign-length and roster mods. Specific
compatibility notes will be added as they're tested.

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

Planned; see [docs/design.md](docs/design.md). In short: fatigue is stored on
each operator as a stacking gameplay effect, which the game saves with the
rest of the operator's effects (the same way it saves injuries). The
in-mission penalty uses the game's own next-mission effect pipeline
(`UBrunoGameStatics::AddNextMissionCharacterEffect`), which the briefing
already lists. Story requirements come from
`ABrunoMissionCentral::GetRequiredMissionCharacter`.

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
│   ├── OffDuty/                          # the distributable mod folder
│   │   ├── Scripts/                      # main.lua and modules
│   │   ├── README.md                     # player guide
│   │   ├── enabled.txt
│   │   ├── modinfo.json                  # Zero Company Mod Command
│   │   └── zcom-mod.json                 # Zero Mod Manager
│   └── OffDutyProbe/                     # developer probe; never packaged
├── unreal/
│   ├── OffDuty/                          # Unreal plugin: GE_OffDuty_Fatigue (fatigue storage)
│   └── scripts/create_fatigue_effect.py  # authors the plugin's assets (editor Python)
├── tests/                                # LuaJIT tests with UE4SS fakes
└── tools/
    ├── build_plugin.sh                   # cook + package the Unreal plugin (SWZC Merged Kit)
    ├── bump_version.py                   # version bump + changelog promotion
    ├── nexus_changelog.py                # a release's notes as Nexus text
    ├── package.py                        # release ZIP (adds LICENSE)
    └── run-tests.sh
```

`src/OffDuty` is the distributable folder; `tools/package.py` zips it with the
LICENSE and checks every script is reachable from `main.lua`.

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

1. Add player-facing notes under `## [Unreleased]` in
   [`CHANGELOG.md`](CHANGELOG.md), grouped as Added / Changed / Fixed /
   Removed.
2. Bump the version with `patch`, `minor` or `major`:

   ```bash
   python3 tools/bump_version.py minor
   ```

   It updates `modinfo.json`, `zcom-mod.json`, `Scripts/main.lua` and the
   player README title, and turns `[Unreleased]` into the new version.
3. Run `tools/run-tests.sh` and `python3 tools/package.py`, then check
   `dist/OffDuty-#.#.#.zip` with a mod manager and a clean manual install.
   A built version is immutable: the packager refuses to overwrite a ZIP with
   different contents.
4. Commit (`chore(release): v#.#.#`), merge to `main` and push.
5. Run **Release to Nexus Mods** from the **Actions** tab. It needs the
   `NEXUSMODS_API_KEY` repository secret.

The workflow:

- requires `modinfo.json`, `zcom-mod.json`, `main.lua` and the player README
  title to hold the same `#.#.#` version;
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
