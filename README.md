# install-action

[![build status](https://img.shields.io/github/workflow/status/taiki-e/install-action/CI/main?style=flat-square&logo=github)](https://github.com/taiki-e/install-action/actions)

GitHub Action for installing development tools (mainly from GitHub Releases).

- [Usage](#usage)
  - [Inputs](#inputs)
  - [Example workflow](#example-workflow)
- [Supported tools](#supported-tools)
- [Security](#security)
- [Related Projects](#related-projects)
- [License](#license)

## Usage

### Inputs

| Name | Required | Description | Type | Default |
| ---- |:--------:| ----------- | ---- | ------- |
| tool | **true** | Tools to install (comma-separated list) | String | |

### Example workflow

```yaml
- uses: taiki-e/install-action@v1
  with:
    tool: cargo-hack
```

You can use the shorthand (if you do not need to pin the versions of this action and the installed tool):

```yaml
- uses: taiki-e/install-action@cargo-hack
```

To install a specific version, use `@version` syntax:

```yaml
- uses: taiki-e/install-action@v1
  with:
    tool: cargo-hack@0.5.15
```

To install multiple tools:

```yaml
- uses: taiki-e/install-action@v1
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
| [**cargo-hack**](https://github.com/taiki-e/cargo-hack) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/taiki-e/cargo-hack/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/taiki-e/cargo-hack/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/taiki-e/cargo-hack/blob/HEAD/LICENSE-MIT) |
| [**cargo-llvm-cov**](https://github.com/taiki-e/cargo-llvm-cov) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/taiki-e/cargo-llvm-cov/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/taiki-e/cargo-llvm-cov/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/taiki-e/cargo-llvm-cov/blob/HEAD/LICENSE-MIT) |
| [**cargo-minimal-versions**](https://github.com/taiki-e/cargo-minimal-versions) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/taiki-e/cargo-minimal-versions/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/taiki-e/cargo-minimal-versions/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/taiki-e/cargo-minimal-versions/blob/HEAD/LICENSE-MIT) |
| [**parse-changelog**](https://github.com/taiki-e/parse-changelog) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/taiki-e/parse-changelog/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/taiki-e/parse-changelog/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/taiki-e/parse-changelog/blob/HEAD/LICENSE-MIT) |
| [**cross**](https://github.com/cross-rs/cross) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/cross-rs/cross/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/cross-rs/cross/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/cross-rs/cross/blob/HEAD/LICENSE-MIT) |
| [**nextest**](https://github.com/nextest-rs/nextest) (alias: `cargo-nextest`) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/nextest-rs/nextest/releases) | Linux, macOS, Windows | [Apache-2.0](https://github.com/nextest-rs/nextest/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/nextest-rs/nextest/blob/HEAD/LICENSE-MIT) |
| [**shellcheck**](https://www.shellcheck.net) | `/usr/local/bin` | [GitHub Releases](https://github.com/koalaman/shellcheck/releases) | Linux, macOS | [GPL-3.0-or-later](https://github.com/koalaman/shellcheck/blob/HEAD/LICENSE) |
| [**shfmt**](https://github.com/mvdan/sh) | `/usr/local/bin` | [GitHub Releases](https://github.com/mvdan/sh/releases) | Linux, macOS | [BSD-3-Clause](https://github.com/mvdan/sh/blob/HEAD/LICENSE) |
| [**valgrind**](https://valgrind.org) | `/snap/bin` | [snap](https://snapcraft.io/install/valgrind/ubuntu) | Linux | [GPL-2.0-or-later](https://valgrind.org/docs/manual/license.gpl.html) |
| [**wasm-pack**](https://github.com/rustwasm/wasm-pack) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/rustwasm/wasm-pack/releases) | Linux, macOS | [Apache-2.0](https://github.com/rustwasm/wasm-pack/blob/HEAD/LICENSE-APACHE) OR [MIT](https://github.com/rustwasm/wasm-pack/blob/HEAD/LICENSE-MIT) |
| [**wasmtime**](https://github.com/bytecodealliance/wasmtime) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/bytecodealliance/wasmtime/releases) | Linux, macOS, Windows | [Apache-2.0 WITH LLVM-exception](https://github.com/bytecodealliance/wasmtime/blob/HEAD/LICENSE) |
| [**mdbook**](https://github.com/rust-lang/mdBook) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/rust-lang/mdBook/releases) | Linux, macOS, Windows | [MPL-2.0](https://github.com/rust-lang/mdBook/blob/HEAD/LICENSE) |
| [**mdbook-linkcheck**](https://github.com/Michael-F-Bryan/mdbook-linkcheck) | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/Michael-F-Bryan/mdbook-linkcheck/releases) | Linux, macOS, Windows | [MIT](https://github.com/Michael-F-Bryan/mdbook-linkcheck/blob/HEAD/LICENSE) |
| [**cargo-binstall**][cargo-binstall] | `$CARGO_HOME/bin` | [GitHub Releases](https://github.com/ryankurte/cargo-binstall/releases) | Linux, macOS, Windows | [GPL-3.0](https://github.com/ryankurte/cargo-binstall/blob/HEAD/LICENSE.txt) |

If `$CARGO_HOME/bin` is not available, Rust-related binaries will be installed to `$HOME/.cargo/bin`.
If `$HOME/.cargo/bin` is not available, Rust-related binaries will be installed to `/usr/local/bin`.

If a tool not included in the list above is specified, this action uses [cargo-binstall] as a fallback.

<!-- TODO:
| [**cmake**](https://cmake.org) | | [GitHub Releases](https://github.com/Kitware/CMake/releases) | Linux, macOS, Windows | [BSD-3-Clause](https://github.com/Kitware/CMake/blob/HEAD/Copyright.txt) |
-->

## Security

When installing the tool from GitHub Releases, this action will download the tool or its installer from GitHub Releases using HTTPS with tlsv1.2+. This is basically considered to be the same level of security as [the recommended installation of rustup](https://www.rust-lang.org/tools/install).

If you want a higher level of security, consider working on [#1](https://github.com/taiki-e/install-action/issues/1).

## Related Projects

- [create-gh-release-action]: GitHub Action for creating GitHub Releases based on changelog.
- [upload-rust-binary-action]: GitHub Action for building and uploading Rust binary to GitHub Releases.
- [setup-cross-toolchain-action]: GitHub Action for setup toolchains for cross compilation and cross testing for Rust.

[cargo-binstall]: https://github.com/ryankurte/cargo-binstall
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
