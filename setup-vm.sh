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

ANSIBLE_OPTS=(-i "$VM_IP," -u "$VM_USER" "$SCRIPT_DIR/playbook.yml")
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
