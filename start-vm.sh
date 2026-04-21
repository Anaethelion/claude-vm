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
