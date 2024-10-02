#!/bin/bash

set -exuo pipefail

cd "$(dirname "$0")"

schema_version="$(grep 'version = "0.*.0"' ./manifest-schema/Cargo.toml | cut -d '.' -f 2)"
branch="manifest-schema-${schema_version}"

git worktree add --force "${1?}"
cd "${1?}"

if git fetch origin "$branch"; then
    git checkout "origin/${branch}" -B "${branch}"
elif ! git checkout "$branch"; then
    # New branch with no history. Credit: https://stackoverflow.com/a/13969482
    git checkout --orphan "${branch}"
    git rm -rf . || true
    git commit -m 'Initial commit' --allow-empty
fi
