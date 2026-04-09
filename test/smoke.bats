#!/usr/bin/env bats

setup() {
  chmod +x ./ttune
}

@test "ttune version command runs" {
  run ./ttune version
  [ "$status" -eq 0 ]
}

@test "ttune detect json emits fingerprint" {
  run ./ttune detect --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.fingerprint' >/dev/null
}
