#!/usr/bin/env bash
# core.sh — logging, command execution, and environment primitives.

# $USER and $HOME are not always exported (cron, systemd, some containers) and
# `set -u` turns that into a hard failure. Fill them in defensively.
: "${USER:=$(id -un 2>/dev/null || echo unknown)}"
: "${HOME:=$(getent passwd "$USER" 2>/dev/null | cut -d: -f6)}"
: "${HOME:=/root}"
export USER HOME

# ---------- colours ----------
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]] && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

# ---------- logging ----------
LOG_FILE="${LOG_FILE:-}"

_log_raw() {
  # Strip colour codes when writing to the log file.
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(sed 's/\x1b\[[0-9;]*m//g' <<<"$1")" >>"$LOG_FILE"
  fi
}

log()      { printf '%s\n' "$1"; _log_raw "$1"; }
info()     { printf '%s\n' "${C_BLUE}::${C_RESET} $1"; _log_raw "[info] $1"; }
success()  { printf '%s\n' "${C_GREEN}✓${C_RESET} $1"; _log_raw "[ok] $1"; }
warn()     { printf '%s\n' "${C_YELLOW}!${C_RESET} $1" >&2; _log_raw "[warn] $1"; }
error()    { printf '%s\n' "${C_RED}✗${C_RESET} $1" >&2; _log_raw "[error] $1"; }
step()     { printf '\n%s\n' "${C_BOLD}${C_CYAN}==>${C_RESET} ${C_BOLD}$1${C_RESET}"; _log_raw "[step] $1"; }
debug()    { [[ "${VERBOSE:-0}" == "1" ]] && printf '%s\n' "${C_DIM}  $1${C_RESET}" >&2; _log_raw "[debug] $1"; return 0; }

die() { error "$1"; exit "${2:-1}"; }

# ---------- command execution ----------
# run <command string> — executes via bash -c, honours DRY_RUN, logs output.
run() {
  local cmd="$1"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] ${cmd}${C_RESET}"
    _log_raw "[dry-run] $cmd"
    return 0
  fi
  debug "exec: $cmd"
  _log_raw "[exec] $cmd"
  if [[ "${VERBOSE:-0}" == "1" ]]; then
    bash -c "$cmd" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"
    return "${PIPESTATUS[0]}"
  fi
  local out rc=0
  out="$(bash -c "$cmd" 2>&1)" || rc=$?
  [[ -n "$out" && -n "$LOG_FILE" ]] && printf '%s\n' "$out" >>"$LOG_FILE"
  if (( rc != 0 )); then
    printf '%s\n' "${C_DIM}${out}${C_RESET}" | tail -n 15 >&2
  fi
  return "$rc"
}

# ---------- sudo ----------
SUDO=""
setup_sudo() {
  if [[ "$(id -u)" == "0" ]]; then
    SUDO=""
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || die "sudo is required but not installed."
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    SUDO="sudo"
    return 0
  fi
  info "Requesting sudo access (needed for apt and /usr/local writes)…"
  sudo -v || die "Could not obtain sudo privileges."
  SUDO="sudo"
  # Keep the sudo timestamp alive for the duration of the run.
  ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE_PID=$!
}

cleanup_sudo() {
  [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}

# ---------- environment ----------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) DEB_ARCH="amd64"; GNU_ARCH="x86_64"; ALT_ARCH="x64" ;;
    aarch64|arm64) DEB_ARCH="arm64"; GNU_ARCH="aarch64"; ALT_ARCH="arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
  export DEB_ARCH GNU_ARCH ALT_ARCH
}

detect_os() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release. This tool targets Ubuntu/Debian."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  OS_VERSION="${VERSION_ID:-}"
  OS_LIKE="${ID_LIKE:-}"
  export OS_ID OS_CODENAME OS_VERSION OS_LIKE
  if [[ "$OS_ID" != "ubuntu" && "$OS_LIKE" != *debian* ]]; then
    warn "Detected '$OS_ID'. This tool is built for Ubuntu; some steps may fail."
  fi
}

# ---------- paths ----------
ensure_local_bin() {
  mkdir -p "$HOME/.local/bin"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

# ---------- temp ----------
TMP_DIR=""
make_tmp() {
  TMP_DIR="$(mktemp -d -t devup.XXXXXXXX)"
  export TMP_DIR
}
cleanup_tmp() {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
  return 0
}

# ---------- idempotent file blocks ----------
# write_block <file> <marker> <content>
# Inserts or replaces a marked block, leaving the rest of the file untouched.
write_block() {
  local file="$1" marker="$2" content="$3"
  local begin="# >>> devup:${marker} >>>"
  local end="# <<< devup:${marker} <<<"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] write block '${marker}' into ${file}${C_RESET}"
    return 0
  fi

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qF "$begin" "$file" 2>/dev/null; then
    # Replace existing block.
    local tmp="${TMP_DIR:-/tmp}/block.$$"
    # Content goes through ENVIRON, not -v: awk -v interprets backslash
    # escapes and would corrupt any content containing a literal backslash.
    DEVUP_BLOCK_CONTENT="$content" awk -v b="$begin" -v e="$end" '
      index($0, b) == 1 { print b; print ENVIRON["DEVUP_BLOCK_CONTENT"]; print e; skip=1; next }
      index($0, e) == 1 { skip=0; next }
      skip != 1 { print }
    ' "$file" >"$tmp"
    cat "$tmp" >"$file"
    rm -f "$tmp"
    debug "updated block '$marker' in $file"
  else
    { printf '\n%s\n%s\n%s\n' "$begin" "$content" "$end"; } >>"$file"
    debug "appended block '$marker' to $file"
  fi
}

# backup_file <path> — copies to <path>.devup-bak.<timestamp> if it exists and has no backup yet.
backup_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] backup ${f}${C_RESET}"
    return 0
  fi
  local bak="${f}.devup-bak.$(date +%Y%m%d%H%M%S)"
  cp -a "$f" "$bak"
  info "Backed up $(basename "$f") → $(basename "$bak")"
}

# ---------- misc ----------
confirm() {
  local prompt="${1:-Continue?}"
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  local reply
  read -r -p "${prompt} [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

human_join() {
  local out="" x
  for x in "$@"; do
    [[ -n "$out" ]] && out+=", "
    out+="$x"
  done
  printf '%s' "$out"
}
