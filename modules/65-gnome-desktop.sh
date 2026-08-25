#!/usr/bin/env bash
# 65-gnome-desktop.sh — optional GNOME desktop customization.
# Kept out of the default/fullstack profile: desktop appearance is personal.

register_group desktop "GNOME Desktop" \
  "Optional GNOME Shell extensions and their management tools."

register_pkg \
  --id gnome-extension-manager \
  --name "Extension Manager" \
  --desc "Browse, configure, enable and update GNOME Shell extensions" \
  --group desktop \
  --check "command -v extension-manager" \
  --install "install_apt gnome-shell-extension-manager" \
  --manual "sudo apt install gnome-shell-extension-manager" \
  --default no

register_pkg \
  --id gnome-extensions-cli \
  --name "gnome-extensions-cli" \
  --desc "gext — install compatible GNOME extensions from extensions.gnome.org" \
  --group desktop \
  --check "command -v gext || test -x \$HOME/.local/bin/gext" \
  --install "_install_gnome_extensions_cli" \
  --manual "sudo apt install pipx python3-gi && pipx install gnome-extensions-cli --system-site-packages" \
  --note "GNOME Shell extension changes may require a logout/login on Wayland." \
  --default no

_install_gnome_extensions_cli() {
  install_apt pipx python3-gi || return 1
  ensure_local_bin
  run "pipx install gnome-extensions-cli --system-site-packages" || return 1
}

_gext_bin() {
  if command -v gext >/dev/null 2>&1; then
    command -v gext
  elif [[ -x "$HOME/.local/bin/gext" ]]; then
    printf '%s\n' "$HOME/.local/bin/gext"
  else
    return 1
  fi
}

_install_gnome_extension() {
  local pk="$1" name="$2" gext_bin

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] install GNOME extension ${name} (EGO #${pk})${C_RESET}"
    return 0
  fi

  gext_bin="$(_gext_bin)" || {
    error "gext is required to install ${name}"
    return 1
  }

  # The filesystem backend avoids one GNOME confirmation dialog per extension
  # in unattended/profile installs. gext still selects a version compatible
  # with the current GNOME Shell and refuses an unavailable/rejected build.
  NO_COLOR=1 "$gext_bin" --filesystem install "$pk" || {
    error "Could not install ${name}; no compatible active release may be available"
    return 1
  }
}

_configure_dash_to_dock() {
  # Ubuntu Dock is itself a Dash-to-Dock fork. Running both causes duplicate
  # docks and competing settings, so disable Ubuntu's copy only when the user
  # explicitly selected upstream Dash to Dock.
  command -v gnome-extensions >/dev/null 2>&1 || return 0
  if gnome-extensions list 2>/dev/null | grep -qx 'ubuntu-dock@ubuntu.com'; then
    if gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null; then
      success "Disabled Ubuntu Dock; upstream Dash to Dock will own the dock"
    else
      warn "Could not disable Ubuntu Dock in this session; disable it after login"
    fi
  fi
}

register_pkg \
  --id gnome-just-perfection \
  --name "Just Perfection" \
  --desc "Fine-grained control over GNOME Shell layout and behavior" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/just-perfection-desktop@just-perfection || test -d /usr/share/gnome-shell/extensions/just-perfection-desktop@just-perfection" \
  --install "_install_gnome_extension 3843 'Just Perfection'" \
  --manual "gext install 3843" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-user-themes \
  --name "User Themes" \
  --desc "Load custom GNOME Shell themes from the user's theme directory" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com || test -d /usr/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com" \
  --install "_install_gnome_extension 19 'User Themes'" \
  --manual "gext install 19" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-wallpaper-slideshow \
  --name "Wallpaper Slideshow" \
  --desc "Rotate wallpapers from a chosen folder at configurable intervals" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/azwallpaper@azwallpaper.gitlab.com || test -d /usr/share/gnome-shell/extensions/azwallpaper@azwallpaper.gitlab.com" \
  --install "_install_gnome_extension 6281 'Wallpaper Slideshow'" \
  --manual "gext install 6281" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-chromaleon \
  --name "ChromaLeon" \
  --desc "Adapt GNOME accent colors dynamically to the current wallpaper" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/user-accent-colors@fabito02 || test -d /usr/share/gnome-shell/extensions/user-accent-colors@fabito02" \
  --install "_install_gnome_extension 10070 'ChromaLeon'" \
  --manual "gext install 10070" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-dash-to-dock \
  --name "Dash to Dock" \
  --desc "Turn GNOME's overview dash into a configurable persistent dock" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com || test -d /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com" \
  --install "_install_gnome_extension 307 'Dash to Dock'" \
  --config "_configure_dash_to_dock" \
  --manual "gext install 307" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-blur-my-shell \
  --name "Blur my Shell" \
  --desc "Add configurable blur to the overview, panel, dash and shell UI" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx || test -d /usr/share/gnome-shell/extensions/blur-my-shell@aunetx" \
  --install "_install_gnome_extension 3193 'Blur my Shell'" \
  --manual "gext install 3193" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-top-bar-organizer \
  --name "Top Bar Organizer" \
  --desc "Drag GNOME top-bar items between left, center and right areas" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/top-bar-organizer@julian.gse.jsts.xyz || test -d /usr/share/gnome-shell/extensions/top-bar-organizer@julian.gse.jsts.xyz" \
  --install "_install_gnome_extension 4356 'Top Bar Organizer'" \
  --manual "gext install 4356" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-lockscreen-clock \
  --name "Customize Lock Screen Clock" \
  --desc "Customize the clock and date displayed on GNOME's lock screen" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/CustomizeClockOnLockScreen@pratap.fastmail.fm || test -d /usr/share/gnome-shell/extensions/CustomizeClockOnLockScreen@pratap.fastmail.fm" \
  --install "_install_gnome_extension 4663 'Customize Clock on Lock Screen'" \
  --manual "gext install 4663" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-gsconnect \
  --name "GSConnect" \
  --desc "Integrate Android/iOS devices using the KDE Connect protocol" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/gsconnect@andyholmes.github.io || test -d /usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io" \
  --install "_install_gnome_extension 1319 'GSConnect'" \
  --manual "gext install 1319" \
  --note "GSConnect should not be used alongside the KDE Connect desktop application." \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-tiling-shell \
  --name "Tiling Shell" \
  --desc "Advanced tiling layouts, snap assistant and keyboard window control" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com || test -d /usr/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com" \
  --install "_install_gnome_extension 7065 'Tiling Shell'" \
  --manual "gext install 7065" \
  --needs "gnome-extensions-cli" \
  --default no

register_pkg \
  --id gnome-search-light \
  --name "Search Light" \
  --desc "Open GNOME application search as a standalone launcher" \
  --group desktop \
  --check "test -d \$HOME/.local/share/gnome-shell/extensions/search-light@icedman.github.com || test -d /usr/share/gnome-shell/extensions/search-light@icedman.github.com" \
  --install "_install_gnome_extension 5489 'Search Light'" \
  --manual "gext install 5489" \
  --needs "gnome-extensions-cli" \
  --default no
