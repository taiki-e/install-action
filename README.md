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
| checksum | | Whether to enable checksums (strongly discouraged to disable) | Boolean | `true` |

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

The `@v<major>` and `@<tool_name>` tags are updated with each release. If you want to enhance workflow stability and security against supply chain attacks, consider using the `@v<major>.<minor>.<patch>` tag or their hash to pin the version and regularly updating with [dependency cooldown]. Since all releases are immutable, pinning the version in either way should have the same effect. Pinning `@<tool_name>` tags by hash is strongly discouraged, as it causes the workflow to reference a [commit that is not present on the repository](https://docs.zizmor.sh/audits/#impostor-commit) when a new version is released.

<!-- omit in toc -->
### Security on installation from GitHub Releases

**Tools covered in this section:** Tools in the [supported tools list](TOOLS.md) where column "Where will it be installed from" is "GitHub Releases".

This action will download the tool or its installer from GitHub Releases using HTTPS with tlsv1.2+. This is basically considered to be the same level of security as [the recommended installation of rustup](https://www.rust-lang.org/tools/install).

Additionally, this action will also verify SHA256 checksums for downloaded files for all tools covered in this section. This is enabled by default and can be disabled by setting the `checksum` input option to `false` (strongly discouraged to disable).

Additionally, we also verify [artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations) or signature if the tool publishes artifact attestations or distributes signed archives. Verification is done at the stage of getting the checksum, so disabling the checksum will also disable verification.

When installing with `taiki-e/install-action@<tool_name>`, `tool: <tool_name>`, or `tool: <tool_name>@<omitted_version>`, The tool version is reflects upstream releases with a delay of one to a few days (as with other common package managers that verify checksums or signatures). A delay of at least one day is known as [dependency cooldown] and is intended to mitigate the risk of supply chain attacks (the specific cooldown period may be changed in the future). You can bypass the cooldown by explicitly specifying a version. If you want a longer cooldown, consider using the property described below.

When installing with `tool: <tool_name>` or `tool: <tool_name>@<omitted_version>`, the tool version is associated with the install-action version, so pinning install-action version with the `@v<major>.<minor>.<patch>` tag or their hash also pins the version of the tool being installed. This also means that if a [dependency cooldown] applies to the action itself, a cooldown of one to a few days longer will apply to the tools installed by that action.

[dependency cooldown]: https://blog.yossarian.net/2025/11/21/We-should-all-be-using-dependency-cooldowns

<!-- omit in toc -->
### Security on other installation methods

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

Note that what this action installs for its setup (such as above tools) is considered an implementation detail if they are installed by this action's side, and there is no guarantee that they will be available in subsequent steps, because this action is not an action for installing those tools.

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
