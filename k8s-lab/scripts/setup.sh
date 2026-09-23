#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

readonly KUBERNETES_VERSION="v1.35.1"
readonly ARGOCD_VERSION="v3.4.5"

usage() {
  printf 'Usage: %s --context radar-lab\n' "$0" >&2
  exit 2
}

[[ $# -eq 2 && "$1" == "--context" ]] || usage
assert_context "$2"
"${SCRIPT_DIR}/preflight.sh" --context "$2"

repo_url="${RADAR_REPO_URL:-}"
repo_key="${RADAR_REPO_SSH_KEY_FILE:-}"
target_revision="${RADAR_TARGET_REVISION:-}"
[[ -n "${repo_url}" ]] || die "RADAR_REPO_URL must identify the private Git repository"
[[ "${repo_url}" != *[[:space:]]* ]] || die "RADAR_REPO_URL must not contain whitespace"
[[ "${target_revision}" =~ ^[0-9a-f]{40}$ ]] || die "RADAR_TARGET_REVISION must be an immutable 40-character commit SHA"
[[ -f "${repo_key}" ]] || die "RADAR_REPO_SSH_KEY_FILE must point to a read-only deploy key"
key_mode="$(stat -c '%a' "${repo_key}")"
[[ "${key_mode: -2}" == "00" ]] || die "repository key must not be readable or writable by group or others"

current_context_before="$(kubectl config current-context 2>/dev/null || true)"

minikube start \
  --profile "${RADAR_PROFILE}" \
  --driver docker \
  --cpus 2 \
  --memory 3072mb \
  --kubernetes-version "${KUBERNETES_VERSION}" \
  --keep-context=true

current_context_after="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${current_context_after}" != "${current_context_before}" ]]; then
  if [[ -n "${current_context_before}" ]]; then
    kubectl config use-context "${current_context_before}" >/dev/null 2>&1 || true
  fi
  die "Minikube changed the current context unexpectedly; the previous context was restored"
fi
kubectl config get-contexts "${RADAR_CONTEXT}" >/dev/null 2>&1 || die "Minikube did not create context ${RADAR_CONTEXT}"
record_lab_cluster_identity

server_version="$(kube version --output json | jq -r '.serverVersion.gitVersion')"
[[ "${server_version}" == "${KUBERNETES_VERSION}" ]] || die "Kubernetes ${KUBERNETES_VERSION} is required; found ${server_version}"

kube create namespace "${ARGO_NAMESPACE}" --dry-run=client --output yaml | kube apply --filename - >/dev/null
kube --namespace "${ARGO_NAMESPACE}" apply --server-side --filename \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
kube --namespace "${ARGO_NAMESPACE}" wait --for=condition=Available deployment --all --timeout=600s >/dev/null
kube --namespace "${ARGO_NAMESPACE}" rollout status statefulset/argocd-application-controller --timeout=600s >/dev/null

kube apply --filename "${REPO_ROOT}/k8s-lab/argocd-config" >/dev/null
kube --namespace "${ARGO_NAMESPACE}" rollout restart deployment/argocd-server >/dev/null
kube --namespace "${ARGO_NAMESPACE}" rollout status deployment/argocd-server --timeout=300s >/dev/null

server_image="$(kube --namespace "${ARGO_NAMESPACE}" get deployment argocd-server --output jsonpath='{.spec.template.spec.containers[0].image}')"
[[ "${server_image}" == *":${ARGOCD_VERSION}" ]] || die "Argo CD server image is not pinned to ${ARGOCD_VERSION}"

kube --namespace "${ARGO_NAMESPACE}" create secret generic radar-repository \
  --from-literal=type=git \
  --from-literal="url=${repo_url}" \
  --from-file="sshPrivateKey=${repo_key}" \
  --dry-run=client --output yaml | kube apply --filename - >/dev/null
kube --namespace "${ARGO_NAMESPACE}" label secret radar-repository argocd.argoproj.io/secret-type=repository --overwrite >/dev/null

escaped_repo_url="$(printf '%s' "${repo_url}" | sed -e 's/[&|\\]/\\&/g')"
escaped_target_revision="$(printf '%s' "${target_revision}" | sed -e 's/[&|\\]/\\&/g')"
sed "s|REPLACE_WITH_RADAR_REPOSITORY_URL|${escaped_repo_url}|g" \
  "${REPO_ROOT}/k8s-lab/argocd-apps/project.yaml.tmpl" | kube apply --filename - >/dev/null
sed -e "s|REPLACE_WITH_RADAR_REPOSITORY_URL|${escaped_repo_url}|g" \
  -e "s|REPLACE_WITH_RADAR_TARGET_REVISION|${escaped_target_revision}|g" \
  "${REPO_ROOT}/k8s-lab/argocd-apps/radar-lab.yaml.tmpl" | kube apply --filename - >/dev/null

refresh_application
wait_for_synced_healthy 600s
"${SCRIPT_DIR}/create-token.sh" --context "${RADAR_CONTEXT}"
"${SCRIPT_DIR}/verify-baseline.sh" --context "${RADAR_CONTEXT}"

printf 'RADAR lab is ready. The previous kubeconfig current context remains %s.\n' "${current_context_before:-unset}"
