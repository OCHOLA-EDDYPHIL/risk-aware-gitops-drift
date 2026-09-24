#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
# shellcheck source=toolchain-versions.sh disable=SC1091
source "${SCRIPT_DIR}/toolchain-versions.sh"

readonly ENV_ROOT="${REPO_ROOT}/.radar-env"
readonly BIN_DIR="${ENV_ROOT}/bin"
readonly DOWNLOAD_DIR="${ENV_ROOT}/downloads"
readonly STATE_DIR="${ENV_ROOT}/state"
readonly CACHE_DIR="${ENV_ROOT}/cache"
readonly LOCK_DIR="${ENV_ROOT}/.bootstrap-lock"

temporary_directory=""

die() {
  printf 'RADAR environment bootstrap failed: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${temporary_directory}" && -d "${temporary_directory}" ]]; then
    rm -rf -- "${temporary_directory}"
  fi
  rmdir -- "${LOCK_DIR}" 2>/dev/null || true
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required host command not found: $1"
}

download_verified() {
  local url="$1"
  local filename="$2"
  local expected_sha256="$3"
  local destination="${DOWNLOAD_DIR}/${filename}"
  local temporary_download

  if [[ -f "${destination}" ]] &&
    printf '%s  %s\n' "${expected_sha256}" "${destination}" | sha256sum --check --status; then
    return
  fi

  temporary_download="$(mktemp "${DOWNLOAD_DIR}/.${filename}.XXXXXX")"
  curl --fail --location --silent --show-error \
    --retry 5 --retry-all-errors --retry-delay 2 \
    "${url}" --output "${temporary_download}"
  if ! printf '%s  %s\n' "${expected_sha256}" "${temporary_download}" | sha256sum --check --status; then
    rm -f -- "${temporary_download}"
    die "checksum verification failed for ${url}"
  fi
  mv -- "${temporary_download}" "${destination}"
}

[[ "$(uname --kernel-name)" == "Linux" ]] || die "only Linux hosts are supported"
[[ "$(uname --machine)" == "x86_64" ]] || die "only Linux x86-64 hosts are supported"

for command_name in curl git install python3 sha256sum tar xz; do
  require_command "${command_name}"
done
python3 -c 'import sys; raise SystemExit(not ((3, 10) <= sys.version_info[:2] <= (3, 14)))' || \
  die "Python 3.10 through 3.14 is required"

mkdir -p -- "${BIN_DIR}" "${DOWNLOAD_DIR}" "${STATE_DIR}" "${CACHE_DIR}"
mkdir -- "${LOCK_DIR}" 2>/dev/null || die "another environment bootstrap is already running"
trap cleanup EXIT
temporary_directory="$(mktemp --directory "${ENV_ROOT}/bootstrap.XXXXXX")"

download_verified \
  "https://go.dev/dl/go${RADAR_GO_VERSION}.linux-amd64.tar.gz" \
  "go${RADAR_GO_VERSION}.linux-amd64.tar.gz" "${RADAR_GO_SHA256}"
download_verified \
  "https://github.com/kubernetes/minikube/releases/download/v${RADAR_MINIKUBE_VERSION}/minikube-linux-amd64" \
  "minikube-v${RADAR_MINIKUBE_VERSION}-linux-amd64" "${RADAR_MINIKUBE_SHA256}"
download_verified \
  "https://dl.k8s.io/release/v${RADAR_KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  "kubectl-v${RADAR_KUBECTL_VERSION}-linux-amd64" "${RADAR_KUBECTL_SHA256}"
download_verified \
  "https://github.com/open-policy-agent/opa/releases/download/v${RADAR_OPA_VERSION}/opa_linux_amd64_static" \
  "opa-v${RADAR_OPA_VERSION}-linux-amd64" "${RADAR_OPA_SHA256}"
download_verified \
  "https://github.com/git-lfs/git-lfs/releases/download/v${RADAR_GIT_LFS_VERSION}/git-lfs-linux-amd64-v${RADAR_GIT_LFS_VERSION}.tar.gz" \
  "git-lfs-v${RADAR_GIT_LFS_VERSION}-linux-amd64.tar.gz" "${RADAR_GIT_LFS_SHA256}"
download_verified \
  "https://github.com/jqlang/jq/releases/download/jq-${RADAR_JQ_VERSION}/jq-linux-amd64" \
  "jq-${RADAR_JQ_VERSION}-linux-amd64" "${RADAR_JQ_SHA256}"
download_verified \
  "https://github.com/koalaman/shellcheck/releases/download/v${RADAR_SHELLCHECK_VERSION}/shellcheck-v${RADAR_SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
  "shellcheck-v${RADAR_SHELLCHECK_VERSION}.linux.x86_64.tar.xz" "${RADAR_SHELLCHECK_SHA256}"

go_is_current=false
if [[ -x "${ENV_ROOT}/go/bin/go" ]] && \
  [[ "$("${ENV_ROOT}/go/bin/go" env GOVERSION 2>/dev/null || true)" == "go${RADAR_GO_VERSION}" ]]; then
  go_is_current=true
fi
if [[ "${go_is_current}" == false ]]; then
  mkdir -p -- "${temporary_directory}/go"
  tar --extract --gzip \
    --file "${DOWNLOAD_DIR}/go${RADAR_GO_VERSION}.linux-amd64.tar.gz" \
    --directory "${temporary_directory}/go"
  [[ -x "${temporary_directory}/go/go/bin/go" ]] || die "downloaded Go archive is incomplete"
  if [[ -e "${ENV_ROOT}/go" || -L "${ENV_ROOT}/go" ]]; then
    mv -- "${ENV_ROOT}/go" "${temporary_directory}/previous-go"
  fi
  if ! mv -- "${temporary_directory}/go/go" "${ENV_ROOT}/go"; then
    [[ ! -e "${temporary_directory}/previous-go" ]] || \
      mv -- "${temporary_directory}/previous-go" "${ENV_ROOT}/go"
    die "could not install Go into the project environment"
  fi
fi

install --mode 0755 "${DOWNLOAD_DIR}/minikube-v${RADAR_MINIKUBE_VERSION}-linux-amd64" "${BIN_DIR}/minikube"
install --mode 0755 "${DOWNLOAD_DIR}/kubectl-v${RADAR_KUBECTL_VERSION}-linux-amd64" "${BIN_DIR}/kubectl"
install --mode 0755 "${DOWNLOAD_DIR}/opa-v${RADAR_OPA_VERSION}-linux-amd64" "${BIN_DIR}/opa"
install --mode 0755 "${DOWNLOAD_DIR}/jq-${RADAR_JQ_VERSION}-linux-amd64" "${BIN_DIR}/jq"

mkdir -p -- "${temporary_directory}/git-lfs" "${temporary_directory}/shellcheck"
tar --extract --gzip \
  --file "${DOWNLOAD_DIR}/git-lfs-v${RADAR_GIT_LFS_VERSION}-linux-amd64.tar.gz" \
  --directory "${temporary_directory}/git-lfs"
install --mode 0755 \
  "${temporary_directory}/git-lfs/git-lfs-${RADAR_GIT_LFS_VERSION}/git-lfs" \
  "${BIN_DIR}/git-lfs"
tar --extract --xz \
  --file "${DOWNLOAD_DIR}/shellcheck-v${RADAR_SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
  --directory "${temporary_directory}/shellcheck"
install --mode 0755 \
  "${temporary_directory}/shellcheck/shellcheck-v${RADAR_SHELLCHECK_VERSION}/shellcheck" \
  "${BIN_DIR}/shellcheck"

python_is_current=false
if [[ -x "${ENV_ROOT}/python/bin/python3" ]] && \
  "${ENV_ROOT}/python/bin/python3" -c \
    'import sys; raise SystemExit(not ((3, 10) <= sys.version_info[:2] <= (3, 14)))' 2>/dev/null; then
  python_is_current=true
fi
if [[ "${python_is_current}" == false ]]; then
  if [[ -e "${ENV_ROOT}/python" || -L "${ENV_ROOT}/python" ]]; then
    mv -- "${ENV_ROOT}/python" "${temporary_directory}/previous-python"
  fi
  if ! python3 -m venv "${ENV_ROOT}/python"; then
    [[ ! -e "${temporary_directory}/previous-python" ]] || \
      mv -- "${temporary_directory}/previous-python" "${ENV_ROOT}/python"
    die "python3 venv support is required to create the project-local tooling environment"
  fi
fi
PIP_CACHE_DIR="${CACHE_DIR}/pip" "${ENV_ROOT}/python/bin/python3" -m pip install \
  --disable-pip-version-check --require-hashes \
  --requirement "${SCRIPT_DIR}/requirements-tooling.txt"

chmod 0700 "${STATE_DIR}"
touch "${STATE_DIR}/kubeconfig"
chmod 0600 "${STATE_DIR}/kubeconfig"

RADAR_ENV_ROOT="${ENV_ROOT}" bash -c \
  'source "${1}/activate-env.sh" && "${1}/check-env.sh"' _ "${SCRIPT_DIR}"

PATH="${ENV_ROOT}/go/bin:${ENV_ROOT}/python/bin:${BIN_DIR}:${PATH}" git -C "${REPO_ROOT}" lfs install --local >/dev/null

printf 'RADAR project environment is ready at %s\n' "${ENV_ROOT}"
printf 'Activate it with: source scripts/activate-env.sh\n'
