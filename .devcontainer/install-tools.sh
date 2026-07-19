#!/usr/bin/env bash

set -euo pipefail

readonly GO_VERSION="1.22.12"
readonly GO_SHA256="4fa4f869b0f7fc6bb1eb2660e74657fbf04cdd290b5aef905585c86051b34d43"
readonly MINIKUBE_VERSION="v1.38.1"
readonly MINIKUBE_SHA256="099477eaf248bcb5bcea8ce78a2898e93ac01461c35189da1848c3de82ecd22e"
readonly KUBECTL_VERSION="v1.35.6"
readonly KUBECTL_SHA256="5d11e2ba01ea68ffd053f56e27738e2b4330013ee67f7e46c6da6c585d3c9926"
readonly OPA_VERSION="v1.17.1"
readonly OPA_SHA256="3d4bb88482958d990351ec5d2f7558509992776bc473bc1b78d86d76cb993ca3"
readonly GIT_LFS_VERSION="3.7.1"
readonly GIT_LFS_SHA256="1c0b6ee5200ca708c5cebebb18fdeb0e1c98f1af5c1a9cba205a4c0ab5a5ec08"

download_verified() {
  local url="$1"
  local destination="$2"
  local expected_sha256="$3"

  curl --fail --location --silent --show-error \
    --retry 5 --retry-all-errors --retry-delay 2 \
    "${url}" --output "${destination}"
  printf '%s  %s\n' "${expected_sha256}" "${destination}" | sha256sum --check --status || {
    printf 'Checksum verification failed for %s\n' "${url}" >&2
    exit 1
  }
}

sudo apt-get update
sudo apt-get install --yes --no-install-recommends \
  ca-certificates curl jq libxml2-utils make python3-yaml shellcheck tar zstd
sudo rm -rf /var/lib/apt/lists/*

temporary_directory="$(mktemp --directory)"
trap 'rm -rf "${temporary_directory}"' EXIT

download_verified \
  "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
  "${temporary_directory}/go.tar.gz" \
  "${GO_SHA256}"
sudo rm -rf /usr/local/go
sudo tar --extract --gzip --file "${temporary_directory}/go.tar.gz" --directory /usr/local
sudo ln --symbolic --force /usr/local/go/bin/go /usr/local/bin/go
sudo ln --symbolic --force /usr/local/go/bin/gofmt /usr/local/bin/gofmt

download_verified \
  "https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64" \
  "${temporary_directory}/minikube" \
  "${MINIKUBE_SHA256}"
sudo install --mode 0755 "${temporary_directory}/minikube" /usr/local/bin/minikube

download_verified \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  "${temporary_directory}/kubectl" \
  "${KUBECTL_SHA256}"
sudo install --mode 0755 "${temporary_directory}/kubectl" /usr/local/bin/kubectl

download_verified \
  "https://github.com/open-policy-agent/opa/releases/download/${OPA_VERSION}/opa_linux_amd64_static" \
  "${temporary_directory}/opa" \
  "${OPA_SHA256}"
sudo install --mode 0755 "${temporary_directory}/opa" /usr/local/bin/opa

download_verified \
  "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-amd64-v${GIT_LFS_VERSION}.tar.gz" \
  "${temporary_directory}/git-lfs.tar.gz" \
  "${GIT_LFS_SHA256}"
tar --extract --gzip --file "${temporary_directory}/git-lfs.tar.gz" --directory "${temporary_directory}"
sudo install --mode 0755 \
  "${temporary_directory}/git-lfs-${GIT_LFS_VERSION}/git-lfs" \
  /usr/local/bin/git-lfs
git lfs install --local

go version
minikube version --short
kubectl version --client --output json | jq --exit-status --raw-output '.clientVersion.gitVersion'
opa version | sed -n '1,2p'
git lfs version
docker version --format '{{.Client.Version}} / {{.Server.Version}}'
