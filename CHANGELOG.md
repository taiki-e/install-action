# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org).

<!--
Note: In this file, do not use the hard wrap in the middle of a sentence for compatibility with GitHub comment style markdown rendering.
-->

## [Unreleased]

## [1.14.5] - 2022-11-27

- Update `wasmtime@latest` to 3.0.0.
- Update `cargo-binstall@latest` to 0.17.0.

## [1.14.4] - 2022-11-04

- Update `cargo-udeps@latest` to 0.1.35.

## [1.14.3] - 2022-10-28

- Update `wasmtime@latest` to 2.0.1.
- Update `protoc@latest` to 3.21.9.

## [1.14.2] - 2022-10-25

- Update `cargo-hack@latest` to 0.5.22.
- Update `cargo-minimal-versions@latest` to 0.1.7.
- Update `parse-changelog@latest` to 0.5.2.

## [1.14.1] - 2022-10-21

- Update `wasmtime@latest` to 2.0.0.
- Update `protoc@latest` to 3.21.8.

## [1.14.0] - 2022-10-18

- Update `protoc@latest` to 3.21.7.
- Update `cargo-binstall@latest` to 0.16.0. ([#28](https://github.com/taiki-e/install-action/pull/28), thanks @NobodyXu)
- Reject semver operators in version. This was not supported even before, but was accidentally accepted in the `cargo-binstall` fallback. ([#26](https://github.com/taiki-e/install-action/pull/26), thanks @NobodyXu)

## [1.13.9] - 2022-09-28

- Update `cargo-binstall@latest` to 0.14.0. ([#24](https://github.com/taiki-e/install-action/pull/24), thanks @coltfred)

## [1.13.8] - 2022-09-26

- Update `cargo-hack@latest` to 0.5.21.

## [1.13.7] - 2022-09-25

- Work around cargo-binstall upgrade issue on Windows. ([#23](https://github.com/taiki-e/install-action/pull/23))
- Ensure that the latest cargo-binstall is used. ([#22](https://github.com/taiki-e/install-action/pull/22), thanks @NobodyXu)

## [1.13.6] - 2022-09-25

- Update `cargo-binstall@latest` to 0.13.3.

## [1.13.5] - 2022-09-24

- Update `cargo-hack@latest` to 0.5.20.
- Downgrade `cargo-binstall@latest` to 0.13.1 to avoid [upstream bug](https://github.com/cargo-bins/cargo-binstall/issues/416).

## [1.13.4] - 2022-09-22

- Update `cargo-hack@latest` to 0.5.19.

## [1.13.3] - 2022-09-20

- Update `wasmtime@latest` to 1.0.0.

## [1.13.2] - 2022-09-16

- Update `cargo-udeps@latest` to 0.1.33.

## [1.13.1] - 2022-09-15

- Update `protoc@latest` to 3.21.6.

## [1.13.0] - 2022-09-10

- Avoid using sudo on `protoc` installation.

## [1.12.4] - 2022-09-10

- Update `cargo-llvm-cov@latest` to 0.5.0.

## [1.12.3] - 2022-09-08

- Update `parse-changelog@latest` to 0.5.1.

## [1.12.2] - 2022-09-04

- Update `cargo-hack@latest` to 0.5.18.

## [1.12.1] - 2022-09-01

- Update `wasmtime@latest` to 0.40.1.

## [1.12.0] - 2022-08-28

- Support `cargo-valgrind`. ([#20](https://github.com/taiki-e/install-action/pull/20), thanks @messense)

## [1.11.2] - 2022-08-23

- Update `wasmtime@latest` to 0.40.0.
- Update `cargo-udeps@latest` to 0.1.32.
- Update `protoc@latest` to 3.21.5.

## [1.11.1] - 2022-08-13

- Make installation that uses `cargo-binstall` robust. ([#19](https://github.com/taiki-e/install-action/pull/19), thanks @NobodyXu)

## [1.11.0] - 2022-08-13

- Update `cargo-hack@latest` to 0.5.17.
- Support `cargo-udeps`. ([#17](https://github.com/taiki-e/install-action/pull/17), thanks @gifnksm)

## [1.10.4] - 2022-08-06

- Update `cargo-llvm-cov@latest` to 0.4.14.

## [1.10.3] - 2022-08-01

- Support `wasm-pack` on Windows.

- Support specifying the version of `wasm-pack`.

## [1.10.2] - 2022-08-01

- Support `protoc` on Windows.

## [1.10.1] - 2022-08-01

- Fix missing include files when installing `protoc` on Linux and macOS.

- Installation of `protoc` on Windows is not currently working (in all released versions) and is considered unsupported.

## [1.10.0] - 2022-08-01

- Set the `PROTOC` environment variable when installing `protoc` if it has not already been set.

## [1.9.0] - 2022-08-01

- Support `protoc`.
- Support `shellcheck` on Windows.
- Support `shfmt` on Windows.

## [1.8.4] - 2022-08-01

- Update `cargo-llvm-cov@latest` to 0.4.13.

## [1.8.3] - 2022-07-30

- Support `taiki-e/install-action@mdbook-linkcheck` shorthand for mdbook-linkcheck.

## [1.8.2] - 2022-07-30

- Update `cargo-hack@latest` to 0.5.16.
- Update `cargo-llvm-cov@latest` to 0.4.12.

## [1.8.1] - 2022-07-26

- Fix `cargo-binstall` installation failure.

## [1.8.0] - 2022-07-26

- Only use musl binaries for nextest if glibc isn't available. See [#13](https://github.com/taiki-e/install-action/issues/13) for more.

- Fix `cargo-binstall` installation failure. ([#16](https://github.com/taiki-e/install-action/pull/16), thanks @CAD97)

- Accept `cargo-nextest` as an alias for `nextest`. ([#15](https://github.com/taiki-e/install-action/pull/15), thanks @CAD97)

## [1.7.0] - 2022-07-25

- Install Rust-related binaries to `/usr/local/bin` when `$CARGO_HOME/bin` and `$HOME/.cargo/bin` is not available.

## [1.6.1] - 2022-07-25

- Fix diagnostics.

## [1.6.0] - 2022-07-25

- Support `mdbook-linkcheck`.
- Support `mdbook` on Windows.
- Support `wasmtime` on Windows.
- Support `nextest` on Linux (musl).
- Fix installation failure when `$CARGO_HOME/bin` and `$HOME/.cargo/bin` is not available.

## [1.5.11] - 2022-07-25

- Fix `cargo-binstall` installation on macOS and Windows.

## [1.5.10] - 2022-07-24

- Update `parse-changelog@latest` to 0.5.0.

## [1.5.9] - 2022-07-22

- Update `wasmtime@latest` to 0.39.1.
- Update `mdbook@latest` to 0.4.21.

## [1.5.8] - 2022-07-21

- Update `wasmtime@latest` to 0.39.0.

## [1.5.7] - 2022-07-20

- Update `cargo-llvm-cov@latest` to 0.4.11.

## [1.5.6] - 2022-07-18

- Update `cargo-llvm-cov@latest` to 0.4.10.

## [1.5.5] - 2022-07-18

- Update `cargo-hack@latest` to 0.5.15.

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

[Unreleased]: https://github.com/taiki-e/install-action/compare/v1.14.5...HEAD
[1.14.5]: https://github.com/taiki-e/install-action/compare/v1.14.4...v1.14.5
[1.14.4]: https://github.com/taiki-e/install-action/compare/v1.14.3...v1.14.4
[1.14.3]: https://github.com/taiki-e/install-action/compare/v1.14.2...v1.14.3
[1.14.2]: https://github.com/taiki-e/install-action/compare/v1.14.1...v1.14.2
[1.14.1]: https://github.com/taiki-e/install-action/compare/v1.14.0...v1.14.1
[1.14.0]: https://github.com/taiki-e/install-action/compare/v1.13.9...v1.14.0
[1.13.9]: https://github.com/taiki-e/install-action/compare/v1.13.8...v1.13.9
[1.13.8]: https://github.com/taiki-e/install-action/compare/v1.13.7...v1.13.8
[1.13.7]: https://github.com/taiki-e/install-action/compare/v1.13.6...v1.13.7
[1.13.6]: https://github.com/taiki-e/install-action/compare/v1.13.5...v1.13.6
[1.13.5]: https://github.com/taiki-e/install-action/compare/v1.13.4...v1.13.5
[1.13.4]: https://github.com/taiki-e/install-action/compare/v1.13.3...v1.13.4
[1.13.3]: https://github.com/taiki-e/install-action/compare/v1.13.2...v1.13.3
[1.13.2]: https://github.com/taiki-e/install-action/compare/v1.13.1...v1.13.2
[1.13.1]: https://github.com/taiki-e/install-action/compare/v1.13.0...v1.13.1
[1.13.0]: https://github.com/taiki-e/install-action/compare/v1.12.4...v1.13.0
[1.12.4]: https://github.com/taiki-e/install-action/compare/v1.12.3...v1.12.4
[1.12.3]: https://github.com/taiki-e/install-action/compare/v1.12.2...v1.12.3
[1.12.2]: https://github.com/taiki-e/install-action/compare/v1.12.1...v1.12.2
[1.12.1]: https://github.com/taiki-e/install-action/compare/v1.12.0...v1.12.1
[1.12.0]: https://github.com/taiki-e/install-action/compare/v1.11.2...v1.12.0
[1.11.2]: https://github.com/taiki-e/install-action/compare/v1.11.1...v1.11.2
[1.11.1]: https://github.com/taiki-e/install-action/compare/v1.11.0...v1.11.1
[1.11.0]: https://github.com/taiki-e/install-action/compare/v1.10.4...v1.11.0
[1.10.4]: https://github.com/taiki-e/install-action/compare/v1.10.3...v1.10.4
[1.10.3]: https://github.com/taiki-e/install-action/compare/v1.10.2...v1.10.3
[1.10.2]: https://github.com/taiki-e/install-action/compare/v1.10.1...v1.10.2
[1.10.1]: https://github.com/taiki-e/install-action/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/taiki-e/install-action/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/taiki-e/install-action/compare/v1.8.4...v1.9.0
[1.8.4]: https://github.com/taiki-e/install-action/compare/v1.8.3...v1.8.4
[1.8.3]: https://github.com/taiki-e/install-action/compare/v1.8.2...v1.8.3
[1.8.2]: https://github.com/taiki-e/install-action/compare/v1.8.1...v1.8.2
[1.8.1]: https://github.com/taiki-e/install-action/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/taiki-e/install-action/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/taiki-e/install-action/compare/v1.6.1...v1.7.0
[1.6.1]: https://github.com/taiki-e/install-action/compare/v1.6.0...v1.6.1
[1.6.0]: https://github.com/taiki-e/install-action/compare/v1.5.11...v1.6.0
[1.5.11]: https://github.com/taiki-e/install-action/compare/v1.5.10...v1.5.11
[1.5.10]: https://github.com/taiki-e/install-action/compare/v1.5.9...v1.5.10
[1.5.9]: https://github.com/taiki-e/install-action/compare/v1.5.8...v1.5.9
[1.5.8]: https://github.com/taiki-e/install-action/compare/v1.5.7...v1.5.8
[1.5.7]: https://github.com/taiki-e/install-action/compare/v1.5.6...v1.5.7
[1.5.6]: https://github.com/taiki-e/install-action/compare/v1.5.5...v1.5.6
[1.5.5]: https://github.com/taiki-e/install-action/compare/v1.5.4...v1.5.5
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
