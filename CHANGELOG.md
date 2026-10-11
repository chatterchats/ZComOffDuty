# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1]

### Changed

- The download now mirrors the game's folders (`Binaries/…/ue4ss/Mods/OffDuty` and
  `Content/Paks/~mods/OffDuty_Assets`), so Vortex installs both parts to the right places. A manual
  install is now one extract into `SWZeroCompany`. If you installed 1.1.0 or earlier by hand, delete
  the old `OffDuty_P` files directly inside `Content/Paks/~mods`.

## [1.1.0]

### Added

- Fatigue now starts after cycle 5, once the roster is big enough to rotate. Until then, missions add no
  fatigue, and squad select says when tracking starts. Change it with the new "Fatigue starts after
  cycle" setting (1–20).

### Changed

- Tuned for two squads: by default operators now recover 2 fatigue per turn off duty, so two squads
  taking turns stay rested, while each mission in a row still makes an operator one tier more tired.
- Presets now set recovery speed (Easy 3, Standard 2, Hard 1.5 per turn off duty); every preset uses the
  same tiers (Tired at 2, Exhausted at 4, Spent at 6). The separate recovery setting is gone.
- Once Crew Quarters has room for 12 or more operators, recovery halves, so it takes three squads taking
  turns to stay rested.

### Fixed

- The AP loss setting's description listed the old odds; it now says 10% (Exhausted) and 15% (Spent).

## [1.0.0]

### Added

- Operator fatigue: each mission adds fatigue to everyone who deploys, and each strategy turn off duty
  removes some. Operators away on an operation are frozen.
- Tired, Exhausted and Spent tiers with next-mission penalties to hit chance, max health, movement and a
  chance each turn to lose an AP. Anyone can still deploy.
- Story-required operators go in at the tier for half their fatigue.
- Squad select banners on every slot (RESTED, REQUIRED, TIRED, EXHAUSTED, SPENT) with detailed tooltips,
  and markers on roster portraits.
- In-mission debuffs under the health bar and in the Inspect panel.
- Settings page (Mixamoo Mod Config Manager): Easy / Standard / Hard presets, fatigue per mission, recovery
  per turn, AP loss.

