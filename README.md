# install-action

[![release](https://img.shields.io/github/release/taiki-e/install-action?style=flat-square&logo=github)](https://github.com/taiki-e/install-action/releases/latest)
[![build status](https://img.shields.io/github/actions/workflow/status/taiki-e/install-action/ci.yml?branch=main&style=flat-square&logo=github)](https://github.com/taiki-e/install-action/actions)

GitHub Action for installing development tools (mainly from GitHub Releases).

- [Usage](#usage)
  - [Inputs](#inputs)
  - [Example workflow](#example-workflow)
- [Supported tools](#supported-tools)
- [Security](#security)
- [Compatibility](#compatibility)
- [Related Projects](#related-projects)
- [License](#license)

## Usage

### Inputs

| Name     | Required | Description                             | Type    | Default |
| -------- |:--------:| --------------------------------------- | ------- | ------- |
| tool     | **true** | Tools to install (comma-separated list) | String  |         |
| checksum | false    | Whether to enable checksums             | Boolean | `true`  |

### Example workflow

```yaml
- uses: taiki-e/install-action@v2
  with:
    tool: cargo-hack
```

You can use the shorthand (if you do not need to pin the versions of this action and the installed tool):

```yaml
- uses: taiki-e/install-action@cargo-hack
```

To install a specific version, use `@version` syntax:

```yaml
- uses: taiki-e/install-action@v2
  with:
    tool: cargo-hack@0.5.24
```

You can also omit patch version.
(You can also omit the minor version if the major version is 1 or greater.)

```yaml
- uses: taiki-e/install-action@v2
  with:
    tool: cargo-hack@0.5
```

To install multiple tools:

```yaml
- uses: taiki-e/install-action@v2
  with:
    tool: cargo-hack,cargo-minimal-versions
```

Or:

```yaml
- uses: taiki-e/install-action@cargo-hack
- uses: taiki-e/install-action@cargo-minimal-versions
```

## Supported tools

<!--
License should use SPDX license identifiers.
https://spdx.org/licenses
-->

| Name | Where binaries will be installed | Where will it be installed from | Supported platform | License |
| ---- | -------------------------------- | ------------------------------- | ------------------ | ------- |
| [**cargo-binstall**][cargo-binstall] | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/cargo-bins/cargo-binstall/releases) | Linux, macOS, Windows | [GPL-3.0](https://github.com/cargo-bins/cargo-binstall/blob/HEAD/crates/bin/LICENSE) |
| [**cargo-deny**](https://github.com/EmbarkStudios/cargo-deny) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/EmbarkStudios/cargo-deny/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/EmbarkStudios/cargo-deny/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/EmbarkStudios/cargo-deny/blob/HEAD/LICENSE-MIT) |
| [**cargo-hack**](https://github.com/taiki-e/cargo-hack) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/taiki-e/cargo-hack/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/taiki-e/cargo-hack/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/taiki-e/cargo-hack/blob/HEAD/LICENSE-MIT) |
| [**cargo-llvm-cov**](https://github.com/taiki-e/cargo-llvm-cov) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/taiki-e/cargo-llvm-cov/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/taiki-e/cargo-llvm-cov/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/taiki-e/cargo-llvm-cov/blob/HEAD/LICENSE-MIT) |
| [**cargo-minimal-versions**](https://github.com/taiki-e/cargo-minimal-versions) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/taiki-e/cargo-minimal-versions/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/taiki-e/cargo-minimal-versions/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/taiki-e/cargo-minimal-versions/blob/HEAD/LICENSE-MIT) |
| [**cargo-udeps**](https://github.com/est31/cargo-udeps) | `$CARGO_HOME/bin` | [GitHub Release](https://github.com/est31/cargo-udeps/releases) | Linux, macOS, Windows | [Apache-2.0 OR MIT](https://github.com/est31/cargo-udeps/blob/master/LICENSE) |
| [**cargo-valgrind**](https://github.com/jfrimmel/cargo-valgrind) | `$CARGO_HOME/bin` | [GitHub Release](https://github.com/jfrimmel/cargo-valgrind/releases) | Linux, macOS, Windows | [MIT](https://github.com/jfrimmel/cargo-valgrind/blob/master/LICENSE-MIT) or [Apache-2.0](https://github.com/jfrimmel/cargo-valgrind/blob/master/LICENSE-APACHE) |
| [**cross**](https://github.com/cross-rs/cross) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/cross-rs/cross/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/cross-rs/cross/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/cross-rs/cross/blob/HEAD/LICENSE-MIT) |
| [**grcov**](https://github.com/mozilla/grcov) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/mozilla/grcov/releases) | Linux, macOS, Windows | [MPL-2.0](https://github.com/mozilla/grcov/blob/master/LICENSE-MPL-2.0) |
| [**just**](https://github.com/casey/just) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/casey/just/releases) | Linux, macOS, Windows | [CC0-1.0](https://github.com/casey/just/blob/HEAD/LICENSE) |
| [**dprint**](https://github.com/dprint/dprint) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/dprint/dprint/releases) | Linux, macOS, Windows | [MIT](https://github.com/dprint/dprint/blob/HEAD/LICENSE) |
| [**mdbook-linkcheck**](https://github.com/Michael-F-Bryan/mdbook-linkcheck) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/Michael-F-Bryan/mdbook-linkcheck/releases) | Linux, macOS, Windows | [MIT](https://github.com/Michael-F-Bryan/mdbook-linkcheck/blob/HEAD/LICENSE) |
| [**mdbook**](https://github.com/rust-lang/mdBook) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/rust-lang/mdBook/releases) | Linux, macOS, Windows | [MPL-2.0](https://github.com/rust-lang/mdBook/blob/HEAD/LICENSE) |
| [**nextest**](https://github.com/nextest-rs/nextest) (alias: `cargo-nextest`) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/nextest-rs/nextest/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/nextest-rs/nextest/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/nextest-rs/nextest/blob/HEAD/LICENSE-MIT) |
| [**parse-changelog**](https://github.com/taiki-e/parse-changelog) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/taiki-e/parse-changelog/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/taiki-e/parse-changelog/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/taiki-e/parse-changelog/blob/HEAD/LICENSE-MIT) |
| [**protoc**](https://github.com/protocolbuffers/protobuf) | `$HOME/.install-action/bin` | [GitHub Releases](https://github.com/protocolbuffers/protobuf/releases) | Linux, macOS, Windows | [BSD-3-Clause](https://github.com/protocolbuffers/protobuf/blob/HEAD/LICENSE) |
| [**shellcheck**](https://www.shellcheck.net) | `/usr/local/bin` | [GitHub Releases](https://github.com/koalaman/shellcheck/releases) | Linux, macOS, Windows | [GPL-3.0-or-later](https://github.com/koalaman/shellcheck/blob/HEAD/LICENSE) |
| [**shfmt**](https://github.com/mvdan/sh) | `/usr/local/bin` | [GitHub Releases](https://github.com/mvdan/sh/releases) | Linux, macOS, Windows | [BSD-3-Clause](https://github.com/mvdan/sh/blob/HEAD/LICENSE) |
| [**valgrind**](https://valgrind.org) | `/snap/bin` | [snap](https://snapcraft.io/install/valgrind/ubuntu) | Linux | [GPL-2.0-or-later](https://valgrind.org/docs/manual/license.gpl.html) |
| [**wasm-pack**](https://github.com/rustwasm/wasm-pack) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/rustwasm/wasm-pack/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/rustwasm/wasm-pack/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/rustwasm/wasm-pack/blob/HEAD/LICENSE-MIT) |
| [**wasmtime**](https://github.com/bytecodealliance/wasmtime) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/bytecodealliance/wasmtime/releases) | Linux, macOS, Windows | [Apache-2.0 WITH LLVM-exception](https://github.com/bytecodealliance/wasmtime/blob/HEAD/LICENSE) |

If `$CARGO_HOME/bin` is not available, Rust-related binaries will be installed to `$HOME/.cargo/bin`.<br>
If `$HOME/.cargo/bin` is not available, Rust-related binaries will be installed to `/usr/local/bin`.<br>
If `/usr/local/bin` is not available, binaries will be installed to `$HOME/.install-action/bin`.<br>

If a tool not included in the list above is specified, this action uses [cargo-binstall] as a fallback.

## Security

When installing the tool from GitHub Releases, this action will download the tool or its installer from GitHub Releases using HTTPS with tlsv1.2+. This is basically considered to be the same level of security as [the recommended installation of rustup](https://www.rust-lang.org/tools/install).

Additionally, this action will also verify SHA256 checksums for downloaded files in all tools installed from GitHub Releases. This is enabled by default and can be disabled by setting the `checksum` input option to `false`.

See the linked documentation for information on security when installed using [snap](https://snapcraft.io/docs) or [cargo-binstall](https://github.com/cargo-bins/cargo-binstall#faq).

## Compatibility

This action has been tested for GitHub-hosted runners (Ubuntu, macOS, Windows) and containers (Ubuntu, Debian, Alpine, Fedora, CentOS, Rocky).
To use this action in self-hosted runners or in containers, you will need to install at least the following:

- bash
- cargo (if you install cargo subcommands or use cargo-binstall fallback)

## Related Projects

- [create-gh-release-action]: GitHub Action for creating GitHub Releases based on changelog.
- [upload-rust-binary-action]: GitHub Action for building and uploading Rust binary to GitHub Releases.
- [setup-cross-toolchain-action]: GitHub Action for setup toolchains for cross compilation and cross testing for Rust.

[cargo-binstall]: https://github.com/cargo-bins/cargo-binstall
[create-gh-release-action]: https://github.com/taiki-e/create-gh-release-action
[setup-cross-toolchain-action]: https://github.com/taiki-e/setup-cross-toolchain-action
[upload-rust-binary-action]: https://github.com/taiki-e/upload-rust-binary-action

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT) at your option.

Each of the tools installed by this action has a different license. See the [Supported tools](#supported-tools) section for more information.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.
