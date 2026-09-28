#!/usr/bin/env bash

set -euo pipefail

TEST_ROOT="$(mktemp --directory)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
SOURCE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
REPOSITORY="${TEST_ROOT}/repository"
FAKE_BIN="${TEST_ROOT}/bin"
ENV_ROOT="${REPOSITORY}/.radar-env"
PATCH_CAPTURE="${TEST_ROOT}/secret-patch.json"
OPERATION_LOG="${TEST_ROOT}/operations.log"
mkdir -p \
  "${REPOSITORY}/k8s-lab/scripts" \
  "${REPOSITORY}/scripts" \
  "${ENV_ROOT}/state/minikube/.minikube/profiles/radar-lab" \
  "${TEST_ROOT}/python-modules" \
  "${FAKE_BIN}"

cp "${SOURCE_ROOT}/k8s-lab/scripts/common.sh" \
  "${SOURCE_ROOT}/k8s-lab/scripts/create-ui-account.sh" \
  "${REPOSITORY}/k8s-lab/scripts/"
cp "${SOURCE_ROOT}/scripts/toolchain-versions.sh" "${REPOSITORY}/scripts/"

cat >"${TEST_ROOT}/forward.py" <<'PY'
#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def send_json(self, value):
        payload = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
        elif self.path.startswith("/api/v1/applications/radar-lab?project=radar"):
            if not self.headers.get("Authorization", "").startswith("Bearer "):
                self.send_response(401)
                self.end_headers()
                return
            self.send_json({"metadata": {"name": "radar-lab"}, "spec": {"project": "radar"}})
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        if self.path != "/api/v1/session" or request.get("username") != "radar-viewer" or not request.get("password"):
            self.send_response(400)
            self.end_headers()
            return
        self.send_json({"token": "viewer-session-token"})

    def log_message(self, *_):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
print(f"Forwarding from 127.0.0.1:{server.server_port} -> 80", flush=True)
server.serve_forever()
PY
chmod +x "${TEST_ROOT}/forward.py"

cat >"${TEST_ROOT}/python-modules/bcrypt.py" <<'PY'
import hashlib
import hmac


def gensalt(rounds=12):
    assert rounds == 12
    return b"radar-test-salt"


def hashpw(password, salt):
    return b"$2b$12$" + hashlib.sha256(salt + password).hexdigest().encode()[:53]


def checkpw(password, password_hash):
    return hmac.compare_digest(hashpw(password, b"radar-test-salt"), password_hash)
PY

cat >"${FAKE_BIN}/minikube" <<'SH'
#!/usr/bin/env bash
[[ "$*" == *"status"* ]]
SH
cat >"${FAKE_BIN}/kubectl" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"port-forward"* ]]; then exec "${FAKE_FORWARD}"; fi
if [[ "$*" == *"config view"* ]]; then
  printf '%s\n' '{"clusters":[{"cluster":{"server":"https://127.0.0.1:9443","certificate-authority-data":"Y2E="}}]}'
  exit 0
fi
if [[ "$*" == *"get namespace kube-system"* ]]; then printf '%s' trusted-uid; exit 0; fi
printf '%s\n' "$*" >>"${OPERATION_LOG}"
previous=""
for argument in "$@"; do
  if [[ "${previous}" == "--patch-file" ]]; then
    cp -- "${argument}" "${PATCH_CAPTURE}"
  fi
  previous="${argument}"
done
exit 0
SH
chmod +x "${FAKE_BIN}/minikube" "${FAKE_BIN}/kubectl"

ca_sha256="$(printf ca | sha256sum | awk '{print $1}')"
jq --null-input \
  --arg server https://127.0.0.1:9443 \
  --arg caSha256 "${ca_sha256}" \
  '{profile:"radar-lab",context:"radar-lab",server:$server,
    caSha256:$caSha256,clusterUid:"trusted-uid"}' \
  >"${ENV_ROOT}/state/minikube/.minikube/profiles/radar-lab/radar-identity.json"
chmod 600 "${ENV_ROOT}/state/minikube/.minikube/profiles/radar-lab/radar-identity.json"
printf 'radar-api-token' >"${ENV_ROOT}/state/radar-token"
chmod 600 "${ENV_ROOT}/state/radar-token"
touch "${ENV_ROOT}/state/kubeconfig"
chmod 600 "${ENV_ROOT}/state/kubeconfig"

export FAKE_FORWARD="${TEST_ROOT}/forward.py"
export PATCH_CAPTURE OPERATION_LOG
export RADAR_ENV_ACTIVE=1
export RADAR_ENV_ROOT="${ENV_ROOT}"
export MINIKUBE_HOME="${ENV_ROOT}/state/minikube"
export KUBECONFIG="${ENV_ROOT}/state/kubeconfig"
export RADAR_TOKEN_FILE="${ENV_ROOT}/state/radar-token"
export RADAR_UI_PASSWORD_FILE="${ENV_ROOT}/state/argocd-ui-password"
export PYTHONPATH="${TEST_ROOT}/python-modules"
export PATH="${FAKE_BIN}:${PATH}"

"${REPOSITORY}/k8s-lab/scripts/create-ui-account.sh" --context radar-lab >/dev/null
[[ -s "${RADAR_UI_PASSWORD_FILE}" && ! -L "${RADAR_UI_PASSWORD_FILE}" ]]
[[ "$(stat --format '%a' "${RADAR_UI_PASSWORD_FILE}")" == "600" ]]
jq --exit-status '
  (.data["accounts.radar-viewer.password"] | type == "string" and length > 0) and
  (.data["accounts.radar-viewer.passwordMtime"] | @base64d | test("Z$"))
' "${PATCH_CAPTURE}" >/dev/null

python3 - "${RADAR_UI_PASSWORD_FILE}" "${PATCH_CAPTURE}" <<'PY'
import base64
import json
import sys
from pathlib import Path

import bcrypt

password = Path(sys.argv[1]).read_bytes()
patch = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
encoded = patch["data"]["accounts.radar-viewer.password"]
assert bcrypt.checkpw(password, base64.b64decode(encoded))
PY

while IFS= read -r operation; do
  [[ "${operation}" == *"--context radar-lab"* ]]
done <"${OPERATION_LOG}"

printf 'Read-only UI credential provisioning guards passed.\n'
