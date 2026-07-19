#!/usr/bin/env bash
# Portable personal Zsh environment for supported Ubuntu and RHEL-family releases.
# Run as a normal user: bash zsh-bootstrap.sh
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info() { printf '%b[+]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*"; }
die()  { printf '%b[x]%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
step() { printf '\n%b-- %s --%b\n' "$BOLD" "$*" "$NC"; }

readonly SYSTEM_PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
readonly CONFIG_REPO='https://github.com/radleylewis/zsh.git'
readonly CONFIG_COMMIT='2edf9f4c271ae1bee91e6e4e30db5ce580810d27'
readonly ICONS_URL='https://raw.githubusercontent.com/gokcehan/lf/r41/etc/icons.example'
readonly ICONS_SHA256='734a2b0d03b885e761fb168dae8bc2d207a1e62ab62be7be3d920be5a6f19c89'

INSTALL_ROOT=false
WORK_DIR=''
CONFIG_TEMPLATE=''
ICONS_FILE=''
OS_ID=''
OS_MAJOR=''
PACKAGE_MANAGER=''
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
declare -a BACKUPS=() ROLLBACKS=()

cleanup() {
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

system_has() { PATH="$SYSTEM_PATH" command -v "$1" &>/dev/null; }

run_for() {
  local target=$1
  shift
  if [[ "$target" == root ]]; then
    sudo -H "$@"
  else
    "$@"
  fi
}

preflight() {
  step "Preflight"
  (( EUID != 0 )) || die "Do not run this script with sudo. Run: bash zsh-bootstrap.sh"
  [[ $(uname -m) == x86_64 ]] || die "Unsupported architecture: $(uname -m) (supported: x86_64)"
  [[ -r /etc/os-release ]] || die "Cannot identify this Linux distribution"

  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID=${ID,,}
  case "$OS_ID" in
    ubuntu)
      [[ "$VERSION_ID" == 24.04 || "$VERSION_ID" == 26.04 ]] ||
        die "Unsupported Ubuntu release: $VERSION_ID (supported: 24.04 and 26.04 LTS)"
      OS_MAJOR=${VERSION_ID%%.*}
      PACKAGE_MANAGER=apt
      ;;
    rhel|ol|almalinux)
      OS_MAJOR=${VERSION_ID%%.*}
      [[ "$OS_MAJOR" == 9 || "$OS_MAJOR" == 10 ]] ||
        die "Unsupported $ID release: $VERSION_ID (supported major versions: 9 and 10)"
      PACKAGE_MANAGER=dnf
      ;;
    *) die "Unsupported distribution: $ID" ;;
  esac

  command -v sudo &>/dev/null || die "sudo is required"
  info "Detected: ${PRETTY_NAME:-$ID $VERSION_ID} / x86_64"
  info "Verifying sudo access..."
  sudo -v || die "The invoking user needs sudo access"

  if [[ -t 0 ]]; then
    read -r -p "Configure root with the same Zsh environment? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] && INSTALL_ROOT=true
  fi
}

install_package() {
  local command_name=$1 package_name=$2 alternate=${3:-}
  system_has "$command_name" && return 0

  info "Installing $package_name..."
  if [[ "$PACKAGE_MANAGER" == apt ]]; then
    sudo apt-get install -y "$package_name" || true
  else
    sudo dnf install -y "$package_name" || true
  fi

  if [[ -n "$alternate" ]] && system_has "$alternate" && ! system_has "$command_name"; then
    sudo ln -sfn "$(PATH="$SYSTEM_PATH" command -v "$alternate")" "/usr/local/bin/$command_name"
  fi
  system_has "$command_name" && return 0
  install_fallback "$command_name"
}

install_fallback() {
  local command_name=$1 url='' sha256='' archive binary target
  case "$command_name" in
    eza)
      url='https://github.com/eza-community/eza/releases/download/v0.23.5/eza_x86_64-unknown-linux-musl.tar.gz'
      sha256='e06eebab74b73d6b7d51a796a353824b001bea82df077706382e100815d28904'
      ;;
    bat)
      url='https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-x86_64-unknown-linux-musl.tar.gz'
      sha256='0dcd8ac79732c0d5b136f11f4ee00e581440e16a44eab5b3105b611bbf2cf191'
      ;;
    fd)
      url='https://github.com/sharkdp/fd/releases/download/v10.4.2/fd-v10.4.2-x86_64-unknown-linux-musl.tar.gz'
      sha256='e3257d48e29a6be965187dbd24ce9af564e0fe67b3e73c9bdcd180f4ec11bdde'
      ;;
    fzf)
      url='https://github.com/junegunn/fzf/releases/download/v0.74.1/fzf-0.74.1-linux_amd64.tar.gz'
      sha256='df53438be5f51e151bb4044d78fda72bdfe209e3ecd2baecae48e8dea370c81b'
      ;;
    zoxide)
      url='https://github.com/ajeetdsouza/zoxide/releases/download/v0.10.0/zoxide-0.10.0-x86_64-unknown-linux-musl.tar.gz'
      sha256='2d93385b99f3e82cf2701609a1bffcad863fbeb75aa3fe7eb6be4d29be68b1ae'
      ;;
    starship)
      url='https://github.com/starship/starship/releases/download/v1.26.0/starship-x86_64-unknown-linux-musl.tar.gz'
      sha256='b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3'
      ;;
    rg)
      url='https://github.com/BurntSushi/ripgrep/releases/download/15.2.0/ripgrep-15.2.0-x86_64-unknown-linux-musl.tar.gz'
      sha256='33e15bcf1624b25cdd2a55813a47a2f95dbe126268203e76aa6a585d1e7b149c'
      ;;
    lf)
      url='https://github.com/gokcehan/lf/releases/download/r41/lf-linux-amd64.tar.gz'
      sha256='c7c4237b5d8618a13bbe01592859d89d6de0f460f8483b8e47c0f8c416203275'
      ;;
    nvim)
      url='https://github.com/neovim/neovim/releases/download/v0.12.4/nvim-linux-x86_64.tar.gz'
      sha256='012bf3fcac5ade43914df3f174668bf64d05e049a4f032a388c027b1ebd78628'
      ;;
    *) die "Required command '$command_name' is unavailable from configured repositories" ;;
  esac

  warn "$command_name is unavailable as a distro package; using the pinned official binary"
  archive="$WORK_DIR/${command_name}.tar.gz"
  curl --proto '=https' --tlsv1.2 -fL --retry 3 -o "$archive" "$url"
  printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c - >/dev/null ||
    die "Checksum verification failed for $command_name"

  if [[ "$command_name" == nvim ]]; then
    target='/opt/zsh-bootstrap/nvim-v0.12.4'
    sudo mkdir -p "$target"
    sudo tar -xzf "$archive" -C "$target" --strip-components=1
    sudo ln -sfn "$target/bin/nvim" /usr/local/bin/nvim
  else
    local extract_dir="$WORK_DIR/${command_name}-extract"
    mkdir -p "$extract_dir"
    tar -xzf "$archive" -C "$extract_dir"
    binary=$(find "$extract_dir" -type f -name "$command_name" -print -quit)
    [[ -n "$binary" ]] || die "The $command_name archive did not contain the expected executable"
    sudo install -m 0755 "$binary" "/usr/local/bin/$command_name"
  fi
  system_has "$command_name" || die "Fallback installation failed for $command_name"
}

setup_rhel_repositories() {
  [[ "$PACKAGE_MANAGER" == dnf ]] || return 0
  step "RHEL-family repositories"
  sudo dnf install -y dnf-plugins-core || warn "Could not install dnf-plugins-core"

  case "$OS_ID" in
    almalinux)
      sudo dnf config-manager --set-enabled crb || warn "Could not enable CRB"
      ;;
    ol)
      sudo dnf config-manager --enable "ol${OS_MAJOR}_codeready_builder" ||
        warn "Could not enable Oracle Linux CodeReady Builder"
      ;;
    rhel)
      if command -v subscription-manager &>/dev/null; then
        sudo subscription-manager repos \
          --enable "codeready-builder-for-rhel-${OS_MAJOR}-$(uname -m)-rpms" ||
          warn "Could not enable RHEL CodeReady Builder"
      else
        warn "subscription-manager is unavailable; CodeReady Builder was not enabled"
      fi
      ;;
  esac

  sudo dnf install -y \
    "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_MAJOR}.noarch.rpm" ||
    warn "Could not enable EPEL; missing tools will use verified upstream binaries"
}

install_packages() {
  step "Required tools"
  if [[ "$PACKAGE_MANAGER" == apt ]]; then
    sudo apt-get update -q
  else
    sudo dnf makecache -y
  fi

  # Install these first because the remaining setup depends on them.
  install_package zsh zsh
  install_package git git
  install_package curl curl
  if ! command -v tar &>/dev/null || ! command -v sha256sum &>/dev/null; then
    die "tar and sha256sum are required"
  fi

  setup_rhel_repositories
  install_package nvim neovim
  install_package eza eza
  install_package bat bat batcat
  install_package fd fd-find fdfind
  install_package fzf fzf
  install_package zoxide zoxide
  install_package starship starship
  install_package rg ripgrep
  install_package lf lf
}

prepare_template() {
  step "Pinned Zsh configuration"
  CONFIG_TEMPLATE="$WORK_DIR/zsh-template"
  git clone -q "$CONFIG_REPO" "$CONFIG_TEMPLATE"
  git -C "$CONFIG_TEMPLATE" checkout -q --detach "$CONFIG_COMMIT"
  [[ $(git -C "$CONFIG_TEMPLATE" rev-parse HEAD) == "$CONFIG_COMMIT" ]] ||
    die "Could not select the pinned Zsh configuration"

  local repo name commit plugin_dir
  while IFS='|' read -r repo name commit; do
    plugin_dir="$CONFIG_TEMPLATE/plugins/$name"
    git clone -q "https://github.com/$repo.git" "$plugin_dir"
    git -C "$plugin_dir" checkout -q -b bootstrap-pinned "$commit"
    git -C "$plugin_dir" branch -q --set-upstream-to=origin/master bootstrap-pinned
  done <<'EOF'
zsh-users/zsh-autosuggestions|zsh-autosuggestions|85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5
zsh-users/zsh-history-substring-search|zsh-history-substring-search|14c8d2e0ffaee98f2df9850b19944f32546fdea5
jeffreytse/zsh-vi-mode|zsh-vi-mode|91cafe4a09b6670cb8e761aa413e5f7b9e00816f
zdharma-continuum/fast-syntax-highlighting|fast-syntax-highlighting|3d574ccf48804b10dca52625df13da5edae7f553
EOF

  cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/starship.toml" \
    "$CONFIG_TEMPLATE/starship.toml"
  write_personal_config

  ICONS_FILE="$WORK_DIR/lf-icons"
  curl --proto '=https' --tlsv1.2 -fL --retry 3 -o "$ICONS_FILE" "$ICONS_URL"
  printf '%s  %s\n' "$ICONS_SHA256" "$ICONS_FILE" | sha256sum -c - >/dev/null ||
    die "Checksum verification failed for lf icons"
}

write_personal_config() {
  cat > "$CONFIG_TEMPLATE/aliases.personal.zsh" <<'EOF'
# Managed by zsh-bootstrap; the previous configuration is backed up on every run.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias '~'='cd ~'
alias lt='eza -lah --icons --git --sort=modified'
alias lS='eza -lah --icons --git --sort=size'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias mkdir='mkdir -pv'
alias du='du -h'
alias free='free -h'
alias ports='ss -tulanp'
alias ip='ip -c'
alias ping='ping -c 5'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias c='clear'
alias h='history'
alias reload='exec zsh'
alias path='echo $PATH | tr ":" "\n"'

# Fedora/RHEL packages use a different FZF integration path than upstream.
if (( ! ${+widgets[fzf-history-widget]} )); then
  source <(fzf --zsh)
fi
EOF

  if ! grep -q 'aliases.personal.zsh' "$CONFIG_TEMPLATE/.zshrc"; then
    printf '\n# Personal aliases\nsource "$ZDOTDIR/aliases.personal.zsh"\n' >> "$CONFIG_TEMPLATE/.zshrc"
  fi
}

install_icons() {
  local target=$1 home=$2 icons
  icons="$home/.config/lf/icons"
  run_for "$target" mkdir -p "$home/.config/lf"
  if ! run_for "$target" test -f "$icons"; then
    run_for "$target" install -m 0644 "$ICONS_FILE" "$icons"
  fi
}

validate_config() {
  local target=$1 home=$2 config_dir=$3 file
  while IFS= read -r -d '' file; do
    run_for "$target" zsh -n "$file"
  done < <(find "$config_dir" -maxdepth 1 -type f \( -name '*.zsh' -o -name '.zshrc' -o -name '.zshenv' \) -print0)

  run_for "$target" env HOME="$home" ZDOTDIR="$config_dir" \
    XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" zsh -lic 'exit'
}

update_zshenv() {
  local target=$1 home=$2 file
  file="$home/.zshenv"
  run_for "$target" touch "$file"
  run_for "$target" sed -i --follow-symlinks \
    '/^# >>> zsh-bootstrap >>>$/,/^# <<< zsh-bootstrap <<<$/{d;}' "$file"

  if [[ "$target" == root ]]; then
    printf '%s\n' '' \
      '# >>> zsh-bootstrap >>>' \
      'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' \
      '[[ -r "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"' \
      '# <<< zsh-bootstrap <<<' | sudo tee -a "$file" >/dev/null
  else
    printf '%s\n' '' \
      '# >>> zsh-bootstrap >>>' \
      'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' \
      '[[ -r "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"' \
      '# <<< zsh-bootstrap <<<' >> "$file"
  fi
}

install_config_for() {
  local target=$1 home=$2 config stage backup='' failed
  config="$home/.config/zsh"
  step "Zsh configuration: $target"
  run_for "$target" mkdir -p "$home/.config" "$home/.local/state/zsh" "$home/.cache/zsh"
  install_icons "$target" "$home"

  stage=$(run_for "$target" mktemp -d "$home/.config/.zsh-bootstrap.XXXXXX")
  run_for "$target" cp -a "$CONFIG_TEMPLATE/." "$stage/"
  [[ "$target" == root ]] && sudo chown -R root:root "$stage"
  validate_config "$target" "$home" "$stage" || die "Staged configuration validation failed for $target"

  if run_for "$target" test -e "$config"; then
    backup="$home/.config/zsh.backup-$TIMESTAMP"
    run_for "$target" test ! -e "$backup" || die "Backup already exists: $backup"
    run_for "$target" mv "$config" "$backup"
    BACKUPS+=("$target: $backup")
  fi
  run_for "$target" mv "$stage" "$config"
  update_zshenv "$target" "$home"

  if ! validate_config "$target" "$home" "$config"; then
    failed="$home/.config/zsh.failed-$TIMESTAMP"
    run_for "$target" mv "$config" "$failed"
    if [[ -n "$backup" ]]; then
      run_for "$target" mv "$backup" "$config"
      die "Configuration validation failed for $target; previous configuration restored"
    fi
    die "Configuration validation failed for $target; failed files saved at $failed"
  fi
  info "Installed: $config"
}

set_login_shell() {
  local user=$1 zsh_path old_shell
  zsh_path=$(PATH="$SYSTEM_PATH" command -v zsh)
  if ! grep -qxF "$zsh_path" /etc/shells; then
    printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  fi

  old_shell=$(getent passwd "$user" | cut -d: -f7)
  [[ -n "$old_shell" ]] || die "Could not determine the login shell for $user"
  if [[ "$old_shell" != "$zsh_path" ]]; then
    sudo chsh -s "$zsh_path" "$user" || die "Could not change the login shell for $user"
    ROLLBACKS+=("$user: sudo chsh -s $old_shell $user")
    info "Login shell changed for $user: $old_shell -> $zsh_path"
  else
    info "$user already uses $zsh_path"
  fi
}

verify_tools() {
  local command_name
  for command_name in zsh nvim eza bat fd fzf zoxide starship rg lf git curl; do
    system_has "$command_name" || die "Required command is missing after installation: $command_name"
    if [[ "$command_name" == lf ]]; then
      PATH="$SYSTEM_PATH" lf -version &>/dev/null || die "Required command cannot run: lf"
    else
      PATH="$SYSTEM_PATH" "$command_name" --version &>/dev/null ||
        die "Required command cannot run: $command_name"
    fi
  done
}

summary() {
  printf '\n%b%bInstallation complete.%b\n' "$GREEN" "$BOLD" "$NC"
  if ((${#BACKUPS[@]})); then
    printf 'Configuration backups:\n'
    printf '  %s\n' "${BACKUPS[@]}"
  fi
  if ((${#ROLLBACKS[@]})); then
    printf 'Login-shell rollback commands:\n'
    printf '  %s\n' "${ROLLBACKS[@]}"
  fi
  printf 'Log out and back in, then run: zsh\n'
}

main() {
  printf '%bzsh-bootstrap%b\n' "$BOLD" "$NC"
  preflight
  WORK_DIR=$(mktemp -d /tmp/zsh-bootstrap.XXXXXX)
  install_packages
  verify_tools
  prepare_template
  install_config_for "$(id -un)" "$HOME"
  $INSTALL_ROOT && install_config_for root /root
  set_login_shell "$(id -un)"
  $INSTALL_ROOT && set_login_shell root
  verify_tools
  summary
}

main "$@"
