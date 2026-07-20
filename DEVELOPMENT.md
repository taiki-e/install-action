# Development Guide

## Add support for new tool

(Example: [ffbd316](https://github.com/taiki-e/install-action/commit/ffbd316e0fe98cb460dae3a66cd2ef9deb398bb1))

1\. Add base manifest to [`tools/codegen/base`](tools/codegen/base) directory.

See JSON files in `tools/codegen/base` directory for examples of the manifest.

2\. Generate manifest with the following command (replace `<tool>` with the tool name).

```sh
./tools/manifest.sh <tool>
```

> If you're having problem with github api rate limit, you can use your GITHUB_TOKEN to increase the rate limit.
> If you have `Github CLI` installed (the command `gh`), you can:
>
> ```sh
> GITHUB_TOKEN=$(gh auth token) ./tools/manifest.sh <tool>
> ```

3\. Update `TOOLS.md` with the following command.

```sh
./tools/update-markdown.sh
```

## Troubleshooting

If one of the CI builds fails due to a bin path or release asset_name, fix the problem in the base
manifest, and re-run the manifest tool `tools/manifest.sh` to regenerate the manifest json file. The
base manifest supports overriding the bin path per platform by adding the `"bin"` / `"asset_name"`
to the platform object.

If CI fails only for containers using older versions of glibc or musl, you may need to add the tool
name to one of the `*_incompat` arrays in `tools/ci/tool-list.sh`.

If the `Manifest / manifest / gen` job in CI fails due to outdated manifests for other tools,
please ignore it and do not modify the manifest for any tools other than the one you are currently
working on. That should be handled by the automation, and if everything else passes, your PR is okay.

## Release new version

Releases are performed by running the [release workflow](https://github.com/taiki-e/install-action/actions/workflows/release.yml) via workflow dispatch. The owner and collaborators can start the release workflow, but the owner's [approval](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments#required-reviewers) is required before the actual release.

### Minor version vs patch version

Increase the patch version if only the following changes are included.

- Update the `@latest` version of the tool.

  Rationale: Normally, tool versions are controlled by the `@<version>` syntax, which is explicitly separated from the versioning of the install-action itself.

  Exception: If the major or minor version of the `cargo-binstall` is updated, the minor version may be increased because the behavior of the fallback may change slightly.

- Fix regressions or minor bugs.

  Rationale: Semantic Versioning.

- Improve documentation or diagnostics.

  Rationale: Semantic Versioning.

Usually increase the minor version otherwise.

Adding support for a new tool may conflict with existing fallbacks, so it is necessary to increase the minor version.
