#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/../..

bail() {
    echo >&2 "error: $*"
    exit 1
}

if [[ -z "${CI:-}" ]]; then
    bail "this script is intended to call from release workflow on CI"
fi

git config user.name "Taiki Endo"
git config user.email "te316e89@gmail.com"

set -x

for manifest in manifests/*.json; do
    git add -N "${manifest}"
    if ! git diff --exit-code -- "${manifest}"; then
        name=$(basename "${manifest%.*}")
        git stash
        old_version=$(jq -r '.latest.version' "${manifest}")
        git stash pop
        new_version=$(jq -r '.latest.version' "${manifest}")
        if [[ "${old_version}" != "${new_version}" ]]; then
            # TODO: If there is a line about updating the same tool in the "Unreleased" section, replace it.
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
