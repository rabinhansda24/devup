#!/usr/bin/env bash
# 35-file-finder.sh — interactive fuzzy file search with preview and editor.

register_pkg \
  --id file-finder \
  --name "file finder" \
  --desc "Ctrl-F / ff — fuzzy file search with preview; opens in Nano, falling back to vi" \
  --group cli \
  --check "test -x \$HOME/.local/bin/ff" \
  --install "_install_file_finder" \
  --config "_configure_file_finder" \
  --manual "Install fd, fzf and bat, copy configs/ff to ~/.local/bin/ff, then bind Ctrl-F in your shell" \
  --note "Press Ctrl-F to find files from the current directory, or run 'ff PATH' to search elsewhere." \
  --needs "fd fzf bat" \
  --default yes

_install_file_finder() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] install ~/.local/bin/ff${C_RESET}"
    return 0
  fi

  ensure_local_bin

  local target="$HOME/.local/bin/ff"
  cat >"$target" <<'FF'
#!/usr/bin/env bash
# Interactive file finder installed by devup.
# Usage: ff [PATH]

# Do not enable pipefail here. When a selection is accepted, fzf exits while fd
# may still be producing results; fd then receives SIGPIPE. With pipefail that
# normal condition makes the pipeline look like a failure and the editor never opens.
set -u

root="${1:-.}"

if command -v fd >/dev/null 2>&1; then
  fd_cmd="fd"
elif command -v fdfind >/dev/null 2>&1; then
  fd_cmd="fdfind"
else
  printf 'ff: fd is required\n' >&2
  exit 127
fi

command -v fzf >/dev/null 2>&1 || {
  printf 'ff: fzf is required\n' >&2
  exit 127
}

if command -v nano >/dev/null 2>&1; then
  editor_cmd="nano"
elif command -v vi >/dev/null 2>&1; then
  editor_cmd="vi"
else
  printf 'ff: neither nano nor vi is available\n' >&2
  exit 1
fi

if command -v bat >/dev/null 2>&1; then
  preview="bat --color=always --style=numbers --line-range=:500 -- {}"
elif command -v batcat >/dev/null 2>&1; then
  preview="batcat --color=always --style=numbers --line-range=:500 -- {}"
else
  preview="sed -n '1,500p' -- {}"
fi

selected="$({
  "$fd_cmd" \
    --type f \
    --hidden \
    --follow \
    --exclude .git \
    . "$root" 2>/dev/null
} | fzf \
  --height=90% \
  --layout=reverse \
  --border \
  --info=inline \
  --prompt='Files ❯ ' \
  --preview "$preview" \
  --preview-window='right:60%:wrap')" || exit 0

[[ -n "$selected" ]] || exit 0
exec "$editor_cmd" -- "$selected"
FF

  chmod 0755 "$target"
  success "Installed $target (fuzzy search + preview + editor)"
}

_configure_file_finder() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] bind Ctrl-F to ff in ~/.zshrc + ~/.bashrc${C_RESET}"
    return 0
  fi

  local zsh_block bash_block
  zsh_block="$(cat <<'ZSH'
# Ctrl-F normally means forward-char in Zsh/readline. devup intentionally
# repurposes it as the familiar Find shortcut; Right Arrow still moves forward.
if command -v ff >/dev/null 2>&1; then
  _devup_file_finder_widget() {
    zle -I
    ff
    zle reset-prompt
  }
  zle -N _devup_file_finder_widget
  bindkey '^F' _devup_file_finder_widget
fi
ZSH
)"

  bash_block="$(cat <<'BASH'
# Ctrl-F normally means forward-char in Bash/readline. devup intentionally
# repurposes it as the familiar Find shortcut; Right Arrow still moves forward.
if command -v ff >/dev/null 2>&1; then
  _devup_file_finder_widget() { ff; }
  bind -x '"\C-f":_devup_file_finder_widget'
fi
BASH
)"

  write_block "$HOME/.zshrc" "file-finder" "$zsh_block"
  write_block "$HOME/.bashrc" "file-finder" "$bash_block"
  success "Bound Ctrl-F to the interactive file finder in zsh and bash"
}
