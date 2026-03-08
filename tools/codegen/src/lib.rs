// SPDX-License-Identifier: Apache-2.0 OR MIT

#![allow(clippy::missing_panics_doc, clippy::too_long_first_doc_paragraph)]

use std::{env, path::Path};

pub use install_action_manifest_schema::*;

#[must_use]
pub fn workspace_root() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR").strip_suffix("tools/codegen").unwrap())
}
