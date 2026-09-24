#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'Source this file instead: source scripts/activate-env.sh\n' >&2
  exit 2
fi

_radar_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_radar_repo_root="$(cd -- "${_radar_script_dir}/.." && pwd)"
_radar_desired_env_root="${_radar_repo_root}/.radar-env"

if [[ "${RADAR_ENV_ACTIVE:-}" == "1" ]]; then
  if [[ "${RADAR_ENV_ROOT:-}" == "${_radar_desired_env_root}" ]]; then
    unset _radar_script_dir _radar_repo_root _radar_desired_env_root
    return 0
  fi
  printf 'A different RADAR project environment is active; deactivate it first.\n' >&2
  unset _radar_script_dir _radar_repo_root _radar_desired_env_root
  return 1
fi

_RADAR_ENV_OLD_ROOT_SET="${RADAR_ENV_ROOT+x}"
_RADAR_ENV_OLD_ROOT="${RADAR_ENV_ROOT-}"
export RADAR_ENV_ROOT="${_radar_desired_env_root}"

if [[ ! -x "${RADAR_ENV_ROOT}/go/bin/go" || ! -x "${RADAR_ENV_ROOT}/bin/opa" || ! -x "${RADAR_ENV_ROOT}/python/bin/python3" ]]; then
  printf 'RADAR project environment is missing. Run: make env-bootstrap\n' >&2
  if [[ "${_RADAR_ENV_OLD_ROOT_SET}" == "x" ]]; then
    export RADAR_ENV_ROOT="${_RADAR_ENV_OLD_ROOT}"
  else
    unset RADAR_ENV_ROOT
  fi
  unset _RADAR_ENV_OLD_ROOT_SET _RADAR_ENV_OLD_ROOT
  unset _radar_script_dir _radar_repo_root _radar_desired_env_root
  return 1
fi

_RADAR_ENV_OLD_PATH="${PATH}"
_RADAR_ENV_OLD_GOROOT_SET="${GOROOT+x}"
_RADAR_ENV_OLD_GOROOT="${GOROOT-}"
_RADAR_ENV_OLD_GOPATH_SET="${GOPATH+x}"
_RADAR_ENV_OLD_GOPATH="${GOPATH-}"
_RADAR_ENV_OLD_GOMODCACHE_SET="${GOMODCACHE+x}"
_RADAR_ENV_OLD_GOMODCACHE="${GOMODCACHE-}"
_RADAR_ENV_OLD_GOCACHE_SET="${GOCACHE+x}"
_RADAR_ENV_OLD_GOCACHE="${GOCACHE-}"
_RADAR_ENV_OLD_GOTOOLCHAIN_SET="${GOTOOLCHAIN+x}"
_RADAR_ENV_OLD_GOTOOLCHAIN="${GOTOOLCHAIN-}"
_RADAR_ENV_OLD_VIRTUAL_ENV_SET="${VIRTUAL_ENV+x}"
_RADAR_ENV_OLD_VIRTUAL_ENV="${VIRTUAL_ENV-}"
_RADAR_ENV_OLD_PYTHONNOUSERSITE_SET="${PYTHONNOUSERSITE+x}"
_RADAR_ENV_OLD_PYTHONNOUSERSITE="${PYTHONNOUSERSITE-}"
_RADAR_ENV_OLD_PIP_CACHE_DIR_SET="${PIP_CACHE_DIR+x}"
_RADAR_ENV_OLD_PIP_CACHE_DIR="${PIP_CACHE_DIR-}"
_RADAR_ENV_OLD_MINIKUBE_HOME_SET="${MINIKUBE_HOME+x}"
_RADAR_ENV_OLD_MINIKUBE_HOME="${MINIKUBE_HOME-}"
_RADAR_ENV_OLD_KUBECONFIG_SET="${KUBECONFIG+x}"
_RADAR_ENV_OLD_KUBECONFIG="${KUBECONFIG-}"
_RADAR_ENV_OLD_TOKEN_FILE_SET="${RADAR_TOKEN_FILE+x}"
_RADAR_ENV_OLD_TOKEN_FILE="${RADAR_TOKEN_FILE-}"
_RADAR_ENV_OLD_UI_PASSWORD_FILE_SET="${RADAR_UI_PASSWORD_FILE+x}"
_RADAR_ENV_OLD_UI_PASSWORD_FILE="${RADAR_UI_PASSWORD_FILE-}"

export PATH="${RADAR_ENV_ROOT}/go/bin:${RADAR_ENV_ROOT}/python/bin:${RADAR_ENV_ROOT}/bin:${PATH}"
export GOROOT="${RADAR_ENV_ROOT}/go"
export GOPATH="${RADAR_ENV_ROOT}/state/go"
export GOMODCACHE="${RADAR_ENV_ROOT}/cache/go-mod"
export GOCACHE="${RADAR_ENV_ROOT}/cache/go-build"
export GOTOOLCHAIN="local"
export VIRTUAL_ENV="${RADAR_ENV_ROOT}/python"
export PYTHONNOUSERSITE="1"
export PIP_CACHE_DIR="${RADAR_ENV_ROOT}/cache/pip"
export MINIKUBE_HOME="${RADAR_ENV_ROOT}/state/minikube"
export KUBECONFIG="${RADAR_ENV_ROOT}/state/kubeconfig"
export RADAR_TOKEN_FILE="${RADAR_ENV_ROOT}/state/radar-token"
export RADAR_UI_PASSWORD_FILE="${RADAR_ENV_ROOT}/state/argocd-ui-password"
export RADAR_ENV_ACTIVE="1"

radar-deactivate() {
  export PATH="${_RADAR_ENV_OLD_PATH}"
  for _radar_name in GOROOT GOPATH GOMODCACHE GOCACHE GOTOOLCHAIN VIRTUAL_ENV PYTHONNOUSERSITE PIP_CACHE_DIR MINIKUBE_HOME KUBECONFIG RADAR_TOKEN_FILE RADAR_UI_PASSWORD_FILE; do
    _radar_set_name="_RADAR_ENV_OLD_${_radar_name}_SET"
    _radar_value_name="_RADAR_ENV_OLD_${_radar_name}"
    if [[ "${!_radar_set_name}" == "x" ]]; then
      export "${_radar_name}=${!_radar_value_name}"
    else
      unset "${_radar_name}"
    fi
    unset "${_radar_set_name}" "${_radar_value_name}"
  done
  if [[ "${_RADAR_ENV_OLD_ROOT_SET}" == "x" ]]; then
    export RADAR_ENV_ROOT="${_RADAR_ENV_OLD_ROOT}"
  else
    unset RADAR_ENV_ROOT
  fi
  unset RADAR_ENV_ACTIVE _RADAR_ENV_OLD_PATH _RADAR_ENV_OLD_ROOT_SET _RADAR_ENV_OLD_ROOT
  unset _radar_name _radar_set_name _radar_value_name
  hash -r
  unset -f radar-deactivate
}

mkdir -p -- "${GOPATH}" "${GOMODCACHE}" "${GOCACHE}" "${MINIKUBE_HOME}" "${PIP_CACHE_DIR}"
touch "${KUBECONFIG}"
chmod 0600 "${KUBECONFIG}"
hash -r
unset _radar_script_dir _radar_repo_root _radar_desired_env_root
