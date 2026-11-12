"""Every shipped script is reachable from main.lua, and every script it requires exists.

require() targets must exist; "name.lua" strings count only when they name a mod script (MXM.lua
mentions its schema, MXM/settings.lua, that way). Run from the repo root:
make test T=scripts_reachable_test
"""
import re
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "src" / "OffDuty" / "Scripts"
REQUIRE = re.compile(r'require\("(\w+)"\)')
FILE_REFERENCE = re.compile(r'"(\w+)\.lua"')


class ScriptsReachable(unittest.TestCase):
    def test_every_script_is_reachable_from_main(self):
        mod = {path.stem: path for path in SCRIPTS.glob("*.lua")}
        seen, pending = set(), ["main"]
        while pending:
            name = pending.pop()
            if name in seen:
                continue
            seen.add(name)
            text = mod[name].read_text()
            refs = set(REQUIRE.findall(text)) | {n for n in FILE_REFERENCE.findall(text) if n in mod}
            for ref in refs:
                self.assertIn(ref, mod, f"{name}.lua needs missing script {ref}.lua")
                pending.append(ref)
        self.assertEqual(sorted(mod.keys() - seen), [], "unreachable scripts")


if __name__ == "__main__":
    unittest.main()
