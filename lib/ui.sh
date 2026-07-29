#!/usr/bin/env bash
# ui.sh — menus. Uses whiptail (preinstalled on Ubuntu) when available,
# and falls back to a plain numbered text interface otherwise.

USE_TUI=0

ui_init() {
  if [[ "${NO_TUI:-0}" == "1" ]]; then USE_TUI=0; return 0; fi
  if [[ ! -t 0 || ! -t 1 ]]; then USE_TUI=0; return 0; fi
  if command -v whiptail >/dev/null 2>&1; then USE_TUI=1; else USE_TUI=0; fi
}

_ui_rows() { local r; r="$(tput lines 2>/dev/null || echo 24)"; echo $(( r > 30 ? 28 : r - 4 )); }
_ui_cols() { local c; c="$(tput cols 2>/dev/null || echo 80)"; echo $(( c > 100 ? 96 : c - 6 )); }

ui_msg() {
  local title="$1" body="$2"
  if (( USE_TUI )); then
    whiptail --title "$title" --msgbox "$body" "$(_ui_rows)" "$(_ui_cols)" 3>&1 1>&2 2>&3 || true
  else
    printf '\n%s\n%s\n' "${C_BOLD}${title}${C_RESET}" "$body"
  fi
}

ui_yesno() {
  local title="$1" body="$2"
  if (( USE_TUI )); then
    whiptail --title "$title" --yesno "$body" 12 "$(_ui_cols)" 3>&1 1>&2 2>&3
  else
    confirm "$body"
  fi
}

# ui_menu <title> <prompt> <tag> <label> [<tag> <label>...]
# Prints the chosen tag on stdout. Returns non-zero if cancelled.
ui_menu() {
  local title="$1" prompt="$2"; shift 2
  if (( USE_TUI )); then
    whiptail --title "$title" --notags --menu "$prompt" \
      "$(_ui_rows)" "$(_ui_cols)" $(( ($# / 2) < 12 ? ($# / 2) : 12 )) \
      "$@" 3>&1 1>&2 2>&3
  else
    local -a tags=() labels=()
    while [[ $# -gt 0 ]]; do tags+=("$1"); labels+=("$2"); shift 2; done
    printf '\n%s\n' "${C_BOLD}${title}${C_RESET}" >&2
    printf '%s\n\n' "$prompt" >&2
    local i
    for i in "${!tags[@]}"; do
      printf '  %2d) %s\n' "$(( i + 1 ))" "${labels[$i]}" >&2
    done
    local choice
    read -r -p "
Choice [1-${#tags[@]}]: " choice >&2
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#tags[@]} )) || return 1
    printf '%s\n' "${tags[$(( choice - 1 ))]}"
  fi
}

# ui_checklist <title> <prompt> <tag> <label> <on|off> [...]
# Prints selected tags, one per line.
ui_checklist() {
  local title="$1" prompt="$2"; shift 2
  if (( USE_TUI )); then
    whiptail --title "$title" --notags --separate-output --checklist "$prompt" \
      "$(_ui_rows)" "$(_ui_cols)" $(( ($# / 3) < 12 ? ($# / 3) : 12 )) \
      "$@" 3>&1 1>&2 2>&3
  else
    local -a tags=() labels=() states=()
    while [[ $# -gt 0 ]]; do tags+=("$1"); labels+=("$2"); states+=("$3"); shift 3; done
    printf '\n%s\n' "${C_BOLD}${title}${C_RESET}" >&2
    printf '%s\n\n' "$prompt" >&2
    local i mark
    for i in "${!tags[@]}"; do
      mark=" "; [[ "${states[$i]}" == "on" ]] && mark="*"
      printf '  %2d) [%s] %s\n' "$(( i + 1 ))" "$mark" "${labels[$i]}" >&2
    done
    printf '\n%s\n' "${C_DIM}Enter numbers separated by spaces, 'a' for all, or blank to accept the [*] defaults.${C_RESET}" >&2
    local reply
    read -r -p "Selection: " reply >&2
    if [[ -z "$reply" ]]; then
      for i in "${!tags[@]}"; do
        [[ "${states[$i]}" == "on" ]] && printf '%s\n' "${tags[$i]}"
      done
      return 0
    fi
    if [[ "$reply" == "a" || "$reply" == "all" ]]; then
      printf '%s\n' "${tags[@]}"
      return 0
    fi
    local n
    for n in $reply; do
      [[ "$n" =~ ^[0-9]+$ ]] || continue
      (( n >= 1 && n <= ${#tags[@]} )) && printf '%s\n' "${tags[$(( n - 1 ))]}"
    done
  fi
}

# ui_gauge_start / ui_gauge_update — progress bar during installation.
# Falls back to plain step logging.
ui_status_line() {
  local current="$1" total="$2" label="$3"
  printf '%s\n' "${C_BOLD}${C_CYAN}[${current}/${total}]${C_RESET} ${C_BOLD}${label}${C_RESET}"
  _log_raw "[install ${current}/${total}] $label"
}

# status_badge <id> — one-character install marker for menus.
status_badge() {
  case "${PKG_STATUS[$1]}" in
    installed) printf '✓' ;;
    missing)   printf '·' ;;
    *)         printf '?' ;;
  esac
}

# pkg_label <id> — the line shown in menus, padded for alignment.
# The leading badge shows install state; the checkbox (drawn by whiptail or by
# our text fallback) shows selection. Keeping them visually distinct matters.
pkg_label() {
  local id="$1"
  printf '%s %-14s %s' "$(status_badge "$id")" "${PKG_NAME[$id]}" "${PKG_DESC[$id]}"
}
