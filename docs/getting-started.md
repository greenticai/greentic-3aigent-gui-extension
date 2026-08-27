# From zero to a published provider extension

Start with nothing installed; finish with an extension live on
`store.greentic.cloud`. Every command here was run against `gtdx 1.2.7` and its
real output is quoted.

Three documents, three jobs:

| | |
| --- | --- |
| **this file** | build a provider extension from scratch, `gtdx new` → published |
| [`anatomy.md`](anatomy.md) | what every file in *this* repo means, line by line |
| [`deploying.md`](deploying.md) | deploying an existing artifact, local and store |

---

## 1. Install the toolchain

```bash
# Rust 1.95 + the WASM component target
rustup toolchain install 1.95.0
rustup target add --toolchain 1.95.0 wasm32-wasip2

# component tooling
cargo install cargo-component
cargo install wasm-tools

# gtdx — the extension CLI
cargo install greentic-extension-sdk-cli
gtdx --version        # gtdx 1.2.7
```

Also needed by the packaging scripts: `jq`, `zip`, `unzip`.

**The gtdx major version is load-bearing.** The 1.2 line reads `describe.json`
at `apiVersion: greentic.ai/v2`. A 0.4-era gtdx cannot, and 1.2 cannot read a v1
manifest either — there is no in-place migration between them:

```
Error: unsupported apiVersion: greentic.ai/v1 (expected greentic.ai/v2;
there is no in-place migration — install a v2 build of the extension, or
re-scaffold and re-publish it with a current gtdx)
```

If you inherit an older extension, re-scaffold rather than hand-patching.

---

## 2. Scaffold

```bash
gtdx new my-gui \
  --kind provider \
  --id greentic.provider.my-gui \
  --version 0.1.0 \
  --license MIT \
  -y
```

`--kind` accepts `design`, `bundle`, `deploy`, `provider`, `wasm-component`,
`mcp`, `llm`. Omit `-y` (on a terminal) for an interactive wizard.

It preflights your toolchain, then reports:

```
  ✓ cargo: ~/.cargo/bin/cargo
  ✓ cargo-component: ~/.cargo/bin/cargo-component
  ✓ wasm32-wasip2 target: installed
  ✓ target directory: my-gui (will be created)

Scaffolded provider extension at my-gui (18 files, contract 0.2.0).
```

### What you get

```
my-gui/
├── describe.json                 the manifest — v2, already valid
├── Cargo.toml                    component package + WIT dependency wiring
├── rust-toolchain.toml           pins 1.95.0 + wasm32-wasip2
├── src/lib.rs                    a working provider, not an empty stub
├── wit/world.wit                 your component's world
├── wit/deps/greentic/…           vendored contract (3 files)
├── .gtdx-contract.lock           sha256 lock over those vendored files
├── build.sh                      thin wrapper over cargo component build
├── ci/local_check.sh             fmt + clippy + test + build
├── i18n/en.json                  labels for the designer UI
├── README.md / CLAUDE.md / AGENTS.md
└── .claude/                      agent instructions + a /check command
```

Two things worth noticing immediately.

**`.gtdx-contract.lock`** pins the vendored WIT by digest:

```toml
contract_version = "0.2.0"
generated_by = "gtdx 1.2.7"

[files]
"wit/deps/greentic/extension-base/world.wit" = "sha256:f57d3b01…"
"wit/deps/greentic/extension-host/world.wit" = "sha256:11f6fc76…"
"wit/deps/greentic/extension-provider/world.wit" = "sha256:35f2610c…"
```

The contract files are copies. Without a lock they drift silently when upstream
moves, and you find out at runtime. Do not edit those files by hand.

**The scaffold already builds and validates.** Before changing a line:

```bash
cd my-gui
gtdx validate .
# ✓ ./describe.json valid
```

It ships one working `webhook` channel so a fresh build has something to show —
the designer lists it and renders its forms. Replace it; do not start from a
blank file.

---

## 3. Make it yours

### 3a. Identity — in three places

```rust
// src/lib.rs
fn get_identity() -> types::ExtensionIdentity {
    types::ExtensionIdentity {
        id: "greentic.provider.my-gui".to_string(),
        version: "0.1.0".to_string(),
        kind: types::Kind::Provider,
    }
}
```

```jsonc
// describe.json
"metadata": { "id": "greentic.provider.my-gui", "version": "0.1.0" }
```

```toml
# Cargo.toml
version = "0.1.0"
```

**Nothing checks that these agree**, and the mismatch is not cosmetic:
`describe.json` `metadata.version` is what gtdx publishes, while `Cargo.toml`
only names the artifact. A release that bumps one and not the other publishes
the old version and silently overwrites it. That has happened.

Copy [`ci/check-version-sync.sh`](../ci/check-version-sync.sh) from this repo
and run it in CI. It compares all three and fails on drift.

### 3b. Channels

A channel is one way your provider sends or receives. `list_channels` is what
the designer's picker shows:

```rust
fn list_channels() -> Vec<messaging::ChannelProfile> {
    vec![messaging::ChannelProfile {
        id: "direct-line".to_string(),
        display_name: "Direct Line".to_string(),
        direction: provider_types::Direction::Bidirectional,
        tier_support: vec![
            provider_types::CardTier::TierANative,
            provider_types::CardTier::TierDTextOnly,
        ],
        metadata: vec![],
    }]
}
```

`direction` is `Outbound`, `Inbound` or `Bidirectional`. `tier_support` declares
how richly the channel renders an Adaptive Card, best first — native, then
attachment, then fallback layout, then plain text. **Declare the honest floor:**
the designer downgrades content to the best tier you actually claim, so
overclaiming produces broken output at the far end, not a friendly error.

`describe_channel`, `secret_schema` and `config_schema` then match on the id and
return `NotFound` for anything you do not own — the designer reads that as "ask
someone else", which is what lets several providers coexist.

### 3c. Schemas

The scaffold inlines its JSON Schemas as string literals. Once they are more
than a few fields, move them to `schemas/` and pull them in at compile time, as
this repo does:

```rust
const DIRECT_LINE_CONFIG_SCHEMA: &str =
    include_str!("../schemas/direct-line.config.schema.json");
```

`include_str!` bakes the file into the WASM **at compile time**. Editing the
schema and repacking is not enough — the designer reads the copy inside the
binary, so you must rebuild.

Set `"additionalProperties": false` deliberately: it means a config key your
runtime accepts but the schema omits is rejected before it ever reaches the
runtime. That is usually what you want, and it means schema and runtime have to
move in the same change.

Mark credentials `"writeOnly": true` so the designer never echoes a stored value
back.

### 3d. Capabilities

```rust
fn get_offered() -> Vec<types::CapabilityRef> {
    vec![types::CapabilityRef {
        id: "greentic:messaging/my-gui-direct-line".to_string(),
        version: "0.1.0".to_string(),
    }]
}
```

Keep this in step with `capabilities.offered` in `describe.json`.

Choose a capability id that is **distinct** if a similar provider already
exists. This repo offers `greentic:messaging/3aigent-direct-line` rather than
reusing `webchat-direct-line` precisely so both can be installed side by side
and a flow has to name which one it means.

### 3e. i18n

Flat key/value JSON, one file per locale, keyed to your config surface:

```
provider.my-gui.displayName
provider.my-gui.channel.direct-line.displayName
provider.my-gui.config.<field>.label
provider.my-gui.config.<field>.help
provider.my-gui.secret.<field>.label
```

A missing key degrades to the raw field name — an ugly form, not a crash.
Adding a config field is three edits: schema, `i18n/en.json`, and the other
locales.

### 3f. The runtime pack

For a **messaging** provider, the extension you are building answers questions;
it does not deliver messages. Delivery lives in a separate runtime `.gtpack`
that ships embedded in the `.gtxpack`, and `describe.json` points at it:

```jsonc
"runtime": {
  "components": {
    "my-gui": {
      "gtpack": {
        "file": "runtime/provider.gtpack",
        "sha256": "0000…0",          // stamped at build time
        "pack_id": "greentic.provider.my-gui",
        "component_version": "0.6.0"
      },
      "sha256": "0000…0",
      "world": "greentic-provider:my-gui/extension@1.0.0"
    }
  }
}
```

Replace the scaffold's placeholder before publishing. An extension published
with a placeholder installs cleanly and serves its schemas, but **cannot move a
single message** — a failure mode that looks like success.

Stamp the digest with a script that targets the v2 path and refuses to invent
one — see [`ci/stamp-gtpack-sha.sh`](../ci/stamp-gtpack-sha.sh). Do not write
`.runtime.gtpack.sha256`: jq *creates* missing paths, so on a v2 manifest that
silently injects a v1-shaped field and gtdx then rejects the whole document.

---

## 4. Build and check

```bash
gtdx validate .
bash ci/local_check.sh     # fmt + clippy + test + build
```

`gtdx publish` builds and packs on its own, so you rarely need `build.sh`
directly:

```bash
gtdx publish --dry-run
# dry-run: would publish …/dist/publish-staging.gtxpack to ~/.greentic/registries/local
# sha256: d34f8cdf…
```

Then validate what was actually produced:

```bash
rm -rf /tmp/xp && mkdir -p /tmp/xp
unzip -q dist/*.gtxpack -d /tmp/xp
gtdx validate /tmp/xp
```

**Validate the unpacked artifact, not the source manifest.** Packaging rewrites
`describe.json` while staging, so a clean source file proves nothing about what
ships. Skipping that distinction is how a broken manifest reached the publish
step in a sibling repository and failed every job at once.

---

## 5. Install locally

```bash
GREENTIC_EXT_ALLOW_UNSIGNED=1 gtdx install \
  ./dist/my-gui-0.1.0.gtxpack --trust loose -y
```

Both flags are for an unsigned dev build; a signed artifact needs neither. Drop
`-y` the first time so you can read the permissions being requested.

```bash
gtdx list                          # what is installed
gtdx info greentic.provider.my-gui
gtdx doctor                        # diagnose broken installs
gtdx uninstall greentic.provider.my-gui
```

`gtdx list` and `gtdx info` read **locally installed** extensions, not the
registry.

To iterate, `gtdx dev` watches, rebuilds and reinstalls on change.

---

## 6. Publish to the store

```bash
gtdx registries list
# default: greentic-store
#   greentic-store  https://store.greentic.cloud

gtdx login                       # browser device flow
GTDX_TOKEN=<token> gtdx login    # non-interactive
```

The token lands in `~/.greentic/credentials.toml`. Treat it as a credential:
never commit it, never paste it into a chat or an issue, prefer `GTDX_TOKEN`
from a secret store over `--token` on the command line (which lands in shell
history), and rotate it if it is ever exposed.

```bash
# is the version free?
gtdx publish --registry greentic-store --verify-only

# rehearse
gtdx publish --registry greentic-store --dry-run

# go
gtdx publish --registry greentic-store --sign --key-env GREENTIC_EXT_SIGNING_KEY_PEM
```

Publishing unsigned works but makes every consumer pass `--trust loose`. Sign
whenever a key exists.

Useful flags: `--version <v>` overrides the manifest for one run (for CI bumps);
`--force` overwrites an existing version — reach for it only when you mean to
replace a published artifact, and understand that anyone pinned to that version
silently gets different code.

### Then check the store, not the exit code

```bash
gtdx search greentic.provider.my-gui --registry greentic-store
```

The version listed here is the only proof. A green publish is not: one release
reported seven successful publish jobs while the store kept the previous
version, because only `Cargo.toml` had been bumped.

---

## 7. Automate it

This repo's workflows are a working reference:

- [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) — WIT sync, version
  sync, build, validate the unpacked artifact, digest match, tests
- [`.github/workflows/release.yml`](../.github/workflows/release.yml) —
  `detect` → `publish` → `verify` → `tag`

Three details worth copying:

1. **Trigger on `describe.json` `metadata.version`, not `Cargo.toml`** — the
   former is what gtdx publishes.
2. **Fail the build when the version copies drift** (`check-version-sync.sh`).
3. **Query the store after publishing and fail if the new version is absent.**
   Trusting the publish job's exit code is what let a silent no-op release ship.

Store the token as a repository secret; never in-tree.

---

## 8. Two things the scaffold gets wrong today

Verified against `gtdx 1.2.7`:

**`build.sh` looks in the wrong directory.** It runs `cargo component build
--release` with no `--target`, which produces
`target/wasm32-wasip1/release/<name>.wasm`, then does `cd
target/wasm32-wasip2/release` — which does not exist:

```
Creating component target/wasm32-wasip1/release/demo_gui.wasm
./build.sh: line 5: cd: target/wasm32-wasip2/release: No such file or directory
```

Fix by making the target explicit, as this repo's `build.sh` does:

```bash
cargo component build --release --locked --target wasm32-wasip2
```

`gtdx publish` is unaffected — it drives the build itself.

**The scaffold's `runtime.components.<name>.gtpack.file` points at
`extension.wasm`**, which is the design-time component, not a runtime pack.
For a messaging provider that is a placeholder you must replace (§3f).

---

## 9. Checklist

Before your first publish:

- [ ] `gtdx validate .` clean
- [ ] id and version agree in `describe.json`, `Cargo.toml`, `get_identity()`
- [ ] capability id distinct from any similar provider
- [ ] real runtime `.gtpack` embedded — **not** the placeholder
- [ ] digest in the manifest matches the embedded pack
- [ ] `gtdx validate` on the **unpacked** `.gtxpack`
- [ ] `--dry-run` clean, `--verify-only` says the version is free
- [ ] signed, or the unsigned install burden accepted
- [ ] after publishing: `gtdx search` shows the **new** version
