#!/usr/bin/env bash
set -euo pipefail

#################################
# Configuration
#################################
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

#################################
# Helper Functions
#################################
now_ts() { date +%s; }

link() {
  local src="$1"
  local dest="$2"

  # Resolve to absolute paths for comparison
  local src_abs dest_abs
  src_abs="$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")"
  dest_abs="$(readlink -f "$dest" 2>/dev/null || printf '%s' "$dest")"

  # If dest exists and is not a symlink to src, backup
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    local backup="${dest}.$(now_ts).bak"
    echo "Backing up $dest → $backup"
    mv "$dest" "$backup"
  fi

  # If destination is a symlink pointing elsewhere, replace it
  if [[ -L "$dest" ]]; then
    if [[ "$(readlink -f "$dest")" != "$src_abs" ]]; then
      echo "Replacing symlink $dest → $src_abs"
      rm -f "$dest"
    else
      echo "Symlink $dest already points to $src_abs"
      return 0
    fi
  fi

  # Ensure parent directory exists
  mkdir -p "$(dirname "$dest")"

  ln -sfn "$src_abs" "$dest"
  echo "Linked $dest → $src_abs"
}

# Generic GitHub repo clone function (idempotent)
clone_github_repo() {
    local repo="$1"       # e.g., zsh-users/zsh-autosuggestions
    local dest="$2"       # full destination path

    if [[ -d "$dest/.git" ]]; then
        echo "✔ Repo already exists at $dest"
        return 0
    fi

    if [[ -e "$dest" ]]; then
        echo "⚠ $dest exists but is not a git repo, skipping"
        return 1
    fi

    echo "→ Cloning https://github.com/$repo.git → $dest"
    git clone "https://github.com/$repo.git" "$dest"
}

ensure_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing command: $cmd"
    return 1
  fi
}

#################################
# Zsh install and setup
#################################

echo "Using DOTFILES_DIR=$DOTFILES_DIR"

# Link dotfiles from the repo (attempt linking unconditionally)
link "$DOTFILES_DIR/zsh/zshrc" "$HOME/.zshrc"
link "$DOTFILES_DIR/zsh/p10k.zsh" "$HOME/.p10k.zsh"
link "$DOTFILES_DIR/gitconfig" "$HOME/.gitconfig"

# Ensure basic system commands are available (or install via apt)
if command -v apt-get >/dev/null 2>&1; then
  echo "Updating apt cache and ensuring prerequisites (git, curl) are installed"
  sudo apt-get update -y
  sudo apt-get install -y git curl
else
  echo "apt-get not available; please ensure git and curl are installed before running this script"
fi

# Install zsh if missing
if ! command -v zsh >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing zsh"
    sudo apt-get install -y zsh
  else
    echo "zsh not found and apt-get unavailable; please install zsh manually"
  fi
else
  echo "zsh already installed"
fi

# Install Oh My Zsh if missing (non-interactive: don't auto-run zsh or chsh)
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  echo "Oh My Zsh already installed"
else
  echo "Installing Oh My Zsh (non-interactive)"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# powerlevel10k theme
clone_github_repo romkatv/powerlevel10k "$ZSH_CUSTOM/themes/powerlevel10k" || true

# Clone zsh plugins
PLUGINS_DIR="$ZSH_CUSTOM/plugins"
mkdir -p "$PLUGINS_DIR"

install_omz_plugin() {
    local github_repo="$1"      # e.g., zsh-users/zsh-autosuggestions
    local plugin_name="$2"      # directory name under plugins/

    clone_github_repo "$github_repo" "$PLUGINS_DIR/$plugin_name" || true
}

install_omz_plugin zsh-users/zsh-autosuggestions zsh-autosuggestions
install_omz_plugin zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting
install_omz_plugin zsh-users/zsh-history-substring-search zsh-history-substring-search

# fzf is optional — clone but do not run interactive installer automatically
if [[ -d "$HOME/.fzf" ]]; then
  echo "fzf already cloned"
else
  clone_github_repo junegunn/fzf "$HOME/.fzf" || true
  echo "To finish fzf setup, run: $HOME/.fzf/install (you can pass --all for non-interactive install)"
fi

echo "Installation steps completed. To apply changes, open a new shell or run: source $HOME/.zshrc"