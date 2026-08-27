#!/usr/bin/env bash
# Build greentic.provider.aigent-gui reference extension into a .gtxpack.
# Requires: rust 1.95.0 + wasm32-wasip2, cargo-component, wasm-tools, jq, zip, sha256sum.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

VERSION="$(awk -F\" '/^version/ {print $2; exit}' Cargo.toml)"
ID="greentic.provider.aigent-gui"

echo "==> validate schemas parse as JSON"
for schema in schemas/*.schema.json; do
    jq empty "$schema"
    jq -e 'has("$schema") or has("type")' "$schema" >/dev/null \
        || { echo "not a JSON Schema: $schema"; exit 1; }
done

echo "==> validate i18n files parse as JSON"
for i18n_file in i18n/*.json; do
    jq empty "$i18n_file"
done

echo "==> cargo component build --release --locked --target wasm32-wasip2"
cargo component build --release --locked --target wasm32-wasip2

WASM_SRC="${HERE}/target/wasm32-wasip2/release/greentic_provider_3aigent_gui_extension.wasm"
[ -f "$WASM_SRC" ] || { echo "ERROR: wasm not found at $WASM_SRC"; exit 1; }

echo "==> wasm-tools validate"
wasm-tools validate "$WASM_SRC"

# Env-aware signing: CI sets GREENTIC_EXT_SIGNING_KEY_PEM via GH secret.
# Dev mode (no env) ships unsigned with a warning; runtime will reject unless
# GREENTIC_EXT_ALLOW_UNSIGNED=1 or install uses --trust loose.
if [ -n "${GREENTIC_EXT_SIGNING_KEY_PEM:-}" ]; then
    echo "==> sign describe.json (GREENTIC_EXT_SIGNING_KEY_PEM set)"
    command -v gtdx >/dev/null || {
        echo "ERROR: gtdx not on PATH — install with 'cargo install --git https://github.com/greentic-biz/greentic-designer-extensions --rev <sha> greentic-ext-cli'"
        exit 1
    }
    gtdx sign describe.json
else
    echo "==> unsigned build (GREENTIC_EXT_SIGNING_KEY_PEM not set — dev mode)"
    # Strip any prior signature so the unsigned artifact is clean.
    if jq -e '.signature' describe.json >/dev/null 2>&1; then
        tmp=$(mktemp)
        jq 'del(.signature)' describe.json > "$tmp" && mv "$tmp" describe.json
    fi
fi

# Stage content
STAGE="$(mktemp -d)"
trap "rm -rf $STAGE" EXIT

mkdir -p "$STAGE/schemas" "$STAGE/i18n" "$STAGE/runtime"
cp describe.json "$STAGE/"
cp "$WASM_SRC" "$STAGE/extension.wasm"
cp schemas/*.json "$STAGE/schemas/"
cp i18n/*.json "$STAGE/i18n/"
if [ -d assets ]; then
  mkdir -p "$STAGE/assets"
  cp assets/*.svg "$STAGE/assets/" 2>/dev/null || true
fi

# Runtime .gtpack source
if [ -n "${PROVIDER_3AIGENT_GUI_GTPACK:-}" ]; then
    if [ ! -f "$PROVIDER_3AIGENT_GUI_GTPACK" ]; then
        echo "ERROR: PROVIDER_3AIGENT_GUI_GTPACK=$PROVIDER_3AIGENT_GUI_GTPACK not found"
        exit 1
    fi
    echo "==> using real runtime .gtpack from PROVIDER_3AIGENT_GUI_GTPACK"
    cp "$PROVIDER_3AIGENT_GUI_GTPACK" "$STAGE/runtime/provider.gtpack"
else
    echo "==> WARNING: using placeholder runtime .gtpack (set PROVIDER_3AIGENT_GUI_GTPACK for real runtime)"
    printf '3aigent-gui-runtime-placeholder-v0.1.0-this-is-not-a-real-gtpack!\n' > "$STAGE/runtime/provider.gtpack"
fi

# Compute sha256 of embedded gtpack + rewrite describe.json in STAGE
GTPACK_SHA="$(sha256sum "$STAGE/runtime/provider.gtpack" | awk '{print $1}')"
echo "==> embed runtime/provider.gtpack sha256=${GTPACK_SHA}"

bash "$HERE/../ci/stamp-gtpack-sha.sh" "$STAGE/describe.json" "$GTPACK_SHA"

# Final zip
OUT="$HERE/${ID}-${VERSION}.gtxpack"
rm -f "$OUT" "${OUT}.zip"
cd "$STAGE"
zip -X -r "$OUT" describe.json extension.wasm schemas i18n runtime $([ -d assets ] && echo assets) >/dev/null
# Some zip implementations (Python zipfile wrapper on some dev machines) append
# .zip unconditionally. InfoZip on Ubuntu CI does not — but does when filename
# has no dots. Normalise both cases.
if [ -f "${OUT}.zip" ] && [ ! -f "$OUT" ]; then
    mv "${OUT}.zip" "$OUT"
fi
[ -f "$OUT" ] || { echo "ERROR: zip did not produce $OUT"; exit 1; }

echo "==> built ${OUT} ($(du -h "$OUT" | cut -f1))"
