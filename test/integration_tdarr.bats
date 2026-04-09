#!/usr/bin/env bats

@test "tdarr generation returns library_variables and node_config" {
  run ./ttune generate tdarr --node-name test-node
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.library_variables and .node_config' >/dev/null
}
