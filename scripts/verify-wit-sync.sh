#!/usr/bin/env bash
# Verify wit/*.wit matches the pinned upstream rev.
# Bump UPSTREAM_REV explicitly when syncing to a new upstream commit.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

UPSTREAM_REPO="greentic-biz/greentic-designer-extensions"
UPSTREAM_REV="154863b8b785c010bea3e91200d5c78f7a7fed7f"
UPSTREAM_BASE="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_REV}/wit"

FILES=(extension-base.wit extension-host.wit extension-provider.wit)
FAILED=0

for f in "${FILES[@]}"; do
    if ! [ -f "wit/${f}" ]; then
        echo "FAIL: wit/${f} missing"
        FAILED=1
        continue
    fi
    LOCAL_SHA=$(sha256sum "wit/${f}" | cut -d' ' -f1)
    REMOTE_SHA=$(curl -fsSL "${UPSTREAM_BASE}/${f}" | sha256sum | cut -d' ' -f1)
    if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
        echo "FAIL: wit/${f} drift vs upstream@${UPSTREAM_REV:0:7}"
        echo "  local:  $LOCAL_SHA"
        echo "  remote: $REMOTE_SHA"
        FAILED=1
    else
        echo "OK: wit/${f} matches upstream@${UPSTREAM_REV:0:7}"
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo
    echo "To fix: either"
    echo "  (a) refresh local:"
    echo "      curl -fsSL ${UPSTREAM_BASE}/<file> > wit/<file>"
    echo "  (b) bump UPSTREAM_REV in scripts/verify-wit-sync.sh to match wit/"
    exit 1
fi
