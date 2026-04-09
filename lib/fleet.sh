#!/usr/bin/env bash

ttune_fleet_usage() {
  cat <<'EOF'
ttune fleet-config --hosts hostA,hostB [--ssh-user user] [--json]
EOF
}

ttune_fleet_collect_local_or_remote() {
  local host="${1}" ssh_user="${2}"
  if [[ "${host}" == "localhost" || "${host}" == "$(hostname)" ]]; then
    ttune_detect_profile_json
  else
    ssh "${ssh_user}@${host}" "ttune detect --json" 2>/dev/null | jq -c '.profile // .'
  fi
}

ttune_fleet_main() {
  local hosts_csv="" ssh_user="${USER}" as_json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --hosts)
      hosts_csv="${2}"
      shift
      ;;
    --ssh-user)
      ssh_user="${2}"
      shift
      ;;
    --json) as_json=1 ;;
    --help | -h)
      ttune_fleet_usage
      return
      ;;
    *)
      ttune_err "Unknown fleet option: $1"
      exit "${TTUNE_EXIT_USAGE}"
      ;;
    esac
    shift
  done

  if [[ -z "${hosts_csv}" ]]; then
    ttune_err "Missing --hosts"
    exit "${TTUNE_EXIT_USAGE}"
  fi

  local items="[]" host
  while IFS= read -r host; do
    [[ -z "${host}" ]] && continue
    local node_json
    node_json="$(ttune_fleet_collect_local_or_remote "${host}" "${ssh_user}" || true)"
    if [[ -n "${node_json}" ]]; then
      items="$(jq -n --argjson arr "${items}" --argjson node "${node_json}" '$arr + [$node]')"
    fi
  done <<<"$(printf '%s' "${hosts_csv}" | tr ',' '\n')"

  local out
  out="$(jq -n --arg ts "$(ttune_now_iso)" --argjson nodes "${items}" '
    {
      schema_version: "1.0",
      timestamp: $ts,
      fleet: $nodes,
      labels: (
        $nodes
        | map({
            host: .hostname,
            labels: {
              "ttune.io/encoder": (.encoders.available[0] // "unknown"),
              "ttune.io/tier": (if ((.hardware.memory_gb // 0) >= 32) then "high" else "mid" end)
            }
          })
      )
    }')"

  if [[ "${as_json}" == "1" ]]; then
    printf '%s\n' "${out}"
  else
    jq -r '.labels[] | "- \(.host): \(.labels["ttune.io/encoder"]) (\(.labels["ttune.io/tier"]))"' <<<"${out}"
  fi
}
