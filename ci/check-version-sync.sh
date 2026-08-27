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

[ "$fail" -eq 0 ] || exit 1
echo "OK: $di at $dv (describe.json, Cargo.toml and src/lib.rs agree)"
