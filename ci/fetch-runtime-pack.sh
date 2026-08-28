#!/usr/bin/env bash
# Fetch the real runtime .gtpack into <dir>/provider.gtpack.
# Usage: ci/fetch-runtime-pack.sh <target-dir>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?usage: $0 <target-dir>}"

# shellcheck source=/dev/null
. "$ROOT/ci/runtime-pack.env"
: "${RUNTIME_PACK_REF:?RUNTIME_PACK_REF unset}"
: "${RUNTIME_PACK_VERSION:?RUNTIME_PACK_VERSION unset}"

command -v oras >/dev/null || { echo "oras not on PATH"; exit 1; }

mkdir -p "$DEST"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "==> pulling ${RUNTIME_PACK_REF}:${RUNTIME_PACK_VERSION}"
( cd "$tmp" && oras pull "${RUNTIME_PACK_REF}:${RUNTIME_PACK_VERSION}" >/dev/null )

pack=$(find "$tmp" -name '*.gtpack' -print -quit)
[ -n "$pack" ] || { echo "no .gtpack in the pulled artifact"; exit 1; }

mv "$pack" "$DEST/provider.gtpack"
echo "==> runtime/provider.gtpack $(stat -c%s "$DEST/provider.gtpack") bytes, sha256=$(sha256sum "$DEST/provider.gtpack" | cut -d' ' -f1)"
