#!/usr/bin/env bash

# shellcheck disable=SC2034
TTUNE_EXIT_OK=0
TTUNE_EXIT_GENERAL=1
TTUNE_EXIT_USAGE=2
TTUNE_EXIT_INPUT=3
TTUNE_EXIT_DISK=4
TTUNE_EXIT_ENCODER=5
TTUNE_EXIT_VMAF=6

ttune_log() {
  printf '%s\n' "$*" >&2
}

ttune_err() {
  printf 'ttune: error: %s\n' "$*" >&2
}

ttune_warn() {
  printf 'ttune: warning: %s\n' "$*" >&2
}

ttune_home_config() {
  printf '%s' "${HOME}/.config/ttune/config.toml"
}

ttune_cache_dir() {
  printf '%s' "${HOME}/.cache/ttune"
}

ttune_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

ttune_json_or_human() {
  local json="${1}"
  local human="${2}"
  local as_json="${3:-0}"
  if [[ "${as_json}" == "1" ]]; then
    printf '%s\n' "${json}"
  else
    printf '%s\n' "${human}"
  fi
}

ttune_version_main() {
  local version="${1}"
  local ffmpeg_version jq_version
  ffmpeg_version="$(ffmpeg -version 2>/dev/null | awk 'NR==1{print $3}' || true)"
  jq_version="$(jq --version 2>/dev/null || true)"
  cat <<EOF
ttune ${version}
ffmpeg: ${ffmpeg_version:-missing}
jq: ${jq_version:-missing}
EOF
}
