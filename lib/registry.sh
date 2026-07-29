#!/usr/bin/env bash
# registry.sh — the package/group registry and detection engine.
#
# Contributors: you almost certainly want to edit a file in modules/ instead
# of this one. See CONTRIBUTING.md.

# shellcheck disable=SC2034  # registry arrays are consumed by devup and lib/*.sh
declare -a GROUP_IDS=()
declare -A GROUP_TITLE=()
declare -A GROUP_DESC=()

declare -a PKG_IDS=()
declare -A PKG_NAME=()
declare -A PKG_DESC=()
declare -A PKG_GROUP=()
declare -A PKG_CHECK=()
declare -A PKG_INSTALL=()
declare -A PKG_CONFIG=()
declare -A PKG_MANUAL=()
declare -A PKG_NOTE=()
declare -A PKG_NEEDS=()
declare -A PKG_DEFAULT=()
declare -A PKG_STATUS=()   # installed | missing | unknown

# register_group <id> <title> [description]
register_group() {
  local id="$1" title="$2" desc="${3:-}"
  if [[ -z "${GROUP_TITLE[$id]:-}" ]]; then
    GROUP_IDS+=("$id")
  fi
  GROUP_TITLE["$id"]="$title"
  GROUP_DESC["$id"]="$desc"
}

# register_pkg --id X --name X --desc X --group X --check CMD --install CMD [...]
#
#   --check    shell snippet; exit 0 means "already installed"
#   --install  shell snippet that installs it
#   --config   shell snippet run after install (also re-runnable on its own)
#   --manual   human-readable instructions for manual mode
#   --note     shown in the post-run summary (e.g. "log out and back in")
#   --needs    space-separated package ids that must be installed first
#   --default  yes|no — whether it is pre-ticked in the menu
register_pkg() {
  local id="" name="" desc="" group="misc" check="" install="" config=""
  local manual="" note="" needs="" default="no"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id)      id="$2"; shift 2 ;;
      --name)    name="$2"; shift 2 ;;
      --desc)    desc="$2"; shift 2 ;;
      --group)   group="$2"; shift 2 ;;
      --check)   check="$2"; shift 2 ;;
      --install) install="$2"; shift 2 ;;
      --config)  config="$2"; shift 2 ;;
      --manual)  manual="$2"; shift 2 ;;
      --note)    note="$2"; shift 2 ;;
      --needs)   needs="$2"; shift 2 ;;
      --default) default="$2"; shift 2 ;;
      *) warn "register_pkg: unknown option '$1' (id=${id:-?})"; shift ;;
    esac
  done

  [[ -z "$id" ]] && { error "register_pkg: --id is required"; return 1; }
  if [[ -n "${PKG_NAME[$id]:-}" ]]; then
    warn "register_pkg: duplicate id '$id' — ignoring the second definition"
    return 0
  fi

  PKG_IDS+=("$id")
  PKG_NAME["$id"]="${name:-$id}"
  PKG_DESC["$id"]="$desc"
  PKG_GROUP["$id"]="$group"
  PKG_CHECK["$id"]="$check"
  PKG_INSTALL["$id"]="$install"
  PKG_CONFIG["$id"]="$config"
  PKG_MANUAL["$id"]="$manual"
  PKG_NOTE["$id"]="$note"
  PKG_NEEDS["$id"]="$needs"
  PKG_DEFAULT["$id"]="$default"
  PKG_STATUS["$id"]="unknown"
}

# load_modules — sources every modules/*.sh in lexical order.
load_modules() {
  local m
  shopt -s nullglob
  for m in "$DEVUP_ROOT"/modules/*.sh; do
    debug "loading module $(basename "$m")"
    # shellcheck disable=SC1090
    . "$m"
  done
  shopt -u nullglob
  (( ${#PKG_IDS[@]} > 0 )) || die "No packages registered — is modules/ empty?"
}

# detect_all — populates PKG_STATUS for every package.
detect_all() {
  local id
  for id in "${PKG_IDS[@]}"; do
    if [[ -z "${PKG_CHECK[$id]}" ]]; then
      PKG_STATUS["$id"]="unknown"
    elif bash -c "${PKG_CHECK[$id]}" >/dev/null 2>&1; then
      PKG_STATUS["$id"]="installed"
    else
      PKG_STATUS["$id"]="missing"
    fi
  done
}

pkg_exists() { [[ -n "${PKG_NAME[$1]:-}" ]]; }

# pkgs_in_group <group> — echoes ids in registration order.
pkgs_in_group() {
  local g="$1" id
  for id in "${PKG_IDS[@]}"; do
    [[ "${PKG_GROUP[$id]}" == "$g" ]] && printf '%s\n' "$id"
  done
}

# resolve_deps <id...> — echoes the selection expanded with dependencies,
# de-duplicated, and ordered by registration order.
resolve_deps() {
  local -A want=()
  local -a queue=("$@")
  local id dep

  while (( ${#queue[@]} > 0 )); do
    id="${queue[0]}"
    queue=("${queue[@]:1}")
    pkg_exists "$id" || { warn "Unknown package id '$id' — skipping"; continue; }
    [[ -n "${want[$id]:-}" ]] && continue
    want["$id"]=1
    for dep in ${PKG_NEEDS[$id]}; do
      if pkg_exists "$dep"; then
        [[ -n "${want[$dep]:-}" ]] || queue+=("$dep")
      fi
    done
  done

  for id in "${PKG_IDS[@]}"; do
    [[ -n "${want[$id]:-}" ]] && printf '%s\n' "$id"
  done
}
