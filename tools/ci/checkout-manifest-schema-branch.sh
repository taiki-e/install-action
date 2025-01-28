#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 's=$?; printf >&2 "%s\n" "${0##*/}:${LINENO}: \`${BASH_COMMAND}\` exit with ${s}"; exit ${s}' ERR
cd -- "$(dirname -- "$0")"

version="$(cargo metadata --format-version=1 --no-deps | jq -r '.packages[] | select(.name == "install-action-manifest-schema") | .version')"
if [[ "${version}" == "0."* ]]; then
  schema_version="0.$(cut -d. -f2 <<<"${version}")"
else
  schema_version="$(cut -d. -f1 <<<"${version}")"
fi
branch="manifest-schema-${schema_version}"

git worktree add --force "${1?}"
cd -- "$1"

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
