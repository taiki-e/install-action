// SPDX-License-Identifier: Apache-2.0 OR MIT

use std::{env, fmt, io::Write, path::PathBuf};

use anyhow::Result;
use fs_err as fs;
use install_action_internal_codegen::{workspace_root, BaseManifest, Manifests};

const HEADER: &str = "# Tools

This is a list of tools that are installed from manifests managed in this action.

If a tool not included in the list below is specified, this action uses [cargo-binstall] as a fallback.

> If `$CARGO_HOME/bin` is not available, Rust-related binaries will be installed to `$HOME/.cargo/bin`.<br>
> If `$HOME/.cargo/bin` is not available, Rust-related binaries will be installed to `$HOME/.install-action/bin`.<br>

| Name | Where binaries will be installed | Where will it be installed from | Supported platform | License |
| ---- | -------------------------------- | ------------------------------- | ------------------ | ------- |
";

const FOOTER: &str = "
[cargo-binstall]: https://github.com/cargo-bins/cargo-binstall
";

fn main() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    if !args.is_empty() || args.iter().any(|arg| arg.starts_with('-')) {
        println!(
            "USAGE: cargo run --manifest-path tools/codegen/Cargo.toml --bin generate-tools-markdown --release"
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

    let mut tools = vec![MarkdownEntry {
        name: "valgrind".to_string(),
        alias: None,
        website: "https://valgrind.org/".to_string(),
        installed_to: InstalledTo::Snap,
        installed_from: InstalledFrom::Snap,
        platforms: Platforms { linux: true, ..Default::default() },
        repository: "https://sourceware.org/git/valgrind.git".to_string(),
        license_markdown:
            "[GPL-2.0](https://sourceware.org/git/?p=valgrind.git;a=blob;f=COPYING;hb=HEAD)"
                .to_string(),
    }];

    for path in paths {
        let file_name = path.file_name();
        let mut name = PathBuf::from(file_name.clone());
        name.set_extension("");
        let name = name.to_string_lossy().to_string();
        let base_info: BaseManifest =
            serde_json::from_slice(&fs::read(base_info_dir.join(file_name.clone()))?)?;
        let manifests: Manifests =
            serde_json::from_slice(&fs::read(manifest_dir.join(file_name))?)?;

        let website = match base_info.website {
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

        let readme_entry = MarkdownEntry {
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

    tools.sort_by(|x, y| x.name.cmp(&y.name));

    let mut markdown_file = workspace_root.clone();
    markdown_file.push("TOOLS.md");

    let file = std::fs::File::create(markdown_file).expect("Unable to create file");
    let mut file = std::io::BufWriter::new(file);

    file.write_all(HEADER.as_bytes()).expect("Unable to write header");

    for tool in tools {
        file.write_all(tool.to_string().as_bytes()).expect("Unable to write entry");
    }

    file.write_all(FOOTER.as_bytes()).expect("Unable to write footer");

    Ok(())
}

#[derive(Debug)]
struct MarkdownEntry {
    name: String,
    alias: Option<String>,
    website: String,
    repository: String,
    installed_to: InstalledTo,
    installed_from: InstalledFrom,
    platforms: Platforms,
    license_markdown: String,
}

#[derive(Debug, Eq, PartialEq)]
enum InstalledFrom {
    GitHubRelease,
    Snap,
}

#[derive(Debug, Default, Eq, PartialEq)]
struct Platforms {
    linux: bool,
    macos: bool,
    windows: bool,
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

#[derive(Debug, Eq, PartialEq)]
enum InstalledTo {
    Cargo,
    Snap,
    UsrLocal,
}

impl fmt::Display for InstalledTo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            InstalledTo::Cargo => f.write_str("`$CARGO_HOME/bin`"),
            InstalledTo::Snap => f.write_str("`/snap/bin`"),
            InstalledTo::UsrLocal => f.write_str("`$HOME/.install-action/bin`"),
        }
    }
}

impl fmt::Display for MarkdownEntry {
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
            InstalledFrom::Snap => {
                let markdown =
                    format!("| [snap](https://snapcraft.io/install/{}/ubuntu) ", self.name);
                f.write_str(&markdown)?;
            }
        }

        f.write_str(&format!("| {} ", self.platforms))?;
        f.write_str(&format!("| {} |\n", self.license_markdown))?;
        Ok(())
    }
}
