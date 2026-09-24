#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=scenario-integrity.sh disable=SC1091
source "${SCRIPT_DIR}/scenario-integrity.sh"

usage() {
  printf 'Usage: %s --context radar-lab\n' "$0" >&2
  exit 2
}

pause_for_presenter() {
  printf '\n%s\n' "$1"
  printf 'Press Enter to continue... '
  IFS= read -r _reply
}

[[ $# -eq 2 && "$1" == "--context" ]] || usage
assert_context "$2"
[[ -t 0 ]] || die "the visual rehearsal requires an interactive terminal"
for command_name in curl git go jq kubectl minikube sha256sum stat; do
  require_command "${command_name}"
done
[[ -z "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=normal)" ]] || \
  die "working tree must be clean before the visual rehearsal"

token_file="${RADAR_TOKEN_FILE}"
[[ -s "${token_file}" && ! -L "${token_file}" ]] || \
  die "RADAR token file is missing or unsafe; finish lab setup first"
[[ "$(stat --format '%a' "${token_file}")" == "600" ]] || \
  die "RADAR token file must have mode 0600"

temporary_directory="$(mktemp --directory)"
scanner_binary="${temporary_directory}/radar"
application_snapshot="${temporary_directory}/application.json"
port_forward_log="${temporary_directory}/port-forward.log"
drift_injected=false
frozen_revision=""

cleanup() {
  local exit_code=$?
  trap - EXIT
  stop_argocd_forward
  if [[ "${drift_injected}" == true && -n "${frozen_revision}" ]]; then
    printf '\nRestoring the declared baseline after an interrupted rehearsal...\n' >&2
    if ! reset_baseline "${frozen_revision}" "${temporary_directory}"; then
      printf 'Automatic reset failed; run verify-baseline.sh before another demonstration.\n' >&2
    fi
  fi
  rm -rf -- "${temporary_directory}"
  exit "${exit_code}"
}
trap cleanup EXIT

verify_declared_baseline
kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output json >"${application_snapshot}"
frozen_revision="$(jq --raw-output '.spec.source.targetRevision' "${application_snapshot}")"
source_revision="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
validate_application_snapshot "${application_snapshot}" "${source_revision}" Synced || \
  die "Argo CD is not synchronized to the clean source commit"
[[ "${frozen_revision}" == "${source_revision}" ]] || die "the lab revision does not match the source checkout"

(cd "${REPO_ROOT}" && go build -trimpath -o "${scanner_binary}" ./cmd/radar)
pause_for_presenter "Stage 1 — show the radar-lab Application as Synced and Healthy in Argo CD."

kube --namespace "${RADAR_NAMESPACE}" patch deployment radar-demo --type strategic \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"radar-demo","securityContext":{"allowPrivilegeEscalation":true,"privileged":true}}]}}}}' \
  >/dev/null
drift_injected=true
refresh_application
wait_for_application_value '{.status.sync.status}' OutOfSync 300s

pause_for_presenter "Stage 2 — refresh Argo CD and show the Application as OutOfSync. Open the Deployment diff and point to privileged: true."

start_argocd_forward "${port_forward_log}"
radar_token="$(tr -d '\r\n' <"${token_file}")"
[[ -n "${radar_token}" ]] || die "RADAR token file is empty"
printf '\nStage 3 — RADAR classifies the same field-level drift:\n\n'
ARGOCD_SERVER="${ARGOCD_FORWARD_BASE_URL}" \
ARGOCD_AUTH_TOKEN="${radar_token}" \
RADAR_POLICY_PATH="${REPO_ROOT}/policies/risk.rego" \
  "${scanner_binary}" scan --app "${RADAR_APP}" --output table
unset radar_token
stop_argocd_forward

pause_for_presenter "Stage 4 — contrast Argo CD's synchronization state with RADAR's explainable CRITICAL decision, then continue to reset."

reset_baseline "${frozen_revision}" "${temporary_directory}"
drift_injected=false
printf '\nStage 5 — baseline restored and verified. Refresh Argo CD to show Synced and Healthy again.\n'
