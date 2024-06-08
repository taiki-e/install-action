#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/../..

# They don't provide prebuilt binaries for musl or old glibc host.
glibc_pre_2_34_incompat=(
    cargo-cyclonedx
    cargo-spellcheck
    wait-for-them
    xbuild
)
glibc_pre_2_31_incompat=(
    "${glibc_pre_2_34_incompat[@]}"
    cargo-sort
    espup
    zola
)
glibc_pre_2_27_incompat=(
    "${glibc_pre_2_31_incompat[@]}"
    cargo-watch
    mdbook-linkcheck
    protoc
    valgrind
    wasmtime
)
musl_incompat=(
    "${glibc_pre_2_27_incompat[@]}"
    deepsource
)

incompat_tools=()
case "${1:-}" in
    '') version=latest ;;
    major.minor.patch | major.minor | major)
        version="$1"
        # Specifying the version of valgrind and cargo-binstall is not supported.
        incompat_tools+=(valgrind cargo-binstall)
        ;;
    *)
        echo "tool=$1"
        exit 0
        ;;
esac
case "$(uname -s)" in
    Linux)
        host_os=linux
        ldd_version=$(ldd --version 2>&1 || true)
        if grep <<<"${ldd_version}" -q 'musl'; then
            incompat_tools+=("${musl_incompat[@]}")
        else
            host_glibc_version=$(grep <<<"${ldd_version}" -E "GLIBC|GNU libc" | sed "s/.* //g")
            higher_glibc_version=$(sort <<<"2.34"$'\n'"${host_glibc_version}" -Vu | tail -1)
            if [[ "${higher_glibc_version}" != "${host_glibc_version}" ]]; then
                higher_glibc_version=$(sort <<<"2.31"$'\n'"${host_glibc_version}" -Vu | tail -1)
                if [[ "${higher_glibc_version}" != "${host_glibc_version}" ]]; then
                    higher_glibc_version=$(sort <<<"2.27"$'\n'"${host_glibc_version}" -Vu | tail -1)
                    if [[ "${higher_glibc_version}" == "${host_glibc_version}" ]]; then
                        incompat_tools+=("${glibc_pre_2_31_incompat[@]}")
                    else
                        incompat_tools+=("${glibc_pre_2_27_incompat[@]}")
                    fi
                else
                    incompat_tools+=("${glibc_pre_2_34_incompat[@]}")
                fi
            fi
        fi
        if ! type -P snap &>/dev/null; then
            incompat_tools+=(valgrind)
        fi
        ;;
    Darwin) host_os=macos ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT) host_os=windows ;;
    *) bail "unrecognized OS type '$(uname -s)'" ;;
esac

tools=()
for manifest in tools/codegen/base/*.json; do
    tool_name=$(basename "${manifest%.*}")
    # cross -V requires rustc
    if [[ "${tool_name}" == "cross" ]] && ! type -P rustc &>/dev/null; then
        continue
    fi
    case "${host_os}" in
        linux*)
            for incompat in ${incompat_tools[@]+"${incompat_tools[@]}"}; do
                if [[ "${incompat}" == "${tool_name}" ]]; then
                    tool_name=''
                    break
                fi
            done
            ;;
        *)
            if [[ "$(jq -r ".platform.x86_64_${host_os}" "${manifest}")" == "null" ]]; then
                continue
            fi
            ;;
    esac
    if [[ -n "${tool_name}" ]]; then
        if [[ "${version}" != "latest" ]]; then
            latest_version=$(jq -r ".latest.version" "manifests/${tool_name}.json")
            case "${version}" in
                major.minor.patch) tool_name+="@${latest_version}" ;;
                major.minor) tool_name+="@${latest_version%.*}" ;;
                major) tool_name+="@${latest_version%%.*}" ;;
                *) exit 1 ;;
            esac
        fi
        if [[ "${tool_name}" != *"@0" ]] && [[ "${tool_name}" != *"@0.0" ]]; then
            tools+=("${tool_name}")
        fi
    fi
done
if [[ "${version}" != "latest" ]]; then
    tools_tmp=()
    for tool in "${tools[@]}"; do
        tools_tmp+=("${tool}")
    done
    tools=("${tools_tmp[@]}")
fi

# Not manifest-based
case "${host_os}" in
    linux*)
        # Installing snap to container is difficult...
        # Specifying the version of valgrind is not supported.
        if type -P snap &>/dev/null && [[ "${version}" == "latest" ]]; then
            tools+=(valgrind)
        fi
        ;;
esac
# cargo-watch/watchexec-cli is supported by cargo-binstall (through quickinstall)
case "${version}" in
    latest) tools+=(cargo-watch watchexec-cli nextest) ;;
    major.minor.patch) tools+=(cargo-watch@8.1.1 watchexec-cli@1.20.5 nextest@0.9.57) ;;
    major.minor) tools+=(cargo-watch@8.1 watchexec-cli@1.20 nextest@0.9) ;;
    major) tools+=(cargo-watch@8 watchexec-cli@1) ;;
    *) exit 1 ;;
esac

# sort and dedup
IFS=$'\n'
# shellcheck disable=SC2207
tools=($(LC_ALL=C sort -u <<<"${tools[*]}"))
IFS=$'\n\t'

# TODO: inject random space before/after of tool name for testing https://github.com/taiki-e/install-action/issues/115.
IFS=','
echo "tool=${tools[*]}"
IFS=$'\n\t'
