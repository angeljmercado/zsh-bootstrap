# zsh Bootstrap

Based on [radleylewis/zsh](https://github.com/radleylewis/zsh).  
Tested on: Ubuntu 24.04+ / Debian 12+.

---

## Quickstart

```bash
bash zsh-bootstrap.sh
```

The script handles every step below automatically. Read on if you prefer manual
steps or want to understand what the script does.

---

## What gets installed

| Tool | Purpose |
|------|---------|
| `zsh` | Shell |
| `neovim` | Editor (`vim` alias) |
| `eza` | `ls` replacement — icons, git status, tree view |
| `bat` | `cat` replacement — syntax highlighting |
| `fd` | Fast `find` replacement |
| `fzf` | Fuzzy finder — `Ctrl+R` history, `Ctrl+T`/`Ctrl+F` file picker |
| `zoxide` | Smart `cd` — `z <partial>` jumps to frecent dirs |
| `starship` | Prompt |
| `ripgrep` | `grep` replacement — `rg` |
| `lf` | Terminal file manager |

Plugins auto-install on first `zsh` launch:

- `zsh-autosuggestions` — fish-style inline suggestions
- `zsh-history-substring-search` — arrow-key history filtering
- `zsh-vi-mode` — vi keybindings on the command line
- `fast-syntax-highlighting` — real-time syntax highlighting

Update plugins any time:

```bash
zplugin-update
```

---

## Prerequisites — Nerd Font

Icons in `eza`, `lf`, and Starship are rendered by your **local terminal**.
The font must be installed on the machine you connect *from*, not the server.

Install **JetBrainsMono Nerd Font** (or any Nerd Font):

_Linux:_
```bash
mkdir -p ~/.local/share/fonts
cp JetBrainsMono/*.ttf ~/.local/share/fonts/
fc-cache -fv
```

_macOS:_
```bash
cp JetBrainsMono/*.ttf ~/Library/Fonts/
```

_Windows (PowerShell):_
```powershell
Copy-Item JetBrainsMono\*.ttf "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\"
```

Download: [nerdfonts.com](https://www.nerdfonts.com/font-downloads) — pick
**JetBrainsMono Nerd Font Mono** (the Mono variant keeps icons fixed-width
so they align in grid layouts).

Then configure your terminal emulator to use the font. Most terminals expose
this in Preferences → Font. Restart the terminal after changing it.

---

## Manual steps

### Step 1 — Install dependencies

```bash
sudo apt update
sudo apt install -y zsh neovim eza bat fd-find fzf zoxide starship ripgrep lf git curl
```

### Step 2 — Compatibility symlinks

Ubuntu ships `fd` as `fdfind` and `bat` as `batcat`. The config expects `fd` and `bat`:

```bash
mkdir -p ~/.local/bin
ln -sf /usr/bin/fdfind ~/.local/bin/fd
ln -sf /usr/bin/batcat ~/.local/bin/bat
```

### Step 3 — lf icons

```bash
mkdir -p ~/.config/lf
curl -fsSLo ~/.config/lf/icons \
  https://raw.githubusercontent.com/gokcehan/lf/master/etc/icons.example
```

### Step 4 — Clone the config

```bash
git clone https://github.com/radleylewis/zsh.git ~/.config/zsh
```

### Step 5 — Set ZDOTDIR

```bash
sudo tee -a /etc/zsh/zshenv <<'EOF'

# Personal zsh config location
export ZDOTDIR=$HOME/.config/zsh
EOF
```

### Step 6 — XDG directories

```bash
mkdir -p ~/.local/state/zsh ~/.cache/zsh
```

### Step 7 — Personal aliases

Create `~/.config/zsh/aliases.personal.zsh`:

```zsh
# PATH
export PATH="$HOME/.local/bin:$PATH"

# direnv (only if installed)
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias '~'='cd ~'

# Listing extras (eza time/size sort)
alias lt='eza -lah --icons --git --sort=modified'
alias lS='eza -lah --icons --git --sort=size'

# Safety nets
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias mkdir='mkdir -pv'

# System info
alias du='du -h'
alias free='free -h'
alias ports='ss -tulanp'

# Network
alias ip='ip -c'
alias ping='ping -c 5'

# Grep extras
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Convenience
alias c='clear'
alias h='history'
alias reload='exec zsh'
alias path='echo $PATH | tr ":" "\n"'
```

Then source it from `~/.config/zsh/.zshrc`:

```bash
printf '\n# Personal aliases\nsource "$ZDOTDIR/aliases.personal.zsh"\n' \
  >> ~/.config/zsh/.zshrc
```

### Step 8 — Set default shell

```bash
chsh -s $(which zsh)
```

Log out and back in for the change to take effect.

### Step 9 — First launch

```bash
zsh
```

Plugins clone automatically on first start.

---

## Verify

```bash
echo $SHELL          # /usr/bin/zsh
bat --version
fd --version
fzf --version
zoxide --version
starship --version
lf --version
```

---

## Starship theme

The theme lives in `starship.toml` alongside the bootstrap script.
During setup it is copied to `~/.config/zsh/starship.toml`, overwriting the
default shipped by radleylewis/zsh.

To edit the theme, modify `starship.toml` and re-run the copy manually:

```bash
cp starship.toml ~/.config/zsh/starship.toml && exec zsh
```

Full reference: [starship.rs/config](https://starship.rs/config/)

---

## Aliases reference

### From `aliases.zsh` (radleylewis/zsh)

| Alias | Expands to |
|-------|-----------|
| `ls` | `eza --icons` |
| `ll` | `eza -lh --icons --git` |
| `la` | `eza -lah --icons --git` |
| `tree` | `eza --tree --icons` |
| `cat` | `bat` |
| `grep` | `rg --color=auto` |
| `diff` | `diff --color=auto` |
| `df` | `df -h` |
| `vim` | `nvim` |
| `-` | `cd -` |

### Personal additions (`aliases.personal.zsh`)

| Alias | Expands to |
|-------|-----------|
| `..` | `cd ..` |
| `...` | `cd ../..` |
| `....` | `cd ../../..` |
| `~` | `cd ~` |
| `lt` | `eza -lah --icons --git --sort=modified` |
| `lS` | `eza -lah --icons --git --sort=size` |
| `cp` | `cp -iv` |
| `mv` | `mv -iv` |
| `rm` | `rm -iv` |
| `mkdir` | `mkdir -pv` |
| `du` | `du -h` |
| `free` | `free -h` |
| `ports` | `ss -tulanp` |
| `ip` | `ip -c` |
| `ping` | `ping -c 5` |
| `c` | `clear` |
| `h` | `history` |
| `reload` | `exec zsh` |
| `path` | `echo $PATH \| tr ":" "\n"` |

---

## Key bindings reference

### Shell prompt

| Binding | Action |
|---------|--------|
| `Ctrl+R` | Fuzzy search shell history |
| `Ctrl+T` | Fuzzy file picker — includes hidden files |
| `Ctrl+F` | Fuzzy file picker — excludes hidden files |
| `↑` / `↓` | History substring search (type prefix first, then arrow) |
| `Ctrl+\` | Toggle autosuggestions on/off |
| `Ctrl+Right` | Move cursor forward one word |
| `Ctrl+Left` | Move cursor backward one word |
| `Esc` | Switch to vi normal mode |

### vi mode (normal mode — enter with `Esc`)

| Key | Action |
|-----|--------|
| `h` / `l` | Move left / right |
| `w` / `b` | Forward / back one word |
| `0` / `$` | Start / end of line |
| `dd` | Clear line |
| `yy` | Yank line |
| `p` | Paste |
| `u` | Undo |
| `i` / `a` | Insert before / after cursor |
| `A` / `I` | Insert at end / start of line |

### lf — file manager

Launch: `lf` — quitting with `q` auto-`cd`s to the last visited directory.

| Key | Action |
|-----|--------|
| `h` / `←` | Parent directory |
| `l` / `→` / `Enter` | Open / enter |
| `j` / `k` | Down / up |
| `gg` / `G` | First / last item |
| `Space` | Select / deselect |
| `zh` | Toggle hidden files |
| `y` / `d` / `p` | Yank / cut / paste |
| `D` | Delete |
| `r` | Rename |
| `/` | Search |
| `n` / `N` | Next / previous result |
| `m` / `'` | Bookmark / jump to bookmark |
| `!` | Open shell here |
| `q` | Quit (shell cds to last dir) |

### Optional: bind lf to a key

Add inside the `vvm_after_init()` function in `~/.config/zsh/bindings.zsh`:

```zsh
function _lf_widget() { lf; zle reset-prompt; }
zle -N _lf_widget
bindkey '^O' _lf_widget   # Ctrl+O
```

`Ctrl+O` is available in every terminal. `Ctrl+Shift+Letter` combos are
unreliable — many terminals intercept them before the shell sees them.

### fzf (when picker is open)

| Key | Action |
|-----|--------|
| `↑` / `↓` | Move up / down |
| `Enter` | Confirm |
| `Tab` / `Shift+Tab` | Toggle multi-select |
| `Ctrl+A` | Select all |
| `Ctrl+/` | Toggle preview |
| `Ctrl+C` / `Esc` | Cancel |

### zoxide

| Command | Action |
|---------|--------|
| `z <query>` | Jump to best frecent match |
| `zi <query>` | Interactive — fzf picker |
| `z -` | Previous directory |
| `zoxide query -l` | List all tracked dirs with scores |
| `zoxide add <path>` | Manually add a path |
