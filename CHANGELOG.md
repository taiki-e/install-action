# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org).

<!--
Note: In this file, do not use the hard wrap in the middle of a sentence for compatibility with GitHub comment style markdown rendering.
-->

## [Unreleased]

## [1.5.4] - 2022-07-16

- Update `mdbook@latest` to 0.4.20.
- Update `cross@latest` to 0.2.4.
- Update `cargo-minimal-versions@latest` to 0.1.5.
- Update `parse-changelog@latest` to 0.4.9.

## [1.5.3] - 2022-07-07

- Update `cargo-llvm-cov@latest` to 0.4.9.

## [1.5.2] - 2022-07-02

- Update `cross@latest` to 0.2.2.

## [1.5.1] - 2022-07-02

- Update `mdbook@latest` to 0.4.19.

## [1.5.0] - 2022-06-28

- Enable secure mode for `cargo-binstall`. ([#9](https://github.com/taiki-e/install-action/pull/9), thanks @NobodyXu)
- Update `wasmtime@latest` to 0.38.1.

## [1.4.2] - 2022-06-16

- Update `cargo-llvm-cov@latest` to 0.4.8.

## [1.4.1] - 2022-06-13

- Update `cargo-llvm-cov@latest` to 0.4.7.

## [1.4.0] - 2022-06-10

- Support `cargo-binstall`. ([#8](https://github.com/taiki-e/install-action/pull/8), thanks @NobodyXu)
- Use `cargo-binstall` as a fallback if the unsupported package is specified. ([#8](https://github.com/taiki-e/install-action/pull/8), thanks @NobodyXu)
- Update `shfmt@latest` to 3.5.1.

## [1.3.13] - 2022-06-02

- Update `cargo-hack@latest` to 0.5.14.
- Update `cargo-llvm-cov@latest` to 0.4.5.
- Update `cargo-minimal-versions@latest` to 0.1.4.
- Update `parse-changelog@latest` to 0.4.8.

## [1.3.12] - 2022-05-30

- Update `cargo-llvm-cov@latest` to 0.4.4.

## [1.3.11] - 2022-05-29

- Update `cargo-llvm-cov@latest` to 0.4.3.

## [1.3.10] - 2022-05-24

- Update `cargo-llvm-cov@latest` to 0.4.1.

## [1.3.9] - 2022-05-21

- Update `wasmtime@latest` to 0.37.0.

## [1.3.8] - 2022-05-12

- Update `shfmt@latest` to 3.5.0.

## [1.3.7] - 2022-05-12

- Update `cargo-hack@latest` to 0.5.13.
- Update `cargo-llvm-cov@latest` to 0.4.0.

## [1.3.6] - 2022-05-06

- Update `cargo-llvm-cov@latest` to 0.3.3.

## [1.3.5] - 2022-05-05

- Update `cargo-llvm-cov@latest` to 0.3.2.

## [1.3.4] - 2022-05-01

- Update `cargo-llvm-cov@latest` to 0.3.1.

## [1.3.3] - 2022-04-21

- Update `wasmtime@latest` to 0.36.0.

## [1.3.2] - 2022-04-16

- Update `mdbook@latest` to 0.4.18.
- Update `wasmtime@latest` to 0.35.3.

## [1.3.1] - 2022-04-08

- Update `cargo-llvm-cov@latest` to 0.3.0.

## [1.3.0] - 2022-04-04

- Support `mdbook`. ([#4](https://github.com/taiki-e/install-action/pull/4), thanks @thomcc)

## [1.2.2] - 2022-03-18

- Support specifying the version of `nextest`. ([#3](https://github.com/taiki-e/install-action/pull/3), thanks @sunshowers)

## [1.2.1] - 2022-03-18

- Update `cargo-llvm-cov@latest` to 0.2.4.

## [1.2.0] - 2022-03-18

- Support `nextest`.

## [1.1.9] - 2022-03-10

- Update `wasmtime@latest` to 0.35.1.

## [1.1.8] - 2022-03-05

- Update `cargo-llvm-cov@latest` to 0.2.3.

## [1.1.7] - 2022-03-02

- Update `cargo-llvm-cov@latest` to 0.2.2.

## [1.1.6] - 2022-02-20

- Update `cargo-llvm-cov@latest` to 0.2.1.
- Update `shfmt@latest` to 3.4.3.

## [1.1.5] - 2022-02-08

- Update `wasmtime@latest` to 0.34.0.

## [1.1.4] - 2022-02-06

- Update `cargo-llvm-cov@latest` to 0.2.0.

## [1.1.3] - 2022-02-06

- Update `cargo-minimal-versions@latest` to 0.1.3.

## [1.1.2] - 2022-01-21

- Update `cargo-hack@latest` to 0.5.12.
- Update `cargo-llvm-cov@latest` to 0.1.16.
- Update `cargo-minimal-versions@latest` to 0.1.2.
- Update `parse-changelog@latest` to 0.4.7.

## [1.1.1] - 2022-01-21

- Update `cargo-hack@latest` to 0.5.11.

## [1.1.0] - 2022-01-09

- Support `valgrind`, `wasm-pack`, and `wasmtime`.

## [1.0.3] - 2022-01-06

- Update `cargo-llvm-cov@latest` to 0.1.15.

## [1.0.2] - 2022-01-05

- Update `cargo-minimal-versions@latest` to 0.1.1.

## [1.0.1] - 2022-01-05

- Fix error in cases where the release has been created but the binary has not yet been uploaded.

## [1.0.0] - 2021-12-30

Initial release

[Unreleased]: https://github.com/taiki-e/install-action/compare/v1.5.4...HEAD
[1.5.4]: https://github.com/taiki-e/install-action/compare/v1.5.3...v1.5.4
[1.5.3]: https://github.com/taiki-e/install-action/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/taiki-e/install-action/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/taiki-e/install-action/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/taiki-e/install-action/compare/v1.4.2...v1.5.0
[1.4.2]: https://github.com/taiki-e/install-action/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/taiki-e/install-action/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/taiki-e/install-action/compare/v1.3.13...v1.4.0
[1.3.13]: https://github.com/taiki-e/install-action/compare/v1.3.12...v1.3.13
[1.3.12]: https://github.com/taiki-e/install-action/compare/v1.3.11...v1.3.12
[1.3.11]: https://github.com/taiki-e/install-action/compare/v1.3.10...v1.3.11
[1.3.10]: https://github.com/taiki-e/install-action/compare/v1.3.9...v1.3.10
[1.3.9]: https://github.com/taiki-e/install-action/compare/v1.3.8...v1.3.9
[1.3.8]: https://github.com/taiki-e/install-action/compare/v1.3.7...v1.3.8
[1.3.7]: https://github.com/taiki-e/install-action/compare/v1.3.6...v1.3.7
[1.3.6]: https://github.com/taiki-e/install-action/compare/v1.3.5...v1.3.6
[1.3.5]: https://github.com/taiki-e/install-action/compare/v1.3.4...v1.3.5
[1.3.4]: https://github.com/taiki-e/install-action/compare/v1.3.3...v1.3.4
[1.3.3]: https://github.com/taiki-e/install-action/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/taiki-e/install-action/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/taiki-e/install-action/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/taiki-e/install-action/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/taiki-e/install-action/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/taiki-e/install-action/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/taiki-e/install-action/compare/v1.1.9...v1.2.0
[1.1.9]: https://github.com/taiki-e/install-action/compare/v1.1.8...v1.1.9
[1.1.8]: https://github.com/taiki-e/install-action/compare/v1.1.7...v1.1.8
[1.1.7]: https://github.com/taiki-e/install-action/compare/v1.1.6...v1.1.7
[1.1.6]: https://github.com/taiki-e/install-action/compare/v1.1.5...v1.1.6
[1.1.5]: https://github.com/taiki-e/install-action/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/taiki-e/install-action/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/taiki-e/install-action/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/taiki-e/install-action/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/taiki-e/install-action/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/taiki-e/install-action/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/taiki-e/install-action/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/taiki-e/install-action/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/taiki-e/install-action/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/taiki-e/install-action/releases/tag/v1.0.0
