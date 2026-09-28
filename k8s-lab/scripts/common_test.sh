#!/usr/bin/env bash

set -euo pipefail

TEST_ROOT="$(mktemp --directory)"
trap '[[ -z "${PORT_FORWARD_PID:-}" ]] || stop_argocd_forward; rm -rf "${TEST_ROOT}"' EXIT
export MINIKUBE_HOME="${TEST_ROOT}/minikube"
export FAKE_BIN="${TEST_ROOT}/bin"
export FAKE_OPERATION_LOG="${TEST_ROOT}/operations.log"
export ACTUAL_UID="trusted-uid"
mkdir -p "${FAKE_BIN}" "${MINIKUBE_HOME}/.minikube/profiles/radar-lab"

cat >"${TEST_ROOT}/forward.py" <<'PY'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200 if self.path == "/healthz" else 404)
        self.end_headers()
    def log_message(self, *_):
        pass
server = HTTPServer(("127.0.0.1", 0), Handler)
print(f"Forwarding from 127.0.0.1:{server.server_port} -> 80", flush=True)
server.serve_forever()
PY
chmod +x "${TEST_ROOT}/forward.py"
export FAKE_FORWARD="${TEST_ROOT}/forward.py"

cat >"${FAKE_BIN}/minikube" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"status"* ]]; then exit 0; fi
if [[ "$*" == *"kubectl --ssh"* ]]; then printf '%s' trusted-uid; exit 0; fi
exit 1
SH
cat >"${FAKE_BIN}/kubectl" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"port-forward"* ]]; then exec "${FAKE_FORWARD}"; fi
if [[ "$*" == *"config view"* ]]; then
  printf '%s\n' '{"clusters":[{"cluster":{"server":"https://127.0.0.1:9443","certificate-authority-data":"Y2E="}}]}'
  exit 0
fi
if [[ "$*" == *"get namespace kube-system"* ]]; then printf '%s' "${ACTUAL_UID}"; exit 0; fi
printf '%s\n' "$*" >>"${FAKE_OPERATION_LOG}"
exit 0
SH
chmod +x "${FAKE_BIN}/minikube" "${FAKE_BIN}/kubectl"
export PATH="${FAKE_BIN}:${PATH}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=scenario-integrity.sh disable=SC1091
source "${SCRIPT_DIR}/scenario-integrity.sh"

readonly FROZEN_REVISION="0123456789abcdef0123456789abcdef01234567"
readonly OTHER_REVISION="1123456789abcdef0123456789abcdef01234567"
assert_frozen_application_revision "${FROZEN_REVISION}" "${FROZEN_REVISION}" "${FROZEN_REVISION}" Succeeded
for bad_args in \
  "mutable-ref ${FROZEN_REVISION} ${FROZEN_REVISION} Succeeded" \
  "${FROZEN_REVISION} ${OTHER_REVISION} ${FROZEN_REVISION} Succeeded" \
  "${FROZEN_REVISION} ${FROZEN_REVISION} ${OTHER_REVISION} Succeeded" \
  "${FROZEN_REVISION} ${FROZEN_REVISION} ${FROZEN_REVISION} Running"; do
  # shellcheck disable=SC2086
  if (assert_frozen_application_revision ${bad_args}) >/dev/null 2>&1; then
    printf 'invalid application revision state was accepted\n' >&2
    exit 1
  fi
done

record_lab_cluster_identity
assert_lab_cluster_identity
[[ "$(stat --format '%a' "${RADAR_IDENTITY_FILE}")" == 600 ]]
# shellcheck disable=SC2218
kube get pods >/dev/null
export ACTUAL_UID="unrelated-uid"
before_count="$(wc -l <"${FAKE_OPERATION_LOG}")"
if (kube delete namespace radar-demo) >/dev/null 2>&1; then
  printf 'mismatched cluster identity was accepted\n' >&2
  exit 1
fi
after_count="$(wc -l <"${FAKE_OPERATION_LOG}")"
[[ "${before_count}" == "${after_count}" ]]
export ACTUAL_UID="trusted-uid"

chmod 644 "${RADAR_IDENTITY_FILE}"
if (assert_lab_cluster_identity) >/dev/null 2>&1; then
  printf 'permissive identity file was accepted\n' >&2
  exit 1
fi
chmod 600 "${RADAR_IDENTITY_FILE}"

prebound_pid=""
python3 -m http.server 18080 --bind 127.0.0.1 >"${TEST_ROOT}/prebound.log" 2>&1 &
prebound_pid=$!
sleep 0.2
start_argocd_forward "${TEST_ROOT}/forward.log"
[[ "${ARGOCD_FORWARD_PORT}" != 18080 ]]
socket_owned_by_pid "${PORT_FORWARD_PID}" "${ARGOCD_FORWARD_PORT}"
if socket_owned_by_pid "${prebound_pid}" "${ARGOCD_FORWARD_PORT}"; then
  printf 'unrelated listener was accepted as port-forward owner\n' >&2
  exit 1
fi
stop_argocd_forward
kill "${prebound_pid}" >/dev/null 2>&1 || true
wait "${prebound_pid}" 2>/dev/null || true

snapshot="${TEST_ROOT}/application.json"
jq --null-input --arg revision "${FROZEN_REVISION}" \
  '{metadata:{uid:"uid",resourceVersion:"1"},
    spec:{source:{targetRevision:$revision},syncPolicy:{automated:{selfHeal:false}}},
    status:{sync:{revision:$revision,status:"OutOfSync"},health:{status:"Progressing"},
      operationState:{phase:"Succeeded",syncResult:{revision:$revision}}}}' >"${snapshot}"
validate_application_snapshot "${snapshot}" "${FROZEN_REVISION}" OutOfSync
jq '.spec.syncPolicy.automated.selfHeal = true' "${snapshot}" >"${snapshot}.bad"
if validate_application_snapshot "${snapshot}.bad" "${FROZEN_REVISION}" OutOfSync; then
  printf 'self-healing Application snapshot was accepted\n' >&2
  exit 1
fi

RUN_TEST_DIR="${TEST_ROOT}/reset"
mkdir -p "${RUN_TEST_DIR}"
kube() { return 1; }
wait_for_synced_healthy() { return 0; }
verify_declared_baseline() { return 0; }
if reset_baseline "${FROZEN_REVISION}" "${RUN_TEST_DIR}"; then
  printf 'conditional-errexit reset regression returned success\n' >&2
  exit 1
fi
[[ ! -f "${RUN_TEST_DIR}/reset.json" ]]

printf 'Cluster identity, revision, forwarding, snapshot, and reset guards passed.\n'
