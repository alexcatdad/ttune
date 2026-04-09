#!/usr/bin/env bash

# shellcheck source=lib/deps.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deps.sh"

ttune_detect_arch() {
  uname -m
}

ttune_detect_os() {
  uname -s
}

ttune_detect_cpu_model() {
  local os
  os="$(ttune_detect_os)"
  if [[ "${os}" == "Darwin" ]]; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model
  else
    awk -F: '/model name|Hardware/{gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "unknown"
  fi
}

ttune_detect_core_counts_json() {
  local os perf eff logical
  os="$(ttune_detect_os)"
  if [[ "${os}" == "Darwin" ]]; then
    logical="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 0)"
    perf="$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo 0)"
    eff="$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || echo 0)"
    jq -n --argjson logical "${logical}" --argjson perf "${perf}" --argjson eff "${eff}" \
      '{threads: $logical, perf_cores: $perf, eff_cores: $eff}'
  else
    logical="$(nproc 2>/dev/null || echo 0)"
    jq -n --argjson logical "${logical}" '{threads: $logical}'
  fi
}

ttune_detect_cpu_features() {
  local os arch
  os="$(ttune_detect_os)"
  arch="$(ttune_detect_arch)"
  if [[ "${arch}" == "arm64" || "${arch}" == "aarch64" ]]; then
    printf '["neon"]\n'
    return
  fi
  if [[ "${os}" == "Darwin" ]]; then
    local f
    f="$(sysctl -n machdep.cpu.leaf7_features 2>/dev/null || true)"
    jq -n --arg f "${f}" '
      [
        (if ($f|test("AVX2")) then "avx2" else empty end),
        (if ($f|test("AVX512")) then "avx512f" else empty end)
      ]'
  else
    local cpu
    cpu="$(cat /proc/cpuinfo 2>/dev/null || true)"
    jq -n --arg cpu "${cpu}" '
      [
        (if ($cpu|test("avx2")) then "avx2" else empty end),
        (if ($cpu|test("avx512f")) then "avx512f" else empty end),
        (if ($cpu|test("sse4_2")) then "sse4_2" else empty end)
      ]'
  fi
}

ttune_detect_memory_gb() {
  local os bytes
  os="$(ttune_detect_os)"
  if [[ "${os}" == "Darwin" ]]; then
    bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
  else
    bytes="$(awk '/MemTotal/{print $2*1024; exit}' /proc/meminfo 2>/dev/null || echo 0)"
  fi
  awk -v b="${bytes}" 'BEGIN{printf "%.1f", b/1024/1024/1024}'
}

ttune_detect_disk_json() {
  local temp_dir="${1:-/tmp}"
  local avail_kb
  avail_kb="$(df -Pk "${temp_dir}" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)"
  jq -n --arg temp "${temp_dir}" --argjson avail_gb "$((avail_kb / 1024 / 1024))" \
    '{temp_dir: $temp, available_gb: $avail_gb}'
}

ttune_detect_encoders_json() {
  local enc_list
  enc_list="$(ffmpeg -hide_banner -encoders 2>/dev/null | awk '{print $2}' | rg '^(h264|hevc|av1).*(_nvenc|_qsv|_vaapi|_videotoolbox|_v4l2m2m)$|^libx265$|^libsvtav1$|^libx264$' || true)"
  jq -n --arg enc "${enc_list}" '
    ($enc | split("\n") | map(select(length>0)) | unique) as $items
    | {available: $items}'
}

ttune_detect_gpu_json() {
  local items='[]'
  if ttune_has_cmd nvidia-smi; then
    local rows
    rows="$(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader,nounits 2>/dev/null || true)"
    if [[ -n "${rows}" ]]; then
      items="$(printf '%s\n' "${rows}" | jq -R -s '
        split("\n")
        | map(select(length>0))
        | map(split(","))
        | map({
            name: (.[0] | gsub("^ +| +$"; "")),
            driver: (.[1] | gsub("^ +| +$"; "")),
            vram_mb: ((.[2] | gsub("^ +| +$"; "")) | tonumber? // 0)
          })')"
    fi
  fi

  jq -n --argjson nvidia "${items}" '{nvidia: $nvidia}'
}

ttune_detect_profile_json() {
  local arch cpu_model core_json cpu_features mem disk_json enc_json gpu_json host
  host="$(hostname)"
  arch="$(ttune_detect_arch)"
  cpu_model="$(ttune_detect_cpu_model)"
  core_json="$(ttune_detect_core_counts_json)"
  cpu_features="$(ttune_detect_cpu_features)"
  mem="$(ttune_detect_memory_gb)"
  disk_json="$(ttune_detect_disk_json "/tmp")"
  enc_json="$(ttune_detect_encoders_json)"
  gpu_json="$(ttune_detect_gpu_json)"

  jq -n \
    --arg hostname "${host}" \
    --arg arch "${arch}" \
    --arg cpu_model "${cpu_model}" \
    --argjson cores "${core_json}" \
    --argjson features "${cpu_features}" \
    --argjson memory_gb "${mem}" \
    --argjson disk "${disk_json}" \
    --argjson encoders "${enc_json}" \
    --argjson gpu "${gpu_json}" \
    --argjson optional_tools "$(ttune_detect_optional_tools_json)" \
    '{
      timestamp: now | todateiso8601,
      hostname: $hostname,
      hardware: {
        arch: $arch,
        cpu: {
          model: $cpu_model,
          features: $features
        } + $cores,
        memory_gb: $memory_gb,
        disk: $disk,
        gpu: $gpu
      },
      encoders: $encoders,
      optional_tools: $optional_tools
    }'
}

ttune_detect_fingerprint() {
  local profile
  profile="$(ttune_detect_profile_json)"
  printf '%s' "${profile}" | jq -c 'del(.timestamp)' | shasum -a 256 | awk '{print $1}'
}

ttune_detect_main() {
  local as_json=0 with_diff=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --json) as_json=1 ;;
    --diff) with_diff=1 ;;
    *)
      ttune_err "Unknown detect option: $1"
      exit "${TTUNE_EXIT_USAGE}"
      ;;
    esac
    shift
  done

  local profile cache_root latest fingerprint
  profile="$(ttune_detect_profile_json)"
  fingerprint="$(ttune_detect_fingerprint)"
  cache_root="$(ttune_cache_dir)"
  mkdir -p "${cache_root}"
  latest="${cache_root}/last_detect.json"

  if [[ "${as_json}" == "1" ]]; then
    if [[ "${with_diff}" == "1" && -f "${latest}" ]]; then
      jq -n --argjson current "${profile}" --argjson previous "$(jq '.' "${latest}")" --arg fp "${fingerprint}" '
        {
          fingerprint: $fp,
          current: $current,
          changed: (($current.hardware != $previous.hardware) or ($current.encoders != $previous.encoders))
        }'
    else
      jq -n --argjson profile "${profile}" --arg fp "${fingerprint}" '{fingerprint: $fp, profile: $profile}'
    fi
  else
    printf 'Host: %s\n' "$(printf '%s' "${profile}" | jq -r '.hostname')"
    printf 'Arch: %s\n' "$(printf '%s' "${profile}" | jq -r '.hardware.arch')"
    printf 'CPU:  %s\n' "$(printf '%s' "${profile}" | jq -r '.hardware.cpu.model')"
    printf 'RAM:  %s GB\n' "$(printf '%s' "${profile}" | jq -r '.hardware.memory_gb')"
    printf 'Encoders: %s\n' "$(printf '%s' "${profile}" | jq -r '.encoders.available | join(", ")')"
    if [[ "${with_diff}" == "1" && -f "${latest}" ]]; then
      local changed
      changed="$(jq -n --argjson c "${profile}" --argjson p "$(jq '.' "${latest}")" \
        '($c.hardware != $p.hardware) or ($c.encoders != $p.encoders)')"
      printf 'Changed since last detect: %s\n' "${changed}"
    fi
    printf 'Fingerprint: %s\n' "${fingerprint}"
  fi

  printf '%s\n' "${profile}" >"${latest}"
}
