#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'Usage: %s --context radar-lab\n' "$0" >&2
  exit 2
}

[[ $# -eq 2 && "$1" == "--context" ]] || usage
assert_context "$2"
for command_name in kubectl curl jq base64; do
  require_command "${command_name}"
done

token_file="${RADAR_TOKEN_FILE:-${REPO_ROOT}/.radar-lab-token}"
port_forward_log="$(mktemp)"
trap 'stop_argocd_forward; rm -f "${port_forward_log}"' EXIT
start_argocd_forward 18080 "${port_forward_log}"

admin_password="$(kube --namespace "${ARGO_NAMESPACE}" get secret argocd-initial-admin-secret --output jsonpath='{.data.password}' | base64 --decode)"
admin_token="$({ jq --null-input --compact-output --arg username admin --arg password "${admin_password}" \
  '{username: $username, password: $password}'; } | \
  curl --fail --silent --show-error --request POST \
    --header 'Content-Type: application/json' --data-binary @- \
    http://127.0.0.1:18080/api/v1/session | jq --exit-status --raw-output '.token')"
unset admin_password

token_name="radar-cli-$(date -u +%Y%m%dT%H%M%SZ)"
radar_token="$({ jq --null-input --compact-output --arg name "${token_name}" \
  '{name: $name, expiresIn: 28800}'; } | \
  curl --fail --silent --show-error --request POST \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer ${admin_token}" --data-binary @- \
    http://127.0.0.1:18080/api/v1/account/radar/token | jq --exit-status --raw-output '.token')"
unset admin_token

umask 077
printf '%s\n' "${radar_token}" >"${token_file}"
unset radar_token
printf 'Wrote a short-lived RADAR API token to %s with mode 0600.\n' "${token_file}"
