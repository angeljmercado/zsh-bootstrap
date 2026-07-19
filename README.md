# Zsh Bootstrap

A simple installer for a consistent Zsh environment on:

- Ubuntu 24.04 and 26.04 LTS
- RHEL, Oracle Linux, and AlmaLinux 9 and 10
- x86_64 systems

It installs Zsh, Neovim, eza, bat, fd, fzf, zoxide, Starship, ripgrep, lf,
Git, and curl. Packages come from the distribution when available; otherwise,
the installer uses pinned, checksum-verified official binaries.

## Install

Run as your normal user with `sudo` access:

```bash
bash zsh-bootstrap.sh
```

Do not run the script itself with `sudo`. During an interactive installation,
you can choose whether to apply the same configuration to root. For automation,
set `ZSH_BOOTSTRAP_INSTALL_ROOT=1` (include root) or `=0` (user only).

Existing Zsh configuration is backed up as
`~/.config/zsh.backup-YYYYMMDD-HHMMSS` and replaced on every run. The installer
validates the new setup before changing login shells and rolls back
configuration changes if the setup fails.

See [zsh-setup.md](zsh-setup.md) for additional details.
