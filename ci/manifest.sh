#!/bin/bash
set -euxo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

git config user.name "Taiki Endo"
git config user.email "te316e89@gmail.com"

for manifest in manifests/*.json; do
    git add -N "${manifest}"
    if ! git diff --exit-code -- "${manifest}"; then
        name="$(basename "${manifest%.*}")"
        git add "${manifest}"
        git commit -m "Update ${name}"
        has_update=1
    fi
done

if [[ -n "${has_update:-}" ]]; then
    echo "success=false" >>"${GITHUB_OUTPUT}"
fi
