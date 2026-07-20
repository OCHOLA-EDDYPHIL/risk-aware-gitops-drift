#!/usr/bin/env bash

set -euo pipefail

# Globals are consumed by the scenario runner after capture.
# shellcheck disable=SC2034
CAPTURE_ATTEMPT=""
# shellcheck disable=SC2034
APPLICATION_RESOURCE_VERSION=""

validate_application_snapshot() {
  local snapshot_file="$1"
  local frozen_revision="$2"
  local expected_sync_status="$3"
  local reset_id="${4:-}"
  jq --exit-status \
    --arg revision "${frozen_revision}" \
    --arg syncStatus "${expected_sync_status}" \
    --arg resetId "${reset_id}" \
    '(.metadata.uid | type == "string" and length > 0) and
     (.metadata.resourceVersion | type == "string" and length > 0) and
     .spec.source.targetRevision == $revision and
     .status.sync.revision == $revision and
     .status.operationState.syncResult.revision == $revision and
     .status.operationState.phase == "Succeeded" and
     .status.sync.status == $syncStatus and
     ((.spec.syncPolicy.automated.selfHeal // false) == false) and
     (if $syncStatus == "Synced" then .status.health.status == "Healthy" else true end) and
     (if $resetId == "" then true else .status.operationState.operation.initiatedBy.username == $resetId end)' \
    "${snapshot_file}" >/dev/null
}

capture_stable_scan_bundle() {
  local run_dir="$1"
  local frozen_revision="$2"
  local auth_header_file="$3"
  local application_after
  local application_before
  local managed_resources
  local before_resource_version
  local after_resource_version

  application_before="${run_dir}/.application-before.json"
  application_after="${run_dir}/.application-after.json"
  managed_resources="${run_dir}/.managed-resources.json"

  for attempt in 1 2 3 4 5; do
    curl --fail --silent --show-error --header "@${auth_header_file}" \
      "${ARGOCD_FORWARD_BASE_URL}/api/v1/applications/${RADAR_APP}" \
      >"${application_before}" || return 1
    validate_application_snapshot "${application_before}" "${frozen_revision}" OutOfSync || return 1
    curl --fail --silent --show-error --header "@${auth_header_file}" \
      "${ARGOCD_FORWARD_BASE_URL}/api/v1/applications/${RADAR_APP}/managed-resources" \
      >"${managed_resources}" || return 1
    jq --exit-status 'type == "object" and (.items | type == "array")' "${managed_resources}" >/dev/null || return 1
    curl --fail --silent --show-error --header "@${auth_header_file}" \
      "${ARGOCD_FORWARD_BASE_URL}/api/v1/applications/${RADAR_APP}" \
      >"${application_after}" || return 1
    validate_application_snapshot "${application_after}" "${frozen_revision}" OutOfSync || return 1

    before_resource_version="$(jq --raw-output '.metadata.resourceVersion' "${application_before}")" || return 1
    after_resource_version="$(jq --raw-output '.metadata.resourceVersion' "${application_after}")" || return 1
    if [[ "${before_resource_version}" != "${after_resource_version}" ]]; then
      sleep 1
      continue
    fi

    mv "${application_before}" "${run_dir}/argocd-application.json" || return 1
    mv "${managed_resources}" "${run_dir}/argocd-managed-resources.json" || return 1
    rm -f "${application_after}"
    jq --null-input \
      --slurpfile application "${run_dir}/argocd-application.json" \
      --slurpfile managedResources "${run_dir}/argocd-managed-resources.json" \
      '{application: $application[0], managedResources: $managedResources[0]}' \
      >"${run_dir}/scan-input.json" || return 1
    jq --arg observedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{application: .metadata.name, project: .spec.project,
        targetRevision: .spec.source.targetRevision,
        synchronizedRevision: .status.sync.revision,
        operationRevision: .status.operationState.syncResult.revision,
        operationPhase: .status.operationState.phase,
        applicationResourceVersion: .metadata.resourceVersion,
        syncStatus: .status.sync.status, healthStatus: .status.health.status,
        observedAt: $observedAt}' \
      "${run_dir}/argocd-application.json" >"${run_dir}/argocd-observation.json" || return 1
    # shellcheck disable=SC2034
    CAPTURE_ATTEMPT="${attempt}"
    # shellcheck disable=SC2034
    APPLICATION_RESOURCE_VERSION="${before_resource_version}"
    return 0
  done
  rm -f "${application_before}" "${application_after}" "${managed_resources}"
  return 1
}

reset_baseline() {
  local frozen_revision="$1"
  local run_dir="$2"
  local application_before_reset
  local application_state
  local reset_completed_at
  local reset_id
  local reset_started_at
  local reset_temporary
  local sync_patch

  application_before_reset="$(mktemp)" || return 1
  kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output json >"${application_before_reset}" || {
    rm -f "${application_before_reset}"
    return 1
  }
  jq --exit-status --arg revision "${frozen_revision}" \
    '.spec.source.targetRevision == $revision and ((.spec.syncPolicy.automated.selfHeal // false) == false)' \
    "${application_before_reset}" >/dev/null || {
    rm -f "${application_before_reset}"
    return 1
  }
  rm -f "${application_before_reset}"

  reset_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return 1
  kube delete namespace "${RADAR_NAMESPACE}" --ignore-not-found=true --wait=true --timeout=180s >/dev/null || return 1
  reset_id="radar-reset-$(date -u +%s%N)" || return 1
  sync_patch="$(jq --null-input --compact-output \
    --arg revision "${frozen_revision}" --arg resetId "${reset_id}" \
    '{operation: {initiatedBy: {username: $resetId}, sync: {revision: $revision, prune: false}}}')" || return 1
  kube --namespace "${ARGO_NAMESPACE}" patch application "${RADAR_APP}" \
    --type merge --patch "${sync_patch}" >/dev/null || return 1
  kube --namespace "${ARGO_NAMESPACE}" wait "application/${RADAR_APP}" \
    "--for=jsonpath={.status.operationState.operation.initiatedBy.username}=${reset_id}" \
    --timeout=300s >/dev/null || return 1
  kube --namespace "${ARGO_NAMESPACE}" wait "application/${RADAR_APP}" \
    "--for=jsonpath={.status.operationState.phase}=Succeeded" \
    --timeout=600s >/dev/null || return 1
  wait_for_synced_healthy 600s || return 1
  verify_declared_baseline || return 1
  application_state="$(mktemp)" || return 1
  kube --namespace "${ARGO_NAMESPACE}" get application "${RADAR_APP}" --output json >"${application_state}" || {
    rm -f "${application_state}"
    return 1
  }
  validate_application_snapshot "${application_state}" "${frozen_revision}" Synced "${reset_id}" || {
    rm -f "${application_state}"
    return 1
  }
  reset_completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || {
    rm -f "${application_state}"
    return 1
  }
  reset_temporary="$(mktemp "${run_dir}/.reset.XXXXXX")" || {
    rm -f "${application_state}"
    return 1
  }
  jq --null-input \
    --arg startedAt "${reset_started_at}" \
    --arg completedAt "${reset_completed_at}" \
    --arg targetRevision "${frozen_revision}" \
    --arg operationRevision "$(jq --raw-output '.status.operationState.syncResult.revision' "${application_state}")" \
    --arg operationPhase "$(jq --raw-output '.status.operationState.phase' "${application_state}")" \
    --arg operationInitiator "${reset_id}" \
    --arg syncStatus "$(jq --raw-output '.status.sync.status' "${application_state}")" \
    --arg healthStatus "$(jq --raw-output '.status.health.status' "${application_state}")" \
    '{method: "namespace-delete-explicit-argocd-sync", startedAt: $startedAt,
      completedAt: $completedAt, targetRevision: $targetRevision,
      operationRevision: $operationRevision, operationPhase: $operationPhase,
      operationInitiator: $operationInitiator, syncStatus: $syncStatus,
      healthStatus: $healthStatus, declaredBaselineVerified: true}' \
    >"${reset_temporary}" || {
    rm -f "${application_state}" "${reset_temporary}"
    return 1
  }
  rm -f "${application_state}"
  mv "${reset_temporary}" "${run_dir}/reset.json" || return 1
}
