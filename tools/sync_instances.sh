#!/usr/bin/env bash
# Copy Off Duty's current scripts and paks into the simtest game copies ("<games>/Instance N").
# The main install symlinks src/OffDuty, so only the copies need this. Run with the copies closed.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
games=${SWZC_GAMES:-"/run/media/chats/e0057d4a-fe46-43eb-a837-db51979c500f/Games/STAR WARS Zero Company (2026)"}
for dir in "$games"/Instance\ *; do
    [ -d "$dir" ] || continue
    root="$dir/Star Wars Zero Company/SWZeroCompany"
    # Each copy keeps its own settings (values.lua), simtest backup and log.
    rsync -a --delete --exclude 'MXM/values.lua*' --exclude 'off_duty.log' "$repo/src/OffDuty/" "$root/Binaries/Win64/ue4ss/Mods/OffDuty/"
    if [ -f "$repo/dist/plugin/SWZeroCompany/Content/Paks/~mods/OffDuty_P.pak" ]; then
        rm -f "$root/Content/Paks/~mods/OffDutyTags_P.pak" # older builds; now inside OffDuty_P.pak
        cp "$repo"/dist/plugin/SWZeroCompany/Content/Paks/~mods/OffDuty_P.* "$root/Content/Paks/~mods/"
    fi
    echo "synced: ${dir##*/}"
done
