#!/usr/bin/env bash
# 50-containers.sh — Docker from the official repo, not Docker Desktop.

register_group containers "Containers" \
  "Native Docker Engine. Docker Desktop on Linux runs a VM and wastes RAM."

register_pkg \
  --id docker \
  --name "Docker" \
  --desc "Engine, CLI, buildx and compose plugin from Docker's own apt repo" \
  --group containers \
  --check "command -v docker" \
  --install "_install_docker" \
  --config "_configure_docker" \
  --manual "See https://docs.docker.com/engine/install/ubuntu/" \
  --note "Log out and back in (or run 'newgrp docker') before using docker without sudo." \
  --default yes

_install_docker() {
  # Remove the distro packages that conflict with docker-ce.
  local old
  for old in docker.io docker-doc docker-compose podman-docker containerd runc; do
    if dpkg -s "$old" >/dev/null 2>&1; then
      warn "Removing conflicting package: $old"
      run "$SUDO apt-get remove -y -qq $old" || true
    fi
  done

  add_apt_key "https://download.docker.com/linux/ubuntu/gpg" "docker"
  add_apt_repo "docker" \
    "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${OS_CODENAME} stable"
  install_apt docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

_configure_docker() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] add \$USER to docker group + write /etc/docker/daemon.json${C_RESET}"
    return 0
  fi

  # --- rootless-ish convenience: docker group ---
  if getent group docker >/dev/null 2>&1; then
    if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
      debug "$USER is already in the docker group"
    else
      run "$SUDO usermod -aG docker $USER" \
        && success "Added $USER to the docker group (effective next login)"
    fi
  fi

  # --- log rotation: container logs will silently eat tens of GB ---
  local daemon="/etc/docker/daemon.json"
  if [[ -f "$daemon" ]]; then
    if grep -q "max-size" "$daemon" 2>/dev/null; then
      debug "docker log rotation already configured"
    else
      warn "$daemon exists but has no log rotation. Not overwriting it."
      warn "Add manually: \"log-opts\": { \"max-size\": \"10m\", \"max-file\": \"3\" }"
    fi
  else
    run "$SUDO install -m 0755 -d /etc/docker"
    local tmp="${TMP_DIR}/daemon.json"
    cat >"$tmp" <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "20GB"
    }
  }
}
JSON
    run "$SUDO install -m 0644 '$tmp' '$daemon'" \
      && success "Wrote $daemon (log rotation + build cache cap)"
    run "$SUDO systemctl restart docker" || warn "Could not restart docker; restart it manually"
  fi

  run "$SUDO systemctl enable --now docker" || warn "Could not enable the docker service"
}

register_pkg \
  --id lazydocker \
  --name "lazydocker" \
  --desc "Container TUI — replaces the Docker Desktop dashboard" \
  --group containers \
  --check "command -v lazydocker" \
  --install "install_gh_tarball jesseduffield/lazydocker \"Linux_\${GNU_ARCH}\\.tar\\.gz\$\" lazydocker" \
  --manual "Download from https://github.com/jesseduffield/lazydocker/releases" \
  --default yes
