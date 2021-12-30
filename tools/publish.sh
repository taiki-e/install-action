#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Publish a new release.
#
# USAGE:
#    ./tools/publish.sh <VERSION>
#
# NOTE:
# - This script requires parse-changelog <https://github.com/taiki-e/parse-changelog>

cd "$(cd "$(dirname "$0")" && pwd)"/..

bail() {
    echo >&2 "error: $*"
    exit 1
}
warn() {
    echo >&2 "warning: $*"
}
info() {
    echo >&2 "info: $*"
}

tools=(
    cargo-hack
    cargo-llvm-cov
    cargo-minimal-versions
    parse-changelog
    cross
    shellcheck
    shfmt
)

# Parse arguments.
version="${1:?}"
version="${version#v}"
tag="v${version}"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z\.-]+)?(\+[0-9A-Za-z\.-]+)?$ ]]; then
    bail "invalid version format: '${version}'"
fi
if [[ "${2:-}" == "--dry-run" ]]; then
    dry_run="--dry-run"
    shift
fi
if [[ $# -gt 1 ]]; then
    bail "invalid argument: '$2'"
fi

if [[ -z "${dry_run:-}" ]]; then
    git diff --exit-code
    git diff --exit-code --staged
fi

# Make sure that a valid release note for this version exists.
# https://github.com/taiki-e/parse-changelog
echo "============== CHANGELOG =============="
parse-changelog CHANGELOG.md "${version}"
echo "======================================="

# Make sure the same release has not been created in the past.
if gh release view "${tag}" &>/dev/null; then
    bail "tag '${tag}' has already been created and pushed"
fi

# Exit if dry run.
if [[ -n "${dry_run:-}" ]]; then
    warn "skip creating a new tag '${tag}' due to dry run"
    exit 0
fi

info "creating and pushing a new tag '${tag}'"

(
    set -x

    git push origin main
    git tag "${tag}"
    git push origin --tags
    sleep 10

    version_tag=v1
    git checkout -b "${version_tag}"
    git push origin -f refs/heads/"${version_tag}"
    if git --no-pager tag | grep -E "^${version_tag}$" &>/dev/null; then
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
        if git --no-pager tag | grep -E "^${tool}$" &>/dev/null; then
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
