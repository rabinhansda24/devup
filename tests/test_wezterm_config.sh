#!/usr/bin/env bash
# configs/wezterm.lua is the user's terminal. A syntax error here does not fail
# a build, it fails their next login, so check that WezTerm can actually load it
# and that the settings people notice are the ones intended.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

CFG="$REPO_ROOT/configs/wezterm.lua"
assert_file_exists "configs/wezterm.lua is present" "$CFG"
body="$(cat "$CFG")"

# WezTerm launches at 80x24 unless told otherwise; 112 is that width plus 40%.
assert_contains "the initial width is set"   "$body" "config.initial_cols = 112"
assert_contains "the window is 90% opaque"   "$body" "config.window_background_opacity = 0.9"
assert_contains "text cells stay opaque"     "$body" "config.text_background_opacity = 1.0"

# Rows were deliberately left alone: only the width was too tight.
assert_not_contains "the initial height is left at the default" "$body" "initial_rows"

if command -v wezterm >/dev/null 2>&1; then
  # show-keys parses and evaluates the whole file, so it fails on a bad config.
  if wezterm --config-file "$CFG" show-keys >/dev/null 2>&1; then
    ok "wezterm loads the config without error"
  else
    notok "wezterm loads the config without error" \
      "$(wezterm --config-file "$CFG" show-keys 2>&1 | head -c 300)"
  fi
else
  printf '    SKIP wezterm not installed\n'
fi

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
