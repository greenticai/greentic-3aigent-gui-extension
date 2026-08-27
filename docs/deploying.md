# Deploying the 3AIgent GUI provider extension

Two deployment targets, same artifact:

- **Local** — install into your own `~/.greentic` so a local designer/runner can
  use it. No registry, no credentials, no publish.
- **Store** — publish to `store.greentic.cloud` so anyone on the tenant can
  install it.

Both start from one `.gtxpack`. Build it once, then choose where it goes.

> This repository has **no CI and no release workflow**. Nothing publishes on
> merge — every step below is run by hand. That is a deliberate gap, not an
> oversight to work around; see [`anatomy.md` §13](anatomy.md#13-open-items).

---

## 0. Prerequisites

| tool | why |
| --- | --- |
| Rust 1.95.0 + `wasm32-wasip2` | pinned by `provider-3aigent-gui/rust-toolchain.toml` |
| `cargo-component` | builds the WASM component |
| `wasm-tools` | validates it |
| `gtdx` **1.2.x** | packs, validates, installs, publishes |
| `jq`, `zip`, `unzip` | used by `build.sh` |

```bash
cargo install cargo-component wasm-tools
cargo install greentic-extension-sdk-cli     # provides gtdx
gtdx --version                               # must be 1.2.x
```

**The gtdx major version matters.** This extension ships a `describe.json` at
`apiVersion: greentic.ai/v2`. A 0.4-era gtdx cannot read it, and a 1.2 gtdx
cannot read a v1 manifest — the two are not interchangeable and there is no
in-place migration.

---

## 1. Build the artifact

### 1a. Get a real runtime pack

The `.gtxpack` embeds a runtime `.gtpack` that does the actual message delivery.
**This repo does not build it.** It comes from
[`greenticai/greentic-messaging-providers`](https://github.com/greenticai/greentic-messaging-providers):

```bash
# in greentic-messaging-providers
ALLOW_REMOTE_COMPONENT_FETCH=0 DRY_RUN=1 \
  PACK_VERSION=<version from packs/messaging-3aigent-gui/pack.yaml> \
  PACK_FILTER=messaging-3aigent-gui ./tools/build_packs_only.sh
# -> dist/packs/messaging-3aigent-gui.gtpack
```

**Set `PACK_VERSION` explicitly.** Unset, that script falls back to the
*workspace* version in the root `Cargo.toml`, which no longer tracks individual
pack versions. The artifact gets stamped with the wrong version and nothing
flags it.

### 1b. Build the extension

```bash
cd provider-3aigent-gui
PROVIDER_3AIGENT_GUI_GTPACK=/abs/path/to/messaging-3aigent-gui.gtpack ./build.sh
# -> greentic.provider.aigent-gui-<version>.gtxpack
```

Without that env var `build.sh` embeds a **placeholder string** instead of a
runtime and warns loudly. Such a build installs fine and serves its schemas, but
cannot move a single message. It is for exercising the install path only — never
publish one.

### 1c. Verify what you actually built

```bash
unzip -q greentic.provider.aigent-gui-*.gtxpack -d /tmp/xp
gtdx validate /tmp/xp
```

Validate the **unpacked artifact**, not the source `describe.json`. `build.sh`
rewrites the manifest while staging (it stamps the runtime digest), so a source
file that validates cleanly proves nothing about what ships. Skipping this
distinction is what let a broken manifest reach the publish step in the sibling
repository and fail all seven jobs at once.

Sanity-check the contents while it is unpacked:

```bash
jq '{id: .metadata.id, version: .metadata.version, api: .apiVersion}' /tmp/xp/describe.json
sha256sum /tmp/xp/runtime/provider.gtpack
jq -r '.runtime.components."aigent-gui".gtpack.sha256' /tmp/xp/describe.json
```

The last two must match. They will not if the runtime was swapped after staging.

---

## 2. Deploy locally

```bash
GREENTIC_EXT_ALLOW_UNSIGNED=1 gtdx install \
  ./provider-3aigent-gui/greentic.provider.aigent-gui-<version>.gtxpack \
  --trust loose -y
```

- `--trust loose` and `GREENTIC_EXT_ALLOW_UNSIGNED=1` are both needed for an
  unsigned dev build. A signed artifact needs neither.
- `-y` skips the permission prompt. Drop it the first time so you can read the
  permissions the extension asks for.
- Installing a **local path** ignores `--version`; that flag is for registry
  installs.

Confirm and manage:

```bash
gtdx list                                    # installed extensions
gtdx info greentic.provider.aigent-gui       # metadata for one
gtdx doctor                                  # diagnose broken installs
gtdx uninstall greentic.provider.aigent-gui
```

Installed extensions live under `~/.greentic/extensions/provider/<id>-<version>/`.

> `gtdx info` and `gtdx list` read **locally installed** extensions, not the
> registry. If an old v1 artifact is still installed, a 1.2 gtdx will fail to
> parse it — `unknown field 'component'`. Uninstall the stale version.

### Iterating

`gtdx dev` rebuilds, repacks and reinstalls on source change:

```bash
cd provider-3aigent-gui && gtdx dev
```

Remember §1b: unless `PROVIDER_3AIGENT_GUI_GTPACK` is exported, each rebuild
embeds the placeholder runtime.

---

## 3. Deploy to the store

### 3a. Authenticate

```bash
gtdx registries list
# default: greentic-store
#   greentic-store  https://store.greentic.cloud

gtdx login                        # browser device flow
gtdx login --paste                # paste a token instead
GTDX_TOKEN=<token> gtdx login     # non-interactive (CI)
```

The token is written to `~/.greentic/credentials.toml`. Treat it as a
credential: never commit it, never paste it into a chat or an issue, and rotate
it if it is exposed. Prefer `GTDX_TOKEN` from a secret store over `--token` on
the command line, which lands in your shell history.

### 3b. Dry run first

```bash
cd provider-3aigent-gui
gtdx publish --registry greentic-store --dry-run
```

Builds, packs and validates without writing to the registry. Fix anything it
reports here — a failure at this point costs nothing, a failure mid-publish
leaves you reasoning about partial state.

Also check the version is actually free:

```bash
gtdx publish --registry greentic-store --verify-only
gtdx search greentic.provider --registry greentic-store
```

### 3c. Publish

```bash
gtdx publish --registry greentic-store \
  --sign --key-env GREENTIC_EXT_SIGNING_KEY_PEM
```

Unsigned publishes are possible but make every consumer pass `--trust loose`.
Sign whenever a key is available.

**The published version comes from `describe.json` `metadata.version` — not
`Cargo.toml`.** These are two separate strings and nothing in this repo checks
that they agree. Getting this wrong is not hypothetical: in the sibling
repository a release ran fully green, reported seven successful publish jobs, and
put the *old* version in the store, silently overwriting a previous build,
because only `Cargo.toml` had been bumped.

Before publishing, confirm they match:

```bash
jq -r .metadata.version describe.json
awk -F'"' '/^version = /{print $2; exit}' Cargo.toml
```

`--version <v>` overrides the manifest for one run (intended for CI bumps).
`--force` overwrites an existing version — reach for it only when you mean to
replace a published artifact, and understand that consumers pinned to that
version silently get different code.

### 3d. Verify the store, not the exit code

```bash
gtdx search greentic.provider --registry greentic-store
```

The version listed here is the only proof the publish landed. A green command is
not enough — check the version string.

### 3e. Install from the store

```bash
gtdx install greentic.provider.aigent-gui \
  --version <version> --registry greentic-store -y
```

---

## 4. Configuring the channel after install

The extension contributes one channel, `direct-line`, offering
`greentic:messaging/3aigent-direct-line`. The designer builds its configuration
form from the two schemas in `schemas/`.

Config worth knowing (full list in
[`anatomy.md` §6](anatomy.md#6-schemas)):

| key | default | meaning |
| --- | --- | --- |
| `public_base_url` | — | public base URL the hosted GUI and Direct Line routes derive from |
| `skin` | `3aigent` | theme folder under `assets/webchat-gui/skins` |
| `oauth_enabled` | `true` | offers OAuth login, including Greentic SSO |
| `presentation_mode` | `standalone` | `standalone` page or `embed_webcomponent` |
| `mode` | `local_queue` | `local_queue`, `websocket`, or `pubsub` |
| `text_input_enabled` | `true` | show the text input in embed mode |

Secrets (`jwt_signing_key`, and the Google / Microsoft / GitHub OAuth client
secrets) are `writeOnly` — the designer never reads them back after they are set.
`jwt_signing_key` is generated by the runner when omitted.

The config schema sets `"additionalProperties": false`. A key the runtime accepts
but the schema does not list is **rejected** before it reaches the runtime. When
the runtime grows a setting, the schema and the i18n bundles have to grow with it
in the same change.

### Pointing a flow at it

The capability is deliberately **not** `greentic:messaging/webchat-direct-line`.
A flow wired to the WebChat provider will not pick this up implicitly — target
`greentic:messaging/3aigent-direct-line` explicitly. That separation is what lets
both providers be installed side by side.

---

## 5. Troubleshooting

| symptom | cause |
| --- | --- |
| `unsupported apiVersion: greentic.ai/v1` | gtdx 1.2 reading a v1 manifest. Rebuild from a v2 source; there is no in-place migration. |
| `unknown field 'gtpack', expected one of ... 'components'` | a v1-shaped `runtime.gtpack` in a v2 manifest. Usually a script stamping `.runtime.gtpack.sha256`; jq *creates* missing paths, so the write silently injects the wrong field. |
| `unknown field 'component'` on install | a stale v1 artifact still installed. `gtdx uninstall` it. |
| publish succeeds, store shows the old version | `metadata.version` was not bumped. `Cargo.toml` does not drive the published version. |
| extension installs but sends nothing | placeholder runtime — `PROVIDER_3AIGENT_GUI_GTPACK` was not set at build time. |
| install refused as unsigned | build without a signing key. Pass `--trust loose` plus `GREENTIC_EXT_ALLOW_UNSIGNED=1`, or sign it. |

---

## 6. Checklist

Build:

- [ ] `./scripts/verify-wit-sync.sh` clean
- [ ] real runtime pack built with an explicit `PACK_VERSION`
- [ ] `PROVIDER_3AIGENT_GUI_GTPACK` exported, and `build.sh` did **not** warn about a placeholder
- [ ] `gtdx validate` on the **unpacked** `.gtxpack`
- [ ] `cd provider-3aigent-gui-tests && cargo test` — 14 passing

Store publish only:

- [ ] `describe.json` `metadata.version` == `Cargo.toml` version
- [ ] that version is not already in the store
- [ ] `--dry-run` clean
- [ ] signed, or the unsigned install burden is accepted
- [ ] `gtdx search` shows the **new** version afterwards
