#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# Update markdown
#
# USAGE:
#    ./tools/update-markdown.sh [PACKAGE [VERSION_REQ]]

cargo run --manifest-path tools/codegen/Cargo.toml --bin generate-tools-markdown --release >TOOLS.md
