#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT

sudo apt-get update
sudo apt-get install --yes --no-install-recommends \
  ca-certificates curl git libxml2-utils make python3 python3-venv tar xz-utils zstd
sudo apt-get clean

"${REPO_ROOT}/scripts/bootstrap-env.sh"
docker version --format '{{.Client.Version}} / {{.Server.Version}}'
