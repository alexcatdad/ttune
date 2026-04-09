#!/usr/bin/env bash

ttune_benchmark_cache_path() {
  local host fp
  host="$(hostname)"
  fp="$(ttune_detect_fingerprint)"
  printf '%s/benchmark_%s_%s.json' "$(ttune_cache_dir)" "${host}" "${fp}"
}

ttune_benchmark_make_sample() {
  local sample="${1}"
  if [[ -f "${sample}" ]]; then
    return
  fi
  ffmpeg -hide_banner -loglevel error \
    -f lavfi -i testsrc2=size=1920x1080:rate=30 \
    -f lavfi -i sine=frequency=1000:sample_rate=48000 \
    -t 20 -pix_fmt yuv420p -c:v libx264 -preset veryfast -crf 18 -c:a aac \
    -y "${sample}"
}

ttune_benchmark_probe_encoder() {
  local sample="${1}" encoder="${2}" duration="${3}" out="/tmp/ttune_probe_$$.mkv"
  local start end elapsed fps
  start="$(date +%s)"
  if ! ffmpeg -hide_banner -loglevel error -y -t "${duration}" -i "${sample}" \
    -c:v "${encoder}" -an "${out}" >/dev/null 2>&1; then
    rm -f "${out}"
    jq -n --arg enc "${encoder}" '{encoder: $enc, available: false}'
    return
  fi
  end="$(date +%s)"
  elapsed="$((end - start))"
  if [[ "${elapsed}" -le 0 ]]; then
    elapsed=1
  fi
  fps="$(awk -v d="${duration}" -v t="${elapsed}" 'BEGIN{printf "%.2f", (d*30)/t}')"
  rm -f "${out}"
  jq -n --arg enc "${encoder}" --argjson fps "${fps}" \
    '{encoder: $enc, available: true, fps_1080p: $fps}'
}

ttune_benchmark_main() {
  local duration=20 as_json=0 no_cache=0 encoders_csv=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --duration)
      duration="${2}"
      shift
      ;;
    --json) as_json=1 ;;
    --no-cache) no_cache=1 ;;
    --encoders)
      encoders_csv="${2}"
      shift
      ;;
    *)
      ttune_err "Unknown benchmark option: $1"
      exit "${TTUNE_EXIT_USAGE}"
      ;;
    esac
    shift
  done

  local cache_root cache_file sample encoders_json encoders benchmark fp host
  cache_root="$(ttune_cache_dir)"
  mkdir -p "${cache_root}"
  cache_file="$(ttune_benchmark_cache_path)"
  if [[ "${no_cache}" == "0" && -f "${cache_file}" ]]; then
    if [[ "${as_json}" == "1" ]]; then
      jq '.' "${cache_file}"
    else
      printf 'Using cached benchmark: %s\n' "${cache_file}"
      jq -r '.recommendations.balanced | "Balanced: \(.encoder) \(.quality_param) preset \(.preset)"' "${cache_file}"
    fi
    return
  fi

  sample="${cache_root}/reference_1080p_20s.mp4"
  ttune_benchmark_make_sample "${sample}"

  if [[ -n "${encoders_csv}" ]]; then
    encoders="$(printf '%s' "${encoders_csv}" | tr ',' '\n')"
  else
    encoders="$(
      ttune_detect_profile_json |
        jq -r '.encoders.available[]' |
        awk '/^(libx264|libx265|libsvtav1|hevc_nvenc|av1_nvenc|hevc_qsv|av1_qsv|hevc_vaapi|av1_vaapi|hevc_videotoolbox)$/'
    )"
  fi
  if [[ -z "${encoders}" ]]; then
    ttune_err "No suitable encoders found for benchmark."
    exit "${TTUNE_EXIT_ENCODER}"
  fi

  encoders_json="[]"
  while IFS= read -r enc; do
    [[ -z "${enc}" ]] && continue
    encoders_json="$(jq -n --argjson base "${encoders_json}" --argjson item "$(ttune_benchmark_probe_encoder "${sample}" "${enc}" "${duration}")" '$base + [$item]')"
  done <<<"${encoders}"

  fp="$(ttune_detect_fingerprint)"
  host="$(hostname)"
  benchmark="$(
    jq -n \
      --arg version "1.0.0" \
      --arg ts "$(ttune_now_iso)" \
      --arg host "${host}" \
      --arg fp "${fp}" \
      --argjson hardware "$(ttune_detect_profile_json | jq '.hardware')" \
      --argjson encoders "${encoders_json}" '
      {
        schema_version: "1.0",
        version: $version,
        timestamp: $ts,
        hostname: $host,
        fingerprint: $fp,
        hardware: $hardware,
        encoder_results: $encoders
      }'
  )"

  benchmark="$(printf '%s' "${benchmark}" | jq '
    .recommendations = {
      speed_priority: (
        (.encoder_results | map(select(.available)) | sort_by(.fps_1080p) | reverse | .[0]) as $best
        | {encoder: $best.encoder, preset: "default", quality_param: "-cq 26", expected_fps: $best.fps_1080p, rationale: "Highest measured fps"}
      ),
      quality_priority: (
        if (.encoder_results | map(.encoder) | index("libx265")) then
          {encoder: "libx265", preset: "slow", quality_param: "-crf 22", rationale: "Software HEVC quality-focused default"}
        else
          {encoder: .encoder_results[0].encoder, preset: "default", quality_param: "-cq 24", rationale: "Fallback quality profile"}
        end
      ),
      balanced: (
        if (.encoder_results | map(.encoder) | index("libsvtav1")) then
          {encoder: "libsvtav1", preset: 6, quality_param: "-crf 32", rationale: "Balanced AV1 recommendation"}
        else
          {encoder: .recommendations.speed_priority.encoder, preset: "default", quality_param: "-cq 26", rationale: "Speed fallback"}
        end
      )
    }')"

  printf '%s\n' "${benchmark}" >"${cache_file}"

  if [[ "${as_json}" == "1" ]]; then
    printf '%s\n' "${benchmark}"
  else
    printf 'Benchmark complete for %s\n' "${host}"
    jq -r '.encoder_results[] | select(.available) | "- \(.encoder): \(.fps_1080p) fps"' <<<"${benchmark}"
    jq -r '.recommendations.balanced | "Balanced recommendation: \(.encoder) \(.quality_param) preset \(.preset)"' <<<"${benchmark}"
  fi
}
