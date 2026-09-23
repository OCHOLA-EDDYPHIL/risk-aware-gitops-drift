#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

[[ "${CODESPACES:-false}" == "true" ]] || die "Codespaces compatibility capture must run inside GitHub Codespaces"

exec "${SCRIPT_DIR}/capture-environment.sh" --provider "GitHub Codespaces" "$@"
