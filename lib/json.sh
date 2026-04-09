#!/usr/bin/env bash

ttune_json_bool() {
  if [[ "${1:-}" == "1" || "${1:-}" == "true" ]]; then
    echo true
  else
    echo false
  fi
}

ttune_json_file_analysis() {
  local file="${1}"
  ffprobe -v quiet -print_format json -show_streams -show_format "${file}" | jq '
    {
      format: .format.format_name,
      duration: (.format.duration | tonumber? // 0),
      size_bytes: (.format.size | tonumber? // 0),
      video: (
        .streams
        | map(select(.codec_type=="video"))[0]
        | {
            codec: .codec_name,
            width: .width,
            height: .height,
            pix_fmt: .pix_fmt,
            hdr: (
              (.color_transfer == "smpte2084") or
              (.color_space == "bt2020nc") or
              (.color_primaries == "bt2020")
            )
          }
      ),
      audio_codecs: (.streams | map(select(.codec_type=="audio").codec_name) | unique),
      subtitles: (.streams | map(select(.codec_type=="subtitle") | {codec: .codec_name, forced: (.disposition.forced == 1)}) )
    }'
}
