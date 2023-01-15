#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: Error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# Publish a new release.
#
# USAGE:
#    ./tools/publish.sh <VERSION>
#
# Note: This script requires the following tools:
# - parse-changelog <https://github.com/taiki-e/parse-changelog>

bail() {
    echo >&2 "error: $*"
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

# Make sure there is no uncommitted change.
git diff --exit-code
git diff --exit-code --staged

# Make sure the same release has not been created in the past.
if gh release view "${tag}" &>/dev/null; then
    bail "tag '${tag}' has already been created and pushed"
fi

if ! git branch | grep -q '\* main$'; then
    bail "current branch is not 'main'"
fi

release_date=$(date -u '+%Y-%m-%d')
tags=$(git --no-pager tag | (grep -E "^${tag_prefix}[0-9]+" || true))
if [[ -n "${tags}" ]]; then
    # Make sure the same release does not exist in changelog.
    if grep -Eq "^## \\[${version//./\\.}\\]" "${changelog}"; then
        bail "release ${version} already exist in ${changelog}"
    fi
    if grep -Eq "^\\[${version//./\\.}\\]: " "${changelog}"; then
        bail "link to ${version} already exist in ${changelog}"
    fi
    # Update changelog.
    remote_url=$(grep -E '^\[Unreleased\]: https://' "${changelog}" | sed 's/^\[Unreleased\]: //; s/\.\.\.HEAD$//')
    before_tag="${remote_url#*/compare/}"
    remote_url="${remote_url%/compare/*}"
    sed -i "s/^## \\[Unreleased\\]/## [Unreleased]\\n\\n## [${version}] - ${release_date}/" "${changelog}"
    sed -i "s#^\[Unreleased\]: https://.*#[Unreleased]: ${remote_url}/compare/${tag}...HEAD\\n[${version}]: ${remote_url}/compare/${before_tag}...${tag}#" "${changelog}"
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
echo "============== CHANGELOG =============="
echo "${changes}"
echo "======================================="

if [[ -n "${tags}" ]]; then
    # Create a release commit.
    git add "${changelog}"
    git commit -m "Release ${version}"
fi

tools=()
for tool in tools/codegen/base/*.json; do
    tools+=("$(basename "${tool%.*}")")
done
# Aliases
tools+=(nextest)
# Not manifest-base
tools+=(valgrind)

(
    set -x

    git tag "${tag}"
    git push origin main
    git push origin --tags

    major_version_tag="v${version%%.*}"
    git checkout -b "${major_version_tag}"
    git push origin refs/heads/"${major_version_tag}"
    if git --no-pager tag | grep -Eq "^${major_version_tag}$"; then
        git tag -d "${major_version_tag}"
        git push --delete origin refs/tags/"${major_version_tag}"
    fi
    git tag "${major_version_tag}"
    git checkout main
    git branch -d "${major_version_tag}"
)

for tool in "${tools[@]}"; do
    (
        set -x
        git checkout -b "${tool}"
        sed -i -e "s/required: true/required: false/g" action.yml
        sed -i -e "s/# default: #publish:tool/default: ${tool}/g" action.yml
        git add action.yml
        git commit -m "${tool}"
        git push origin -f refs/heads/"${tool}"
        if git --no-pager tag | grep -Eq "^${tool}$"; then
            git tag -d "${tool}"
            git push --delete origin refs/tags/"${tool}"
        fi
        git tag "${tool}"
        git checkout main
        git branch -D "${tool}"
    )
done

set -x

git push origin --tags
