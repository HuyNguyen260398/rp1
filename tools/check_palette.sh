#!/usr/bin/env bash
# The palette gate. docs/palette.md section 1 names this file; the pixel walk
# is in tools/check_palette.gd because bash cannot read PNGs.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d assets ]] || { echo "No assets/ directory yet; nothing to check."; exit 0; }

exec ./tools/godot.sh --headless --path . -s tools/check_palette.gd
