#!/usr/bin/env bash

set -euo pipefail

readonly RADAR_CONTEXT="radar-lab"
readonly RADAR_PROFILE="radar-lab"
readonly RADAR_APP="radar-lab"
# shellcheck disable=SC2034
readonly RADAR_NAMESPACE="radar-demo"
readonly ARGO_NAMESPACE="argocd"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
# shellcheck source=../../scripts/toolchain-versions.sh disable=SC1091
source "${REPO_ROOT}/scripts/toolchain-versions.sh"
readonly RADAR_PROJECT_ENV_ROOT="${REPO_ROOT}/.radar-env"
# shellcheck disable=SC2034
readonly BASELINE_DIR="${REPO_ROOT}/k8s-lab/baseline"
readonly RADAR_IDENTITY_FILE="${MINIKUBE_HOME:-${HOME}/.minikube}/profiles/${RADAR_PROFILE}/radar-identity.json"

die() {
  printf 'RADAR lab safety check failed: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

assert_context() {
  local requested_context="${1:-}"
  [[ "${requested_context}" == "${RADAR_CONTEXT}" ]] || die "--context must be exactly ${RADAR_CONTEXT}"
  assert_project_environment
}

assert_project_environment() {
  [[ "${RADAR_ENV_ACTIVE:-}" == "1" ]] || \
    die "activate the project environment first: source scripts/activate-env.sh"
  [[ "${RADAR_ENV_ROOT:-}" == "${RADAR_PROJECT_ENV_ROOT}" ]] || \
    die "RADAR_ENV_ROOT must be ${RADAR_PROJECT_ENV_ROOT}"
  [[ "${MINIKUBE_HOME:-}" == "${RADAR_PROJECT_ENV_ROOT}/state/minikube" ]] || \
    die "MINIKUBE_HOME must remain inside the project environment"
  [[ "${KUBECONFIG:-}" == "${RADAR_PROJECT_ENV_ROOT}/state/kubeconfig" ]] || \
    die "KUBECONFIG must remain inside the project environment"
  [[ "${RADAR_TOKEN_FILE:-}" == "${RADAR_PROJECT_ENV_ROOT}/state/radar-token" ]] || \
    die "RADAR_TOKEN_FILE must remain inside the project environment"
  [[ "${RADAR_UI_PASSWORD_FILE:-}" == "${RADAR_PROJECT_ENV_ROOT}/state/argocd-ui-password" ]] || \
    die "RADAR_UI_PASSWORD_FILE must remain inside the project environment"
}

context_connection_values() {
  local context_json
  local ca_data
  local server
  context_json="$(command kubectl --context "${RADAR_CONTEXT}" config view --minify --flatten --raw --output json)" || return 1
  server="$(jq --exit-status --raw-output '.clusters[0].cluster.server | select(type == "string" and length > 0)' <<<"${context_json}")" || return 1
  ca_data="$(jq --exit-status --raw-output '.clusters[0].cluster["certificate-authority-data"] | select(type == "string" and length > 0)' <<<"${context_json}")" || return 1
  printf '%s\t%s\n' "${server}" "$(printf '%s' "${ca_data}" | base64 --decode | sha256sum | awk '{print $1}')"
}

record_lab_cluster_identity() {
  local connection
  local context_uid
  local identity_temporary
  local profile_uid
  local server
  local ca_sha256

  for command_name in base64 jq kubectl minikube sha256sum stat; do require_command "${command_name}"; done
  minikube status --profile "${RADAR_PROFILE}" >/dev/null 2>&1 || die "Minikube profile ${RADAR_PROFILE} is not running"
  [[ ! -e "${RADAR_IDENTITY_FILE}" && ! -L "${RADAR_IDENTITY_FILE}" ]] || die "lab identity already exists"
  connection="$(context_connection_values)" || die "could not read the ${RADAR_CONTEXT} context identity"
  IFS=$'\t' read -r server ca_sha256 <<<"${connection}"
  context_uid="$(command kubectl --context "${RADAR_CONTEXT}" get namespace kube-system --output jsonpath='{.metadata.uid}')" || die "could not identify the named context"
  profile_uid="$(minikube --profile "${RADAR_PROFILE}" kubectl --ssh -- get namespace kube-system --output jsonpath='{.metadata.uid}')" || die "could not identify the Minikube profile"
  [[ -n "${context_uid}" && "${context_uid}" == "${profile_uid}" ]] || die "the named context is not the ${RADAR_PROFILE} Minikube profile"

  umask 077
  identity_temporary="$(mktemp "${RADAR_IDENTITY_FILE}.XXXXXX")"
  jq --null-input \
    --arg profile "${RADAR_PROFILE}" \
    --arg context "${RADAR_CONTEXT}" \
    --arg server "${server}" \
    --arg caSha256 "${ca_sha256}" \
    --arg clusterUid "${context_uid}" \
    '{profile: $profile, context: $context, server: $server, caSha256: $caSha256, clusterUid: $clusterUid}' \
    >"${identity_temporary}"
  chmod 600 "${identity_temporary}"
  mv "${identity_temporary}" "${RADAR_IDENTITY_FILE}"
}

assert_lab_cluster_identity() {
  local actual_ca_sha256
  local actual_server
  local actual_uid
  local connection
  local expected_ca_sha256
  local expected_server
  local expected_uid
  local mode

  for command_name in base64 jq kubectl minikube sha256sum stat; do require_command "${command_name}"; done
  minikube status --profile "${RADAR_PROFILE}" >/dev/null 2>&1 || die "Minikube profile ${RADAR_PROFILE} is not running"
  [[ -f "${RADAR_IDENTITY_FILE}" && ! -L "${RADAR_IDENTITY_FILE}" ]] || die "trusted lab identity is missing or unsafe"
  mode="$(stat --format '%a' "${RADAR_IDENTITY_FILE}")"
  [[ "${mode}" == "600" ]] || die "trusted lab identity must have mode 0600"
  jq --exit-status \
    --arg profile "${RADAR_PROFILE}" --arg context "${RADAR_CONTEXT}" \
    '.profile == $profile and .context == $context and
     (.server | type == "string" and length > 0) and
     (.caSha256 | test("^[0-9a-f]{64}$")) and
     (.clusterUid | type == "string" and length > 0)' \
    "${RADAR_IDENTITY_FILE}" >/dev/null || die "trusted lab identity is malformed"

  connection="$(context_connection_values)" || die "could not read the ${RADAR_CONTEXT} context identity"
  IFS=$'\t' read -r actual_server actual_ca_sha256 <<<"${connection}"
  actual_uid="$(command kubectl --context "${RADAR_CONTEXT}" get namespace kube-system --output jsonpath='{.metadata.uid}')" || die "could not verify the named context"
  expected_server="$(jq --raw-output '.server' "${RADAR_IDENTITY_FILE}")"
  expected_ca_sha256="$(jq --raw-output '.caSha256' "${RADAR_IDENTITY_FILE}")"
  expected_uid="$(jq --raw-output '.clusterUid' "${RADAR_IDENTITY_FILE}")"
  [[ "${actual_server}" == "${expected_server}" ]] || die "context API server does not match the trusted lab"
  [[ "${actual_ca_sha256}" == "${expected_ca_sha256}" ]] || die "context CA does not match the trusted lab"
  [[ "${actual_uid}" == "${expected_uid}" ]] || die "context cluster UID does not match the trusted lab"
}

kube() {
  (assert_lab_cluster_identity) || return 1
  command kubectl --context "${RADAR_CONTEXT}" "$@"
}

assert_frozen_application_revision() {
  local target_revision="${1:-}"
  local synchronized_revision="${2:-}"
  local operation_revision="${3:-}"
  local operation_phase="${4:-}"

  [[ "${target_revision}" =~ ^[0-9a-f]{40}$ ]] || die "controlled scenarios require an immutable 40-character Git commit SHA as the Argo CD target revision"
  [[ "${synchronized_revision}" == "${target_revision}" ]] || die "the Argo CD synchronized revision does not match its immutable target revision"
  [[ "${operation_revision}" == "${target_revision}" && "${operation_phase}" == "Succeeded" ]] || die "the latest successful Argo CD sync operation does not match the immutable target revision"
}

refresh_application() {
  kube --namespace "${ARGO_NAMESPACE}" annotate application "${RADAR_APP}" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

wait_for_application_value() {
  local jsonpath="$1"
  local expected="$2"
  local timeout="${3:-300s}"
  kube --namespace "${ARGO_NAMESPACE}" wait "application/${RADAR_APP}" \
    "--for=jsonpath=${jsonpath}=${expected}" "--timeout=${timeout}" >/dev/null
}

wait_for_synced_healthy() {
  local timeout="${1:-600s}"
  wait_for_application_value '{.status.sync.status}' Synced "${timeout}" || return 1
  wait_for_application_value '{.status.health.status}' Healthy "${timeout}" || return 1
}

verify_declared_baseline() {
  "${SCRIPT_DIR}/verify-baseline.sh" --context "${RADAR_CONTEXT}" >/dev/null
}

PORT_FORWARD_PID=""
ARGOCD_FORWARD_PORT=""
ARGOCD_FORWARD_BASE_URL=""

socket_owned_by_pid() {
  local pid="$1"
  local port="$2"
  local hex_port
  local inode
  local descriptor
  local target
  hex_port="$(printf '%04X' "${port}")"
  inode="$(awk -v port=":${hex_port}" '$2 ~ port "$" && $4 == "0A" {print $10; exit}' /proc/net/tcp)"
  [[ -n "${inode}" ]] || return 1
  for descriptor in "/proc/${pid}/fd/"*; do
    [[ -e "${descriptor}" ]] || continue
    target="$(readlink "${descriptor}" 2>/dev/null || true)"
    [[ "${target}" == "socket:[${inode}]" ]] && return 0
  done
  return 1
}

stop_argocd_forward() {
  if [[ -n "${PORT_FORWARD_PID}" ]] && kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
  PORT_FORWARD_PID=""
  ARGOCD_FORWARD_PORT=""
  ARGOCD_FORWARD_BASE_URL=""
}

start_argocd_forward() {
  local log_file="$1"
  local forwarding_line
  local port

  require_command curl
  assert_lab_cluster_identity
  : >"${log_file}"
  command kubectl --context "${RADAR_CONTEXT}" --namespace "${ARGO_NAMESPACE}" \
    port-forward --address 127.0.0.1 service/argocd-server :80 >"${log_file}" 2>&1 &
  PORT_FORWARD_PID=$!

  for _attempt in {1..60}; do
    if ! kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
      stop_argocd_forward
      die "Argo CD localhost port-forward exited before readiness; inspect ${log_file}"
    fi
    forwarding_line="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) -> [0-9][0-9]*$/\1/p' "${log_file}" | head -n 1)"
    if [[ "${forwarding_line}" =~ ^[1-9][0-9]{0,4}$ ]] && ((forwarding_line <= 65535)); then
      port="${forwarding_line}"
      if socket_owned_by_pid "${PORT_FORWARD_PID}" "${port}" && \
        curl --fail --silent --show-error "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1 && \
        kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1 && \
        socket_owned_by_pid "${PORT_FORWARD_PID}" "${port}"; then
        # Globals are consumed by scripts that source this file.
        # shellcheck disable=SC2034
        ARGOCD_FORWARD_PORT="${port}"
        # shellcheck disable=SC2034
        ARGOCD_FORWARD_BASE_URL="http://127.0.0.1:${port}"
        return 0
      fi
    fi
    sleep 0.25
  done
  stop_argocd_forward
  die "Argo CD localhost port-forward did not become ready"
}
