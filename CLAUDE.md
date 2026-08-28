# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`devup` — a Bash CLI that provisions a fresh Ubuntu machine into a Go/Rust/Python/TypeScript
development box. Bash rather than a compiled language on purpose: a provisioning tool that needs
a toolchain to build it is circular on a bare install (see README "Design decisions" for the rest
of the non-obvious choices — shared `CARGO_TARGET_DIR`, mold, pnpm, no snaps).

## Layout

```
devup              CLI entrypoint: arg parsing, menus, install engine, doctor/status/list
install.sh         curl|bash bootstrap → clones to ~/.local/share/devup, symlinks ~/.local/bin/devup
lib/core.sh        logging, run(), DRY_RUN, sudo keepalive, write_block, backup_file
lib/registry.sh    register_pkg / register_group, detect_all, resolve_deps
lib/install.sh     install primitives (install_apt, install_gh_deb, install_script, …)
lib/ui.sh          whiptail menus with a plain-numbered-text fallback
modules/[1-7]0-*.sh  package declarations, sourced in lexical order
profiles/*.conf    named package-id lists (fullstack, minimal, terminal-transition, rust-heavy)
configs/           files copied to the user's home (ff, devup-clean, starship.toml, wezterm.lua)
```

## Architecture

**Everything is a registry entry.** Modules never install anything at load time — they call
`register_pkg` to populate parallel associative arrays (`PKG_CHECK`, `PKG_INSTALL`, `PKG_CONFIG`,
`PKG_NEEDS`, …) keyed by package id. `load_modules` sources every module, `detect_all` runs each
`--check` snippet to set `PKG_STATUS` to installed/missing/unknown, and only then does anything
execute. Adding a tool means one `register_pkg` block in a module; `devup` and `lib/` stay untouched.

**`--check` / `--install` / `--config` are eval'd strings, not functions.** They are evaluated at
run time in `run_selection`, so `$DEB_ARCH`/`$GNU_ARCH`/`$OS_CODENAME` must be escaped in the
registration (`\${DEB_ARCH}`) or they expand at load time to nothing. Anything non-trivial goes in
a module-local `_`-prefixed shell function named by `--install`.

**Three-phase lifecycle per package.** `--install` is skipped when `PKG_STATUS` is `installed`;
`--config` runs *unconditionally* on every selected package. That is what makes `devup config <id>`
work standalone, and it means every `--config` must be independently re-runnable — it cannot assume
the install just happened.

**Failures are per-package, not fatal.** The engine records into `RESULT_OK`/`RESULT_SKIP`/
`RESULT_FAIL` and continues. Return non-zero to signal failure; never `exit` from a module. The
codebase deliberately does not rely on `set -e` (`devup` runs `set -uo pipefail` only).

**Dependencies:** `--needs` is expanded by `resolve_deps` (BFS, deduped, re-sorted into
registration order) — so ordering falls out of module filename prefixes plus registration order,
not from the dependency edges themselves.

**Idempotency mechanisms** (in `lib/core.sh`): `write_block` inserts/replaces
`# >>> devup:<marker> >>>` regions in files devup doesn't own; `backup_file` copies to
`<file>.devup-bak.<timestamp>` before replacing one. Use these rather than appending or clobbering.

**Dry-run is a contract.** `run()`, `install_apt`, and the `install_gh_*` helpers honour `DRY_RUN`
for you. Raw shell inside a `--config` function must guard on `${DRY_RUN:-0}` itself and return 0 —
CI dry-runs every registered package, so an unguarded `--config` will make real changes on the
runner.

**Generated shell config is a single managed file.** `_configure_shell_integration`
(`modules/20-shell.sh`) emits `~/.config/devup/shell.sh` conditionally on what is actually
installed, then sources it from `.zshrc`/`.bashrc` via a marked block. User tweaks belong in
`~/.config/devup/local.sh`, which it sources last. Regenerate with
`devup config shell-integration`.

## Commands

```bash
./devup                              # interactive menu
./devup list                         # every package + install state
./devup status                       # machine summary + per-group coverage
./devup doctor                       # diagnose PATH, shell wiring, docker group, cargo target, fonts
./devup --dry-run -p fullstack --auto --yes --no-tui   # preview; changes nothing
./devup install ripgrep fzf          # specific ids
./devup config <id>                  # re-run one --config step
```

Log: `~/.local/state/devup/devup.log`. `-v/--verbose` streams command output instead of buffering it.

## Testing

No install-level harness (it would need throwaway VMs). CI (`.github/workflows/ci.yml`) runs three
jobs — lint, smoke on ubuntu-22.04/24.04, and a real `minimal` install — and these are the same
checks to run locally:

```bash
# syntax + lint
for f in devup install.sh configs/devup-clean configs/ff lib/*.sh modules/*.sh; do bash -n "$f" || echo "FAIL: $f"; done
shellcheck -S warning -x devup install.sh configs/devup-clean configs/ff lib/*.sh modules/*.sh

# detection, then a dry run of just your package
./devup list
./devup --dry-run --only your-id --yes --no-tui

# every registered package must dry-run clean (what CI enforces)
./devup --dry-run --auto --yes --no-tui

# real run in a throwaway container
docker run -it --rm -v "$PWD:/devup" ubuntu:24.04 bash -c \
  'apt-get update -qq && apt-get install -y -qq sudo whiptail curl git && /devup/devup'

# idempotency — the second run must print "unchanged"
./devup install your-id --yes && ./devup install your-id --yes
```

If you touched `modules/20-shell.sh`, also confirm the generated file still parses:
`./devup config shell-integration --yes && bash -n ~/.config/devup/shell.sh`.

## Conventions

`CONTRIBUTING.md` is the reference for `register_pkg` fields and the full list of install
primitives. Beyond it: two spaces, no tabs; quote expansions; `_`-prefix module-local helpers;
`--desc` under ~70 chars so it fits the whiptail menu, and say *why* someone wants the tool rather
than what it is. Prefer apt when the version is usable, then a vendor `.deb`, then a vendor
script, then a tarball — never a snap. Never alias over standard commands (`cat`, `du`).

## MCP note

The root `CLAUDE.md` at `/home/rabinhansda/CLAUDE.md` directs you to the `code-review-graph` MCP
tools before Grep/Read. That graph is currently empty for this directory (0 nodes/edges), so
Grep/Glob/Read is the working path here until it has been indexed.
