#!/usr/bin/env bash
# Fetch the runtime .gtpack this extension ships, as pinned in
# provider-3aigent-gui/runtime-pack.json, and place it at the path the
# packaging step embeds.
#
# Why this exists: the release workflow used to stage a literal placeholder
# string as runtime/provider.gtpack and stamp its digest, so every published
# extension carried a runtime that was not a gtpack at all. A placeholder must
# never be reachable from a release path — it is opt-in only, and only for
# local builds that explicitly ask.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
EXT="$ROOT/provider-3aigent-gui"
PIN="$EXT/runtime-pack.json"
OUT="${1:-$EXT/runtime/provider.gtpack}"

[ -f "$PIN" ] || { echo "ERROR: missing runtime pin $PIN" >&2; exit 1; }

REF="$(jq -r '.ref // empty' "$PIN")"
VERSION="$(jq -r '.version // empty' "$PIN")"
[ -n "$REF" ] || { echo "ERROR: runtime-pack.json has no .ref" >&2; exit 1; }
[ -n "$VERSION" ] || { echo "ERROR: runtime-pack.json has no .version" >&2; exit 1; }
case "$REF" in
  *@sha256:*) ;;
  *) echo "ERROR: runtime pin must be by digest, got: $REF" >&2; exit 1 ;;
esac

command -v oras >/dev/null 2>&1 || { echo "ERROR: oras is required to fetch $REF" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> pulling runtime gtpack $VERSION from $REF"
oras pull "$REF" -o "$TMP" >/dev/null

PACK="$(find "$TMP" -name '*.gtpack' -print -quit)"
[ -n "$PACK" ] || { echo "ERROR: no .gtpack in $REF" >&2; exit 1; }
cp "$PACK" "$OUT"

echo "==> runtime gtpack: $OUT ($(stat -c%s "$OUT") bytes, $VERSION)"
sha256sum "$OUT" | awk '{print $1}'
