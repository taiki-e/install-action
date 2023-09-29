#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# Update manifests
#
# USAGE:
#    ./tools/manifest.sh [PACKAGE [VERSION_REQ]]

if [[ $# -gt 0 ]]; then
    cargo run --release -p install-action-internal-codegen -- "$@"
    exit 0
fi

for manifest in tools/codegen/base/*.json; do
    package=$(basename "${manifest%.*}")
    cargo run --release -p install-action-internal-codegen -- "${package}" latest
done
