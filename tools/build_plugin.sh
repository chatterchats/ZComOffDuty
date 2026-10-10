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
#   4. rebuild the companion OffDuty_P.pak (UAT's own pak list, same compression) with one more entry:
#      Config/Tags/OffDutyTags.ini at the game's SWZeroCompany/Config/Tags/. The game only reads gameplay
#      tag files from there at startup; the cooked plugin copy lands under Mods/OffDuty/, which nothing
#      scans. IoStore containers (utoc/ucas) hold only cooked packages, so loose files belong in this pak.
#      (Earlier builds shipped that one file as a separate OffDutyTags_P.pak; Zero Mod Manager skips a
#      pak-only file sitting beside an IoStore set, so it now rides in the companion.)
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
paklist="$engine/Programs/AutomationTool/Saved/ResponseFiles/PakList_OffDutySWZeroCompany-$platform.txt"
[ "$paklist" -nt "$logs/author.log" ] || { echo "UAT's pak list $paklist is stale or missing" >&2; exit 1; }
# UAT writes the list with a UTF-8 BOM; drop it, then add the tags file at the game's path.
sed '1s/^\xEF\xBB\xBF//' "$paklist" > "$logs/companion-pak.txt"
printf '"%s" "../../../SWZeroCompany/Config/Tags/OffDutyTags.ini" -compress\n' \
    "$repo/unreal/OffDuty/Config/Tags/OffDutyTags.ini" >> "$logs/companion-pak.txt"
rm -f "$out/OffDuty_P.pak"
"$engine/Binaries/Linux/UnrealPak" "$out/OffDuty_P.pak" -create="$logs/companion-pak.txt" -platform=$platform \
    -compressionformats=Oodle -compresslevel=4 -compressmethod=Kraken > "$logs/companion-pak.log" 2>&1 \
    || { tail -5 "$logs/companion-pak.log" >&2; echo "Companion pak failed; see $logs/companion-pak.log" >&2; exit 1; }
"$engine/Binaries/Linux/UnrealPak" "$out/OffDuty_P.pak" -List > "$logs/companion-list.log" 2>&1
grep -q 'mount point "../../../SWZeroCompany/"' "$logs/companion-list.log" \
    && grep -q '"Config/Tags/OffDutyTags.ini"' "$logs/companion-list.log" \
    && grep -q '"Mods/OffDuty/AssetRegistry.bin"' "$logs/companion-list.log" \
    || { echo "Companion pak layout unexpected; see $logs/companion-list.log" >&2; exit 1; }
( cd "$out" && sha256sum OffDuty_P.* ) > "$repo/dist/plugin/SHA256SUMS"
cat "$repo/dist/plugin/SHA256SUMS"
# The release ships these paks from src/OffDuty_Assets (CI can't cook). BUILD.sha256 records the paks and
# the sources they were built from, so tools/package.py can refuse paks older than their sources.
assets="$repo/src/OffDuty_Assets"
cp "$out"/OffDuty_P.pak "$out"/OffDuty_P.ucas "$out"/OffDuty_P.utoc "$assets/"
( cd "$assets" && sha256sum OffDuty_P.pak OffDuty_P.ucas OffDuty_P.utoc
  cd "$repo" && sha256sum unreal/scripts/create_effects.py unreal/OffDuty/Config/Tags/OffDutyTags.ini ) > "$assets/BUILD.sha256"

if $install; then
    game=${SWZC_GAME:-$(cat "$kit/GameInstallDirectory.txt")}
    target="$game/SWZeroCompany/Content/Paks/~mods"
    # OffDutyTags_P.pak is from older builds (its file now rides in OffDuty_P.pak): remove it.
    mkdir -p "$target" && rm -f "$target"/OffDuty_P.* "$target"/OffDutyTags_P.pak \
        && cp "$out"/OffDuty_P.* "$target/"
    echo "Installed: $target/OffDuty_P.{pak,ucas,utoc}"
    "$repo/tools/sync_instances.sh" # the simtest game copies, if any
fi
