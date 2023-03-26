# Development Guide

## Add support for new tool

(Example: [2ba826d](https://github.com/taiki-e/install-action/commit/2ba826d3ded42d6fa480b6bb82810d1282aa3460))

1\. Add base manifest to [`tools/codegen/base`](tools/codegen/base) directory.

See JSON files in `tools/codegen/base` directory for examples of the manifest.

2\. Generate manifest with the following command (replace `<tool>` with the tool name).

```sh
./tools/manifest.sh <tool>
```

3\. Add tool name to test matrix in `.github/workflows/ci.yml`.

4\. Add tool name to table in "Supported tools" section in `README.md`.

## Release new version

Note: This is a guide for maintainers.

### Minor version vs patch version

Increase the patch version if only the following changes are included.

- Update the `@latest` version of the tool.

  Rationale: Normally, tool versions are controlled by the `@<version>` syntax, which is explicitly separated from the versioning of the install-action itself.

  Exception: If the major or minor version of the `cargo-binstall` is updated, the minor version should be increased because the behavior of the fallback may change slightly.

- Fix regressions or minor bugs.

  Rationale: Semantic Versioning.

- Improve documentation or diagnostics.

  Rationale: Semantic Versioning.

Increase the minor version otherwise.

### Release instructions

TODO: current release script assumes admin permissions
