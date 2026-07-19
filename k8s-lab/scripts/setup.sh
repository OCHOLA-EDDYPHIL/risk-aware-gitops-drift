#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

readonly MINIKUBE_VERSION="v1.38.1"
readonly KUBERNETES_VERSION="v1.35.6"
readonly ARGOCD_VERSION="v3.4.5"
readonly OPA_VERSION="1.17.1"
readonly GO_VERSION="go1.24.0"
readonly MIN_AVAILABLE_KIB="${RADAR_MIN_AVAILABLE_KIB:-4194304}"

usage() {
  printf 'Usage: %s --context radar-lab\n' "$0" >&2
  exit 2
}

[[ $# -eq 2 && "$1" == "--context" ]] || usage
assert_context "$2"

for command_name in minikube kubectl docker jq opa go sed stat; do
  require_command "${command_name}"
done

installed_minikube="$(minikube version --short)"
[[ "${installed_minikube}" == "${MINIKUBE_VERSION}" ]] || die "Minikube ${MINIKUBE_VERSION} is required; found ${installed_minikube}"

installed_opa="$(opa version | awk '/^Version:/ {print $2}')"
[[ "${installed_opa}" == "${OPA_VERSION}" ]] || die "OPA ${OPA_VERSION} is required; found ${installed_opa}"

installed_go="$(go env GOVERSION)"
[[ "${installed_go}" == "${GO_VERSION}" ]] || die "Go ${GO_VERSION} is required; found ${installed_go}"

docker info >/dev/null

available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
[[ "${available_kib}" =~ ^[0-9]+$ ]] || die "could not read available host memory"
if ((available_kib < MIN_AVAILABLE_KIB)); then
  die "at least $((MIN_AVAILABLE_KIB / 1024)) MiB available memory is required; found $((available_kib / 1024)) MiB"
fi

repo_url="${RADAR_REPO_URL:-}"
repo_key="${RADAR_REPO_SSH_KEY_FILE:-}"
target_revision="${RADAR_TARGET_REVISION:-main}"
[[ -n "${repo_url}" ]] || die "RADAR_REPO_URL must identify the private Git repository"
[[ "${repo_url}" != *[[:space:]]* ]] || die "RADAR_REPO_URL must not contain whitespace"
[[ "${target_revision}" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || die "RADAR_TARGET_REVISION contains unsupported characters"
[[ -f "${repo_key}" ]] || die "RADAR_REPO_SSH_KEY_FILE must point to a read-only deploy key"
key_mode="$(stat -c '%a' "${repo_key}")"
[[ "${key_mode: -2}" == "00" ]] || die "repository key must not be readable or writable by group or others"

if minikube profile list --output json | jq -e --arg profile "${RADAR_PROFILE}" \
  '[.valid[]?, .invalid[]?] | any(.Name == $profile)' >/dev/null; then
  die "Minikube profile ${RADAR_PROFILE} already exists; verify or tear it down explicitly"
fi

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

server_version="$(kube version --output json | jq -r '.serverVersion.gitVersion')"
[[ "${server_version}" == "${KUBERNETES_VERSION}" ]] || die "Kubernetes ${KUBERNETES_VERSION} is required; found ${server_version}"

kube create namespace "${ARGO_NAMESPACE}" --dry-run=client --output yaml | kube apply --filename - >/dev/null
kube --namespace "${ARGO_NAMESPACE}" apply --filename \
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
