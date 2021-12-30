#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

x() {
    local cmd="$1"
    shift
    (
        set -x
        "${cmd}" "$@"
    )
}
retry() {
    for i in {1..5}; do
        if "$@"; then
            return 0
        else
            sleep "${i}"
        fi
    done
    "$@"
}
bail() {
    echo "::error::$*"
    exit 1
}
warn() {
    echo "::warning::$*"
}
info() {
    echo >&2 "info: $*"
}

if [[ $# -gt 0 ]]; then
    bail "invalid argument '$1'"
fi

export DEBIAN_FRONTEND=noninteractive

# Inputs
tool="${INPUT_TOOL:-}"

tools=()
if [[ -n "${tool}" ]]; then
    while read -rd,; do tools+=("${REPLY}"); done <<<"${tool},"
fi

for tool in "${tools[@]}"; do
    if [[ "${tool}" == *"@"* ]]; then
        version="${tool#*@}"
    else
        version="latest"
    fi
    tool="${tool%@*}"
    info "installing ${tool}@${version}"
    case "${tool}" in
        # https://github.com/taiki-e/cargo-hack/releases
        # https://github.com/taiki-e/cargo-llvm-cov/releases
        # https://github.com/taiki-e/cargo-minimal-versions/releases
        # https://github.com/taiki-e/parse-changelog/releases
        cargo-hack | cargo-llvm-cov | cargo-minimal-versions | parse-changelog)
            repo="taiki-e/${tool}"
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-musl" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                cygwin* | msys*) target="x86_64-pc-windows-msvc" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) url="https://github.com/${repo}/releases/latest/download/${tool}-${target}.tar.gz" ;;
                *) url="https://github.com/${repo}/releases/download/v${version}/${tool}-${target}.tar.gz" ;;
            esac
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C ~/.cargo/bin
            ;;
        # https://github.com/rust-embedded/cross/releases
        cross)
            repo="rust-embedded/cross"
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-musl" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                cygwin* | msys*) target="x86_64-pc-windows-msvc" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) tag=$(retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://api.github.com/repos/${repo}/releases/latest | jq -r '.tag_name') ;;
                *) tag="v${version}" ;;
            esac
            url="https://github.com/${repo}/releases/download/${tag}/cross-${tag}-${target}.tar.gz"
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C ~/.cargo/bin
            ;;
        # https://github.com/koalaman/shellcheck/releases
        shellcheck)
            repo="koalaman/shellcheck"
            case "${OSTYPE}" in
                linux*)
                    if type -P shellcheck &>/dev/null; then
                        sudo apt-get -qq -o Dpkg::Use-Pty=0 remove -y shellcheck
                    fi
                    target="linux"
                    ;;
                darwin*) target="darwin" ;;
                cygwin* | msys*) bail "${tool} for windows is not supported yet by this action" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) tag="$(retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://api.github.com/repos/${repo}/releases/latest | jq -r '.tag_name')" ;;
                *) tag="v${version}" ;;
            esac
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://github.com/${repo}/releases/download/${tag}/shellcheck-${tag}.${target}.x86_64.tar.xz" \
                | tar xJf - --strip-components 1 -C /usr/local/bin "shellcheck-${tag}/shellcheck"
            ;;
        # https://github.com/mvdan/sh/releases
        shfmt)
            repo="mvdan/sh"
            case "${OSTYPE}" in
                linux*) target="linux_amd64" ;;
                darwin*) target="darwin_amd64" ;;
                cygwin* | msys*) bail "${tool} for windows is not supported yet by this action" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) tag="$(retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://api.github.com/repos/${repo}/releases/latest | jq -r '.tag_name')" ;;
                *) tag="v${version}" ;;
            esac
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused -o /usr/local/bin/shfmt "https://github.com/${repo}/releases/download/${tag}/shfmt_${tag}_${target}"
            chmod +x /usr/local/bin/shfmt
            ;;
        *) bail "unsupported tool '${tool}'" ;;
    esac

    info "${tool} installed at $(type -P "${tool}")"
    case "${tool}" in
        cargo-*) x cargo "${tool#cargo-}" --version ;;
        *) x "${tool}" --version ;;
    esac
    echo >&2
done
