#!/usr/bin/env bash

ttune_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ttune_require_min_deps() {
  local missing=()
  local cmd
  for cmd in ffmpeg ffprobe jq; do
    if ! ttune_has_cmd "${cmd}"; then
      missing+=("${cmd}")
    fi
  done
  if ((${#missing[@]} > 0)); then
    ttune_err "Missing required dependency(s): ${missing[*]}"
    exit "${TTUNE_EXIT_GENERAL}"
  fi
}

ttune_detect_optional_tools_json() {
  jq -n \
    --arg nvidia_smi "$(ttune_has_cmd nvidia-smi && echo true || echo false)" \
    --arg vainfo "$(ttune_has_cmd vainfo && echo true || echo false)" \
    --arg fio "$(ttune_has_cmd fio && echo true || echo false)" \
    --arg mediainfo "$(ttune_has_cmd mediainfo && echo true || echo false)" \
    --arg ab_av1 "$(ttune_has_cmd ab-av1 && echo true || echo false)" \
    --arg ttune_bench "$(ttune_has_cmd ttune-bench && echo true || echo false)" \
    '{
      nvidia_smi: ($nvidia_smi == "true"),
      vainfo: ($vainfo == "true"),
      fio: ($fio == "true"),
      mediainfo: ($mediainfo == "true"),
      ab_av1: ($ab_av1 == "true"),
      ttune_bench: ($ttune_bench == "true")
    }'
}
