// SPDX-License-Identifier: Apache-2.0 OR MIT

#![allow(clippy::missing_panics_doc, clippy::too_long_first_doc_paragraph)]

use std::{collections::BTreeMap, env, path::Path};

pub use install_action_manifest_schema::*;
use serde_derive::Deserialize;

#[must_use]
pub fn workspace_root() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR").strip_suffix("tools/codegen").unwrap())
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BaseManifest {
    /// Link to the GitHub repository.
    pub repository: String,
    /// Alternative link for the project.  Automatically detected if possible.
    pub website: Option<String>,
    /// Markdown syntax for links to licenses.  Automatically detected if possible.
    pub license_markdown: Option<String>,
    /// Prefix of release tag.
    pub tag_prefix: StringOrArray,
    /// Crate name, if this is Rust crate.
    pub rust_crate: Option<String>,
    pub default_major_version: Option<String>,
    /// Asset name patterns.
    pub asset_name: Option<StringOrArray>,
    /// Path to binaries in archive. Default to `${tool}${exe}`.
    pub bin: Option<StringOrArray>,
    pub signing: Option<Signing>,
    #[serde(default)]
    pub broken: Vec<semver::Version>,
    pub version_range: Option<String>,
    /// Use glibc build if host_env is gnu.
    #[serde(default)]
    pub prefer_linux_gnu: bool,
    /// Check that the version is yanked not only when updating the manifest,
    /// but also when running the action.
    #[serde(default)]
    pub immediate_yank_reflection: bool,
    pub platform: BTreeMap<HostPlatform, BaseManifestPlatformInfo>,
}
impl BaseManifest {
    /// Validate the manifest.
    pub fn validate(&self) {
        for bin in self.bin.iter().chain(self.platform.values().flat_map(|m| &m.bin)) {
            assert!(!bin.as_slice().is_empty());
            for bin in bin.as_slice() {
                let file_name = Path::new(bin).file_name().unwrap().to_str().unwrap();
                if !self.repository.ends_with("/xbuild") {
                    assert!(
                        !(file_name.contains("${version") || file_name.contains("${rust")),
                        "{bin}"
                    );
                }
            }
        }
        if self.platform.is_empty() {
            panic!("At least one platform must be specified");
        }
        if let Some(website) = &self.website {
            if website.is_empty() || *website == self.repository {
                panic!(
                    "Please do not put the repository in website, or set website to an empty value"
                );
            }
        }
        if let Some(license_markdown) = &self.license_markdown {
            if license_markdown.is_empty() {
                panic!("license_markdown can not be an empty value");
            }
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Signing {
    pub version_range: Option<String>,
    pub kind: SigningKind,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
#[serde(deny_unknown_fields)]
pub enum SigningKind {
    /// gh attestation
    /// <https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations>
    #[serde(rename_all = "kebab-case")]
    GhAttestation { signer_workflow: String },
    /// algorithm: minisign
    /// public key: package.metadata.binstall.signing.pubkey at Cargo.toml
    /// <https://github.com/cargo-bins/cargo-binstall/blob/HEAD/SIGNING.md>
    MinisignBinstall,
    /// tool-specific
    Custom,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BaseManifestPlatformInfo {
    /// Asset name patterns. Default to the value at `BaseManifest::asset_name`.
    pub asset_name: Option<StringOrArray>,
    /// Path to binaries in archive. Default to the value at `BaseManifest::bin`.
    pub bin: Option<StringOrArray>,
}
