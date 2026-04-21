#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../setup-vm.sh"

@test "dry-run prints tart pull command" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"tart pull ghcr.io/cirruslabs/macos-sequoia-base:latest"* ]]
}

@test "dry-run prints tart clone with correct VM name" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"tart clone"* ]]
  [[ "$output" == *"elastic-dev"* ]]
}

@test "dry-run prints tart set with 12 CPUs" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--cpu 12"* ]]
}

@test "dry-run prints tart set with 24576 MB RAM" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--memory 24576"* ]]
}

@test "dry-run prints tart set with 200 GB disk" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--disk-size 200"* ]]
}

@test "dry-run prints SSH provisioning steps" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"tart run --no-graphics"* ]]
  [[ "$output" == *"provision.sh"* ]]
  [[ "$output" == *"tart stop"* ]]
}

@test "exits nonzero on unknown flag" {
  run bash "$SCRIPT" --unknown-flag
  [ "$status" -ne 0 ]
}
