#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 's=$?; printf >&2 "%s\n" "${0##*/}:${LINENO}: \`${BASH_COMMAND}\` exit with ${s}"; exit ${s}' ERR
cd -- "$(dirname -- "$0")"/../..

bail() {
  printf >&2 'error: %s\n' "$*"
  exit 1
}

if [[ -z "${CI:-}" ]]; then
  bail "this script is intended to call from release workflow on CI"
fi

git config user.name 'Taiki Endo'
git config user.email 'te316e89@gmail.com'

set -x

has_update=''
for manifest in manifests/*.json; do
  git add -N "${manifest}"
  if ! git diff --exit-code -- "${manifest}"; then
    name="${manifest##*/}"
    name="${name%.*}"
    git stash
    old_version=$(jq -r '.latest.version' "${manifest}")
    git stash pop
    new_version=$(jq -r '.latest.version' "${manifest}")
    if [[ "${old_version}" != "${new_version}" ]]; then
      # TODO: If there is a line about updating the same tool in the "Unreleased" section, replace it.
      msg="Update \`${name}@latest\` to ${new_version}"
      sed -Ei "s/^## \\[Unreleased\\]/## [Unreleased]\\n\\n- ${msg}./" CHANGELOG.md
      git add "${manifest}" CHANGELOG.md
    else
      msg="Update ${name} manifest"
      git add "${manifest}"
    fi
    git commit -m "${msg}"
    has_update=1
  fi
done

if [[ -n "${has_update}" ]] && [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'success=false\n' >>"${GITHUB_OUTPUT}"
fi
