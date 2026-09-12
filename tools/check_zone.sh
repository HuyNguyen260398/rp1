#!/usr/bin/env bash
# The zone gate. Bash cannot read PNGs, so the work is in tools/check_zone.gd.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d data/zone ]] || { echo "No data/zone/ yet; nothing to check."; exit 0; }

exec ./tools/godot.sh --headless --path . -s tools/check_zone.gd
