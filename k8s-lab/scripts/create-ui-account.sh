#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'Usage: %s --context radar-lab\n' "$0" >&2
  exit 2
}

[[ $# -eq 2 && "$1" == "--context" ]] || usage
assert_context "$2"
for command_name in curl jq kubectl minikube python3 stat; do
  require_command "${command_name}"
done

password_file="${RADAR_UI_PASSWORD_FILE}"
[[ ! -e "${password_file}" && ! -L "${password_file}" ]] || \
  die "UI password file already exists; tear down the lab before provisioning another account"

temporary_directory="$(mktemp --directory)"
password_temporary="${temporary_directory}/password"
password_hash="${temporary_directory}/password-hash"
secret_patch="${temporary_directory}/secret-patch.json"
session_request="${temporary_directory}/session-request.json"
session_response="${temporary_directory}/session-response.json"
session_token="${temporary_directory}/session-token"
session_header="${temporary_directory}/session-header"
application_response="${temporary_directory}/application.json"
api_header="${temporary_directory}/api-header"
port_forward_log="${temporary_directory}/port-forward.log"
trap 'stop_argocd_forward; rm -rf "${temporary_directory}"' EXIT

python3 - "${password_temporary}" <<'PY'
import secrets
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(secrets.token_urlsafe(24), encoding="utf-8")
PY
chmod 600 "${password_temporary}"

python3 - "${password_temporary}" "${password_hash}" <<'PY'
import sys
from pathlib import Path

import bcrypt

password = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_bytes(bcrypt.hashpw(password, bcrypt.gensalt(rounds=12)))
PY
chmod 600 "${password_hash}"

jq --null-input \
  --rawfile passwordHash "${password_hash}" \
  --arg passwordMtime "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{data: {
    "accounts.radar-viewer.password": ($passwordHash | @base64),
    "accounts.radar-viewer.passwordMtime": ($passwordMtime | @base64)
  }}' >"${secret_patch}"
chmod 600 "${secret_patch}"
kube --namespace "${ARGO_NAMESPACE}" patch secret argocd-secret \
  --type merge --patch-file "${secret_patch}" >/dev/null

kube --namespace "${ARGO_NAMESPACE}" rollout restart deployment/argocd-server >/dev/null
kube --namespace "${ARGO_NAMESPACE}" rollout status deployment/argocd-server --timeout=300s >/dev/null

jq --null-input --rawfile password "${password_temporary}" \
  '{username: "radar-viewer", password: $password}' >"${session_request}"
chmod 600 "${session_request}"
start_argocd_forward "${port_forward_log}"
curl --fail --silent --show-error --request POST \
  --header 'Content-Type: application/json' --data-binary "@${session_request}" \
  "${ARGOCD_FORWARD_BASE_URL}/api/v1/session" >"${session_response}"
jq --exit-status --raw-output '.token | select(type == "string" and length > 0)' \
  "${session_response}" >"${session_token}"
{
  printf 'Authorization: Bearer '
  tr -d '\r\n' <"${session_token}"
  printf '\n'
} >"${session_header}"
chmod 600 "${session_header}"
curl --fail --silent --show-error --header "@${session_header}" \
  "${ARGOCD_FORWARD_BASE_URL}/api/v1/applications/${RADAR_APP}?project=radar" \
  >"${application_response}"
jq --exit-status --arg app "${RADAR_APP}" \
  '.metadata.name == $app and .spec.project == "radar"' \
  "${application_response}" >/dev/null || die "the UI account cannot read the intended Application"

[[ -s "${RADAR_TOKEN_FILE}" && ! -L "${RADAR_TOKEN_FILE}" ]] || \
  die "RADAR API token is missing or unsafe"
{
  printf 'Authorization: Bearer '
  tr -d '\r\n' <"${RADAR_TOKEN_FILE}"
  printf '\n'
} >"${api_header}"
chmod 600 "${api_header}"
curl --fail --silent --show-error --header "@${api_header}" \
  "${ARGOCD_FORWARD_BASE_URL}/api/v1/applications/${RADAR_APP}?project=radar" \
  >"${application_response}"
jq --exit-status --arg app "${RADAR_APP}" \
  '.metadata.name == $app and .spec.project == "radar"' \
  "${application_response}" >/dev/null || die "the RADAR API token failed after administrator shutdown"
stop_argocd_forward

mkdir -p -- "$(dirname -- "${password_file}")"
mv -- "${password_temporary}" "${password_file}"
chmod 600 "${password_file}"
printf 'Provisioned the read-only Argo CD browser account; its password is stored with mode 0600.\n'
