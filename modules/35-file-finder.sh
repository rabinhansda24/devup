#!/usr/bin/env bash
# 35-file-finder.sh — interactive fuzzy file search with preview and Nano.

register_pkg \
  --id file-finder \
  --name "file finder" \
  --desc "ff — fuzzy file search with live preview; opens selection in Nano" \
  --group cli \
  --check "test -x \$HOME/.local/bin/ff" \
  --install "_install_file_finder" \
  --manual "Install fd, fzf, bat and nano, then copy configs/ff to ~/.local/bin/ff" \
  --note "Run 'ff' to search from the current directory, or 'ff PATH' to search elsewhere." \
  --needs "fd fzf bat" \
  --default yes

_install_file_finder() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] install nano + ~/.local/bin/ff${C_RESET}"
    return 0
  fi

  command -v nano >/dev/null 2>&1 || install_apt nano || return 1
  ensure_local_bin

  local target="$HOME/.local/bin/ff"
  cat >"$target" <<'FF'
#!/usr/bin/env bash
# Interactive file finder installed by devup.
# Usage: ff [PATH]

set -uo pipefail

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
exec nano -- "$selected"
FF

  chmod 0755 "$target"
  success "Installed $target (fuzzy search + preview + Nano)"
}
