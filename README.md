<!-- omit in toc -->
# install-action

[![release](https://img.shields.io/github/release/taiki-e/install-action?style=flat-square&logo=github)](https://github.com/taiki-e/install-action/releases/latest)
[![github actions](https://img.shields.io/github/actions/workflow/status/taiki-e/install-action/ci.yml?branch=main&style=flat-square&logo=github)](https://github.com/taiki-e/install-action/actions)

GitHub Action for installing development tools (mainly from GitHub Releases).

- [Usage](#usage)
  - [Inputs](#inputs)
  - [Example workflow](#example-workflow)
- [Supported tools](#supported-tools)
  - [Add support for new tool](#add-support-for-new-tool)
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

To install the latest version:

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

See [TOOLS.md](TOOLS.md) for the list of tools that are installed from manifests managed in this action.

If a tool not included in the list above is specified, this action uses [cargo-binstall] as a fallback.

If you want to ensure that fallback is not used, use `fallback: none`.

```yaml
- uses: taiki-e/install-action@v2
  with:
    tool: cargo-hack
    # Possible values:
    # - none: disable all fallback
    # - cargo-binstall (default): cargo-binstall (includes quickinstall)
    fallback: none
```

### Add support for new tool

See the [development guide](DEVELOPMENT.md) for how to add support for new tool.

## Security

When installing the tool from GitHub Releases, this action will download the tool or its installer from GitHub Releases using HTTPS with tlsv1.2+. This is basically considered to be the same level of security as [the recommended installation of rustup](https://www.rust-lang.org/tools/install).

Additionally, this action will also verify SHA256 checksums for downloaded files in all tools installed from GitHub Releases. This is enabled by default and can be disabled by setting the `checksum` input option to `false`.

Additionally, we also verify signature if the tool distributes signed archives. Signature verification is done at the stage of getting the checksum, so disabling the checksum will also disable signature verification.

See the linked documentation for information on security when installed using [snap](https://snapcraft.io/docs) or [cargo-binstall](https://github.com/cargo-bins/cargo-binstall#faq).

See the [Supported tools section](#supported-tools) for how to ensure that fallback is not used.

## Compatibility

This action has been tested for GitHub-hosted runners (Ubuntu, macOS, Windows) and containers (Ubuntu, Debian, Fedora, CentOS, Alma, openSUSE, Arch, Alpine).
To use this action in self-hosted runners or in containers, at least the following tools are required:

- bash

## Related Projects

- [cache-cargo-install-action]: GitHub Action for `cargo install` with cache.
- [create-gh-release-action]: GitHub Action for creating GitHub Releases based on changelog.
- [upload-rust-binary-action]: GitHub Action for building and uploading Rust binary to GitHub Releases.
- [setup-cross-toolchain-action]: GitHub Action for setup toolchains for cross compilation and cross testing for Rust.

[cache-cargo-install-action]: https://github.com/taiki-e/cache-cargo-install-action
[cargo-binstall]: https://github.com/cargo-bins/cargo-binstall
[create-gh-release-action]: https://github.com/taiki-e/create-gh-release-action
[setup-cross-toolchain-action]: https://github.com/taiki-e/setup-cross-toolchain-action
[upload-rust-binary-action]: https://github.com/taiki-e/upload-rust-binary-action

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT) at your option.

Each of the tools installed by this action has a different license. See the
[Supported tools](#supported-tools) section for more information.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.
