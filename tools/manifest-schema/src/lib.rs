// SPDX-License-Identifier: Apache-2.0 OR MIT

/*!
Structured access to the install-action manifests.
*/

#![no_std]
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
    clippy::exhaustive_enums,
    clippy::exhaustive_structs,
    clippy::impl_trait_in_params,
    clippy::std_instead_of_alloc,
    clippy::std_instead_of_core,
    // clippy::missing_inline_in_public_items,
)]
#![allow(clippy::missing_panics_doc, clippy::too_long_first_doc_paragraph)]

extern crate alloc;
extern crate std;

use alloc::{
    collections::BTreeMap,
    string::{String, ToString as _},
    vec::Vec,
};
use core::{
    cmp::{self, Reverse},
    fmt, slice,
    str::FromStr,
};

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
#[non_exhaustive]
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
#[non_exhaustive]
pub struct Manifests {
    pub rust_crate: Option<String>,
    pub template: Option<ManifestTemplate>,
    #[serde(flatten)]
    pub map: BTreeMap<Reverse<Version>, ManifestRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
#[allow(clippy::exhaustive_enums)]
pub enum ManifestRef {
    Ref { version: Version },
    Real(Manifest),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[non_exhaustive]
pub struct Manifest {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_stable_version: Option<Version>,
    #[serde(flatten)]
    pub download_info: BTreeMap<HostPlatform, ManifestDownloadInfo>,
}

impl Manifest {
    #[must_use]
    pub fn new(download_info: BTreeMap<HostPlatform, ManifestDownloadInfo>) -> Self {
        Self { previous_stable_version: None, download_info }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[non_exhaustive]
pub struct ManifestDownloadInfo {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    pub etag: String,
    pub hash: String,
    /// Path to binaries in archive. Default to `${tool}${exe}`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bin: Option<StringOrArray>,
}

impl ManifestDownloadInfo {
    #[must_use]
    pub fn new(
        url: Option<String>,
        etag: String,
        hash: String,
        bin: Option<StringOrArray>,
    ) -> Self {
        Self { url, etag, hash, bin }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[non_exhaustive]
pub struct ManifestTemplate {
    #[serde(flatten)]
    pub download_info: BTreeMap<HostPlatform, ManifestTemplateDownloadInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[non_exhaustive]
pub struct ManifestTemplateDownloadInfo {
    pub url: String,
    /// Path to binaries in archive. Default to `${tool}${exe}`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bin: Option<StringOrArray>,
}

impl ManifestTemplateDownloadInfo {
    #[must_use]
    pub fn new(url: String, bin: Option<StringOrArray>) -> Self {
        Self { url, bin }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
#[allow(clippy::exhaustive_enums)]
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

/// GitHub Actions runner supports x86_64/AArch64/Arm Linux and x86_64/AArch64 Windows/macOS.
/// <https://github.com/actions/runner/blob/v2.332.0/.github/workflows/build.yml#L24>
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
/// - Ignore 32-bit Arm for now, as we need to consider the version and whether hard-float is supported.
///   <https://github.com/rust-lang/rustup/pull/593>
///   <https://github.com/cross-rs/cross/pull/1018>
///   And support for 32-bit Arm will be removed in near future.
///   <https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/#removal-of-operating-system-support-with-node24>
///   Does it seem only armv7l+ is supported?
///   <https://github.com/actions/runner/blob/v2.321.0/src/Misc/externals.sh#L178>
///   <https://github.com/actions/runner/issues/688>
// TODO: support musl with dynamic linking like wasmtime and cyclonedx's musl binaries.
#[allow(non_camel_case_types)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[non_exhaustive]
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
