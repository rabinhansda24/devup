#!/usr/bin/env bash
#
# devup bootstrap.
#
#   curl -fsSL https://raw.githubusercontent.com/rabinhansda24/devup/main/install.sh | bash
#
# Clones (or updates) devup into ~/.local/share/devup, symlinks the CLI into
# ~/.local/bin, and then hands over to it.

set -euo pipefail

REPO="${DEVUP_REPO:-https://github.com/rabinhansda24/devup.git}"
BRANCH="${DEVUP_BRANCH:-main}"
DEST="${DEVUP_DEST:-$HOME/.local/share/devup}"
BIN="$HOME/.local/bin"

if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; R=$'\033[0m'
else
  B=""; G=""; Y=""; D=""; R=""
fi

say()  { printf '%s::%s %s\n' "$G" "$R" "$1"; }
warn() { printf '%s!%s %s\n' "$Y" "$R" "$1" >&2; }
die()  { printf '%sx%s %s\n' "$Y" "$R" "$1" >&2; exit 1; }

# --- sanity checks ---
[[ "$(id -u)" == "0" ]] && die "Do not run this as root. devup will ask for sudo when it needs it."

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *debian* ]]; then
    warn "This targets Ubuntu/Debian; detected '${ID:-unknown}'. Continuing anyway."
  fi
else
  warn "Could not detect the distribution."
fi

# --- git is the only prerequisite ---
if ! command -v git >/dev/null 2>&1; then
  say "Installing git (the only prerequisite)…"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git ca-certificates
fi

# --- clone or update ---
if [[ -d "$DEST/.git" ]]; then
  say "Updating existing checkout at $DEST"
  git -C "$DEST" fetch --quiet origin "$BRANCH"
  git -C "$DEST" reset --hard --quiet "origin/$BRANCH"
else
  say "Cloning devup into $DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --branch "$BRANCH" --quiet "$REPO" "$DEST"
fi

chmod +x "$DEST/devup" "$DEST/configs/devup-clean" "$DEST/configs/ff" 2>/dev/null || true

# --- link the CLI ---
mkdir -p "$BIN"
ln -sf "$DEST/devup" "$BIN/devup"
say "Linked $BIN/devup"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    warn "$BIN is not on your PATH for this session."
    export PATH="$BIN:$PATH"
    ;;
esac

printf '\n%sdevup is installed.%s\n\n' "$B" "$R"
printf '  %sdevup%s                 interactive setup menu\n' "$B" "$R"
printf '  %sdevup status%s          see what is already on this machine\n' "$B" "$R"
printf '  %sdevup --dry-run -p fullstack%s   preview the full setup\n' "$B" "$R"
printf '\n'

# --- hand over, if we have a terminal ---
if [[ -t 0 && -t 1 ]]; then
  printf 'Launch devup now? [Y/n] '
  read -r reply </dev/tty || reply="n"
  if [[ ! "$reply" =~ ^[Nn]$ ]]; then
    exec "$DEST/devup"
  fi
else
  printf '%sRun `devup` to get started.%s\n' "$D" "$R"
fi
