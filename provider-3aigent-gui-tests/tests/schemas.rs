use greentic_provider_3aigent_gui_extension_tests::ext_dir;
use jsonschema::JSONSchema;

fn load_schema(name: &str) -> serde_json::Value {
    let path = ext_dir().join("schemas").join(name);
    serde_json::from_reader(std::fs::File::open(&path).expect("schema file"))
        .expect("schema parses as JSON")
}

#[test]
fn secret_schema_accepts_empty_object() {
    let schema = load_schema("direct-line.secret.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let valid = serde_json::json!({});
    assert!(compiled.is_valid(&valid));
}

#[test]
fn secret_schema_accepts_all_fields() {
    let schema = load_schema("direct-line.secret.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let valid = serde_json::json!({
        "jwt_signing_key": "a-sufficiently-long-signing-key",
        "oauth_google_client_secret": "google-secret",
        "oauth_microsoft_client_secret": "microsoft-secret",
        "oauth_github_client_secret": "github-secret"
    });
    assert!(compiled.is_valid(&valid));
}

#[test]
fn secret_schema_rejects_short_jwt_signing_key() {
    let schema = load_schema("direct-line.secret.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let invalid = serde_json::json!({ "jwt_signing_key": "short" });
    assert!(!compiled.is_valid(&invalid));
}

#[test]
fn secret_schema_rejects_unknown_property() {
    let schema = load_schema("direct-line.secret.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let invalid = serde_json::json!({ "not_a_real_secret": "value" });
    assert!(!compiled.is_valid(&invalid));
}

#[test]
fn config_schema_accepts_minimum_shape() {
    let schema = load_schema("direct-line.config.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let valid = serde_json::json!({});
    assert!(compiled.is_valid(&valid));
}

#[test]
fn config_schema_accepts_all_fields() {
    let schema = load_schema("direct-line.config.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let valid = serde_json::json!({
        "public_base_url": "https://chat.example.com",
        "mode": "websocket",
        "route": "3aigent-gui-route",
        "tenant_channel_id": "tenant-123",
        "base_url": "https://chat.example.com",
        "presentation_mode": "embed_webcomponent",
        "skin": "3aigent",
        "text_input_enabled": false,
        "nav_links": [{"label": "Docs", "href": "https://example.com/docs"}],
        "oauth_enabled": true
    });
    assert!(compiled.is_valid(&valid));
}

#[test]
fn config_schema_rejects_unknown_mode() {
    let schema = load_schema("direct-line.config.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let invalid = serde_json::json!({ "mode": "carrier-pigeon" });
    assert!(!compiled.is_valid(&invalid));
}

#[test]
fn config_schema_rejects_unknown_presentation_mode() {
    let schema = load_schema("direct-line.config.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let invalid = serde_json::json!({ "presentation_mode": "popup" });
    assert!(!compiled.is_valid(&invalid));
}

#[test]
fn config_schema_rejects_additional_properties() {
    let schema = load_schema("direct-line.config.schema.json");
    let compiled = JSONSchema::compile(&schema).expect("schema compiles");
    let invalid = serde_json::json!({ "oauth_providers": "[]" });
    assert!(!compiled.is_valid(&invalid));
}
