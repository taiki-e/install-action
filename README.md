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

| Name | Required | Description | Type | Default |
| ---- | :------: | ----------- | ---- | ------- |
| tool | **✓** | Tools to install (whitespace or comma separated list) | String | |
| checksum | | Whether to enable checksums | Boolean | `true` |

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
    # - none: disable all fallback options
    # - cargo-binstall (default): use cargo-binstall (includes "quickinstall" and "install from source")
    # - cargo-install: use `cargo install`
    fallback: none
```

On platforms where cargo-binstall does not provide prebuilt binaries, cargo-install fallback is used instead of cargo-binstall fallback.

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

On Linux, if any required tools are missing, this action will attempt to install them from distro's package manager, so no pre-setup is usually required (except for CentOS or Debian 10 (or older) or very old distro described below, which was already EoL and needs to use vault/archive repos -- see "Install requirements" in [our CI config](https://github.com/taiki-e/install-action/blob/HEAD/.github/workflows/ci.yml) for example of setup).

On other platforms, at least the following tools are required:

- bash 3.2+
- jq 1.3+ (only on non-Windows platforms)
- curl 7.34+ (or RHEL7/CentOS7's patched curl 7.29)

Known environments affected by the above version requirements are CentOS 6 (EoL on 2020-11) using curl 7.19, and Ubuntu 12.04 (EoL on 2017-04) using curl 7.22 (see "Install requirements" in [our CI config](https://github.com/taiki-e/install-action/blob/HEAD/.github/workflows/ci.yml) for example of workaround).

## Related Projects

- [cache-cargo-install-action]: GitHub Action for `cargo install` with cache.
- [create-gh-release-action]: GitHub Action for creating GitHub Releases based on changelog.
- [upload-rust-binary-action]: GitHub Action for building and uploading Rust binary to GitHub Releases.
- [setup-cross-toolchain-action]: GitHub Action for setup toolchains for cross compilation and cross testing for Rust.
- [checkout-action]: GitHub Action for checking out a repository. (Simplified actions/checkout alternative that does not depend on Node.js.)

[cache-cargo-install-action]: https://github.com/taiki-e/cache-cargo-install-action
[cargo-binstall]: https://github.com/cargo-bins/cargo-binstall
[checkout-action]: https://github.com/taiki-e/checkout-action
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
