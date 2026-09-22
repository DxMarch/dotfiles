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
    local dest_target
    if dest_target="$(readlink -f "$dest" 2>/dev/null)"; then
      :
    else
      dest_target="$(readlink "$dest")"
      if [[ "$dest_target" != /* ]]; then
        dest_target="$(cd "$(dirname "$dest")" && pwd -P)/$dest_target"
      fi
    fi

    if [[ "$dest_target" != "$src_abs" ]]; then
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

######################################
# Basic utilities and useful programs
######################################

# Select the platform-specific package manager and command/package mapping.
# Indexed arrays keep this compatible with macOS's default Bash 3.2.
case "$(uname -s)" in
  Linux)
    PACKAGE_MANAGER="apt-get"
    REQUIRED_COMMANDS=(git curl zsh tmux htop fdfind)
    REQUIRED_PACKAGES=(git curl zsh tmux htop fd-find)
    ;;
  Darwin)
    PACKAGE_MANAGER="brew"
    REQUIRED_COMMANDS=(git curl zsh tmux htop fd)
    REQUIRED_PACKAGES=(git curl zsh tmux htop fd)
    ;;
  *)
    echo "Error: unsupported operating system: $(uname -s)"
    exit 1
    ;;
esac

if [[ "${SKIP_PACKAGE_INSTALL:-}" = "1" ]]; then
  echo "Skipping package installs because SKIP_PACKAGE_INSTALL=1"
elif ! command -v "$PACKAGE_MANAGER" >/dev/null 2>&1; then
  echo "Error: $PACKAGE_MANAGER not found. Install it or set SKIP_PACKAGE_INSTALL=1 to skip installs."
  exit 1
else
  pkgs_to_install=()
  for index in "${!REQUIRED_COMMANDS[@]}"; do
    if ! command -v "${REQUIRED_COMMANDS[$index]}" >/dev/null 2>&1; then
      pkgs_to_install+=("${REQUIRED_PACKAGES[$index]}")
    fi
  done

  if [[ ${#pkgs_to_install[@]} -gt 0 ]]; then
    if [[ "$PACKAGE_MANAGER" = "apt-get" ]]; then
      echo "Updating apt cache"
      sudo apt-get update -y
      echo "Installing packages: ${pkgs_to_install[*]}"
      sudo apt-get install -y "${pkgs_to_install[@]}"
    else
      echo "Installing packages: ${pkgs_to_install[*]}"
      brew install "${pkgs_to_install[@]}"
    fi
  else
    echo "All required commands present"
  fi
fi

#################################
# Zsh install and setup
#################################

echo "Using DOTFILES_DIR=$DOTFILES_DIR"

# Link dotfiles from the repo (attempt linking unconditionally)
link "$DOTFILES_DIR/zsh/zshrc" "$HOME/.zshrc"
link "$DOTFILES_DIR/zsh/p10k.zsh" "$HOME/.p10k.zsh"
link "$DOTFILES_DIR/gitconfig" "$HOME/.gitconfig"

# Prompt user to make zsh the default login shell
# Only prompt if current shell isn't already zsh or if SHELL doesn't match zsh path
if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    if command -v chsh >/dev/null 2>&1; then
      read -r -p "Make zsh your default shell? [y/N] " _ans
      case "$_ans" in
        [Yy]|[Yy][Ee][Ss])
          echo "Changing default shell to zsh for $USER..."
          # Try generic chsh first, fall back to sudo if needed
          if ! chsh -s "$(command -v zsh)" "$USER"; then
            echo "Standard chsh failed; attempting with sudo..."
            sudo chsh -s "$(command -v zsh)" "$USER"
          fi
          ;;
        *) echo "Skipping shell change." ;;
      esac
    else
      echo "Warning: 'chsh' not found; cannot change default shell automatically."
    fi
else
  echo "zsh is already the default shell."
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

# fzf is optional — clone it and install its shell integration without editing ~/.zshrc
if [[ -d "$HOME/.fzf" ]]; then
  echo "fzf already cloned"
else
  clone_github_repo junegunn/fzf "$HOME/.fzf" || true
fi

if [[ -x "$HOME/.fzf/install" && ! -e "$HOME/.fzf.zsh" ]]; then
  echo "Installing fzf shell integration"
  "$HOME/.fzf/install" --all --no-update-rc
fi

if [[ ! -e "$HOME/.fzf.zsh" ]]; then
  echo "Warning: fzf shell integration was not installed; run $HOME/.fzf/install --all manually"
fi

echo "Installation steps completed. To apply changes, open a new shell or run: source $HOME/.zshrc"

# Ensure user-local zsh file exists (create only if missing)
if [ ! -e "$HOME/.local.zsh" ]; then
  touch "$HOME/.local.zsh"
fi