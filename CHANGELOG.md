# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1]

### Added

- Fatigue now starts at cycle 5, once the roster is big enough to rotate. Before that, missions add no
  fatigue, and squad select says when tracking starts. Change it with the new "Fatigue starts at cycle"
  setting (1–20).

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

