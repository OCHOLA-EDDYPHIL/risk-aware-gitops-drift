#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

readonly FROZEN_REVISION="0123456789abcdef0123456789abcdef01234567"
readonly OTHER_REVISION="1123456789abcdef0123456789abcdef01234567"

assert_frozen_application_revision "${FROZEN_REVISION}" "${FROZEN_REVISION}"

if (assert_frozen_application_revision "mutable-ref" "${FROZEN_REVISION}") >/dev/null 2>&1; then
  printf 'mutable target revision was accepted unexpectedly\n' >&2
  exit 1
fi

if (assert_frozen_application_revision "${FROZEN_REVISION}" "${OTHER_REVISION}") >/dev/null 2>&1; then
  printf 'mismatched synchronized revision was accepted unexpectedly\n' >&2
  exit 1
fi

printf 'Application revision guard tests passed.\n'
