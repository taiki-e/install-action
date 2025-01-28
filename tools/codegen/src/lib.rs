// SPDX-License-Identifier: Apache-2.0 OR MIT

#![allow(clippy::missing_panics_doc, clippy::too_long_first_doc_paragraph)]

use std::{env, path::PathBuf};

pub use install_action_manifest_schema::*;

#[must_use]
pub fn workspace_root() -> PathBuf {
    let mut dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    dir.pop(); // codegen
    dir.pop(); // tools
    dir
}
