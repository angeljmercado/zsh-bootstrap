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
readonly TOOL_SPECS='core|zsh|zsh|zsh|
core|git|git|git|
core|curl|curl|curl|
dependency|chsh|passwd|util-linux-user|
tool|nvim|neovim|neovim|
tool|eza|eza|eza|
tool|bat|bat|bat|batcat
tool|fd|fd-find|fd-find|fdfind
tool|fzf|fzf|fzf|
tool|zoxide|zoxide|zoxide|
tool|starship|starship|starship|
tool|rg|ripgrep|ripgrep|
tool|lf|lf|lf|'

INSTALL_ROOT=false
WORK_DIR=''
CONFIG_TEMPLATE=''
ICONS_FILE=''
OS_ID=''
OS_MAJOR=''
PACKAGE_MANAGER=''
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TRANSACTION_OPEN=false
SUDO_KEEPALIVE_PID=''
declare -a BACKUPS=() ROLLBACKS=()
declare -a CONFIG_TARGETS=() CONFIG_HOMES=() CONFIG_BACKUPS=()
declare -a SHELL_USERS=() SHELL_OLD_VALUES=()

stop_sudo_keepalive() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=''
  fi
}

start_sudo_keepalive() {
  stop_sudo_keepalive
  # Refresh the sudo timestamp while this installer runs (long package/network steps).
  # kill -0 "$$" exits the loop when the parent shell is gone.
  while true; do
    sudo -n true || exit
    sleep 30
    kill -0 "$$" || exit
  done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
}

cleanup() {
  stop_sudo_keepalive
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
  return 0
}

on_exit() {
  local status=$?
  trap - EXIT
  if (( status != 0 )) && $TRANSACTION_OPEN; then
    set +e
    rollback_transaction
  fi
  cleanup
  exit "$status"
}
trap on_exit EXIT

system_has() { PATH="$SYSTEM_PATH" command -v "$1" &>/dev/null; }

run_as_target() {
  local target=$1
  shift
  if [[ "$target" == root ]]; then
    sudo -H "$@"
  else
    "$@"
  fi
}

# Download a single pinned commit (shallow when the remote allows it).
# Falls back to a full clone + checkout so older git remotes still work.
clone_pinned_commit() {
  local url=$1 dest=$2 commit=$3
  [[ -n "$url" && -n "$dest" && -n "$commit" ]] ||
    die "clone_pinned_commit requires url, destination, and commit"

  rm -rf -- "$dest"
  mkdir -p "$dest"
  git -C "$dest" init -q
  git -C "$dest" remote add origin "$url"

  if git -C "$dest" fetch --depth 1 --quiet origin "$commit"; then
    git -C "$dest" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD ||
      die "Could not check out pinned commit $commit from $url"
  else
    warn "Shallow fetch failed for $url; falling back to a full clone"
    rm -rf -- "$dest"
    git clone --quiet "$url" "$dest" || die "Could not clone $url"
    git -C "$dest" -c advice.detachedHead=false checkout -q --detach "$commit" ||
      die "Could not check out pinned commit $commit from $url"
  fi

  [[ $(git -C "$dest" rev-parse HEAD) == "$commit" ]] ||
    die "Pinned commit mismatch for $url (expected $commit)"
  # Named local branch at the pin (no fragile origin/master upstream tracking).
  git -C "$dest" checkout -q -B bootstrap-pinned
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
  start_sudo_keepalive

  # Noninteractive opt-in/out for automation. Unset → prompt on a TTY, else user only.
  case "${ZSH_BOOTSTRAP_INSTALL_ROOT:-}" in
    1|true|yes|YES|True)
      INSTALL_ROOT=true
      info "Root configuration enabled via ZSH_BOOTSTRAP_INSTALL_ROOT"
      ;;
    0|false|no|NO|False)
      INSTALL_ROOT=false
      ;;
    '')
      if [[ -t 0 ]]; then
        read -r -p "Configure root with the same Zsh environment? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] && INSTALL_ROOT=true
      fi
      ;;
    *)
      die "Invalid ZSH_BOOTSTRAP_INSTALL_ROOT value: ${ZSH_BOOTSTRAP_INSTALL_ROOT} (use 1/true/yes or 0/false/no)"
      ;;
  esac
}

package_available() {
  local package_name=$1 result
  if [[ "$PACKAGE_MANAGER" == apt ]]; then
    result=$(LC_ALL=C apt-cache policy "$package_name") ||
      die "apt could not query package availability: $package_name"
    [[ -z "$result" ]] && return 1
    [[ "$result" == *'Candidate: (none)'* ]] && return 1
    [[ "$result" == *'Candidate:'* ]] || die "apt returned an invalid result for: $package_name"
  else
    result=$(dnf -q repoquery --available --qf '%{name}' "$package_name") ||
      die "dnf could not query package availability: $package_name"
    [[ -n "$result" ]] || return 1
  fi
}

install_package() {
  local command_name=$1 apt_package=$2 dnf_package=$3 alternate=${4:-} group=$5 package_name
  if system_has "$command_name"; then
    info "Found required command: $command_name"
    return 0
  fi

  if [[ "$PACKAGE_MANAGER" == apt ]]; then
    package_name=$apt_package
  else
    package_name=$dnf_package
  fi

  if [[ "$group" == tool ]]; then
    info "Checking repositories for $package_name..."
    if ! package_available "$package_name"; then
      install_fallback "$command_name"
      return
    fi
  fi

  info "Installing $package_name..."
  if [[ "$PACKAGE_MANAGER" == apt ]]; then
    sudo apt-get install -y "$package_name" || die "apt failed to install required package: $package_name"
  else
    sudo dnf install -y "$package_name" || die "dnf failed to install required package: $package_name"
  fi

  if [[ -n "$alternate" ]] && system_has "$alternate" && ! system_has "$command_name"; then
    sudo mkdir -p /usr/local/bin
    sudo ln -sfn "$(PATH="$SYSTEM_PATH" command -v "$alternate")" "/usr/local/bin/$command_name"
  fi
  system_has "$command_name" || die "$package_name installed but did not provide required command: $command_name"
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
  sudo mkdir -p /usr/local/bin
  archive="$WORK_DIR/${command_name}.tar.gz"
  info "Downloading $command_name..."
  curl --proto '=https' --tlsv1.2 -fL --retry 3 -o "$archive" "$url"
  info "Verifying and installing $command_name..."
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

  step "Repository metadata"
  info "Refreshing metadata after repository changes..."
  sudo dnf makecache -y || die "dnf could not refresh repository metadata"
}

install_packages() {
  step "Required tools"
  if [[ "$PACKAGE_MANAGER" == apt ]]; then
    info "Refreshing APT package metadata..."
    sudo apt-get update -q
  fi

  local group command_name apt_package dnf_package alternate
  # Install these first because the remaining setup depends on them.
  while IFS='|' read -r group command_name apt_package dnf_package alternate; do
    [[ "$group" == core || "$group" == dependency ]] || continue
    install_package "$command_name" "$apt_package" "$dnf_package" "$alternate" "$group"
  done <<< "$TOOL_SPECS"
  if ! command -v tar &>/dev/null || ! command -v sha256sum &>/dev/null; then
    die "tar and sha256sum are required"
  fi

  setup_rhel_repositories
  while IFS='|' read -r group command_name apt_package dnf_package alternate; do
    [[ "$group" == tool ]] || continue
    install_package "$command_name" "$apt_package" "$dnf_package" "$alternate" "$group"
  done <<< "$TOOL_SPECS"
}

prepare_template() {
  step "Pinned Zsh configuration"
  CONFIG_TEMPLATE="$WORK_DIR/zsh-template"
  info "Downloading the pinned Zsh configuration..."
  clone_pinned_commit "$CONFIG_REPO" "$CONFIG_TEMPLATE" "$CONFIG_COMMIT"
  # Keep non-interactive startup validation from failing when no TTY exists.
  sed -i 's#export GPG_TTY=$(tty)#export GPG_TTY=$(tty 2>/dev/null || true)#' \
    "$CONFIG_TEMPLATE/.zshenv"
  grep -qxF 'export GPG_TTY=$(tty 2>/dev/null || true)' "$CONFIG_TEMPLATE/.zshenv" ||
    die "Could not prepare the pinned Zsh configuration"
  sed -i 's#export PATH="$HOME/.local/bin:$PATH"#export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"#' \
    "$CONFIG_TEMPLATE/.zshenv"
  grep -qxF 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"' \
    "$CONFIG_TEMPLATE/.zshenv" || die "Could not prepare the Zsh command path"

  local repo name commit plugin_dir
  while IFS='|' read -r repo name commit; do
    plugin_dir="$CONFIG_TEMPLATE/plugins/$name"
    info "Downloading Zsh plugin: $name..."
    clone_pinned_commit "https://github.com/$repo.git" "$plugin_dir" "$commit"
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
  info "Downloading lf icons..."
  curl --proto '=https' --tlsv1.2 -fL --retry 3 -o "$ICONS_FILE" "$ICONS_URL"
  printf '%s  %s\n' "$ICONS_SHA256" "$ICONS_FILE" | sha256sum -c - >/dev/null ||
    die "Checksum verification failed for lf icons"
}

write_personal_config() {
  cat > "$CONFIG_TEMPLATE/aliases.personal.zsh" <<'EOF'
# Managed by zsh-bootstrap; the previous configuration is backed up on every run.
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
  if ! _fzf_init=$(fzf --zsh); then
    print -u2 "fzf does not provide Zsh integration"
    return 1
  fi
  eval "$_fzf_init"
  unset _fzf_init
fi
EOF

  if ! grep -q 'aliases.personal.zsh' "$CONFIG_TEMPLATE/.zshrc"; then
    printf '\n# Personal aliases\nsource "$ZDOTDIR/aliases.personal.zsh"\n' >> "$CONFIG_TEMPLATE/.zshrc"
  fi
}

install_icons() {
  local target=$1 home=$2 icons
  icons="$home/.config/lf/icons"
  run_as_target "$target" mkdir -p "$home/.config/lf"
  if ! run_as_target "$target" test -f "$icons"; then
    run_as_target "$target" install -m 0644 "$ICONS_FILE" "$icons"
  fi
}

validate_config() {
  local target=$1 home=$2 config_dir=$3 file files startup_output startup_status=0
  files=$(run_as_target "$target" find "$config_dir" -maxdepth 1 -type f \
    \( -name '*.zsh' -o -name '.zshrc' -o -name '.zshenv' \) -print) || return 1
  [[ -n "$files" ]] || return 1
  while IFS= read -r file; do
    run_as_target "$target" zsh -n "$file" || return 1
  done <<< "$files"

  # LANG/LC_ALL=C keeps "command not found:" matching stable across locales.
  startup_output=$(run_as_target "$target" env HOME="$home" PATH="$SYSTEM_PATH" \
    LANG=C LC_ALL=C \
    XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" zsh -f -o ERR_EXIT -ic \
    'export ZDOTDIR=$1; source "$1/.zshenv"; source "$1/.zshrc"' zsh "$config_dir" 2>&1) ||
    startup_status=$?
  [[ -z "$startup_output" ]] || printf '%s\n' "$startup_output" >&2
  (( startup_status == 0 )) || return 1
  [[ "$startup_output" != *'command not found:'* ]]
}

update_zshenv() {
  local target=$1 home=$2 file
  file="$home/.zshenv"
  run_as_target "$target" touch "$file" || return 1
  run_as_target "$target" sed -i --follow-symlinks \
    '/^# >>> zsh-bootstrap >>>$/,/^# <<< zsh-bootstrap <<<$/{d;}' "$file" || return 1

  if [[ "$target" == root ]]; then
    zdotdir_block | sudo tee -a "$file" >/dev/null
  else
    zdotdir_block >> "$file"
  fi
}

zdotdir_block() {
  printf '%s\n' '' \
    '# >>> zsh-bootstrap >>>' \
    'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' \
    '[[ -r "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"' \
    '# <<< zsh-bootstrap <<<'
}

install_config_for() {
  local target=$1 home=$2 config stage backup='' failed
  config="$home/.config/zsh"
  step "Zsh configuration: $target"
  run_as_target "$target" mkdir -p "$home/.config" "$home/.local/state/zsh" "$home/.cache/zsh"
  install_icons "$target" "$home"

  info "Staging configuration for $target..."
  stage=$(run_as_target "$target" mktemp -d "$home/.config/.zsh-bootstrap.XXXXXX")
  run_as_target "$target" cp -a "$CONFIG_TEMPLATE/." "$stage/"
  [[ "$target" == root ]] && sudo chown -R root:root "$stage"
  info "Validating staged configuration for $target..."
  if ! validate_config "$target" "$home" "$stage"; then
    failed="$home/.config/zsh.failed-$TIMESTAMP-$$"
    run_as_target "$target" mv "$stage" "$failed"
    die "Staged configuration validation failed for $target; files saved at $failed"
  fi

  if run_as_target "$target" test -e "$config"; then
    backup="$home/.config/zsh.backup-$TIMESTAMP"
    run_as_target "$target" test ! -e "$backup" || die "Backup already exists: $backup"
    run_as_target "$target" mv "$config" "$backup"
    BACKUPS+=("$target: $backup")
  fi
  CONFIG_TARGETS+=("$target")
  CONFIG_HOMES+=("$home")
  CONFIG_BACKUPS+=("$backup")

  info "Activating configuration for $target..."
  run_as_target "$target" mv "$stage" "$config" || die "Could not activate configuration for $target"
  update_zshenv "$target" "$home" || die "Could not update $home/.zshenv"
  info "Validating installed configuration for $target..."
  validate_config "$target" "$home" "$config" || die "Configuration validation failed for $target"
  info "Installed: $config"
}

rollback_transaction() {
  local i user old_shell target home config backup failed
  warn "Installation failed; rolling back completed changes"

  for ((i=${#SHELL_USERS[@]} - 1; i >= 0; i--)); do
    user=${SHELL_USERS[i]}
    old_shell=${SHELL_OLD_VALUES[i]}
    if sudo chsh -s "$old_shell" "$user"; then
      warn "Restored $user login shell to $old_shell"
    else
      warn "Could not restore $user login shell; run: sudo chsh -s $old_shell $user"
    fi
  done

  for ((i=${#CONFIG_TARGETS[@]} - 1; i >= 0; i--)); do
    target=${CONFIG_TARGETS[i]}
    home=${CONFIG_HOMES[i]}
    backup=${CONFIG_BACKUPS[i]}
    config="$home/.config/zsh"
    failed="$home/.config/zsh.failed-$TIMESTAMP-$$"

    if run_as_target "$target" test -e "$config"; then
      run_as_target "$target" mv "$config" "$failed" &&
        warn "Saved failed $target configuration at $failed"
    fi
    if [[ -n "$backup" ]] && run_as_target "$target" test -e "$backup"; then
      if run_as_target "$target" mv "$backup" "$config"; then
        warn "Restored $target configuration from $backup"
      else
        warn "Could not restore $target configuration; backup remains at $backup"
      fi
    fi
  done
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
    info "Changing the login shell for $user..."
    sudo chsh -s "$zsh_path" "$user" || die "Could not change the login shell for $user"
    SHELL_USERS+=("$user")
    SHELL_OLD_VALUES+=("$old_shell")
    ROLLBACKS+=("$user: sudo chsh -s $old_shell $user")
    info "Login shell changed for $user: $old_shell -> $zsh_path"
  else
    info "$user already uses $zsh_path"
  fi
}

remove_legacy_global_zdotdir() {
  local file=/etc/zsh/zshenv
  [[ -f "$file" ]] || return 0
  if grep -q '^# Personal zsh config location$' "$file" &&
     grep -q '^export ZDOTDIR=\$HOME/.config/zsh$' "$file"; then
    if sudo sed -i '/^# Personal zsh config location$/{N;/\nexport ZDOTDIR=\$HOME\/.config\/zsh$/d;}' "$file"; then
      info "Removed the legacy system-wide ZDOTDIR setting"
    else
      warn "Could not remove the legacy ZDOTDIR setting from $file"
    fi
  fi
}

verify_tools() {
  local group command_name apt_package dnf_package alternate
  while IFS='|' read -r group command_name apt_package dnf_package alternate; do
    [[ "$group" == dependency ]] && continue
    info "Verifying required command: $command_name"
    system_has "$command_name" || die "Required command is missing after installation: $command_name"
    if [[ "$command_name" == lf ]]; then
      PATH="$SYSTEM_PATH" lf -version &>/dev/null || die "Required command cannot run: lf"
    else
      PATH="$SYSTEM_PATH" "$command_name" --version &>/dev/null ||
        die "Required command cannot run: $command_name"
    fi
  done <<< "$TOOL_SPECS"
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
  # -t uses $TMPDIR when set, otherwise the system temp directory.
  WORK_DIR=$(mktemp -d -t zsh-bootstrap.XXXXXX) ||
    die "Could not create a temporary working directory"
  install_packages
  verify_tools
  prepare_template
  TRANSACTION_OPEN=true
  install_config_for "$(id -un)" "$HOME"
  $INSTALL_ROOT && install_config_for root /root
  set_login_shell "$(id -un)"
  $INSTALL_ROOT && set_login_shell root
  verify_tools
  TRANSACTION_OPEN=false
  remove_legacy_global_zdotdir
  summary
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
