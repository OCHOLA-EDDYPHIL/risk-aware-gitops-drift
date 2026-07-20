#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'Usage: %s --context radar-lab --confirm radar-lab\n' "$0" >&2
  exit 2
}

[[ $# -eq 4 && "$1" == "--context" && "$3" == "--confirm" ]] || usage
assert_context "$2"
[[ "$4" == "${RADAR_PROFILE}" ]] || die "confirmation must be exactly ${RADAR_PROFILE}"
require_command minikube

minikube delete --profile "${RADAR_PROFILE}"
rm -f "${RADAR_TOKEN_FILE:-${REPO_ROOT}/.radar-lab-token}"
printf 'Deleted only Minikube profile %s and the local RADAR token file.\n' "${RADAR_PROFILE}"
