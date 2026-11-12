"""Refuse to package paks that don't match the build record (src/OffDuty_Assets/BUILD.sha256).

tools/build_plugin.sh writes the record: the committed paks and the sources they were built from
(hashes, not file times: a fresh checkout has no meaningful times). CI can't cook, so the release
ships the committed paks; this keeps them from going stale against their sources.
"""
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "src" / "OffDuty_Assets"
PAKS = ("OffDuty_P.pak", "OffDuty_P.ucas", "OffDuty_P.utoc")
INPUTS = ("unreal/scripts/create_effects.py", "unreal/OffDuty/Config/Tags/OffDutyTags.ini")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    recorded = dict(reversed(line.split()) for line in (ASSETS / "BUILD.sha256").read_text().splitlines())
    problems = []
    for name in PAKS:
        if not (ASSETS / name).is_file():
            problems.append(f"{name} missing")
        elif sha(ASSETS / name) != recorded.get(name):
            problems.append(f"{name} doesn't match BUILD.sha256")
    problems += [f"{name} changed since the paks were built" for name in INPUTS
                 if sha(ROOT / name) != recorded.get(name)]
    if problems:
        print("error: " + "; ".join(problems) + ": run `make build-plugin`", file=sys.stderr)
        return 1
    print("paks match their build record")
    return 0


if __name__ == "__main__":
    sys.exit(main())
