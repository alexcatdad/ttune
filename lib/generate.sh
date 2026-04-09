#!/usr/bin/env bash

ttune_generate_tdarr_variables() {
  local node_name="${1:-ttune-node}"
  jq -n --arg node "${node_name}" '
    {
      node: $node,
      v_encoder: "libx265",
      v_preset: "slow",
      v_crf: "22",
      v_pix_fmt: "yuv420p10le",
      v_scale: "1920:-2:flags=lanczos",
      a_strategy: "copy",
      target_container: ".mkv"
    }'
}

ttune_generate_tdarr_node_config() {
  local node_name="${1}" server_url="${2}"
  local gpu_type="none"
  if ttune_detect_profile_json | jq -e '.encoders.available | index("hevc_nvenc")' >/dev/null; then
    gpu_type="nvenc"
  elif ttune_detect_profile_json | jq -e '.encoders.available | index("hevc_qsv")' >/dev/null; then
    gpu_type="qsv"
  elif ttune_detect_profile_json | jq -e '.encoders.available | index("hevc_videotoolbox")' >/dev/null; then
    gpu_type="videotoolbox"
  fi

  jq -n --arg n "${node_name}" --arg s "${server_url}" --arg g "${gpu_type}" '
    {
      nodeName: $n,
      serverURL: $s,
      transcodecpuWorkers: 2,
      transcodegpuWorkers: (if $g=="none" then 0 else 1 end),
      healthcheckcpuWorkers: 1,
      healthcheckgpuWorkers: 0,
      gpuType: $g
    }'
}

ttune_generate_tdarr_flow() {
  cat <<'EOF'
{
  "name": "ttune Auto Optimize Flow",
  "description": "Generated flow that resolves params via ttune optimize",
  "nodes": [
    {"id":"input","type":"input"},
    {"id":"run_cli","type":"Run CLI","command":"ttune optimize -i \"{{{args.inputFileObj._id}}}\" --json --codec hevc --target-vmaf 95"},
    {"id":"encode","type":"ffmpegCommandStart"},
    {"id":"output","type":"output"}
  ],
  "edges": [
    {"from":"input","to":"run_cli"},
    {"from":"run_cli","to":"encode"},
    {"from":"encode","to":"output"}
  ]
}
EOF
}

ttune_generate_tdarr_flow_ts() {
  cat <<'EOF'
const details = () => ({
  name: "Transcode Tuner Optimize",
  description: "Runs ttune to determine optimal encoding parameters for this file",
  stage: "Pre-processing",
  tags: "video,ffmpeg,optimization"
});

const plugin = async (args) => {
  const inputFile = args.inputFileObj._id;
  const result = await args.deps.cliExec(
    `ttune optimize -i "${inputFile}" --json --codec hevc --target-vmaf 95`
  );
  const params = JSON.parse(result.stdout);
  args.variables.user.encoder = params.encoder;
  args.variables.user.crf = params.quality_param.split(" ").pop();
  args.variables.user.preset = String(params.preset);
  return { outputFileObj: args.inputFileObj, outputNumber: 1, variables: args.variables };
};

module.exports = { details, plugin };
EOF
}

ttune_generate_k8s_labels() {
  local host encoder tier
  host="$(hostname)"
  encoder="$(ttune_detect_profile_json | jq -r '.encoders.available[0] // "unknown"')"
  tier="mid"
  if ttune_detect_profile_json | jq -e '.hardware.memory_gb >= 32' >/dev/null; then
    tier="high"
  fi
  cat <<EOF
kubectl label node ${host} ttune.io/encoder=${encoder} --overwrite
kubectl label node ${host} ttune.io/tier=${tier} --overwrite
EOF
}

ttune_generate_docker_labels() {
  local encoder tier
  encoder="$(ttune_detect_profile_json | jq -r '.encoders.available[0] // "unknown"')"
  tier="mid"
  if ttune_detect_profile_json | jq -e '.hardware.memory_gb >= 32' >/dev/null; then
    tier="high"
  fi
  jq -n --arg e "${encoder}" --arg t "${tier}" \
    '{"com.ttune.encoder": $e, "com.ttune.tier": $t}'
}

ttune_generate_unmanic_plugin() {
  cat <<'EOF'
from unmanic.libs.unplugins.settings import PluginSettings

class Settings(PluginSettings):
    settings = {"target_vmaf": 95, "codec": "hevc"}

def on_library_management_file_test(data):
    data["add_file_to_pending_tasks"] = True
    return data

def worker_process(data):
    in_file = data.get("abspath")
    data["exec_command"] = ["/bin/sh", "-lc", f'ttune optimize -i "{in_file}" --output-format ffmpeg-cmd']
    return data
EOF
}

ttune_generate_ci_gate() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
src="${1}"
out="${2}"
target="${3:-95}"
ttune verify --source "${src}" --transcoded "${out}" --target-vmaf "${target}" --ci
EOF
}

ttune_generate_main() {
  local kind="${1:-}"
  shift || true
  case "${kind}" in
  tdarr)
    local node_name="ttune-node" server_url="http://localhost:8266" flow=0 flow_ts=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
      --node-name)
        node_name="${2}"
        shift
        ;;
      --server-url)
        server_url="${2}"
        shift
        ;;
      --flow) flow=1 ;;
      --flow-ts) flow_ts=1 ;;
      *)
        ttune_err "Unknown tdarr option: $1"
        exit "${TTUNE_EXIT_USAGE}"
        ;;
      esac
      shift
    done
    if [[ "${flow}" == "1" ]]; then
      ttune_generate_tdarr_flow
    elif [[ "${flow_ts}" == "1" ]]; then
      ttune_generate_tdarr_flow_ts
    else
      jq -n \
        --argjson vars "$(ttune_generate_tdarr_variables "${node_name}")" \
        --argjson node "$(ttune_generate_tdarr_node_config "${node_name}" "${server_url}")" \
        '{library_variables: $vars, node_config: $node}'
    fi
    ;;
  k8s-labels)
    ttune_generate_k8s_labels
    ;;
  docker-labels)
    ttune_generate_docker_labels
    ;;
  unmanic-plugin)
    ttune_generate_unmanic_plugin
    ;;
  ci-gate-script)
    ttune_generate_ci_gate
    ;;
  *)
    ttune_err "Unknown generate target. Use: tdarr|k8s-labels|docker-labels|unmanic-plugin|ci-gate-script"
    exit "${TTUNE_EXIT_USAGE}"
    ;;
  esac
}
