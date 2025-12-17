// SPDX-License-Identifier: Apache-2.0 OR MIT

use std::{
    cmp::Reverse,
    collections::{BTreeMap, BTreeSet},
    env,
    ffi::OsStr,
    io::Read as _,
    path::Path,
    sync::{LazyLock, RwLock},
    time::Duration,
};

use anyhow::{Context as _, Result, bail};
use fs_err as fs;
use install_action_internal_codegen::{
    BaseManifest, HostPlatform, Manifest, ManifestDownloadInfo, ManifestRef, ManifestTemplate,
    ManifestTemplateDownloadInfo, Manifests, Signing, SigningKind, Version, workspace_root,
};
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
    let version_req = args.get(1);
    let version_req_given = version_req.is_some();
    let skip_existing_manifest_versions = std::env::var("SKIP_EXISTING_MANIFEST_VERSIONS").is_ok();

    let workspace_root = &workspace_root();
    let manifest_path = &workspace_root.join("manifests").join(format!("{package}.json"));
    let download_cache_dir = &workspace_root.join("tools/codegen/tmp/cache").join(package);
    fs::create_dir_all(manifest_path.parent().unwrap())?;
    fs::create_dir_all(download_cache_dir)?;

    eprintln!("download cache: {}", download_cache_dir.display());

    let mut base_info: BaseManifest = serde_json::from_slice(&fs::read(
        workspace_root.join("tools/codegen/base").join(format!("{package}.json")),
    )?)?;
    base_info.validate();
    let repo = base_info
        .repository
        .strip_prefix("https://github.com/")
        .context("repository must start with https://github.com/")?;

    eprintln!("downloading metadata from {GITHUB_API_START}repos/{repo}");
    let repo_info: github::RepoMetadata =
        download(&format!("{GITHUB_API_START}repos/{repo}"))?.into_json()?;

    eprintln!("downloading releases from {GITHUB_API_START}repos/{repo}/releases");
    let mut releases: github::Releases = vec![];
    // GitHub API returns up to 100 results at a time. If the number of releases
    // is greater than 100, multiple fetches are needed.
    for page in 1.. {
        let per_page = 100;
        let mut r: github::Releases = download(&format!(
            "{GITHUB_API_START}repos/{repo}/releases?per_page={per_page}&page={page}"
        ))?
        .into_json()?;
        // If version_req is latest, it is usually sufficient to look at the latest 100 releases.
        if r.len() < per_page || version_req.is_some_and(|req| req == "latest") {
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
            if !crate_repository.to_lowercase().starts_with(&base_info.repository.to_lowercase()) {
                panic!("repository {crate_repository} from crates.io differs from base manifest");
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
        println!("loading pre-existing manifest {}", manifest_path.display());
        match serde_json::from_slice(&fs::read(manifest_path)?) {
            Ok(m) => {
                manifests = m;
                for (k, manifest) in &mut manifests.map {
                    let ManifestRef::Real(manifest) = manifest else {
                        continue;
                    };
                    let version = &*k.0.to_string();
                    if let Some(template) = &manifests.template {
                        #[allow(clippy::literal_string_with_formatting_args)]
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

    // Populate license_markdown from the base manifest if present.
    if let Some(license_markdown) = base_info.license_markdown {
        if license_markdown.is_empty() {
            panic!("license_markdown can not be an empty value");
        }
        manifests.license_markdown = license_markdown;
    }

    // Check if the license_markdown is valid.
    if !manifests.license_markdown.is_empty() {
        let urls = get_license_markdown_urls(&manifests.license_markdown);
        if urls.is_empty() {
            bail!("Could not find URLs in license_markdown: {}.", manifests.license_markdown);
        }
        for url in urls {
            if let Err(err) = github_head(&url) {
                eprintln!("Failed to fetch pre-existing license_markdown {url}: {err}");
                manifests.license_markdown = String::new();
                break;
            }
        }
    }

    // Try to detect license_markdown from crates.io or GitHub.
    if manifests.license_markdown.is_empty() {
        let license = match (crates_io_version_detail, repo_info.license) {
            (Some(crates_io::VersionMetadataDetail { license: Some(license) }), _) => {
                eprintln!("Trying to verify license '{license}' obtained from crates.io ...");
                license
            }
            (_, Some(github::RepoLicense { spdx_id: Some(spdx_id) })) => {
                eprintln!("Trying to verify license '{spdx_id}' obtained from github.com ...");
                spdx_id
            }
            _ => {
                bail!(
                    "No license SPDX found in crates.io or GitHub metadata.\n\
                    Please set license_markdown in the base manifest"
                );
            }
        };
        if let Some(license_markdown) =
            get_license_markdown(&license, repo, &repo_info.default_branch)
        {
            manifests.license_markdown = license_markdown;
        } else {
            bail!(
                "Unable to verify license file(s) in the repo for license {license}.\n\
                Please set license_markdown in the base manifest"
            );
        }
    }

    let version_req: Option<semver::VersionReq> = match version_req {
        _ if latest_only => {
            let req = format!("={}", releases.first_key_value().unwrap().0.0).parse()?;
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
                    format!("={}", releases.first_key_value().unwrap().0.0).parse()?
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

        let existing_manifest = manifests.map.get(&reverse_semver).cloned();

        if skip_existing_manifest_versions && existing_manifest.is_some() {
            eprintln!("Skipping {semver_version} already in manifest");
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
            let (url, digest, asset_name) = match asset_names.iter().find_map(|asset_name| {
                release
                    .assets
                    .iter()
                    .find(|asset| asset.name == *asset_name)
                    .map(|asset| (asset, asset_name))
            }) {
                Some((asset, asset_name)) => {
                    (asset.browser_download_url.clone(), &asset.digest, asset_name.clone())
                }
                None => {
                    eprintln!("no asset '{asset_names:?}' for host platform '{platform:?}'");
                    continue;
                }
            };

            eprint!("downloading {url} for etag and checksum ... ");
            let download_cache = &download_cache_dir.join(format!(
                "{version}-{platform:?}-{}",
                Path::new(&url).file_name().unwrap().to_str().unwrap()
            ));
            let response = download(&url)?;
            let etag =
                response.header("etag").expect("binary should have an etag").replace('\"', "");

            if let Some(ManifestRef::Real(ref manifest)) = existing_manifest {
                if let Some(entry) = manifest.download_info.get(&platform) {
                    if entry.etag == etag {
                        eprintln!("existing etag matched");
                        download_info.insert(platform, entry.clone());
                        continue;
                    }
                    eprintln!("warn: existing etag no longer valid.");
                } else {
                    eprintln!("existing manifest for {version} is missing platform {platform:?}");
                }
            }

            if download_cache.is_file() {
                eprintln!("already downloaded");
                fs::File::open(download_cache)?.read_to_end(&mut buf)?; // Not buffered because it is read at once.
            } else {
                response.into_reader().read_to_end(&mut buf)?;
                eprintln!("download complete");
                fs::write(download_cache, &buf)?;
            }

            eprintln!("getting sha256 hash for {url}");
            let hash = ring::digest::digest(&ring::digest::SHA256, &buf);
            let hash = format!("{hash:?}").strip_prefix("SHA256:").unwrap().to_owned();
            if let Some(digest) = digest {
                if hash != digest.strip_prefix("sha256:").unwrap() {
                    bail!(
                        "digest mismatch between GitHub release page and actually downloaded file"
                    );
                }
            }
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
                        let hash = ring::digest::digest(&ring::digest::SHA256, &buf2);
                        if format!("{hash:?}").strip_prefix("SHA256:").unwrap() != v.checksum {
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
                        let cargo_manifest = toml::de::from_str::<cargo_manifest::Manifest>(
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
                etag,
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
        if !base_info.prefer_linux_gnu {
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
            if download_info.contains_key(&HostPlatform::powerpc64le_linux_gnu)
                && download_info.contains_key(&HostPlatform::powerpc64le_linux_musl)
            {
                download_info.remove(&HostPlatform::powerpc64le_linux_gnu);
            }
            if download_info.contains_key(&HostPlatform::riscv64_linux_gnu)
                && download_info.contains_key(&HostPlatform::riscv64_linux_musl)
            {
                download_info.remove(&HostPlatform::riscv64_linux_gnu);
            }
            if download_info.contains_key(&HostPlatform::s390x_linux_gnu)
                && download_info.contains_key(&HostPlatform::s390x_linux_musl)
            {
                download_info.remove(&HostPlatform::s390x_linux_gnu);
            }
        }
        if download_info.contains_key(&HostPlatform::x86_64_macos)
            && download_info.contains_key(&HostPlatform::aarch64_macos)
            && download_info[&HostPlatform::x86_64_macos].url
                == download_info[&HostPlatform::aarch64_macos].url
        {
            // macOS universal binary or x86_64 binary that works on both x86_64 and AArch64 (rosetta).
            download_info.remove(&HostPlatform::aarch64_macos);
        }
        if download_info.contains_key(&HostPlatform::x86_64_windows)
            && download_info.contains_key(&HostPlatform::aarch64_windows)
            && download_info[&HostPlatform::x86_64_windows].url
                == download_info[&HostPlatform::aarch64_windows].url
        {
            // x86_64 Windows binary that works on both x86_64 and AArch64.
            download_info.remove(&HostPlatform::aarch64_windows);
        }
        has_build_metadata |= !semver_version.build.is_empty();
        if semver_version.pre.is_empty() {
            semver_versions.insert(semver_version.clone());
        }
        manifests.map.insert(
            reverse_semver,
            ManifestRef::Real(Manifest { previous_stable_version: None, download_info }),
        );

        // update an existing manifests.json to avoid discarding work done in the event of a fetch error.
        if existing_manifest.is_some() && !version_req_given {
            write_manifests(manifest_path, &manifests.clone())?;
            eprintln!("wrote {} with incomplete data", manifest_path.display());
        }
    }
    if base_info.immediate_yank_reflection {
        let mut prev: Option<&Version> = None;
        for (Reverse(v), m) in manifests.map.iter_mut().rev() {
            let ManifestRef::Real(m) = m else { continue };
            if base_info.rust_crate.is_some() {
                m.previous_stable_version = prev.cloned();
            } else {
                m.previous_stable_version = None;
            }
            prev = Some(v);
        }
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
                        continue; // Exclude yanked version from candidate for "latest".
                    }
                } else {
                    continue; // Exclude version not released on crates.io from candidate for "latest".
                }
            }
            if base_info.broken.contains(version) {
                continue; // Exclude version marked as broken from candidate for "latest".
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
        manifests.map.first_key_value().expect("no versions found").1.clone()
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
            bail!(
                "platform list in base manifest for {package} contains {p:?}, \
                 but result manifest doesn't contain it; \
                 consider removing {p:?} from platform list in base manifest"
            );
        }
        if latest_manifest.download_info.contains_key(&p) {
            continue;
        }
        if !base_info.prefer_linux_gnu {
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
            if p == HostPlatform::powerpc64le_linux_gnu
                && latest_manifest.download_info.contains_key(&HostPlatform::powerpc64le_linux_musl)
            {
                continue;
            }
            if p == HostPlatform::riscv64_linux_gnu
                && latest_manifest.download_info.contains_key(&HostPlatform::riscv64_linux_musl)
            {
                continue;
            }
            if p == HostPlatform::s390x_linux_gnu
                && latest_manifest.download_info.contains_key(&HostPlatform::s390x_linux_musl)
            {
                continue;
            }
        }
        if p == HostPlatform::x86_64_macos
            && latest_manifest.download_info.contains_key(&HostPlatform::aarch64_macos)
        {
            // The value of x86_64 macOS binaries has significantly decreased since GitHub Actions
            // deprecated macos-13 runner. While the recently introduced macos-15-intel is available
            // until 2027-08, people aren't paying much attention to it at this time.
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
        #[allow(clippy::literal_string_with_formatting_args)]
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

    write_manifests(manifest_path, &manifests)?;
    eprintln!("wrote {}", manifest_path.display());

    Ok(())
}

fn write_manifests(manifest_path: &Path, manifests: &Manifests) -> Result<()> {
    let mut buf = serde_json::to_vec_pretty(&manifests)?;
    buf.push(b'\n');
    fs::write(manifest_path, buf)?;
    Ok(())
}

#[allow(clippy::literal_string_with_formatting_args)]
fn replace_vars(
    s: &str,
    package: &str,
    version: Option<&str>,
    platform: Option<HostPlatform>,
    rust_crate: Option<&str>,
) -> Result<String> {
    static RUST_SPECIFIC: &[(&str, fn(HostPlatform) -> &'static str)] = &[
        ("${rust_target}", HostPlatform::rust_target),
        ("${rust_target_arch}", HostPlatform::rust_target_arch),
        ("${rust_target_os}", HostPlatform::rust_target_os),
    ];
    // zola is Rust crate, but is not released on crates.io.
    static KNOWN_RUST_CRATE_NOT_IN_CRATES_IO: &[&str] = &["zola"];
    let mut s = s.replace("${package}", package).replace("${tool}", package);
    if let Some(platform) = platform {
        s = s.replace("${exe}", platform.exe_suffix());
        if rust_crate.is_some() || KNOWN_RUST_CRATE_NOT_IN_CRATES_IO.contains(&package) {
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

struct GitHubTokens {
    // In my experience, only api.github.com have severe rate limit.
    // https://api.github.com/
    // Refs: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
    api: RwLock<Option<String>>,
    // https://raw.githubusercontent.com/
    // Refs: https://stackoverflow.com/questions/66522261/does-github-rate-limit-access-to-public-raw-files
    raw: RwLock<Option<String>>,
    // https://github.com/*/*/releases/download/
    other: RwLock<Option<String>>,
}
const GITHUB_API_START: &str = "https://api.github.com/";
const GITHUB_RAW_START: &str = "https://raw.githubusercontent.com/";
impl GitHubTokens {
    fn get(&self, url: &str) -> Option<String> {
        if url.starts_with(GITHUB_RAW_START) {
            self.raw.read().unwrap().clone()
        } else if url.starts_with(GITHUB_API_START) {
            self.api.read().unwrap().clone()
        } else if url.starts_with("https://github.com/") {
            self.other.read().unwrap().clone()
        } else {
            None
        }
    }
    fn clear(&self, url: &str) {
        if url.starts_with(GITHUB_RAW_START) {
            *self.raw.write().unwrap() = None;
        } else if url.starts_with(GITHUB_API_START) {
            *self.api.write().unwrap() = None;
        } else if url.starts_with("https://github.com/") {
            *self.other.write().unwrap() = None;
        }
    }
}
static GITHUB_TOKENS: LazyLock<GitHubTokens> = LazyLock::new(|| {
    let token = env::var("GITHUB_TOKEN").ok().filter(|v| !v.is_empty());
    GitHubTokens {
        raw: RwLock::new(token.clone()),
        api: RwLock::new(token.clone()),
        other: RwLock::new(token),
    }
});

fn download(url: &str) -> Result<ureq::Response> {
    let mut token = GITHUB_TOKENS.get(url);
    let mut retry = 0;
    let mut retry_time = 0;
    let mut max_retry = 6;
    let is_github_api = url.starts_with(GITHUB_API_START);
    if token.is_none() {
        max_retry /= 2;
    }
    let mut last_error;
    loop {
        let mut req = ureq::get(url);
        if let Some(token) = &token {
            req = req.set("Authorization", &format!("Bearer {token}"));
        }
        if is_github_api {
            req = req
                .set("Accept", "application/vnd.github+json")
                .set("X-GitHub-Api-Version", "2022-11-28");
        }
        match req.call() {
            Ok(res) => return Ok(res),
            Err(e) => last_error = Some(e),
        }
        retry_time += 1;
        if token.is_some() && retry == max_retry / 2 {
            retry_time = 0;
            token = None;
            // rate limit
            GITHUB_TOKENS.clear(url);
        }
        retry += 1;
        if retry > max_retry {
            break;
        }
        eprintln!("download failed; retrying after {}s ({retry}/{max_retry})", retry_time * 2);
        std::thread::sleep(Duration::from_secs(retry_time * 2));
    }
    Err(last_error.unwrap().into())
}

fn github_head(url: &str) -> Result<()> {
    eprintln!("fetching head of {url} ..");
    let mut token = GITHUB_TOKENS.get(url);
    let mut retry = 0;
    let mut retry_time = 0;
    let mut max_retry = 2;
    if token.is_none() {
        max_retry /= 2;
    }
    let mut last_error;
    loop {
        let mut req = ureq::head(url);
        if let Some(token) = &token {
            req = req.set("Authorization", &format!("Bearer {token}"));
        }
        match req.call() {
            Ok(_) => return Ok(()),
            // rate limit
            Err(e @ ureq::Error::Status(403, _)) => last_error = Some(e),
            Err(e) => return Err(e.into()),
        }
        retry_time += 1;
        if token.is_some() && retry == max_retry / 2 {
            retry_time = 0;
            token = None;
            GITHUB_TOKENS.clear(url);
        }
        retry += 1;
        if retry > max_retry {
            break;
        }
        eprintln!("head of {url} failed; retrying after {}s ({retry}/{max_retry})", retry_time * 2);
        std::thread::sleep(Duration::from_secs(retry_time * 2));
    }
    Err(last_error.unwrap().into())
}

#[allow(dead_code)]
#[must_use]
fn create_github_raw_link(repository: &str, branch: &str, filename: &str) -> String {
    format!("{GITHUB_RAW_START}{repository}/{branch}/{filename}")
}

/// Create URLs for https://docs.github.com/en/rest/repos/contents
#[must_use]
fn github_content_api_url(repository: &str, branch: &str, filename: &str) -> String {
    format!("{GITHUB_API_START}repos/{repository}/contents/{filename}?ref={branch}")
}

#[must_use]
fn create_github_link(repository: &str, branch: &str, filename: &str) -> String {
    format!("https://github.com/{repository}/blob/{branch}/{filename}")
}
#[must_use]
fn get_license_markdown(spdx_expr: &str, repo: &str, default_branch: &str) -> Option<String> {
    // TODO: use https://docs.rs/spdx/latest/spdx/expression/struct.Expression.html#method.canonicalize ?
    let expr = spdx::Expression::parse_mode(spdx_expr, spdx::ParseMode::LAX).unwrap();

    let mut op = None;
    let mut license_ids: Vec<(&spdx::LicenseId, Option<&spdx::ExceptionId>)> = vec![];

    for node in expr.iter() {
        match node {
            ExprNode::Req(ExpressionReq {
                req:
                    spdx::LicenseReq {
                        license: spdx::LicenseItem::Spdx { id, or_later }, addition, ..
                    },
                ..
            }) => {
                if *or_later {
                    panic!("need to handle or_later");
                }
                if let Some(spdx::AdditionItem::Spdx(exception_id)) = addition {
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
        0 => panic!("No licenses detected in SPDX expression: {expr}"),
        1 => {
            let (license_id, exception_id) = license_ids.first().unwrap();
            let license_name = if let Some(exception_id) = exception_id {
                format!("{} WITH {}", license_id.name, exception_id.name)
            } else {
                license_id.name.to_owned()
            };
            let name = license_id.name.split('-').next().unwrap().to_ascii_uppercase();
            for filename in [
                "LICENSE".to_owned(),
                format!("LICENSE-{name}"),
                "LICENSE.md".to_owned(),
                "COPYING".to_owned(),
            ] {
                let url = github_content_api_url(repo, default_branch, &filename);
                match download(&url) {
                    Ok(_) => {
                        let url = create_github_link(repo, default_branch, &filename);
                        return Some(format!("[{license_name}]({url})"));
                    }
                    Err(e) => {
                        eprintln!("Failed to fetch {url}: {e}");
                    }
                }
            }
        }
        len => {
            let mut license_markdowns: Vec<String> = vec![];
            for (license_id, exception_id) in &license_ids {
                let name = license_id.name.split('-').next().unwrap().to_ascii_uppercase();
                let filename = format!("LICENSE-{name}");
                let url = github_content_api_url(repo, default_branch, &filename);
                let license_name = if let Some(exception_id) = exception_id {
                    format!("{} WITH {}", license_id.name, exception_id.name)
                } else {
                    license_id.name.to_owned()
                };
                match download(&url) {
                    Ok(_) => {
                        let url = create_github_link(repo, default_branch, &filename);
                        license_markdowns.push(format!("[{license_name}]({url})"));
                    }
                    Err(e) => {
                        eprintln!("Failed to fetch {url}: {e}");
                    }
                }
            }
            if license_markdowns.is_empty() {
                panic!("Unable to find any license files in the repo for licenses {license_ids:?}");
            }
            if license_markdowns.len() != len {
                panic!(
                    "Unable to find license files in the repo for all licenses {license_ids:?}; found {license_markdowns:?}"
                );
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

fn get_license_markdown_urls(license_markdown: &str) -> Vec<String> {
    license_markdown
        .split(['(', ')'])
        .filter(|s| s.starts_with("http"))
        .map(|s| s.trim().to_string())
        .collect::<Vec<_>>()
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
        // Note that this field is null if the release is old.
        pub(crate) digest: Option<String>,
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
