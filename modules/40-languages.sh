#!/usr/bin/env bash
# 40-languages.sh — toolchains for Go, Rust, Python, Node.
#
# Deliberately NOT from apt: distro language runtimes are always stale and you
# need per-project versions anyway.

register_group lang "Language Toolchains" \
  "Go, Rust, Python, Node — version-managed, with build caches configured."

register_pkg \
  --id mise \
  --name "mise" \
  --desc "One version manager for Go, Node, Python; auto-switches per project" \
  --group lang \
  --check "command -v mise || test -x \$HOME/.local/bin/mise" \
  --install "install_script https://mise.run" \
  --manual "curl https://mise.run | sh" \
  --note "mise activates via ~/.config/devup/shell.sh — open a new shell before using it." \
  --default yes

register_pkg \
  --id go \
  --name "Go" \
  --desc "Latest stable Go via mise" \
  --group lang \
  --check "command -v go" \
  --install "_mise_use go@latest" \
  --config "_configure_go" \
  --manual "mise use -g go@latest" \
  --needs "mise" \
  --default yes

register_pkg \
  --id node \
  --name "Node.js" \
  --desc "Current LTS Node via mise" \
  --group lang \
  --check "command -v node" \
  --install "_mise_use node@lts" \
  --manual "mise use -g node@lts" \
  --needs "mise" \
  --default yes

register_pkg \
  --id pnpm \
  --name "pnpm" \
  --desc "Node package manager with a shared store — the biggest disk win" \
  --group lang \
  --check "command -v pnpm" \
  --install "_install_pnpm" \
  --manual "corepack enable pnpm  # or: curl -fsSL https://get.pnpm.io/install.sh | sh -" \
  --needs "node" \
  --default yes

register_pkg \
  --id uv \
  --name "uv" \
  --desc "Replaces pyenv + pip + venv + pip-tools, and is far faster" \
  --group lang \
  --check "command -v uv" \
  --install "install_script https://astral.sh/uv/install.sh" \
  --manual "curl -LsSf https://astral.sh/uv/install.sh | sh" \
  --note "Create envs with 'uv venv' and install with 'uv pip install'. 'uv python install 3.12' manages interpreters." \
  --default yes

register_pkg \
  --id rust \
  --name "Rust" \
  --desc "rustup toolchain plus clippy and rust-analyzer" \
  --group lang \
  --check "command -v rustc || test -x \$HOME/.cargo/bin/rustc" \
  --install "_install_rust" \
  --config "_configure_cargo" \
  --manual "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" \
  --needs "build-essential" \
  --default yes

_install_rust() {
  # rustup-init wants a comma-separated component list (space-separated values
  # are parsed as positional args and abort the install)
  install_script https://sh.rustup.rs -y --no-modify-path --component clippy,rustfmt,rust-analyzer || return 1
  if [[ "${DRY_RUN:-0}" != "1" && -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
}

register_pkg \
  --id mold \
  --name "mold" \
  --desc "Drastically faster linker — the top Rust build-time win on modest CPUs" \
  --group lang \
  --check "command -v mold" \
  --install "install_apt mold clang" \
  --manual "sudo apt install mold clang" \
  --default yes

register_pkg \
  --id sccache \
  --name "sccache" \
  --desc "Shared compilation cache across Rust projects" \
  --group lang \
  --check "command -v sccache" \
  --install "install_gh_tarball mozilla/sccache \"\${GNU_ARCH}-unknown-linux-musl\\.tar\\.gz\$\" sccache" \
  --manual "Download from https://github.com/mozilla/sccache/releases" \
  --default no

# Wires up the shared target dir, mold, and sccache in one cargo config.
# This is the setting that keeps four language ecosystems inside 500GB.
_configure_cargo() {
  local cfg="$HOME/.cargo/config.toml"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] configure ${cfg} (shared target dir, mold, sccache)${C_RESET}"
    return 0
  fi

  mkdir -p "$HOME/.cargo" "$HOME/.cache/cargo-target"

  if [[ -f "$cfg" ]] && grep -q "devup" "$cfg" 2>/dev/null; then
    debug "cargo config already managed by devup"
    return 0
  fi
  [[ -f "$cfg" ]] && backup_file "$cfg"

  {
    cat <<'CARGO'
# Managed by devup.

[build]
# One shared target directory instead of a 3-5GB target/ per project.
# This is the single most effective disk saving for multi-repo Rust work.
target-dir = "~/.cache/cargo-target"

CARGO

    if command -v mold >/dev/null 2>&1 && command -v clang >/dev/null 2>&1; then
      cat <<'MOLD'
[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]

[target.aarch64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]

MOLD
    fi

    if command -v sccache >/dev/null 2>&1; then
      cat <<'SCCACHE'
[build.rustc-wrapper]
# sccache is enabled below; comment out if you hit odd cache misses.
SCCACHE
      printf 'rustc-wrapper = "%s"\n\n' "$(command -v sccache)"
    fi

    cat <<'PROFILE'
[profile.dev]
# Full debuginfo is slow to write and eats disk. Line tables keep backtraces
# useful while cutting link time substantially.
debug = "line-tables-only"

[profile.dev.package."*"]
# Dependencies rarely need debug symbols.
debug = false
opt-level = 1
PROFILE
  } >"$cfg"

  success "Wrote $cfg (shared target dir + fast linker)"
}

_configure_go() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] ensure GOPATH/bin exists${C_RESET}"
    return 0
  fi
  mkdir -p "${GOPATH:-$HOME/go}/bin"
}

_mise_use() {
  local spec="$1"
  local mise_bin
  mise_bin="$(command -v mise 2>/dev/null || echo "$HOME/.local/bin/mise")"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] mise use -g ${spec}${C_RESET}"
    return 0
  fi
  [[ -x "$mise_bin" ]] || { error "mise not found; install it first"; return 1; }
  run "'$mise_bin' use -g --yes $spec"
}

_install_pnpm() {
  # corepack ships with Node and pins pnpm per project, which is preferable.
  if command -v corepack >/dev/null 2>&1; then
    run "corepack enable pnpm" && return 0
  fi
  install_script https://get.pnpm.io/install.sh
}
