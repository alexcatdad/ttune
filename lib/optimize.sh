#!/usr/bin/env bash

# shellcheck source=lib/json.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/json.sh"

ttune_optimize_usage() {
  cat <<'EOF'
ttune optimize -i <file> [options]
  --codec <hevc|av1|h264>
  --target-vmaf <num>
  --speed-priority | --quality-priority
  --output-format <json|ffmpeg-cmd|tdarr-vars>
  --scale <1080p|720p|WxH>
  --hdr-mode <auto|preserve|tonemap>
  --batch <dir>
EOF
}

ttune_optimize_resolve_benchmark() {
  local cache_file
  cache_file="$(ttune_benchmark_cache_path)"
  if [[ -f "${cache_file}" ]]; then
    jq '.' "${cache_file}"
  else
    ttune_benchmark_main --json >/dev/null
    jq '.' "${cache_file}"
  fi
}

ttune_optimize_pick_strategy() {
  local benchmark_json="${1}" strategy="${2}"
  printf '%s' "${benchmark_json}" | jq -c ".recommendations.${strategy}"
}

ttune_optimize_content_profile() {
  local analysis_json="${1}"
  printf '%s' "${analysis_json}" | jq '
    {
      hdr: .video.hdr,
      grain_likely: ((.video.pix_fmt // "") | test("10")),
      anime_likely: ((.video.width // 0) <= 1920 and (.video.height // 0) <= 1080 and (.video.codec // "") == "h264")
    }'
}

ttune_optimize_vmaf_search() {
  local file="${1}" codec="${2}" target="${3}"
  if ttune_has_cmd ttune-bench; then
    ttune-bench vmaf-search --input "${file}" --codec "${codec}" --target-vmaf "${target}" --json
    return
  fi
  if ttune_has_cmd ab-av1; then
    ab-av1 crf-search -i "${file}" --preset medium --target-vmaf "${target}" --min-vmaf "${target}" --json
    return
  fi
  return 1
}

ttune_optimize_fallback_chain_json() {
  local codec="${1}"
  if [[ "${codec}" == "av1" ]]; then
    jq -n '{chain: ["av1_nvenc","av1_qsv","av1_vaapi","libsvtav1"]}'
  else
    jq -n '{chain: ["hevc_nvenc","hevc_qsv","hevc_vaapi","libx265"]}'
  fi
}

ttune_optimize_estimate_hours() {
  local size_bytes="${1}" fps="${2}" width="${3}" height="${4}" duration="${5}"
  awk -v bytes="${size_bytes}" -v fps="${fps}" -v w="${width}" -v h="${height}" -v dur="${duration}" '
    BEGIN {
      if (fps <= 0) fps = 1;
      if (dur <= 0 && bytes > 0) dur = (bytes / 10000000);
      if (dur <= 0) dur = 3600;
      print (dur / fps) / 3600
    }'
}

ttune_optimize_save_learning_cache() {
  local key="${1}" payload="${2}"
  local dir
  dir="$(ttune_cache_dir)/crf-cache"
  mkdir -p "${dir}"
  printf '%s\n' "${payload}" >"${dir}/${key}.json"
}

ttune_optimize_lookup_learning_cache() {
  local key="${1}" dir file
  dir="$(ttune_cache_dir)/crf-cache"
  file="${dir}/${key}.json"
  if [[ -f "${file}" ]]; then
    jq '.' "${file}"
  else
    return 1
  fi
}

ttune_optimize_emit_ffmpeg_cmd() {
  local input="${1}" encoder="${2}" quality_param="${3}" preset="${4}" scale="${5}" hdr_mode="${6}" container="${7}"
  local vf tone
  vf="scale=${scale}:flags=lanczos+accurate_rnd+full_chroma_int"
  tone=""
  if [[ "${hdr_mode}" == "tonemap" ]]; then
    tone=",zscale=t=linear:npl=100,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv"
  fi
  cat <<EOF
ffmpeg -i "${input}" \\
  -map 0:v:0 -map 0:a? -map 0:s? \\
  -c:v ${encoder} ${quality_param} -preset ${preset} \\
  -pix_fmt yuv420p10le \\
  -vf "${vf}${tone}" \\
  -c:a copy -c:s copy \\
  -movflags +faststart \\
  "${input%.*}.ttune.${container}"
EOF
}

ttune_optimize_single() {
  local input_file="${1}" codec="${2}" target_vmaf="${3}" strategy="${4}" output_format="${5}" scale="${6}" hdr_mode="${7}"
  if [[ ! -f "${input_file}" ]]; then
    ttune_err "Input file not found: ${input_file}"
    exit "${TTUNE_EXIT_INPUT}"
  fi
  if ! ffprobe -v error -i "${input_file}" -show_entries format=duration >/dev/null 2>&1; then
    ttune_err "Input appears corrupt: ${input_file}"
    exit "${TTUNE_EXIT_INPUT}"
  fi

  local benchmark analysis content strategy_json encoder preset quality_param vmaf_result=""
  benchmark="$(ttune_optimize_resolve_benchmark)"
  analysis="$(ttune_json_file_analysis "${input_file}")"
  content="$(ttune_optimize_content_profile "${analysis}")"
  strategy_json="$(ttune_optimize_pick_strategy "${benchmark}" "${strategy}")"
  encoder="$(printf '%s' "${strategy_json}" | jq -r '.encoder')"
  preset="$(printf '%s' "${strategy_json}" | jq -r '.preset')"
  quality_param="$(printf '%s' "${strategy_json}" | jq -r '.quality_param')"
  if [[ -z "${encoder}" || "${encoder}" == "null" ]]; then
    encoder="libx265"
  fi
  if [[ -z "${preset}" || "${preset}" == "null" ]]; then
    preset="slow"
  fi
  if [[ -z "${quality_param}" || "${quality_param}" == "null" ]]; then
    quality_param="-crf 22"
  fi

  if [[ "${codec}" == "av1" && "${encoder}" == "libx265" ]]; then
    encoder="libsvtav1"
    preset="6"
    quality_param="-crf 32"
  fi

  if [[ "${codec}" == "hevc" && "${encoder}" == "libsvtav1" ]]; then
    encoder="libx265"
    preset="slow"
    quality_param="-crf 22"
  fi
  if [[ "${encoder}" == "libx265" || "${encoder}" == "libx264" || "${encoder}" == "libsvtav1" ]]; then
    if [[ "${quality_param}" == *"-cq "* ]]; then
      quality_param="-crf 22"
    fi
  fi
  if [[ "${encoder}" == *"_nvenc" || "${encoder}" == *"_qsv" || "${encoder}" == *"_vaapi" || "${encoder}" == *"_videotoolbox" ]]; then
    if [[ "${quality_param}" == *"-crf "* ]]; then
      quality_param="-cq 26"
    fi
  fi

  local key
  key="$(printf '%s|%s|%s|%s' \
    "$(jq -r '.video.codec' <<<"${analysis}")" \
    "$(jq -r '.video.width' <<<"${analysis}")" \
    "$(jq -r '.video.height' <<<"${analysis}")" \
    "${codec}" | shasum -a 256 | awk '{print $1}')"

  if cached="$(ttune_optimize_lookup_learning_cache "${key}" 2>/dev/null)"; then
    quality_param="$(jq -r '.quality_param' <<<"${cached}")"
  elif vmaf_result="$(ttune_optimize_vmaf_search "${input_file}" "${codec}" "${target_vmaf}" 2>/dev/null || true)"; then
    # Supports optional rust companion output: {"quality_param":"-crf 22"}
    if jq -e . >/dev/null 2>&1 <<<"${vmaf_result}"; then
      quality_param="$(jq -r '.quality_param // empty' <<<"${vmaf_result}")"
      [[ -z "${quality_param}" ]] && quality_param="$(jq -r '.crf? // empty | "-crf \(.)"' <<<"${vmaf_result}")"
    fi
  fi
  [[ -z "${quality_param}" ]] && quality_param="-crf 22"
  if [[ "${encoder}" == "libx265" || "${encoder}" == "libx264" || "${encoder}" == "libsvtav1" ]]; then
    [[ "${quality_param}" == *"-cq "* ]] && quality_param="-crf 22"
  fi
  if [[ "${encoder}" == *"_nvenc" || "${encoder}" == *"_qsv" || "${encoder}" == *"_vaapi" || "${encoder}" == *"_videotoolbox" ]]; then
    [[ "${quality_param}" == *"-crf "* ]] && quality_param="-cq 26"
  fi

  ttune_optimize_save_learning_cache "${key}" "$(jq -n --arg qp "${quality_param}" --arg ts "$(ttune_now_iso)" '{quality_param: $qp, cached_at: $ts}')"

  local video_w video_h duration size_bytes hdr_detected final_hdr_mode estimate_hours fallback
  video_w="$(jq -r '.video.width // 1920' <<<"${analysis}")"
  video_h="$(jq -r '.video.height // 1080' <<<"${analysis}")"
  duration="$(jq -r '.duration // 0' <<<"${analysis}")"
  size_bytes="$(jq -r '.size_bytes // 0' <<<"${analysis}")"
  hdr_detected="$(jq -r '.video.hdr' <<<"${analysis}")"
  if [[ "${hdr_mode}" == "auto" && "${hdr_detected}" == "true" ]]; then
    final_hdr_mode="tonemap"
  else
    final_hdr_mode="${hdr_mode}"
  fi
  estimate_hours="$(ttune_optimize_estimate_hours "${size_bytes}" 30 "${video_w}" "${video_h}" "${duration}")"
  fallback="$(ttune_optimize_fallback_chain_json "${codec}")"

  local result
  result="$(jq -n \
    --arg input "${input_file}" \
    --arg codec "${codec}" \
    --arg encoder "${encoder}" \
    --arg preset "${preset}" \
    --arg quality_param "${quality_param}" \
    --arg scale "${scale}" \
    --arg hdr_mode "${final_hdr_mode}" \
    --arg target_vmaf "${target_vmaf}" \
    --argjson analysis "${analysis}" \
    --argjson content "${content}" \
    --argjson fallback "${fallback}" \
    --argjson estimate_hours "${estimate_hours}" \
    '{
      schema_version: "1.0",
      input: $input,
      codec: $codec,
      encoder: $encoder,
      preset: $preset,
      quality_param: $quality_param,
      scale: $scale,
      hdr_mode: $hdr_mode,
      target_vmaf: ($target_vmaf | tonumber),
      estimated_encode_hours: $estimate_hours,
      file_analysis: $analysis,
      content_profile: $content,
      fallback: $fallback
    }')"

  case "${output_format}" in
  json) printf '%s\n' "${result}" ;;
  tdarr-vars)
    jq -n --argjson r "${result}" '{
        v_encoder: $r.encoder,
        v_preset: ($r.preset|tostring),
        v_crf: ($r.quality_param|split(" ")|last),
        v_pix_fmt: "yuv420p10le",
        v_scale: $r.scale,
        target_container: ".mkv"
      }'
    ;;
  ffmpeg-cmd)
    ttune_optimize_emit_ffmpeg_cmd "${input_file}" "${encoder}" "${quality_param}" "${preset}" "${scale}" "${final_hdr_mode}" "mkv"
    ;;
  *)
    ttune_err "Unknown output format: ${output_format}"
    exit "${TTUNE_EXIT_USAGE}"
    ;;
  esac
}

ttune_optimize_batch() {
  local batch_dir="${1}" codec="${2}" target_vmaf="${3}" strategy="${4}" scale="${5}" hdr_mode="${6}"
  if [[ ! -d "${batch_dir}" ]]; then
    ttune_err "Batch directory not found: ${batch_dir}"
    exit "${TTUNE_EXIT_INPUT}"
  fi
  local files first
  files="$(rg --files "${batch_dir}" | rg '\.(mkv|mp4|mov|avi)$' || true)"
  first=1
  printf '[\n'
  while IFS= read -r file; do
    [[ -z "${file}" ]] && continue
    [[ "${first}" == "0" ]] && printf ',\n'
    ttune_optimize_single "${file}" "${codec}" "${target_vmaf}" "${strategy}" "json" "${scale}" "${hdr_mode}"
    first=0
  done <<<"${files}"
  printf '\n]\n'
}

ttune_optimize_main() {
  local input_file="" codec="hevc" target_vmaf="95" strategy="balanced" output_format="json"
  local scale="1920:-2" hdr_mode="auto" batch_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -i)
      input_file="${2}"
      shift
      ;;
    --codec)
      codec="${2}"
      shift
      ;;
    --target-vmaf)
      target_vmaf="${2}"
      shift
      ;;
    --speed-priority) strategy="speed_priority" ;;
    --quality-priority) strategy="quality_priority" ;;
    --output-format)
      output_format="${2}"
      shift
      ;;
    --scale)
      case "${2}" in
      1080p) scale="1920:-2" ;;
      720p) scale="1280:-2" ;;
      *) scale="${2}" ;;
      esac
      shift
      ;;
    --hdr-mode)
      hdr_mode="${2}"
      shift
      ;;
    --batch)
      batch_dir="${2}"
      shift
      ;;
    --help | -h)
      ttune_optimize_usage
      return
      ;;
    *)
      ttune_err "Unknown optimize option: $1"
      ttune_optimize_usage
      exit "${TTUNE_EXIT_USAGE}"
      ;;
    esac
    shift
  done

  local avail_gb
  avail_gb="$(ttune_detect_disk_json "/tmp" | jq -r '.available_gb')"
  if [[ "${avail_gb}" -lt 1 ]]; then
    ttune_err "Insufficient disk space in /tmp"
    exit "${TTUNE_EXIT_DISK}"
  fi

  if [[ -n "${batch_dir}" ]]; then
    ttune_optimize_batch "${batch_dir}" "${codec}" "${target_vmaf}" "${strategy}" "${scale}" "${hdr_mode}"
    return
  fi

  if [[ -z "${input_file}" ]]; then
    ttune_err "Missing input file. Use -i <file> or --batch <dir>."
    exit "${TTUNE_EXIT_USAGE}"
  fi
  ttune_optimize_single "${input_file}" "${codec}" "${target_vmaf}" "${strategy}" "${output_format}" "${scale}" "${hdr_mode}"
}
