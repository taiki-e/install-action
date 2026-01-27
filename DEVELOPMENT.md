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

## Refresh TOOLS.md

To update `TOOLS.md`, run

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
