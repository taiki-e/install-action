// SPDX-License-Identifier: Apache-2.0 OR MIT

use std::{
    cmp::Reverse,
    collections::{BTreeMap, BTreeSet},
    env,
    ffi::OsStr,
    io::Read,
    path::Path,
    time::Duration,
};

use anyhow::{bail, Context as _, Result};
use fs_err as fs;
use install_action_internal_codegen::{
    workspace_root, BaseManifest, HostPlatform, Manifest, ManifestDownloadInfo, ManifestRef,
    ManifestTemplate, ManifestTemplateDownloadInfo, Manifests, Signing, SigningKind, Version,
};
use sha2::{Digest, Sha256};
use spdx::expression::{ExprNode, ExpressionReq, Operator};

fn main() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    if args.is_empty() || args.iter().any(|arg| arg.starts_with('-')) {
        println!(
            "USAGE: cargo run --manifest-path tools/codegen/Cargo.toml --release -- <PACKAGE> [VERSION_REQ]"
        );
        std::process::exit(1);
    }
    let package = &args[0];
    let skip_existing_manifest_versions = std::env::var("SKIP_EXISTING_MANIFEST_VERSIONS").is_ok();

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
        .context("repository must start with https://github.com/")?;

    eprintln!("downloading metadata from https://github.com/{repo}");

    let repo_info: github::RepoMetadata =
        download_github(&format!("https://api.github.com/repos/{repo}"))?.into_json()?;

    eprintln!("downloading releases of https://github.com/{repo} from https://api.github.com/repos/{repo}/releases");
    let mut releases: github::Releases = vec![];
    // GitHub API returns up to 100 results at a time. If the number of releases
    // is greater than 100, multiple fetches are needed.
    for page in 1.. {
        let per_page = 100;
        let mut r: github::Releases = download_github(&format!(
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
    let mut crates_io_version_detail = None;
    base_info.rust_crate = base_info
        .rust_crate
        .as_ref()
        .map(|s| replace_vars(s, package, None, None, base_info.rust_crate.as_deref()))
        .transpose()?;
    if let Some(crate_name) = &base_info.rust_crate {
        eprintln!("downloading crate info from https://crates.io/api/v1/crates/{crate_name}");
        let info = download(&format!("https://crates.io/api/v1/crates/{crate_name}"))?
            .into_json::<crates_io::Crate>()?;
        let latest_version = &info.versions[0].num;
        crates_io_version_detail = Some(
            download(&format!("https://crates.io/api/v1/crates/{crate_name}/{latest_version}"))?
                .into_json::<crates_io::VersionMetadata>()?
                .version,
        );

        if let Some(crate_repository) = info.crate_.repository.clone() {
            // cargo-dinghy is fixed at https://github.com/sonos/dinghy/pull/231, but not yet released
            if crate_name != "cargo-dinghy"
                && !crate_repository
                    .to_lowercase()
                    .starts_with(&base_info.repository.to_lowercase())
            {
                panic!("metadata repository {crate_repository} differs from base manifest");
            }
        } else if crate_name != "zola" {
            panic!("crate metadata does not include a repository");
        }

        crates_io_info = Some(info);
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

    // Check website
    if let Some(website) = base_info.website {
        if website.is_empty() || website == base_info.repository {
            panic!("Please do not put the repository in website, or set website to an empty value");
        }
    }

    // Populate license_markdown
    if let Some(license_markdown) = base_info.license_markdown {
        if license_markdown.is_empty() {
            panic!("license_markdown can not be an empty value");
        }
        manifests.license_markdown = license_markdown;
    } else if let Some(detail) = crates_io_version_detail {
        if let Some(license) = detail.license {
            if let Some(license_markdown) =
                get_license_markdown(&license, &repo.to_string(), &repo_info.default_branch)
            {
                manifests.license_markdown = license_markdown;
            }
        }
    } else if let Some(license) = repo_info.license {
        if let Some(license) = license.spdx_id {
            if let Some(license_markdown) =
                get_license_markdown(&license, &repo.to_string(), &repo_info.default_branch)
            {
                manifests.license_markdown = license_markdown;
            }
        }
    }

    if manifests.license_markdown.is_empty() {
        panic!("Unable to determine license_markdown; set manually")
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

        let reverse_semver = Reverse(semver_version.clone().into());

        if skip_existing_manifest_versions && manifests.map.contains_key(&reverse_semver) {
            eprintln!("Skipping {semver_version} already in manifest");
            continue;
        };

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
                download_github(&url)?.into_reader().read_to_end(&mut buf)?;
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
                        let buf = download_github(&url)?.into_string()?;
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
        manifests.map.insert(reverse_semver, ManifestRef::Real(Manifest { download_info }));
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

/// Download using GITHUB_TOKEN.
#[allow(clippy::missing_panics_doc)]
fn download_github(url: &str) -> Result<ureq::Response> {
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

#[allow(clippy::missing_panics_doc)]
pub fn github_head(url: &str) -> Result<()> {
    eprintln!("fetching head of {url} ..");
    let mut token = env::var("GITHUB_TOKEN").ok().filter(|v| !v.is_empty());
    let mut retry = 0;
    let max_retry = 2;
    let mut last_error;
    loop {
        let mut req = ureq::head(url);
        if let Some(token) = &token {
            req = req.set("Authorization", token);
        }
        match req.call() {
            Ok(_) => return Ok(()),
            Err(e) => last_error = Some(e),
        }
        if retry == max_retry / 2 && token.is_some() {
            token = None;
        }
        retry += 1;
        if retry > max_retry {
            break;
        }
        eprintln!("head of {url} failed; retrying after {}s ({retry}/{max_retry})", retry * 2);
        std::thread::sleep(Duration::from_secs(retry * 2));
    }
    Err(last_error.unwrap().into())
}

/// Download without using GITHUB_TOKEN.
#[allow(clippy::missing_panics_doc)]
pub fn download(url: &str) -> Result<ureq::Response> {
    let mut retry = 0;
    let max_retry = 6;
    let mut last_error;
    loop {
        let req = ureq::get(url);
        match req.call() {
            Ok(res) => return Ok(res),
            Err(e) => last_error = Some(e),
        }
        retry += 1;
        if retry > max_retry {
            break;
        }
        eprintln!("download of {url} failed; retrying after {}s ({retry}/{max_retry})", retry * 2);
        std::thread::sleep(Duration::from_secs(retry * 2));
    }
    Err(last_error.unwrap().into())
}

#[must_use]
fn create_github_raw_link(repository: &String, branch: &String, filename: &String) -> String {
    format!("https://raw.githubusercontent.com/{repository}/{branch}/{filename}")
}

#[must_use]
fn create_github_link(repository: &String, branch: &String, filename: &String) -> String {
    format!("https://github.com/{repository}/blob/{branch}/{filename}")
}
#[must_use]
fn get_license_markdown(spdx_expr: &str, repo: &String, default_branch: &String) -> Option<String> {
    // TODO: use https://docs.rs/spdx/latest/spdx/expression/struct.Expression.html#method.canonicalize ?
    let expr = spdx::Expression::parse_mode(spdx_expr, spdx::ParseMode::LAX).unwrap();

    let mut op = None;
    let mut license_ids: Vec<(&spdx::LicenseId, Option<&spdx::ExceptionId>)> = vec![];

    for node in expr.iter() {
        match node {
            ExprNode::Req(ExpressionReq {
                req:
                    spdx::LicenseReq {
                        license: spdx::LicenseItem::Spdx { id, or_later },
                        exception,
                        ..
                    },
                ..
            }) => {
                //eprintln!("{req:?}");
                //panic!();
                if *or_later {
                    panic!("need to handle or_later");
                }
                if let Some(exception_id) = exception {
                    license_ids.push((id, Some(exception_id)));
                } else {
                    license_ids.push((id, None));
                }
            }
            ExprNode::Op(current_op) => {
                if op.is_some() && op != Some(current_op) {
                    panic!("SPDX too complex");
                }
                op = Some(current_op);
            }
            ExprNode::Req(_) => {}
        }
    }

    match license_ids.len() {
        0 => panic!("No licenses"),
        1 => {
            let (license_id, exception_id) = license_ids.first().unwrap();
            let license_name = if let Some(exception_id) = exception_id {
                format!("{} WITH {}", license_id.name, exception_id.name)
            } else {
                license_id.name.to_string()
            };
            let name = license_id.name.split('-').next().unwrap().to_ascii_uppercase();
            for filename in
                ["LICENSE".to_string(), format!("LICENSE-{name}"), "LICENSE.md".to_string()]
            {
                let url = create_github_raw_link(repo, default_branch, &filename);
                if github_head(&url).is_ok() {
                    let url = create_github_link(repo, default_branch, &filename);
                    return Some(format!("[{license_name}]({url})"));
                }
            }
        }
        len => {
            let mut license_markdowns: Vec<String> = vec![];
            for (license_id, exception_id) in &license_ids {
                let name = license_id.name.split('-').next().unwrap().to_ascii_uppercase();
                let filename = format!("LICENSE-{name}");
                let url = create_github_raw_link(repo, default_branch, &filename);
                let license_name = if let Some(exception_id) = exception_id {
                    format!("{} WITH {}", license_id.name, exception_id.name)
                } else {
                    license_id.name.to_string()
                };
                if github_head(&url).is_ok() {
                    let url = create_github_link(repo, default_branch, &filename);
                    license_markdowns.push(format!("[{license_name}]({url})"));
                }
            }
            if license_markdowns.is_empty() {
                panic!("Unable to find any license files in the repo for licenses {license_ids:?}");
            }
            if license_markdowns.len() != len {
                panic!("Unable to find license files in the repo for all licenses {license_ids:?}; found {license_markdowns:?}");
            }
            match op {
                None => panic!("op expected"),
                Some(Operator::Or) => {
                    return Some(license_markdowns.join(" OR "));
                }
                Some(Operator::And) => {
                    return Some(license_markdowns.join(" AND "));
                }
            }
        }
    }
    None
}

mod github {
    use serde_derive::Deserialize;

    // https://api.github.com/repos/<repo>
    #[derive(Debug, Deserialize)]
    pub(crate) struct RepoMetadata {
        #[serde(default)]
        #[allow(dead_code)]
        pub(crate) homepage: Option<String>,
        #[serde(default)]
        pub(crate) license: Option<RepoLicense>,
        pub(crate) default_branch: String,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct RepoLicense {
        #[serde(default)]
        pub(crate) spdx_id: Option<String>,
    }

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
        #[serde(rename = "crate")]
        pub(crate) crate_: CrateMetadata,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct Version {
        pub(crate) checksum: String,
        pub(crate) dl_path: String,
        pub(crate) num: semver::Version,
        pub(crate) yanked: bool,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct CrateMetadata {
        #[allow(dead_code)]
        pub(crate) homepage: Option<String>,
        pub(crate) repository: Option<String>,
    }

    // https://crates.io/api/v1/crates/<crate>/<version>
    #[derive(Debug, Deserialize)]
    pub(crate) struct VersionMetadata {
        pub(crate) version: VersionMetadataDetail,
    }

    #[derive(Debug, Deserialize)]
    pub(crate) struct VersionMetadataDetail {
        pub(crate) license: Option<String>,
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
