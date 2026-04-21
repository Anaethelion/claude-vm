#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../start-vm.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  # Create real directories for mount paths
  mkdir -p "$TEST_DIR/repo-a" "$TEST_DIR/repo-b"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "dry-run prints tart run command" {
  cat > "$TEST_DIR/mounts.conf" <<EOF
repo-a=$TEST_DIR/repo-a
EOF
  run bash "$SCRIPT" --dry-run --config "$TEST_DIR/mounts.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tart run elastic-dev"* ]]
}

@test "dry-run includes --dir flag with correct format" {
  cat > "$TEST_DIR/mounts.conf" <<EOF
repo-a=$TEST_DIR/repo-a
EOF
  run bash "$SCRIPT" --dry-run --config "$TEST_DIR/mounts.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dir repo-a:$TEST_DIR/repo-a"* ]]
}

@test "dry-run with multiple mounts includes all --dir flags" {
  cat > "$TEST_DIR/mounts.conf" <<EOF
repo-a=$TEST_DIR/repo-a
repo-b=$TEST_DIR/repo-b
EOF
  run bash "$SCRIPT" --dry-run --config "$TEST_DIR/mounts.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dir repo-a:$TEST_DIR/repo-a"* ]]
  [[ "$output" == *"--dir repo-b:$TEST_DIR/repo-b"* ]]
}

@test "prints mount reference table with VM paths" {
  cat > "$TEST_DIR/mounts.conf" <<EOF
go-elasticsearch=$TEST_DIR/repo-a
EOF
  run bash "$SCRIPT" --dry-run --config "$TEST_DIR/mounts.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/Volumes/My Shared Files/go-elasticsearch"* ]]
}

@test "fails with nonzero exit if config file missing" {
  run bash "$SCRIPT" --dry-run --config "$TEST_DIR/nonexistent.conf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "fails with nonzero exit if mount path does not exist" {
  cat > "$TEST_DIR/mounts.conf" <<EOF
repo-a=/nonexistent/path/that/does/not/exist
EOF
  run bash "$SCRIPT" --dry-run --config "$TEST_DIR/mounts.conf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "skips blank lines and comment lines in config" {
  cat > "$TEST_DIR/mounts.conf" <<EOF
# this is a comment
repo-a=$TEST_DIR/repo-a

repo-b=$TEST_DIR/repo-b
EOF
  run bash "$SCRIPT" --dry-run --config "$TEST_DIR/mounts.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dir repo-a:"* ]]
  [[ "$output" == *"--dir repo-b:"* ]]
}
