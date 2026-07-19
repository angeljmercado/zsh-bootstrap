# Zsh Bootstrap

A single interactive installer for the personal Zsh environment based on
[radleylewis/zsh](https://github.com/radleylewis/zsh).

## Supported systems

- Ubuntu 26.04 and 24.04 LTS
- RHEL 10 and 9
- Oracle Linux 10 and 9
- AlmaLinux 10 and 9
- `x86_64`

Run the script as a normal user with working `sudo` access. Do not run the
whole script through `sudo`.

```bash
bash zsh-bootstrap.sh
```

During an interactive run, the installer asks whether root should receive the
same environment. Choosing Yes also changes root's login shell after its Zsh
configuration passes validation. Without a terminal, only the invoking user is
configured.

## What it does

The installer:

1. Verifies the distribution, architecture, and `sudo` access.
2. Installs `zsh`, `neovim`, `eza`, `bat`, `fd`, `fzf`, `zoxide`, `starship`,
   `ripgrep`, `lf`, `git`, and `curl`.
3. Enables CRB/CodeReady Builder and EPEL on RHEL-family systems.
4. Uses pinned, checksum-verified official binaries only when a required tool
   is unavailable from configured repositories.
5. Stages a pinned Zsh configuration and pinned plugins before replacing the
   active configuration.
6. Validates every required command and Zsh startup before changing login
   shells.

Ubuntu's `batcat` and `fdfind` commands are exposed system-wide as `bat` and
`fd`, so the same configuration also works for root.

## Existing configuration

Every existing `~/.config/zsh` is moved intact before replacement:

```text
~/.config/zsh.backup-YYYYMMDD-HHMMSS
```

Root receives the same backup under `/root/.config` when selected. The exact
backup paths are printed at the end. Failed replacement validation restores the
previous configuration; the failed files are retained with a `.failed-...`
name for inspection.

An existing `~/.zshenv` remains in place. The installer owns only the marked
`zsh-bootstrap` block appended to it, replacing that block on later runs rather
than adding duplicates.

## Other locations

- `~/.config/lf/icons` — installed only when missing
- `~/.local/state/zsh` — shell history
- `~/.cache/zsh` — completion cache
- `/usr/local/bin` — canonical links and verified fallback binaries
- `/opt/zsh-bootstrap` — Neovim fallback files, when needed
- `/etc/shells` — updated only if the installed Zsh path is absent

The installer does not set a system-wide `ZDOTDIR`.

## Verify

Log out and back in, then run:

```bash
echo "$SHELL"
zsh --version
nvim --version
eza --version
bat --version
fd --version
fzf --version
zoxide --version
starship --version
rg --version
lf -version
```

The final installer summary prints a `chsh` rollback command whenever it
changes a login shell.

## Nerd Font

Icons are rendered by the terminal on the machine from which you connect.
Configure that terminal to use a Nerd Font such as JetBrainsMono Nerd Font
Mono; installing a font on a headless server does not change the local terminal.

The Starship theme remains in `starship.toml` beside the installer and is
copied into each selected Zsh configuration.
