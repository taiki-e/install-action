// SPDX-License-Identifier: Apache-2.0 OR MIT

use std::{env, fmt, path::PathBuf};

use anyhow::Result;
use fs_err as fs;
use install_action_internal_codegen::{workspace_root, BaseManifest, Manifests};

fn main() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    if !args.is_empty() || args.iter().any(|arg| arg.starts_with('-')) {
        println!(
            "USAGE: cargo run --manifest-path tools/codegen/Cargo.toml --bin generate-readme --release"
        );
        std::process::exit(1);
    }

    let workspace_root = workspace_root();

    let mut manifest_dir = workspace_root.clone();
    manifest_dir.push("manifests");
    let mut base_info_dir = workspace_root.clone();
    base_info_dir.push("tools");
    base_info_dir.push("codegen");
    base_info_dir.push("base");

    let mut paths: Vec<_> =
        fs::read_dir(manifest_dir.clone()).unwrap().map(|r| r.unwrap()).collect();
    paths.sort_by_key(fs_err::DirEntry::path);

    let mut tools = vec![
        ReadmeEntry {
            name: "nextest".to_string(),
            alias: "cargo-nextest".to_string().into(),
            website: "https://nexte.st/".to_string(),
            installed_to: InstalledTo::Cargo,
            installed_from: InstalledFrom::Binstall,
            platforms: Platforms::all(),
            repository: "https://github.com/nextest-rs/nextest".to_string(),
            license_markdown: "[Apache-2.0](https://github.com/nextest-rs/nextest/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/nextest-rs/nextest/blob/HEAD/LICENSE-MIT)".to_string()
        },
        ReadmeEntry {
            name: "valgrind".to_string(),
            alias: None,
            website: "https://nexte.st/".to_string(),
            installed_to: InstalledTo::Snap,
            installed_from: InstalledFrom::Snap,
            platforms: Platforms {
                linux: true,
                ..Default::default()
            },
            repository: "https://github.com/nextest-rs/nextest".to_string(),
            license_markdown: "[Apache-2.0](https://github.com/nextest-rs/nextest/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/nextest-rs/nextest/blob/HEAD/LICENSE-MIT)".to_string()
        }
    ];

    for path in paths {
        let file_name = path.file_name();
        let mut name = PathBuf::from(file_name.clone());
        name.set_extension("");
        let name = name.to_string_lossy().to_string();
        let base_info: BaseManifest =
            serde_json::from_slice(&fs::read(base_info_dir.join(file_name.clone()))?)?;
        let manifests: Manifests =
            serde_json::from_slice(&fs::read(manifest_dir.join(file_name))?)?;

        let website = match manifests.website {
            Some(website) => website,
            None => base_info.repository.clone(),
        };

        let repository = base_info.repository;

        let installed_to =
            if manifests.rust_crate.is_some() { InstalledTo::Cargo } else { InstalledTo::UsrLocal };

        let installed_from = InstalledFrom::GitHubRelease;
        let mut platforms = Platforms::default();

        for platform in base_info.platform.keys() {
            match platform.rust_target_os() {
                "linux" => platforms.linux = true,
                "macos" => platforms.macos = true,
                "windows" => platforms.windows = true,
                &_ => todo!(),
            }
        }

        let license_markdown = manifests.license_markdown;

        let readme_entry = ReadmeEntry {
            name,
            website,
            repository,
            installed_to,
            installed_from,
            platforms,
            license_markdown,
            alias: None,
        };
        tools.push(readme_entry);
    }

    println!("# Tools");
    println!();
    println!("| Name | Where binaries will be installed | Where will it be installed from | Supported platform | License |");
    println!("| ---- | -------------------------------- | ------------------------------- | ------------------ | ------- |");

    tools.sort();

    for tool in tools {
        println!("{tool}");
    }

    Ok(())
}

#[derive(Debug, Eq, Ord, PartialEq, PartialOrd)]
struct ReadmeEntry {
    name: String,
    alias: Option<String>,
    website: String,
    repository: String,
    installed_to: InstalledTo,
    installed_from: InstalledFrom,
    platforms: Platforms,
    license_markdown: String,
}

#[derive(Debug, Eq, Ord, PartialEq, PartialOrd)]
enum InstalledFrom {
    Binstall,
    GitHubRelease,
    Snap,
}

#[derive(Debug, Default, Eq, PartialEq, Ord, PartialOrd)]
struct Platforms {
    linux: bool,
    macos: bool,
    windows: bool,
}
impl Platforms {
    fn all() -> Self {
        Self { linux: true, macos: true, windows: true }
    }
}

impl fmt::Display for Platforms {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut platform_names: Vec<&str> = vec![];
        if self.linux {
            platform_names.push("Linux");
        }
        if self.macos {
            platform_names.push("macOS");
        }
        if self.windows {
            platform_names.push("Windows");
        }
        let name = platform_names.join(", ");
        f.write_str(&name)?;
        Ok(())
    }
}

#[derive(Debug, Eq, Ord, PartialEq, PartialOrd)]
enum InstalledTo {
    Cargo,
    Snap,
    UsrLocal,
}

impl fmt::Display for InstalledTo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            InstalledTo::Cargo => f.write_str("`$CARGO_HOME/bin`")?,
            InstalledTo::Snap => f.write_str("`/snap/bin`")?,
            InstalledTo::UsrLocal => f.write_str("`/usr/local/bin`")?,
        }

        Ok(())
    }
}

impl fmt::Display for ReadmeEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = format!("| [**{}**]({}) ", self.name, self.website);
        f.write_str(&name)?;

        if let Some(alias) = self.alias.clone() {
            let alias = format!("(alias: `{alias}`)");
            f.write_str(&alias)?;
        }

        f.write_str(&format!("| {} ", self.installed_to))?;

        match self.installed_from {
            InstalledFrom::GitHubRelease => {
                let markdown = format!("| [GitHub Releases]({}/releases) ", self.repository);
                f.write_str(&markdown)?;
            }
            InstalledFrom::Binstall => f.write_str("cargo-binstall")?,
            InstalledFrom::Snap => {
                let markdown =
                    format!("| [snap](https://snapcraft.io/install/{}/ubuntu) ", self.name);
                f.write_str(&markdown)?;
            }
        }

        f.write_str(&format!("| {} ", self.platforms))?;
        f.write_str(&format!("| {} |", self.license_markdown))?;
        Ok(())
    }
}
