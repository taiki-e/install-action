use anyhow::{bail, Context as _, Result};
use fs_err as fs;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    cmp::Reverse,
    collections::{BTreeMap, BTreeSet},
    env, fmt,
    io::Read,
    path::{Path, PathBuf},
    slice,
    str::FromStr,
    time::Duration,
};

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
    let manifest_path = &workspace_root
        .join("manifests")
        .join(format!("{package}.json"));
    let download_cache_dir = &workspace_root.join("tools/codegen/tmp/cache").join(package);
    fs::create_dir_all(download_cache_dir)?;

    let base_info: BaseManifest = serde_json::from_slice(&fs::read(
        workspace_root
            .join("tools/codegen/base")
            .join(format!("{package}.json")),
    )?)?;
    let repo = base_info
        .repository
        .strip_prefix("https://github.com/")
        .context("repository must be starts with https://github.com/")?;

    eprintln!("downloading releases of https://github.com/{repo}");
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
    let releases: Vec<_> = releases
        .iter()
        .filter_map(|release| {
            release
                .tag_name
                .strip_prefix(&base_info.tag_prefix)
                .map(|version| (version, release))
        })
        .collect();

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
                    let ManifestRef::Real(manifest) = manifest else { continue };
                    let version = &*k.0.to_string();
                    if let Some(template) = &manifests.template {
                        for (platform, d) in &mut manifest.download_info {
                            let template = &template.download_info[platform];
                            d.url = Some(template.url.replace("${version}", version));
                            d.bin_dir = template
                                .bin_dir
                                .as_ref()
                                .map(|s| s.replace("${version}", version));
                            d.bin = template
                                .bin
                                .as_ref()
                                .map(|s| s.replace("${version}", version));
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
            if args.get(1).map(String::as_str) == Some("latest") {
                if let Some(m) = manifests.map.first_key_value() {
                    let version = match m.1 {
                        ManifestRef::Ref { version } => version,
                        ManifestRef::Real(_) => &m.0 .0,
                    };
                    if !manifests.map.is_empty()
                        && *version == releases.first().unwrap().0.parse()?
                    {
                        return Ok(());
                    }
                }
            }
            Some(format!("={}", releases.first().unwrap().0).parse()?)
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
                if manifests.map.is_empty() {
                    format!("={}", releases.first().unwrap().0).parse()?
                } else {
                    format!(">{}", semver_versions.last().unwrap()).parse()?
                }
            } else {
                version_req.parse()?
            };
            eprintln!("update manifest for versions '{req}'");
            Some(req)
        }
    };

    let mut buf = vec![];
    for &(version, release) in &releases {
        let mut semver_version = version.parse::<semver::Version>();
        if semver_version.is_err() {
            if let Some(default_major_version) = &base_info.default_major_version {
                semver_version = format!("{default_major_version}.{version}").parse();
            }
        }
        let Ok(semver_version) = semver_version else {
            continue;
        };
        if let Some(version_req) = &version_req {
            if !version_req.matches(&semver_version) {
                continue;
            }
        }
        let mut download_info = BTreeMap::new();
        for (&platform, base_download_info) in &base_info.platform {
            let asset_names = base_download_info
                .asset_name
                .as_ref()
                .or(base_info.asset_name.as_ref())
                .with_context(|| format!("asset_name is needed for {package} on {platform:?}"))?
                .as_slice()
                .iter()
                .map(|asset_name| replace_vars(asset_name, package, version, platform))
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

            eprintln!("downloading {url} for checksum");
            let download_cache = download_cache_dir.join(format!(
                "{version}-{platform:?}-{}",
                Path::new(&url).file_name().unwrap().to_str().unwrap()
            ));
            if download_cache.is_file() {
                eprintln!("{url} is already downloaded");
                fs::File::open(download_cache)?.read_to_end(&mut buf)?;
            } else {
                download(&url)?.into_reader().read_to_end(&mut buf)?;
                eprintln!("downloaded complete");
                fs::write(download_cache, &buf)?;
            }
            eprintln!("getting sha256 hash for {url}");
            let hash = Sha256::digest(&buf);
            let hash = format!("{hash:x}");
            eprintln!("{hash} *{asset_name}");

            download_info.insert(
                platform,
                ManifestDownloadInfo {
                    url: Some(url),
                    checksum: hash,
                    bin_dir: base_download_info
                        .bin_dir
                        .as_ref()
                        .or(base_info.bin_dir.as_ref())
                        .cloned(),
                    bin: base_download_info
                        .bin
                        .as_ref()
                        .or(base_info.bin.as_ref())
                        .map(|s| replace_vars(s, package, version, platform))
                        .transpose()?,
                },
            );
            buf.clear();
        }
        if download_info.is_empty() {
            eprintln!("no release asset for {package} {version}");
            continue;
        }
        if !base_info.prefer_linux_gnu {
            // compact manifest
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
            if !(version.major == 0 && version.minor == 0) {
                manifests.map.insert(
                    Reverse(Version::omitted(version.major, Some(version.minor))),
                    ManifestRef::Ref {
                        version: version.clone().into(),
                    },
                );
            }
            if version.major != 0 {
                manifests.map.insert(
                    Reverse(Version::omitted(version.major, None)),
                    ManifestRef::Ref {
                        version: version.clone().into(),
                    },
                );
            }
            prev_version = version;
        }
        manifests.map.insert(
            Reverse(Version::latest()),
            ManifestRef::Ref {
                version: prev_version.clone().into(),
            },
        );
    }

    let ManifestRef::Ref { version: latest_version } = manifests.map.first_key_value().unwrap().1.clone() else { unreachable!() };
    if latest_only {
        manifests
            .map
            .retain(|k, _| k.0 == Version::latest() || k.0 == latest_version);
    }
    let ManifestRef::Real(latest_manifest) = &manifests.map[&Reverse(latest_version.clone())] else { unreachable!() };
    for &p in base_info.platform.keys() {
        if latest_manifest.download_info.contains_key(&p) {
            continue;
        }
        if !base_info.prefer_linux_gnu {
            if p == HostPlatform::x86_64_linux_gnu
                && latest_manifest
                    .download_info
                    .contains_key(&HostPlatform::x86_64_linux_musl)
            {
                continue;
            }
            if p == HostPlatform::aarch64_linux_gnu
                && latest_manifest
                    .download_info
                    .contains_key(&HostPlatform::aarch64_linux_musl)
            {
                continue;
            }
        }
        bail!(
            "platform list in base manifest for {package} contains {p:?}, \
             but latest release ({latest_version}) doesn't contain it"
        );
    }

    let original_manifests = manifests.clone();
    let mut template = Some(ManifestTemplate {
        download_info: BTreeMap::new(),
    });
    'outer: for (version, manifest) in &mut manifests.map {
        let ManifestRef::Real(manifest) = manifest else { continue };
        let version = &*version.0.to_string();
        let t = template.as_mut().unwrap();
        for (platform, d) in &mut manifest.download_info {
            let template_url = d.url.take().unwrap().replace(version, "${version}");
            let template_bin_dir = d.bin_dir.take().map(|s| s.replace(version, "${version}"));
            let template_bin = d.bin.take().map(|s| s.replace(version, "${version}"));
            if let Some(d) = t.download_info.get(platform) {
                if template_url != d.url || template_bin_dir != d.bin_dir || template_bin != d.bin {
                    template = None;
                    break 'outer;
                }
            } else {
                t.download_info.insert(
                    *platform,
                    ManifestTemplateDownloadInfo {
                        url: template_url,
                        bin_dir: template_bin_dir,
                        bin: template_bin,
                    },
                );
            }
        }
    }
    if template.is_none() {
        manifests = original_manifests;
    } else {
        manifests.template = template;
    }

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

fn replace_vars(s: &str, package: &str, version: &str, platform: HostPlatform) -> Result<String> {
    let s = s
        .replace("${package}", package)
        .replace("${tool}", package)
        .replace("${rust_target}", platform.rust_target())
        .replace("${version}", version)
        .replace("${exe}", platform.exe_suffix());
    if s.contains('$') {
        bail!("variable not fully replaced: '{s}'");
    }
    Ok(s)
}

fn download(url: &str) -> Result<ureq::Response> {
    let mut token1 = env::var("INTERNAL_CODEGEN_GH_PAT")
        .ok()
        .filter(|v| !v.is_empty());
    let mut token2 = env::var("GITHUB_TOKEN").ok().filter(|v| !v.is_empty());
    let mut retry = 0;
    let mut last_error;
    loop {
        let mut req = ureq::get(url);
        if let Some(token) = &token1 {
            req = req.set("Authorization", token);
        } else if let Some(token) = &token2 {
            req = req.set("Authorization", token);
        }
        match req.call() {
            Ok(res) => return Ok(res),
            Err(e) => last_error = Some(e),
        }
        if token1.is_some() {
            token1 = None;
        } else if token2.is_some() {
            token2 = None;
        }
        retry += 1;
        if retry > 10 {
            break;
        }
        eprintln!("download failed; retrying ({retry}/10)");
        std::thread::sleep(Duration::from_secs(retry * 4));
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
            pre: Default::default(),
            build: Default::default(),
        }
    }
    fn latest() -> Self {
        Self {
            major: None,
            minor: None,
            patch: None,
            pre: Default::default(),
            build: Default::default(),
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
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for Version {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
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
                    pre: Default::default(),
                    build: Default::default(),
                }),
                Err(_e) => Err(e),
            },
        }
    }
}
impl Serialize for Version {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        String::serialize(&self.to_string(), serializer)
    }
}
impl<'de> Deserialize<'de> for Version {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        use serde::de::Error as _;
        String::deserialize(deserializer)?
            .parse()
            .map_err(D::Error::custom)
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct Manifests {
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
    /// Default to ${cargo_bin}
    #[serde(skip_serializing_if = "Option::is_none")]
    bin_dir: Option<String>,
    /// Default to ${tool}${exe}
    #[serde(skip_serializing_if = "Option::is_none")]
    bin: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ManifestTemplate {
    #[serde(flatten)]
    download_info: BTreeMap<HostPlatform, ManifestTemplateDownloadInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ManifestTemplateDownloadInfo {
    url: String,
    /// Default to ${cargo_bin}
    #[serde(skip_serializing_if = "Option::is_none")]
    bin_dir: Option<String>,
    /// Default to ${tool}${exe}
    #[serde(skip_serializing_if = "Option::is_none")]
    bin: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct BaseManifest {
    /// Link to the GitHub repository.
    repository: String,
    /// Prefix of release tag.
    tag_prefix: String,
    default_major_version: Option<String>,
    /// Asset name patterns.
    asset_name: Option<StringOrArray>,
    /// Directory where binary is installed. Default to `${cargo_bin}`.
    bin_dir: Option<String>,
    /// Path to binary in archive. Default to `${tool}${exe}`.
    bin: Option<String>,
    platform: BTreeMap<HostPlatform, BaseManifestPlatformInfo>,
    /// Use glibc build if host_env is gnu.
    #[serde(default)]
    prefer_linux_gnu: bool,
    version_range: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct BaseManifestPlatformInfo {
    /// Asset name patterns. Default to the value at `BaseManifest::asset_name`.
    asset_name: Option<StringOrArray>,
    /// Directory where binary is installed. Default to the value at `BaseManifest::bin_dir`.
    bin_dir: Option<String>,
    /// Path to binary in archive. Default to the value at `BaseManifest::bin`.
    bin: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
enum StringOrArray {
    String(String),
    Array(Vec<String>),
}

impl StringOrArray {
    fn as_slice(&self) -> &[String] {
        match self {
            Self::Array(v) => v,
            Self::String(s) => slice::from_ref(s),
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
    fn exe_suffix(self) -> &'static str {
        match self {
            Self::x86_64_windows | Self::aarch64_windows => ".exe",
            _ => "",
        }
    }
}

mod github {
    use serde::Deserialize;

    // https://api.github.com/repos/<repo>/releases
    pub type Releases = Vec<Release>;

    // https://api.github.com/repos/<repo>/releases/<tag>
    #[derive(Debug, Deserialize)]
    pub struct Release {
        pub tag_name: String,
        pub prerelease: bool,
        pub assets: Vec<ReleaseAsset>,
    }

    #[derive(Debug, Deserialize)]
    pub struct ReleaseAsset {
        pub name: String,
        pub content_type: String,
        pub browser_download_url: String,
    }
}
