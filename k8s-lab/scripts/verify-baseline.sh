#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'Usage: %s --context radar-lab\n' "$0" >&2
  exit 2
}

[[ $# -eq 2 && "$1" == "--context" ]] || usage
assert_context "$2"
require_command kubectl
require_command minikube
require_command python3

minikube status --profile "${RADAR_PROFILE}" >/dev/null 2>&1 || die "Minikube profile ${RADAR_PROFILE} is not running"
refresh_application
wait_for_synced_healthy 300s
rendered_baseline="$(mktemp)"
trap 'rm -f "${rendered_baseline}"' EXIT
kube kustomize "${BASELINE_DIR}" >"${rendered_baseline}"
python3 "${SCRIPT_DIR}/verify-baseline.py" \
  --context "${RADAR_CONTEXT}" --rendered "${rendered_baseline}" || \
  die "live resources differ from the controlled baseline"
kube --namespace "${RADAR_NAMESPACE}" wait deployment/radar-demo --for=condition=Available --timeout=180s >/dev/null

printf 'RADAR baseline is Synced, Healthy, and equal to the committed manifests.\n'
