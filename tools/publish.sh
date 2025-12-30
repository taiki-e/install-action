#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 's=$?; printf >&2 "%s\n" "${0##*/}:${LINENO}: \`${BASH_COMMAND}\` exit with ${s}"; exit ${s}' ERR
cd -- "$(dirname -- "$0")"/..

# Publish a new release.
#
# USAGE:
#    ./tools/publish.sh <VERSION>
#
# Note: This script requires the following tools:
# - parse-changelog <https://github.com/taiki-e/parse-changelog>

retry() {
  for i in {1..10}; do
    if "$@"; then
      return 0
    else
      sleep "${i}"
    fi
  done
  "$@"
}
bail() {
  printf >&2 'error: %s\n' "$*"
  exit 1
}

version="${1:?}"
version="${version#v}"
tag_prefix="v"
tag="${tag_prefix}${version}"
changelog="CHANGELOG.md"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z\.-]+)?(\+[0-9A-Za-z\.-]+)?$ ]]; then
  bail "invalid version format '${version}'"
fi
if [[ $# -gt 1 ]]; then
  bail "invalid argument '$2'"
fi
if { sed --help 2>&1 || true; } | grep -Eq -e '-i extension'; then
  in_place=(-i '')
else
  in_place=(-i)
fi

# Make sure there is no uncommitted change.
git diff --exit-code
git diff --exit-code --staged

# Make sure the same release has not been created in the past.
if gh release view "${tag}" &>/dev/null; then
  bail "tag '${tag}' has already been created and pushed"
fi

# Make sure that the release was created from an allowed branch.
if ! git branch | grep -Eq '\* main$'; then
  bail "current branch is not 'main'"
fi
if ! git remote -v | grep -F origin | grep -Eq 'github\.com[:/]taiki-e/'; then
  bail "cannot publish a new release from fork repository"
fi

release_date=$(date -u '+%Y-%m-%d')
tags=$(git --no-pager tag | { grep -E "^${tag_prefix}[0-9]+" || true; })
if [[ -n "${tags}" ]]; then
  # Make sure the same release does not exist in changelog.
  if grep -Eq "^## \\[${version//./\\.}\\]" "${changelog}"; then
    bail "release ${version} already exist in ${changelog}"
  fi
  if grep -Eq "^\\[${version//./\\.}\\]: " "${changelog}"; then
    bail "link to ${version} already exist in ${changelog}"
  fi
  # Update changelog.
  remote_url=$(grep -E '^\[Unreleased\]: https://' "${changelog}" | sed -E 's/^\[Unreleased\]: //; s/\.\.\.HEAD$//')
  prev_tag="${remote_url#*/compare/}"
  remote_url="${remote_url%/compare/*}"
  sed -E "${in_place[@]}" \
    -e "s/^## \\[Unreleased\\]/## [Unreleased]\\n\\n## [${version}] - ${release_date}/" \
    -e "s#^\[Unreleased\]: https://.*#[Unreleased]: ${remote_url}/compare/${tag}...HEAD\\n[${version}]: ${remote_url}/compare/${prev_tag}...${tag}#" "${changelog}"
  if ! grep -Eq "^## \\[${version//./\\.}\\] - ${release_date}$" "${changelog}"; then
    bail "failed to update ${changelog}"
  fi
  if ! grep -Eq "^\\[${version//./\\.}\\]: " "${changelog}"; then
    bail "failed to update ${changelog}"
  fi
else
  # Make sure the release exists in changelog.
  if ! grep -Eq "^## \\[${version//./\\.}\\] - ${release_date}$" "${changelog}"; then
    bail "release ${version} does not exist in ${changelog} or has wrong release date"
  fi
  if ! grep -Eq "^\\[${version//./\\.}\\]: " "${changelog}"; then
    bail "link to ${version} does not exist in ${changelog}"
  fi
fi

# Make sure that a valid release note for this version exists.
# https://github.com/taiki-e/parse-changelog
changes=$(parse-changelog "${changelog}" "${version}")
if [[ -z "${changes}" ]]; then
  bail "changelog for ${version} has no body"
fi
printf '============== CHANGELOG ==============\n'
printf '%s\n' "${changes}"
printf '=======================================\n'

if [[ -n "${tags}" ]]; then
  # Create a release commit.
  (
    set -x
    git add "${changelog}"
    git commit -m "Release ${version}"
  )
fi

set -x

git tag "${tag}"
retry git push origin refs/heads/main
retry git push origin refs/tags/"${tag}"

major_version_tag="v${version%%.*}"
git branch "${major_version_tag}"
git tag -f "${major_version_tag}"
refs=("refs/heads/${major_version_tag}" "+refs/tags/${major_version_tag}")

tools=()
for tool in tools/codegen/base/*.json; do
  tool="${tool##*/}"
  tools+=("${tool%.*}")
done
# Aliases.
# NB: Update case for aliases in main.sh and tool input option in test-alias in .github/workflows/ci.yml.
tools+=(
  nextest
  taplo-cli
  typos-cli
  wasm-bindgen-cli
  wasmtime-cli
)
# Non-manifest-based tools.
tools+=(valgrind)

for tool in "${tools[@]}"; do
  git checkout -b "${tool}"
  sed -E "${in_place[@]}" action.yml \
    -e "s/required: true/required: false/g" \
    -e "s/# default: #publish:tool/default: ${tool}/g"
  git add action.yml
  git commit -m "${tool}"
  git tag -f "${tool}"
  git checkout main
  refs+=("+refs/heads/${tool}" "+refs/tags/${tool}")
done
retry git push origin --atomic "${refs[@]}"
git branch -d "${major_version_tag}"
git branch -D "${tools[@]}"

schema_workspace=/tmp/workspace
rm -rf -- "${schema_workspace}"
# Checkout manifest-schema branch
schema_version="$(cargo metadata --format-version=1 --no-deps | jq -r '.packages[] | select(.name == "install-action-manifest-schema") | .version')"
if [[ "${schema_version}" == "0."* ]]; then
  schema_version="0.$(cut -d. -f2 <<<"${schema_version}")"
else
  schema_version="$(cut -d. -f1 <<<"${schema_version}")"
fi
schema_branch="manifest-schema-${schema_version}"

git worktree add --force "${schema_workspace}"
(
  cd -- "${schema_workspace}"
  if git fetch origin "${schema_branch}"; then
    git checkout "origin/${schema_branch}" -B "${schema_branch}"
  elif ! git checkout "${schema_branch}"; then
    # New branch with no history. Credit: https://stackoverflow.com/a/13969482
    git checkout --orphan "${schema_branch}"
    git rm -rf -- . || true
    git commit -m 'Initial commit' --allow-empty
  fi
)

# Copy over schema
cp -- ./manifests/* "${schema_workspace}"

(
  cd -- "${schema_workspace}"
  # Stage changes
  git add .
  # Detect changes, then commit and push if changes exist
  if [[ "$(git status --porcelain=v1 | LC_ALL=C wc -l)" != "0" ]]; then
    git commit -m 'Update manifest schema'
    retry git push origin HEAD
  fi
)

rm -rf -- "${schema_workspace}"
git worktree prune
# TODO: get branch in schema_workspace dir instead
git branch -D "${schema_branch}" "${schema_workspace##*/}"
