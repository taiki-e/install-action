#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'

rx() {
  (
    set -x
    "$@"
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
  printf '::error::%s\n' "$*"
  exit 1
}
warn() {
  printf '::warning::%s\n' "$*"
}
info() {
  printf >&2 'info: %s\n' "$*"
}
normalize_comma_or_space_separated() {
  # Normalize whitespace characters into space because it's hard to handle single input contains lines with POSIX sed alone.
  local list="${1//[$'\r\n\t']/ }"
  if [[ "${list}" == *","* ]]; then
    # If a comma is contained, consider it is a comma-separated list.
    # Drop leading and trailing whitespaces in each element.
    sed -E 's/ *, */,/g; s/^.//' <<<",${list},"
  else
    # Otherwise, consider it is a whitespace-separated list.
    # Convert whitespace characters into comma.
    sed -E 's/ +/,/g; s/^.//' <<<" ${list} "
  fi
}
_sudo() {
  if type -P sudo >/dev/null; then
    sudo "$@"
  else
    "$@"
  fi
}
download_and_checksum() {
  local url="$1"
  local checksum="$2"
  if [[ -z "${enable_checksum}" ]]; then
    checksum=''
  fi
  info "downloading ${url}"
  retry curl --proto '=https' --tlsv1.2 -fsSL --retry 10 "${url}" -o tmp
  if [[ -n "${checksum}" ]]; then
    info "verifying sha256 checksum for $(basename -- "${url}")"
    if type -P sha256sum >/dev/null; then
      sha256sum -c - >/dev/null <<<"${checksum} *tmp"
    elif type -P shasum >/dev/null; then
      # GitHub-hosted macOS runner does not install GNU Coreutils by default.
      # https://github.com/actions/runner-images/issues/90
      shasum -a 256 -c - >/dev/null <<<"${checksum} *tmp"
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
        installed_bin+=("${bin_dir}/$(basename -- "${tmp}")")
      done
      ;;
  esac

  local tar_args=()
  case "${url}" in
    *.tar.gz | *.tgz)
      tar_args+=('xzf')
      if ! type -P gzip >/dev/null; then
        case "${base_distro}" in
          debian | fedora | suse | arch | alpine)
            printf '::group::Install packages required for installation (gzip)\n'
            sys_install gzip
            printf '::endgroup::\n'
            ;;
        esac
      fi
      ;;
    *.gz)
      if ! type -P gzip >/dev/null; then
        case "${base_distro}" in
          debian | fedora | suse | arch | alpine)
            printf '::group::Install packages required for installation (gzip)\n'
            sys_install gzip
            printf '::endgroup::\n'
            ;;
        esac
      fi
      ;;
    *.tar.bz2 | *.tbz2)
      tar_args+=('xjf')
      if ! type -P bzip2 >/dev/null; then
        case "${base_distro}" in
          debian | fedora | suse | arch | alpine)
            printf '::group::Install packages required for installation (bzip2)\n'
            sys_install bzip2
            printf '::endgroup::\n'
            ;;
        esac
      fi
      ;;
    *.tar.xz | *.txz)
      tar_args+=('xJf')
      if ! type -P xz >/dev/null; then
        case "${base_distro}" in
          debian)
            printf '::group::Install packages required for installation (xz-utils)\n'
            sys_install xz-utils
            printf '::endgroup::\n'
            ;;
          fedora | suse | arch | alpine)
            printf '::group::Install packages required for installation (xz)\n'
            sys_install xz
            printf '::endgroup::\n'
            ;;
        esac
      fi
      ;;
    *.zip)
      if ! type -P unzip >/dev/null; then
        case "${base_distro}" in
          debian | fedora | suse | arch | alpine)
            printf '::group::Install packages required for installation (unzip)\n'
            sys_install unzip
            printf '::endgroup::\n'
            ;;
        esac
      fi
      ;;
  esac

  mkdir -p -- "${tmp_dir}"
  (
    cd -- "${tmp_dir}"
    download_and_checksum "${url}" "${checksum}"
    if [[ ${#tar_args[@]} -gt 0 ]]; then
      tar_args+=("tmp")
      tar "${tar_args[@]}"
      for tmp in "${bin_in_archive[@]}"; do
        case "${tool}" in
          editorconfig-checker) mv -- "${tmp}" "${bin_dir}/${tool}${exe}" ;;
          *) mv -- "${tmp}" "${bin_dir}/" ;;
        esac
      done
    else
      case "${url}" in
        *.zip)
          unzip -q tmp "${bin_in_archive#\./}"
          for tmp in "${bin_in_archive[@]}"; do
            case "${tool}" in
              editorconfig-checker) mv -- "${tmp}" "${bin_dir}/${tool}${exe}" ;;
              *) mv -- "${tmp}" "${bin_dir}/" ;;
            esac
          done
          ;;
        *.gz)
          mv -- tmp "${bin_in_archive#\./}.gz"
          gzip -d "${bin_in_archive#\./}.gz"
          for tmp in "${bin_in_archive[@]}"; do
            mv -- "${tmp}" "${bin_dir}/"
          done
          ;;
        *)
          for tmp in "${installed_bin[@]}"; do
            mv -- tmp "${tmp}"
          done
          ;;
      esac
    fi
  )
  rm -rf -- "${tmp_dir}"

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
  rust_crate=$(jq -r '.rust_crate' "${manifest_dir}/${tool}.json")
  manifest=$(jq -r ".[\"${version}\"]" "${manifest_dir}/${tool}.json")
  if [[ "${manifest}" == "null" ]]; then
    download_info="null"
    return 0
  fi
  exact_version=$(jq -r '.version' <<<"${manifest}")
  if [[ "${exact_version}" == "null" ]]; then
    exact_version="${version}"
  else
    manifest=$(jq -r ".[\"${exact_version}\"]" "${manifest_dir}/${tool}.json")
    if [[ "${rust_crate}" != "null" ]]; then
      # TODO: don't hardcode tool name and use 'immediate_yank_reflection' field in base manifest.
      case "${tool}" in
        cargo-nextest)
          crate_info=$(curl -v --user-agent "${ACTION_USER_AGENT}" --proto '=https' --tlsv1.2 -fsSL --retry 10 "https://crates.io/api/v1/crates/${rust_crate}" || true)
          if [[ -n "${crate_info}" ]]; then
            while true; do
              yanked=$(jq -r ".versions[] | select(.num == \"${exact_version}\") | .yanked" <<<"${crate_info}")
              if [[ "${yanked}" != "true" ]]; then
                break
              fi
              previous_stable_version=$(jq -r '.previous_stable_version' <<<"${manifest}")
              if [[ "${previous_stable_version}" == "null" ]]; then
                break
              fi
              info "${tool}@${exact_version} is yanked; downgrade to ${previous_stable_version}"
              exact_version="${previous_stable_version}"
              manifest=$(jq -r ".[\"${exact_version}\"]" "${manifest_dir}/${tool}.json")
            done
          fi
          ;;
      esac
    fi
  fi

  case "${host_os}" in
    linux)
      # Static-linked binaries compiled for linux-musl will also work on linux-gnu systems and are
      # usually preferred over linux-gnu binaries because they can avoid glibc version issues.
      # (rustc enables statically linking for linux-musl by default, except for mips.)
      host_platform="${host_arch}_linux_musl"
      download_info=$(jq -r ".${host_platform}" <<<"${manifest}")
      if [[ "${download_info}" == "null" ]]; then
        # Even if host_env is musl, we won't issue an error here because it seems that in
        # some cases linux-gnu binaries will work on linux-musl hosts.
        # https://wiki.alpinelinux.org/wiki/Running_glibc_programs
        # TODO: However, a warning may make sense.
        host_platform="${host_arch}_linux_gnu"
        download_info=$(jq -r ".${host_platform}" <<<"${manifest}")
      elif [[ "${host_env}" == "gnu" ]]; then
        # TODO: don't hardcode tool name and use 'prefer_linux_gnu' field in base manifest.
        case "${tool}" in
          cargo-nextest)
            # TODO: don't hardcode required glibc version
            required_glibc_version=2.27
            higher_glibc_version=$(LC_ALL=C sort -Vu <<<"${required_glibc_version}"$'\n'"${host_glibc_version}" | tail -1)
            if [[ "${higher_glibc_version}" == "${host_glibc_version}" ]]; then
              # musl build of nextest is slow, so use glibc build if host_env is gnu.
              # https://github.com/taiki-e/install-action/issues/13
              host_platform="${host_arch}_linux_gnu"
              download_info=$(jq -r ".${host_platform}" <<<"${manifest}")
            fi
            ;;
        esac
      fi
      ;;
    macos | windows)
      # Binaries compiled for x86_64 macOS will usually also work on AArch64 macOS.
      # Binaries compiled for x86_64 Windows will usually also work on AArch64 Windows 11+.
      host_platform="${host_arch}_${host_os}"
      download_info=$(jq -r ".${host_platform}" <<<"${manifest}")
      if [[ "${download_info}" == "null" ]] && [[ "${host_arch}" != "x86_64" ]]; then
        host_platform="x86_64_${host_os}"
        download_info=$(jq -r ".${host_platform}" <<<"${manifest}")
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
  checksum=$(jq -r '.checksum' <<<"${download_info}")
  url=$(jq -r '.url' <<<"${download_info}")
  local tmp
  bin_in_archive=()
  if [[ "${url}" == "null" ]]; then
    local template
    template=$(jq -c ".template.${host_platform}" "${manifest_dir}/${tool}.json")
    template="${template//\$\{version\}/${exact_version}}"
    url=$(jq -r '.url' <<<"${template}")
    tmp=$(jq -r '.bin' <<<"${template}")
    if [[ "${tmp}" == *"["* ]]; then
      # shellcheck disable=SC2207
      bin_in_archive=($(jq -r '.bin[]' <<<"${template}"))
    fi
  else
    tmp=$(jq -r '.bin' <<<"${download_info}")
    if [[ "${tmp}" == *"["* ]]; then
      # shellcheck disable=SC2207
      bin_in_archive=($(jq -r '.bin[]' <<<"${download_info}"))
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
    # Moving files to /usr/local/bin requires sudo in some environments, so do not use it: https://github.com/taiki-e/install-action/issues/543
    bin_dir="${install_action_dir}/bin"
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
  binstall_version=$(jq -r '.latest.version' "${manifest_dir}/cargo-binstall.json")
  local install_binstall=1
  _binstall_version=$("cargo-binstall${exe}" binstall -V 2>/dev/null || true)
  if [[ -n "${_binstall_version}" ]]; then
    if [[ "${_binstall_version}" == "${binstall_version}" ]]; then
      info "cargo-binstall already installed at ${cargo_bin}/cargo-binstall${exe}"
      install_binstall=''
    else
      info "cargo-binstall already installed at ${cargo_bin}/cargo-binstall${exe}, but is not compatible version with install-action, upgrading"
      rm -- "${cargo_bin}/cargo-binstall${exe}"
    fi
  fi

  if [[ -n "${install_binstall}" ]]; then
    info "installing cargo-binstall@latest (${binstall_version})"
    download_from_manifest "cargo-binstall" "latest"
    installed_at=$(type -P "cargo-binstall${exe}" || true)
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
  if type -P sudo >/dev/null; then
    retry sudo apk --no-cache add "$@"
  elif type -P doas >/dev/null; then
    retry doas apk --no-cache add "$@"
  else
    retry apk --no-cache add "$@"
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
    mkdir -p -- "${bin_dir}"
    export PATH="${PATH}:${bin_dir}"
    local _bin_dir
    _bin_dir=$(canonicalize_windows_path "${bin_dir}")
    # TODO: avoid this when already added
    info "adding '${_bin_dir}' to PATH"
    printf '%s\n' "${_bin_dir}" >>"${GITHUB_PATH}"
  fi
}
canonicalize_windows_path() {
  case "${host_os}" in
    windows) sed -E 's/^\/cygdrive\//\//; s/^\/c\//C:\\/; s/\//\\/g' <<<"$1" ;;
    *) printf '%s\n' "$1" ;;
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
manifest_dir="$(dirname -- "$0")/manifests"

# Inputs
tool="${INPUT_TOOL:-}"
tools=()
if [[ -n "${tool}" ]]; then
  while read -rd,; do
    tools+=("${REPLY}")
  done < <(normalize_comma_or_space_separated "${tool}")
fi
if [[ ${#tools[@]} -eq 0 ]]; then
  warn "no tool specified; this could be caused by a dependabot bug where @<tool_name> tags on this action are replaced by @<version> tags"
  # Exit with 0 for backward compatibility.
  # TODO: We want to reject it in the next major release.
  exit 0
fi

enable_checksum="${INPUT_CHECKSUM:-}"
case "${enable_checksum}" in
  true) ;;
  false) enable_checksum='' ;;
  *) bail "'checksum' input option must be 'true' or 'false': '${enable_checksum}'" ;;
esac

fallback="${INPUT_FALLBACK:-}"
case "${fallback}" in
  none | cargo-binstall | cargo-install) ;;
  *) bail "'fallback' input option must be 'none', 'cargo-binstall', or 'cargo-install': '${fallback}'" ;;
esac

# Refs: https://github.com/rust-lang/rustup/blob/HEAD/rustup-init.sh
base_distro=''
exe=''
case "$(uname -s)" in
  Linux)
    host_os=linux
    ldd_version=$(ldd --version 2>&1 || true)
    if grep -Fq musl <<<"${ldd_version}"; then
      host_env=musl
    else
      host_env=gnu
      host_glibc_version=$(grep -E "GLIBC|GNU libc" <<<"${ldd_version}" | sed -E "s/.* //g")
    fi
    if [[ -e /etc/os-release ]]; then
      if grep -Eq '^ID_LIKE=' /etc/os-release; then
        base_distro=$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2)
        case "${base_distro}" in
          *debian*) base_distro=debian ;;
          *fedora*) base_distro=fedora ;;
          *suse*) base_distro=suse ;;
          *arch*) base_distro=arch ;;
          *alpine*) base_distro=alpine ;;
        esac
      else
        base_distro=$(grep -E '^ID=' /etc/os-release | cut -d= -f2)
      fi
      base_distro="${base_distro//\"/}"
    elif [[ -e /etc/redhat-release ]]; then
      # /etc/os-release is available on RHEL/CentOS 7+
      base_distro=fedora
    elif [[ -e /etc/debian_version ]]; then
      # /etc/os-release is available on Debian 7+
      base_distro=debian
    fi
    case "${base_distro}" in
      fedora)
        dnf=dnf
        if ! type -P dnf >/dev/null; then
          if type -P microdnf >/dev/null; then
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
    exe=.exe
    ;;
  *) bail "unrecognized OS type '$(uname -s)'" ;;
esac
# NB: Sync with tools/ci/tool-list.sh.
case "$(uname -m)" in
  aarch64 | arm64) host_arch=aarch64 ;;
  # Ignore Arm for now, as we need to consider the version and whether hard-float is supported.
  # https://github.com/rust-lang/rustup/pull/593
  # https://github.com/cross-rs/cross/pull/1018
  # Does it seem only armv7l+ is supported?
  # https://github.com/actions/runner/blob/v2.321.0/src/Misc/externals.sh#L178
  # https://github.com/actions/runner/issues/688
  xscale | arm | armv*l) bail "32-bit Arm runner is not supported yet by this action; if you need support for this platform, please submit an issue at <https://github.com/taiki-e/install-action>" ;;
  ppc64le) host_arch=powerpc64le ;;
  riscv64) host_arch=riscv64 ;;
  s390x) host_arch=s390x ;;
  # Very few tools provide prebuilt binaries for these.
  # TODO: fallback to `cargo install`? (binstall fallback is not good idea here as cargo-binstall doesn't provide prebuilt binaries for these.)
  loongarch64 | mips | mips64 | ppc | ppc64 | sun4v) bail "$(uname -m) runner is not supported yet by this action; if you need support for this platform, please submit an issue at <https://github.com/taiki-e/install-action>" ;;
  # GitHub Actions Runner supports x86_64/AArch64/Arm Linux, x86_64/AArch64 Windows,
  # and x86_64/AArch64 macOS.
  # https://github.com/actions/runner/blob/v2.321.0/.github/workflows/build.yml#L21
  # https://docs.github.com/en/actions/reference/runners/self-hosted-runners#supported-processor-architectures
  # And IBM provides runners for powerpc64le/s390x Linux.
  # https://github.com/IBM/actionspz
  # So we can assume x86_64 unless it has a known non-x86_64 uname -m result.
  # TODO: uname -m on windows-11-arm returns "x86_64"
  *) host_arch=x86_64 ;;
esac
info "host platform: ${host_arch}_${host_os}"

home="${HOME:-}"
if [[ -z "${home}" ]]; then
  # https://github.com/IBM/actionspz/issues/30
  home=$(realpath ~)
  export HOME="${home}"
fi
if [[ "${host_os}" == "windows" ]]; then
  if [[ "${home}" == "/home/"* ]]; then
    if [[ -d "${home/\/home\///c/Users/}" ]]; then
      # MSYS2 https://github.com/taiki-e/install-action/pull/518#issuecomment-2160736760
      home="${home/\/home\///c/Users/}"
    elif [[ -d "${home/\/home\///cygdrive/c/Users/}" ]]; then
      # Cygwin https://github.com/taiki-e/install-action/issues/224#issuecomment-1720196288
      home="${home/\/home\///cygdrive/c/Users/}"
    else
      warn "\$HOME starting /home/ (${home}) on Windows bash is usually fake path, this may cause installation issue"
    fi
  fi
fi
install_action_dir="${home}/.install-action"
tmp_dir="${install_action_dir}/tmp"
cargo_bin="${CARGO_HOME:-"${home}/.cargo"}/bin"
# If $CARGO_HOME does not exist, or cargo installed outside of $CARGO_HOME/bin
# is used ($CARGO_HOME/bin is most likely not included in the PATH), fallback to
# $install_action_dir/bin.
if [[ "${host_os}" == "windows" ]]; then
  if type -P cargo >/dev/null; then
    info "cargo is located at $(type -P cargo)"
    cargo_bin=$(dirname -- "$(type -P cargo)")
  else
    cargo_bin="${install_action_dir}/bin"
  fi
elif [[ ! -e "${cargo_bin}" ]] || [[ "$(type -P cargo || true)" != "${cargo_bin}/cargo"* ]]; then
  if type -P cargo >/dev/null; then
    info "cargo is located at $(type -P cargo)"
  fi
  # Moving files to /usr/local/bin requires sudo in some environments, so do not use it: https://github.com/taiki-e/install-action/issues/543
  cargo_bin="${install_action_dir}/bin"
fi

case "${host_os}" in
  linux)
    if ! type -P jq >/dev/null || ! type -P curl >/dev/null || ! type -P tar >/dev/null; then
      case "${base_distro}" in
        debian | fedora | suse | arch | alpine)
          printf '::group::Install packages required for installation (jq, curl, and/or tar)\n'
          sys_packages=()
          if ! type -P curl >/dev/null; then
            sys_packages+=(ca-certificates curl)
          fi
          if ! type -P tar >/dev/null; then
            sys_packages+=(tar)
          fi
          if [[ "${dnf:-}" == "yum" ]]; then
            # On RHEL7-based distribution jq requires EPEL
            if ! type -P jq >/dev/null; then
              sys_packages+=(epel-release)
              sys_install "${sys_packages[@]}"
              sys_install jq --enablerepo=epel
            else
              sys_install "${sys_packages[@]}"
            fi
          else
            if ! type -P jq >/dev/null; then
              # https://github.com/taiki-e/install-action/issues/521
              if [[ "${base_distro}" == "arch" ]]; then
                sys_packages+=(glibc)
              fi
              sys_packages+=(jq)
            fi
            sys_install "${sys_packages[@]}"
          fi
          printf '::endgroup::\n'
          ;;
        *) warn "install-action requires at least jq and curl on non-Debian/Fedora/SUSE/Arch/Alpine-based Linux" ;;
      esac
    fi
    ;;
  macos)
    if ! type -P jq >/dev/null || ! type -P curl >/dev/null; then
      warn "install-action requires at least jq and curl on macOS"
    fi
    ;;
  windows)
    if ! type -P curl >/dev/null; then
      warn "install-action requires at least curl on Windows"
    fi
    if [[ -f "${install_action_dir}/jq/bin/jq.exe" ]]; then
      jq() { "${install_action_dir}/jq/bin/jq.exe" -b "$@"; }
    elif type -P jq >/dev/null; then
      # https://github.com/jqlang/jq/issues/1854
      _tmp=$(jq -r .a <<<'{}')
      if [[ "${_tmp}" != "null" ]]; then
        _tmp=$(jq -b -r .a 2>/dev/null <<<'{}' || true)
        if [[ "${_tmp}" == "null" ]]; then
          jq() { command jq -b "$@"; }
        else
          jq() { command jq "$@" | tr -d '\r'; }
        fi
      fi
    else
      printf '::group::Install packages required for installation (jq)\n'
      mkdir -p -- "${install_action_dir}/jq/bin"
      url='https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-windows-amd64.exe'
      checksum='23cb60a1354eed6bcc8d9b9735e8c7b388cd1fdcb75726b93bc299ef22dd9334'
      (
        cd -- "${install_action_dir}/jq/bin"
        download_and_checksum "${url}" "${checksum}"
        mv -- tmp jq.exe
      )
      printf '::endgroup::\n'
      jq() { "${install_action_dir}/jq/bin/jq.exe" -b "$@"; }
    fi
    ;;
  *) bail "unsupported host OS '${host_os}'" ;;
esac

unsupported_tools=()
for tool in "${tools[@]}"; do
  if [[ "${tool}" == *"@"* ]]; then
    version="${tool#*@}"
    tool="${tool%@*}"
    if [[ ! "${version}" =~ ^([1-9][0-9]*(\.[0-9]+(\.[0-9]+)?)?|0\.[1-9][0-9]*(\.[0-9]+)?|^0\.0\.[0-9]+)(-[0-9A-Za-z\.-]+)?$|^latest$ ]]; then
      if [[ ! "${version}" =~ ^([1-9][0-9]*(\.[0-9]+(\.[0-9]+)?)?|0\.[1-9][0-9]*(\.[0-9]+)?|^0\.0\.[0-9]+)(-[0-9A-Za-z\.-]+)?(\+[0-9A-Za-z\.-]+)?$|^latest$ ]]; then
        bail "install-action does not support semver operators: '${version}'"
      fi
      bail "install-action v2 does not support semver build-metadata: '${version}'; if you need these supports again, please submit an issue at <https://github.com/taiki-e/install-action>"
    fi
  else
    version=latest
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
        mkdir -p -- "${include_dir}"
      fi
      if ! type -P unzip >/dev/null; then
        case "${base_distro}" in
          debian | fedora | suse | arch | alpine)
            printf '::group::Install packages required for installation (unzip)\n'
            sys_install unzip
            printf '::endgroup::\n'
            ;;
        esac
      fi
      mkdir -p -- "${tmp_dir}"
      (
        cd -- "${tmp_dir}"
        download_and_checksum "${url}" "${checksum}"
        unzip -q tmp
        mv -- "bin/protoc${exe}" "${bin_dir}/"
        mkdir -p -- "${include_dir}/"
        cp -r -- include/. "${include_dir}/"
        if [[ -z "${PROTOC:-}" ]]; then
          _bin_dir=$(canonicalize_windows_path "${bin_dir}")
          info "setting PROTOC environment variable to '${_bin_dir}/protoc${exe}'"
          printf '%s\n' "PROTOC=${_bin_dir}/protoc${exe}" >>"${GITHUB_ENV}"
        fi
      )
      rm -rf -- "${tmp_dir}"
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
        macos | windows) bail "${tool} for non-Linux is not supported yet by this action" ;;
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
      printf '\n'
      continue
      ;;
    *)
      # Handle aliases.
      # NB: Update alias list in tools/publish.rs and tool input option in test-alias in .github/workflows/ci.yml.
      # TODO(codegen): auto-detect cases where crate name and tool name are different.
      case "${tool}" in
        nextest) tool=cargo-nextest ;;
        taplo-cli | typos-cli | wasm-bindgen-cli | wasmtime-cli) tool="${tool%-cli}" ;;
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
        if [[ "${rust_crate}" == "null" ]] || [[ "${fallback}" == "none" ]]; then
          bail "${tool}@${version} for '${host_arch}_${host_os}' is not supported"
        fi
        warn "${tool}@${version} for '${host_arch}_${host_os}' is not supported; fallback to ${fallback}"
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
              if type -P shellcheck >/dev/null; then
                apt_remove -y shellcheck
              fi
              ;;
          esac
          ;;
        cyclonedx)
          case "${host_os}" in
            linux)
              apt_install libicu-dev
              ;;
          esac
          ;;
      esac

      download_from_download_info "${tool}" "${version}"
      ;;
  esac

  tool_bin_stems=()
  for tool_bin in "${installed_bin[@]}"; do
    tool_bin=$(basename -- "${tool_bin}")
    tool_bin_stem="${tool_bin%.exe}"
    installed_at=$(type -P "${tool_bin}" || true)
    if [[ -z "${installed_at}" ]]; then
      tool_bin="${tool_bin_stem}"
      installed_at=$(type -P "${tool_bin}" || true)
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
      # wait-for-them up to 0.4.0 does not support --version flag.
      biome | cargo-machete | wait-for-them) rx "${tool_bin_stem}" --version || true ;;
      # these packages support neither --version nor --help flag.
      cargo-auditable | cargo-careful | wasm-bindgen-test-runner) ;;
      # wasm2es6js does not support --version flag and --help flag doesn't contains version info.
      wasm2es6js) ;;
      # iai-callgrind-runner --version works only with iai-callgrind in nearby Cargo.toml.
      iai-callgrind-runner) ;;
      # cargo-zigbuild/cargo-insta has no --version flag on `cargo $tool_bin_stem` subcommand.
      cargo-zigbuild | cargo-insta) rx "${tool_bin_stem}" --version ;;
      # deepsource has version command instead of --version flag.
      deepsource | vacuum) rx "${tool_bin_stem}" version ;;
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
  printf '\n'
done

if [[ ${#unsupported_tools[@]} -gt 0 ]]; then
  IFS=','
  case "${fallback}" in
    none) bail "install-action does not support ${unsupported_tools[*]} (fallback is disabled by 'fallback: none' input option)" ;;
    cargo-binstall)
      case "${host_arch}" in
        x86_64 | aarch64) ;;
        *)
          info "cargo-binstall does not provide prebuilt binaries for this platform (${host_arch}); use 'cargo-install' fallback instead"
          fallback=cargo-install
          ;;
      esac
      ;;
  esac
  info "install-action does not support ${unsupported_tools[*]}; fallback to ${fallback}"
  IFS=$'\n\t'
  case "${fallback}" in
    cargo-binstall)
      install_cargo_binstall
      if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ -n "${DEFAULT_GITHUB_TOKEN:-}" ]]; then
        export GITHUB_TOKEN="${DEFAULT_GITHUB_TOKEN}"
      fi
      # By default, cargo-binstall enforce downloads over secure transports only.
      # As a result, http will be disabled, and it will also set
      # min tls version to be 1.2
      cargo-binstall binstall --force --no-confirm --locked "${unsupported_tools[@]}"
      if ! type -P cargo >/dev/null; then
        _bin_dir=$(canonicalize_windows_path "${home}/.cargo/bin")
        # TODO: avoid this when already added
        info "adding '${_bin_dir}' to PATH"
        printf '%s\n' "${_bin_dir}" >>"${GITHUB_PATH}"
      fi
      ;;
    cargo-install)
      cargo install --locked "${unsupported_tools[@]}"
      ;;
    *) bail "unhandled fallback ${fallback}" ;;
  esac
fi
