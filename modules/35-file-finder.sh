#!/usr/bin/env bash
# 35-file-finder.sh — interactive fuzzy file search with preview and editor.

register_pkg \
  --id file-finder \
  --name "file finder" \
  --desc "Ctrl-F / ff — fuzzy file search with preview; opens in Nano, falling back to vi" \
  --group cli \
  --check "test -x \"\$HOME/.local/bin/ff\" && cmp -s \"\$DEVUP_ROOT/configs/ff\" \"\$HOME/.local/bin/ff\"" \
  --install "_install_file_finder" \
  --config "_configure_file_finder" \
  --manual "Install fd, fzf and bat, then: install -m 0755 configs/ff ~/.local/bin/ff, and bind Ctrl-F in your shell" \
  --note "Press Ctrl-F to find files from the current directory, or run 'ff PATH' to search elsewhere." \
  --needs "fd fzf bat" \
  --default yes

_install_file_finder() {
  [[ "${DRY_RUN:-0}" == "1" ]] || ensure_local_bin
  install_managed_file "$DEVUP_ROOT/configs/ff" "$HOME/.local/bin/ff"
}

_configure_file_finder() {
  # The script is refreshed here as well as in --install, so that
  # `devup config file-finder` repairs an out-of-date ff on its own. It is a
  # no-op when the installed copy already matches the one we ship.
  _install_file_finder || return 1

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] bind Ctrl-F to ff in ~/.zshrc + ~/.bashrc${C_RESET}"
    return 0
  fi

  local zsh_block bash_block
  zsh_block="$(cat <<'ZSH'
# Ctrl-F normally means forward-char in Zsh/readline. devup intentionally
# repurposes it as the familiar Find shortcut; Right Arrow still moves forward.
if [[ -o interactive ]]; then
  _devup_file_finder_widget() {
    if ! command -v ff >/dev/null 2>&1; then
      zle -M "ff is not on PATH — run: devup install file-finder"
      return 1
    fi
    # zle -I hands the screen to the finder; reset-prompt draws the prompt again
    # once it, and any editor it opened, has exited.
    zle -I
    ff < /dev/tty
    zle reset-prompt
  }
  zle -N _devup_file_finder_widget
  # Bound in every keymap so Ctrl-F works the same whether the shell is in
  # emacs or vi editing mode. Looking ff up inside the widget rather than out
  # here keeps the binding working when ~/.local/bin joins PATH later in the
  # rc file than this block runs.
  bindkey -M emacs '^F' _devup_file_finder_widget
  bindkey -M viins '^F' _devup_file_finder_widget
  bindkey -M vicmd '^F' _devup_file_finder_widget
fi
ZSH
)"

  bash_block="$(cat <<'BASH'
# Ctrl-F normally means forward-char in Bash/readline. devup intentionally
# repurposes it as the familiar Find shortcut; Right Arrow still moves forward.
# bind only works in an interactive shell, and plenty of tooling sources
# .bashrc from a non-interactive one, where it would otherwise warn.
if [[ $- == *i* ]]; then
  _devup_file_finder_widget() {
    if command -v ff >/dev/null 2>&1; then
      ff < /dev/tty
    else
      printf 'ff is not on PATH — run: devup install file-finder\n' >&2
    fi
  }
  # Bound in every keymap so Ctrl-F works the same in emacs and vi editing
  # mode. ff is looked up inside the function rather than out here, so the
  # binding survives ~/.local/bin joining PATH later in the rc file.
  bind -m emacs-standard -x '"\C-f": _devup_file_finder_widget'
  bind -m vi-insert      -x '"\C-f": _devup_file_finder_widget'
  bind -m vi-command     -x '"\C-f": _devup_file_finder_widget'
fi
BASH
)"

  write_block "$HOME/.zshrc" "file-finder" "$zsh_block"
  write_block "$HOME/.bashrc" "file-finder" "$bash_block"
  success "Bound Ctrl-F to the interactive file finder in zsh and bash"
}
