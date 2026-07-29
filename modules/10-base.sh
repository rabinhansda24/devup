#!/usr/bin/env bash
# 10-base.sh — compilers, VCS, and the shell itself.

register_group base "System & Build Essentials" \
  "Compilers, headers and libraries that language toolchains link against."

register_pkg \
  --id build-essential \
  --name "build-essential" \
  --desc "gcc, g++, make — needed by cgo, Rust and native npm modules" \
  --group base \
  --check "dpkg -s build-essential" \
  --install "install_apt build-essential" \
  --manual "sudo apt install build-essential" \
  --default yes

register_pkg \
  --id dev-headers \
  --name "dev headers" \
  --desc "pkg-config, libssl-dev, zlib, libffi — common -sys crate deps" \
  --group base \
  --check "dpkg -s pkg-config && dpkg -s libssl-dev" \
  --install "install_apt pkg-config libssl-dev zlib1g-dev libffi-dev libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev ca-certificates gnupg" \
  --manual "sudo apt install pkg-config libssl-dev zlib1g-dev libffi-dev libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev ca-certificates gnupg" \
  --default yes

register_pkg \
  --id core-utils \
  --name "core utils" \
  --desc "curl, wget, git, unzip, htop, tree, xclip" \
  --group base \
  --check "command -v curl && command -v git && command -v unzip" \
  --install "install_apt curl wget git unzip zip htop tree xclip file" \
  --manual "sudo apt install curl wget git unzip zip htop tree xclip file" \
  --default yes

register_pkg \
  --id git-config \
  --name "git defaults" \
  --desc "Sane global git config (rebase pulls, autosetupremote, delta pager)" \
  --group base \
  --check "git config --global --get devup.configured" \
  --install "true" \
  --config "_configure_git" \
  --manual "See configs/gitconfig for the settings applied" \
  --needs "core-utils" \
  --default yes

_configure_git() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] apply global git defaults${C_RESET}"
    return 0
  fi
  local gc="git config --global"
  $gc init.defaultBranch main
  $gc pull.rebase true
  $gc push.autoSetupRemote true
  $gc push.default simple
  $gc fetch.prune true
  $gc rebase.autoStash true
  $gc rebase.autosquash true
  $gc diff.algorithm histogram
  $gc merge.conflictstyle zdiff3
  $gc rerere.enabled true
  $gc column.ui auto
  $gc branch.sort -committerdate
  $gc log.date iso
  $gc alias.st "status -sb"
  $gc alias.lg "log --oneline --graph --decorate --all"
  $gc alias.last "log -1 --stat"
  $gc alias.unstage "restore --staged"
  $gc alias.amend "commit --amend --no-edit"

  if command -v delta >/dev/null 2>&1; then
    $gc core.pager delta
    $gc interactive.diffFilter "delta --color-only"
    $gc delta.navigate true
    $gc delta.line-numbers true
    $gc merge.conflictstyle zdiff3
  fi

  $gc devup.configured true

  if [[ -z "$($gc --get user.name 2>/dev/null || true)" ]]; then
    warn "git user.name is not set. Run: git config --global user.name 'Your Name'"
  fi
  if [[ -z "$($gc --get user.email 2>/dev/null || true)" ]]; then
    warn "git user.email is not set. Run: git config --global user.email 'you@example.com'"
  fi
  success "Applied global git defaults"
}

register_pkg \
  --id zsh \
  --name "zsh" \
  --desc "Z shell plus autosuggestions and syntax highlighting" \
  --group base \
  --check "command -v zsh" \
  --install "install_apt zsh zsh-autosuggestions zsh-syntax-highlighting" \
  --config "_configure_zsh_shell" \
  --manual "sudo apt install zsh zsh-autosuggestions zsh-syntax-highlighting && chsh -s \$(which zsh)" \
  --note "Log out and back in for zsh to become your active login shell." \
  --default yes

_configure_zsh_shell() {
  local zsh_path current
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] set zsh as the default login shell${C_RESET}"
    return 0
  fi
  zsh_path="$(command -v zsh)" || return 0
  current="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$current" == "$zsh_path" ]]; then
    debug "zsh is already the default shell"
    return 0
  fi
  if confirm "Make zsh your default login shell?"; then
    grep -qxF "$zsh_path" /etc/shells 2>/dev/null || \
      printf '%s\n' "$zsh_path" | $SUDO tee -a /etc/shells >/dev/null
    if $SUDO chsh -s "$zsh_path" "$USER"; then
      success "Default shell set to zsh (takes effect on next login)"
    else
      warn "Could not change shell automatically. Run: chsh -s $zsh_path"
    fi
  fi
}
