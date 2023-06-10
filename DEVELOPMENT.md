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

3\. Add tool name to test matrix in `.github/workflows/ci.yml`.

4\. Add tool name to the table in ["Supported tools" section in `README.md`](https://github.com/taiki-e/install-action#supported-tools).
