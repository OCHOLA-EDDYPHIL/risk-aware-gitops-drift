#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
# shellcheck source=toolchain-versions.sh disable=SC1091
source "${SCRIPT_DIR}/toolchain-versions.sh"

readonly ENV_ROOT="${REPO_ROOT}/.radar-env"

die() {
  printf 'RADAR environment check failed: %s\n' "$*" >&2
  exit 1
}

[[ "${RADAR_ENV_ACTIVE:-}" == "1" ]] || die "activate the environment with: source scripts/activate-env.sh"
[[ "${RADAR_ENV_ROOT:-}" == "${ENV_ROOT}" ]] || die "RADAR_ENV_ROOT is outside this repository"

expect_path() {
  local command_name="$1"
  local expected="$2"
  local actual
  actual="$(command -v "${command_name}" 2>/dev/null || true)"
  [[ "${actual}" == "${expected}" ]] || die "${command_name} resolved to ${actual:-nothing}; expected ${expected}"
}

expect_path go "${ENV_ROOT}/go/bin/go"
expect_path gofmt "${ENV_ROOT}/go/bin/gofmt"
expect_path python3 "${ENV_ROOT}/python/bin/python3"
for command_name in git-lfs jq kubectl minikube opa shellcheck; do
  expect_path "${command_name}" "${ENV_ROOT}/bin/${command_name}"
done

[[ "$(go env GOVERSION)" == "go${RADAR_GO_VERSION}" ]] || die "unexpected Go version"
[[ "$(minikube version --short)" == "v${RADAR_MINIKUBE_VERSION}" ]] || die "unexpected Minikube version"
[[ "$(kubectl version --client --output json | jq --raw-output '.clientVersion.gitVersion')" == "v${RADAR_KUBECTL_VERSION}" ]] || die "unexpected kubectl version"
[[ "$(opa version | awk '/^Version:/ {print $2}')" == "${RADAR_OPA_VERSION}" ]] || die "unexpected OPA version"
[[ "$(jq --version)" == "jq-${RADAR_JQ_VERSION}" ]] || die "unexpected jq version"
[[ "$(git lfs version | sed -n 's#^git-lfs/\([^ ]*\).*#\1#p')" == "${RADAR_GIT_LFS_VERSION}" ]] || die "unexpected Git LFS version"
[[ "$(shellcheck --version | awk '/^version:/ {print $2}')" == "${RADAR_SHELLCHECK_VERSION}" ]] || die "unexpected ShellCheck version"
python3 -c "import bcrypt, yaml; assert bcrypt.__version__ == '${RADAR_BCRYPT_VERSION}'; assert yaml.__version__ == '${RADAR_PYYAML_VERSION}'" ||
  die "unexpected Python tooling versions"
python3 -c 'import sys; raise SystemExit(not ((3, 10) <= sys.version_info[:2] <= (3, 14)))' ||
  die "unexpected Python interpreter version"

[[ "${MINIKUBE_HOME:-}" == "${ENV_ROOT}/state/minikube" ]] || die "MINIKUBE_HOME is not isolated"
[[ "${KUBECONFIG:-}" == "${ENV_ROOT}/state/kubeconfig" ]] || die "KUBECONFIG is not isolated"
[[ "${RADAR_TOKEN_FILE:-}" == "${ENV_ROOT}/state/radar-token" ]] || die "RADAR_TOKEN_FILE is not isolated"
[[ "${RADAR_UI_PASSWORD_FILE:-}" == "${ENV_ROOT}/state/argocd-ui-password" ]] || die "RADAR_UI_PASSWORD_FILE is not isolated"

printf 'RADAR project environment verified.\n'
printf 'Go %s; Minikube %s; kubectl %s; OPA %s; jq %s; Git LFS %s; ShellCheck %s.\n' \
  "${RADAR_GO_VERSION}" "${RADAR_MINIKUBE_VERSION}" "${RADAR_KUBECTL_VERSION}" \
  "${RADAR_OPA_VERSION}" "${RADAR_JQ_VERSION}" "${RADAR_GIT_LFS_VERSION}" "${RADAR_SHELLCHECK_VERSION}"
