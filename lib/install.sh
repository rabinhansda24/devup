#!/usr/bin/env bash
# install.sh — reusable installation primitives for modules.

APT_UPDATED=0

apt_update_once() {
  [[ "$APT_UPDATED" == "1" ]] && return 0
  info "Refreshing apt package lists…"
  run "$SUDO apt-get update -qq" || warn "apt-get update reported problems; continuing"
  APT_UPDATED=1
}

apt_update_force() {
  run "$SUDO apt-get update -qq" || warn "apt-get update reported problems; continuing"
  APT_UPDATED=1
}

# install_apt <pkg...>
install_apt() {
  apt_update_once
  run "$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $*"
}

# add_apt_key <url> <keyring-name>  — dearmors into /etc/apt/keyrings
add_apt_key() {
  local url="$1" name="$2"
  run "$SUDO install -m 0755 -d /etc/apt/keyrings"
  run "curl -fsSL '$url' | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/${name}.gpg"
  run "$SUDO chmod a+r /etc/apt/keyrings/${name}.gpg"
}

# add_apt_key_raw <url> <keyring-name> — for URLs that already serve a binary
# keyring (e.g. GitHub CLI), where gpg --dearmor would fail.
add_apt_key_raw() {
  local url="$1" name="$2"
  run "$SUDO install -m 0755 -d /etc/apt/keyrings"
  run "curl -fsSL '$url' | $SUDO tee /etc/apt/keyrings/${name}.gpg >/dev/null"
  run "$SUDO chmod a+r /etc/apt/keyrings/${name}.gpg"
}

# add_apt_repo <name> <line>
add_apt_repo() {
  local name="$1" line="$2"
  run "printf '%s\n' '$line' | $SUDO tee /etc/apt/sources.list.d/${name}.list >/dev/null"
  apt_update_force
}

# gh_asset_url <owner/repo> <regex> — prints the matching browser_download_url
# from the latest release. Uses grep/sed so it works before jq is installed.
gh_asset_url() {
  local repo="$1" pattern="$2" url
  url="$(curl -fsSL \
      -H 'Accept: application/vnd.github+json' \
      ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
      "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/' \
    | grep -E "$pattern" \
    | head -n1)"
  [[ -n "$url" ]] || return 1
  printf '%s\n' "$url"
}

# install_gh_deb <owner/repo> <asset regex>
install_gh_deb() {
  local repo="$1" pattern="$2"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] download latest .deb from ${repo} matching /${pattern}/ and dpkg -i${C_RESET}"
    return 0
  fi
  local url deb
  url="$(gh_asset_url "$repo" "$pattern")" \
    || { error "No release asset in ${repo} matching /${pattern}/"; return 1; }
  deb="${TMP_DIR}/$(basename "$url")"
  info "Downloading $(basename "$url")"
  run "curl -fsSL -o '$deb' '$url'" || return 1
  # apt-get install resolves dependencies; dpkg -i does not.
  run "$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq '$deb'"
}

# install_gh_tarball <owner/repo> <asset regex> <binary-name...>
# Extracts the archive and installs the named binaries into /usr/local/bin.
install_gh_tarball() {
  local repo="$1" pattern="$2"; shift 2
  local bins=("$@")
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] download ${repo} /${pattern}/ → install ${bins[*]} to /usr/local/bin${C_RESET}"
    return 0
  fi
  local url archive dir b found
  url="$(gh_asset_url "$repo" "$pattern")" \
    || { error "No release asset in ${repo} matching /${pattern}/"; return 1; }
  archive="${TMP_DIR}/$(basename "$url")"
  dir="${TMP_DIR}/x-$(basename "$repo")"
  mkdir -p "$dir"
  info "Downloading $(basename "$url")"
  run "curl -fsSL -o '$archive' '$url'" || return 1
  case "$archive" in
    *.tar.gz|*.tgz) run "tar -xzf '$archive' -C '$dir'" || return 1 ;;
    *.tar.xz)       run "tar -xJf '$archive' -C '$dir'" || return 1 ;;
    *.tar.bz2)      run "tar -xjf '$archive' -C '$dir'" || return 1 ;;
    *.zip)          command -v unzip >/dev/null || install_apt unzip
                    run "unzip -qo '$archive' -d '$dir'" || return 1 ;;
    *) error "Don't know how to extract $(basename "$archive")"; return 1 ;;
  esac
  for b in "${bins[@]}"; do
    found="$(find "$dir" -type f -name "$b" -perm -u+x 2>/dev/null | head -n1)"
    [[ -z "$found" ]] && found="$(find "$dir" -type f -name "$b" 2>/dev/null | head -n1)"
    if [[ -z "$found" ]]; then
      error "Binary '$b' not found inside $(basename "$archive")"
      return 1
    fi
    run "$SUDO install -m 0755 '$found' /usr/local/bin/$b" || return 1
    success "Installed /usr/local/bin/$b"
  done
}

# install_script <url> [args...] — pipe a vendor install script to sh.
# Vendor scripts are the officially supported path for these tools; we always
# show the URL so the user can audit it, and manual mode prints it instead.
install_script() {
  local url="$1"; shift
  local args="$*"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] curl -fsSL ${url} | sh ${args:+-s -- $args}${C_RESET}"
    return 0
  fi
  info "Running vendor installer: $url"
  if [[ -n "$args" ]]; then
    run "curl --proto '=https' --tlsv1.2 -fsSL '$url' | sh -s -- $args"
  else
    run "curl --proto '=https' --tlsv1.2 -fsSL '$url' | sh"
  fi
}

# install_managed_file <src> <dest> [mode]
# Keeps a file devup generates into the user's home in step with the copy in
# configs/. Existence alone is not enough to call such a file installed: an old
# copy would keep every later improvement from ever reaching the machine, so the
# contents decide.
#
# devup only claims a file that still carries the "devup-managed:" marker every
# file in configs/ starts with. Anything else belongs to the user and is backed
# up before it is replaced.
install_managed_file() {
  local src="$1" dest="$2" mode="${3:-0755}"

  [[ -f "$src" ]] || { error "$(basename "$src") is missing from the devup checkout"; return 1; }

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    if cmp -s "$src" "$dest" 2>/dev/null; then
      printf '%s\n' "${C_DIM}  [dry-run] ${dest} is already up to date${C_RESET}"
    else
      printf '%s\n' "${C_DIM}  [dry-run] install ${dest}${C_RESET}"
    fi
    return 0
  fi

  # Already byte-for-byte what we ship: leave it alone. Rewriting it would make
  # every run report a change it did not make.
  if cmp -s "$src" "$dest"; then
    [[ -x "$dest" ]] || chmod "$mode" "$dest"
    debug "$dest is already up to date"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  local verb="Installed"
  if [[ -e "$dest" ]]; then
    verb="Updated"
    if ! grep -q 'devup-managed:' "$dest" 2>/dev/null; then
      warn "$dest does not carry devup's marker — saving a copy before replacing it"
      backup_file "$dest"
    fi
  fi

  install -m "$mode" "$src" "$dest" || return 1
  success "${verb} ${dest}"
}

# symlink_bin <target> <linkname> — for Ubuntu's renamed binaries (bat→batcat).
symlink_bin() {
  local target="$1" name="$2"
  ensure_local_bin
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] ln -s \$(command -v ${target}) ~/.local/bin/${name}${C_RESET}"
    return 0
  fi
  local src
  src="$(command -v "$target" 2>/dev/null)" || { warn "$target not found; skipping $name symlink"; return 0; }
  ln -sf "$src" "$HOME/.local/bin/$name"
  debug "linked $name → $src"
}

# cargo_install <crate...>
cargo_install() {
  if ! command -v cargo >/dev/null 2>&1 && [[ "${DRY_RUN:-0}" != "1" ]]; then
    # shellcheck disable=SC1091
    [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
  fi
  run "cargo install --locked $*"
}

# install_gh_binary <owner/repo> <asset regex> <dest-name>
# For releases that publish a bare executable rather than an archive.
install_gh_binary() {
  local repo="$1" pattern="$2" dest="$3"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] download ${repo} /${pattern}/ → /usr/local/bin/${dest}${C_RESET}"
    return 0
  fi
  local url out
  url="$(gh_asset_url "$repo" "$pattern")" \
    || { error "No release asset in ${repo} matching /${pattern}/"; return 1; }
  out="${TMP_DIR}/${dest}"
  info "Downloading $(basename "$url")"
  run "curl -fsSL -o '$out' '$url'" || return 1
  run "chmod +x '$out'" || return 1
  run "$SUDO install -m 0755 '$out' /usr/local/bin/${dest}" || return 1
  success "Installed /usr/local/bin/${dest}"
}
