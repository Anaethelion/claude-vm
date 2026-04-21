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

@test "dry-run prints ansible provisioning steps" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"tart run --no-graphics"* ]]
  [[ "$output" == *"tart stop"* ]]
  [[ "$output" == *"ssh-copy-id"* ]]
  [[ "$output" == *"ansible-playbook"* ]]
}

@test "dry-run does not include provision.sh" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"provision.sh"* ]]
}

@test "dry-run with --check includes --check --diff in ansible command" {
  run bash "$SCRIPT" --dry-run --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"ansible-playbook"* ]]
  [[ "$output" == *"--check --diff"* ]]
}

@test "exits nonzero on unknown flag" {
  run bash "$SCRIPT" --unknown-flag
  [ "$status" -ne 0 ]
}
