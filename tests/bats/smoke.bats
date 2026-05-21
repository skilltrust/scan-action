#!/usr/bin/env bats

@test "bats is wired" {
  run echo "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}
