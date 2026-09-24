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
for command_name in curl kubectl minikube stat; do
  require_command "${command_name}"
done

password_file="${RADAR_UI_PASSWORD_FILE}"
[[ -s "${password_file}" && ! -L "${password_file}" ]] || \
  die "UI password file is missing or unsafe; finish lab setup first"
[[ "$(stat --format '%a' "${password_file}")" == "600" ]] || \
  die "UI password file must have mode 0600"

temporary_directory="$(mktemp --directory)"
port_forward_log="${temporary_directory}/port-forward.log"
cleanup() {
  stop_argocd_forward
  rm -rf -- "${temporary_directory}"
}
trap cleanup EXIT

start_argocd_forward "${port_forward_log}"
printf 'Argo CD UI: %s\n' "${ARGOCD_FORWARD_BASE_URL}"
printf 'Username: radar-viewer\n'
printf 'Password file (mode 0600): %s\n' "${password_file}"
printf 'Read it privately with: cat %q\n' "${password_file}"
printf 'Open the URL in a browser. Keep this process running; press Ctrl-C to close the localhost-only tunnel.\n'
wait "${PORT_FORWARD_PID}"
