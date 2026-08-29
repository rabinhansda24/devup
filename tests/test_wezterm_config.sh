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

# A steady cursor is easy to lose on a busy screen. The easing matters as much
# as the style: WezTerm's default fades the cursor rather than blinking it.
assert_contains "the cursor style blinks"        "$body" "config.default_cursor_style = 'BlinkingBlock'"
assert_contains "the blink rate is set"          "$body" "config.cursor_blink_rate ="
assert_contains "the blink is on/off, not a fade (in)"  "$body" "config.cursor_blink_ease_in = 'Constant'"
assert_contains "the blink is on/off, not a fade (out)" "$body" "config.cursor_blink_ease_out = 'Constant'"

if ! command -v wezterm >/dev/null 2>&1; then
  printf '    SKIP wezterm not installed\n'
elif ! wezterm --config-file "$CFG" show-keys >/dev/null 2>&1; then
  # show-keys evaluates the Lua, so it catches a syntax error. It does NOT
  # check the values: it accepts default_cursor_style = 'NotAThing' happily.
  notok "the config is valid Lua" "$(wezterm --config-file "$CFG" show-keys 2>&1 | head -c 300)"
else
  ok "the config is valid Lua"

  # Only starting WezTerm for real validates the settings themselves, and that
  # needs a display. Where there is one, a bad enum shows up as
  # "Configuration Error: ... is not a valid ... variant".
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    launch="$(timeout 30 wezterm --config-file "$CFG" start --always-new-process \
                -- true 2>&1 | grep -i 'configuration error' | head -c 300)"
    if [[ -z "$launch" ]]; then
      ok "wezterm accepts every setting in it"
    else
      notok "wezterm accepts every setting in it" "$launch"
    fi
  else
    printf '    SKIP no display, cannot validate setting values\n'
  fi
fi

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
