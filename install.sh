#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/towelbro0812/dotfiles.git"
BRANCH="main"
TRACKED_PATHS=(.config/nvim .config/starship.toml .config/herdr/config.toml install.sh .gitignore README.md)

LOCAL_BIN="$HOME/.local/bin"
NVIM_MIN_VERSION="0.10.0"
mkdir -p "$LOCAL_BIN"

BACKED_UP=()

log() { printf '\033[1;34m✦ %s\033[0m\n' "$1"; }
ok() { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }
err() { printf '\033[1;31m✕ %s\033[0m\n' "$1" >&2; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1" >&2; }

OS="$(uname -s)"
if [ "$OS" != "Linux" ]; then
  err "Only Linux is supported, detected: $OS"
  exit 1
fi

ARCH="$(uname -m)"

version_ge() {
  [ "$1" = "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" ]
}

install_system_deps() {
  # git/curl/ca-certificates: needed to bootstrap this script and deploy the dotfiles
  # build-essential: nvim-treesitter needs a C compiler to build parsers
  # ripgrep/fd-find: LazyVim's search/explorer plugins (snacks.nvim, grug-far.nvim) need these
  local missing=()
  command -v git >/dev/null 2>&1 || missing+=(git)
  command -v curl >/dev/null 2>&1 || missing+=(curl ca-certificates)
  command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || missing+=(build-essential)
  command -v rg >/dev/null 2>&1 || missing+=(ripgrep)
  command -v fdfind >/dev/null 2>&1 || missing+=(fd-find)

  if [ ${#missing[@]} -eq 0 ]; then
    ok "system dependencies already installed, skipping"
  else
    log "Installing system dependencies: ${missing[*]}..."
    sudo apt update && sudo apt install -y "${missing[@]}"
  fi

  # Ubuntu's fd-find package ships the binary as `fdfind`, not `fd`
  if command -v fdfind >/dev/null 2>&1 && [ ! -e "$LOCAL_BIN/fd" ]; then
    ln -sfn "$(command -v fdfind)" "$LOCAL_BIN/fd"
  fi
}

deploy_dotfiles() {
  cd "$HOME"

  if [ -d .git ]; then
    ok "dotfiles repo already set up, pulling latest"
    git pull origin "$BRANCH"
    return
  fi

  log "Deploying dotfiles to \$HOME..."
  git init -q
  git remote add origin "$REPO_URL"
  git fetch origin

  for p in "${TRACKED_PATHS[@]}"; do
    if [ -e "$p" ] && [ ! -L "$p" ]; then
      local backup="$p.bak.$(date +%s)"
      mv "$p" "$backup"
      BACKED_UP+=("$backup")
      warn "Backed up existing: $p -> $backup"
    fi
  done

  git checkout -b "$BRANCH" --track "origin/$BRANCH"
}

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    ok "uv already installed, skipping"
    return
  fi
  log "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
}

install_nvim() {
  local current_version=""
  if command -v nvim >/dev/null 2>&1; then
    current_version="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  fi

  if [ -n "$current_version" ] && version_ge "$current_version" "$NVIM_MIN_VERSION" && [ -L "$LOCAL_BIN/nvim" ]; then
    ok "nvim $current_version already meets the requirement, skipping"
    return
  fi

  log "Installing nvim..."
  local asset
  case "$ARCH" in
  x86_64) asset="nvim-linux-x86_64.tar.gz" ;;
  aarch64) asset="nvim-linux-arm64.tar.gz" ;;
  *)
    err "Unsupported architecture: $ARCH, please install nvim manually"
    return 1
    ;;
  esac

  local dest="$HOME/.local/opt/nvim"
  rm -rf "$dest"
  mkdir -p "$dest"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$asset" | tar -xz -C "$dest" --strip-components=1
  ln -sfn "$dest/bin/nvim" "$LOCAL_BIN/nvim"
}

install_starship() {
  if command -v starship >/dev/null 2>&1; then
    ok "starship already installed, skipping"
  else
    log "Installing starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir "$LOCAL_BIN" -y
  fi

  if ! grep -q 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
    echo 'eval "$(starship init bash)"' >>"$HOME/.bashrc"
    ok "Added starship init to ~/.bashrc"
  fi
}

install_herdr() {
  if command -v herdr >/dev/null 2>&1; then
    ok "herdr already installed, skipping"
    return
  fi
  log "Installing herdr..."
  curl -fsSL https://herdr.dev/install.sh | sh
}

install_lazygit() {
  if command -v lazygit >/dev/null 2>&1; then
    ok "lazygit already installed, skipping"
    return
  fi

  local asset
  case "$ARCH" in
  x86_64) asset="linux_x86_64" ;;
  aarch64) asset="linux_arm64" ;;
  *)
    err "Unsupported architecture: $ARCH, please install lazygit manually"
    return 1
    ;;
  esac

  log "Installing lazygit..."
  local version
  version="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -Po '"tag_name": "v\K[^"]*')"

  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${version}_${asset}.tar.gz" | tar -xz -C "$tmp" lazygit
  install "$tmp/lazygit" "$LOCAL_BIN/lazygit"
  rm -rf "$tmp"
}

install_system_deps

log "Installing toolchain"
install_uv
install_nvim
install_starship
install_herdr
install_lazygit

deploy_dotfiles

case ":$PATH:" in
*":$LOCAL_BIN:"*) ;;
*) warn "Note: $LOCAL_BIN is not in PATH" ;;
esac

if [ ${#BACKED_UP[@]} -gt 0 ]; then
  warn "The following existing files were backed up, not deleted:"
  for b in "${BACKED_UP[@]}"; do
    printf '    %s\n' "$b"
  done
fi

ok "Done!"
