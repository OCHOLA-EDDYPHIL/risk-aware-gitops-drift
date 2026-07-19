#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  printf 'Usage: %s --collection-id <identifier> --run-dir <raw-run-directory>\n' "$0" >&2
  exit 2
}

collection_id=""
run_dir=""
while (($# > 0)); do
  case "$1" in
    --collection-id)
      (($# >= 2)) || usage
      collection_id="$2"
      shift 2
      ;;
    --run-dir)
      (($# >= 2)) || usage
      run_dir="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ "${collection_id}" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "invalid collection identifier"
[[ -d "${run_dir}" ]] || die "run directory does not exist: ${run_dir}"

for command_name in git jq python3 sha256sum stat tar zstd; do
  require_command "${command_name}"
done
git -C "${REPO_ROOT}" lfs version >/dev/null

metadata_path="${run_dir}/metadata.json"
[[ -f "${metadata_path}" && ! -L "${metadata_path}" ]] || die "regular run metadata is required"
jq --exit-status \
  'type == "object" and
   (.scenario | type == "string") and
   (.repetition | type == "number") and
   (.status | type == "string") and
   (.evidenceTier | type == "string") and
   (.expectedRule | type == "string") and
   (.expectedSeverity | type == "string")' \
  "${metadata_path}" >/dev/null || die "run metadata is incomplete or invalid"

scenario="$(jq --raw-output '.scenario' "${metadata_path}")"
repetition="$(jq --raw-output '.repetition' "${metadata_path}")"
status="$(jq --raw-output '.status' "${metadata_path}")"
evidence_tier="$(jq --raw-output '.evidenceTier' "${metadata_path}")"
expected_rule="$(jq --raw-output '.expectedRule' "${metadata_path}")"
expected_severity="$(jq --raw-output '.expectedSeverity' "${metadata_path}")"

[[ "${scenario}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid scenario in metadata"
[[ "${repetition}" =~ ^[1-9][0-9]*$ ]] || die "invalid repetition in metadata"
[[ "${status}" =~ ^[a-z][a-z0-9-]*$ ]] || die "invalid status in metadata"
[[ "${evidence_tier}" =~ ^[a-z][a-z0-9-]*$ ]] || die "invalid evidence tier in metadata"
[[ "${expected_rule}" =~ ^[A-Z0-9][A-Z0-9-]*$ ]] || die "invalid expected rule in metadata"
[[ "${expected_severity}" =~ ^(INFO|LOW|MEDIUM|HIGH|CRITICAL)$ ]] || die "invalid expected severity in metadata"

run_id="run-$(printf '%03d' "${repetition}")"
relative_evidence_root="research/evidence/${collection_id}"
evidence_root="${REPO_ROOT}/${relative_evidence_root}"
archive_name="${scenario}-${run_id}.tar.zst"
archive_relative_path="${relative_evidence_root}/archives/${archive_name}"
archive_path="${REPO_ROOT}/${archive_relative_path}"
summary_dir="${evidence_root}/runs/${scenario}/${run_id}"
index_path="${evidence_root}/index.csv"

[[ ! -e "${archive_path}" && ! -e "${summary_dir}" ]] || die "evidence already exists for ${scenario} ${run_id}"
attributes="$(git -C "${REPO_ROOT}" check-attr filter -- "${archive_relative_path}")"
[[ "${attributes}" == *': lfs' ]] || die "archive path is not eligible for Git LFS"

temporary_directory="$(mktemp --directory)"
trap 'rm -rf "${temporary_directory}"' EXIT
sanitized_directory="${temporary_directory}/${scenario}-${run_id}"
python3 "${SCRIPT_DIR}/sanitize-evidence.py" "${run_dir}" "${sanitized_directory}"

jq --exit-status . "${sanitized_directory}/metadata.json" >/dev/null
[[ ! -f "${sanitized_directory}/environment.json" ]] || jq --exit-status . "${sanitized_directory}/environment.json" >/dev/null
[[ ! -f "${sanitized_directory}/radar-result.json" ]] || jq --exit-status . "${sanitized_directory}/radar-result.json" >/dev/null

staged_archive="${temporary_directory}/${archive_name}"
tar --create --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  --directory "${temporary_directory}" "${scenario}-${run_id}" | \
  zstd --quiet -T1 --ultra -19 -o "${staged_archive}"
[[ -s "${staged_archive}" ]] || die "archive creation produced no data"
zstd --quiet -t "${staged_archive}"

archive_bytes="$(stat --format '%s' "${staged_archive}")"
((archive_bytes <= 10485760)) || die "archive exceeds the 10 MiB evidence ceiling: ${archive_bytes} bytes"
if ((archive_bytes > 5242880)); then
  printf 'Warning: archive exceeds 5 MiB and requires review: %s\n' "${archive_name}" >&2
fi
archive_sha256="$(sha256sum "${staged_archive}" | awk '{print $1}')"

staged_summary="${temporary_directory}/summary"
mkdir -p "${staged_summary}"
cp "${sanitized_directory}/metadata.json" "${staged_summary}/metadata.json"
[[ ! -f "${sanitized_directory}/environment.json" ]] || cp "${sanitized_directory}/environment.json" "${staged_summary}/environment.json"
[[ ! -f "${sanitized_directory}/radar-result.json" ]] || cp "${sanitized_directory}/radar-result.json" "${staged_summary}/radar-result.json"

staged_index="${temporary_directory}/index.csv"
if [[ -f "${index_path}" ]]; then
  cp "${index_path}" "${staged_index}"
else
  printf 'collection_id,scenario,repetition,status,evidence_tier,expected_rule,expected_severity,archive_sha256,archive_bytes\n' >"${staged_index}"
fi
if awk -F, -v scenario="${scenario}" -v repetition="${repetition}" \
  'NR > 1 && $2 == scenario && $3 == repetition {found = 1} END {exit !found}' "${staged_index}"; then
  die "index already contains ${scenario} repetition ${repetition}"
fi
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
  "${collection_id}" "${scenario}" "${repetition}" "${status}" "${evidence_tier}" \
  "${expected_rule}" "${expected_severity}" "${archive_sha256}" "${archive_bytes}" >>"${staged_index}"

mkdir -p "$(dirname -- "${archive_path}")" "$(dirname -- "${summary_dir}")"
cp "${staged_archive}" "${archive_path}"
printf '%s  %s\n' "${archive_sha256}" "${archive_name}" >"${archive_path}.sha256"
cp -R "${staged_summary}" "${summary_dir}"
cp "${staged_index}" "${index_path}"

(
  cd "$(dirname -- "${archive_path}")"
  sha256sum --check --status "$(basename -- "${archive_path}.sha256")"
)
printf 'Prepared sanitized evidence for %s %s at %s\n' "${scenario}" "${run_id}" "${evidence_root}"
