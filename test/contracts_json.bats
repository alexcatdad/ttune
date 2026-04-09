#!/usr/bin/env bats

@test "benchmark json matches required keys" {
  run ./ttune benchmark --json --duration 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    has("schema_version") and
    has("encoder_results") and
    has("recommendations")
  ' >/dev/null
}
