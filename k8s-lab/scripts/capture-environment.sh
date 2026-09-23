#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'Usage: %s --collection-id <identifier> --provider <label> [--region <region>] [--machine-type <type>] --output <environment.json>\n' "$0" >&2
  exit 2
}

collection_id=""
provider=""
region=""
machine_type=""
output_path=""
collection_id_set=false
provider_set=false
region_set=false
machine_type_set=false
output_path_set=false
while (($# > 0)); do
  case "$1" in
    --collection-id)
      (($# >= 2)) || usage
      [[ "${collection_id_set}" == false ]] || die "collection identifier was provided more than once"
      collection_id="$2"
      collection_id_set=true
      shift 2
      ;;
    --provider)
      (($# >= 2)) || usage
      [[ "${provider_set}" == false ]] || die "provider was provided more than once"
      provider="$2"
      provider_set=true
      shift 2
      ;;
    --output)
      (($# >= 2)) || usage
      [[ "${output_path_set}" == false ]] || die "output was provided more than once"
      output_path="$2"
      output_path_set=true
      shift 2
      ;;
    --region)
      (($# >= 2)) || usage
      [[ "${region_set}" == false ]] || die "region was provided more than once"
      region="$2"
      region_set=true
      shift 2
      ;;
    --machine-type)
      (($# >= 2)) || usage
      [[ "${machine_type_set}" == false ]] || die "machine type was provided more than once"
      machine_type="$2"
      machine_type_set=true
      shift 2
      ;;
    *) usage ;;
  esac
done

label_pattern='^[A-Za-z0-9][A-Za-z0-9._ -]*$'
[[ "${collection_id}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "collection identifier contains unsupported characters"
[[ "${provider}" =~ ${label_pattern} ]] || die "provider contains unsupported characters"
[[ -z "${region}" || "${region}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "region contains unsupported characters"
[[ -z "${machine_type}" || "${machine_type}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "machine type contains unsupported characters"
[[ -n "${output_path}" ]] || usage
[[ "$(uname --kernel-name)" == "Linux" ]] || die "environment capture requires a Linux host"
[[ -r /proc/meminfo ]] || die "environment capture requires Linux memory information from /proc/meminfo"
[[ -z "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=normal)" ]] || die "working tree must be clean before environment capture"
[[ ! -e "${output_path}" && ! -L "${output_path}" ]] || die "environment output already exists: ${output_path}"

for command_name in docker git go jq kubectl minikube opa sha256sum; do
  require_command "${command_name}"
done
git -C "${REPO_ROOT}" lfs version >/dev/null

lab_server_version="not-running"
argocd_server_image="not-running"
if minikube status --profile "${RADAR_PROFILE}" >/dev/null 2>&1; then
  lab_server_version="$(kube version --output json | jq --raw-output '.serverVersion.gitVersion')"
  argocd_server_image="$(kube --namespace "${ARGO_NAMESPACE}" get deployment argocd-server --output jsonpath='{.spec.template.spec.containers[0].image}')"
fi

mkdir -p "$(dirname -- "${output_path}")"
jq --null-input \
  --arg collectionId "${collection_id}" \
  --arg capturedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg provider "${provider}" \
  --arg region "${region}" \
  --arg machineType "${machine_type}" \
  --argjson hostCpuCount "$(nproc)" \
  --argjson hostMemoryBytes "$(( $(awk '/^MemTotal:/ {print $2}' /proc/meminfo) * 1024 ))" \
  --argjson availableMemoryBytes "$(( $(awk '/^MemAvailable:/ {print $2}' /proc/meminfo) * 1024 ))" \
  --argjson workspaceAvailableBytes "$(df --output=avail --block-size=1 "${REPO_ROOT}" | tail -1 | tr -d ' ')" \
  --arg gitCommit "$(git -C "${REPO_ROOT}" rev-parse HEAD)" \
  --arg goVersion "$(go version)" \
  --arg minikubeVersion "$(minikube version --short)" \
  --arg kubectlClientVersion "$(kubectl version --client --output json | jq --raw-output '.clientVersion.gitVersion')" \
  --arg kubernetesServerVersion "${lab_server_version}" \
  --arg opaVersion "$(opa version | awk '/^Version:/ {print $2}')" \
  --arg gitLfsVersion "$(git -C "${REPO_ROOT}" lfs version | awk '{print $1}')" \
  --arg dockerClientVersion "$(docker version --format '{{.Client.Version}}')" \
  --arg dockerServerVersion "$(docker version --format '{{.Server.Version}}')" \
  --arg argocdServerImage "${argocd_server_image}" \
  '{
    collectionId: $collectionId,
    capturedAt: $capturedAt,
    evidenceTier: "environment-provenance",
    provider: $provider,
    environment: {
      region: (if $region == "" then null else $region end),
      machineType: (if $machineType == "" then null else $machineType end),
      cpuCount: $hostCpuCount,
      memoryBytes: $hostMemoryBytes,
      availableMemoryBytes: $availableMemoryBytes,
      workspaceAvailableBytes: $workspaceAvailableBytes
    },
    source: {commit: $gitCommit},
    versions: {
      go: $goVersion,
      minikube: $minikubeVersion,
      kubectlClient: $kubectlClientVersion,
      kubernetesServer: $kubernetesServerVersion,
      opa: $opaVersion,
      gitLfs: $gitLfsVersion,
      dockerClient: $dockerClientVersion,
      dockerServer: $dockerServerVersion,
      argocdServerImage: $argocdServerImage
    }
  }' >"${output_path}"

sha256sum "${output_path}" >"${output_path}.sha256"
printf 'Captured environment provenance at %s\n' "${output_path}"
