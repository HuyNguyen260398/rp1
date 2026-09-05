#!/usr/bin/env bash
# Resolves the Godot 4.7.2 binary across dev machines and CI.
# Override with GODOT_BIN=/path/to/godot
set -euo pipefail

if [[ -n "${GODOT_BIN:-}" ]]; then
  GODOT="$GODOT_BIN"
elif [[ -x "$HOME/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
  GODOT="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
else
  echo "ERROR: Godot not found. Set GODOT_BIN or install to ~/Applications/Godot.app" >&2
  exit 127
fi

# Guard against the Mono build, which hangs headless without a .NET runtime.
if "$GODOT" --version 2>/dev/null | grep -q "mono"; then
  echo "ERROR: $GODOT is a Mono build. This project needs the standard build." >&2
  exit 126
fi

exec "$GODOT" "$@"
