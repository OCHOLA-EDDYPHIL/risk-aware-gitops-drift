#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'Usage: %s --context radar-lab --scenario <name> --repetition <positive-integer> [--output-dir <path>]\n' "$0" >&2
  exit 2
}

requested_context=""
scenario=""
repetition=""
output_root="${REPO_ROOT}/k8s-lab/evidence"

while (($# > 0)); do
  case "$1" in
    --context)
      (($# >= 2)) || usage
      requested_context="$2"
      shift 2
      ;;
    --scenario)
      (($# >= 2)) || usage
      scenario="$2"
      shift 2
      ;;
    --repetition)
      (($# >= 2)) || usage
      repetition="$2"
      shift 2
      ;;
    --output-dir)
      (($# >= 2)) || usage
      output_root="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

assert_context "${requested_context}"
[[ "${repetition}" =~ ^[1-9][0-9]*$ ]] || die "--repetition must be a positive integer"

expected_rule=""
expected_severity=""
case "${scenario}" in
  rbac-wildcard)
    expected_rule="RADAR-RBAC-WILDCARD"
    expected_severity="CRITICAL"
    ;;
  networkpolicy-removal)
    expected_rule="RADAR-NETPOL-REMOVED"
    expected_severity="HIGH"
    ;;
  privileged-container)
    expected_rule="RADAR-WORKLOAD-PRIVILEGED"
    expected_severity="CRITICAL"
    ;;
  hostpath-addition)
    expected_rule="RADAR-VOLUME-HOSTPATH"
    expected_severity="HIGH"
    ;;
  service-exposure)
    expected_rule="RADAR-SERVICE-EXPOSURE"
    expected_severity="HIGH"
    ;;
  unsafe-image-tag)
    expected_rule="RADAR-IMAGE-LATEST"
    expected_severity="MEDIUM"
    ;;
  secret-reference)
    expected_rule="RADAR-SECRET-REFERENCE"
    expected_severity="MEDIUM"
    ;;
  metadata-only)
    expected_rule="RADAR-METADATA-ONLY"
    expected_severity="LOW"
    ;;
  *) die "unknown scenario: ${scenario:-empty}" ;;
esac

for command_name in kubectl minikube jq curl go; do
  require_command "${command_name}"
done

"${SCRIPT_DIR}/verify-baseline.sh" --context "${RADAR_CONTEXT}"

run_id="run-$(printf '%03d' "${repetition}")"
run_dir="${output_root}/${scenario}/${run_id}"
[[ ! -e "${run_dir}" ]] || die "evidence directory already exists: ${run_dir}"
mkdir -p "${run_dir}"

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --null-input \
  --arg scenario "${scenario}" \
  --argjson repetition "${repetition}" \
  --arg startedAt "${started_at}" \
  --arg expectedRule "${expected_rule}" \
  --arg expectedSeverity "${expected_severity}" \
  '{scenario: $scenario, repetition: $repetition, startedAt: $startedAt, expectedRule: $expectedRule, expectedSeverity: $expectedSeverity, status: "in-progress", evidenceTier: "controlled-lab-observed"}' \
  >"${run_dir}/metadata.json"

reset_required=false

reset_baseline() {
  kube delete namespace "${RADAR_NAMESPACE}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null
  kube apply --kustomize "${BASELINE_DIR}" >/dev/null
  refresh_application
  wait_for_synced_healthy 600s
  "${SCRIPT_DIR}/verify-baseline.sh" --context "${RADAR_CONTEXT}" >/dev/null
}

cleanup() {
  local exit_code=$?
  trap - EXIT
  stop_argocd_forward
  if [[ "${reset_required}" == true ]]; then
    printf 'Attempting fail-safe baseline reset after interrupted run.\n' >&2
    reset_baseline || printf 'Fail-safe reset failed; verify radar-lab manually.\n' >&2
  fi
  exit "${exit_code}"
}
trap cleanup EXIT

case "${scenario}" in
  rbac-wildcard)
    kube --namespace "${RADAR_NAMESPACE}" patch role radar-demo-reader --type json \
      --patch='[{"op":"replace","path":"/rules","value":[{"apiGroups":["*"],"resources":["*"],"verbs":["*"]}]}]' >/dev/null
    ;;
  networkpolicy-removal)
    kube --namespace "${RADAR_NAMESPACE}" delete networkpolicy radar-demo-default-deny-ingress --wait=true >/dev/null
    ;;
  privileged-container)
    kube --namespace "${RADAR_NAMESPACE}" patch deployment radar-demo --type strategic \
      --patch='{"spec":{"template":{"spec":{"containers":[{"name":"radar-demo","securityContext":{"privileged":true}}]}}}}' >/dev/null
    ;;
  hostpath-addition)
    kube --namespace "${RADAR_NAMESPACE}" patch deployment radar-demo --type json \
      --patch='[{"op":"remove","path":"/spec/template/spec/volumes/0/emptyDir"},{"op":"add","path":"/spec/template/spec/volumes/0/hostPath","value":{"path":"/var/log","type":"Directory"}}]' >/dev/null
    ;;
  service-exposure)
    kube --namespace "${RADAR_NAMESPACE}" patch service radar-demo --type merge --patch='{"spec":{"type":"NodePort"}}' >/dev/null
    ;;
  unsafe-image-tag)
    kube --namespace "${RADAR_NAMESPACE}" patch deployment radar-demo --type strategic \
      --patch='{"spec":{"template":{"spec":{"containers":[{"name":"radar-demo","image":"nginx:latest"}]}}}}' >/dev/null
    ;;
  secret-reference)
    kube --namespace "${RADAR_NAMESPACE}" patch deployment radar-demo --type json \
      --patch='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name","value":"radar-demo-credentials-v2"}]' >/dev/null
    ;;
  metadata-only)
    kube --namespace "${RADAR_NAMESPACE}" label deployment radar-demo radar.research/scenario=metadata-only --overwrite >/dev/null
    ;;
esac
reset_required=true

refresh_application
wait_for_application_value '{.status.sync.status}' OutOfSync 300s
observed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output json | \
  jq --arg observedAt "${observed_at}" \
    '{application: .metadata.name, project: .spec.project, syncStatus: .status.sync.status, healthStatus: .status.health.status, observedAt: $observedAt}' \
    >"${run_dir}/argocd-observation.json"

token_file="${RADAR_TOKEN_FILE:-${REPO_ROOT}/.radar-lab-token}"
[[ -s "${token_file}" ]] || die "RADAR token file is missing; run create-token.sh"
radar_token="$(<"${token_file}")"

start_argocd_forward 18080 "${run_dir}/port-forward.log"
if [[ -n "${RADAR_BIN:-}" ]]; then
  ARGOCD_SERVER=http://127.0.0.1:18080 \
  ARGOCD_AUTH_TOKEN="${radar_token}" \
  RADAR_POLICY_PATH="${REPO_ROOT}/policies/risk.rego" \
    "${RADAR_BIN}" scan --app "${RADAR_APP}" --output json >"${run_dir}/radar-result.json"
else
  (
    cd "${REPO_ROOT}"
    ARGOCD_SERVER=http://127.0.0.1:18080 \
    ARGOCD_AUTH_TOKEN="${radar_token}" \
    RADAR_POLICY_PATH="${REPO_ROOT}/policies/risk.rego" \
      go run ./cmd/radar scan --app "${RADAR_APP}" --output json
  ) >"${run_dir}/radar-result.json"
fi
unset radar_token
stop_argocd_forward

jq --exit-status --arg rule "${expected_rule}" --arg severity "${expected_severity}" \
  'any(.findings[]; .ruleId == $rule and .severity == $severity)' \
  "${run_dir}/radar-result.json" >/dev/null || die "RADAR did not emit the expected rule and severity"

reset_baseline
reset_required=false
completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --null-input \
  --arg scenario "${scenario}" \
  --argjson repetition "${repetition}" \
  --arg startedAt "${started_at}" \
  --arg observedAt "${observed_at}" \
  --arg completedAt "${completed_at}" \
  --arg expectedRule "${expected_rule}" \
  --arg expectedSeverity "${expected_severity}" \
  '{scenario: $scenario, repetition: $repetition, startedAt: $startedAt, observedAt: $observedAt, completedAt: $completedAt, expectedRule: $expectedRule, expectedSeverity: $expectedSeverity, status: "completed", baselineResetVerified: true, evidenceTier: "controlled-lab-observed"}' \
  >"${run_dir}/metadata.json"

trap - EXIT
printf 'Scenario %s repetition %s completed and reset; evidence: %s\n' "${scenario}" "${repetition}" "${run_dir}"
