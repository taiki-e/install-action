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
    echo "info: $*"
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
        cargo-hack | cargo-llvm-cov | cargo-minimal-versions | parse-changelog)
            case "${tool}" in
                # https://github.com/taiki-e/cargo-hack/releases
                cargo-hack) latest_version="0.5.12" ;;
                # https://github.com/taiki-e/cargo-llvm-cov/releases
                cargo-llvm-cov) latest_version="0.2.3" ;;
                # https://github.com/taiki-e/cargo-minimal-versions/releases
                cargo-minimal-versions) latest_version="0.1.3" ;;
                # https://github.com/taiki-e/parse-changelog/releases
                parse-changelog) latest_version="0.4.7" ;;
                *) exit 1 ;;
            esac
            repo="taiki-e/${tool}"
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-musl" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                cygwin* | msys*) target="x86_64-pc-windows-msvc" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/${tool}-${target}.tar.gz"
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C ~/.cargo/bin
            ;;
        cross)
            # https://github.com/cross-rs/cross/releases
            latest_version="0.2.1"
            repo="cross-rs/cross"
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-musl" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                cygwin* | msys*) target="x86_64-pc-windows-msvc" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/cross-v${version}-${target}.tar.gz"
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C ~/.cargo/bin
            ;;
        shellcheck)
            # https://github.com/koalaman/shellcheck/releases
            latest_version="0.8.0"
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
                latest) version="${latest_version}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/shellcheck-v${version}.${target}.x86_64.tar.xz"
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xJf - --strip-components 1 -C /usr/local/bin "shellcheck-v${version}/shellcheck"
            ;;
        shfmt)
            # https://github.com/mvdan/sh/releases
            latest_version="3.4.3"
            repo="mvdan/sh"
            case "${OSTYPE}" in
                linux*) target="linux_amd64" ;;
                darwin*) target="darwin_amd64" ;;
                cygwin* | msys*) bail "${tool} for windows is not supported yet by this action" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/shfmt_v${version}_${target}"
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused -o /usr/local/bin/shfmt "${url}"
            chmod +x /usr/local/bin/shfmt
            ;;
        valgrind)
            case "${OSTYPE}" in
                linux*) ;;
                darwin* | cygwin* | msys*) bail "${tool} for non-linux is not supported yet by this action" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) ;;
                *) warn "specifying the version of ${tool} is not supported yet by this action" ;;
            esac
            retry sudo apt-get -o Acquire::Retries=10 -qq update
            # libc6-dbg is needed to run Valgrind
            retry sudo apt-get -o Acquire::Retries=10 -qq -o Dpkg::Use-Pty=0 install -y libc6-dbg
            # Use snap to install the latest Valgrind
            # https://snapcraft.io/install/valgrind/ubuntu
            retry sudo snap install valgrind --classic
            ;;
        wasm-pack)
            # https://rustwasm.github.io/wasm-pack/installer
            case "${OSTYPE}" in
                linux* | darwin*) ;;
                cygwin* | msys*) bail "${tool} for windows is not supported yet by this action" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused https://rustwasm.github.io/wasm-pack/installer/init.sh | sh
            ;;
        wasmtime)
            # https://github.com/bytecodealliance/wasmtime/releases
            latest_version="0.35.1"
            repo="bytecodealliance/wasmtime"
            case "${OSTYPE}" in
                linux*) target="x86_64-linux" ;;
                darwin*) target="x86_64-macos" ;;
                cygwin* | msys*) bail "${tool} for windows is not supported yet by this action" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            url="https://github.com/bytecodealliance/wasmtime/releases/download/v${version}/wasmtime-v${version}-${target}.tar.xz"
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xJf - --strip-components 1 -C ~/.cargo/bin "wasmtime-v${version}-${target}/wasmtime"
            ;;
        *) bail "unsupported tool '${tool}'" ;;
    esac

    info "${tool} installed at $(type -P "${tool}")"
    case "${tool}" in
        cargo-*) x cargo "${tool#cargo-}" --version ;;
        *) x "${tool}" --version ;;
    esac
    echo
done
