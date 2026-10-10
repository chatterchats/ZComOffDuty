"""Build the release ZIP from source, never the live mod directory.

Two components, each with its own manifests so both mod managers install them as a pair:
  OffDuty/         the UE4SS mod: exactly src/OffDuty's player files      -> ue4ss/Mods/OffDuty
  OffDuty_Assets/  src/OffDuty_Assets: OffDuty_P.pak/.ucas/.utoc            -> Content/Paks/~mods
                   (committed build of tools/build_plugin.sh; the companion
                   .pak also carries the gameplay tags file) and manifests
src/OffDutyProbe is a developer tool and never ships.
"""
from pathlib import Path
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src" / "OffDuty"
SCRIPTS = SOURCE / "Scripts"
PACKAGE_ROOT = "OffDuty"  # installed folder name
# Pak components: folder -> the built paks it ships (beside its src/<folder> manifests).
PAK_COMPONENTS = {
    "OffDuty_Assets": ("OffDuty_P.pak", "OffDuty_P.ucas", "OffDuty_P.utoc"),
}
PAK_DIR = ROOT / "src" / "OffDuty_Assets"
PAKS = [PAK_DIR / name for name in ("OffDuty_P.pak", "OffDuty_P.ucas", "OffDuty_P.utoc")]
PAK_INPUTS = ["unreal/scripts/create_effects.py", "unreal/OffDuty/Config/Tags/OffDutyTags.ini"]
version = json.loads((SOURCE / "modinfo.json").read_text())["version"]
assert re.fullmatch(r"\d+\.\d+\.\d+", version), "Invalid package version"
assert json.loads((SOURCE / "zcom-mod.json").read_text())["version"] == version
assert f'local VERSION = "{version}"' in (SCRIPTS / "main.lua").read_text()
assert f"Off Duty v{version} " in (SOURCE / "README.md").read_text()
for component in PAK_COMPONENTS:
    for manifest in ("modinfo.json", "zcom-mod.json"):
        path = ROOT / "src" / component / manifest
        assert json.loads(path.read_text())["version"] == version, f"{component}/{manifest}"


def checked_paks():
    """The committed paks: matching BUILD.sha256, which also records the sources they were built from
    (hashes, not file times: a fresh checkout has no meaningful times)."""
    recorded = {}
    for line in (PAK_DIR / "BUILD.sha256").read_text().splitlines():
        digest, name = line.split()
        recorded[name] = digest
    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    for pak in PAKS:
        assert pak.is_file(), f"{pak.name} missing: run tools/build_plugin.sh"
        assert sha(pak) == recorded.get(pak.name), f"{pak.name} doesn't match BUILD.sha256: run tools/build_plugin.sh"
    for source in PAK_INPUTS:
        assert sha(ROOT / source) == recorded.get(source), f"{source} changed since the paks were built: run tools/build_plugin.sh"
    return PAKS

COMMON = [SOURCE / leaf for leaf in ("enabled.txt", "modinfo.json", "zcom-mod.json", "README.md",
                                     "MXM/settings.lua")]
ICONS = [SOURCE / "icons" / f"T_OffDuty_Fatigue_{tier}.png" for tier in (0, 1, 2, 3)]  # draw_icons.py
REQUIRE = re.compile(r'require\("(\w+)"\)')
FILE_REFERENCE = re.compile(r'"(\w+)\.lua"')


def references(path, mod):
    """require() targets must exist; "name.lua" strings count only when they name a mod script
    (MXM.lua mentions its schema, MXM/settings.lua, that way)."""
    text = path.read_text()
    required = set(REQUIRE.findall(text))
    return required | {name for name in FILE_REFERENCE.findall(text) if name in mod}


def player_scripts():
    """Every mod script, checked to be reachable from main.lua."""
    mod = {p.stem: p for p in SCRIPTS.glob("*.lua")}
    seen, pending = set(), ["main"]
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        for ref in references(mod[name], mod):
            assert ref in mod, f"{name}.lua needs missing script {ref}.lua"
            pending.append(ref)
    assert seen == mod.keys(), f"Unreachable mod scripts: {sorted(mod.keys() - seen)}"
    return sorted(mod.values())


def build(scripts, paks):
    files = COMMON + ICONS + scripts
    assert all(p.is_file() and not p.is_symlink() for p in files)
    entries = {f"{PACKAGE_ROOT}/" + p.relative_to(SOURCE).as_posix(): p for p in files}
    entries[f"{PACKAGE_ROOT}/LICENSE"] = ROOT / "LICENSE"  # MIT: copies keep the notice
    assert entries[f"{PACKAGE_ROOT}/LICENSE"].is_file()
    assert len(entries) == len(files) + 1
    by_name = {pak.name: pak for pak in paks}
    for component, names in PAK_COMPONENTS.items():
        for path in [ROOT / "src" / component / "modinfo.json", ROOT / "src" / component / "zcom-mod.json"]:
            entries[f"{component}/{path.name}"] = path
        for name in names:
            entries[f"{component}/{name}"] = by_name[name]
    assert not any(name.endswith(".log") for name in entries)
    output = ROOT / "dist" / f"OffDuty-{version}.zip"
    output.parent.mkdir(exist_ok=True)
    if output.exists():
        # A released version is immutable: same version, same bytes, or bump it.
        with zipfile.ZipFile(output) as existing:
            same = set(existing.namelist()) == set(entries) and all(
                existing.read(name) == source.read_bytes() for name, source in entries.items())
        assert same, f"{output.name} already exists with different contents; bump the version"
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, source in entries.items():
            archive.write(source, name)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == set(entries)
        for name, source in entries.items():
            assert archive.read(name) == source.read_bytes(), name
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".zip.sha256").write_text(f"{digest}  {output.name}\n")
    print(f"Verified {len(entries)} packaged files ({len(scripts)} scripts, {len(ICONS)} icons, {len(paks)} paks): {output}")
    print(f"SHA256: {digest}")


build(player_scripts(), checked_paks())
