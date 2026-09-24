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
for command_name in base64 curl jq kubectl minikube sha256sum stat; do
  require_command "${command_name}"
done

token_file="${RADAR_TOKEN_FILE}"
temporary_directory="$(mktemp --directory)"
port_forward_log="${temporary_directory}/port-forward.log"
trap 'stop_argocd_forward; rm -rf "${temporary_directory}"' EXIT
start_argocd_forward "${port_forward_log}"

session_request="${temporary_directory}/session-request.json"
session_response="${temporary_directory}/session-response.json"
admin_token_file="${temporary_directory}/admin-token"
admin_header_file="${temporary_directory}/admin-header"
token_request="${temporary_directory}/token-request.json"
token_response="${temporary_directory}/token-response.json"
radar_token_temporary="${temporary_directory}/radar-token"
radar_header_file="${temporary_directory}/radar-header"
application_response="${temporary_directory}/application.json"

kube --namespace "${ARGO_NAMESPACE}" get secret argocd-initial-admin-secret \
  --output jsonpath='{.data.password}' | base64 --decode | \
  jq --raw-input --slurp '{username: "admin", password: .}' >"${session_request}"
chmod 600 "${session_request}"
curl --fail --silent --show-error --request POST \
  --header 'Content-Type: application/json' --data-binary "@${session_request}" \
  "${ARGOCD_FORWARD_BASE_URL}/api/v1/session" >"${session_response}"
rm -f "${session_request}"
jq --exit-status --raw-output '.token | select(type == "string" and length > 0)' \
  "${session_response}" >"${admin_token_file}"
rm -f "${session_response}"
{
  printf 'Authorization: Bearer '
  tr -d '\r\n' <"${admin_token_file}"
  printf '\n'
} >"${admin_header_file}"
rm -f "${admin_token_file}"
chmod 600 "${admin_header_file}"

token_name="radar-cli-$(date -u +%Y%m%dT%H%M%SZ)"
jq --null-input --arg name "${token_name}" '{name: $name, expiresIn: 28800}' >"${token_request}"
chmod 600 "${token_request}"
curl --fail --silent --show-error --request POST \
  --header 'Content-Type: application/json' --header "@${admin_header_file}" \
  --data-binary "@${token_request}" \
  "${ARGOCD_FORWARD_BASE_URL}/api/v1/account/radar/token" >"${token_response}"
jq --exit-status --raw-output '.token | select(type == "string" and length > 0)' \
  "${token_response}" >"${radar_token_temporary}"
chmod 600 "${radar_token_temporary}"
{
  printf 'Authorization: Bearer '
  tr -d '\r\n' <"${radar_token_temporary}"
  printf '\n'
} >"${radar_header_file}"
chmod 600 "${radar_header_file}"
curl --fail --silent --show-error --header "@${radar_header_file}" \
  "${ARGOCD_FORWARD_BASE_URL}/api/v1/applications/${RADAR_APP}?project=radar" \
  >"${application_response}"
jq --exit-status --arg app "${RADAR_APP}" \
  '.metadata.name == $app and .spec.project == "radar"' \
  "${application_response}" >/dev/null || die "the RADAR API token cannot read the intended Application"
mkdir -p "$(dirname -- "${token_file}")"
mv "${radar_token_temporary}" "${token_file}"
chmod 600 "${token_file}"
printf 'Wrote a short-lived RADAR API token with mode 0600.\n'
