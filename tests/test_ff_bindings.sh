#!/usr/bin/env bash
# The Ctrl-F bindings devup writes into ~/.zshrc and ~/.bashrc.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SB="$(new_sandbox)"
BIN="$SB/bin"
mkdir -p "$BIN"
make_stub "$BIN" ff 'exit 0'

# Pre-existing user content that must survive untouched.
printf '%s\n' '# my own zshrc' 'export MY_ZSH_MARKER=1' >"$SB/.zshrc"
printf '%s\n' '# my own bashrc' 'export MY_BASH_MARKER=1' >"$SB/.bashrc"

configure() { PATH="$BIN:$PATH" devup_sh "$SB" '_configure_file_finder' >/dev/null 2>&1; }

configure
assert_contains "existing .zshrc content is kept"  "$(cat "$SB/.zshrc")"  "MY_ZSH_MARKER"
assert_contains "existing .bashrc content is kept" "$(cat "$SB/.bashrc")" "MY_BASH_MARKER"
assert_contains "a marked block is written to .zshrc"  "$(cat "$SB/.zshrc")"  ">>> devup:file-finder >>>"
assert_contains "a marked block is written to .bashrc" "$(cat "$SB/.bashrc")" ">>> devup:file-finder >>>"

# --- the generated blocks have to parse in their own shell ---
if bash -n "$SB/.bashrc" 2>/dev/null; then ok "the generated .bashrc parses"
else notok "the generated .bashrc parses"; fi
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$SB/.zshrc" 2>/dev/null; then ok "the generated .zshrc parses"
  else notok "the generated .zshrc parses"; fi
else
  printf '    SKIP zsh not installed\n'
fi

# --- re-running must not stack up blocks or bindings ---
before_zsh="$(cat "$SB/.zshrc")"; before_bash="$(cat "$SB/.bashrc")"
configure; configure
assert_eq ".zshrc is unchanged by re-running config"  "$before_zsh"  "$(cat "$SB/.zshrc")"
assert_eq ".bashrc is unchanged by re-running config" "$before_bash" "$(cat "$SB/.bashrc")"
assert_eq "exactly one block in .zshrc"  1 "$(grep -c '>>> devup:file-finder >>>' "$SB/.zshrc")"
assert_eq "exactly one block in .bashrc" 1 "$(grep -c '>>> devup:file-finder >>>' "$SB/.bashrc")"

# --- Ctrl-F must actually be bound, in every keymap the user might be in ---
bash_binds() { # <keymap>
  HOME="$SB" PATH="$BIN:$PATH" bash -i -c "bind -m $1 -X" 2>/dev/null | grep -c '\\C-f' || true
}
assert_eq "bash binds Ctrl-F once in emacs"      1 "$(bash_binds emacs-standard)"
assert_eq "bash binds Ctrl-F once in vi-insert"  1 "$(bash_binds vi-insert)"
assert_eq "bash binds Ctrl-F once in vi-command" 1 "$(bash_binds vi-command)"

# Alt-Shift-F arrives as ESC F. Ctrl-Shift-F cannot be used for this: a terminal
# sends the same 0x06 for it as for Ctrl-F, so the two are indistinguishable
# without per-terminal configuration.
bash_global_binds() { # <keymap>
  HOME="$SB" PATH="$BIN:$PATH" bash -i -c "bind -m $1 -X" 2>/dev/null \
    | grep -c '_devup_global_finder_widget' || true
}
assert_eq "bash binds Alt-Shift-F once in emacs"      1 "$(bash_global_binds emacs-standard)"
assert_eq "bash binds Alt-Shift-F once in vi-insert"  1 "$(bash_global_binds vi-insert)"
assert_eq "bash binds Alt-Shift-F once in vi-command" 1 "$(bash_global_binds vi-command)"

# The two keys must stay distinct: one searches here, the other searches $HOME.
local_target="$(HOME="$SB" PATH="$BIN:$PATH" bash -i -c 'bind -m emacs-standard -X' 2>/dev/null | grep '\\C-f')"
assert_contains     "Ctrl-F is still the current-directory finder" "$local_target" "_devup_file_finder_widget"
assert_not_contains "Ctrl-F did not become the global finder"      "$local_target" "_devup_global_finder_widget"

if command -v zsh >/dev/null 2>&1; then
  zsh_widget() { # <keymap>
    HOME="$SB" PATH="$BIN:$PATH" zsh -i -c "bindkey -M $1 '^F'" 2>/dev/null
  }
  assert_contains "zsh binds Ctrl-F in emacs" "$(zsh_widget emacs)" "_devup_file_finder_widget"
  assert_contains "zsh binds Ctrl-F in viins" "$(zsh_widget viins)" "_devup_file_finder_widget"
  assert_contains "zsh binds Ctrl-F in vicmd" "$(zsh_widget vicmd)" "_devup_file_finder_widget"

  zsh_global() { # <keymap>
    HOME="$SB" PATH="$BIN:$PATH" zsh -i -c "bindkey -M $1 '^[F'" 2>/dev/null
  }
  assert_contains "zsh binds Alt-Shift-F in emacs" "$(zsh_global emacs)" "_devup_global_finder_widget"
  assert_contains "zsh binds Alt-Shift-F in viins" "$(zsh_global viins)" "_devup_global_finder_widget"
  assert_contains "zsh binds Alt-Shift-F in vicmd" "$(zsh_global vicmd)" "_devup_global_finder_widget"
  assert_not_contains "zsh Ctrl-F is not the global finder" "$(zsh_widget emacs)" "_devup_global_finder_widget"
fi

# --- a non-interactive shell that sources .bashrc must stay quiet ---
# Plenty of tooling does `bash -c '. ~/.bashrc; ...'`, and `bind` complains
# loudly there unless the block guards on being interactive.
noise="$(HOME="$SB" PATH="$BIN:$PATH" bash -c ". \"$SB/.bashrc\"" 2>&1 >/dev/null)"
assert_eq "sourcing .bashrc non-interactively is silent" "" "$noise"

# --- the binding must not depend on ff being on PATH when the rc file loads ---
# ~/.local/bin often joins PATH later in the rc file than this block runs.
assert_eq "bash still binds Ctrl-F when ff is not yet on PATH" 1 \
  "$(HOME="$SB" PATH="/usr/bin:/bin" bash -i -c 'bind -m emacs-standard -X' 2>/dev/null | grep -c '\\C-f' || true)"

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
