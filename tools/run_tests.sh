#!/usr/bin/env bash
# Single entry point for the test suite.
set -euo pipefail
cd "$(dirname "$0")/.."

# Import pass populates .godot/global_script_class_cache.cfg.
# GUT cannot resolve GutTest without it, and fails with exit code 0.
./tools/godot.sh --headless --path . --import >/dev/null

OUT="$(./tools/godot.sh --headless --path . \
        -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1)" || RC=$?
RC="${RC:-0}"
echo "$OUT"

if grep -q "class_names have not been imported" <<<"$OUT"; then
  echo "ERROR: GUT class cache missing; import pass did not take effect." >&2
  exit 2
fi

exit "$RC"
