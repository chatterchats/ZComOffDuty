#!/bin/sh
# Run every Lua test against the package layout: src/OffDuty linked into a
# temporary folder (as tools/package.py packages it).
# Usage: tools/run-tests.sh [test_name ...]   (default: every tests/*_test.lua)
# Exits non-zero if any test fails; prints each failure's output.
cd "$(dirname "$0")/.." || exit 1
root=$(pwd)
tree=$(mktemp -d) || exit 1
trap 'rm -rf "$tree"' EXIT
mkdir "$tree/Scripts"
for f in src/OffDuty/Scripts/*.lua; do
    name=$(basename "$f")
    ln -s "$root/$f" "$tree/Scripts/$name"
done
pass=0
fail=0
if [ $# -gt 0 ]; then
    tests=""; for n in "$@"; do tests="$tests tests/${n%_test}_test.lua"; done
else
    tests=$(ls tests/*_test.lua)
fi
for t in $tests; do
    if out=$(luajit "$t" "$tree/Scripts" 2>&1); then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL %s\n%s\n\n' "$t" "$out" | head -25
    fi
done
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
