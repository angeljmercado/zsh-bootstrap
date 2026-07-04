#!/usr/bin/env bash
# zsh-bootstrap — portable personal zsh environment
# Based on https://github.com/radleylewis/zsh
# Tested on: Ubuntu 24.04+ / Debian 12+
# Usage: bash zsh-bootstrap.sh
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${BOLD}── $* ──${NC}"; }

# ── 1. Install packages ──────────────────────────────────────────────────────
install_packages() {
  step "Install packages"
  if command -v apt &>/dev/null; then
    sudo apt update -q
    sudo apt install -y zsh neovim eza bat fd-find fzf zoxide starship ripgrep lf git curl
  elif command -v pacman &>/dev/null; then
    # On Arch: bat and fd use their canonical names
    sudo pacman -Sy --noconfirm zsh neovim eza bat fd fzf zoxide starship ripgrep lf git curl
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y zsh neovim eza bat fd-find fzf zoxide starship ripgrep lf git curl
  else
    warn "Unknown package manager — install manually: zsh neovim eza bat fd fzf zoxide starship ripgrep lf git curl"
  fi
}

# ── 2. Compatibility symlinks ────────────────────────────────────────────────
# Ubuntu/Debian ship fd as 'fdfind' and bat as 'batcat' to avoid name conflicts.
# The zsh config expects 'fd' and 'bat'.
setup_symlinks() {
  step "Compatibility symlinks"
  mkdir -p "$HOME/.local/bin"
  [[ -f /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"  && info "fd → fdfind"
  [[ -f /usr/bin/batcat  ]] && ln -sf /usr/bin/batcat  "$HOME/.local/bin/bat" && info "bat → batcat"
}

# ── 3. lf icons ──────────────────────────────────────────────────────────────
setup_lf_icons() {
  step "lf icons"
  mkdir -p "$HOME/.config/lf"
  if [[ ! -f "$HOME/.config/lf/icons" ]]; then
    info "Downloading icons..."
    curl -fsSLo "$HOME/.config/lf/icons" \
      https://raw.githubusercontent.com/gokcehan/lf/master/etc/icons.example
  else
    info "Already exists, skipping"
  fi
}

# ── 4. Clone zsh config ───────────────────────────────────────────────────────
clone_config() {
  step "Clone radleylewis/zsh"
  if [[ -d "$HOME/.config/zsh/.git" ]]; then
    info "Repo exists — pulling latest..."
    git -C "$HOME/.config/zsh" pull --ff-only
  else
    git clone https://github.com/radleylewis/zsh.git "$HOME/.config/zsh"
  fi
}

# ── 5. ZDOTDIR ────────────────────────────────────────────────────────────────
# Tells zsh to load its config from ~/.config/zsh instead of ~/.zshrc
setup_zdotdir() {
  step "ZDOTDIR"
  local env_file="/etc/zsh/zshenv"
  sudo mkdir -p "$(dirname "$env_file")"
  sudo touch "$env_file"
  if ! grep -q 'ZDOTDIR' "$env_file" 2>/dev/null; then
    info "Writing to $env_file..."
    sudo tee -a "$env_file" > /dev/null <<'EOF'

# Personal zsh config location
export ZDOTDIR=$HOME/.config/zsh
EOF
  else
    info "Already set"
  fi
}

# ── 6. XDG directories ────────────────────────────────────────────────────────
setup_xdg_dirs() {
  step "XDG state/cache dirs"
  mkdir -p "$HOME/.local/state/zsh"
  mkdir -p "$HOME/.cache/zsh"
}

# ── 7. Personal aliases ───────────────────────────────────────────────────────
write_personal_aliases() {
  step "Personal aliases"
  local target="$HOME/.config/zsh/aliases.personal.zsh"
  cat > "$target" <<'ALIASES'
# Personal aliases — sourced after aliases.zsh
# Entries already in aliases.zsh (eza, bat, rg, nvim, df, vim, cd -) are not repeated.

# PATH
export PATH="$HOME/.local/bin:$PATH"

# direnv (only if installed)
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# ── Navigation ──────────────────────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias '~'='cd ~'

# ── Listing extras ──────────────────────────────────────────────────────────
alias lt='eza -lah --icons --git --sort=modified'   # newest modified first
alias lS='eza -lah --icons --git --sort=size'        # largest first

# ── Safety nets ─────────────────────────────────────────────────────────────
alias cp='cp -iv'       # prompt before overwrite, show what was copied
alias mv='mv -iv'       # prompt before overwrite, show what was moved
alias rm='rm -iv'       # prompt before delete, show what was removed
alias mkdir='mkdir -pv' # create parent dirs, show what was created

# ── System info ─────────────────────────────────────────────────────────────
alias du='du -h'
alias free='free -h'
alias ports='ss -tulanp'

# ── Network ─────────────────────────────────────────────────────────────────
alias ip='ip -c'
alias ping='ping -c 5'

# ── Grep extras ─────────────────────────────────────────────────────────────
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# ── Convenience ─────────────────────────────────────────────────────────────
alias c='clear'
alias h='history'
alias reload='exec zsh'
alias path='echo $PATH | tr ":" "\n"'
ALIASES
  info "Written: $target"
}

# ── 8. Starship theme ─────────────────────────────────────────────────────────
# Overwrites the default shipped by radleylewis/zsh with the personal theme.
copy_starship_theme() {
  step "Starship theme"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cp "$script_dir/starship.toml" "$HOME/.config/zsh/starship.toml"
  info "Copied starship.toml"
}

# ── 10. Hook personal aliases into .zshrc ────────────────────────────────────
patch_zshrc() {
  step "Patch .zshrc"
  local zshrc="$HOME/.config/zsh/.zshrc"
  if ! grep -q "aliases.personal.zsh" "$zshrc"; then
    printf '\n# Personal aliases\nsource "$ZDOTDIR/aliases.personal.zsh"\n' >> "$zshrc"
    info "Patched $zshrc"
  else
    info "Already patched"
  fi
}

# ── 11. Default shell ─────────────────────────────────────────────────────────
set_default_shell() {
  step "Default shell"
  local zsh_path
  zsh_path=$(command -v zsh)
  if [[ "$SHELL" != "$zsh_path" ]]; then
    # Ensure zsh is in /etc/shells
    if ! grep -qx "$zsh_path" /etc/shells; then
      echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
    fi
    chsh -s "$zsh_path"
    warn "Log out and back in for the shell change to take effect"
  else
    info "Already using $zsh_path"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}zsh-bootstrap${NC}"
  install_packages
  setup_symlinks
  setup_lf_icons
  clone_config
  setup_zdotdir
  setup_xdg_dirs
  write_personal_aliases
  copy_starship_theme
  patch_zshrc
  set_default_shell

  echo -e "\n${GREEN}Done.${NC}"
  echo "  Launch zsh — plugins auto-install on first run."
  echo "  Verify: bat --version && fd --version && fzf --version && zoxide --version && starship --version"
}

main "$@"
