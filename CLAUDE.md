# ZComOffDuty

@docs/agent-rules.md

Read README.md first: what the mod does, its layout and how it's tested.

## Rules for this repo

- Fatigue lives in the game's own saved gameplay effects; never keep a separate save or store.
- Penalties go through the game's next-mission effects; don't reimplement accuracy or AP rules.
- After changing `unreal/scripts/create_effects.py` or the tags `.ini`, run `make build-plugin`
  and commit the new paks; `make package` refuses stale ones.
- Every new script must be required from `main.lua` (directly or through a module), or the
  reachability test fails.
- Sims: use speed 4 (higher speeds leave units at 0 health or idle) and the user's real settings
  (Standard, AP loss on); only ever on game copies or ZC Sandbox's forked campaign.
- Guests not on the roster (Rex) never gain fatigue.
