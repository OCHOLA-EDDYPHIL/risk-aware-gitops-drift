#!/usr/bin/env bash

set -euo pipefail

# Constants are consumed by scripts that source this file.
# shellcheck disable=SC2034
readonly RADAR_CONTEXT="radar-lab"
# shellcheck disable=SC2034
readonly RADAR_PROFILE="radar-lab"
readonly RADAR_APP="radar-lab"
# shellcheck disable=SC2034
readonly RADAR_NAMESPACE="radar-demo"
readonly ARGO_NAMESPACE="argocd"
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
# shellcheck disable=SC2034
readonly BASELINE_DIR="${REPO_ROOT}/k8s-lab/baseline"

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
}

assert_frozen_application_revision() {
  local target_revision="${1:-}"
  local synchronized_revision="${2:-}"
  local operation_revision="${3:-}"
  local operation_phase="${4:-}"

  [[ "${target_revision}" =~ ^[0-9a-f]{40}$ ]] || \
    die "controlled scenarios require an immutable 40-character Git commit SHA as the Argo CD target revision"
  [[ "${synchronized_revision}" == "${target_revision}" ]] || \
    die "the Argo CD synchronized revision does not match its immutable target revision"
  [[ "${operation_revision}" == "${target_revision}" && "${operation_phase}" == "Succeeded" ]] || \
    die "the latest successful Argo CD sync operation does not match the immutable target revision"
}

kube() {
  command kubectl --context "${RADAR_CONTEXT}" "$@"
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
  wait_for_application_value '{.status.sync.status}' Synced "${timeout}"
  wait_for_application_value '{.status.health.status}' Healthy "${timeout}"
}

PORT_FORWARD_PID=""

start_argocd_forward() {
  local port="${1:-18080}"
  local log_file="$2"

  require_command curl
  kube --namespace "${ARGO_NAMESPACE}" port-forward --address 127.0.0.1 service/argocd-server "${port}:80" >"${log_file}" 2>&1 &
  PORT_FORWARD_PID=$!

  for _attempt in {1..30}; do
    if curl --fail --silent --show-error "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
      die "Argo CD localhost port-forward exited; inspect ${log_file}"
    fi
    sleep 1
  done
  die "Argo CD localhost port-forward did not become ready"
}

stop_argocd_forward() {
  if [[ -n "${PORT_FORWARD_PID}" ]] && kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
  PORT_FORWARD_PID=""
}
