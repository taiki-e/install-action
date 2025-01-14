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
retry git push origin main
retry git push origin --tags

major_version_tag="v${version%%.*}"
git checkout -b "${major_version_tag}"
retry git push origin refs/heads/"${major_version_tag}"
if git --no-pager tag | grep -Eq "^${major_version_tag}$"; then
    git tag -d "${major_version_tag}"
    retry git push --delete origin refs/tags/"${major_version_tag}"
fi
git tag "${major_version_tag}"
retry git push origin --tags
git checkout main
git branch -d "${major_version_tag}"

tools=()
for tool in tools/codegen/base/*.json; do
    tool="${tool##*/}"
    tools+=("${tool%.*}")
done
# Alias
tools+=(nextest)
# Not manifest-based
tools+=(valgrind)

for tool in "${tools[@]}"; do
    git checkout -b "${tool}"
    sed -E "${in_place[@]}" "s/required: true/required: false/g" action.yml
    sed -E "${in_place[@]}" "s/# default: #publish:tool/default: ${tool}/g" action.yml
    git add action.yml
    git commit -m "${tool}"
    retry git push origin -f refs/heads/"${tool}"
    if git --no-pager tag | grep -Eq "^${tool}$"; then
        git tag -d "${tool}"
        retry git push --delete origin refs/tags/"${tool}"
    fi
    git tag "${tool}"
    retry git push origin --tags
    git checkout main
    git branch -D "${tool}"
done
