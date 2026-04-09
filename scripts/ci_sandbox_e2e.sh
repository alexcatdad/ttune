#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX_DIR="${ROOT_DIR}/.sandbox/ci"
HOME_DIR="${SANDBOX_DIR}/home"
OUT_DIR="${SANDBOX_DIR}/out"
MEDIA_DIR="${SANDBOX_DIR}/media"

mkdir -p "${HOME_DIR}" "${OUT_DIR}" "${MEDIA_DIR}"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i testsrc2=size=1920x1080:rate=24 \
  -f lavfi -i sine=frequency=880:sample_rate=48000 \
  -t 6 -c:v libx264 -pix_fmt yuv420p -c:a aac \
  -y "${MEDIA_DIR}/sdr.mp4"

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i testsrc=size=1920x1080:rate=24 \
  -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -t 4 -c:v libx265 -pix_fmt yuv420p10le \
  -x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc" \
  -c:a aac -y "${MEDIA_DIR}/hdr10.mkv"

HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" detect --json >"${OUT_DIR}/detect.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" benchmark --json --duration 1 >"${OUT_DIR}/benchmark.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" benchmark --json --duration 1 --no-cache >"${OUT_DIR}/benchmark_nocache.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" optimize -i "${MEDIA_DIR}/sdr.mp4" --codec hevc --output-format json >"${OUT_DIR}/optimize_sdr.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" optimize -i "${MEDIA_DIR}/hdr10.mkv" --codec hevc --hdr-mode auto --output-format json >"${OUT_DIR}/optimize_hdr.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" optimize -i "${MEDIA_DIR}/sdr.mp4" --output-format ffmpeg-cmd >"${OUT_DIR}/ffmpeg_cmd.txt"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" generate tdarr --node-name ci-node >"${OUT_DIR}/generate_tdarr.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" generate tdarr --flow >"${OUT_DIR}/generate_tdarr_flow.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" generate tdarr --flow-ts >"${OUT_DIR}/generate_tdarr_flow.ts"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" generate docker-labels >"${OUT_DIR}/docker_labels.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" generate k8s-labels >"${OUT_DIR}/k8s_labels.txt"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" fleet-config --hosts localhost --json >"${OUT_DIR}/fleet.json"
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" verify --source "${MEDIA_DIR}/sdr.mp4" --transcoded "${MEDIA_DIR}/sdr.mp4" --ci >"${OUT_DIR}/verify_same.json"

set +e
HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" optimize -i "${MEDIA_DIR}/missing.mp4" --output-format json >"${OUT_DIR}/negative_missing.log" 2>&1
missing_exit=$?
set -e
echo "${missing_exit}" >"${OUT_DIR}/negative_missing.exit"

HOME="${HOME_DIR}" "${ROOT_DIR}/ttune" detect --json --diff >"${OUT_DIR}/detect_diff.json"

jq -e '.fingerprint and .profile.hardware and .profile.encoders' "${OUT_DIR}/detect.json" >/dev/null
jq -e '.schema_version=="1.0" and (.encoder_results|type=="array") and .recommendations.balanced' "${OUT_DIR}/benchmark.json" >/dev/null
jq -e '.schema_version=="1.0" and (.encoder_results|type=="array") and .recommendations.speed_priority' "${OUT_DIR}/benchmark_nocache.json" >/dev/null
jq -e '.schema_version=="1.0" and .input and .encoder and .quality_param and .fallback.chain' "${OUT_DIR}/optimize_sdr.json" >/dev/null
jq -e '.file_analysis.video.hdr == true and .hdr_mode == "tonemap"' "${OUT_DIR}/optimize_hdr.json" >/dev/null
rg '^ffmpeg -i ' "${OUT_DIR}/ffmpeg_cmd.txt" >/dev/null
jq -e '.library_variables and .node_config' "${OUT_DIR}/generate_tdarr.json" >/dev/null
jq -e '.nodes and .edges' "${OUT_DIR}/generate_tdarr_flow.json" >/dev/null
rg 'module\.exports' "${OUT_DIR}/generate_tdarr_flow.ts" >/dev/null
jq -e 'has("com.ttune.encoder") and has("com.ttune.tier")' "${OUT_DIR}/docker_labels.json" >/dev/null
rg 'ttune\.io/encoder=' "${OUT_DIR}/k8s_labels.txt" >/dev/null
jq -e '.fleet|length>=1' "${OUT_DIR}/fleet.json" >/dev/null
jq -e '.pass == true' "${OUT_DIR}/verify_same.json" >/dev/null
test "$(cat "${OUT_DIR}/negative_missing.exit")" = "3"
jq -e '.changed|type=="boolean"' "${OUT_DIR}/detect_diff.json" >/dev/null

echo "sandbox_ci: passed"
