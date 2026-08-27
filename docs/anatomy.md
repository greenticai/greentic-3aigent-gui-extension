# Anatomy of a provider extension

A file-by-file and line-by-line reading of `greentic.provider.aigent-gui`. If you
are building a *new* provider extension, this doubles as the template: every file
here has an equivalent in the six sibling providers, and the differences between
them are small and mechanical.

---

## 1. The two artifacts inside one `.gtxpack`

The single most important thing to understand: **this extension does not send
messages.** It ships two independent pieces of code with different jobs.

| | `extension.wasm` | `runtime/provider.gtpack` |
| --- | --- | --- |
| built from | this repo (`src/lib.rs`) | `greentic-messaging-providers` |
| runs in | `greentic-designer`, at design time | `greentic-runner`, at message time |
| answers | *what channels exist, what config and secrets do they need* | *actually deliver this message* |

Both are zipped into one `.gtxpack`, along with the JSON schemas, the i18n
bundles and the icon. `gtdx install` unpacks it; the designer loads the WASM to
populate its UI, and the runner loads the embedded pack to move traffic.

This split explains an otherwise puzzling piece of `src/lib.rs`:

```rust
fn dry_run_encode(_id: String, _sample: Vec<u8>) -> Result<Vec<u8>, types::ExtensionError> {
    Err(types::ExtensionError::Internal(
        "dry-run-encode not implemented in the 3AIgent GUI pilot".into(),
    ))
}
```

Encoding is a runtime concern, and the runtime lives in the embedded pack. The
design-time component has no encoder to call, so it refuses rather than
pretending.

---

## 2. Repository layout

```
.
├── README.md
├── .gitignore
├── docs/anatomy.md                     ← this file
├── ci/stamp-gtpack-sha.sh              ← writes the runtime digest into the manifest
├── scripts/verify-wit-sync.sh          ← guards the vendored WIT copies
├── wit/                                ← vendored contract (see §3)
│   ├── extension-base.wit
│   ├── extension-host.wit
│   └── extension-provider.wit
├── provider-3aigent-gui/               ← the extension crate
│   ├── Cargo.toml
│   ├── Cargo.lock
│   ├── rust-toolchain.toml
│   ├── build.sh                        ← produces the .gtxpack
│   ├── describe.json                   ← the manifest the store publishes
│   ├── wit/world.wit                   ← this component's world
│   ├── src/lib.rs                      ← the whole implementation
│   ├── src/bindings.rs                 ← generated, do not edit
│   ├── schemas/*.schema.json           ← config + secret contracts
│   ├── i18n/*.json                     ← labels for the designer UI
│   └── assets/icon.svg
└── provider-3aigent-gui-tests/         ← separate crate, native target
    ├── src/lib.rs
    └── tests/{describe,schemas}.rs
```

The tests live in a **separate crate** on purpose. The extension crate compiles
to `wasm32-wasip2`; you cannot run `cargo test` against it on the host. The test
crate is a plain native crate that reads its sibling's static files from disk.

---

## 3. The WIT contract

### The vendored files

`wit/extension-{base,host,provider}.wit` are **copies** of interfaces owned by
`greentic-biz/greentic-designer-extensions`, pinned to one upstream revision.
Because they are copies, they drift silently when upstream moves.
`scripts/verify-wit-sync.sh` fetches each file at the pinned `UPSTREAM_REV` and
compares sha256:

```bash
./scripts/verify-wit-sync.sh
```

Run it before trusting a build. When you deliberately sync forward, bump
`UPSTREAM_REV` in that script — the same three files are also vendored in
`greentic-biz/greentic-provider-extensions`, so expect to bump both.

### This component's world

`provider-3aigent-gui/wit/world.wit` names what the component consumes and
provides:

```wit
package greentic:provider-aigent-gui-extension;

world extension {
  import greentic:extension-base/types@0.2.0;      // shared data types
  import greentic:extension-host/logging@0.1.0;    // host-provided logger
  import greentic:extension-host/i18n@0.1.0;       // host-provided translation

  export greentic:extension-base/manifest@0.2.0;   // identity + capabilities
  export greentic:extension-base/lifecycle@0.2.0;  // init / shutdown
  export greentic:extension-provider/messaging@0.2.0;  // the provider surface
}
```

Imports are what the host hands you; exports are what you must implement. Every
export here has a matching `impl ... for Component` in `src/lib.rs`, and the
compiler will not let you omit one.

### Why the package name has no `3`

The package is `greentic:provider-aigent-gui-extension` while every user-visible
identifier keeps the `3`. The component-model label grammar rejects a label that
**begins** with a digit:

```
greentic:3aigent-gui-extension     → rejected
3greentic:aigent                   → rejected
greentic:provider-3aigent-gui-extension  → accepted
```

Note the third line. Only the *first* character of a label is constrained — a
digit-leading word later in a dashed label is legal. So `provider-3aigent-gui-extension`
would have been a valid package name, and dropping the `3` was not forced by the
grammar. (An earlier version of the README stated the rule more broadly than it
actually is.)

---

## 4. `src/lib.rs`, walked

99 lines, and every one of them is contract plumbing. There is no business logic
in this component.

### Bindings and constants

```rust
#[allow(warnings)]
mod bindings;
```

`src/bindings.rs` is **generated** by `cargo component` from `wit/world.wit`. It
is committed so the crate builds without a codegen step, but never hand-edit it —
change the WIT and rebuild.

```rust
const CHANNEL_DIRECT_LINE: &str = "direct-line";
const DIRECT_LINE_SECRET_SCHEMA: &str = include_str!("../schemas/direct-line.secret.schema.json");
const DIRECT_LINE_CONFIG_SCHEMA: &str = include_str!("../schemas/direct-line.config.schema.json");
```

`include_str!` bakes the schema files into the WASM **at compile time**. A
consequence worth internalising: editing a file under `schemas/` and re-zipping
is not enough — the schema the designer actually reads comes from inside the
binary, so you must rebuild. The copies placed in the `.gtxpack` under `schemas/`
are for tooling and inspection; the component serves its own embedded copy.

### `manifest::Guest` — who am I

```rust
fn get_identity() -> types::ExtensionIdentity {
    types::ExtensionIdentity {
        id: "greentic.provider.aigent-gui".into(),
        version: "0.2.1".into(),
        kind: types::Kind::Provider,
    }
}
```

Called first, by the designer, to identify the extension. **These two strings are
duplicated in `describe.json`** (`metadata.id`, `metadata.version`) and nothing
in the build checks that they agree. Keep them in sync by hand; a mismatch means
the manifest advertises one version and the component reports another.

```rust
fn get_offered() -> Vec<types::CapabilityRef> {
    vec![types::CapabilityRef {
        id: "greentic:messaging/3aigent-direct-line".into(),
        version: "0.1.0".into(),
    }]
}
```

The capability id is deliberately **not** `greentic:messaging/webchat-direct-line`.
That distinction is what lets this be installed next to the WebChat provider
without ambiguity — a flow wired to the WebChat capability will not silently pick
this up. Point flows at `3aigent-direct-line` explicitly.

`get_required()` returns empty: this extension depends on no other extension.

### `lifecycle::Guest` — start and stop

```rust
fn init(_config_json: String) -> Result<(), types::ExtensionError> { Ok(()) }
fn shutdown() {}
```

Both are no-ops. There is nothing to set up because there is no state and no
connection — the runtime pack owns all of that. A provider that needed to
validate global config at load time would do it in `init` and return
`ExtensionError` to refuse the load.

### `messaging::Guest` — the provider surface

Four of the five methods share one shape: check the channel id, answer or fail.

```rust
fn list_channels() -> Vec<provider_types::ChannelProfile> { vec![direct_line_profile()] }

fn describe_channel(id: String) -> Result<provider_types::ChannelProfile, types::ExtensionError> {
    if id == CHANNEL_DIRECT_LINE { Ok(direct_line_profile()) }
    else { Err(types::ExtensionError::NotFound(id)) }
}
```

`list_channels` is how the designer populates its channel picker.
`describe_channel`, `secret_schema` and `config_schema` are then called with the
chosen id to build the configuration form. An unknown id returns `NotFound`
rather than an empty result, so the designer can distinguish "no such channel"
from "channel with nothing to configure".

A multi-channel provider (Slack, say) returns several profiles from
`list_channels` and matches on the id in the other three. That is the only
structural difference.

### The channel profile

```rust
fn direct_line_profile() -> provider_types::ChannelProfile {
    provider_types::ChannelProfile {
        id: CHANNEL_DIRECT_LINE.into(),
        display_name: "Direct Line".into(),
        direction: provider_types::Direction::Bidirectional,
        tier_support: vec![CardTier::TierANative, CardTier::TierDTextOnly],
        metadata: vec![],
    }
}
```

`tier_support` declares which Adaptive Card tiers the channel renders. `TierANative`
means the browser GUI renders Adaptive Cards natively; `TierDTextOnly` is the
plain-text fallback. Providers that cannot render cards at all (Telegram, Email)
declare only `TierD`.

### The export macro

```rust
bindings::export!(Component with_types_in bindings);
```

Wires the `Component` struct into the component-model exports. Without it the
crate compiles to a WASM module with no exports, and the designer sees nothing.

---

## 5. `describe.json`

The manifest. **This is the file the store reads, and `metadata.version` is the
version gtdx publishes at** — not the version in `Cargo.toml`.

```jsonc
{
  "$schema": "https://store.greentic.cloud/schemas/describe-v2.json",
  "apiVersion": "greentic.ai/v2",       // manifest schema version
  "kind": "ProviderExtension",
  "compat": {                           // what host versions this works with
    "min_designer_version": ">=1.2.0",
    "min_runner_version": "^1.2.7",
    "contract_version": "1.2.7"
  },
  "metadata": {
    "id": "greentic.provider.aigent-gui",
    "name": "3AIgent GUI",
    "version": "0.2.1",                 // ← the published version
    "summary": "...",
    "author": { "name": "Greentic", "email": "team@greentic.ai" },
    "license": "MIT",
    "icon": "assets/icon.svg"           // path inside the .gtxpack
  },
  "capabilities": {
    "offered":  [ { "id": "greentic:messaging/3aigent-direct-line", "version": "0.1.0" } ],
    "required": []
  },
  "runtime": {
    "components": {                     // one entry per component
      "aigent-gui": {
        "gtpack": {                     // the embedded runtime
          "file": "runtime/provider.gtpack",
          "sha256": "0000…0",           // placeholder; build.sh stamps the real one
          "pack_id": "greentic.provider.aigent-gui",
          "component_version": "0.6.0"  // the greentic:component WIT version
        },
        "sha256": "0000…0",
        "world": "greentic:provider-aigent-gui-extension/extension@1.0.0"
      }
    },
    "permissions": {                    // deny-by-default sandbox
      "network": [],                    // no outbound hosts allowed
      "secrets": [],                    // reads no secrets itself
      "callExtensionKinds": []          // calls no other extensions
    },
    "memoryLimitMB": 32
  },
  "contributions": {}
}
```

In v1 this block was flat — `runtime.component` pointed at the WASM and
`runtime.gtpack` held the embedded pack. v2 replaces both with the
`runtime.components` map so one extension can ship several components, each with
its own world and digest.

Two things deserve emphasis.

**The empty `permissions` block is a real deny-list, not a stub.** The design-time
component reaches no network, reads no secrets and calls nothing. Widening any of
those arrays is a security decision, not a formality.

**The `sha256` of `0000…0` is a placeholder by design.** `build.sh` computes the
real digest of whatever runtime pack it embedded and rewrites the field in the
staged copy. The committed file keeps zeros so a stale digest can never be
mistaken for a verified one.

---

## 6. `schemas/`

Two JSON Schema (draft 2020-12) files define the configuration contract the
designer renders as a form.

`direct-line.config.schema.json` — non-secret settings: `public_base_url`,
`mode` (`local_queue` | `websocket` | `pubsub`), `route`, `tenant_channel_id`,
`base_url`, `presentation_mode` (`standalone` | `embed_webcomponent`), `skin`
(default `3aigent`), `text_input_enabled`, `nav_links`, `oauth_enabled`
(default `true` — this is the SSO-on-by-default switch).

`direct-line.secret.schema.json` — credentials: `jwt_signing_key` and the three
OAuth client secrets. Every property is marked `writeOnly`, which tells the
designer to render it as a write-only field and never echo the stored value back.

Both set `"additionalProperties": false`. That is deliberate and it bites: a
config key the runtime accepts but the schema omits will be **rejected** before
it reaches the runtime. When you add a field to the runtime, add it here in the
same change.

---

## 7. `i18n/`

Six locales (`de`, `en`, `es`, `id`, `ja`, `zh`), flat key/value JSON. The key
convention mirrors the config surface:

```
provider.3aigent-gui.displayName
provider.3aigent-gui.channel.direct-line.displayName
provider.3aigent-gui.channel.direct-line.description
provider.3aigent-gui.config.<field>.label
provider.3aigent-gui.config.<field>.help
provider.3aigent-gui.secret.<field>.label
provider.3aigent-gui.secret.<field>.help
```

The designer resolves these through the imported
`greentic:extension-host/i18n` interface to label the generated form. A missing
key degrades to showing the raw field name — no crash, just an ugly form. Adding
a config field means three edits: the schema, `i18n/en.json`, and ideally the
other five locales.

---

## 8. `build.sh`, step by step

```bash
cd provider-3aigent-gui
PROVIDER_3AIGENT_GUI_GTPACK=/path/to/messaging-3aigent-gui.gtpack ./build.sh
```

What it does, in order:

1. **Validate inputs.** Every file in `schemas/` must parse as JSON and look like
   a schema (`$schema` or `type`); every file in `i18n/` must parse as JSON.
2. **Compile.** `cargo component build --release --locked --target wasm32-wasip2`.
   `--locked` means a stale `Cargo.lock` fails the build rather than silently
   resolving new dependencies — regenerate the lockfile when you bump the version.
3. **Verify the artifact.** `wasm-tools validate` on the produced component.
4. **Sign, or deliberately not.** With `GREENTIC_EXT_SIGNING_KEY_PEM` set it runs
   `gtdx sign describe.json`. Without it, it *strips* any existing `signature`
   field so an unsigned artifact is honestly unsigned rather than carrying a
   stale signature.
5. **Stage.** Copies `describe.json`, the WASM as `extension.wasm`, `schemas/`,
   `i18n/` and `assets/` into a temp directory.
6. **Embed the runtime.** With `PROVIDER_3AIGENT_GUI_GTPACK` pointing at a real
   pack it copies it in. Without it, it writes a **placeholder string** and warns.
   A placeholder build installs but cannot move a message — useful for exercising
   the install path, useless for running anything.
7. **Stamp the digest.** Computes the sha256 of the embedded pack and hands it to
   `ci/stamp-gtpack-sha.sh`, which rewrites
   `runtime.components.<name>.gtpack.sha256` in the staged manifest. That script
   errors out when it finds no gtpack block rather than creating one — see §12
   for why that guard exists.
8. **Zip** to `greentic.provider.3aigent-gui-<version>.gtxpack`, normalising the
   `.zip` suffix some `zip` implementations append.

### Where the runtime pack comes from

This repo does not build it. From `greenticai/greentic-messaging-providers`:

```bash
ALLOW_REMOTE_COMPONENT_FETCH=0 DRY_RUN=1 \
  PACK_VERSION=<version from packs/messaging-3aigent-gui/pack.yaml> \
  PACK_FILTER=messaging-3aigent-gui ./tools/build_packs_only.sh
# -> dist/packs/messaging-3aigent-gui.gtpack
```

**Set `PACK_VERSION` explicitly.** Left unset, that script falls back to the
*workspace* version from the root `Cargo.toml`, which no longer tracks individual
pack versions — the artifact gets stamped with the wrong version and nothing
flags it.

---

## 9. Tests

```bash
cd provider-3aigent-gui-tests && cargo test
```

14 tests, all reading the sibling crate's files from disk via the `ext_dir()`
helper:

- `tests/describe.rs` (5) — manifest shape: `apiVersion`, `kind`, `metadata.id`,
  a 64-char hex `runtime.components.aigent-gui.gtpack.sha256`, the `compat`
  ranges, that the `3aigent-direct-line` capability is offered, and that no v1
  `runtime.gtpack` / `runtime.component` / `engine` key survives.
- `tests/schemas.rs` (9) — both schemas compile as JSON Schema and accept/reject
  representative documents.

These assert the manifest **as committed**, which is why they pin `apiVersion`
and the exact id — and why a manifest-format migration means editing these tests
in the same change.

---

## 10. Building a new provider extension

The mechanical path, given this repo as the template:

1. Copy `provider-3aigent-gui/` and the top-level `wit/` + `scripts/`.
2. In `Cargo.toml`: rename the package, set
   `[package.metadata.component] package = "greentic:provider-<name>-extension"`
   (remember §3 — the label may not *begin* with a digit).
3. In `wit/world.wit`: match that package name. Keep the imports and exports.
4. In `src/lib.rs`: change the id, the capability id, and the channel constants;
   add one `ChannelProfile` per channel and match on its id in `describe_channel`,
   `secret_schema` and `config_schema`.
5. Write `schemas/<channel>.config.schema.json` and `.secret.schema.json`.
6. Write `i18n/en.json` following the key convention, then the other locales.
7. Update `describe.json` — id, name, version, capability, `gtpack.pack_id`.
8. Update the test crate's expected id and capability.
9. `./build.sh` (placeholder runtime first, to check the shape), then with a real
   `*_GTPACK` when the runtime pack exists.

Steps 4, 7 and 8 all restate the same id. Nothing enforces that they agree —
grep for the old id before you call it done.

---

## 11. Install

Full deployment guide, local and store: [`deploying.md`](deploying.md).

```bash
GREENTIC_EXT_ALLOW_UNSIGNED=1 gtdx install \
  ./provider-3aigent-gui/greentic.provider.3aigent-gui-<version>.gtxpack \
  --trust loose -y
```

`--trust loose` and the env flag are both needed for an unsigned dev build; a
signed artifact needs neither.

---

## 12. The v1 → v2 migration

This extension was migrated from manifest `apiVersion greentic.ai/v1` to `v2`.
The record matters because a current `gtdx` refuses v1 outright:

```
Error: unsupported apiVersion: greentic.ai/v1 (expected greentic.ai/v2;
there is no in-place migration — install a v2 build of the extension, or
re-scaffold and re-publish it with a current gtdx)
```

What changed:

| | v1 | v2 |
| --- | --- | --- |
| `apiVersion` | `greentic.ai/v1` | `greentic.ai/v2` |
| host compatibility | `engine.greenticDesigner` / `engine.extRuntime` | `compat.min_designer_version` / `min_runner_version` / `contract_version` |
| runtime | flat `runtime.component` + `runtime.gtpack` | `runtime.components` map keyed by component name |
| WIT world | `world provider-extension` | `world extension` |
| WIT interfaces | `@0.1.0` | `@0.2.0` (`extension-host` stayed at `0.1.0`) |
| error type | `provider_types::Error` | `types::ExtensionError` |

### The trap in the sha stamping

`build.sh` used to stamp the digest with:

```bash
jq '.runtime.gtpack.sha256 = $sha'
```

**jq creates missing paths.** Run against a v2 manifest that no longer has
`runtime.gtpack`, this does not fail — it injects a fresh v1-shaped object, and
gtdx then rejects the entire document over an unknown field. In the sibling
repository the same line took down all seven publish jobs at once.

The write now lives in `ci/stamp-gtpack-sha.sh`, which targets
`.runtime.components.*.gtpack.sha256` and *errors* when there is no gtpack block
to update, instead of inventing one.

### The identifier change

The published extension is `greentic.provider.aigent-gui`, without the `3`, so
this repo adopted that id to stay continuous with what is already in the store.
Note that this was **not** forced by validation — `gtdx validate` accepts
`greentic.provider.3aigent-gui` in a v2 manifest just as readily. The id was
matched to the published artifact deliberately; changing it back would create a
second, parallel store entry rather than an update.

### Verifying a migration

```bash
./scripts/verify-wit-sync.sh                     # vendored WIT matches upstream
cd provider-3aigent-gui && ./build.sh            # builds, stamps, zips
cd ../provider-3aigent-gui-tests && cargo test   # 14 tests
unzip -q ../provider-3aigent-gui/*.gtxpack -d /tmp/x && gtdx validate /tmp/x
```

The last line is the one that matters, and it is the step that is easy to skip:
validate the **built artifact**, not the source `describe.json`. `build.sh`
rewrites the manifest while staging, so a source file that validates cleanly says
nothing about what actually ships.

---

## 13. Open items

- `assets/icon.svg` is a 388-byte placeholder. Real 3AIgent artwork is needed;
  the brand asset that exists today is a PNG.
- `get_identity()` in `src/lib.rs` and `metadata` in `describe.json` restate the
  same id and version with no check that they agree. The sibling repository grew
  a `ci/check-version-sync.sh` for exactly this class of drift; this repo has no
  equivalent yet.
- There is no CI workflow here. Every check in §12 is manual.
