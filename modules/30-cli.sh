#!/usr/bin/env bash
# 30-cli.sh — the daily-driver command line tools.

register_group cli "CLI Tools" \
  "Search, git, file browsing, disk usage. Replace GUI habits one at a time."

# --- search & navigation ---

register_pkg \
  --id ripgrep \
  --name "ripgrep" \
  --desc "rg — grep the whole repo in milliseconds" \
  --group cli \
  --check "command -v rg" \
  --install "install_apt ripgrep" \
  --manual "sudo apt install ripgrep" \
  --default yes

register_pkg \
  --id fd \
  --name "fd" \
  --desc "Fast, sane 'find'. Ubuntu names the binary fdfind; we symlink fd" \
  --group cli \
  --check "command -v fd || command -v fdfind" \
  --install "install_apt fd-find" \
  --config "symlink_bin fdfind fd" \
  --manual "sudo apt install fd-find && ln -s \$(which fdfind) ~/.local/bin/fd" \
  --default yes

register_pkg \
  --id fzf \
  --name "fzf" \
  --desc "Fuzzy finder — the glue that connects every other tool" \
  --group cli \
  --check "command -v fzf" \
  --install "install_apt fzf" \
  --manual "sudo apt install fzf" \
  --default yes

register_pkg \
  --id bat \
  --name "bat" \
  --desc "cat with syntax highlighting; used as the fzf previewer" \
  --group cli \
  --check "command -v bat || command -v batcat" \
  --install "install_apt bat" \
  --config "symlink_bin batcat bat" \
  --manual "sudo apt install bat && ln -s \$(which batcat) ~/.local/bin/bat" \
  --default yes

register_pkg \
  --id eza \
  --name "eza" \
  --desc "Modern ls with git status columns" \
  --group cli \
  --check "command -v eza" \
  --install "_install_eza" \
  --manual "See https://github.com/eza-community/eza/blob/main/INSTALL.md" \
  --default yes

_install_eza() {
  # eza is in Ubuntu 24.04+ universe; fall back to the upstream repo otherwise.
  if apt-cache policy eza 2>/dev/null | grep -q 'Candidate: [0-9]'; then
    install_apt eza
    return $?
  fi
  add_apt_key "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" "gierens"
  add_apt_repo "gierens" "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main"
  install_apt eza
}

register_pkg \
  --id jq \
  --name "jq" \
  --desc "JSON processor — indispensable for API work" \
  --group cli \
  --check "command -v jq" \
  --install "install_apt jq" \
  --manual "sudo apt install jq" \
  --default yes

# --- disk usage (your 500GB is the real constraint) ---

register_pkg \
  --id dust \
  --name "dust" \
  --desc "Instant 'what is eating my disk' tree view" \
  --group cli \
  --check "command -v dust" \
  --install "install_gh_deb bootandy/dust \"du-dust_.*_\${DEB_ARCH}\\.deb\$\"" \
  --manual "Download the .deb from https://github.com/bootandy/dust/releases" \
  --default yes

register_pkg \
  --id ncdu \
  --name "ncdu" \
  --desc "Interactive disk usage browser with delete support" \
  --group cli \
  --check "command -v ncdu" \
  --install "install_apt ncdu" \
  --manual "sudo apt install ncdu" \
  --default yes

# --- git ---

register_pkg \
  --id delta \
  --name "delta" \
  --desc "Syntax-highlighted git diffs with side-by-side mode" \
  --group cli \
  --check "command -v delta" \
  --install "install_gh_deb dandavison/delta \"git-delta_.*_\${DEB_ARCH}\\.deb\$\"" \
  --manual "Download the .deb from https://github.com/dandavison/delta/releases" \
  --default yes

register_pkg \
  --id lazygit \
  --name "lazygit" \
  --desc "Git TUI — stage hunks and rebase faster than any GUI" \
  --group cli \
  --check "command -v lazygit" \
  --install "install_gh_tarball jesseduffield/lazygit \"[Ll]inux_\${GNU_ARCH}\\.tar\\.gz\$\" lazygit" \
  --manual "Download from https://github.com/jesseduffield/lazygit/releases" \
  --default yes

register_pkg \
  --id gh \
  --name "gh" \
  --desc "GitHub CLI — PRs, issues and reviews without the browser" \
  --group cli \
  --check "command -v gh" \
  --install "_install_gh" \
  --manual "See https://github.com/cli/cli/blob/trunk/docs/install_linux.md" \
  --note "Run 'gh auth login' to authenticate." \
  --default yes

_install_gh() {
  add_apt_key_raw "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "githubcli"
  add_apt_repo "github-cli" \
    "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main"
  install_apt gh
}

# --- task running & docs ---

register_pkg \
  --id just \
  --name "just" \
  --desc "Per-project command runner — replaces IDE run configurations" \
  --group cli \
  --check "command -v just" \
  --install "install_gh_tarball casey/just \"\${GNU_ARCH}-unknown-linux-musl\\.tar\\.gz\$\" just" \
  --manual "Download from https://github.com/casey/just/releases" \
  --default yes

register_pkg \
  --id tealdeer \
  --name "tldr" \
  --desc "Practical command examples — use instead of man pages" \
  --group cli \
  --check "command -v tldr" \
  --install "install_gh_binary tealdeer-rs/tealdeer \"tealdeer-linux-\${GNU_ARCH}-musl\$\" tldr" \
  --config "run 'tldr --update' || true" \
  --manual "Download from https://github.com/tealdeer-rs/tealdeer/releases" \
  --default yes

register_pkg \
  --id yazi \
  --name "yazi" \
  --desc "TUI file manager — good bridge away from Nautilus" \
  --group cli \
  --check "command -v yazi" \
  --install "install_gh_tarball sxyazi/yazi \"\${GNU_ARCH}-unknown-linux-musl\\.zip\$\" yazi ya" \
  --manual "Download from https://github.com/sxyazi/yazi/releases" \
  --default no

register_pkg \
  --id chezmoi \
  --name "chezmoi" \
  --desc "Dotfile manager — set this up before you configure anything else" \
  --group cli \
  --check "command -v chezmoi" \
  --install "install_script https://get.chezmoi.io -b \$HOME/.local/bin" \
  --manual "sh -c \"\$(curl -fsLS get.chezmoi.io)\" -- -b ~/.local/bin" \
  --note "Start your dotfile repo with: chezmoi init --apply <your-github-username>" \
  --default yes
