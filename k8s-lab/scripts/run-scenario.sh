#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'Usage: %s --context radar-lab --scenario <name> --repetition <positive-integer> [--environment-file <environment.json>] [--output-dir <path>]\n' "$0" >&2
  exit 2
}

requested_context=""
scenario=""
repetition=""
output_root="${REPO_ROOT}/k8s-lab/evidence"
environment_file=""

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
    --environment-file)
      (($# >= 2)) || usage
      environment_file="$2"
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
application_target_revision="$(kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output jsonpath='{.spec.source.targetRevision}')"
application_synchronized_revision="$(kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output jsonpath='{.status.sync.revision}')"
assert_frozen_application_revision "${application_target_revision}" "${application_synchronized_revision}"
if [[ -n "${environment_file}" ]]; then
  [[ -f "${environment_file}" && ! -L "${environment_file}" ]] || die "environment file must be a regular JSON file"
  jq --exit-status --arg commit "${application_target_revision}" \
    'type == "object" and .source.commit == $commit' "${environment_file}" >/dev/null || \
    die "environment source commit does not match the Argo CD target revision"
fi

run_id="run-$(printf '%03d' "${repetition}")"
run_dir="${output_root}/${scenario}/${run_id}"
[[ ! -e "${run_dir}" ]] || die "evidence directory already exists: ${run_dir}"
mkdir -p "${run_dir}"
if [[ -n "${environment_file}" ]]; then
  cp "${environment_file}" "${run_dir}/environment.json"
fi

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --null-input \
  --arg scenario "${scenario}" \
  --argjson repetition "${repetition}" \
  --arg startedAt "${started_at}" \
  --arg sourceCommit "${application_target_revision}" \
  --arg argoTargetRevision "${application_target_revision}" \
  --arg argoSynchronizedRevision "${application_synchronized_revision}" \
  --arg expectedRule "${expected_rule}" \
  --arg expectedSeverity "${expected_severity}" \
  '{scenario: $scenario, repetition: $repetition, startedAt: $startedAt, sourceCommit: $sourceCommit, argoTargetRevision: $argoTargetRevision, argoSynchronizedRevision: $argoSynchronizedRevision, expectedRule: $expectedRule, expectedSeverity: $expectedSeverity, status: "in-progress", evidenceTier: "implemented"}' \
  >"${run_dir}/metadata.json"

reset_required=false
current_stage="prepare-mutation"
auth_header_file=""

reset_baseline() {
  local application_state
  local reset_completed_at
  local reset_id
  local reset_started_at
  local revision
  local sync_patch
  reset_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  kube delete namespace "${RADAR_NAMESPACE}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null
  revision="$(kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output jsonpath='{.spec.source.targetRevision}')"
  reset_id="radar-reset-$(date -u +%s%N)"
  sync_patch="$(jq --null-input --compact-output \
    --arg revision "${revision}" --arg resetId "${reset_id}" \
    '{operation: {initiatedBy: {username: $resetId}, sync: {revision: $revision, prune: false}}}')"
  kube --namespace "${ARGO_NAMESPACE}" patch application "${RADAR_APP}" \
    --type merge --patch "${sync_patch}" >/dev/null
  kube --namespace "${ARGO_NAMESPACE}" wait "application/${RADAR_APP}" \
    "--for=jsonpath={.status.operationState.operation.initiatedBy.username}=${reset_id}" \
    --timeout=300s >/dev/null
  kube --namespace "${ARGO_NAMESPACE}" wait "application/${RADAR_APP}" \
    "--for=jsonpath={.status.operationState.phase}=Succeeded" \
    --timeout=600s >/dev/null
  wait_for_synced_healthy 600s
  "${SCRIPT_DIR}/verify-baseline.sh" --context "${RADAR_CONTEXT}" >/dev/null
  application_state="$(kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output json)"
  reset_completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq --null-input \
    --arg startedAt "${reset_started_at}" \
    --arg completedAt "${reset_completed_at}" \
    --arg targetRevision "${revision}" \
    --arg syncStatus "$(jq --raw-output '.status.sync.status' <<<"${application_state}")" \
    --arg healthStatus "$(jq --raw-output '.status.health.status' <<<"${application_state}")" \
    '{method: "namespace-delete-explicit-argocd-sync", startedAt: $startedAt, completedAt: $completedAt, targetRevision: $targetRevision, syncStatus: $syncStatus, healthStatus: $healthStatus, declaredBaselineVerified: true}' \
    >"${run_dir}/reset.json"
}

cleanup() {
  local exit_code=$?
  local failed_at
  local metadata_temporary
  local reset_verified=false
  trap - EXIT
  failed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stop_argocd_forward
  if [[ -n "${auth_header_file}" ]]; then
    rm -f "${auth_header_file}"
    auth_header_file=""
  fi
  if [[ "${reset_required}" == true ]]; then
    printf 'Attempting fail-safe baseline reset after interrupted run.\n' >&2
    if reset_baseline; then
      reset_verified=true
    else
      printf 'Fail-safe reset failed; verify radar-lab manually.\n' >&2
      jq --null-input --arg failedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{method: "namespace-delete-explicit-argocd-sync", failedAt: $failedAt, declaredBaselineVerified: false}' \
        >"${run_dir}/reset.json"
    fi
  elif "${SCRIPT_DIR}/verify-baseline.sh" --context "${RADAR_CONTEXT}" >/dev/null 2>&1; then
    reset_verified=true
  fi
  if [[ -f "${run_dir}/metadata.json" ]]; then
    metadata_temporary="$(mktemp)"
    jq --arg failedAt "${failed_at}" --arg failureStage "${current_stage}" \
      --argjson exitCode "${exit_code}" --argjson baselineResetVerified "${reset_verified}" \
      '.status = "failed" | .failedAt = $failedAt | .failureStage = $failureStage | .exitCode = $exitCode | .baselineResetVerified = $baselineResetVerified | .evidenceTier = "implemented"' \
      "${run_dir}/metadata.json" >"${metadata_temporary}"
    mv "${metadata_temporary}" "${run_dir}/metadata.json"
  fi
  exit "${exit_code}"
}
trap cleanup EXIT

mutation_action="patch"
mutation_group="apps"
mutation_kind="Deployment"
mutation_name="radar-demo"
mutation_namespace="${RADAR_NAMESPACE}"
mutation_patch="null"
mutation_patch_type=""
case "${scenario}" in
  rbac-wildcard)
    mutation_group="rbac.authorization.k8s.io"
    mutation_kind="Role"
    mutation_name="radar-demo-reader"
    mutation_patch_type="json"
    mutation_patch='[{"op":"replace","path":"/rules","value":[{"apiGroups":["*"],"resources":["*"],"verbs":["*"]}]}]'
    ;;
  networkpolicy-removal)
    mutation_action="delete"
    mutation_group="networking.k8s.io"
    mutation_kind="NetworkPolicy"
    mutation_name="radar-demo-default-deny-ingress"
    ;;
  privileged-container)
    mutation_patch_type="strategic"
    mutation_patch='{"spec":{"template":{"spec":{"containers":[{"name":"radar-demo","securityContext":{"allowPrivilegeEscalation":true,"privileged":true}}]}}}}'
    ;;
  hostpath-addition)
    mutation_patch_type="json"
    mutation_patch='[{"op":"remove","path":"/spec/template/spec/volumes/0/emptyDir"},{"op":"add","path":"/spec/template/spec/volumes/0/hostPath","value":{"path":"/var/log","type":"Directory"}}]'
    ;;
  service-exposure)
    mutation_group=""
    mutation_kind="Service"
    mutation_patch_type="merge"
    mutation_patch='{"spec":{"type":"NodePort"}}'
    ;;
  unsafe-image-tag)
    mutation_patch_type="strategic"
    mutation_patch='{"spec":{"template":{"spec":{"containers":[{"name":"radar-demo","image":"nginx:latest"}]}}}}'
    ;;
  secret-reference)
    mutation_patch_type="json"
    mutation_patch='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name","value":"radar-demo-credentials-v2"}]'
    ;;
  metadata-only)
    mutation_action="label"
    mutation_patch='{"radar.research/scenario":"metadata-only"}'
    ;;
esac

current_stage="inject-drift"
mutation_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
reset_required=true
case "${scenario}" in
  rbac-wildcard)
    kube --namespace "${RADAR_NAMESPACE}" patch role "${mutation_name}" --type "${mutation_patch_type}" --patch="${mutation_patch}" >/dev/null
    ;;
  networkpolicy-removal)
    kube --namespace "${RADAR_NAMESPACE}" delete networkpolicy "${mutation_name}" --wait=true >/dev/null
    ;;
  privileged-container | hostpath-addition | unsafe-image-tag | secret-reference)
    kube --namespace "${RADAR_NAMESPACE}" patch deployment "${mutation_name}" --type "${mutation_patch_type}" --patch="${mutation_patch}" >/dev/null
    ;;
  service-exposure)
    kube --namespace "${RADAR_NAMESPACE}" patch service "${mutation_name}" --type "${mutation_patch_type}" --patch="${mutation_patch}" >/dev/null
    ;;
  metadata-only)
    kube --namespace "${RADAR_NAMESPACE}" label deployment "${mutation_name}" radar.research/scenario=metadata-only --overwrite >/dev/null
    ;;
esac
mutation_completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --null-input \
  --arg scenario "${scenario}" \
  --arg startedAt "${mutation_started_at}" \
  --arg completedAt "${mutation_completed_at}" \
  --arg group "${mutation_group}" \
  --arg kind "${mutation_kind}" \
  --arg namespace "${mutation_namespace}" \
  --arg name "${mutation_name}" \
  --arg action "${mutation_action}" \
  --arg patchType "${mutation_patch_type}" \
  --argjson patch "${mutation_patch}" \
  '{scenario: $scenario, startedAt: $startedAt, completedAt: $completedAt, resource: {group: $group, kind: $kind, namespace: $namespace, name: $name}, action: $action, patchType: (if $patchType == "" then null else $patchType end), patch: $patch}' \
  >"${run_dir}/mutation.json"

current_stage="observe-argocd"
refresh_application
wait_for_application_value '{.status.sync.status}' OutOfSync 300s
observed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output json | \
  jq --arg observedAt "${observed_at}" \
    '{application: .metadata.name, project: .spec.project, targetRevision: .spec.source.targetRevision, synchronizedRevision: .status.sync.revision, syncStatus: .status.sync.status, healthStatus: .status.health.status, observedAt: $observedAt}' \
    >"${run_dir}/argocd-observation.json"

token_file="${RADAR_TOKEN_FILE:-${REPO_ROOT}/.radar-lab-token}"
[[ -s "${token_file}" ]] || die "RADAR token file is missing; run create-token.sh"
radar_token="$(<"${token_file}")"

start_argocd_forward 18080 "${run_dir}/port-forward.log"
current_stage="capture-managed-resources"
auth_header_file="$(mktemp)"
chmod 600 "${auth_header_file}"
printf 'Authorization: Bearer %s\n' "${radar_token}" >"${auth_header_file}"
curl --fail --silent --show-error \
  --header "@${auth_header_file}" \
  "http://127.0.0.1:18080/api/v1/applications/${RADAR_APP}/managed-resources" \
  >"${run_dir}/argocd-managed-resources.json"
rm -f "${auth_header_file}"
auth_header_file=""

current_stage="scan-radar"
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
radar_completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
unset radar_token
stop_argocd_forward

current_stage="verify-decision"
jq --exit-status --arg rule "${expected_rule}" --arg severity "${expected_severity}" \
  'any(.findings[]; .ruleId == $rule and .severity == $severity)' \
  "${run_dir}/radar-result.json" >/dev/null || die "RADAR did not emit the expected rule and severity"

current_stage="reset-baseline"
reset_baseline
reset_required=false
completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq \
  --arg mutationAt "${mutation_completed_at}" \
  --arg observedAt "${observed_at}" \
  --arg radarCompletedAt "${radar_completed_at}" \
  --arg completedAt "${completed_at}" \
  '.mutationAt = $mutationAt | .observedAt = $observedAt | .radarCompletedAt = $radarCompletedAt | .completedAt = $completedAt | .status = "completed" | .baselineResetVerified = true | .evidenceTier = "controlled-lab-observed"' \
  "${run_dir}/metadata.json" >"${run_dir}/metadata.json.tmp"
mv "${run_dir}/metadata.json.tmp" "${run_dir}/metadata.json"

trap - EXIT
printf 'Scenario %s repetition %s completed and reset; evidence: %s\n' "${scenario}" "${repetition}" "${run_dir}"
