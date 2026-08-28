#!/usr/bin/env bash
# describe.json metadata.version is the version gtdx publishes; Cargo.toml drives
# the .gtxpack filename and the release tag. They are separate strings, and a
# release that bumped only Cargo.toml once published the old version and silently
# overwrote it. Keep them equal.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$ROOT/provider-3aigent-gui"

dv=$(jq -r '.metadata.version // empty' "$EXT/describe.json")
cv=$(awk -F\" '/^version = /{print $2; exit}' "$EXT/Cargo.toml")
lv=$(grep -oP 'version: "\K[^"]+' "$EXT/src/lib.rs" | head -1)

[ -n "$dv" ] || { echo "FAIL: describe.json has no metadata.version"; exit 1; }
[ -n "$lv" ] || { echo "FAIL: src/lib.rs get_identity() has no version"; exit 1; }

fail=0
[ "$dv" = "$cv" ] || { echo "FAIL: describe.json=$dv but Cargo.toml=$cv"; fail=1; }
[ "$dv" = "$lv" ] || { echo "FAIL: describe.json=$dv but src/lib.rs=$lv"; fail=1; }

di=$(jq -r '.metadata.id' "$EXT/describe.json")
li=$(grep -oP 'id: "\K[^"]+' "$EXT/src/lib.rs" | head -1)
[ "$di" = "$li" ] || { echo "FAIL: describe.json id=$di but src/lib.rs id=$li"; fail=1; }

# The runtime pin is what makes the published extension carry a real pack.
# A release that loses it would silently fall back to whatever the packaging
# step finds — which is how the placeholder shipped for as long as it did.
PIN="$EXT/runtime-pack.json"
if [ ! -f "$PIN" ]; then
  echo "FAIL: missing runtime pin $PIN"; fail=1
else
  pr=$(jq -r '.ref // empty' "$PIN")
  pv=$(jq -r '.version // empty' "$PIN")
  case "$pr" in
    *@sha256:*) ;;
    *) echo "FAIL: runtime-pack.json ref must pin a digest, got: ${pr:-<empty>}"; fail=1 ;;
  esac
  [ -n "$pv" ] || { echo "FAIL: runtime-pack.json has no version"; fail=1; }
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK: $di at $dv (describe.json, Cargo.toml and src/lib.rs agree)"
