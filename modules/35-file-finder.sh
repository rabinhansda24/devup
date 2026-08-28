#!/usr/bin/env bash
# 35-file-finder.sh — interactive fuzzy file search with preview and editor.

register_pkg \
  --id file-finder \
  --name "file finder" \
  --desc "Ctrl-F here, Alt-Shift-F over \$HOME — fuzzy file search with preview" \
  --group cli \
  --check "test -x \"\$HOME/.local/bin/ff\" && cmp -s \"\$DEVUP_ROOT/configs/ff\" \"\$HOME/.local/bin/ff\"" \
  --install "_install_file_finder" \
  --config "_configure_file_finder" \
  --manual "Install fd, fzf and bat, then: install -m 0755 configs/ff ~/.local/bin/ff, and bind Ctrl-F in your shell" \
  --note "Ctrl-F finds files in the current directory, Alt-Shift-F searches all of \$HOME. Also: ff PATH, ff --global." \
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
# Alt-Shift-F is the same finder over $HOME. It is used rather than Ctrl-Shift-F
# because a terminal cannot tell Ctrl-Shift-F from Ctrl-F — control characters
# carry no shift bit — so that would need per-terminal configuration, while
# Alt-Shift-F arrives as ESC F everywhere and only displaces a duplicate of
# Alt-f (forward-word), which Alt-f itself still does.
if [[ -o interactive ]]; then
  _devup_ff_run() {
    if ! command -v ff >/dev/null 2>&1; then
      zle -M "ff is not on PATH — run: devup install file-finder"
      return 1
    fi
    # zle -I hands the screen to the finder; reset-prompt draws the prompt again
    # once it, and any editor it opened, has exited.
    zle -I
    ff "$@" < /dev/tty
    zle reset-prompt
  }
  _devup_file_finder_widget()   { _devup_ff_run; }
  _devup_global_finder_widget() { _devup_ff_run --global; }
  zle -N _devup_file_finder_widget
  zle -N _devup_global_finder_widget
  # Bound in every keymap so both work the same whether the shell is in emacs
  # or vi editing mode. Looking ff up inside the widget rather than out here
  # keeps the bindings working when ~/.local/bin joins PATH later in the rc
  # file than this block runs.
  bindkey -M emacs '^F'  _devup_file_finder_widget
  bindkey -M viins '^F'  _devup_file_finder_widget
  bindkey -M vicmd '^F'  _devup_file_finder_widget
  bindkey -M emacs '^[F' _devup_global_finder_widget
  bindkey -M viins '^[F' _devup_global_finder_widget
  bindkey -M vicmd '^[F' _devup_global_finder_widget
fi
ZSH
)"

  bash_block="$(cat <<'BASH'
# Ctrl-F normally means forward-char in Bash/readline. devup intentionally
# repurposes it as the familiar Find shortcut; Right Arrow still moves forward.
# Alt-Shift-F is the same finder over $HOME. It is used rather than Ctrl-Shift-F
# because a terminal cannot tell Ctrl-Shift-F from Ctrl-F — control characters
# carry no shift bit — so that would need per-terminal configuration, while
# Alt-Shift-F arrives as ESC F everywhere and readline only has it aliased to
# Alt-f (do-lowercase-version), which Alt-f itself still does.
# bind only works in an interactive shell, and plenty of tooling sources
# .bashrc from a non-interactive one, where it would otherwise warn.
if [[ $- == *i* ]]; then
  _devup_ff_run() {
    if command -v ff >/dev/null 2>&1; then
      ff "$@" < /dev/tty
    else
      printf 'ff is not on PATH — run: devup install file-finder\n' >&2
    fi
  }
  _devup_file_finder_widget()   { _devup_ff_run; }
  _devup_global_finder_widget() { _devup_ff_run --global; }
  # Bound in every keymap so both work the same in emacs and vi editing mode.
  # ff is looked up inside the function rather than out here, so the bindings
  # survive ~/.local/bin joining PATH later in the rc file.
  bind -m emacs-standard -x '"\C-f": _devup_file_finder_widget'
  bind -m vi-insert      -x '"\C-f": _devup_file_finder_widget'
  bind -m vi-command     -x '"\C-f": _devup_file_finder_widget'
  bind -m emacs-standard -x '"\eF": _devup_global_finder_widget'
  bind -m vi-insert      -x '"\eF": _devup_global_finder_widget'
  bind -m vi-command     -x '"\eF": _devup_global_finder_widget'
fi
BASH
)"

  write_block "$HOME/.zshrc" "file-finder" "$zsh_block"
  write_block "$HOME/.bashrc" "file-finder" "$bash_block"
  success "Bound Ctrl-F (here) and Alt-Shift-F (global) to the file finder in zsh and bash"
}
