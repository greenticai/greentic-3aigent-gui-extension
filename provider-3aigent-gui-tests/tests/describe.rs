use greentic_provider_3aigent_gui_extension_tests::ext_dir;

fn describe() -> serde_json::Value {
    let path = ext_dir().join("describe.json");
    serde_json::from_reader(std::fs::File::open(&path).expect("describe.json"))
        .expect("describe.json parses")
}

#[test]
fn describe_has_required_provider_fields() {
    let d = describe();
    assert_eq!(d["apiVersion"], "greentic.ai/v1");
    assert_eq!(d["kind"], "ProviderExtension");
    assert_eq!(d["metadata"]["id"], "greentic.provider.3aigent-gui");
    assert!(!d["metadata"]["version"].as_str().expect("version").is_empty());
}

#[test]
fn describe_declares_runtime_gtpack() {
    let d = describe();
    let gtpack = &d["runtime"]["gtpack"];
    assert_eq!(gtpack["file"], "runtime/provider.gtpack");
    let sha = gtpack["sha256"].as_str().expect("sha256 is string");
    assert_eq!(sha.len(), 64, "sha256 must be 64 hex chars");
    assert!(sha.chars().all(|c| c.is_ascii_hexdigit()), "sha256 must be hex");
    assert_eq!(gtpack["pack_id"], "greentic.provider.3aigent-gui");
    assert_eq!(gtpack["component_version"], "0.6.0");
}

#[test]
fn describe_engine_accepts_any_designer_version() {
    let d = describe();
    assert_eq!(d["engine"]["greenticDesigner"], "*");
    let ext_runtime = d["engine"]["extRuntime"].as_str().expect("extRuntime");
    assert!(ext_runtime.starts_with("^0.1"), "extRuntime should pin ^0.1.x");
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
