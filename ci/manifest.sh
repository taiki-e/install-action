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
        git stash
        old_version=$(jq -r '.latest.version' "${manifest}")
        git stash pop
        new_version=$(jq -r '.latest.version' "${manifest}")
        if [[ "${old_version}" != "${new_version}" ]]; then
            msg="Update \`${name}@latest\` to ${new_version}"
            sed -i "s/^## \\[Unreleased\\]/## [Unreleased]\\n\\n- ${msg}./" CHANGELOG.md
            git add "${manifest}" CHANGELOG.md
        else
            msg="Update ${name} manifest"
            git add "${manifest}"
        fi
        git commit -m "${msg}"
        has_update=1
    fi
done

if [[ -n "${has_update:-}" ]] && [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "success=false" >>"${GITHUB_OUTPUT}"
fi
