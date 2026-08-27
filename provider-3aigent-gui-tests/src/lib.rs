//! Helpers for locating the sibling extension crate's static files.

use std::path::PathBuf;

pub fn ext_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("reference-extensions parent")
        .join("provider-3aigent-gui")
}
