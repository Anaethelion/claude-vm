# claude-vm

Scripts to create and launch a macOS 15 Sequoia [Tart](https://github.com/cirruslabs/tart) VM pre-loaded with Elastic Go project dev dependencies, with host repo directories mounted inside.

## How it works

| Script | Role |
|--------|------|
| `setup-vm.sh` | One-time: creates the VM and provisions it headlessly via SSH |
| `provision.sh` | Runs inside the VM during setup; installs all dev deps |
| `start-vm.sh` | Daily driver: reads `vm-mounts.conf`, mounts host dirs, opens the VM GUI |

Installed inside the VM: Homebrew, Go (latest), Node.js 24 (via nvm), goimports, golangci-lint, pre-commit, GNU coreutils, Claude Code CLI.

Host repos are mounted read-write at `/Volumes/My Shared Files/<name>` inside the VM.

## Prerequisites

```bash
brew install cirruslabs/cli/tart
brew install sshpass
brew install bats-core   # only needed to run tests
```

## First-time setup

```bash
./setup-vm.sh
```

This pulls the base macOS Sequoia image (~10 GB), clones it as `elastic-dev`, configures it with 12 vCPUs / 24 GB RAM / 200 GB disk, boots it headlessly, runs `provision.sh` over SSH (~10 min), then shuts it down.

The default VM credentials are `admin` / `admin` — change the password on first login.

Use `--dry-run` to preview what would run without touching anything:

```bash
./setup-vm.sh --dry-run
```

## Configure mounts

```bash
cp vm-mounts.conf.example vm-mounts.conf
```

Edit `vm-mounts.conf` with your actual repo paths:

```
go-elasticsearch=/Users/you/go-elasticsearch
elasticsearch-specification=/Users/you/elasticsearch-specification
elastic-client-generator-go=/Users/you/elastic-client-generator-go
cli=/Users/you/elastic-cli
```

`vm-mounts.conf` is gitignored — only the example is tracked.

## Daily use

```bash
./start-vm.sh
```

This reads `vm-mounts.conf`, prints a mount table, and launches the VM GUI with all directories mounted. Preview without launching:

```bash
./start-vm.sh --dry-run
```

Inside the VM, mounted repos are at `/Volumes/My Shared Files/<name>`.

## Running tests

```bash
bats tests/
```

14 tests covering `setup-vm.sh` and `start-vm.sh` dry-run behaviour.
