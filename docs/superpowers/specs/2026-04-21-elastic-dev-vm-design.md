# Elastic Dev VM — Design Spec

**Date:** 2026-04-21  
**Status:** Approved

## Goal

Provide a fully automated script that creates a macOS 15 Sequoia VM (via Tart) configured for interactive development on four Elastic projects, with host repo directories mounted into the VM.

## Repositories

| Repo | Language | Key deps |
|------|----------|----------|
| elastic/go-elasticsearch | Go | Docker |
| elastic/elasticsearch-specification | Node.js | GNU coreutils |
| elastic/elastic-client-generator-go | Go + Node.js | goimports, golangci-lint |
| elastic/cli | TypeScript/Node.js | pre-commit, Docker |

## VM Specifications

| Resource | Value |
|----------|-------|
| Base image | `ghcr.io/cirruslabs/macos-sequoia-base:latest` |
| VM name | `elastic-dev` |
| CPUs | 12 |
| RAM | 24 GB |
| Disk | 200 GB |
| macOS version | 15 Sequoia |

## File Structure

```
elastic-vm/
├── setup-vm.sh      # One-time: creates & provisions the VM
├── start-vm.sh      # Daily driver: mounts host dirs + opens GUI
└── vm-mounts.conf   # Host paths to mount (name=path, one per line)
```

### `vm-mounts.conf` format

```
your-repo=/absolute/path/to/your-repo



```

Inside the VM, each mount is accessible at `/Volumes/My Shared Files/<name>`.

## `setup-vm.sh` — One-time provisioning

Idempotent where possible: skips steps already done (e.g. won't re-clone if VM named `elastic-dev` already exists).

### Phase 1 — VM creation

1. Pull base image: `tart pull ghcr.io/cirruslabs/macos-sequoia-base:latest`
2. Clone to named VM: `tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest elastic-dev`
3. Configure resources: `tart set elastic-dev --cpu 12 --memory 24576 --disk-size 200`

### Phase 2 — Headless provisioning

1. Boot without graphics: `tart run --no-graphics elastic-dev &`
2. Poll until SSH is available (max 5 min, check every 5s)
3. Copy and execute remote provisioning script over SSH that installs:
   - Xcode Command Line Tools (`xcode-select --install`)
   - Homebrew (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
   - Go 1.25+ (`brew install go`)
   - nvm (`curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash`)
   - Node.js 24 (`nvm install 24 && nvm alias default 24`)
   - `goimports` (`go install golang.org/x/tools/cmd/goimports@latest`)
   - `golangci-lint` (`brew install golangci-lint`)
   - `pre-commit` (`brew install pre-commit`)
   - GNU coreutils (`brew install coreutils`)
   - Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)
4. Graceful shutdown: `tart stop elastic-dev`

### SSH credentials

The Cirrus Labs base image ships with a default user `admin` / password `admin`. The provisioning script SSHes as this user. After setup, the user should change the password interactively on first GUI login.

## `start-vm.sh` — Daily use

1. Reads `vm-mounts.conf` from the same directory as the script
2. Parses each `name=path` line and converts to Tart's `name:path` format for `--dir` flags
3. Launches VM with GUI: `tart run elastic-dev --dir "name:path" ...`
4. Prints a mount reference table so the user knows where each repo lives inside the VM

Example output:
```
Starting elastic-dev...
Mounts:
  go-elasticsearch  →  /Volumes/My Shared Files/go-elasticsearch
  cli               →  /Volumes/My Shared Files/cli
  ...
```

## Dependencies (host machine)

- Tart (`brew install cirruslabs/cli/tart`)
- `gh` CLI (for cloning private repos, already authenticated)
- macOS 13+ with Apple Silicon or Intel with Virtualization support

## Out of Scope

- Claude Code authentication (user handles manually on first launch)
- Cloning repos on the host (user's repos are already checked out at scattered paths)
- Automated VM updates / re-provisioning
