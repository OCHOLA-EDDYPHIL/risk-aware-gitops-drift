#!/usr/bin/env bash

set -euo pipefail

TEST_ROOT="$(mktemp --directory)"
trap 'rm -rf "${TEST_ROOT}"' EXIT
REPOSITORY="${TEST_ROOT}/repository"
FAKE_BIN="${TEST_ROOT}/bin"
OUTPUT_ROOT="${TEST_ROOT}/output"
mkdir -p "${REPOSITORY}/k8s-lab/scripts" "${FAKE_BIN}" "${OUTPUT_ROOT}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cp "${SCRIPT_DIR}/common.sh" "${SCRIPT_DIR}/capture-environment.sh" "${SCRIPT_DIR}/preflight.sh" \
  "${SCRIPT_DIR}/capture-codespace-environment.sh" "${REPOSITORY}/k8s-lab/scripts/"

cat >"${FAKE_BIN}/docker" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "version" ]]; then printf '29.6.2\n'; exit 0; fi
exit 0
SH
cat >"${FAKE_BIN}/go" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "env" ]]; then printf 'go1.24.0\n'; exit 0; fi
printf 'go version go1.24.0 linux/amd64\n'
SH
cat >"${FAKE_BIN}/kubectl" <<'SH'
#!/usr/bin/env bash
printf '{"clientVersion":{"gitVersion":"v1.35.6"}}\n'
SH
cat >"${FAKE_BIN}/minikube" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "status" ]]; then exit 1; fi
if [[ "$1 $2 $3" == "profile list --output" ]]; then printf '{"valid":[],"invalid":[]}\n'; exit 0; fi
printf 'v1.38.1\n'
SH
cat >"${FAKE_BIN}/opa" <<'SH'
#!/usr/bin/env bash
printf 'Version: 1.17.1\n'
SH
cat >"${FAKE_BIN}/git-lfs" <<'SH'
#!/usr/bin/env bash
printf 'git-lfs/3.7.1 (test)\n'
SH
chmod +x "${FAKE_BIN}"/* "${REPOSITORY}/k8s-lab/scripts/"*.sh

git -C "${REPOSITORY}" init --quiet
git -C "${REPOSITORY}" update-index --add \
  k8s-lab/scripts/common.sh \
  k8s-lab/scripts/capture-environment.sh \
  k8s-lab/scripts/capture-codespace-environment.sh \
  k8s-lab/scripts/preflight.sh
git -C "${REPOSITORY}" -c user.name=RADAR -c user.email=radar@example.invalid \
  commit --quiet --no-gpg-sign --message initial

PATH="${FAKE_BIN}:${PATH}" "${REPOSITORY}/k8s-lab/scripts/capture-environment.sh" \
  --collection-id local-test \
  --provider local-linux \
  --output "${OUTPUT_ROOT}/local.json" >/dev/null

jq --exit-status '
  .collectionId == "local-test" and
  .provider == "local-linux" and
  .environment.region == null and
  .environment.machineType == null and
  .versions.kubernetesServer == "not-running"
' "${OUTPUT_ROOT}/local.json" >/dev/null
(cd "${OUTPUT_ROOT}" && sha256sum --check local.json.sha256 >/dev/null)

RADAR_MIN_AVAILABLE_KIB=1 PATH="${FAKE_BIN}:${PATH}" \
  "${REPOSITORY}/k8s-lab/scripts/preflight.sh" --context radar-lab >/dev/null

if PATH="${FAKE_BIN}:${PATH}" "${REPOSITORY}/k8s-lab/scripts/capture-environment.sh" \
  --collection-id local-test --provider local-linux \
  --output "${OUTPUT_ROOT}/local.json" >/dev/null 2>&1; then
  printf 'existing environment output was overwritten\n' >&2
  exit 1
fi

if PATH="${FAKE_BIN}:${PATH}" "${REPOSITORY}/k8s-lab/scripts/capture-environment.sh" \
  --collection-id duplicate-test --provider local-linux --provider cloud-vm \
  --output "${OUTPUT_ROOT}/duplicate.json" >/dev/null 2>&1; then
  printf 'duplicate provider metadata was accepted\n' >&2
  exit 1
fi

if PATH="${FAKE_BIN}:${PATH}" "${REPOSITORY}/k8s-lab/scripts/capture-codespace-environment.sh" \
  --collection-id codespace-test --region TestRegion --machine-type testMachine \
  --output "${OUTPUT_ROOT}/codespace.json" >/dev/null 2>&1; then
  printf 'Codespaces wrapper ran outside Codespaces\n' >&2
  exit 1
fi

CODESPACES=true PATH="${FAKE_BIN}:${PATH}" \
  "${REPOSITORY}/k8s-lab/scripts/capture-codespace-environment.sh" \
  --collection-id codespace-test --region TestRegion --machine-type testMachine \
  --output "${OUTPUT_ROOT}/codespace.json" >/dev/null
jq --exit-status '
  .provider == "GitHub Codespaces" and
  .environment.region == "TestRegion" and
  .environment.machineType == "testMachine"
' "${OUTPUT_ROOT}/codespace.json" >/dev/null

touch "${REPOSITORY}/untracked"
if PATH="${FAKE_BIN}:${PATH}" "${REPOSITORY}/k8s-lab/scripts/capture-environment.sh" \
  --collection-id dirty-test --provider local-linux \
  --output "${OUTPUT_ROOT}/dirty.json" >/dev/null 2>&1; then
  printf 'dirty working tree was accepted\n' >&2
  exit 1
fi

printf 'Provider-neutral environment capture guards passed.\n'
