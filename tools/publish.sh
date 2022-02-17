#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# Publish a new release.
#
# USAGE:
#    ./tools/publish.sh <VERSION>
#
# Note:
# - This script requires parse-changelog <https://github.com/taiki-e/parse-changelog>

bail() {
    echo >&2 "error: $*"
    exit 1
}

version="${1:?}"
version="${version#v}"
tag="v${version}"
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
if gh release view "${tag}" >/dev/null; then
    bail "tag '${tag}' has already been created and pushed"
fi

# Make sure the same release does not exist in CHANGELOG.md.
release_date=$(date --utc '+%Y-%m-%d')
if grep -Eq "^## \\[${version//./\\.}\\] - ${release_date}$" CHANGELOG.md; then
    bail "release ${version} already exist in CHANGELOG.md"
fi
if grep -Eq "^\\[${version//./\\.}\\]: " CHANGELOG.md; then
    bail "link to ${version} already exist in CHANGELOG.md"
fi

# Update changelog.
remote_url=$(grep -E '^\[Unreleased\]: https://' CHANGELOG.md | sed 's/^\[Unreleased\]: //' | sed 's/\.\.\.HEAD$//')
before_tag=$(sed <<<"${remote_url}" 's/^.*\/compare\///')
remote_url=$(sed <<<"${remote_url}" 's/\/compare\/v.*$//')
sed -i "s/^## \\[Unreleased\\]/## [Unreleased]\\n\\n## [${version}] - ${release_date}/" CHANGELOG.md
sed -i "s#^\[Unreleased\]: https://.*#[Unreleased]: ${remote_url}/compare/v${version}...HEAD\\n[${version}]: ${remote_url}/compare/${before_tag}...v${version}#" CHANGELOG.md
if ! grep -Eq "^## \\[${version//./\\.}\\] - ${release_date}$" CHANGELOG.md; then
    bail "failed to update CHANGELOG.md"
fi
if ! grep -Eq "^\\[${version//./\\.}\\]: " CHANGELOG.md; then
    bail "failed to update CHANGELOG.md"
fi

# Make sure that a valid release note for this version exists.
# https://github.com/taiki-e/parse-changelog
echo "============== CHANGELOG =============="
parse-changelog CHANGELOG.md "${version}"
echo "======================================="

# Create a release commit.
git add CHANGELOG.md
git commit -m "Release ${version}"

tools=(
    cargo-hack
    cargo-llvm-cov
    cargo-minimal-versions
    parse-changelog
    cross
    shellcheck
    shfmt
    valgrind
    wasm-pack
    wasmtime
)

(
    set -x

    git push origin main
    git tag "${tag}"
    git push origin --tags

    version_tag="v${version%%.*}"
    git checkout -b "${version_tag}"
    git push origin refs/heads/"${version_tag}"
    if git --no-pager tag | grep -Eq "^${version_tag}$"; then
        git tag -d "${version_tag}"
        git push --delete origin refs/tags/"${version_tag}"
    fi
    git tag "${version_tag}"
    git checkout main
    git branch -d "${version_tag}"
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
