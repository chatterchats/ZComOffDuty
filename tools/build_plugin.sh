#!/bin/sh
# Build Off Duty's Unreal plugin (GE_OffDuty_Fatigue) with the SWZC Merged Kit.
#
#   tools/build_plugin.sh            author, cook, package and assemble dist/plugin/
#   tools/build_plugin.sh --install  also copy it into the game's SWZeroCompany/Mods/
#
# Steps:
#   1. unreal/scripts/create_effects.py creates/updates the assets (headless editor)
#   2. DLC cook against the BaseGame release, then IoStore packaging (UAT BuildCookRun)
#   3. assemble a ~mods pak mod (a Modkit "override" mod: content remapped onto /Game):
#        SWZeroCompany/Content/Paks/~mods/OffDuty_P.{pak,ucas,utoc}
#      and check the remap ran (in game the effect is /Game/OffDuty/Effects/GE_OffDuty_Fatigue)
#   4. OffDutyTags_P.pak: Config/Tags/OffDutyTags.ini mounted at the project's Config/Tags, in case the
#      game only reads gameplay tag files from there (the cooked plugin config lands under Mods/OffDuty/)
#
# The Linux editor has no Windows target platform, so this cooks for Linux. GE_OffDuty_Fatigue
# has no shaders, textures or other platform-specific data; whether a Linux cook loads in the
# Windows game is being verified in game (docs/phase0-findings.md).
#
# Environment: SWZC_ROOT (default /run/media/chats/0c7bd812-03b4-405c-9602-31282b68fd64),
#              SWZC_KIT (default "$SWZC_ROOT/SWZC Merged Kit"), SWZC_GAME (game install root).
set -eu
cd "$(dirname "$0")/.."
repo=$(pwd)
root=${SWZC_ROOT:-/run/media/chats/0c7bd812-03b4-405c-9602-31282b68fd64}
kit=${SWZC_KIT:-"$root/SWZC Merged Kit"}
engine="$root/UnrealEngine/Engine"
project="$kit/SWZeroCompany.uproject"
platform=Linux
logs="$repo/dist/plugin-logs"
out="$repo/dist/plugin/SWZeroCompany/Content/Paks/~mods"
install=false
[ "${1:-}" = "--install" ] && install=true

mkdir -p "$logs"
[ -f "$project" ] || { echo "SWZC Merged Kit not found: $project" >&2; exit 1; }
if [ ! -e "$kit/Mods/OffDuty" ]; then
    ln -s "$repo/unreal/OffDuty" "$kit/Mods/OffDuty"
fi
# The DLC cook reads the base release for the cook platform; the shipped registry is a package list.
mkdir -p "$kit/Releases/BaseGame/$platform"
cp "$kit/Releases/BaseGame/Windows/AssetRegistry.bin" "$kit/Releases/BaseGame/$platform/"
# The editor doesn't scan an explicitly loaded plugin's Config/Tags; register Off Duty's tags in the
# kit's (a merge.py rerun may prune it; this puts it back every build).
cp "$repo/unreal/OffDuty/Config/Tags/OffDutyTags.ini" "$kit/Config/Tags/OffDutyTags.ini"

echo "1/3 Authoring assets"
"$engine/Binaries/Linux/UnrealEditor-Cmd" "$project" -run=pythonscript \
    -script="$repo/unreal/scripts/create_effects.py" \
    -unattended -nop4 -nosplash -NullRHI -stdout -FullStdOutLogOutput -NoCrashDialog \
    > "$logs/author.log" 2>&1 || true
grep -q "OFFDUTY_RESULT ok" "$logs/author.log" || { grep OFFDUTY "$logs/author.log" >&2; echo "Authoring failed; see $logs/author.log" >&2; exit 1; }

echo "2/3 Cooking and packaging ($platform)"
rm -rf "$kit/Packaged/$platform/SWZeroCompany/Mods/OffDuty"
# NuGetAudit=false: new advisories for UAT's bundled Magick.NET otherwise fail the script build.
NuGetAudit=false "$engine/Build/BatchFiles/RunUAT.sh" -ScriptsForProject="$project" BuildCookRun \
    -project="$project" -nop4 -utf8output -unattended -nocompileeditor -skipbuildeditor \
    -platform=$platform -clientconfig=Shipping -cook -stage -pak -iostore \
    -dlcname=OffDuty -DLCPakPluginFile -basedonreleaseversion=BaseGame \
    -AdditionalCookerOptions="-AllowUncookedAssetReferences" \
    -archive -archivedirectory="$kit/Packaged" > "$logs/cook.log" 2>&1 \
    || { tail -20 "$logs/cook.log" >&2; echo "Cook failed; see $logs/cook.log" >&2; exit 1; }

echo "3/3 Assembling $out"
paks="$kit/Packaged/$platform/SWZeroCompany/Mods/OffDuty/Content/Paks/$platform"
rm -rf "$repo/dist/plugin" && mkdir -p "$out"
for ext in pak ucas utoc; do
    cp "$paks/OffDutySWZeroCompany-$platform.$ext" "$out/OffDuty_P.$ext"
done
# The remap renames packages (/OffDuty/<rest> -> /Game/<rest>) through the container header's
# PackageRedirects; file paths in the directory index stay under the plugin.
grep -q "Remapping plugin content to game: 'True'" "$logs/cook.log" \
    || { echo "IoStore did not remap the plugin onto /Game; check unreal/OffDuty/Config/DefaultOffDuty.ini" >&2; exit 1; }
"$engine/Binaries/Linux/UnrealPak" "$out/OffDuty_P.utoc" -List > "$logs/list.log" 2>&1
grep -q '/OffDuty/Effects/GE_OffDuty_Fatigue.uasset"' "$logs/list.log" \
    || { echo "GE_OffDuty_Fatigue missing from the container; see $logs/list.log" >&2; exit 1; }
for tier in 1 2 3; do
    grep -q "/OffDuty/Icons/T_OffDuty_Fatigue_$tier.uasset\"" "$logs/list.log" \
        || { echo "T_OffDuty_Fatigue_$tier missing from the container; see $logs/list.log" >&2; exit 1; }
done
printf '"%s" "../../../SWZeroCompany/Config/Tags/OffDutyTags.ini"\n' \
    "$repo/unreal/OffDuty/Config/Tags/OffDutyTags.ini" > "$logs/tags-pak.txt"
"$engine/Binaries/Linux/UnrealPak" "$out/OffDutyTags_P.pak" -create="$logs/tags-pak.txt" > "$logs/tags-pak.log" 2>&1 \
    || { tail -5 "$logs/tags-pak.log" >&2; echo "Tags pak failed; see $logs/tags-pak.log" >&2; exit 1; }
( cd "$out" && sha256sum OffDuty_P.* OffDutyTags_P.pak ) > "$repo/dist/plugin/SHA256SUMS"
cat "$repo/dist/plugin/SHA256SUMS"

if $install; then
    game=${SWZC_GAME:-$(cat "$kit/GameInstallDirectory.txt")}
    target="$game/SWZeroCompany/Content/Paks/~mods"
    mkdir -p "$target" && rm -f "$target"/OffDuty_P.* "$target"/OffDutyTags_P.pak \
        && cp "$out"/OffDuty_P.* "$out"/OffDutyTags_P.pak "$target/"
    echo "Installed: $target/OffDuty_P.{pak,ucas,utoc} and OffDutyTags_P.pak"
fi
