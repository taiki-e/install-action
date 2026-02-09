// SPDX-License-Identifier: Apache-2.0 OR MIT

/*!
Structured access to the install-action manifests.
*/

#![doc(test(
    no_crate_inject,
    attr(allow(
        dead_code,
        unused_variables,
        clippy::undocumented_unsafe_blocks,
        clippy::unused_trait_names,
    ))
))]
#![warn(
    // Lints that may help when writing public library.
    missing_debug_implementations,
    // missing_docs,
    clippy::alloc_instead_of_core,
    // clippy::exhaustive_enums,
    // clippy::exhaustive_structs,
    clippy::impl_trait_in_params,
    // clippy::missing_inline_in_public_items,
    clippy::std_instead_of_alloc,
    clippy::std_instead_of_core,
)]
#![allow(clippy::missing_panics_doc, clippy::too_long_first_doc_paragraph)]

extern crate alloc;

use alloc::collections::BTreeMap;
use core::{
    cmp::{self, Reverse},
    fmt, slice,
    str::FromStr,
};
use std::path::Path;

use serde::{
    de::{self, Deserialize, Deserializer},
    ser::{Serialize, Serializer},
};
use serde_derive::{Deserialize, Serialize};

#[must_use]
pub fn get_manifest_schema_branch_name() -> &'static str {
    if env!("CARGO_PKG_VERSION_MAJOR") == "0" {
        concat!("manifest-schema-0.", env!("CARGO_PKG_VERSION_MINOR"))
    } else {
        concat!("manifest-schema-", env!("CARGO_PKG_VERSION_MAJOR"))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Version {
    pub major: Option<u64>,
    pub minor: Option<u64>,
    pub patch: Option<u64>,
    pub pre: semver::Prerelease,
    pub build: semver::BuildMetadata,
}

impl Version {
    #[must_use]
    pub fn omitted(major: u64, minor: Option<u64>) -> Self {
        Self {
            major: Some(major),
            minor,
            patch: None,
            pre: semver::Prerelease::default(),
            build: semver::BuildMetadata::default(),
        }
    }
    #[must_use]
    pub fn latest() -> Self {
        Self {
            major: None,
            minor: None,
            patch: None,
            pre: semver::Prerelease::default(),
            build: semver::BuildMetadata::default(),
        }
    }
    #[must_use]
    pub fn to_semver(&self) -> Option<semver::Version> {
        Some(semver::Version {
            major: self.major?,
            minor: self.minor?,
            patch: self.patch?,
            pre: self.pre.clone(),
            build: self.build.clone(),
        })
    }
}
impl From<semver::Version> for Version {
    fn from(v: semver::Version) -> Self {
        Self {
            major: Some(v.major),
            minor: Some(v.minor),
            patch: Some(v.patch),
            pre: v.pre,
            build: v.build,
        }
    }
}
impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for Version {
    fn cmp(&self, other: &Self) -> cmp::Ordering {
        pub(crate) fn convert(v: &Version) -> semver::Version {
            semver::Version {
                major: v.major.unwrap_or(u64::MAX),
                minor: v.minor.unwrap_or(u64::MAX),
                patch: v.patch.unwrap_or(u64::MAX),
                pre: v.pre.clone(),
                build: v.build.clone(),
            }
        }
        convert(self).cmp(&convert(other))
    }
}
impl fmt::Display for Version {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let Some(major) = self.major else {
            f.write_str("latest")?;
            return Ok(());
        };
        f.write_str(&major.to_string())?;
        let Some(minor) = self.minor else {
            return Ok(());
        };
        f.write_str(".")?;
        f.write_str(&minor.to_string())?;
        let Some(patch) = self.patch else {
            return Ok(());
        };
        f.write_str(".")?;
        f.write_str(&patch.to_string())?;
        if !self.pre.is_empty() {
            f.write_str("-")?;
            f.write_str(&self.pre)?;
        }
        if !self.build.is_empty() {
            f.write_str("+")?;
            f.write_str(&self.build)?;
        }
        Ok(())
    }
}
impl FromStr for Version {
    type Err = semver::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        if s == "latest" {
            return Ok(Self::latest());
        }
        match s.parse::<semver::Version>() {
            Ok(v) => Ok(v.into()),
            Err(e) => match s.parse::<semver::Comparator>() {
                Ok(v) => Ok(Self {
                    major: Some(v.major),
                    minor: v.minor,
                    patch: v.patch,
                    pre: semver::Prerelease::default(),
                    build: semver::BuildMetadata::default(),
                }),
                Err(_e) => Err(e),
            },
        }
    }
}
impl Serialize for Version {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        String::serialize(&self.to_string(), serializer)
    }
}
impl<'de> Deserialize<'de> for Version {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        String::deserialize(deserializer)?.parse().map_err(de::Error::custom)
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Manifests {
    pub rust_crate: Option<String>,
    pub template: Option<ManifestTemplate>,
    /// Markdown for the licenses.
    pub license_markdown: String,
    #[serde(flatten)]
    pub map: BTreeMap<Reverse<Version>, ManifestRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ManifestRef {
    Ref { version: Version },
    Real(Manifest),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_stable_version: Option<Version>,
    #[serde(flatten)]
    pub download_info: BTreeMap<HostPlatform, ManifestDownloadInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManifestDownloadInfo {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    pub etag: String,
    pub checksum: String,
    /// Path to binaries in archive. Default to `${tool}${exe}`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bin: Option<StringOrArray>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManifestTemplate {
    #[serde(flatten)]
    pub download_info: BTreeMap<HostPlatform, ManifestTemplateDownloadInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManifestTemplateDownloadInfo {
    pub url: String,
    /// Path to binaries in archive. Default to `${tool}${exe}`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bin: Option<StringOrArray>,
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
    pub tag_prefix: String,
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
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Signing {
    pub kind: SigningKind,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
#[serde(deny_unknown_fields)]
pub enum SigningKind {
    /// algorithm: minisign
    /// public key: package.metadata.binstall.signing.pubkey at Cargo.toml
    /// <https://github.com/cargo-bins/cargo-binstall/blob/HEAD/SIGNING.md>
    MinisignBinstall,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BaseManifestPlatformInfo {
    /// Asset name patterns. Default to the value at `BaseManifest::asset_name`.
    pub asset_name: Option<StringOrArray>,
    /// Path to binaries in archive. Default to the value at `BaseManifest::bin`.
    pub bin: Option<StringOrArray>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum StringOrArray {
    String(String),
    Array(Vec<String>),
}

impl StringOrArray {
    #[must_use]
    pub fn as_slice(&self) -> &[String] {
        match self {
            Self::String(s) => slice::from_ref(s),
            Self::Array(v) => v,
        }
    }
    #[must_use]
    pub fn map<F: FnMut(&String) -> String>(&self, mut f: F) -> Self {
        match self {
            Self::String(s) => Self::String(f(s)),
            Self::Array(v) => Self::Array(v.iter().map(f).collect()),
        }
    }
}

/// GitHub Actions Runner supports x86_64/AArch64/Arm Linux, x86_64/AArch64 Windows,
/// and x86_64/AArch64 macOS.
/// <https://github.com/actions/runner/blob/v2.321.0/.github/workflows/build.yml#L21>
/// <https://docs.github.com/en/actions/reference/runners/self-hosted-runners#supported-processor-architectures>
/// And IBM provides runners for powerpc64le/s390x Linux.
/// <https://github.com/IBM/actionspz>
///
/// Note:
/// - Static-linked binaries compiled for linux-musl will also work on linux-gnu systems and are
///   usually preferred over linux-gnu binaries because they can avoid glibc version issues.
///   (rustc enables statically linking for linux-musl by default, except for mips.)
/// - Binaries compiled for x86_64 macOS will usually also work on AArch64 macOS.
/// - Binaries compiled for x86_64 Windows will usually also work on AArch64 Windows 11+.
/// - Ignore Arm for now, as we need to consider the version and whether hard-float is supported.
///   <https://github.com/rust-lang/rustup/pull/593>
///   <https://github.com/cross-rs/cross/pull/1018>
///   Does it seem only armv7l+ is supported?
///   <https://github.com/actions/runner/blob/v2.321.0/src/Misc/externals.sh#L178>
///   <https://github.com/actions/runner/issues/688>
// TODO: support musl with dynamic linking like wasmtime 22.0.0+'s musl binaries: <https://github.com/bytecodealliance/wasmtime/releases/tag/v22.0.0>
#[allow(non_camel_case_types)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum HostPlatform {
    x86_64_linux_gnu,
    x86_64_linux_musl,
    x86_64_macos,
    x86_64_windows,
    aarch64_linux_gnu,
    aarch64_linux_musl,
    aarch64_macos,
    aarch64_windows,
    powerpc64le_linux_gnu,
    powerpc64le_linux_musl,
    riscv64_linux_gnu,
    riscv64_linux_musl,
    s390x_linux_gnu,
    s390x_linux_musl,
}

impl HostPlatform {
    #[must_use]
    pub fn rust_target(self) -> &'static str {
        match self {
            Self::x86_64_linux_gnu => "x86_64-unknown-linux-gnu",
            Self::x86_64_linux_musl => "x86_64-unknown-linux-musl",
            Self::x86_64_macos => "x86_64-apple-darwin",
            Self::x86_64_windows => "x86_64-pc-windows-msvc",
            Self::aarch64_linux_gnu => "aarch64-unknown-linux-gnu",
            Self::aarch64_linux_musl => "aarch64-unknown-linux-musl",
            Self::aarch64_macos => "aarch64-apple-darwin",
            Self::aarch64_windows => "aarch64-pc-windows-msvc",
            Self::powerpc64le_linux_gnu => "powerpc64le-unknown-linux-gnu",
            Self::powerpc64le_linux_musl => "powerpc64le-unknown-linux-musl",
            Self::riscv64_linux_gnu => "riscv64gc-unknown-linux-gnu",
            Self::riscv64_linux_musl => "riscv64gc-unknown-linux-musl",
            Self::s390x_linux_gnu => "s390x-unknown-linux-gnu",
            Self::s390x_linux_musl => "s390x-unknown-linux-musl",
        }
    }
    #[must_use]
    pub fn rust_target_arch(self) -> &'static str {
        match self {
            Self::aarch64_linux_gnu
            | Self::aarch64_linux_musl
            | Self::aarch64_macos
            | Self::aarch64_windows => "aarch64",
            Self::x86_64_linux_gnu
            | Self::x86_64_linux_musl
            | Self::x86_64_macos
            | Self::x86_64_windows => "x86_64",
            Self::powerpc64le_linux_gnu | Self::powerpc64le_linux_musl => "powerpc64",
            Self::riscv64_linux_gnu | Self::riscv64_linux_musl => "riscv64",
            Self::s390x_linux_gnu | Self::s390x_linux_musl => "s390x",
        }
    }
    #[must_use]
    pub fn rust_target_os(self) -> &'static str {
        match self {
            Self::aarch64_linux_gnu
            | Self::aarch64_linux_musl
            | Self::x86_64_linux_gnu
            | Self::x86_64_linux_musl
            | Self::powerpc64le_linux_gnu
            | Self::powerpc64le_linux_musl
            | Self::riscv64_linux_gnu
            | Self::riscv64_linux_musl
            | Self::s390x_linux_gnu
            | Self::s390x_linux_musl => "linux",
            Self::aarch64_macos | Self::x86_64_macos => "macos",
            Self::aarch64_windows | Self::x86_64_windows => "windows",
        }
    }
    #[must_use]
    pub fn exe_suffix(self) -> &'static str {
        match self {
            Self::x86_64_windows | Self::aarch64_windows => ".exe",
            _ => "",
        }
    }
}
