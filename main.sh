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
install_cargo_binstall() {
    cargo_bin="${CARGO_HOME:-$HOME/.cargo}/bin"

    if [[ ! -f "${cargo_bin}/cargo-binstall" ]]; then
        info "installing cargo-binstall"

        target="$(rustc -vV | grep host | cut -c 7-)"
        base_url=https://github.com/ryankurte/cargo-binstall/releases/latest/download/cargo-binstall
        is_zip=false
        case "${target}" in
            x86_64-unknown-linux-gnu) url="${base_url}-x86_64-unknown-linux-musl.tgz" ;;
            x86_64-unknown-linux-musl) url="${base_url}-x86_64-unknown-linux-musl.tgz" ;;

            armv7-unknown-linux-gnueabihf) url="${base_url}-armv7-unknown-linux-musleabihf.tgz" ;;
            armv7-unknown-linux-musleabihf) url="${base_url}-armv7-unknown-linux-musleabihf.tgz" ;;

            aarch64-unknown-linux-gnu) url="${base_url}-aarch64-unknown-linux-musl.tgz" ;;
            aarch64-unknown-linux-musl) url="${base_url}-aarch64-unknown-linux-musl.tgz" ;;

            x86_64-pc-windows-gnu)
                is_zip=true
                url="${base_url}-x86_64-pc-windows-msvc.zip"
                ;;

            x86_64-apple-darwin | aarch64-apple-darwin | x86_64-pc-windows-msvc)
                is_zip=true
                url="${base_url}-${target}.zip"
                ;;

            *) bail "unsupported target '${target}' for cargo-binstall" ;;
        esac

        mkdir -p .install-action-tmp
        (
            cd .install-action-tmp
            if [[ "${is_zip}" == "true" ]]; then
                retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "$url" -o "cargo-binstall-${target}.zip"
                unzip "cargo-binstall-${target}.zip"
                rm "cargo-binstall-${target}.zip"
            else
                retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "$url" | tar xzf -
            fi

            mkdir -p "{cargo_bin}/"

            case "${OSTYPE}" in
                cygwin* | msys*) mv cargo-binstall.exe "${cargo_bin}/" ;;
                *) mv cargo-binstall "${cargo_bin}/" ;;
            esac
        )
        rm -rf .install-action-tmp
    else
        info "cargo-binstall already installed on in ${cargo_bin}/cargo-binstall"
    fi
}
cargo_binstall() {
    tool="$1"
    version="$2"

    info "install-action does not support ${tool}, fallback to cargo-binstall"

    install_cargo_binstall

    # --secure mode enforce downloads over secure transports only.
    # As a result, http will be disabled, and it will also set
    # min tls version to be 1.2
    case "${version}" in
        latest)
            cargo binstall --secure --no-confirm "$tool"
            ;;
        *)
            cargo binstall --secure --no-confirm --version "$version" "$tool"
            ;;
    esac
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
                cargo-hack) latest_version="0.5.15" ;;
                # https://github.com/taiki-e/cargo-llvm-cov/releases
                cargo-llvm-cov) latest_version="0.4.11" ;;
                # https://github.com/taiki-e/cargo-minimal-versions/releases
                cargo-minimal-versions) latest_version="0.1.5" ;;
                # https://github.com/taiki-e/parse-changelog/releases
                parse-changelog) latest_version="0.5.0" ;;
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
            # shellcheck disable=SC2086
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C ${CARGO_HOME:-~/.cargo}/bin
            ;;
        cross)
            # https://github.com/cross-rs/cross/releases
            latest_version="0.2.4"
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
            case "${version}" in
                0.1* | 0.2.[0-1]) url="https://github.com/${repo}/releases/download/v${version}/cross-v${version}-${target}.tar.gz" ;;
                *) url="https://github.com/${repo}/releases/download/v${version}/cross-${target}.tar.gz" ;;
            esac
            # shellcheck disable=SC2086
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C ${CARGO_HOME:-~/.cargo}/bin
            ;;
        nextest)
            # https://nexte.st/book/pre-built-binaries.html
            case "${OSTYPE}" in
                linux*) url="https://get.nexte.st/${version}/linux" ;;
                darwin*) url="https://get.nexte.st/${version}/mac" ;;
                cygwin* | msys*) url="https://get.nexte.st/${version}/windows-tar" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            # shellcheck disable=SC2086
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C ${CARGO_HOME:-~/.cargo}/bin
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
            latest_version="3.5.1"
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
            latest_version="0.39.1"
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
            # shellcheck disable=SC2086
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xJf - --strip-components 1 -C ${CARGO_HOME:-~/.cargo}/bin "wasmtime-v${version}-${target}/wasmtime"
            ;;
        mdbook)
            # https://github.com/rust-lang/mdBook/releases
            latest_version="0.4.21"
            repo="rust-lang/mdBook"
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-gnu" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                # TODO: mdbook has windows binaries, but they use `.zip` and not `.tar.gz`.
                cygwin* | msys*) bail "${tool} for windows is not supported yet by this action" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/${tool}-v${version}-${target}.tar.gz"
            # shellcheck disable=SC2086
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C ${CARGO_HOME:-~/.cargo}/bin
            ;;
        cargo-binstall) install_cargo_binstall ;;
        *)
            cargo_binstall "$tool" "$version"
            continue
            ;;
    esac

    info "${tool} installed at $(type -P "${tool}")"
    case "${tool}" in
        cargo-* | nextest) x cargo "${tool#cargo-}" --version ;;
        *) x "${tool}" --version ;;
    esac
    echo
done
