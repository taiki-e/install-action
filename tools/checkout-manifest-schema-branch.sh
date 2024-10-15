#!/bin/bash

set -exuo pipefail

cd "$(dirname "$0")"

schema_version="$(cargo metadata --format-version=1 --no-deps | jq -r '.packages[] | select(.name == "install-action-manifest-schema") | .version')"
branch="manifest-schema-${schema_version}"

git worktree add --force "${1?}"
cd "$1"

if git fetch origin "${branch}"; then
    git checkout "origin/${branch}" -B "${branch}"
elif ! git checkout "${branch}"; then
    # New branch with no history. Credit: https://stackoverflow.com/a/13969482
    git checkout --orphan "${branch}"
    git rm -rf . || true
    git config --local user.name github-actions
    git config --local user.email github-actions@github.com
    git commit -m 'Initial commit' --allow-empty
fi
