#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=scenario-integrity.sh disable=SC1091
source "${SCRIPT_DIR}/scenario-integrity.sh"

usage() {
  printf 'Usage: %s --context radar-lab --collection-id <identifier> --scenario <name> --repetition <positive-integer> --environment-file <environment.json> [--output-dir <path>]\n' "$0" >&2
  exit 2
}

requested_context=""
collection_id=""
scenario=""
repetition=""
output_root=""
environment_file=""

while (($# > 0)); do
  case "$1" in
    --context) requested_context="${2:-}"; shift 2 ;;
    --collection-id) collection_id="${2:-}"; shift 2 ;;
    --scenario) scenario="${2:-}"; shift 2 ;;
    --repetition) repetition="${2:-}"; shift 2 ;;
    --output-dir) output_root="${2:-}"; shift 2 ;;
    --environment-file) environment_file="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

assert_context "${requested_context}"
[[ "${collection_id}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "--collection-id is invalid"
[[ "${repetition}" =~ ^[1-9][0-9]*$ ]] || die "--repetition must be a positive integer"
[[ -n "${environment_file}" ]] || die "--environment-file is required"
[[ -z "${RADAR_BIN+x}" ]] || die "RADAR_BIN is not permitted for controlled evidence"
output_root="${output_root:-${REPO_ROOT}/k8s-lab/evidence/${collection_id}}"

expected_rule=""
expected_severity=""
case "${scenario}" in
  rbac-wildcard) expected_rule="RADAR-RBAC-WILDCARD"; expected_severity="CRITICAL" ;;
  networkpolicy-removal) expected_rule="RADAR-NETPOL-REMOVED"; expected_severity="HIGH" ;;
  privileged-container) expected_rule="RADAR-WORKLOAD-PRIVILEGED"; expected_severity="CRITICAL" ;;
  hostpath-addition) expected_rule="RADAR-VOLUME-HOSTPATH"; expected_severity="HIGH" ;;
  service-exposure) expected_rule="RADAR-SERVICE-EXPOSURE"; expected_severity="HIGH" ;;
  unsafe-image-tag) expected_rule="RADAR-IMAGE-LATEST"; expected_severity="MEDIUM" ;;
  secret-reference) expected_rule="RADAR-SECRET-REFERENCE"; expected_severity="MEDIUM" ;;
  metadata-only) expected_rule="RADAR-METADATA-ONLY"; expected_severity="LOW" ;;
  *) die "unknown scenario: ${scenario:-empty}" ;;
esac

for command_name in base64 curl git go jq kubectl minikube sha256sum tar; do
  require_command "${command_name}"
done
[[ -f "${environment_file}" && ! -L "${environment_file}" ]] || die "environment file must be a regular JSON file"
[[ -f "${environment_file}.sha256" && ! -L "${environment_file}.sha256" ]] || die "environment checksum sidecar is required"
expected_environment_sha="$(awk 'NR == 1 {print $1}' "${environment_file}.sha256")"
[[ "${expected_environment_sha}" =~ ^[0-9a-f]{64}$ ]] || die "environment checksum sidecar is malformed"
actual_environment_sha="$(sha256sum "${environment_file}" | awk '{print $1}')"
[[ "${actual_environment_sha}" == "${expected_environment_sha}" ]] || die "environment checksum does not match"

[[ -z "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=all)" ]] || die "controlled scenarios require a clean worktree"
source_head="$(git -C "${REPO_ROOT}" rev-parse HEAD)"

verify_declared_baseline
preflight_application="$(mktemp)"
kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output json >"${preflight_application}"
validate_application_snapshot "${preflight_application}" "${source_head}" Synced || die "Argo CD preflight does not match the clean source commit"
application_target_revision="$(jq --raw-output '.spec.source.targetRevision' "${preflight_application}")"
application_synchronized_revision="$(jq --raw-output '.status.sync.revision' "${preflight_application}")"
application_operation_revision="$(jq --raw-output '.status.operationState.syncResult.revision' "${preflight_application}")"
application_operation_phase="$(jq --raw-output '.status.operationState.phase' "${preflight_application}")"
assert_frozen_application_revision "${application_target_revision}" "${application_synchronized_revision}" \
  "${application_operation_revision}" "${application_operation_phase}"
jq --exit-status --arg collection "${collection_id}" --arg commit "${source_head}" \
  '.collectionId == $collection and .source.commit == $commit' "${environment_file}" >/dev/null || \
  die "environment provenance does not match the collection and source commit"

build_root="$(mktemp --directory)"
snapshot_root="${build_root}/source"
scanner_binary="${build_root}/radar"
mkdir -p "${snapshot_root}"
git -C "${REPO_ROOT}" archive "${source_head}" | tar --extract --directory "${snapshot_root}"
(cd "${snapshot_root}" && go build -trimpath -o "${scanner_binary}" ./cmd/radar)
scanner_sha256="$(sha256sum "${scanner_binary}" | awk '{print $1}')"
policy_sha256="$(sha256sum "${snapshot_root}/policies/risk.rego" | awk '{print $1}')"

run_id="run-$(printf '%03d' "${repetition}")"
run_dir="${output_root}/${scenario}/${run_id}"
diagnostics_dir="${output_root}/.diagnostics"
port_forward_log="${diagnostics_dir}/${scenario}-${run_id}-port-forward.log"
[[ ! -e "${run_dir}" ]] || die "evidence directory already exists: ${run_dir}"
mkdir -p "${run_dir}" "${diagnostics_dir}"
cp "${environment_file}" "${run_dir}/environment.json"

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --null-input \
  --arg collectionId "${collection_id}" --arg scenario "${scenario}" \
  --argjson repetition "${repetition}" --arg startedAt "${started_at}" \
  --arg sourceCommit "${source_head}" --arg scannerSha256 "${scanner_sha256}" \
  --arg policySha256 "${policy_sha256}" --arg environmentSha256 "${actual_environment_sha}" \
  --arg argoTargetRevision "${application_target_revision}" \
  --arg argoSynchronizedRevision "${application_synchronized_revision}" \
  --arg argoOperationRevision "${application_operation_revision}" \
  --arg argoOperationPhase "${application_operation_phase}" \
  --arg expectedRule "${expected_rule}" --arg expectedSeverity "${expected_severity}" \
  '{evidenceSchemaVersion: 3, collectionId: $collectionId, scenario: $scenario,
    repetition: $repetition, startedAt: $startedAt, sourceCommit: $sourceCommit,
    scannerSha256: $scannerSha256, policySha256: $policySha256,
    environmentSha256: $environmentSha256, argoTargetRevision: $argoTargetRevision,
    argoSynchronizedRevision: $argoSynchronizedRevision,
    argoOperationRevision: $argoOperationRevision, argoOperationPhase: $argoOperationPhase,
    expectedRule: $expectedRule, expectedSeverity: $expectedSeverity,
    status: "in-progress", evidenceTier: "implemented"}' >"${run_dir}/metadata.json"

reset_required=false
current_stage="prepare-mutation"
auth_header_file=""

cleanup() {
  local exit_code=$?
  local failed_at
  local metadata_temporary
  local reset_verified=false
  set +e
  trap - EXIT
  failed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stop_argocd_forward
  [[ -z "${auth_header_file}" ]] || rm -f "${auth_header_file}"
  rm -f "${run_dir}"/.application-*.json "${run_dir}/.managed-resources.json" "${run_dir}"/.reset.* 2>/dev/null
  if [[ "${reset_required}" == true ]]; then
    printf 'Attempting fail-safe baseline reset after interrupted run.\n' >&2
    if reset_baseline "${application_target_revision}" "${run_dir}"; then
      reset_verified=true
    else
      printf 'Fail-safe reset failed; verify radar-lab manually.\n' >&2
      jq --null-input --arg failedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg targetRevision "${application_target_revision}" \
        '{method: "namespace-delete-explicit-argocd-sync", failedAt: $failedAt,
          targetRevision: $targetRevision, declaredBaselineVerified: false}' >"${run_dir}/reset.json"
    fi
  elif verify_declared_baseline >/dev/null 2>&1; then
    reset_verified=true
  fi
  if [[ -f "${run_dir}/metadata.json" ]]; then
    metadata_temporary="$(mktemp "${run_dir}/.metadata.XXXXXX")"
    jq --arg failedAt "${failed_at}" --arg failureStage "${current_stage}" \
      --argjson exitCode "${exit_code}" --argjson baselineResetVerified "${reset_verified}" \
      '.status = "failed" | .failedAt = $failedAt | .failureStage = $failureStage |
       .exitCode = $exitCode | .baselineResetVerified = $baselineResetVerified |
       .evidenceTier = "implemented"' "${run_dir}/metadata.json" >"${metadata_temporary}" && \
      mv "${metadata_temporary}" "${run_dir}/metadata.json"
  fi
  rm -rf "${build_root}" "${preflight_application}"
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
    mutation_group="rbac.authorization.k8s.io"; mutation_kind="Role"; mutation_name="radar-demo-reader"; mutation_patch_type="json"
    mutation_patch='[{"op":"replace","path":"/rules","value":[{"apiGroups":["*"],"resources":["*"],"verbs":["*"]}]}]'
    ;;
  networkpolicy-removal)
    mutation_action="delete"; mutation_group="networking.k8s.io"; mutation_kind="NetworkPolicy"; mutation_name="radar-demo-default-deny-ingress"
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
    mutation_group=""; mutation_kind="Service"; mutation_patch_type="merge"; mutation_patch='{"spec":{"type":"NodePort"}}'
    ;;
  unsafe-image-tag)
    mutation_patch_type="strategic"; mutation_patch='{"spec":{"template":{"spec":{"containers":[{"name":"radar-demo","image":"nginx:latest"}]}}}}'
    ;;
  secret-reference)
    mutation_patch_type="json"; mutation_patch='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name","value":"radar-demo-credentials-v2"}]'
    ;;
  metadata-only)
    mutation_action="label"; mutation_patch='{"app.kubernetes.io/part-of":"metadata-only"}'
    ;;
esac

[[ -z "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=all)" ]] || die "worktree changed after the frozen build"
[[ "$(git -C "${REPO_ROOT}" rev-parse HEAD)" == "${application_target_revision}" ]] || die "HEAD changed after the frozen build"
current_stage="inject-drift"
mutation_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
reset_required=true
case "${scenario}" in
  rbac-wildcard) kube --namespace "${RADAR_NAMESPACE}" patch role "${mutation_name}" --type "${mutation_patch_type}" --patch="${mutation_patch}" >/dev/null ;;
  networkpolicy-removal) kube --namespace "${RADAR_NAMESPACE}" delete networkpolicy "${mutation_name}" --wait=true >/dev/null ;;
  privileged-container | hostpath-addition | unsafe-image-tag | secret-reference) kube --namespace "${RADAR_NAMESPACE}" patch deployment "${mutation_name}" --type "${mutation_patch_type}" --patch="${mutation_patch}" >/dev/null ;;
  service-exposure) kube --namespace "${RADAR_NAMESPACE}" patch service "${mutation_name}" --type "${mutation_patch_type}" --patch="${mutation_patch}" >/dev/null ;;
  metadata-only) kube --namespace "${RADAR_NAMESPACE}" label deployment "${mutation_name}" app.kubernetes.io/part-of=metadata-only --overwrite >/dev/null ;;
esac
mutation_completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --null-input \
  --arg collectionId "${collection_id}" --arg scenario "${scenario}" \
  --arg startedAt "${mutation_started_at}" --arg completedAt "${mutation_completed_at}" \
  --arg group "${mutation_group}" --arg kind "${mutation_kind}" \
  --arg namespace "${mutation_namespace}" --arg name "${mutation_name}" \
  --arg action "${mutation_action}" --arg patchType "${mutation_patch_type}" \
  --argjson patch "${mutation_patch}" \
  '{collectionId: $collectionId, scenario: $scenario, startedAt: $startedAt,
    completedAt: $completedAt, resource: {group: $group, kind: $kind,
    namespace: $namespace, name: $name}, action: $action,
    patchType: (if $patchType == "" then null else $patchType end), patch: $patch}' \
  >"${run_dir}/mutation.json"

current_stage="observe-argocd"
refresh_application
wait_for_application_value '{.status.sync.status}' OutOfSync 300s
token_file="${RADAR_TOKEN_FILE:-${REPO_ROOT}/.radar-lab-token}"
[[ -s "${token_file}" && ! -L "${token_file}" ]] || die "RADAR token file is missing or unsafe; run create-token.sh"
start_argocd_forward "${port_forward_log}"
current_stage="capture-managed-resources"
auth_header_file="$(mktemp)"
chmod 600 "${auth_header_file}"
{
  printf 'Authorization: Bearer '
  tr -d '\r\n' <"${token_file}"
  printf '\n'
} >"${auth_header_file}"
capture_stable_scan_bundle "${run_dir}" "${application_target_revision}" "${auth_header_file}" || die "could not capture a stable Argo CD scan bundle"
rm -f "${auth_header_file}"
auth_header_file=""
captured_input_sha256="$(sha256sum "${run_dir}/scan-input.json" | awk '{print $1}')"
observed_at="$(jq --raw-output '.observedAt' "${run_dir}/argocd-observation.json")"

current_stage="scan-radar"
RADAR_POLICY_PATH="${snapshot_root}/policies/risk.rego" \
  "${scanner_binary}" scan --fixture "${run_dir}/scan-input.json" --output json >"${run_dir}/radar-result.json"
radar_completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stop_argocd_forward

current_stage="verify-decision"
jq --exit-status --arg rule "${expected_rule}" --arg severity "${expected_severity}" \
  'any(.findings[]; .ruleId == $rule and .severity == $severity)' \
  "${run_dir}/radar-result.json" >/dev/null || die "RADAR did not emit the expected rule and severity"

current_stage="reset-baseline"
reset_baseline "${application_target_revision}" "${run_dir}"
reset_required=false
completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --arg mutationAt "${mutation_completed_at}" --arg observedAt "${observed_at}" \
  --arg radarCompletedAt "${radar_completed_at}" --arg completedAt "${completed_at}" \
  --arg capturedInputSha256 "${captured_input_sha256}" \
  --arg applicationResourceVersion "${APPLICATION_RESOURCE_VERSION}" \
  --argjson captureAttempt "${CAPTURE_ATTEMPT}" \
  '.mutationAt = $mutationAt | .observedAt = $observedAt |
   .radarCompletedAt = $radarCompletedAt | .completedAt = $completedAt |
   .capturedInputSha256 = $capturedInputSha256 |
   .applicationResourceVersion = $applicationResourceVersion |
   .captureAttempt = $captureAttempt | .status = "completed" |
   .baselineResetVerified = true | .evidenceTier = "controlled-lab-observed"' \
  "${run_dir}/metadata.json" >"${run_dir}/metadata.json.tmp"
mv "${run_dir}/metadata.json.tmp" "${run_dir}/metadata.json"

rm -rf "${build_root}" "${preflight_application}"
trap - EXIT
printf 'Scenario %s repetition %s completed and reset; evidence: %s\n' "${scenario}" "${repetition}" "${run_dir}"
