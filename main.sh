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
        echo "${checksum} *tmp" >tmp.sha256sum
        if type -P sha256sum &>/dev/null; then
            sha256sum -c tmp.sha256sum >/dev/null
        elif type -P shasum &>/dev/null; then
            # GitHub-hosted macOS runner does not install GNU Coreutils by default.
            # https://github.com/actions/runner-images/issues/90
            shasum -a 256 -c tmp.sha256sum >/dev/null
        else
            bail "checksum requires 'sha256sum' or 'shasum' command; consider installing one of them or setting 'checksum' input option to 'false'"
        fi
    fi
}
download_and_extract() {
    local url="$1"
    local checksum="$2"
    local bin_dir="$3"
    local bin_in_archive="$4" # path to bin in archive
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
    local installed_bin
    installed_bin="${bin_dir}/$(basename "${bin_in_archive}")"

    local tar_args=()
    case "${url}" in
        *.tar.gz | *.tgz) tar_args+=("xzf") ;;
        *.tar.bz2 | *.tbz2)
            tar_args+=("xjf")
            if ! type -P bzip2 &>/dev/null; then
                case "${base_distro}" in
                    debian | alpine | fedora) sys_install bzip2 ;;
                esac
            fi
            ;;
        *.tar.xz | *.txz)
            tar_args+=("xJf")
            if ! type -P xz &>/dev/null; then
                case "${base_distro}" in
                    debian) sys_install xz-utils ;;
                    alpine | fedora) sys_install xz ;;
                esac
            fi
            ;;
        *.zip)
            if ! type -P unzip &>/dev/null; then
                case "${base_distro}" in
                    debian | alpine | fedora) sys_install unzip ;;
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
            local components
            components=$(tr <<<"${bin_in_archive}" -cd '/' | wc -c)
            if [[ "${components}" != "0" ]]; then
                tar_args+=(--strip-components "${components}")
            fi
            tar "${tar_args[@]}" -C "${bin_dir}" "${bin_in_archive}"
        else
            case "${url}" in
                *.zip)
                    unzip tmp
                    mv "${bin_in_archive}" "${bin_dir}/"
                    ;;
                *) mv tmp "${installed_bin}" ;;
            esac
        fi
    )
    rm -rf "${tmp_dir}"

    case "${host_os}" in
        linux | macos)
            if [[ ! -x "${installed_bin}" ]]; then
                chmod +x "${installed_bin}"
            fi
            ;;
    esac
}
read_manifest() {
    local tool="$1"
    local version="$2"
    local manifest
    manifest=$(jq -r ".\"${version}\"" "${manifest_dir}/${tool}.json")
    if [[ "${manifest}" == "null" ]]; then
        bail "version '${version}' for ${tool} is not supported"
    fi
    local exact_version
    exact_version=$(jq <<<"${manifest}" -r '.version')
    if [[ "${exact_version}" == "null" ]]; then
        exact_version="${version}"
    else
        manifest=$(jq -r ".\"${exact_version}\"" "${manifest_dir}/${tool}.json")
    fi
    local download_info
    local host_platform
    case "${host_os}" in
        linux)
            # Static-linked binaries compiled for linux-musl will also work on linux-gnu systems and are
            # usually preferred over linux-gnu binaries because they can avoid glibc version issues.
            # (rustc enables statically linking for linux-musl by default, except for mips.)
            host_platform="${host_arch}_linux_musl"
            download_info=$(jq <<<"${manifest}" -r ".${host_platform}")
            if [[ "${download_info}" == "null" ]]; then
                # Even if host_env is musl, we won't issue an error here because it seems that in
                # some cases linux-gnu binaries will work on linux-musl hosts.
                # https://wiki.alpinelinux.org/wiki/Running_glibc_programs
                # TODO: However, a warning may make sense.
                host_platform="${host_arch}_linux_gnu"
                download_info=$(jq <<<"${manifest}" -r ".${host_platform}")
            elif [[ "${host_env}" == "gnu" ]]; then
                # TODO: don't hardcode tool name and use 'prefer_linux_gnu' field in base manifest.
                case "${tool}" in
                    cargo-nextest | nextest)
                        # TODO: don't hardcode required glibc version
                        required_glibc_version=2.27
                        higher_glibc_version=$(sort <<<"${required_glibc_version}"$'\n'"${host_glibc_version}" -Vu | tail -1)
                        if [[ "${higher_glibc_version}" == "${host_glibc_version}" ]]; then
                            # musl build of nextest is slow, so use glibc build if host_env is gnu.
                            # https://github.com/taiki-e/install-action/issues/13
                            host_platform="${host_arch}_linux_gnu"
                            download_info=$(jq <<<"${manifest}" -r ".${host_platform}")
                        fi
                        ;;
                esac
            fi
            ;;
        macos | windows)
            # Binaries compiled for x86_64 macOS will usually also work on aarch64 macOS.
            # Binaries compiled for x86_64 Windows will usually also work on aarch64 Windows 11+.
            host_platform="${host_arch}_${host_os}"
            download_info=$(jq <<<"${manifest}" -r ".${host_platform}")
            if [[ "${download_info}" == "null" ]] && [[ "${host_arch}" != "x86_64" ]]; then
                host_platform="x86_64_${host_os}"
                download_info=$(jq <<<"${manifest}" -r ".${host_platform}")
            fi
            ;;
        *) bail "unsupported OS type '${host_os}' for ${tool}" ;;
    esac
    if [[ "${download_info}" == "null" ]]; then
        bail "${tool}@${version} for '${host_os}' is not supported"
    fi
    checksum=$(jq <<<"${download_info}" -r '.checksum')
    url=$(jq <<<"${download_info}" -r '.url')
    if [[ "${url}" == "null" ]]; then
        local template
        template=$(jq -r ".template.${host_platform}" "${manifest_dir}/${tool}.json")
        url=$(jq <<<"${template}" -r '.url')
        url="${url//\$\{version\}/${exact_version}}"
        bin_dir=$(jq <<<"${template}" -r '.bin_dir')
        bin_dir="${bin_dir//\$\{version\}/${exact_version}}"
        bin_in_archive=$(jq <<<"${template}" -r '.bin')
        bin_in_archive="${bin_in_archive//\$\{version\}/${exact_version}}"
    else
        bin_dir=$(jq <<<"${download_info}" -r '.bin_dir')
        bin_in_archive=$(jq <<<"${download_info}" -r '.bin')
    fi
    if [[ "${bin_dir}" == "null" ]]; then
        bin_dir="${cargo_bin}"
    fi
    if [[ "${bin_in_archive}" == "null" ]]; then
        bin_in_archive="${tool}${exe}"
    fi
}
download_from_manifest() {
    read_manifest "$@"
    download_and_extract "${url}" "${checksum}" "${bin_dir}" "${bin_in_archive}"
}
install_cargo_binstall() {
    local binstall_version
    binstall_version=$(jq -r '.latest.version' "${manifest_dir}/cargo-binstall.json")
    local install_binstall='1'
    if [[ -f "${cargo_bin}/cargo-binstall${exe}" ]]; then
        if [[ "$(cargo binstall -V)" == "${binstall_version}" ]]; then
            info "cargo-binstall already installed at ${cargo_bin}/cargo-binstall${exe}"
            install_binstall=''
        else
            info "cargo-binstall already installed at ${cargo_bin}/cargo-binstall${exe}, but is not compatible version with install-action, upgrading"
            rm "${cargo_bin}/cargo-binstall${exe}"
        fi
    fi

    if [[ -n "${install_binstall}" ]]; then
        info "installing cargo-binstall"
        download_from_manifest "cargo-binstall" "latest"
        info "cargo-binstall installed at $(type -P "cargo-binstall${exe}")"
        x cargo binstall -V
    fi
}
cargo_binstall() {
    local tool="$1"
    local version="$2"

    info "install-action does not support ${tool}, fallback to cargo-binstall"

    install_cargo_binstall

    # By default, cargo-binstall enforce downloads over secure transports only.
    # As a result, http will be disabled, and it will also set
    # min tls version to be 1.2
    case "${version}" in
        latest) cargo binstall --force --no-confirm "${tool}" ;;
        *) cargo binstall --force --no-confirm --version "${version}" "${tool}" ;;
    esac
}
apt_update() {
    if type -P sudo &>/dev/null; then
        retry sudo apt-get -o Acquire::Retries=10 -qq update
    else
        retry apt-get -o Acquire::Retries=10 -qq update
    fi
    apt_updated=1
}
apt_install() {
    if [[ -z "${apt_updated:-}" ]]; then
        apt_update
    fi
    if type -P sudo &>/dev/null; then
        retry sudo apt-get -o Acquire::Retries=10 -qq -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@"
    else
        retry apt-get -o Acquire::Retries=10 -qq -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@"
    fi
}
apt_remove() {
    if type -P sudo &>/dev/null; then
        sudo apt-get -qq -o Dpkg::Use-Pty=0 remove -y "$@"
    else
        apt-get -qq -o Dpkg::Use-Pty=0 remove -y "$@"
    fi
}
snap_install() {
    if type -P sudo &>/dev/null; then
        retry sudo snap install "$@"
    else
        retry snap install "$@"
    fi
}
apk_install() {
    if type -P doas &>/dev/null; then
        doas apk add --no-cache "$@"
    else
        apk add --no-cache "$@"
    fi
}
dnf_install() {
    if type -P sudo &>/dev/null; then
        retry sudo "${dnf}" install -y "$@"
    else
        retry "${dnf}" install -y "$@"
    fi
}
sys_install() {
    case "${base_distro}" in
        debian) apt_install "$@" ;;
        alpine) apk_install "$@" ;;
        fedora) dnf_install "$@" ;;
    esac
}

if [[ $# -gt 0 ]]; then
    bail "invalid argument '$1'"
fi

export DEBIAN_FRONTEND=noninteractive
manifest_dir="$(dirname "$0")/manifests"

# Inputs
tool="${INPUT_TOOL:-}"
tools=()
if [[ -n "${tool}" ]]; then
    while read -rd,; do tools+=("${REPLY}"); done <<<"${tool},"
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
        ldd_version=$(ldd --version 2>&1 || true)
        if grep <<<"${ldd_version}" -q 'musl'; then
            host_env="musl"
        else
            host_env="gnu"
            host_glibc_version=$(grep <<<"${ldd_version}" -E "GLIBC|GNU libc" | sed "s/.* //g")
        fi
        if grep -q '^ID_LIKE=' /etc/os-release; then
            base_distro="$(grep '^ID_LIKE=' /etc/os-release | sed 's/^ID_LIKE=//')"
            case "${base_distro}" in
                *debian*) base_distro=debian ;;
                *alpine*) base_distro=alpine ;;
                *fedora*) base_distro=fedora ;;
            esac
        else
            base_distro="$(grep '^ID=' /etc/os-release | sed 's/^ID=//')"
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
    xscale | arm | armv6l | armv7l | armv8l)
        # Ignore arm for now, as we need to consider the version and whether hard-float is supported.
        # https://github.com/rust-lang/rustup/pull/593
        # https://github.com/cross-rs/cross/pull/1018
        # Does it seem only armv7l is supported?
        # https://github.com/actions/runner/blob/caec043085990710070108f375cd0aeab45e1017/src/Misc/externals.sh#L174
        bail "32-bit ARM runner is not supported yet by this action"
        ;;
    # GitHub Actions Runner supports Linux (x86_64, aarch64, arm), Windows (x86_64, aarch64),
    # and macOS (x86_64, aarch64).
    # https://github.com/actions/runner
    # https://github.com/actions/runner/blob/caec043085990710070108f375cd0aeab45e1017/.github/workflows/build.yml#L21
    # https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners#supported-architectures-and-operating-systems-for-self-hosted-runners
    # So we can assume x86_64 unless it is aarch64 or arm.
    *) host_arch="x86_64" ;;
esac

tmp_dir="${HOME}/.install-action/tmp"
cargo_bin="${CARGO_HOME:-"${HOME}/.cargo"}/bin"
if [[ ! -d "${cargo_bin}" ]]; then
    cargo_bin=/usr/local/bin
fi

if ! type -P jq &>/dev/null || ! type -P curl &>/dev/null || ! type -P tar &>/dev/null; then
    case "${base_distro}" in
        debian | alpine) sys_install ca-certificates curl jq tar ;;
        fedora)
            if [[ "${dnf}" == "yum" ]]; then
                # On RHEL7-based distribution jq requires EPEL
                sys_install ca-certificates curl tar epel-release
                sys_install jq --enablerepo=epel
            else
                sys_install ca-certificates curl jq tar
            fi
            ;;
    esac
fi

for tool in "${tools[@]}"; do
    if [[ "${tool}" == *"@"* ]]; then
        version="${tool#*@}"
        tool="${tool%@*}"
        if [[ ! "${version}" =~ ^([1-9][0-9]*(\.[0-9]+(\.[0-9]+)?)?|0\.[1-9][0-9]*(\.[0-9]+)?|^0\.0\.[0-9]+)$|^latest$ ]]; then
            if [[ ! "${version}" =~ ^([1-9][0-9]*(\.[0-9]+(\.[0-9]+)?)?|0\.[1-9][0-9]*(\.[0-9]+)?|^0\.0\.[0-9]+)(-[0-9A-Za-z\.-]+)?(\+[0-9A-Za-z\.-]+)?$|^latest$ ]]; then
                bail "install-action does not support semver operators: '${version}'"
            fi
            bail "install-action v2 does not support semver pre-release and build-metadata; please submit an issue if you need these supports again: '${version}'"
        fi
    else
        version="latest"
    fi
    info "installing ${tool}@${version}"
    case "${tool}" in
        protoc)
            read_manifest "protoc" "${version}"
            # Copying files to /usr/local/include requires sudo, so do not use it.
            bin_dir="${HOME}/.install-action/bin"
            include_dir="${HOME}/.install-action/include"
            if [[ ! -d "${bin_dir}" ]]; then
                mkdir -p "${bin_dir}"
                mkdir -p "${include_dir}"
                echo "${bin_dir}" >>"${GITHUB_PATH}"
                export PATH="${PATH}:${bin_dir}"
            fi
            if ! type -P unzip &>/dev/null; then
                case "${base_distro}" in
                    debian | alpine | fedora) sys_install unzip ;;
                esac
            fi
            mkdir -p "${tmp_dir}"
            (
                cd "${tmp_dir}"
                download_and_checksum "${url}" "${checksum}"
                unzip tmp
                mv "bin/protoc${exe}" "${bin_dir}/"
                mkdir -p "${include_dir}/"
                cp -r include/. "${include_dir}/"
                case "${host_os}" in
                    windows) bin_dir=$(sed <<<"${bin_dir}" 's/^\/c\//C:\\/') ;;
                esac
                if [[ -z "${PROTOC:-}" ]]; then
                    info "setting PROTOC environment variable"
                    echo "PROTOC=${bin_dir}/protoc${exe}" >>"${GITHUB_ENV}"
                fi
            )
            rm -rf "${tmp_dir}"
            ;;
        valgrind)
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
                cargo_binstall "${tool}" "${version}"
                echo
                continue
            fi

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

            download_from_manifest "${tool}" "${version}"
            ;;
    esac

    info "${tool} installed at $(type -P "${tool}${exe}")"
    case "${tool}" in
        cargo-udeps) x cargo udeps --help | head -1 ;; # cargo-udeps v0.1.30 does not support --version option
        cargo-valgrind) x cargo valgrind --help ;;     # cargo-valgrind v2.1.0 does not support --version option
        cargo-*) x cargo "${tool#cargo-}" --version ;;
        *) x "${tool}" --version ;;
    esac
    echo
done
