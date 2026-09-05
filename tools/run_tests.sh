#!/usr/bin/env bash
# Single entry point for the test suite.
#
# GUT is quietly permissive in two ways that would let a broken suite report
# success, so this wrapper closes both:
#   1. Without an --import pass it cannot resolve GutTest, prints
#      "class_names have not been imported", and exits 0.
#   2. A test file that fails to PARSE is skipped with a warning, not an
#      error, and the run still exits 0. So we also assert that the number
#      of scripts GUT actually ran matches the number of test files on disk.
set -euo pipefail
cd "$(dirname "$0")/.."

./tools/godot.sh --headless --path . --import >/dev/null

RC=0
OUT="$(./tools/godot.sh --headless --path . \
        -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1)" || RC=$?
echo "$OUT"

# Strip ANSI colour codes before parsing the summary.
PLAIN="$(printf '%s' "$OUT" | sed $'s/\033\\[[0-9;]*m//g')"

if grep -q "class_names have not been imported" <<<"$PLAIN"; then
  echo "ERROR: GUT class cache missing; import pass did not take effect." >&2
  exit 2
fi

if grep -qE "Ignoring script|Failed to load script|Parse Error" <<<"$PLAIN"; then
  echo "ERROR: a test script failed to load. GUT skips these with only a" >&2
  echo "       warning and still exits 0, so treating it as a failure." >&2
  exit 3
fi

EXPECTED="$(find tests -name 'test_*.gd' -type f | wc -l | tr -d '[:space:]')"
ACTUAL="$(grep -E '^Scripts +[0-9]+' <<<"$PLAIN" | head -1 | awk '{print $2}')"
if [[ -z "$ACTUAL" ]]; then
  echo "ERROR: could not parse a script count from the GUT summary." >&2
  exit 4
fi
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ERROR: GUT ran $ACTUAL script(s) but tests/ contains $EXPECTED test file(s)." >&2
  echo "       A test file was skipped. This would otherwise pass silently." >&2
  exit 5
fi

exit "$RC"
