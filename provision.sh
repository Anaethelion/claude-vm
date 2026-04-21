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

# ── Ghostty ───────────────────────────────────────────────────────────────────
if ! brew list --cask ghostty &>/dev/null 2>&1; then
  log "Installing Ghostty..."
  brew install --cask ghostty
  sudo xattr -rd com.apple.quarantine /Applications/Ghostty.app 2>/dev/null || true
fi
log "Ghostty: installed"

# ── Register apps with Launch Services ───────────────────────────────────────
log "Registering apps with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -v /Applications/ 2>/dev/null || true

# ── Summary ──────────────────────────────────────────────────────────────────
log ""
log "Provisioning complete. Summary:"
log "  Go:            $(go version)"
log "  Node.js:       $(node --version)"
log "  npm:           $(npm --version)"
log "  golangci-lint: $(golangci-lint --version 2>&1 | head -1)"
log "  pre-commit:    $(pre-commit --version)"
log "  Ghostty:       installed"
log ""
log "PATH additions written to ~/.zprofile (take effect on next login)."
