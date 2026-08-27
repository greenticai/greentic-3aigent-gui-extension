#!/usr/bin/env bash
# Stamp the embedded runtime .gtpack sha256 into a v2 describe.json, in place.
# Usage: ci/stamp-gtpack-sha.sh <describe.json> <sha256>
set -euo pipefail

DESCRIBE="${1:?usage: $0 <describe.json> <sha256>}"
SHA="${2:?usage: $0 <describe.json> <sha256>}"
[ -f "$DESCRIBE" ] || { echo "not a file: $DESCRIBE"; exit 1; }

# jq creates missing paths, so writing the v1 location (.runtime.gtpack) into a
# v2 document silently injects a field gtdx then rejects the whole file over.
tmp=$(mktemp)
jq --arg sha "$SHA" '
  ((.runtime.components // {}) | with_entries(select(.value.gtpack)) | length) as $n
  | if $n == 0 then
      error("describe.json: no runtime.components.*.gtpack to stamp")
    else . end
  | .runtime.components |= with_entries(
      if .value.gtpack then .value.gtpack.sha256 = $sha else . end
    )
' "$DESCRIBE" > "$tmp"
mv "$tmp" "$DESCRIBE"
