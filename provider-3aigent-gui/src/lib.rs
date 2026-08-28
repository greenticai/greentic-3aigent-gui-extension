//! greentic.provider.aigent-gui — reference provider extension for 3AIgent GUI Direct Line messaging.
//!
//! Messaging-only pilot: metadata + schemas served here. Actual message send
//! runs in the runtime .gtpack that ships embedded in the .gtxpack.

#[allow(warnings)]
mod bindings;

use bindings::exports::greentic::extension_base::{lifecycle, manifest};
use bindings::exports::greentic::extension_provider::messaging;
use bindings::greentic::extension_base::types;
use bindings::greentic::extension_provider::types as provider_types;

const CHANNEL_DIRECT_LINE: &str = "direct-line";
const DIRECT_LINE_SECRET_SCHEMA: &str = include_str!("../schemas/direct-line.secret.schema.json");
const DIRECT_LINE_CONFIG_SCHEMA: &str = include_str!("../schemas/direct-line.config.schema.json");

struct Component;

impl manifest::Guest for Component {
    fn get_identity() -> types::ExtensionIdentity {
        types::ExtensionIdentity {
            id: "greentic.provider.aigent-gui".into(),
            version: "0.2.4".into(),
            kind: types::Kind::Provider,
        }
    }

    fn get_offered() -> Vec<types::CapabilityRef> {
        vec![types::CapabilityRef {
            id: "greentic:messaging/3aigent-direct-line".into(),
            version: "0.1.0".into(),
        }]
    }

    fn get_required() -> Vec<types::CapabilityRef> {
        vec![]
    }
}

impl lifecycle::Guest for Component {
    fn init(_config_json: String) -> Result<(), types::ExtensionError> {
        Ok(())
    }

    fn shutdown() {}
}

impl messaging::Guest for Component {
    fn list_channels() -> Vec<provider_types::ChannelProfile> {
        vec![direct_line_profile()]
    }

    fn describe_channel(
        id: String,
    ) -> Result<provider_types::ChannelProfile, types::ExtensionError> {
        if id == CHANNEL_DIRECT_LINE {
            Ok(direct_line_profile())
        } else {
            Err(types::ExtensionError::NotFound(id))
        }
    }

    fn secret_schema(id: String) -> Result<String, types::ExtensionError> {
        if id == CHANNEL_DIRECT_LINE {
            Ok(DIRECT_LINE_SECRET_SCHEMA.into())
        } else {
            Err(types::ExtensionError::NotFound(id))
        }
    }

    fn config_schema(id: String) -> Result<String, types::ExtensionError> {
        if id == CHANNEL_DIRECT_LINE {
            Ok(DIRECT_LINE_CONFIG_SCHEMA.into())
        } else {
            Err(types::ExtensionError::NotFound(id))
        }
    }

    fn dry_run_encode(_id: String, _sample: Vec<u8>) -> Result<Vec<u8>, types::ExtensionError> {
        Err(types::ExtensionError::Internal(
            "dry-run-encode not implemented in the 3AIgent GUI pilot".into(),
        ))
    }
}

fn direct_line_profile() -> provider_types::ChannelProfile {
    provider_types::ChannelProfile {
        id: CHANNEL_DIRECT_LINE.into(),
        display_name: "Direct Line".into(),
        direction: provider_types::Direction::Bidirectional,
        tier_support: vec![
            provider_types::CardTier::TierANative,
            provider_types::CardTier::TierDTextOnly,
        ],
        metadata: vec![],
    }
}

bindings::export!(Component with_types_in bindings);
