#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'

rx() {
    local cmd="$1"
    shift
    (
        set -x
        "${cmd}" "$@"
    )
}
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
    echo "::error::$*"
    exit 1
}
warn() {
    echo "::warning::$*"
}
info() {
    echo "info: $*"
}
_sudo() {
    if type -P sudo &>/dev/null; then
        sudo "$@"
    else
        "$@"
    fi
}
download_and_checksum() {
    local url="$1"
    local checksum="$2"
    if [[ -z "${enable_checksum}" ]]; then
        checksum=""
    fi
    info "downloading ${url}"
    retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "${url}" -o tmp
    if [[ -n "${checksum}" ]]; then
        info "verifying sha256 checksum for $(basename "${url}")"
        if type -P sha256sum &>/dev/null; then
            echo "${checksum} *tmp" | sha256sum -c - >/dev/null
        elif type -P shasum &>/dev/null; then
            # GitHub-hosted macOS runner does not install GNU Coreutils by default.
            # https://github.com/actions/runner-images/issues/90
            echo "${checksum} *tmp" | shasum -a 256 -c - >/dev/null
        else
            bail "checksum requires 'sha256sum' or 'shasum' command; consider installing one of them or setting 'checksum' input option to 'false'"
        fi
    fi
}
download_and_extract() {
    local url="$1"
    shift
    local checksum="$1"
    shift
    local bin_dir="$1"
    shift
    local bin_in_archive=("$@") # path to bin in archive
    if [[ "${bin_dir}" == "${install_action_dir}/bin" ]]; then
        init_install_action_bin_dir
    fi

    installed_bin=()
    local tmp
    case "${tool}" in
        # xbuild's binary name is "x", as opposed to the usual crate name
        xbuild) installed_bin=("${bin_dir}/x${exe}") ;;
        # editorconfig-checker's binary name is renamed below
        editorconfig-checker) installed_bin=("${bin_dir}/${tool}${exe}") ;;
        *)
            for tmp in "${bin_in_archive[@]}"; do
                installed_bin+=("${bin_dir}/$(basename "${tmp}")")
            done
            ;;
    esac

    local tar_args=()
    case "${url}" in
        *.tar.gz | *.tgz)
            tar_args+=("xzf")
            if ! type -P gzip &>/dev/null; then
                case "${base_distro}" in
                    debian | fedora | suse | arch | alpine)
                        echo "::group::Install packages required for installation (gzip)"
                        sys_install gzip
                        echo "::endgroup::"
                        ;;
                esac
            fi
            ;;
        *.tar.bz2 | *.tbz2)
            tar_args+=("xjf")
            if ! type -P bzip2 &>/dev/null; then
                case "${base_distro}" in
                    debian | fedora | suse | arch | alpine)
                        echo "::group::Install packages required for installation (bzip2)"
                        sys_install bzip2
                        echo "::endgroup::"
                        ;;
                esac
            fi
            ;;
        *.tar.xz | *.txz)
            tar_args+=("xJf")
            if ! type -P xz &>/dev/null; then
                case "${base_distro}" in
                    debian)
                        echo "::group::Install packages required for installation (xz-utils)"
                        sys_install xz-utils
                        echo "::endgroup::"
                        ;;
                    fedora | suse | arch | alpine)
                        echo "::group::Install packages required for installation (xz)"
                        sys_install xz
                        echo "::endgroup::"
                        ;;
                esac
            fi
            ;;
        *.zip)
            if ! type -P unzip &>/dev/null; then
                case "${base_distro}" in
                    debian | fedora | suse | arch | alpine)
                        echo "::group::Install packages required for installation (unzip)"
                        sys_install unzip
                        echo "::endgroup::"
                        ;;
                esac
            fi
            ;;
    esac

    mkdir -p "${tmp_dir}"
    (
        cd "${tmp_dir}"
        download_and_checksum "${url}" "${checksum}"
        if [[ ${#tar_args[@]} -gt 0 ]]; then
            tar_args+=("tmp")
            tar "${tar_args[@]}"
            for tmp in "${bin_in_archive[@]}"; do
                case "${tool}" in
                    editorconfig-checker) mv "${tmp}" "${bin_dir}/${tool}${exe}" ;;
                    *) mv "${tmp}" "${bin_dir}/" ;;
                esac
            done
        else
            case "${url}" in
                *.zip)
                    unzip -q tmp "${bin_in_archive#\./}"
                    for tmp in "${bin_in_archive[@]}"; do
                        mv "${tmp}" "${bin_dir}/"
                    done
                    ;;
                *)
                    for tmp in "${installed_bin[@]}"; do
                        mv tmp "${tmp}"
                    done
                    ;;
            esac
        fi
    )
    rm -rf "${tmp_dir}"

    case "${host_os}" in
        linux | macos)
            for tmp in "${installed_bin[@]}"; do
                if [[ ! -x "${tmp}" ]]; then
                    chmod +x "${tmp}"
                fi
            done
            ;;
    esac
}
read_manifest() {
    local tool="$1"
    local version="$2"
    local manifest
    rust_crate=$(call_jq -r ".rust_crate" "${manifest_dir}/${tool}.json")
    manifest=$(call_jq -r ".\"${version}\"" "${manifest_dir}/${tool}.json")
    if [[ "${manifest}" == "null" ]]; then
        download_info="null"
        return 0
    fi
    exact_version=$(call_jq <<<"${manifest}" -r '.version')
    if [[ "${exact_version}" == "null" ]]; then
        exact_version="${version}"
    else
        manifest=$(call_jq -r ".\"${exact_version}\"" "${manifest_dir}/${tool}.json")
    fi
    case "${host_os}" in
        linux)
            # Static-linked binaries compiled for linux-musl will also work on linux-gnu systems and are
            # usually preferred over linux-gnu binaries because they can avoid glibc version issues.
            # (rustc enables statically linking for linux-musl by default, except for mips.)
            host_platform="${host_arch}_linux_musl"
            download_info=$(call_jq <<<"${manifest}" -r ".${host_platform}")
            if [[ "${download_info}" == "null" ]]; then
                # Even if host_env is musl, we won't issue an error here because it seems that in
                # some cases linux-gnu binaries will work on linux-musl hosts.
                # https://wiki.alpinelinux.org/wiki/Running_glibc_programs
                # TODO: However, a warning may make sense.
                host_platform="${host_arch}_linux_gnu"
                download_info=$(call_jq <<<"${manifest}" -r ".${host_platform}")
            fi
            ;;
        macos | windows)
            # Binaries compiled for x86_64 macOS will usually also work on aarch64 macOS.
            # Binaries compiled for x86_64 Windows will usually also work on aarch64 Windows 11+.
            host_platform="${host_arch}_${host_os}"
            download_info=$(call_jq <<<"${manifest}" -r ".${host_platform}")
            if [[ "${download_info}" == "null" ]] && [[ "${host_arch}" != "x86_64" ]]; then
                host_platform="x86_64_${host_os}"
                download_info=$(call_jq <<<"${manifest}" -r ".${host_platform}")
            fi
            ;;
        *) bail "unsupported OS type '${host_os}' for ${tool}" ;;
    esac
}
read_download_info() {
    local tool="$1"
    local version="$2"
    if [[ "${download_info}" == "null" ]]; then
        bail "${tool}@${version} for '${host_os}' is not supported"
    fi
    checksum=$(call_jq <<<"${download_info}" -r '.checksum')
    url=$(call_jq <<<"${download_info}" -r '.url')
    local tmp
    bin_in_archive=()
    if [[ "${url}" == "null" ]]; then
        local template
        template=$(call_jq -r ".template.${host_platform}" "${manifest_dir}/${tool}.json")
        url=$(call_jq <<<"${template}" -r '.url')
        url="${url//\$\{version\}/${exact_version}}"
        tmp=$(call_jq <<<"${template}" -r '.bin' | sed -E "s/\\$\\{version\\}/${exact_version}/g")
        if [[ "${tmp}" == *"["* ]]; then
            # shellcheck disable=SC2207
            bin_in_archive=($(call_jq <<<"${template}" -r '.bin[]' | sed -E "s/\\$\\{version\\}/${exact_version}/g"))
        fi
    else
        tmp=$(call_jq <<<"${download_info}" -r '.bin')
        if [[ "${tmp}" == *"["* ]]; then
            # shellcheck disable=SC2207
            bin_in_archive=($(call_jq <<<"${download_info}" -r '.bin[]'))
        fi
    fi
    if [[ ${#bin_in_archive[@]} -eq 0 ]]; then
        if [[ "${tmp}" == "null" ]]; then
            bin_in_archive=("${tool}${exe}")
        else
            bin_in_archive=("${tmp}")
        fi
    fi
    if [[ "${rust_crate}" == "null" ]]; then
        if [[ "${host_os}" == "windows" ]] || [[ ! -e /usr/local/bin ]]; then
            bin_dir="${install_action_dir}/bin"
        else
            bin_dir=/usr/local/bin
        fi
    else
        bin_dir="${cargo_bin}"
    fi
}
download_from_manifest() {
    read_manifest "$@"
    download_from_download_info "$@"
}
download_from_download_info() {
    read_download_info "$@"
    download_and_extract "${url}" "${checksum}" "${bin_dir}" "${bin_in_archive[@]}"
}
install_cargo_binstall() {
    local binstall_version
    binstall_version=$(call_jq -r '.latest.version' "${manifest_dir}/cargo-binstall.json")
    local install_binstall='1'
    _binstall_version=$("cargo-binstall${exe}" binstall -V 2>/dev/null || echo "")
    if [[ -n "${_binstall_version}" ]]; then
        if [[ "${_binstall_version}" == "${binstall_version}" ]]; then
            info "cargo-binstall already installed at ${cargo_bin}/cargo-binstall${exe}"
            install_binstall=''
        else
            info "cargo-binstall already installed at ${cargo_bin}/cargo-binstall${exe}, but is not compatible version with install-action, upgrading"
            rm "${cargo_bin}/cargo-binstall${exe}"
        fi
    fi

    if [[ -n "${install_binstall}" ]]; then
        info "installing cargo-binstall@latest (${binstall_version})"
        download_from_manifest "cargo-binstall" "latest"
        installed_at=$(type -P "cargo-binstall${exe}" || echo "")
        if [[ -n "${installed_at}" ]]; then
            info "cargo-binstall installed at ${installed_at}"
        else
            warn "cargo-binstall should be installed at ${bin_dir:-}/cargo-binstall${exe}; but cargo-binstall${exe} not found in path"
        fi
        rx "cargo-binstall${exe}" binstall -V
    fi
}
apt_update() {
    retry _sudo apt-get -o Acquire::Retries=10 -qq update
    apt_updated=1
}
apt_install() {
    if [[ -z "${apt_updated:-}" ]]; then
        apt_update
    fi
    retry _sudo apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@"
}
apt_remove() {
    _sudo apt-get -qq -o Dpkg::Use-Pty=0 remove -y "$@"
}
snap_install() {
    retry _sudo snap install "$@"
}
dnf_install() {
    retry _sudo "${dnf}" install -y "$@"
}
zypper_install() {
    retry _sudo zypper install -y "$@"
}
pacman_install() {
    retry _sudo pacman -Sy --noconfirm "$@"
}
apk_install() {
    if type -P sudo &>/dev/null; then
        sudo apk --no-cache add "$@"
    elif type -P doas &>/dev/null; then
        doas apk --no-cache add "$@"
    else
        apk --no-cache add "$@"
    fi
}
sys_install() {
    case "${base_distro}" in
        debian) apt_install "$@" ;;
        fedora) dnf_install "$@" ;;
        suse) zypper_install "$@" ;;
        arch) pacman_install "$@" ;;
        alpine) apk_install "$@" ;;
    esac
}
init_install_action_bin_dir() {
    if [[ -z "${init_install_action_bin:-}" ]]; then
        init_install_action_bin=1
        mkdir -p "${bin_dir}"
        export PATH="${PATH}:${bin_dir}"
        local _bin_dir
        _bin_dir=$(canonicalize_windows_path "${bin_dir}")
        # TODO: avoid this when already added
        info "adding '${_bin_dir}' to PATH"
        echo "${_bin_dir}" >>"${GITHUB_PATH}"
    fi
}
canonicalize_windows_path() {
    case "${host_os}" in
        windows) sed <<<"$1" 's/^\/c\//C:\\/; s/\//\\/g' ;;
        *) echo "$1" ;;
    esac
}

# cargo-binstall may call `cargo install` on their fallback: https://github.com/taiki-e/install-action/pull/54#issuecomment-1383140833
# cross calls rustup on `cross --version` if the current directly is cargo workspace.
export CARGO_NET_RETRY=10
export RUSTUP_MAX_RETRIES=10

if [[ $# -gt 0 ]]; then
    bail "invalid argument '$1'"
fi

export DEBIAN_FRONTEND=noninteractive
manifest_dir="$(dirname "$0")/manifests"

# Inputs
tool="${INPUT_TOOL:-}"
tools=()
if [[ -n "${tool}" ]]; then
    while read -rd,; do
        t="${REPLY# *}"
        tools+=("${t%* }")
    done <<<"${tool},"
fi
if [[ ${#tools[@]} -eq 0 ]]; then
    warn "no tool specified; this could be caused by a dependabot bug where @<tool_name> tags on this action are replaced by @<version> tags"
    # Exit with 0 for backward compatibility, we want to reject it in the next major release.
    exit 0
fi

enable_checksum="${INPUT_CHECKSUM:-}"
case "${enable_checksum}" in
    true) ;;
    false) enable_checksum='' ;;
    *) bail "'checksum' input option must be 'true' or 'false': '${enable_checksum}'" ;;
esac

# Refs: https://github.com/rust-lang/rustup/blob/HEAD/rustup-init.sh
base_distro=""
exe=""
case "$(uname -s)" in
    Linux)
        host_os=linux
        if grep -q '^ID_LIKE=' /etc/os-release; then
            base_distro=$(grep '^ID_LIKE=' /etc/os-release | cut -d= -f2)
            case "${base_distro}" in
                *debian*) base_distro=debian ;;
                *fedora*) base_distro=fedora ;;
                *suse*) base_distro=suse ;;
                *arch*) base_distro=arch ;;
                *alpine*) base_distro=alpine ;;
            esac
        else
            base_distro=$(grep '^ID=' /etc/os-release | cut -d= -f2)
        fi
        case "${base_distro}" in
            fedora)
                dnf=dnf
                if ! type -P dnf &>/dev/null; then
                    if type -P microdnf &>/dev/null; then
                        # fedora-based distributions have "minimal" images that
                        # use microdnf instead of dnf.
                        dnf=microdnf
                    else
                        # If neither dnf nor microdnf is available, it is
                        # probably an RHEL7-based distribution that does not
                        # have dnf installed by default.
                        dnf=yum
                    fi
                fi
                ;;
        esac
        ;;
    Darwin) host_os=macos ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT)
        host_os=windows
        exe=".exe"
        ;;
    *) bail "unrecognized OS type '$(uname -s)'" ;;
esac
case "$(uname -m)" in
    aarch64 | arm64) host_arch="aarch64" ;;
    xscale | arm | armv*l)
        # Ignore arm for now, as we need to consider the version and whether hard-float is supported.
        # https://github.com/rust-lang/rustup/pull/593
        # https://github.com/cross-rs/cross/pull/1018
        # Does it seem only armv7l+ is supported?
        # https://github.com/actions/runner/blob/v2.315.0/src/Misc/externals.sh#L189
        # https://github.com/actions/runner/issues/688
        bail "32-bit ARM runner is not supported yet by this action; if you need support for this platform, please submit an issue at <https://github.com/taiki-e/install-action>"
        ;;
    # GitHub Actions Runner supports Linux (x86_64, aarch64, arm), Windows (x86_64, aarch64),
    # and macOS (x86_64, aarch64).
    # https://github.com/actions/runner/blob/v2.315.0/.github/workflows/build.yml#L21
    # https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners#supported-architectures-and-operating-systems-for-self-hosted-runners
    # So we can assume x86_64 unless it is aarch64 or arm.
    *) host_arch="x86_64" ;;
esac
info "host platform: ${host_arch}_${host_os}"

install_action_dir="${HOME}/.install-action"
tmp_dir="${install_action_dir}/tmp"
cargo_bin="${CARGO_HOME:-"${HOME}/.cargo"}/bin"
# If $CARGO_HOME does not exist, or cargo installed outside of $CARGO_HOME/bin
# is used ($CARGO_HOME/bin is most likely not included in the PATH), fallback to
# /usr/local/bin or $install_action_dir/bin.
if [[ ! -e "${cargo_bin}" ]] || [[ "$(type -P cargo || true)" != "${cargo_bin}/cargo"* ]]; then
    if type -P cargo &>/dev/null; then
        info "cargo is located at $(type -P cargo)"
    fi
    if [[ "${host_os}" == "windows" ]] || [[ ! -e /usr/local/bin ]]; then
        cargo_bin="${install_action_dir}/bin"
    else
        cargo_bin=/usr/local/bin
    fi
fi

jq_use_b=''
case "${host_os}" in
    linux)
        if ! type -P jq &>/dev/null || ! type -P curl &>/dev/null || ! type -P tar &>/dev/null; then
            case "${base_distro}" in
                debian | fedora | suse | arch | alpine)
                    echo "::group::Install packages required for installation (jq, curl, and/or tar)"
                    sys_packages=()
                    if ! type -P curl &>/dev/null; then
                        sys_packages+=(ca-certificates curl)
                    fi
                    if ! type -P tar &>/dev/null; then
                        sys_packages+=(tar)
                    fi
                    if [[ "${dnf:-}" == "yum" ]]; then
                        # On RHEL7-based distribution jq requires EPEL
                        if ! type -P jq &>/dev/null; then
                            sys_packages+=(epel-release)
                            sys_install "${sys_packages[@]}"
                            sys_install jq --enablerepo=epel
                        else
                            sys_install "${sys_packages[@]}"
                        fi
                    else
                        if ! type -P jq &>/dev/null; then
                            sys_packages+=(jq)
                        fi
                        sys_install "${sys_packages[@]}"
                    fi
                    echo "::endgroup::"
                    ;;
                *) warn "install-action requires at least jq and curl on non-Debian/Fedora/SUSE/Arch/Alpine-based Linux" ;;
            esac
        fi
        ;;
    macos)
        if ! type -P jq &>/dev/null || ! type -P curl &>/dev/null; then
            warn "install-action requires at least jq and curl on macOS"
        fi
        ;;
    windows)
        if ! type -P curl &>/dev/null; then
            warn "install-action requires at least curl on Windows"
        fi
        # https://github.com/jqlang/jq/issues/1854
        jq_use_b=1
        jq="${install_action_dir}/jq/bin/jq.exe"
        if [[ ! -f "${jq}" ]]; then
            jq_version=$(jq --version || echo "")
            case "${jq_version}" in
                jq-1.[7-9]* | jq-1.[1-9][0-9]*) jq='' ;;
                *)
                    _tmp=$(jq <<<"{}" -r .a || echo "")
                    if [[ "${_tmp}" == "null" ]]; then
                        jq=''
                        jq_use_b=''
                    else
                        info "old jq (${jq_version}) has bug on Windows; downloading jq 1.7 (will not be added to PATH)"
                        mkdir -p "${install_action_dir}/jq/bin"
                        url='https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe'
                        checksum='7451fbbf37feffb9bf262bd97c54f0da558c63f0748e64152dd87b0a07b6d6ab'
                        (
                            cd "${install_action_dir}/jq/bin"
                            download_and_checksum "${url}" "${checksum}"
                            mv tmp jq.exe
                        )
                        echo
                    fi
                    ;;
            esac
        fi
        ;;
    *) bail "unsupported host OS '${host_os}'" ;;
esac
call_jq() {
    # https://github.com/jqlang/jq/issues/1854
    if [[ -n "${jq_use_b}" ]]; then
        "${jq:-jq}" -b "$@"
    else
        "${jq:-jq}" "$@"
    fi
}

unsupported_tools=()
for tool in "${tools[@]}"; do
    if [[ "${tool}" == *"@"* ]]; then
        version="${tool#*@}"
        tool="${tool%@*}"
        if [[ ! "${version}" =~ ^([1-9][0-9]*(\.[0-9]+(\.[0-9]+)?)?|0\.[1-9][0-9]*(\.[0-9]+)?|^0\.0\.[0-9]+)$|^latest$ ]]; then
            if [[ ! "${version}" =~ ^([1-9][0-9]*(\.[0-9]+(\.[0-9]+)?)?|0\.[1-9][0-9]*(\.[0-9]+)?|^0\.0\.[0-9]+)(-[0-9A-Za-z\.-]+)?(\+[0-9A-Za-z\.-]+)?$|^latest$ ]]; then
                bail "install-action does not support semver operators: '${version}'"
            fi
            bail "install-action v2 does not support semver pre-release and build-metadata: '${version}'; if you need these supports again, please submit an issue at <https://github.com/taiki-e/install-action>"
        fi
    else
        version="latest"
    fi
    installed_bin=()
    case "${tool}" in
        protoc)
            info "installing ${tool}@${version}"
            read_manifest "protoc" "${version}"
            read_download_info "protoc" "${version}"
            # Copying files to /usr/local/include requires sudo, so do not use it.
            bin_dir="${install_action_dir}/bin"
            include_dir="${install_action_dir}/include"
            init_install_action_bin_dir
            if [[ ! -e "${include_dir}" ]]; then
                mkdir -p "${include_dir}"
            fi
            if ! type -P unzip &>/dev/null; then
                case "${base_distro}" in
                    debian | fedora | suse | arch | alpine)
                        echo "::group::Install packages required for installation (unzip)"
                        sys_install unzip
                        echo "::endgroup::"
                        ;;
                esac
            fi
            mkdir -p "${tmp_dir}"
            (
                cd "${tmp_dir}"
                download_and_checksum "${url}" "${checksum}"
                unzip -q tmp
                mv "bin/protoc${exe}" "${bin_dir}/"
                mkdir -p "${include_dir}/"
                cp -r include/. "${include_dir}/"
                if [[ -z "${PROTOC:-}" ]]; then
                    _bin_dir=$(canonicalize_windows_path "${bin_dir}")
                    info "setting PROTOC environment variable to '${_bin_dir}/protoc${exe}'"
                    echo "PROTOC=${_bin_dir}/protoc${exe}" >>"${GITHUB_ENV}"
                fi
            )
            rm -rf "${tmp_dir}"
            installed_bin=("${tool}${exe}")
            ;;
        valgrind)
            info "installing ${tool}@${version}"
            case "${version}" in
                latest) ;;
                *) warn "specifying the version of ${tool} is not supported yet by this action" ;;
            esac
            case "${host_os}" in
                linux) ;;
                macos | windows) bail "${tool} for non-linux is not supported yet by this action" ;;
                *) bail "unsupported host OS '${host_os}' for ${tool}" ;;
            esac
            # libc6-dbg is needed to run Valgrind
            apt_install libc6-dbg
            # Use snap to install the latest Valgrind
            # https://snapcraft.io/install/valgrind/ubuntu
            snap_install valgrind --classic
            installed_bin=("${tool}${exe}")
            ;;
        cargo-binstall)
            case "${version}" in
                latest) ;;
                *) warn "specifying the version of ${tool} is not supported by this action" ;;
            esac
            install_cargo_binstall
            echo
            continue
            ;;
        *)
            # Handle aliases
            case "${tool}" in
                cargo-nextest | nextest) tool="cargo-nextest" ;;
            esac

            # Use cargo-binstall fallback if tool is not available.
            if [[ ! -f "${manifest_dir}/${tool}.json" ]]; then
                case "${version}" in
                    latest) unsupported_tools+=("${tool}") ;;
                    *) unsupported_tools+=("${tool}@${version}") ;;
                esac
                continue
            fi

            # Use cargo-binstall fallback if tool is available but the specified version not available.
            read_manifest "${tool}" "${version}"
            if [[ "${download_info}" == "null" ]]; then
                if [[ "${rust_crate}" == "null" ]]; then
                    bail "${tool}@${version} for '${host_os}' is not supported"
                fi
                warn "${tool}@${version} for '${host_os}' is not supported; fallback to cargo-binstall"
                case "${version}" in
                    latest) unsupported_tools+=("${rust_crate}") ;;
                    *) unsupported_tools+=("${rust_crate}@${version}") ;;
                esac
                continue
            fi

            info "installing ${tool}@${version}"

            # Pre-install
            case "${tool}" in
                shellcheck)
                    case "${host_os}" in
                        linux)
                            if type -P shellcheck &>/dev/null; then
                                apt_remove -y shellcheck
                            fi
                            ;;
                    esac
                    ;;
            esac

            download_from_download_info "${tool}" "${version}"
            ;;
    esac

    tool_bin_stems=()
    for tool_bin in "${installed_bin[@]}"; do
        tool_bin=$(basename "${tool_bin}")
        tool_bin_stem="${tool_bin%.exe}"
        installed_at=$(type -P "${tool_bin}" || echo "")
        if [[ -z "${installed_at}" ]]; then
            tool_bin="${tool_bin_stem}"
            installed_at=$(type -P "${tool_bin}" || echo "")
        fi
        if [[ -n "${installed_at}" ]]; then
            info "${tool_bin_stem} installed at ${installed_at}"
        else
            warn "${tool_bin_stem} should be installed at ${bin_dir:+"${bin_dir}/"}${tool_bin}${exe}; but ${tool_bin}${exe} not found in path"
        fi
        tool_bin_stems+=("${tool_bin_stem}")
    done
    for tool_bin_stem in "${tool_bin_stems[@]}"; do
        # cargo-udeps 0.1.30 and wasm-pack 0.12.0 do not support --version flag.
        case "${tool_bin_stem}" in
            # biome up to 1.2.2 exits with 1 on both --version and --help flags.
            # cargo-machete up to 0.6.0 does not support --version flag.
            biome | cargo-machete) rx "${tool_bin_stem}" --version || true ;;
            # these packages support neither --version nor --help flag.
            cargo-careful | wasm-bindgen-test-runner) ;;
            # wasm2es6js does not support --version flag and --help flag doesn't contains version info.
            wasm2es6js) ;;
            cargo-*)
                case "${tool_bin_stem}" in
                    # cargo-valgrind 2.1.0's --version flag just calls cargo's --version flag
                    cargo-valgrind) rx "${tool_bin_stem}" "${tool_bin_stem#cargo-}" --help ;;
                    *)
                        if ! rx "${tool_bin_stem}" "${tool_bin_stem#cargo-}" --version; then
                            rx "${tool_bin_stem}" "${tool_bin_stem#cargo-}" --help
                        fi
                        ;;
                esac
                ;;
            *)
                if ! rx "${tool_bin_stem}" --version; then
                    rx "${tool_bin_stem}" --help
                fi
                ;;
        esac
    done
    echo
done

if [[ ${#unsupported_tools[@]} -gt 0 ]]; then
    IFS=','
    info "install-action does not support ${unsupported_tools[*]}; fallback to cargo-binstall"
    IFS=$'\n\t'
    install_cargo_binstall
    # By default, cargo-binstall enforce downloads over secure transports only.
    # As a result, http will be disabled, and it will also set
    # min tls version to be 1.2
    cargo-binstall binstall --force --no-confirm --locked "${unsupported_tools[@]}"
    if ! type -P cargo >/dev/null; then
        _bin_dir=$(canonicalize_windows_path "${HOME}/.cargo/bin")
        # TODO: avoid this when already added
        info "adding '${_bin_dir}' to PATH"
        echo "${_bin_dir}" >>"${GITHUB_PATH}"
    fi
fi
