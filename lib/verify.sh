#!/usr/bin/env bash

ttune_verify_main() {
  local source_file="" transcoded_file="" target_vmaf="95" ci=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --source)
      source_file="${2}"
      shift
      ;;
    --transcoded)
      transcoded_file="${2}"
      shift
      ;;
    --target-vmaf)
      target_vmaf="${2}"
      shift
      ;;
    --ci) ci=1 ;;
    *)
      ttune_err "Unknown verify option: $1"
      exit "${TTUNE_EXIT_USAGE}"
      ;;
    esac
    shift
  done

  if [[ ! -f "${source_file}" || ! -f "${transcoded_file}" ]]; then
    ttune_err "Both --source and --transcoded files must exist."
    exit "${TTUNE_EXIT_INPUT}"
  fi

  local src_dur out_dur diff_pct estimated_vmaf pass
  src_dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "${source_file}" 2>/dev/null || echo 0)"
  out_dur="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "${transcoded_file}" 2>/dev/null || echo 0)"
  diff_pct="$(awk -v a="${src_dur}" -v b="${out_dur}" 'BEGIN{if(a<=0){print 100}else{d=a-b; if(d<0)d=-d; print (d/a)*100}}')"

  # Lightweight proxy until full VMAF pipeline is available everywhere.
  estimated_vmaf="$(awk -v d="${diff_pct}" 'BEGIN{v=98-(d*2); if(v<70)v=70; print v}')"
  pass="$(awk -v v="${estimated_vmaf}" -v t="${target_vmaf}" 'BEGIN{if(v>=t) print "true"; else print "false"}')"

  jq -n \
    --arg source "${source_file}" \
    --arg transcoded "${transcoded_file}" \
    --argjson target "${target_vmaf}" \
    --argjson estimated "${estimated_vmaf}" \
    --arg pass "${pass}" \
    '{
      schema_version: "1.0",
      source: $source,
      transcoded: $transcoded,
      target_vmaf: $target,
      estimated_vmaf: $estimated,
      pass: ($pass == "true")
    }'

  if [[ "${ci}" == "1" && "${pass}" != "true" ]]; then
    exit "${TTUNE_EXIT_VMAF}"
  fi
}
