#!/usr/bin/env bash
# 60-terminal.sh — WezTerm and the font it needs to render prompt glyphs.

register_group terminal "Terminal" \
  "WezTerm plus a Nerd Font. Sets up leader-key splits and tabs."

register_pkg \
  --id nerd-font \
  --name "JetBrainsMono NF" \
  --desc "Nerd Font — required or starship's glyphs render as boxes" \
  --group terminal \
  --check "fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd Font'" \
  --install "_install_nerd_font" \
  --manual "Download JetBrainsMono.zip from https://github.com/ryanoasis/nerd-fonts/releases and unzip into ~/.local/share/fonts" \
  --default yes

_install_nerd_font() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] install JetBrainsMono Nerd Font to ~/.local/share/fonts${C_RESET}"
    return 0
  fi
  command -v unzip >/dev/null 2>&1 || install_apt unzip
  command -v fc-cache >/dev/null 2>&1 || install_apt fontconfig

  local url zip dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
  url="$(gh_asset_url ryanoasis/nerd-fonts 'JetBrainsMono\.(zip|tar\.xz)$')" \
    || { error "Could not find the JetBrainsMono asset in nerd-fonts releases"; return 1; }
  zip="${TMP_DIR}/$(basename "$url")"
  info "Downloading $(basename "$url") (~30MB)"
  run "curl -fsSL -o '$zip' '$url'" || return 1
  mkdir -p "$dir"
  case "$zip" in
    *.zip)    run "unzip -qo '$zip' -d '$dir'" || return 1 ;;
    *.tar.xz) run "tar -xJf '$zip' -C '$dir'" || return 1 ;;
  esac
  # Drop the license/readme noise the archive ships with.
  find "$dir" -maxdepth 1 -type f ! -name '*.ttf' ! -name '*.otf' -delete 2>/dev/null || true
  run "fc-cache -f" || true
  success "Installed JetBrainsMono Nerd Font"
}

register_pkg \
  --id wezterm \
  --name "WezTerm" \
  --desc "GPU terminal with built-in multiplexing (tmux optional)" \
  --group terminal \
  --check "command -v wezterm" \
  --install "_install_wezterm" \
  --config "_configure_wezterm" \
  --manual "See https://wezterm.org/installation.html — use the .deb, not the snap" \
  --needs "nerd-font" \
  --default yes

_install_wezterm() {
  # Prefer the .deb matching this Ubuntu release, then any Ubuntu .deb.
  local esc="${OS_VERSION//./\\.}"
  install_gh_deb wez/wezterm "Ubuntu${esc}\\.deb\$" && return 0
  warn "No .deb for Ubuntu ${OS_VERSION}; trying the newest available Ubuntu build"
  install_gh_deb wez/wezterm "Ubuntu[0-9.]+\\.deb\$" && return 0
  error "Could not install WezTerm automatically. See https://wezterm.org/installation.html"
  return 1
}

_configure_wezterm() {
  local cfg="$HOME/.wezterm.lua"
  local src="$DEVUP_ROOT/configs/wezterm.lua"

  [[ -f "$src" ]] || { warn "configs/wezterm.lua missing; skipping"; return 0; }

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] install ~/.wezterm.lua${C_RESET}"
    return 0
  fi

  if [[ -f "$cfg" ]]; then
    if grep -q "devup" "$cfg" 2>/dev/null; then
      debug "wezterm config already managed by devup"
      return 0
    fi
    backup_file "$cfg"
  fi
  cp "$src" "$cfg"
  success "Installed ~/.wezterm.lua (leader = Ctrl-A, see comments for keys)"
}

register_pkg \
  --id tmux \
  --name "tmux" \
  --desc "Only needed for persistent sessions over SSH — WezTerm multiplexes locally" \
  --group terminal \
  --check "command -v tmux" \
  --install "install_apt tmux" \
  --manual "sudo apt install tmux" \
  --default no
