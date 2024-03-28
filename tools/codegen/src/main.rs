// SPDX-License-Identifier: Apache-2.0 OR MIT

use std::{
    cmp::{self, Reverse},
    collections::{BTreeMap, BTreeSet},
    env,
    ffi::OsStr,
    fmt,
    io::Read,
    path::{Path, PathBuf},
    slice,
    str::FromStr,
    time::Duration,
};

use anyhow::{bail, Context as _, Result};
use fs_err as fs;
use serde::{
    de::{self, Deserialize, Deserializer},
    ser::{Serialize, Serializer},
};
use serde_derive::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

fn main() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    if args.is_empty() || args.iter().any(|arg| arg.starts_with('-')) {
        println!(
            "USAGE: cargo run -p install-action-internal-codegen -r -- <PACKAGE> [VERSION_REQ]"
        );
        std::process::exit(1);
    }
    let package = &args[0];

    let workspace_root = &workspace_root();
    let manifest_path = &workspace_root.join("manifests").join(format!("{package}.json"));
    let download_cache_dir = &workspace_root.join("tools/codegen/tmp/cache").join(package);
    fs::create_dir_all(manifest_path.parent().unwrap())?;
    fs::create_dir_all(download_cache_dir)?;

    let mut base_info: BaseManifest = serde_json::from_slice(&fs::read(
        workspace_root.join("tools/codegen/base").join(format!("{package}.json")),
    )?)?;
    base_info.validate();
    let repo = base_info
        .repository
        .strip_prefix("https://github.com/")
        .context("repository must be starts with https://github.com/")?;

    eprintln!("downloading releases of https://github.com/{repo} from https://api.github.com/repos/{repo}/releases");
    let mut releases: github::Releases = vec![];
    // GitHub API returns up to 100 results at a time. If the number of releases
    // is greater than 100, multiple fetches are needed.
    for page in 1.. {
        let per_page = 100;
        let mut r: github::Releases = download(&format!(
            "https://api.github.com/repos/{repo}/releases?per_page={per_page}&page={page}"
        ))?
        .into_json()?;
        if r.len() < per_page {
            releases.append(&mut r);
            break;
        }
        releases.append(&mut r);
    }
    let releases: BTreeMap<_, _> = releases
        .iter()
        .filter_map(|release| {
            if release.prerelease {
                return None;
            }
            let version = release.tag_name.strip_prefix(&base_info.tag_prefix)?;
            let mut semver_version = version.parse::<semver::Version>();
            if semver_version.is_err() {
                if let Some(default_major_version) = &base_info.default_major_version {
                    semver_version = format!("{default_major_version}.{version}").parse();
                }
            }
            Some((Reverse(semver_version.ok()?), (version, release)))
        })
        .collect();

    let mut crates_io_info = None;
    base_info.rust_crate = base_info
        .rust_crate
        .as_ref()
        .map(|s| replace_vars(s, package, None, None, base_info.rust_crate.as_deref()))
        .transpose()?;
    if let Some(crate_name) = &base_info.rust_crate {
        eprintln!("downloading crate info from https://crates.io/api/v1/crates/{crate_name}");
        crates_io_info = Some(
            download(&format!("https://crates.io/api/v1/crates/{crate_name}"))?
                .into_json::<crates_io::Crate>()?,
        );
    }

    let mut manifests: Manifests = Manifests::default();
    let mut semver_versions = BTreeSet::new();
    let mut has_build_metadata = false;

    let mut latest_only = false;
    if let Some(version_range) = &base_info.version_range {
        if version_range == "latest" {
            latest_only = true;
        }
    }
    if manifest_path.is_file() {
        match serde_json::from_slice(&fs::read(manifest_path)?) {
            Ok(m) => {
                manifests = m;
                for (k, manifest) in &mut manifests.map {
                    let ManifestRef::Real(manifest) = manifest else {
                        continue;
                    };
                    let version = &*k.0.to_string();
                    if let Some(template) = &manifests.template {
                        for (platform, d) in &mut manifest.download_info {
                            let template = &template.download_info[platform];
                            d.url = Some(template.url.replace("${version}", version));
                            d.bin = template
                                .bin
                                .as_ref()
                                .map(|s| s.map(|s| s.replace("${version}", version)));
                        }
                    }
                }
                manifests.template = None;
            }
            Err(e) => eprintln!("failed to load old manifest: {e}"),
        }
    }
    let version_req: Option<semver::VersionReq> = match args.get(1) {
        _ if latest_only => {
            let req = format!("={}", releases.first_key_value().unwrap().0 .0).parse()?;
            eprintln!("update manifest for versions '{req}'");
            Some(req)
        }
        None => match base_info.version_range {
            Some(version_range) => Some(version_range.parse()?),
            None => Some(">= 0.0.1".parse()?), // HACK: ignore pre-releases
        },
        Some(version_req) => {
            for version in manifests.map.keys() {
                let Some(semver_version) = version.0.to_semver() else {
                    continue;
                };
                has_build_metadata |= !semver_version.build.is_empty();
                if semver_version.pre.is_empty() {
                    semver_versions.insert(semver_version.clone());
                }
            }

            let req = if version_req == "latest" {
                // TODO: this should check all missing versions
                if manifests.map.is_empty() {
                    format!("={}", releases.first_key_value().unwrap().0 .0).parse()?
                } else {
                    format!(">={}", semver_versions.last().unwrap()).parse()?
                }
            } else {
                version_req.parse()?
            };
            eprintln!("update manifest for versions '{req}'");
            Some(req)
        }
    };

    let mut buf = vec![];
    let mut buf2 = vec![];
    for (Reverse(semver_version), (version, release)) in &releases {
        if let Some(version_req) = &version_req {
            if !version_req.matches(semver_version) {
                continue;
            }
        }

        // Specifically skip versions of xbuild with build metadata.
        if base_info.rust_crate.as_deref() == Some("xbuild") && !semver_version.build.is_empty() {
            continue;
        }

        let mut download_info = BTreeMap::new();
        let mut pubkey = None;
        for (&platform, base_download_info) in &base_info.platform {
            let asset_names = base_download_info
                .asset_name
                .as_ref()
                .or(base_info.asset_name.as_ref())
                .with_context(|| format!("asset_name is needed for {package} on {platform:?}"))?
                .as_slice()
                .iter()
                .map(|asset_name| {
                    replace_vars(
                        asset_name,
                        package,
                        Some(version),
                        Some(platform),
                        base_info.rust_crate.as_deref(),
                    )
                })
                .collect::<Result<Vec<_>>>()?;
            let (url, asset_name) = match asset_names.iter().find_map(|asset_name| {
                release
                    .assets
                    .iter()
                    .find(|asset| asset.name == *asset_name)
                    .map(|asset| (asset, asset_name))
            }) {
                Some((asset, asset_name)) => {
                    (asset.browser_download_url.clone(), asset_name.clone())
                }
                None => {
                    eprintln!("no asset '{asset_names:?}' for host platform '{platform:?}'");
                    continue;
                }
            };

            eprint!("downloading {url} for checksum ... ");
            let download_cache = &download_cache_dir.join(format!(
                "{version}-{platform:?}-{}",
                Path::new(&url).file_name().unwrap().to_str().unwrap()
            ));
            if download_cache.is_file() {
                eprintln!("already downloaded");
                fs::File::open(download_cache)?.read_to_end(&mut buf)?;
            } else {
                download(&url)?.into_reader().read_to_end(&mut buf)?;
                eprintln!("download complete");
                fs::write(download_cache, &buf)?;
            }
            eprintln!("getting sha256 hash for {url}");
            let hash = Sha256::digest(&buf);
            let hash = format!("{hash:x}");
            eprintln!("{hash} *{asset_name}");
            let bin_url = &url;

            match base_info.signing {
                Some(Signing { kind: SigningKind::MinisignBinstall }) => {
                    let url = url.clone() + ".sig";
                    let sig_download_cache = &download_cache.with_extension(format!(
                        "{}.sig",
                        download_cache.extension().unwrap_or_default().to_str().unwrap()
                    ));
                    eprint!("downloading {url} for signature validation ... ");
                    let sig = if sig_download_cache.is_file() {
                        eprintln!("already downloaded");
                        minisign_verify::Signature::from_file(sig_download_cache)?
                    } else {
                        let buf = download(&url)?.into_string()?;
                        eprintln!("download complete");
                        fs::write(sig_download_cache, &buf)?;
                        minisign_verify::Signature::decode(&buf)?
                    };

                    let Some(crates_io_info) = &crates_io_info else {
                        bail!("signing kind minisign-binstall is supported only for rust crate");
                    };
                    let v =
                        crates_io_info.versions.iter().find(|v| v.num == *semver_version).unwrap();
                    let url = format!("https://crates.io{}", v.dl_path);
                    let crate_download_cache =
                        &download_cache_dir.join(format!("{version}-Cargo.toml"));
                    eprint!("downloading {url} for signature verification ... ");
                    if crate_download_cache.is_file() {
                        eprintln!("already downloaded");
                    } else {
                        download(&url)?.into_reader().read_to_end(&mut buf2)?;
                        let hash = Sha256::digest(&buf2);
                        if format!("{hash:x}") != v.checksum {
                            bail!("checksum mismatch for {url}");
                        }
                        let decoder = flate2::read::GzDecoder::new(&*buf2);
                        let mut archive = tar::Archive::new(decoder);
                        for entry in archive.entries()? {
                            let mut entry = entry?;
                            let path = entry.path()?;
                            if path.file_name() == Some(OsStr::new("Cargo.toml")) {
                                entry.unpack(crate_download_cache)?;
                                break;
                            }
                        }
                        buf2.clear();
                        eprintln!("download complete");
                    }
                    if pubkey.is_none() {
                        let cargo_manifest = toml_edit::de::from_str::<cargo_manifest::Manifest>(
                            &fs::read_to_string(crate_download_cache)?,
                        )?;
                        eprintln!(
                            "algorithm: {}",
                            cargo_manifest.package.metadata.binstall.signing.algorithm
                        );
                        eprintln!(
                            "pubkey: {}",
                            cargo_manifest.package.metadata.binstall.signing.pubkey
                        );
                        assert_eq!(
                            cargo_manifest.package.metadata.binstall.signing.algorithm,
                            "minisign"
                        );
                        pubkey = Some(minisign_verify::PublicKey::from_base64(
                            &cargo_manifest.package.metadata.binstall.signing.pubkey,
                        )?);
                    }
                    let pubkey = pubkey.as_ref().unwrap();
                    eprint!("verifying signature for {bin_url} ... ");
                    let allow_legacy = false;
                    pubkey.verify(&buf, &sig, allow_legacy)?;
                    eprintln!("done");
                }
                None => {}
            }

            download_info.insert(platform, ManifestDownloadInfo {
                url: Some(url),
                checksum: hash,
                bin: base_download_info.bin.as_ref().or(base_info.bin.as_ref()).map(|s| {
                    s.map(|s| {
                        replace_vars(
                            s,
                            package,
                            Some(version),
                            Some(platform),
                            base_info.rust_crate.as_deref(),
                        )
                        .unwrap()
                    })
                }),
            });
            buf.clear();
        }
        if download_info.is_empty() {
            eprintln!("no release asset for {package} {version}");
            continue;
        }
        // compact manifest
        // TODO: do this before download binaries
        if download_info.contains_key(&HostPlatform::x86_64_linux_gnu)
            && download_info.contains_key(&HostPlatform::x86_64_linux_musl)
        {
            download_info.remove(&HostPlatform::x86_64_linux_gnu);
        }
        if download_info.contains_key(&HostPlatform::aarch64_linux_gnu)
            && download_info.contains_key(&HostPlatform::aarch64_linux_musl)
        {
            download_info.remove(&HostPlatform::aarch64_linux_gnu);
        }
        if download_info.contains_key(&HostPlatform::x86_64_macos)
            && download_info.contains_key(&HostPlatform::aarch64_macos)
            && download_info[&HostPlatform::x86_64_macos].url
                == download_info[&HostPlatform::aarch64_macos].url
        {
            // macOS universal binary or x86_64 binary that works on both x86_64 and aarch64 (rosetta).
            download_info.remove(&HostPlatform::aarch64_macos);
        }
        has_build_metadata |= !semver_version.build.is_empty();
        if semver_version.pre.is_empty() {
            semver_versions.insert(semver_version.clone());
        }
        manifests.map.insert(
            Reverse(semver_version.clone().into()),
            ManifestRef::Real(Manifest { download_info }),
        );
    }
    if has_build_metadata {
        eprintln!(
            "omitting patch/minor version is not supported yet for package with build metadata"
        );
    } else if !semver_versions.is_empty() {
        let mut prev_version = semver_versions.iter().next().unwrap();
        for version in &semver_versions {
            if let Some(crates_io_info) = &crates_io_info {
                if let Some(v) = crates_io_info.versions.iter().find(|v| v.num == *version) {
                    if v.yanked {
                        continue;
                    }
                }
            }
            if base_info.broken.contains(version) {
                continue;
            }
            if !(version.major == 0 && version.minor == 0) {
                manifests.map.insert(
                    Reverse(Version::omitted(version.major, Some(version.minor))),
                    ManifestRef::Ref { version: version.clone().into() },
                );
            }
            if version.major != 0 {
                manifests
                    .map
                    .insert(Reverse(Version::omitted(version.major, None)), ManifestRef::Ref {
                        version: version.clone().into(),
                    });
            }
            prev_version = version;
        }
        manifests.map.insert(Reverse(Version::latest()), ManifestRef::Ref {
            version: prev_version.clone().into(),
        });
    }

    let ManifestRef::Ref { version: latest_version } =
        manifests.map.first_key_value().unwrap().1.clone()
    else {
        unreachable!()
    };
    if latest_only {
        manifests.map.retain(|k, _| k.0 == Version::latest() || k.0 == latest_version);
    }
    let ManifestRef::Real(latest_manifest) = &manifests.map[&Reverse(latest_version.clone())]
    else {
        unreachable!()
    };
    for &p in base_info.platform.keys() {
        if !manifests
            .map
            .values()
            .any(|m| matches!(m, ManifestRef::Real(m) if m.download_info.contains_key(&p)))
        {
            // TODO: better error message: https://github.com/taiki-e/install-action/pull/411
            bail!(
                "platform list in base manifest for {package} contains {p:?}, \
                 but result manifest doesn't contain it; \
                 consider removing {p:?} from platform list in base manifest"
            );
        }
        if latest_manifest.download_info.contains_key(&p) {
            continue;
        }
        if p == HostPlatform::x86_64_linux_gnu
            && latest_manifest.download_info.contains_key(&HostPlatform::x86_64_linux_musl)
        {
            continue;
        }
        if p == HostPlatform::aarch64_linux_gnu
            && latest_manifest.download_info.contains_key(&HostPlatform::aarch64_linux_musl)
        {
            continue;
        }
        bail!(
            "platform list in base manifest for {package} contains {p:?}, \
             but latest release ({latest_version}) doesn't contain it; \
             consider marking {latest_version} as broken by adding 'broken' field to base manifest"
        );
    }

    let original_manifests = manifests.clone();
    let mut template = Some(ManifestTemplate { download_info: BTreeMap::new() });
    'outer: for (version, manifest) in &mut manifests.map {
        let ManifestRef::Real(manifest) = manifest else {
            continue;
        };
        let version = &*version.0.to_string();
        let t = template.as_mut().unwrap();
        for (platform, d) in &mut manifest.download_info {
            let template_url = d.url.take().unwrap().replace(version, "${version}");
            let template_bin = d.bin.take().map(|s| s.map(|s| s.replace(version, "${version}")));
            if let Some(d) = t.download_info.get(platform) {
                if template_url != d.url || template_bin != d.bin {
                    template = None;
                    break 'outer;
                }
            } else {
                t.download_info.insert(*platform, ManifestTemplateDownloadInfo {
                    url: template_url,
                    bin: template_bin,
                });
            }
        }
    }
    if template.is_none() {
        manifests = original_manifests;
    } else {
        manifests.template = template;
    }

    manifests.rust_crate = base_info.rust_crate;

    let mut buf = serde_json::to_vec_pretty(&manifests)?;
    buf.push(b'\n');
    fs::write(manifest_path, buf)?;

    Ok(())
}

fn workspace_root() -> PathBuf {
    let mut dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    dir.pop(); // codegen
    dir.pop(); // tools
    dir
}

fn replace_vars(
    s: &str,
    package: &str,
    version: Option<&str>,
    platform: Option<HostPlatform>,
    rust_crate: Option<&str>,
) -> Result<String> {
    const RUST_SPECIFIC: &[(&str, fn(HostPlatform) -> &'static str)] = &[
        ("${rust_target}", HostPlatform::rust_target),
        ("${rust_target_arch}", HostPlatform::rust_target_arch),
        ("${rust_target_os}", HostPlatform::rust_target_os),
    ];
    let mut s = s.replace("${package}", package).replace("${tool}", package);
    if let Some(platform) = platform {
        s = s.replace("${exe}", platform.exe_suffix());
        if rust_crate.is_some() {
            for &(var, f) in RUST_SPECIFIC {
                s = s.replace(var, f(platform));
            }
        }
    }
    if let Some(version) = version {
        s = s.replace("${version}", version);
    }
    if s.contains('$') {
        for &(var, _) in RUST_SPECIFIC {
            if s.contains(var) {
                bail!(
                    "base manifest for {package} refers {var}, but 'rust_crate' field is not set"
                );
            }
        }
        bail!("variable not fully replaced: '{s}'");
    }
    Ok(s)
}

fn download(url: &str) -> Result<ureq::Response> {
    let mut token = env::var("GITHUB_TOKEN").ok().filter(|v| !v.is_empty());
    let mut retry = 0;
    let max_retry = 6;
    let mut last_error;
    loop {
        let mut req = ureq::get(url);
        if let Some(token) = &token {
            req = req.set("Authorization", token);
        }
        match req.call() {
            Ok(res) => return Ok(res),
            Err(e) => last_error = Some(e),
        }
        if retry == max_retry / 2 && token.is_some() {
            token = None;
        }
        retry += 1;
        if retry > max_retry {
            break;
        }
        eprintln!("download failed; retrying after {}s ({retry}/{max_retry})", retry * 2);
        std::thread::sleep(Duration::from_secs(retry * 2));
    }
    Err(last_error.unwrap().into())
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Version {
    major: Option<u64>,
    minor: Option<u64>,
    patch: Option<u64>,
    pre: semver::Prerelease,
    build: semver::BuildMetadata,
}

impl Version {
    fn omitted(major: u64, minor: Option<u64>) -> Self {
        Self {
            major: Some(major),
            minor,
            patch: None,
            pre: semver::Prerelease::default(),
            build: semver::BuildMetadata::default(),
        }
    }
    fn latest() -> Self {
        Self {
            major: None,
            minor: None,
            patch: None,
            pre: semver::Prerelease::default(),
            build: semver::BuildMetadata::default(),
        }
    }
    fn to_semver(&self) -> Option<semver::Version> {
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
        fn convert(v: &Version) -> semver::Version {
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
struct Manifests {
    rust_crate: Option<String>,
    template: Option<ManifestTemplate>,
    #[serde(flatten)]
    map: BTreeMap<Reverse<Version>, ManifestRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
enum ManifestRef {
    Ref { version: Version },
    Real(Manifest),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Manifest {
    #[serde(flatten)]
    download_info: BTreeMap<HostPlatform, ManifestDownloadInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ManifestDownloadInfo {
    #[serde(skip_serializing_if = "Option::is_none")]
    url: Option<String>,
    checksum: String,
    /// Path to binaries in archive. Default to `${tool}${exe}`.
    #[serde(skip_serializing_if = "Option::is_none")]
    bin: Option<StringOrArray>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ManifestTemplate {
    #[serde(flatten)]
    download_info: BTreeMap<HostPlatform, ManifestTemplateDownloadInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ManifestTemplateDownloadInfo {
    url: String,
    /// Path to binaries in archive. Default to `${tool}${exe}`.
    #[serde(skip_serializing_if = "Option::is_none")]
    bin: Option<StringOrArray>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct BaseManifest {
    /// Link to the GitHub repository.
    repository: String,
    /// Prefix of release tag.
    tag_prefix: String,
    /// Crate name, if this is Rust crate.
    rust_crate: Option<String>,
    default_major_version: Option<String>,
    /// Asset name patterns.
    asset_name: Option<StringOrArray>,
    /// Path to binaries in archive. Default to `${tool}${exe}`.
    bin: Option<StringOrArray>,
    signing: Option<Signing>,
    #[serde(default)]
    broken: Vec<semver::Version>,
    platform: BTreeMap<HostPlatform, BaseManifestPlatformInfo>,
    version_range: Option<String>,
}
impl BaseManifest {
    fn validate(&self) {
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
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Signing {
    kind: SigningKind,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
#[serde(deny_unknown_fields)]
enum SigningKind {
    /// algorithm: minisign
    /// public key: package.metadata.binstall.signing.pubkey at Cargo.toml
    /// <https://github.com/cargo-bins/cargo-binstall/blob/HEAD/SIGNING.md>
    MinisignBinstall,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct BaseManifestPlatformInfo {
    /// Asset name patterns. Default to the value at `BaseManifest::asset_name`.
    asset_name: Option<StringOrArray>,
    /// Path to binaries in archive. Default to the value at `BaseManifest::bin`.
    bin: Option<StringOrArray>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
enum StringOrArray {
    String(String),
    Array(Vec<String>),
}

impl StringOrArray {
    fn as_slice(&self) -> &[String] {
        match self {
            Self::String(s) => slice::from_ref(s),
            Self::Array(v) => v,
        }
    }
    fn map(&self, mut f: impl FnMut(&String) -> String) -> Self {
        match self {
            Self::String(s) => Self::String(f(s)),
            Self::Array(v) => Self::Array(v.iter().map(f).collect()),
        }
    }
}

/// GitHub Actions Runner supports Linux (x86_64, aarch64, arm), Windows (x86_64, aarch64),
/// and macOS (x86_64, aarch64).
/// https://github.com/actions/runner
/// https://github.com/actions/runner/blob/caec043085990710070108f375cd0aeab45e1017/.github/workflows/build.yml#L21
/// https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners#supported-architectures-and-operating-systems-for-self-hosted-runners
///
/// Note:
/// - Static-linked binaries compiled for linux-musl will also work on linux-gnu systems and are
///   usually preferred over linux-gnu binaries because they can avoid glibc version issues.
///   (rustc enables statically linking for linux-musl by default, except for mips.)
/// - Binaries compiled for x86_64 macOS will usually also work on aarch64 macOS.
/// - Binaries compiled for x86_64 Windows will usually also work on aarch64 Windows 11+.
/// - Ignore arm for now, as we need to consider the version and whether hard-float is supported.
///   https://github.com/rust-lang/rustup/pull/593
///   https://github.com/cross-rs/cross/pull/1018
///   Does it seem only armv7l is supported?
///   https://github.com/actions/runner/blob/caec043085990710070108f375cd0aeab45e1017/src/Misc/externals.sh#L174
#[allow(non_camel_case_types)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
enum HostPlatform {
    x86_64_linux_gnu,
    x86_64_linux_musl,
    x86_64_macos,
    x86_64_windows,
    aarch64_linux_gnu,
    aarch64_linux_musl,
    aarch64_macos,
    aarch64_windows,
}

impl HostPlatform {
    fn rust_target(self) -> &'static str {
        match self {
            Self::x86_64_linux_gnu => "x86_64-unknown-linux-gnu",
            Self::x86_64_linux_musl => "x86_64-unknown-linux-musl",
            Self::x86_64_macos => "x86_64-apple-darwin",
            Self::x86_64_windows => "x86_64-pc-windows-msvc",
            Self::aarch64_linux_gnu => "aarch64-unknown-linux-gnu",
            Self::aarch64_linux_musl => "aarch64-unknown-linux-musl",
            Self::aarch64_macos => "aarch64-apple-darwin",
            Self::aarch64_windows => "aarch64-pc-windows-msvc",
        }
    }
    fn rust_target_arch(self) -> &'static str {
        match self {
            Self::aarch64_linux_gnu
            | Self::aarch64_linux_musl
            | Self::aarch64_macos
            | Self::aarch64_windows => "aarch64",
            Self::x86_64_linux_gnu
            | Self::x86_64_linux_musl
            | Self::x86_64_macos
            | Self::x86_64_windows => "x86_64",
        }
    }
    fn rust_target_os(self) -> &'static str {
        match self {
            Self::aarch64_linux_gnu
            | Self::aarch64_linux_musl
            | Self::x86_64_linux_gnu
            | Self::x86_64_linux_musl => "linux",
            Self::aarch64_macos | Self::x86_64_macos => "macos",
            Self::aarch64_windows | Self::x86_64_windows => "windows",
        }
    }
    fn exe_suffix(self) -> &'static str {
        match self {
            Self::x86_64_windows | Self::aarch64_windows => ".exe",
            _ => "",
        }
    }
}

mod github {
    use serde_derive::Deserialize;

    // https://api.github.com/repos/<repo>/releases
    pub(crate) type Releases = Vec<Release>;

    // https://api.github.com/repos/<repo>/releases/<tag>
    #[derive(Debug, Deserialize)]
    pub(crate) struct Release {
        pub(crate) tag_name: String,
        pub(crate) prerelease: bool,
        pub(crate) assets: Vec<ReleaseAsset>,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct ReleaseAsset {
        pub(crate) name: String,
        // pub(crate) content_type: String,
        pub(crate) browser_download_url: String,
    }
}

mod crates_io {
    use serde_derive::Deserialize;

    // https://crates.io/api/v1/crates/<crate>
    #[derive(Debug, Deserialize)]
    pub(crate) struct Crate {
        pub(crate) versions: Vec<Version>,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct Version {
        pub(crate) checksum: String,
        pub(crate) dl_path: String,
        pub(crate) num: semver::Version,
        pub(crate) yanked: bool,
    }
}

mod cargo_manifest {
    use serde_derive::Deserialize;

    #[derive(Debug, Deserialize)]
    pub(crate) struct Manifest {
        pub(crate) package: Package,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct Package {
        pub(crate) metadata: Metadata,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct Metadata {
        pub(crate) binstall: Binstall,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct Binstall {
        pub(crate) signing: BinstallSigning,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct BinstallSigning {
        pub(crate) algorithm: String,
        pub(crate) pubkey: String,
    }
}
