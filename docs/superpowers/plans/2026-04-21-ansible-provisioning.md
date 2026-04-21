# Ansible Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `provision.sh` with an Ansible playbook that runs from a project-local Python venv, giving declarative, idempotent, diffable provisioning via `ansible-playbook --check --diff`.

**Architecture:** `setup-vm.sh` activates `.venv`, copies the host SSH key into the VM once via `sshpass`, then hands off to `ansible-playbook`. The playbook is a single flat file with tasks for every tool. `--check` flag added to `setup-vm.sh` passes `--check --diff` to Ansible.

**Tech Stack:** Bash, Ansible (ansible-core via pip, community.general collection), Python 3 venv, bats-core.

---

## File Map

| File | Purpose |
|------|---------|
| `requirements.txt` | Pins `ansible-core` for the project venv |
| `playbook.yml` | All provisioning tasks |
| `setup-vm.sh` | Updated — venv activation, SSH key copy, ansible-playbook call, `--check` flag |
| `provision.sh` | Deleted |
| `tests/test_setup_vm.bats` | Updated — new dry-run assertions |
| `.gitignore` | Updated — add `.venv/` |
| `README.md` | Updated — new prerequisites |

---

## Task 1: Scaffold — requirements.txt and .gitignore

**Files:**
- Create: `requirements.txt`
- Modify: `.gitignore`

- [ ] **Step 1: Create requirements.txt**

Create `/Users/laurentsaint-felix/Devel/claude-vm/requirements.txt`:
```
ansible-core>=2.17,<3.0
```

- [ ] **Step 2: Update .gitignore**

Edit `/Users/laurentsaint-felix/Devel/claude-vm/.gitignore` to add `.venv/`:
```
*.conf
!*.example
.venv/
```

- [ ] **Step 3: Create the venv and install deps**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/ansible-playbook --version | head -1
```
Expected: prints `ansible-playbook [core 2.x.x]`

- [ ] **Step 4: Install community.general collection**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
.venv/bin/ansible-galaxy collection install community.general
```
Expected: `community.general:x.x.x was installed successfully` (or already installed)

- [ ] **Step 5: Verify .venv is gitignored**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git check-ignore .venv && echo "ignored (good)" || echo "not ignored (bad)"
```
Expected: `ignored (good)`

- [ ] **Step 6: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add requirements.txt .gitignore
git commit -m "chore: add requirements.txt and gitignore .venv"
git push
```

---

## Task 2: playbook.yml

**Files:**
- Create: `playbook.yml`

- [ ] **Step 1: Create playbook.yml**

Create `/Users/laurentsaint-felix/Devel/claude-vm/playbook.yml`:
```yaml
---
- name: Provision elastic-dev VM
  hosts: all
  become: false

  vars:
    nvm_dir: "{{ ansible_env.HOME }}/.nvm"
    nvm_version: "v0.40.1"
    node_version: "24"
    go_bin: "{{ ansible_env.HOME }}/go/bin"
    brew_bin: /opt/homebrew/bin

  tasks:

    # ── Homebrew ──────────────────────────────────────────────────────────────

    - name: Check if Homebrew is installed
      ansible.builtin.stat:
        path: /opt/homebrew/bin/brew
      register: brew_binary

    - name: Install Homebrew
      ansible.builtin.shell: |
        NONINTERACTIVE=1 /bin/bash -c \
          "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      when: not brew_binary.stat.exists
      changed_when: true

    - name: Persist Homebrew in ~/.zprofile
      ansible.builtin.lineinfile:
        path: "{{ ansible_env.HOME }}/.zprofile"
        line: 'eval "$(/opt/homebrew/bin/brew shellenv)"'
        create: true
        mode: "0644"

    # ── Brew formulae ──────────────────────────────────────────────────────────

    - name: Install brew formulae
      community.general.homebrew:
        name:
          - go
          - golangci-lint
          - pre-commit
          - coreutils
          - gh
        state: present
        path: "{{ brew_bin }}"

    # ── Ghostty ────────────────────────────────────────────────────────────────

    - name: Check if Ghostty app bundle exists
      ansible.builtin.stat:
        path: /Applications/Ghostty.app
      register: ghostty_app

    - name: Uninstall broken Ghostty cask if app bundle is missing
      community.general.homebrew_cask:
        name: ghostty
        state: absent
        path: "{{ brew_bin }}"
      when: not ghostty_app.stat.exists
      failed_when: false

    - name: Install Ghostty
      community.general.homebrew_cask:
        name: ghostty
        state: present
        path: "{{ brew_bin }}"

    - name: Remove quarantine from Ghostty
      ansible.builtin.shell: xattr -rd com.apple.quarantine /Applications/Ghostty.app
      failed_when: false
      changed_when: false

    - name: Register apps with Launch Services
      ansible.builtin.shell: >
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
        -v /Applications/
      failed_when: false
      changed_when: false

    # ── nvm ────────────────────────────────────────────────────────────────────

    - name: Check if nvm is installed
      ansible.builtin.stat:
        path: "{{ nvm_dir }}"
      register: nvm_dir_stat

    - name: Install nvm
      ansible.builtin.shell: |
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/{{ nvm_version }}/install.sh | bash
      when: not nvm_dir_stat.stat.exists
      changed_when: true

    - name: Persist nvm in ~/.zprofile
      ansible.builtin.lineinfile:
        path: "{{ ansible_env.HOME }}/.zprofile"
        line: 'export NVM_DIR="{{ nvm_dir }}"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
        create: true
        mode: "0644"

    # ── Node.js 24 ─────────────────────────────────────────────────────────────

    - name: Check if Node.js 24 is installed
      ansible.builtin.shell: |
        export NVM_DIR="{{ nvm_dir }}"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm ls {{ node_version }}
      register: node_installed
      failed_when: false
      changed_when: false

    - name: Install Node.js 24
      ansible.builtin.shell: |
        export NVM_DIR="{{ nvm_dir }}"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install {{ node_version }}
        nvm alias default {{ node_version }}
      when: node_installed.rc != 0
      changed_when: true

    # ── Go PATH ────────────────────────────────────────────────────────────────

    - name: Persist Go bin in ~/.zprofile
      ansible.builtin.lineinfile:
        path: "{{ ansible_env.HOME }}/.zprofile"
        line: 'export PATH="{{ go_bin }}:$PATH"'
        create: true
        mode: "0644"

    # ── goimports ──────────────────────────────────────────────────────────────

    - name: Check if goimports is installed
      ansible.builtin.stat:
        path: "{{ go_bin }}/goimports"
      register: goimports_stat

    - name: Install goimports
      ansible.builtin.shell: go install golang.org/x/tools/cmd/goimports@latest
      environment:
        PATH: "{{ brew_bin }}:{{ go_bin }}:{{ ansible_env.PATH }}"
        HOME: "{{ ansible_env.HOME }}"
        GOPATH: "{{ ansible_env.HOME }}/go"
      when: not goimports_stat.stat.exists
      changed_when: true

    # ── Claude Code ────────────────────────────────────────────────────────────

    - name: Check if Claude Code is installed
      ansible.builtin.shell: |
        export NVM_DIR="{{ nvm_dir }}"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        command -v claude
      register: claude_check
      failed_when: false
      changed_when: false

    - name: Install Claude Code
      ansible.builtin.shell: |
        export NVM_DIR="{{ nvm_dir }}"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        npm install -g @anthropic-ai/claude-code
      when: claude_check.rc != 0
      changed_when: true
```

- [ ] **Step 2: Verify syntax**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
.venv/bin/ansible-playbook --syntax-check -i "127.0.0.1," playbook.yml
```
Expected: `playbook: playbook.yml` with no errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add playbook.yml
git commit -m "feat: add Ansible playbook for VM provisioning"
git push
```

---

## Task 3: Update bats tests (write failing tests first)

**Files:**
- Modify: `tests/test_setup_vm.bats`

- [ ] **Step 1: Update the failing test and add new ones**

Replace the contents of `/Users/laurentsaint-felix/Devel/claude-vm/tests/test_setup_vm.bats`:
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

@test "dry-run prints ansible provisioning steps" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"tart run --no-graphics"* ]]
  [[ "$output" == *"ssh-copy-id"* ]]
  [[ "$output" == *"ansible-playbook"* ]]
  [[ "$output" == *"tart stop"* ]]
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
```

- [ ] **Step 2: Run tests to verify the new/changed ones fail**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/test_setup_vm.bats
```
Expected: "dry-run prints ansible provisioning steps", "dry-run does not include provision.sh", and "dry-run with --check includes --check --diff" fail. The five Phase 1 tests still pass.

- [ ] **Step 3: Commit failing tests**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add tests/test_setup_vm.bats
git commit -m "test: update setup-vm bats tests for Ansible provisioning"
git push
```

---

## Task 4: Update setup-vm.sh

**Files:**
- Modify: `setup-vm.sh`

- [ ] **Step 1: Rewrite setup-vm.sh**

Replace the contents of `/Users/laurentsaint-felix/Devel/claude-vm/setup-vm.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

VM_NAME="elastic-dev"
BASE_IMAGE="ghcr.io/cirruslabs/macos-sequoia-base:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_PLAYBOOK="$SCRIPT_DIR/.venv/bin/ansible-playbook"
DRY_RUN=false
CHECK=false
VM_USER="admin"
VM_PASS="admin"
SSH_TIMEOUT=300
SSH_INTERVAL=5
SSH_OPTS=(-o StrictHostKeyChecking=no -o PubkeyAuthentication=no -o PreferredAuthentications=password)

usage() {
  echo "Usage: $0 [--dry-run] [--check]" >&2
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
    --check)   CHECK=true; shift ;;
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
  if [[ ! -f "$ANSIBLE_PLAYBOOK" ]]; then
    echo "Error: Ansible venv not found at $SCRIPT_DIR/.venv" >&2
    echo "  Run:" >&2
    echo "    python3 -m venv .venv" >&2
    echo "    .venv/bin/pip install -r requirements.txt" >&2
    echo "    .venv/bin/ansible-galaxy collection install community.general" >&2
    exit 1
  fi
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
  ANSIBLE_CMD="ansible-playbook -i <ip>, playbook.yml"
  if "$CHECK"; then
    ANSIBLE_CMD="$ANSIBLE_CMD --check --diff"
  fi
  echo "[dry-run] tart run --no-graphics $VM_NAME &"
  echo "[dry-run] wait for SSH at <ip>..."
  echo "[dry-run] ssh-copy-id $VM_USER@<ip>"
  echo "[dry-run] $ANSIBLE_CMD"
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
        "${SSH_OPTS[@]}" -o ConnectTimeout=3 \
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

log "Copying SSH key to VM..."
sshpass -p "$VM_PASS" ssh-copy-id \
  -o StrictHostKeyChecking=no \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  "$VM_USER@$VM_IP" 2>/dev/null || true

ANSIBLE_OPTS=(-i "$VM_IP," "$SCRIPT_DIR/playbook.yml")
if "$CHECK"; then
  ANSIBLE_OPTS+=(--check --diff)
  log "Running Ansible playbook (check mode — no changes will be made)..."
else
  log "Running Ansible playbook (this takes ~10 minutes)..."
fi
"$ANSIBLE_PLAYBOOK" "${ANSIBLE_OPTS[@]}"

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

- [ ] **Step 2: Run all tests to verify they pass**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/
```
Expected: all 16 tests pass (9 setup-vm + 7 start-vm).

- [ ] **Step 3: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add setup-vm.sh
git commit -m "feat: replace provision.sh with Ansible playbook in setup-vm.sh"
git push
```

---

## Task 5: Clean up — delete provision.sh and update README

**Files:**
- Delete: `provision.sh`
- Modify: `README.md`

- [ ] **Step 1: Delete provision.sh**

```bash
rm /Users/laurentsaint-felix/Devel/claude-vm/provision.sh
```

- [ ] **Step 2: Update README.md**

Replace the Prerequisites section in `/Users/laurentsaint-felix/Devel/claude-vm/README.md`:
```markdown
## Prerequisites

```bash
brew install cirruslabs/cli/tart
brew install sshpass
```

Then set up the Ansible venv (one-time, on the host):

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/ansible-galaxy collection install community.general
```

`bats-core` is only needed to run the test suite:

```bash
brew install bats-core
```
```

Also update the How it works table to replace `provision.sh` row with `playbook.yml`:
```markdown
| `playbook.yml` | Ansible playbook; runs inside the VM via SSH to install all dev deps |
```

- [ ] **Step 3: Run full test suite one last time**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
bats tests/
```
Expected: all 16 tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/laurentsaint-felix/Devel/claude-vm
git add -A
git commit -m "chore: remove provision.sh and update README for Ansible"
git push
```
