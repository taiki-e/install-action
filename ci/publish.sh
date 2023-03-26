#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: Error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

bail() {
    echo >&2 "error: $*"
    exit 1
}

if [[ -z "${CI:-}" ]]; then
    bail "this script is intended to call from release workflow on CI"
fi
ref="${GITHUB_REF:-}"
if [[ "${ref}" != "refs/tags/"* ]]; then
    bail "tag ref should start with 'refs/tags/'"
fi
tag="${ref#refs/tags/}"

git config user.name "Taiki Endo"
git config user.email "te316e89@gmail.com"

version="${tag}"
version="${version#v}"

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
