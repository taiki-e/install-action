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
download() {
    local url="$1"
    local bin_dir="$2"
    local bin="$3"
    if [[ "${bin_dir}" == "/usr/"* ]]; then
        if [[ ! -d "${bin_dir}" ]]; then
            bin_dir="${HOME}/.install-action/bin"
            if [[ ! -d "${bin_dir}" ]]; then
                mkdir -p "${bin_dir}"
                echo "${bin_dir}" >>"${GITHUB_PATH}"
                export PATH="${PATH}:${bin_dir}"
            fi
        fi
    fi
    local tar_args=()
    case "${url}" in
        *.tar.gz | *.tgz) tar_args+=("xzf") ;;
        *.tar.bz2 | *.tbz2) tar_args+=("xjf") ;;
        *.tar.xz | *.txz) tar_args+=("xJf") ;;
        *.zip)
            mkdir -p .install-action-tmp
            (
                cd .install-action-tmp
                info "downloading ${url}"
                retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" -o tmp.zip
                unzip tmp.zip
                mv "${bin}" "${bin_dir}/"
            )
            rm -rf .install-action-tmp
            return 0
            ;;
        *) bail "unrecognized archive format '${url}' for ${tool}" ;;
    esac
    tar_args+=("-")
    local components
    components=$(tr <<<"${bin}" -cd '/' | wc -c)
    if [[ "${components}" != "0" ]]; then
        tar_args+=(--strip-components "${components}")
    fi
    info "downloading ${url}"
    retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
        | tar "${tar_args[@]}" -C "${bin_dir}" "${bin}"
}
host_triple() {
    if [[ -z "${host:-}" ]]; then
        host="$(rustc -vV | grep host | cut -c 7-)"
    fi
}
install_cargo_binstall() {
    if [[ ! -f "${cargo_bin}/cargo-binstall" ]]; then
        info "installing cargo-binstall"

        host_triple
        base_url=https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall
        case "${host}" in
            x86_64-unknown-linux-gnu) url="${base_url}-x86_64-unknown-linux-musl.tgz" ;;
            x86_64-unknown-linux-musl) url="${base_url}-x86_64-unknown-linux-musl.tgz" ;;

            armv7-unknown-linux-gnueabihf) url="${base_url}-armv7-unknown-linux-musleabihf.tgz" ;;
            armv7-unknown-linux-musleabihf) url="${base_url}-armv7-unknown-linux-musleabihf.tgz" ;;

            aarch64-unknown-linux-gnu) url="${base_url}-aarch64-unknown-linux-musl.tgz" ;;
            aarch64-unknown-linux-musl) url="${base_url}-aarch64-unknown-linux-musl.tgz" ;;

            x86_64-pc-windows-gnu) url="${base_url}-x86_64-pc-windows-msvc.zip" ;;

            x86_64-apple-darwin | aarch64-apple-darwin | x86_64-pc-windows-msvc)
                url="${base_url}-${host}.zip"
                ;;

            *) bail "unsupported target '${host}' for cargo-binstall" ;;
        esac

        download "${url}" "${cargo_bin}" "cargo-binstall${exe}"
        info "cargo-binstall installed at $(type -P "cargo-binstall${exe}")"
        x cargo binstall -V
    else
        info "cargo-binstall already installed on in ${cargo_bin}/cargo-binstall"
    fi
}
cargo_binstall() {
    local tool="$1"
    local version="$2"

    info "install-action does not support ${tool}, fallback to cargo-binstall"

    install_cargo_binstall

    # --secure mode enforce downloads over secure transports only.
    # As a result, http will be disabled, and it will also set
    # min tls version to be 1.2
    case "${version}" in
        latest) cargo binstall --secure --no-confirm "$tool" ;;
        *) cargo binstall --secure --no-confirm --version "$version" "$tool" ;;
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

exe=""
case "${OSTYPE}" in
    cygwin* | msys*) exe=".exe" ;;
esac

cargo_bin="${CARGO_HOME:-"$HOME/.cargo"}/bin"
if [[ ! -d "${cargo_bin}" ]]; then
    cargo_bin=/usr/local/bin
fi

for tool in "${tools[@]}"; do
    if [[ "${tool}" == *"@"* ]]; then
        version="${tool#*@}"
    else
        version="latest"
    fi
    tool="${tool%@*}"
    bin="${tool}${exe}"
    info "installing ${tool}@${version}"
    case "${tool}" in
        cargo-hack | cargo-llvm-cov | cargo-minimal-versions | parse-changelog)
            case "${tool}" in
                # https://github.com/taiki-e/cargo-hack/releases
                cargo-hack) latest_version="0.5.17" ;;
                # https://github.com/taiki-e/cargo-llvm-cov/releases
                cargo-llvm-cov) latest_version="0.4.14" ;;
                # https://github.com/taiki-e/cargo-minimal-versions/releases
                cargo-minimal-versions) latest_version="0.1.5" ;;
                # https://github.com/taiki-e/parse-changelog/releases
                parse-changelog) latest_version="0.5.0" ;;
                *) exit 1 ;;
            esac
            repo="taiki-e/${tool}"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-musl" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                cygwin* | msys*) target="x86_64-pc-windows-msvc" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/${tool}-${target}.tar.gz"
            download "${url}" "${cargo_bin}" "${tool}${exe}"
            ;;
        cargo-udeps)
            # https://github.com/est31/cargo-udeps/releases
            latest_version="0.1.30"
            repo="est31/${tool}"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            base_url="https://github.com/${repo}/releases/download/v${version}/${tool}-v${version}"
            case "${OSTYPE}" in
                linux*)
                    target="x86_64-unknown-linux-gnu"
                    url="${base_url}-${target}.tar.gz"
                    ;;
                darwin*)
                    target="x86_64-apple-darwin"
                    url="${base_url}-${target}.tar.gz"
                    ;;
                cygwin* | msys*)
                    target="x86_64-pc-windows-msvc"
                    url="${base_url}-${target}.zip"
                    ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            # leading `./` is required for cargo-udeps to work
            download "${url}" "${cargo_bin}" "./${tool}-v${version}-${target}/${tool}${exe}"
            ;;
        cross)
            # https://github.com/cross-rs/cross/releases
            latest_version="0.2.4"
            repo="cross-rs/${tool}"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-musl" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                cygwin* | msys*) target="x86_64-pc-windows-msvc" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            case "${version}" in
                0.1.* | 0.2.[0-1]) url="https://github.com/${repo}/releases/download/v${version}/${tool}-v${version}-${target}.tar.gz" ;;
                *) url="https://github.com/${repo}/releases/download/v${version}/${tool}-${target}.tar.gz" ;;
            esac
            download "${url}" "${cargo_bin}" "${tool}${exe}"
            ;;
        nextest | cargo-nextest)
            bin="cargo-nextest"
            # https://nexte.st/book/pre-built-binaries.html
            case "${OSTYPE}" in
                linux*)
                    host_triple
                    case "${host}" in
                        *-linux-gnu*) url="https://get.nexte.st/${version}/linux" ;;
                        *) url="https://get.nexte.st/${version}/linux-musl" ;;
                    esac
                    ;;
                darwin*) url="https://get.nexte.st/${version}/mac" ;;
                cygwin* | msys*) url="https://get.nexte.st/${version}/windows-tar" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            info "downloading ${url}"
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" \
                | tar xzf - -C "${cargo_bin}"
            ;;
        protoc)
            # https://github.com/protocolbuffers/protobuf/releases
            latest_version="3.21.4"
            repo="protocolbuffers/protobuf"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            miner_patch_version="${version#*.}"
            base_url="https://github.com/${repo}/releases/download/v${miner_patch_version}/protoc-${miner_patch_version}"
            bin_dir="/usr/local/bin"
            include_dir="/usr/local/include"
            case "${OSTYPE}" in
                linux*) url="${base_url}-linux-x86_64.zip" ;;
                darwin*) url="${base_url}-osx-x86_64.zip" ;;
                cygwin* | msys*)
                    url="${base_url}-win64.zip"
                    bin_dir="${HOME}/.install-action/bin"
                    include_dir="${HOME}/.install-action/include"
                    if [[ ! -d "${bin_dir}" ]]; then
                        mkdir -p "${bin_dir}"
                        mkdir -p "${include_dir}"
                        echo "${bin_dir}" >>"${GITHUB_PATH}"
                        export PATH="${PATH}:${bin_dir}"
                    fi
                    ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            mkdir -p .install-action-tmp
            (
                cd .install-action-tmp
                info "downloading ${url}"
                retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "${url}" -o tmp.zip
                unzip tmp.zip
                mv "bin/protoc${exe}" "${bin_dir}/"
                mkdir -p "${include_dir}/"
                case "${OSTYPE}" in
                    linux* | darwin*) sudo cp -r include/. "${include_dir}/" ;;
                    cygwin* | msys*)
                        cp -r include/. "${include_dir}/"
                        bin_dir=$(sed <<<"${bin_dir}" 's/^\/c\//C:\\/')
                        ;;
                esac
                if [[ -z "${PROTOC:-}" ]]; then
                    info "setting PROTOC environment variable"
                    echo "PROTOC=${bin_dir}/protoc${exe}" >>"${GITHUB_ENV}"
                fi
            )
            rm -rf .install-action-tmp
            ;;
        shellcheck)
            # https://github.com/koalaman/shellcheck/releases
            latest_version="0.8.0"
            repo="koalaman/${tool}"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            base_url="https://github.com/${repo}/releases/download/v${version}/${tool}-v${version}"
            bin="${tool}-v${version}/${tool}${exe}"
            case "${OSTYPE}" in
                linux*)
                    if type -P shellcheck &>/dev/null; then
                        sudo apt-get -qq -o Dpkg::Use-Pty=0 remove -y shellcheck
                    fi
                    url="${base_url}.linux.x86_64.tar.xz"
                    ;;
                darwin*) url="${base_url}.darwin.x86_64.tar.xz" ;;
                cygwin* | msys*)
                    url="${base_url}.zip"
                    bin="${tool}${exe}"
                    ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            download "${url}" /usr/local/bin "${bin}"
            ;;
        shfmt)
            # https://github.com/mvdan/sh/releases
            latest_version="3.5.1"
            repo="mvdan/sh"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            bin_dir="/usr/local/bin"
            case "${OSTYPE}" in
                linux*) target="linux_amd64" ;;
                darwin*) target="darwin_amd64" ;;
                cygwin* | msys*)
                    target="windows_amd64"
                    bin_dir="${HOME}/.install-action/bin"
                    if [[ ! -d "${bin_dir}" ]]; then
                        mkdir -p "${bin_dir}"
                        echo "${bin_dir}" >>"${GITHUB_PATH}"
                        export PATH="${PATH}:${bin_dir}"
                    fi
                    ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/${tool}_v${version}_${target}${exe}"
            info "downloading ${url}"
            retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused -o "${bin_dir}/${tool}${exe}" "${url}"
            case "${OSTYPE}" in
                linux* | darwin*) chmod +x "${bin_dir}/${tool}${exe}" ;;
            esac
            ;;
        valgrind)
            case "${version}" in
                latest) ;;
                *) warn "specifying the version of ${tool} is not supported yet by this action" ;;
            esac
            case "${OSTYPE}" in
                linux*) ;;
                darwin* | cygwin* | msys*) bail "${tool} for non-linux is not supported yet by this action" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            retry sudo apt-get -o Acquire::Retries=10 -qq update
            # libc6-dbg is needed to run Valgrind
            retry sudo apt-get -o Acquire::Retries=10 -qq -o Dpkg::Use-Pty=0 install -y libc6-dbg
            # Use snap to install the latest Valgrind
            # https://snapcraft.io/install/valgrind/ubuntu
            retry sudo snap install valgrind --classic
            ;;
        wasm-pack)
            # https://github.com/rustwasm/wasm-pack/releases
            latest_version="0.10.3"
            repo="rustwasm/${tool}"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-musl" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                cygwin* | msys*) target="x86_64-pc-windows-msvc" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/${tool}-v${version}-${target}.tar.gz"
            download "${url}" "${cargo_bin}" "${tool}-v${version}-${target}/${tool}${exe}"
            ;;
        wasmtime)
            # https://github.com/bytecodealliance/wasmtime/releases
            latest_version="0.39.1"
            repo="bytecodealliance/${tool}"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            base_url="https://github.com/${repo}/releases/download/v${version}/${tool}-v${version}"
            case "${OSTYPE}" in
                linux*)
                    target="x86_64-linux"
                    url="${base_url}-${target}.tar.xz"
                    ;;
                darwin*)
                    target="x86_64-macos"
                    url="${base_url}-${target}.tar.xz"
                    ;;
                cygwin* | msys*)
                    target="x86_64-windows"
                    url="${base_url}-${target}.zip"
                    ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            download "${url}" "${cargo_bin}" "${tool}-v${version}-${target}/${tool}${exe}"
            ;;
        mdbook)
            # https://github.com/rust-lang/mdBook/releases
            latest_version="0.4.21"
            repo="rust-lang/mdBook"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            base_url="https://github.com/${repo}/releases/download/v${version}/${tool}-v${version}"
            case "${OSTYPE}" in
                linux*) url="${base_url}-x86_64-unknown-linux-gnu.tar.gz" ;;
                darwin*) url="${base_url}-x86_64-apple-darwin.tar.gz" ;;
                cygwin* | msys*) url="${base_url}-x86_64-pc-windows-msvc.zip" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            download "${url}" "${cargo_bin}" "${tool}${exe}"
            ;;
        mdbook-linkcheck)
            # https://github.com/Michael-F-Bryan/mdbook-linkcheck/releases
            latest_version="0.7.6"
            repo="Michael-F-Bryan/${tool}"
            case "${version}" in
                latest) version="${latest_version}" ;;
            esac
            case "${OSTYPE}" in
                linux*) target="x86_64-unknown-linux-gnu" ;;
                darwin*) target="x86_64-apple-darwin" ;;
                cygwin* | msys*) target="x86_64-pc-windows-msvc" ;;
                *) bail "unsupported OSTYPE '${OSTYPE}' for ${tool}" ;;
            esac
            url="https://github.com/${repo}/releases/download/v${version}/${tool}.${target}.zip"
            download "${url}" "${cargo_bin}" "${tool}${exe}"
            case "${OSTYPE}" in
                linux* | darwin*) chmod +x "${cargo_bin}/${tool}${exe}" ;;
            esac
            ;;
        cargo-binstall)
            install_cargo_binstall
            continue
            ;;
        *)
            cargo_binstall "${tool}" "${version}"
            continue
            ;;
    esac

    info "${tool} installed at $(type -P "${bin}")"
    case "${bin}" in
        "cargo-udeps${exe}") x cargo udeps --help | head -1 ;; # cargo-udeps v0.1.30 does not support --version option
        cargo-*) x cargo "${tool#cargo-}" --version ;;
        *) x "${tool}" --version ;;
    esac
    echo
done
