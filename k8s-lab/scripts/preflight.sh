#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

readonly MIN_AVAILABLE_KIB="${RADAR_MIN_AVAILABLE_KIB:-4194304}"
readonly MIN_CPU_COUNT=2

usage() {
  printf 'Usage: %s --context radar-lab\n' "$0" >&2
  exit 2
}

[[ $# -eq 2 && "$1" == "--context" ]] || usage
assert_context "$2"
"${REPO_ROOT}/scripts/check-env.sh" >/dev/null

[[ "$(uname --kernel-name)" == "Linux" ]] || die "the controlled lab requires a Linux host"
[[ -r /proc/meminfo ]] || die "the controlled lab requires Linux memory information from /proc/meminfo"
[[ "${MIN_AVAILABLE_KIB}" =~ ^[1-9][0-9]*$ ]] || die "RADAR_MIN_AVAILABLE_KIB must be a positive integer"

for command_name in docker git go jq kubectl minikube nproc opa sed sha256sum stat; do
  require_command "${command_name}"
done
git -C "${REPO_ROOT}" lfs version >/dev/null

[[ -z "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=normal)" ]] || die "working tree must be clean before lab setup"

cpu_count="$(nproc)"
[[ "${cpu_count}" =~ ^[0-9]+$ ]] || die "could not read the host CPU count"
((cpu_count >= MIN_CPU_COUNT)) || die "at least ${MIN_CPU_COUNT} CPUs are required; found ${cpu_count}"

available_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
[[ "${available_kib}" =~ ^[0-9]+$ ]] || die "could not read available host memory"
if ((available_kib < MIN_AVAILABLE_KIB)); then
  die "at least $((MIN_AVAILABLE_KIB / 1024)) MiB available memory is required; found $((available_kib / 1024)) MiB"
fi

installed_minikube="$(minikube version --short)"
[[ "${installed_minikube}" == "v${RADAR_MINIKUBE_VERSION}" ]] || die "Minikube v${RADAR_MINIKUBE_VERSION} is required; found ${installed_minikube}"

installed_kubectl="$(kubectl version --client --output json | jq --raw-output '.clientVersion.gitVersion')"
[[ "${installed_kubectl}" == "v${RADAR_KUBECTL_VERSION}" ]] || die "kubectl v${RADAR_KUBECTL_VERSION} is required; found ${installed_kubectl}"

installed_opa="$(opa version | awk '/^Version:/ {print $2}')"
[[ "${installed_opa}" == "${RADAR_OPA_VERSION}" ]] || die "OPA ${RADAR_OPA_VERSION} is required; found ${installed_opa}"

installed_go="$(go env GOVERSION)"
[[ "${installed_go}" == "go${RADAR_GO_VERSION}" ]] || die "Go go${RADAR_GO_VERSION} is required; found ${installed_go}"

docker info >/dev/null

profile_list="$(minikube profile list --output json 2>/dev/null || true)"
if [[ -n "${profile_list}" ]] && jq --exit-status --arg profile "${RADAR_PROFILE}" \
  '[.valid[]?, .invalid[]?] | any(.Name == $profile)' <<<"${profile_list}" >/dev/null; then
  die "Minikube profile ${RADAR_PROFILE} already exists; verify or tear it down explicitly"
fi

printf 'RADAR lab preflight passed on this Linux host.\n'
