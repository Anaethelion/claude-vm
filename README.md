# claude-vm

Scripts to create and launch a macOS 15 Sequoia [Tart](https://github.com/cirruslabs/tart) VM pre-loaded with Elastic Go project dev dependencies, with host repo directories mounted inside.

## How it works

| File | Role |
|------|------|
| `setup-vm.sh` | One-time: creates the VM and provisions it headlessly via SSH |
| `playbook.yml` | Ansible playbook; runs inside the VM via SSH to install all dev deps |
| `start-vm.sh` | Daily driver: reads `vm-mounts.conf`, mounts host dirs, opens the VM GUI |
| `Makefile` | Convenience wrapper — run `make` to see all available commands |

Installed inside the VM: Homebrew, Go, golangci-lint, goimports, pre-commit, GNU coreutils, gh, Node.js 24 (via nvm), Ghostty, Claude Desktop.

Host repos are mounted read-write at `/Volumes/My Shared Files/<name>` inside the VM.

## Prerequisites

```bash
brew install cirruslabs/cli/tart
brew install sshpass
```

`bats-core` is only needed to run the test suite:

```bash
brew install bats-core
```

### macOS Local Network permission

On macOS Sonoma and later, the terminal you run `setup-vm.sh` from needs
**Local Network** permission to reach the VM on `192.168.64.0/24`. Without
it, `ping` and `ssh` to the VM fail silently with `No route to host` even
though the VM is booted and has a DHCP lease.

Grant it in **System Settings → Privacy & Security → Local Network**, toggle
your terminal (Terminal.app, iTerm2, Ghostty, etc.) on, then fully quit and
relaunch the terminal before retrying.

### Python version

The Ansible venv uses `python3` by default. Override with the `PYTHON`
variable if you need a specific interpreter:

```bash
make setup PYTHON=python3.12
```

## First-time setup

```bash
make setup
```

This sets up the Ansible venv, pulls the base macOS Sequoia image (~10 GB), clones it as `elastic-dev`, configures it with 12 vCPUs / 24 GB RAM / 200 GB disk, boots it headlessly, copies your SSH key into the VM, runs the Ansible playbook (~10 min), then shuts it down.

The default VM credentials are `admin` / `admin` — change the password on first login.

Use `--dry-run` to preview what would run without touching anything:

```bash
./setup-vm.sh --dry-run
```

Use `make check` to diff what Ansible would change against an already-provisioned VM (no writes):

```bash
make check
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
make start
```

This reads `vm-mounts.conf`, prints a mount table, and launches the VM GUI with all directories mounted. Preview without launching:

```bash
./start-vm.sh --dry-run
```

Inside the VM, mounted repos are at `/Volumes/My Shared Files/<name>`.

## Running tests

```bash
make test
```

16 tests covering `setup-vm.sh` and `start-vm.sh` dry-run behaviour.
