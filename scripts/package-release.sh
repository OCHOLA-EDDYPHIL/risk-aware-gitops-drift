#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s <semantic-version>\n' "$0" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
version="$1"
[[ "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  printf 'Version must be a semantic version, for example 1.2.3 or v1.2.3-rc.1\n' >&2
  exit 2
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="${DIST_DIR:-${repo_root}/dist}"
commit="$(git -C "${repo_root}" rev-parse --verify HEAD)"
build_date="$(git -C "${repo_root}" show -s --format=%cI HEAD)"
display_version="${version#v}"

if [[ "${display_version}" != "0.0.0-test" ]]; then
  for license_file in LICENSE LICENSE-DOCUMENTATION; do
    [[ -f "${repo_root}/${license_file}" ]] || {
      printf 'Refusing to prepare a release without %s\n' "${license_file}" >&2
      exit 1
    }
  done
  [[ -z "$(git -C "${repo_root}" status --porcelain)" ]] || {
    printf 'Refusing to prepare a release from a dirty working tree\n' >&2
    exit 1
  }
fi

mkdir -p "${dist_dir}"
rm -f "${dist_dir}/SHA256SUMS"

for arch in amd64 arm64; do
  work_dir="$(mktemp --directory)"
  trap 'rm -rf "${work_dir}"' EXIT
  package_name="radar_${display_version}_linux_${arch}"
  package_dir="${work_dir}/${package_name}"
  binary="${package_dir}/radar"
  archive="radar_${display_version}_linux_${arch}.tar.gz"

  mkdir -p "${package_dir}/docs" "${package_dir}/policies"

  (
    cd "${repo_root}"
    CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" go build \
      -trimpath \
      -ldflags "-s -w -X github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/version.Version=${display_version} -X github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/version.Commit=${commit} -X github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/version.Date=${build_date}" \
      -o "${binary}" ./cmd/radar
  )

  chmod 0755 "${binary}"
  cp "${repo_root}/README.md" "${repo_root}/CITATION.cff" "${repo_root}/THIRD_PARTY_NOTICES.md" "${package_dir}/"
  cp "${repo_root}/docs/licensing.md" "${package_dir}/docs/"
  cp "${repo_root}/policies/risk.rego" "${package_dir}/policies/"
  for license_file in LICENSE LICENSE-DOCUMENTATION; do
    if [[ -f "${repo_root}/${license_file}" ]]; then
      cp "${repo_root}/${license_file}" "${package_dir}/"
    fi
  done
  tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -C "${work_dir}" -czf "${dist_dir}/${archive}" "${package_name}"
  rm -rf "${work_dir}"
  trap - EXIT
done

(
  cd "${dist_dir}"
  sha256sum radar_"${display_version}"_linux_*.tar.gz >SHA256SUMS
)

printf 'Prepared Linux amd64 and arm64 archives in %s\n' "${dist_dir}"
