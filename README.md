# dotfiles

Minimal, modular dotfiles for Ubuntu / WSL-style environments.

**Quick start**
- Clone to `~/dotfiles` (recommended):
```bash
git clone git@github.com:dxmarch/dotfiles.git ~/dotfiles
cd ~/dotfiles
```
- Run the installer (non-interactive where possible):
```bash
bash install.sh
```

**What the installer does**
- Installs `zsh` (via `apt`) if missing.
- Installs Oh My Zsh non-interactively.
- Clones `powerlevel10k`, common zsh plugins, and `fzf` (does not run interactive installers).

**Configuration**
- `ZSH_CUSTOM` can be set to change the Oh My Zsh custom path.

**Notes & tips**
- The script is idempotent: it backs up existing files (timestamped `.bak`), and avoids re-cloning git repos.
- To finish `fzf` setup manually (optional):
```bash
~/.fzf/install --all
```
