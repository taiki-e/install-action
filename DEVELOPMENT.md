# Development Guide

## Add support for new tool

(Example: [2ba826d](https://github.com/taiki-e/install-action/commit/2ba826d3ded42d6fa480b6bb82810d1282aa3460))

1\. Add base manifest to [`tools/codegen/base`](tools/codegen/base) directory.

See JSON files in `tools/codegen/base` directory for examples of the manifest.

2\. Generate manifest with the following command (replace `<tool>` with the tool name).

```sh
./tools/manifest.sh <tool>
```

> If you're having problem with github api rate limit, you can use your GITHUB_TOKEN to increase the rate limit.
> If you have `Github CLI` installed (the command `gh`), you can:
>
> ```shell
> GITHUB_TOKEN=$(gh auth status --show-token 2>&1 | sed -n 's/^.*Token: \(.*\)$/\1/p') ./tools/manifest.sh <tool>
> ```

3\. Add tool name to the table in ["Supported tools" section in `README.md`](https://github.com/taiki-e/install-action#supported-tools).

## Troubleshooting

If one of the CI builds fails due to a bin path or release asset_name, fix the problem in the base
manifest, and re-run the manifest tool `tools/manifest.sh` to regenerate the manifest json file. The
base manifest supports overriding the bin path per platform by adding the `"bin"` / `"asset_name"`
to the platform object.

If CI fails only for containers using older versions of glibc or musl, you may need to add the tool
name to one of the `*_incompat` arrays in `tools/ci/tool-list.sh`.
