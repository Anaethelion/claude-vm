# Elastic Dev VM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create three shell scripts (`setup-vm.sh`, `start-vm.sh`, `provision.sh`) that fully automate creating and launching a macOS 15 Sequoia Tart VM pre-loaded with Elastic project dev dependencies, with host repo directories mounted into the VM.

**Architecture:** `setup-vm.sh` is a one-time script that creates the VM and provisions it headlessly via SSH; `start-vm.sh` is the daily driver that mounts host directories and opens the GUI; `provision.sh` is the remote script copied into the VM during setup. All scripts support `--dry-run` for safe testing.

**Tech Stack:** Bash, [Tart](https://github.com/cirruslabs/tart) (macOS VMs), `sshpass` (SSH automation), `bats-core` (shell testing), Homebrew, Go 1.25+, Node.js 24 (via nvm).

---

## File Map

| File | Purpose |
|------|---------|
| `setup-vm.sh` | One-time VM creation + headless provisioning |
| `start-vm.sh` | Daily: parse mounts config, launch VM with GUI |
| `provision.sh` | Runs inside VM via SSH; installs all dev deps |
| `vm-mounts.conf.example` | Template config file for users to copy |
| `tests/test_start_vm.bats` | Bats tests for start-vm.sh logic |
| `tests/test_setup_vm.bats` | Bats tests for setup-vm.sh dry-run output |

---

## Task 1: Scaffold — install bats and create project structure

**Files:**
- Create: `tests/.gitkeep`
- Create: `.gitignore`

- [ ] **Step 1: Install bats-core on the host**

```bash
brew install bats-core
bats --version
```
Expected output: `Bats x.y.z`

- [ ] **Step 2: Create .gitignore**

Create `/Users/laurentsaint-felix/Devel/claude-vm/.gitignore`:
```
*.conf
!*.example
```

This prevents accidentally committing real `vm-mounts.conf` with personal paths while keeping the example.

- [ ] **Step 3: Create tests directory**

```bash
mkdir -p /Users/laurentsaint-felix/Devel/claude-vm/tests
touch /Users/laurentsaint-felix/Devel/claude-vm/tests/.gitkeep
```

- [ ] **Step 4: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add .gitignore tests/.gitkeep
git commit -m "chore: scaffold project structure"
```

---

## Task 2: vm-mounts.conf.example

**Files:**
- Create: `vm-mounts.conf.example`

- [ ] **Step 1: Create the example config**

Create `/Users/laurentsaint-felix/Devel/claude-vm/vm-mounts.conf.example`:
```
# Mount name=absolute-host-path
# Copy this file to vm-mounts.conf and fill in your actual paths.
# Inside the VM each mount is at: /Volumes/My Shared Files/<name>

your-repo=/absolute/path/to/your-repo



```

- [ ] **Step 2: Verify .gitignore allows the example but blocks the real config**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git check-ignore vm-mounts.conf.example && echo "BLOCKED (bad)" || echo "not ignored (good)"
touch vm-mounts.conf
git check-ignore vm-mounts.conf && echo "ignored (good)" || echo "not ignored (bad)"
rm vm-mounts.conf
```
Expected: first line prints `not ignored (good)`, second prints `ignored (good)`.

- [ ] **Step 3: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add vm-mounts.conf.example
git commit -m "chore: add vm-mounts.conf.example"
```

---

## Task 3: start-vm.sh + tests

**Files:**
- Create: `start-vm.sh`
- Create: `tests/test_start_vm.bats`

- [ ] **Step 1: Write the failing tests**

Create `/Users/laurentsaint-felix/Devel/claude-vm/tests/test_start_vm.bats`:
```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/test_start_vm.bats
```
Expected: all tests fail with `command not found` or similar (start-vm.sh doesn't exist yet).

- [ ] **Step 3: Implement start-vm.sh**

Create `/Users/laurentsaint-felix/Devel/claude-vm/start-vm.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

VM_NAME="elastic-dev"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/vm-mounts.conf"
DRY_RUN=false

usage() {
  echo "Usage: $0 [--dry-run] [--config <path>]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: config file not found: $CONFIG_FILE" >&2
  exit 1
fi

DIR_FLAGS=()
MOUNT_NAMES=()

while IFS='=' read -r name path || [[ -n "${name:-}" ]]; do
  [[ -z "${name:-}" || "$name" =~ ^# ]] && continue
  if [[ ! -d "$path" ]]; then
    echo "Error: mount path not found: $path (for $name)" >&2
    exit 1
  fi
  DIR_FLAGS+=("--dir" "${name}:${path}")
  MOUNT_NAMES+=("$name")
done < "$CONFIG_FILE"

echo "Starting $VM_NAME..."
echo ""
echo "Mounts:"
for name in "${MOUNT_NAMES[@]}"; do
  printf "  %-35s →  /Volumes/My Shared Files/%s\n" "$name" "$name"
done
echo ""

CMD=(tart run "$VM_NAME" "${DIR_FLAGS[@]}")

if "$DRY_RUN"; then
  echo "[dry-run] ${CMD[*]}"
else
  exec "${CMD[@]}"
fi
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x /Users/laurentsaint-felix/Devel/claude-vm/start-vm.sh
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/test_start_vm.bats
```
Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add start-vm.sh tests/test_start_vm.bats
git commit -m "feat: add start-vm.sh with mount config parsing"
```

---

## Task 4: provision.sh

**Files:**
- Create: `provision.sh`

This script runs inside the VM. There are no unit tests for it — correctness is verified by running it in the VM during integration. It is idempotent: each tool is only installed if not already present.

- [ ] **Step 1: Create provision.sh**

Create `/Users/laurentsaint-felix/Devel/claude-vm/provision.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

log() { echo "==> [provision] $*"; }

# ── Homebrew ──────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  log "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Add brew to PATH for this session (works for both Apple Silicon and Intel)
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Persist brew PATH in shell profile
BREW_INIT='eval "$(/opt/homebrew/bin/brew shellenv)"'
if ! grep -qF "$BREW_INIT" "$HOME/.zprofile" 2>/dev/null; then
  echo "$BREW_INIT" >> "$HOME/.zprofile"
fi

log "Homebrew: $(brew --version | head -1)"

# ── Go ────────────────────────────────────────────────────────────────────────
if ! command -v go &>/dev/null; then
  log "Installing Go..."
  brew install go
fi

# Persist ~/go/bin in PATH
GO_PATH_INIT='export PATH="$HOME/go/bin:$PATH"'
if ! grep -qF "$GO_PATH_INIT" "$HOME/.zprofile" 2>/dev/null; then
  echo "$GO_PATH_INIT" >> "$HOME/.zprofile"
fi
export PATH="$HOME/go/bin:$PATH"
log "Go: $(go version)"

# ── nvm + Node.js 24 ─────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
if [[ ! -d "$NVM_DIR" ]]; then
  log "Installing nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! nvm ls 24 &>/dev/null; then
  log "Installing Node.js 24..."
  nvm install 24
fi
nvm alias default 24

# Persist nvm init in .zprofile
NVM_INIT='export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
if ! grep -qF 'NVM_DIR' "$HOME/.zprofile" 2>/dev/null; then
  echo "$NVM_INIT" >> "$HOME/.zprofile"
fi
log "Node.js: $(node --version)"

# ── goimports ────────────────────────────────────────────────────────────────
if ! command -v goimports &>/dev/null; then
  log "Installing goimports..."
  go install golang.org/x/tools/cmd/goimports@latest
fi
log "goimports: installed"

# ── golangci-lint ────────────────────────────────────────────────────────────
if ! command -v golangci-lint &>/dev/null; then
  log "Installing golangci-lint..."
  brew install golangci-lint
fi
log "golangci-lint: $(golangci-lint --version)"

# ── pre-commit ───────────────────────────────────────────────────────────────
if ! command -v pre-commit &>/dev/null; then
  log "Installing pre-commit..."
  brew install pre-commit
fi
log "pre-commit: $(pre-commit --version)"

# ── GNU coreutils ────────────────────────────────────────────────────────────
if ! brew list coreutils &>/dev/null 2>&1; then
  log "Installing GNU coreutils..."
  brew install coreutils
fi
log "coreutils: installed"

# ── Claude Code CLI ───────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
  log "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
fi
log "Claude Code: $(claude --version 2>/dev/null || echo 'installed')"

# ── Summary ──────────────────────────────────────────────────────────────────
log ""
log "Provisioning complete. Summary:"
log "  Go:            $(go version)"
log "  Node.js:       $(node --version)"
log "  npm:           $(npm --version)"
log "  golangci-lint: $(golangci-lint --version 2>&1 | head -1)"
log "  pre-commit:    $(pre-commit --version)"
log ""
log "PATH additions written to ~/.zprofile (take effect on next login)."
```

- [ ] **Step 2: Make executable and verify syntax**

```bash
chmod +x /Users/laurentsaint-felix/Devel/claude-vm/provision.sh
bash -n /Users/laurentsaint-felix/Devel/claude-vm/provision.sh
echo "Syntax OK"
```
Expected: prints `Syntax OK` with no errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add provision.sh
git commit -m "feat: add provision.sh with idempotent dep installs"
```

---

## Task 5: setup-vm.sh + tests

**Files:**
- Create: `setup-vm.sh`
- Create: `tests/test_setup_vm.bats`

- [ ] **Step 1: Write the failing tests**

Create `/Users/laurentsaint-felix/Devel/claude-vm/tests/test_setup_vm.bats`:
```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/test_setup_vm.bats
```
Expected: all tests fail (setup-vm.sh doesn't exist yet).

- [ ] **Step 3: Implement setup-vm.sh**

Create `/Users/laurentsaint-felix/Devel/claude-vm/setup-vm.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

VM_NAME="elastic-dev"
BASE_IMAGE="ghcr.io/cirruslabs/macos-sequoia-base:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION_SCRIPT="$SCRIPT_DIR/provision.sh"
DRY_RUN=false
VM_USER="admin"
VM_PASS="admin"
SSH_TIMEOUT=300
SSH_INTERVAL=5

usage() {
  echo "Usage: $0 [--dry-run]" >&2
  exit 1
}

log() { echo "==> $*"; }

run_cmd() {
  if "$DRY_RUN"; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    *) usage ;;
  esac
done

# ── Prerequisites check (skip in dry-run) ────────────────────────────────────
if ! "$DRY_RUN"; then
  for cmd in tart sshpass; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: '$cmd' is required but not installed." >&2
      echo "  tart:    brew install cirruslabs/cli/tart" >&2
      echo "  sshpass: brew install sshpass" >&2
      exit 1
    fi
  done
fi

# ── Phase 1: VM creation ──────────────────────────────────────────────────────
log "Phase 1: VM creation"

if ! "$DRY_RUN" && tart list 2>/dev/null | grep -q "^${VM_NAME}[[:space:]]"; then
  log "VM '$VM_NAME' already exists, skipping creation."
else
  run_cmd tart pull "$BASE_IMAGE"
  run_cmd tart clone "$BASE_IMAGE" "$VM_NAME"
  run_cmd tart set "$VM_NAME" --cpu 12 --memory 24576 --disk-size 200
fi

# ── Phase 2: Headless provisioning ───────────────────────────────────────────
log "Phase 2: Headless provisioning"

if "$DRY_RUN"; then
  echo "[dry-run] tart run --no-graphics $VM_NAME &"
  echo "[dry-run] wait for SSH at <ip>..."
  echo "[dry-run] sshpass -p $VM_PASS scp provision.sh $VM_USER@<ip>:/tmp/provision.sh"
  echo "[dry-run] sshpass -p $VM_PASS ssh $VM_USER@<ip> bash /tmp/provision.sh"
  echo "[dry-run] tart stop $VM_NAME"
  exit 0
fi

log "Booting VM headlessly..."
tart run --no-graphics "$VM_NAME" &
TART_PID=$!

cleanup() {
  log "Stopping VM..."
  tart stop "$VM_NAME" 2>/dev/null || true
  wait "$TART_PID" 2>/dev/null || true
}
trap cleanup EXIT

log "Waiting for SSH (max ${SSH_TIMEOUT}s)..."
ELAPSED=0
VM_IP=""
while [[ $ELAPSED -lt $SSH_TIMEOUT ]]; do
  VM_IP=$(tart ip "$VM_NAME" 2>/dev/null || true)
  if [[ -n "$VM_IP" ]]; then
    if sshpass -p "$VM_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=3 \
        "$VM_USER@$VM_IP" "echo ok" &>/dev/null; then
      break
    fi
  fi
  sleep "$SSH_INTERVAL"
  ELAPSED=$((ELAPSED + SSH_INTERVAL))
  VM_IP=""
done

if [[ -z "$VM_IP" ]]; then
  echo "Error: timed out waiting for SSH after ${SSH_TIMEOUT}s" >&2
  exit 1
fi

log "VM reachable at $VM_IP"
log "Copying provisioning script..."
sshpass -p "$VM_PASS" scp \
  -o StrictHostKeyChecking=no \
  "$PROVISION_SCRIPT" "$VM_USER@$VM_IP:/tmp/provision.sh"

log "Running provisioning script (this takes ~10 minutes)..."
sshpass -p "$VM_PASS" ssh \
  -o StrictHostKeyChecking=no \
  "$VM_USER@$VM_IP" "bash /tmp/provision.sh"

log "Provisioning complete. Shutting down VM..."
trap - EXIT
tart stop "$VM_NAME"
wait "$TART_PID" 2>/dev/null || true

log ""
log "Setup complete!"
log "Next steps:"
log "  1. Copy vm-mounts.conf.example → vm-mounts.conf and fill in your repo paths"
log "  2. Run ./start-vm.sh to launch the VM"
log "  3. Change the default password (admin/admin) on first login"
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x /Users/laurentsaint-felix/Devel/claude-vm/setup-vm.sh
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/test_setup_vm.bats
```
Expected: all 7 tests pass.

- [ ] **Step 5: Run all tests together to ensure no regressions**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/
```
Expected: all 14 tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add setup-vm.sh tests/test_setup_vm.bats
git commit -m "feat: add setup-vm.sh with VM creation and headless provisioning"
```

---

## Task 6: End-to-end dry-run verification

No new files — this is a smoke-test of the full flow.

- [ ] **Step 1: Run setup-vm.sh dry-run and verify output**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
./setup-vm.sh --dry-run
```

Expected output (approximate):
```
==> Phase 1: VM creation
[dry-run] tart pull ghcr.io/cirruslabs/macos-sequoia-base:latest
[dry-run] tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest elastic-dev
[dry-run] tart set elastic-dev --cpu 12 --memory 24576 --disk-size 200
==> Phase 2: Headless provisioning
[dry-run] tart run --no-graphics elastic-dev &
[dry-run] wait for SSH at <ip>...
[dry-run] sshpass -p admin scp provision.sh admin@<ip>:/tmp/provision.sh
[dry-run] sshpass -p admin ssh admin@<ip> bash /tmp/provision.sh
[dry-run] tart stop elastic-dev
```

- [ ] **Step 2: Create a local test vm-mounts.conf and run start-vm.sh dry-run**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
# Create a real temp dir to satisfy path-existence check
TMPDIR=$(mktemp -d)
cat > /tmp/test-mounts.conf <<EOF
my-repo=$TMPDIR
EOF
./start-vm.sh --dry-run --config /tmp/test-mounts.conf
rm -rf "$TMPDIR" /tmp/test-mounts.conf
```

Expected output (approximate):
```
Starting elastic-dev...

Mounts:
  my-repo                             →  /Volumes/My Shared Files/my-repo

[dry-run] tart run elastic-dev --dir my-repo:/tmp/tmp.XXXXX
```

- [ ] **Step 3: Run the full test suite one last time**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/
```
Expected: all 14 tests pass, no failures.

- [ ] **Step 4: Final commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git status
# Nothing to commit — all changes were committed in previous tasks
```
