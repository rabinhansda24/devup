# Contributing

Adding a tool is usually about ten lines in a file under `modules/`. You
shouldn't need to touch `devup` or `lib/` at all.

## Project layout

```
devup                  CLI entrypoint — arg parsing, menus, install engine
install.sh             curl|bash bootstrap
lib/
  core.sh              logging, run(), dry-run, sudo, marked file blocks
  registry.sh          register_pkg / register_group, detection, deps
  install.sh           install primitives (apt, GitHub releases, repos)
  ui.sh                whiptail menus + plain-text fallback
modules/
  10-base.sh           compilers, git, zsh
  20-shell.sh          prompt, history, shell wiring
  30-cli.sh            ripgrep, fzf, lazygit, …
  40-languages.sh      mise, rust, uv, pnpm, mold
  50-containers.sh     docker
  60-terminal.sh       wezterm, fonts
  70-maintenance.sh    backups, cleanup
profiles/*.conf        named package lists
configs/               templates copied to the user's home
```

Modules are sourced in lexical order, so `10-` runs before `20-`. Order matters
only for dependencies.

## Adding a tool

Add a `register_pkg` block to the relevant module:

```bash
register_pkg \
  --id ripgrep \
  --name "ripgrep" \
  --desc "rg — grep the whole repo in milliseconds" \
  --group cli \
  --check "command -v rg" \
  --install "install_apt ripgrep" \
  --manual "sudo apt install ripgrep" \
  --default yes
```

### Fields

| Field | Required | Meaning |
|---|---|---|
| `--id` | yes | Stable identifier. Used in profiles and on the CLI. |
| `--name` | yes | Display name. |
| `--desc` | yes | One line. Say *why* someone wants it, not just what it is. |
| `--group` | yes | Must match a `register_group` id. |
| `--check` | yes | Shell snippet; exit 0 means already installed. |
| `--install` | yes | Shell snippet that installs it. |
| `--config` | no | Runs after install. Must be safe to re-run alone. |
| `--manual` | no | Copy-pasteable instructions for `--manual` mode. |
| `--note` | no | Shown in the post-run summary (e.g. "log out and back in"). |
| `--needs` | no | Space-separated ids installed first. |
| `--default` | no | `yes` pre-ticks it in the menu. Default `no`. |

### Install primitives

Use these rather than raw shell where possible:

```bash
install_apt pkg1 pkg2                       # apt, with one shared update
install_gh_deb owner/repo 'regex\.deb$'     # latest release .deb
install_gh_tarball owner/repo 'regex$' bin  # extract binaries → /usr/local/bin
install_gh_binary owner/repo 'regex$' name  # bare executable asset
install_script https://example.com/i.sh -y  # vendor installer, piped to sh
add_apt_key url keyring-name                # armoured key → /etc/apt/keyrings
add_apt_key_raw url keyring-name            # already-binary keyring
add_apt_repo name "deb [...] ... main"      # sources.list.d entry + update
symlink_bin fdfind fd                       # for Ubuntu's renamed binaries
cargo_install crate
```

Architecture is available as `$DEB_ARCH` (amd64/arm64), `$GNU_ARCH`
(x86_64/aarch64), and `$OS_CODENAME` / `$OS_VERSION` for the Ubuntu release.

Because `--install` is `eval`'d at run time, escape those variables in the
registration so they expand then, not at load time:

```bash
  --install "install_gh_deb bootandy/dust \"du-dust_.*_\${DEB_ARCH}\\.deb\$\""
```

For anything more involved, write a shell function in the same module and name it
in `--install`:

```bash
register_pkg --id eza --install "_install_eza" ...

_install_eza() {
  if apt-cache policy eza 2>/dev/null | grep -q 'Candidate: [0-9]'; then
    install_apt eza
    return $?
  fi
  add_apt_key "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" gierens
  add_apt_repo gierens "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main"
  install_apt eza
}
```

Prefix module-local helpers with `_` so they don't collide.

## Rules

**Respect `--dry-run`.** Anything going through `run()`, `install_apt` or the
`install_gh_*` helpers is handled for you. If you write raw shell in a `--config`
function, guard it:

```bash
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf '%s\n' "${C_DIM}  [dry-run] what this would do${C_RESET}"
  return 0
fi
```

**Never clobber a user's config.** Use `write_block` for additions to files you
don't own, and `backup_file` before replacing one. If a config already exists and
isn't devup's, leave it and warn.

**`--config` must be independently re-runnable.** `devup config <id>` calls it on
its own, so it can't assume the install just happened.

**Prefer apt when the version is usable**, then vendor `.deb`, then a vendor
script, then a tarball. Never a snap.

**No `set -e` reliance.** The engine runs each package in a subshell-ish context
and reports failures without aborting the whole run. Return non-zero to signal
failure; don't call `exit`.

## Testing

There is no install-level test harness (it would need throwaway VMs), so:

```bash
# 1. Syntax
for f in devup install.sh configs/devup-clean lib/*.sh modules/*.sh; do
  bash -n "$f" || echo "FAIL: $f"
done
shellcheck -S warning devup lib/*.sh modules/*.sh   # if you have it

# 2. Detection — your package should show the right state
./devup list

# 3. Dry run — check the commands look right
./devup --dry-run --only your-package-id --yes --no-tui

# 4. Real run, ideally in a container or VM
docker run -it --rm -v "$PWD:/devup" ubuntu:24.04 bash -c \
  'apt-get update -qq && apt-get install -y -qq sudo whiptail curl git && /devup/devup'

# 5. Idempotency — the second run should report "already installed"
./devup install your-package-id --yes
./devup install your-package-id --yes
```

Please also check the generated shell config still parses if you touched
`20-shell.sh`:

```bash
./devup config shell-integration --yes && bash -n ~/.config/devup/shell.sh
```

## Adding a profile

Drop a file in `profiles/`, one id per line. `# desc:` on the first line shows up
in `devup profiles`.

```
# desc: What this profile is for.
build-essential
ripgrep
fzf
```

## Style

- Tabs are out, two spaces in.
- Quote variable expansions.
- Comments should explain *why*, not restate the command. `--desc` and comments
  that say "why you want this" are the most valuable part of the project.
- Keep descriptions under ~70 characters so they fit the menu.

## Pull requests

One tool or one fix per PR where practical. Mention which Ubuntu version you
tested on, and whether you tested a real install or only `--dry-run`.
