# Ansible Provisioning Design

**Date:** 2026-04-21
**Status:** Approved

## Goal

Replace the bash `provision.sh` script with an Ansible playbook so that provisioning is declarative, idempotent, and diffable. Adding or removing tools becomes a one-line edit to `playbook.yml`, and `--check --diff` shows exactly what would change on the VM without applying it.

## Architecture

### File changes

| File | Change |
|------|--------|
| `provision.sh` | Deleted |
| `playbook.yml` | New — all provisioning tasks |
| `setup-vm.sh` | Updated — copy SSH key, call `ansible-playbook` |
| `requirements.txt` | New — pins `ansible-core` for the project venv |
| `tests/test_setup_vm.bats` | Updated — dry-run output reflects new commands |

### Host prerequisites

```bash
brew install sshpass
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install community.general
```

Ansible runs from a project-local Python venv (`.venv/`) rather than system-wide. `requirements.txt` pins `ansible-core` and any Python deps. `.venv/` is gitignored. `setup-vm.sh` activates the venv automatically before calling `ansible-playbook`.

`sshpass` is still needed for the one-time SSH key copy during setup.

## `setup-vm.sh` changes

Phase 1 (VM creation) is unchanged.

Phase 2 (provisioning) becomes:

1. Boot VM headlessly — unchanged
2. Wait for SSH — unchanged (still uses `sshpass` to probe)
3. **New:** copy host public key into VM with `ssh-copy-id` via `sshpass` — skipped if key is already authorised
4. Run `ansible-playbook -i "$VM_IP," playbook.yml`
5. Stop VM — unchanged

A new `--check` flag passes `--check --diff` to `ansible-playbook`. This works on an already-running VM too, not just during initial setup:

```bash
./setup-vm.sh --check   # diff what would change, no writes
./setup-vm.sh           # apply
```

Dry-run mode (`--dry-run`) continues to print commands without running anything, as before.

## `playbook.yml` structure

Single flat playbook, all tasks targeting `all` hosts as `admin` user. Tasks in order:

### 1. Homebrew
- Shell task: install Homebrew if `brew` not in PATH (`NONINTERACTIVE=1`)
- Lineinfile: persist `eval "$(/opt/homebrew/bin/brew shellenv)"` in `~/.zprofile`

### 2. Brew formulae
- `community.general.homebrew` task with `state: present` and package list:
  - `go`
  - `golangci-lint`
  - `pre-commit`
  - `coreutils`
  - `gh`

### 3. Brew casks
- `community.general.homebrew_cask` task: `ghostty` with `state: present`
- Shell task: `xattr -rd com.apple.quarantine /Applications/Ghostty.app`
- Shell task: `lsregister /Applications/` to register apps with Launch Services

### 4. nvm + Node.js 24
- Shell task: install nvm via curl if `~/.nvm` missing
- Lineinfile: persist nvm init in `~/.zprofile`
- Shell task: `nvm install 24 && nvm alias default 24`, guarded by `nvm ls 24`

### 5. Go PATH
- Lineinfile: persist `export PATH="$HOME/go/bin:$PATH"` in `~/.zprofile`

### 6. goimports
- Shell task: `go install golang.org/x/tools/cmd/goimports@latest`, guarded by `command -v goimports`

### 7. Claude Code
- Shell task: `npm install -g @anthropic-ai/claude-code`, guarded by `command -v claude`

## Idempotency and check mode

- All `community.general.homebrew` and `homebrew_cask` tasks are natively idempotent and support `--check --diff`
- Shell tasks that are always safe to re-run use `changed_when: false`
- Shell tasks that are guarded (only run when tool is absent) use `creates:` or a `when:` condition so Ansible tracks their state correctly in check mode

## Testing

- `tests/test_setup_vm.bats` dry-run tests updated to match new `ansible-playbook` output
- Existing `tests/test_start_vm.bats` unchanged

## README updates

Prerequisites section updated to add `ansible` and the `community.general` collection install command.
