#!/usr/bin/env bash
# Every folder under assets/ must declare its licence. Reconstructing this
# before a Steam launch with 60 packs and no records is a miserable week.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d assets ]] || { echo "No assets/ directory yet; nothing to check."; exit 0; }

missing=0
while IFS= read -r dir; do
  [[ "$dir" == "assets" ]] && continue
  if [[ ! -f "$dir/LICENSE.txt" ]]; then
    echo "MISSING LICENCE: $dir/LICENSE.txt" >&2
    missing=1
  fi
done < <(find assets -mindepth 1 -maxdepth 1 -type d)

if [[ $missing -eq 1 ]]; then
  echo "Every folder under assets/ needs a LICENSE.txt naming source, author, licence." >&2
  exit 1
fi
echo "Asset licences: OK"
