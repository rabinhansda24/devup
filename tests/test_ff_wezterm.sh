#!/usr/bin/env bash
# devup's WezTerm config is what lets Ctrl-Shift-F reach the shell at all.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

CFG="$REPO_ROOT/configs/wezterm.lua"

assert_file_exists "configs/wezterm.lua is present" "$CFG"

# The escape it sends must be the kitty keyboard protocol's encoding of
# Ctrl-Shift-F: CSI 102 ; 6 u — 102 is 'f', 6 is ctrl+shift. Terminals that
# implement the protocol send exactly this, so one shell binding serves both.
assert_contains "Ctrl-Shift-F is mapped" "$(cat "$CFG")" "mods = 'CTRL|SHIFT'"
assert_contains "it sends the CSI-u sequence for Ctrl-Shift-F" "$(cat "$CFG")" '102;6u'

# Overriding WezTerm's built-in Ctrl-Shift-F must not lose scrollback search.
assert_contains "scrollback search is still on LEADER f" "$(cat "$CFG")" \
  "{ key = 'f', mods = 'LEADER', action = act.Search"

# The shell side has to agree with what the terminal sends, or the key does
# nothing at all.
assert_contains "the shell binds the same sequence" \
  "$(cat "$REPO_ROOT/modules/35-file-finder.sh")" '102;6u'

if command -v wezterm >/dev/null 2>&1; then
  keys="$(wezterm --config-file "$CFG" show-keys 2>/dev/null)"
  if [[ -n "$keys" ]]; then
    ok "wezterm loads the config without error"
    assert_contains "wezterm registers the Ctrl-Shift-F send" "$keys" "SendString"
    assert_contains "wezterm still has LEADER f searching"    "$keys" "Search(CaseInSensitiveString"
  else
    notok "wezterm loads the config without error" "show-keys produced nothing"
  fi
else
  printf '    SKIP wezterm not installed\n'
fi

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
