use greentic_provider_3aigent_gui_extension_tests::ext_dir;

fn describe() -> serde_json::Value {
    let path = ext_dir().join("describe.json");
    serde_json::from_reader(std::fs::File::open(&path).expect("describe.json"))
        .expect("describe.json parses")
}

#[test]
fn describe_has_required_provider_fields() {
    let d = describe();
    assert_eq!(d["apiVersion"], "greentic.ai/v2");
    assert_eq!(d["kind"], "ProviderExtension");
    assert_eq!(d["metadata"]["id"], "greentic.provider.aigent-gui");
    assert!(!d["metadata"]["version"].as_str().expect("version").is_empty());
}

#[test]
fn describe_declares_runtime_gtpack() {
    let d = describe();
    let gtpack = &d["runtime"]["components"]["aigent-gui"]["gtpack"];
    assert_eq!(gtpack["file"], "runtime/provider.gtpack");
    let sha = gtpack["sha256"].as_str().expect("sha256 is string");
    assert_eq!(sha.len(), 64, "sha256 must be 64 hex chars");
    assert!(sha.chars().all(|c| c.is_ascii_hexdigit()), "sha256 must be hex");
    assert_eq!(gtpack["pack_id"], "greentic.provider.aigent-gui");
    assert_eq!(gtpack["component_version"], "0.6.0");
}

#[test]
fn describe_declares_compat_ranges() {
    let d = describe();
    let compat = &d["compat"];
    assert!(
        compat["min_designer_version"].as_str().expect("min_designer_version").starts_with(">="),
        "min_designer_version should be a >= range"
    );
    assert!(
        compat["min_runner_version"].as_str().expect("min_runner_version").starts_with('^'),
        "min_runner_version should be a caret range"
    );
    assert!(!compat["contract_version"].as_str().expect("contract_version").is_empty());
    assert!(d["engine"].is_null(), "v1 engine block must be gone");
}

#[test]
fn describe_has_no_leftover_v1_runtime_keys() {
    let d = describe();
    let runtime = &d["runtime"];
    assert!(runtime["gtpack"].is_null(), "v1 runtime.gtpack must be gone");
    assert!(runtime["component"].is_null(), "v1 runtime.component must be gone");
    assert!(runtime["components"].is_object(), "v2 runtime.components must be a map");
}

#[test]
fn describe_offers_3aigent_direct_line_capability() {
    let d = describe();
    let offered = d["capabilities"]["offered"].as_array().expect("offered array");
    assert!(
        offered.iter().any(|c| c["id"] == "greentic:messaging/3aigent-direct-line"),
        "missing greentic:messaging/3aigent-direct-line capability"
    );
}

/// The declaration is what lets greentic-designer resolve this channel to a
/// deployable pack without the digest being compiled into its binary. Without
/// it the designer falls back to its own registry row, and moving a pack
/// version means a designer source edit rather than an extension release.
///
/// The repository is asserted, not the digest. A digest MOVES — that is the
/// point of owning the pin here — while the repository is fixed by the
/// designer's same-repository rule, which refuses an override naming a
/// different one.
#[test]
fn describe_declares_the_channel_it_owns() {
    let d = describe();
    let channel = &d["contributions"]["messaging_channel"];
    assert!(
        !channel.is_null(),
        "provider-3aigent-gui must declare the channel it owns"
    );
    assert_eq!(channel["id"], "messaging-3aigent-gui");
    let oci_ref = channel["ref"].as_str().expect("messaging_channel.ref");
    assert!(
        oci_ref.starts_with("oci://ghcr.io/greenticai/packs/messaging/messaging-3aigent-gui@sha256:"),
        "declared ref must be a digest-pinned reference into the \
         messaging-3aigent-gui repository, which is the only one the designer's \
         same-repository rule accepts; got {oci_ref}"
    );
}
