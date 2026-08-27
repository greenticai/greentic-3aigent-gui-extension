# greentic-3aigent-gui-extension

The 3AIgent GUI provider, packaged as a Greentic **provider extension**.

A provider extension is a WASM component implementing `greentic:extension-provider`, packaged into a `.gtxpack` alongside an embedded runtime `.gtpack`. `greentic-designer` reads the extension to learn what channels exist and what config and secrets they need; `greentic-runner` executes the embedded runtime pack.

For a file-by-file and line-by-line reading — what every file is for, what each
function in `src/lib.rs` answers, and how to build a new provider extension from
this one as a template — see [`docs/anatomy.md`](docs/anatomy.md).

## What it offers

| | |
| --- | --- |
| extension id | `greentic.provider.3aigent-gui` |
| channel | `direct-line` |
| capability | `greentic:messaging/3aigent-direct-line` |
| runtime pack | `messaging-3aigent-gui` |

The capability id is deliberately distinct from `greentic:messaging/webchat-direct-line`, so this can be installed alongside the WebChat provider without ambiguity. A flow wired to the WebChat capability will not pick this up implicitly — point it at `3aigent-direct-line` explicitly.

## Where the runtime comes from

The embedded `runtime/provider.gtpack` is built in
[`greenticai/greentic-messaging-providers`](https://github.com/greenticai/greentic-messaging-providers)
from `packs/messaging-3aigent-gui`. This repo does not build it.

```bash
# 1. In greentic-messaging-providers, build the pack:
ALLOW_REMOTE_COMPONENT_FETCH=0 DRY_RUN=1 \
  PACK_VERSION=<the pack's own version from packs/messaging-3aigent-gui/pack.yaml> \
  PACK_FILTER=messaging-3aigent-gui ./tools/build_packs_only.sh
# -> dist/packs/messaging-3aigent-gui.gtpack

# 2. Here, build the extension with that runtime embedded:
cd provider-3aigent-gui
PROVIDER_3AIGENT_GUI_GTPACK=/path/to/messaging-3aigent-gui.gtpack ./build.sh
# -> greentic.provider.3aigent-gui-<version>.gtxpack
```

Set `PACK_VERSION` explicitly in step 1. Left unset, `build_packs_only.sh` falls back to the *workspace* version from the root `Cargo.toml`, which no longer tracks individual pack versions — the artifact would be stamped with the wrong version and nothing would flag it.

Without `PROVIDER_3AIGENT_GUI_GTPACK`, `build.sh` embeds a placeholder string instead of a real runtime. That is useful for exercising the install path, not for running anything.

## Install

```bash
GREENTIC_EXT_ALLOW_UNSIGNED=1 gtdx install \
  ./provider-3aigent-gui/greentic.provider.3aigent-gui-<version>.gtxpack \
  --trust loose -y
```

Builds are unsigned unless `GREENTIC_EXT_SIGNING_KEY_PEM` is set.

## Tests

```bash
cd provider-3aigent-gui-tests && cargo test
```

13 tests validating `describe.json` and the JSON schemas.

## The vendored WIT contract

`wit/extension-{base,host,provider}.wit` are **copies** of the interface definitions owned by
[`greentic-biz/greentic-designer-extensions`](https://github.com/greentic-biz/greentic-designer-extensions),
pinned to a specific upstream revision. `scripts/verify-wit-sync.sh` checks them by sha256 against that revision.

Because they are a copy, they drift silently when upstream moves. Run the check before trusting a build:

```bash
./scripts/verify-wit-sync.sh
```

Bump `UPSTREAM_REV` in that script deliberately when syncing forward. The same three files are also vendored in
`greentic-biz/greentic-provider-extensions`, which is where this extension was originally developed alongside its
siblings — expect to bump both.

## Known gaps

- `provider-3aigent-gui/assets/icon.svg` is a placeholder. Real 3AIgent artwork is needed; the brand asset that exists today is a PNG.
- The WIT package name is `greentic:provider-aigent-gui-extension`, without the `3`. Every user-visible identifier keeps it. The stated reason used to be that the component-model label grammar forbids a dash-separated word beginning with a digit — that is too broad. Only the *first* character of a label is constrained: `greentic:3aigent-gui-extension` is rejected, but `greentic:provider-3aigent-gui-extension` is accepted. Dropping the `3` was not forced by the grammar.
- The repo is at `apiVersion: greentic.ai/v1` and cannot be published or installed by a current `gtdx`, which requires v2. The published `0.2.0` also carries a different id (`greentic.provider.aigent-gui`). See [Known divergences](docs/anatomy.md#12-known-divergences-between-this-repo-and-the-published-extension).
