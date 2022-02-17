#!/bin/bash
# shellcheck disable=SC2046
set -euo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# USAGE:
#    ./tools/tidy.sh
#
# Note: This script requires the following tools:
# - shfmt
# - prettier
# - shellcheck

x() {
    local cmd="$1"
    shift
    if [[ -n "${verbose:-}" ]]; then
        (
            set -x
            "${cmd}" "$@"
        )
    else
        "${cmd}" "$@"
    fi
}
warn() {
    echo >&2 "warning: $*"
}

if [[ "${1:-}" == "-v" ]]; then
    shift
    verbose=1
fi
if [[ $# -gt 0 ]]; then
    cat <<EOF
USAGE:
    $0 [-v]
EOF
    exit 1
fi

prettier=prettier
if type -P npm &>/dev/null && type -P "$(npm bin)/prettier" &>/dev/null; then
    prettier="$(npm bin)/prettier"
fi

if type -P shfmt &>/dev/null; then
    x shfmt -l -w $(git ls-files '*.sh')
else
    warn "'shfmt' is not installed"
fi
if type -P "${prettier}" &>/dev/null; then
    x "${prettier}" -l -w $(git ls-files '*.yml')
    x "${prettier}" -l -w $(git ls-files '*.js')
else
    warn "'prettier' is not installed"
fi
if type -P shellcheck &>/dev/null; then
    x shellcheck $(git ls-files '*.sh')
else
    warn "'shellcheck' is not installed"
fi
