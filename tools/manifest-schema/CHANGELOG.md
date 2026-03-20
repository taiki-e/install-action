# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org).

<!--
Note: In this file, do not use the hard wrap in the middle of a sentence for compatibility with GitHub comment style markdown rendering.
-->

## [Unreleased]

## [0.2.0] - 2026-03-20

- Rename `ManifestDownloadInfo::checksum` field to `hash` to reduce manifest size.

- Make `Version`, `Manifests`, `Manifest`, `ManifestDownloadInfo`, `ManifestTemplate`, `ManifestTemplateDownloadInfo`, and `HostPlatform` `#[non_exhaustive]`.

- Add `Manifest::new`, `ManifestDownloadInfo::new`, and `ManifestTemplateDownloadInfo::new`.

- Implement `Default` for `ManifestTemplate`.

- Remove `BaseManifest` and related types since they are unrelated to public manifests.

## [0.1.1] - 2025-09-20

- Add `HostPlatform::{powerpc64le_linux_gnu,powerpc64le_linux_musl,riscv64_linux_gnu,riscv64_linux_musl,s390x_linux_gnu,s390x_linux_musl}` ([#1133](https://github.com/taiki-e/install-action/pull/1133))

## [0.1.0] - 2025-01-28

Initial release

[Unreleased]: https://github.com/taiki-e/install-action/compare/install-action-manifest-schema-0.1.1...HEAD
[0.1.1]: https://github.com/taiki-e/install-action/compare/install-action-manifest-schema-0.1.0...install-action-manifest-schema-0.1.1
[0.1.0]: https://github.com/taiki-e/install-action/releases/tag/install-action-manifest-schema-0.1.0
