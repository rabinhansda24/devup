#!/usr/bin/env bash
# Which editor ff opens, and what it does when there is none.
#
# These run with PATH set to the stub directory only, so the developer's real
# nano, vi and editor configuration are never involved.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SB="$(new_sandbox)"
BIN="$SB/bin"
mkdir -p "$SB/proj"
printf 'top level\n' >"$SB/proj/top.txt"

export FF_TEST_LIST="$SB/list.txt"
export FF_EDITOR_LOG="$SB/editor.log"
export FF_TEST_MATCH="top.txt"

isolate_bin "$BIN"

# A stand-in for fd that always offers the one file.
make_stub "$BIN" fd 'printf "%s\n" "./top.txt"'
install_fzf_stub "$BIN" match

run_isolated() { # -> sets $rc and $err; PATH contains only the stubs
  rm -f "$FF_EDITOR_LOG" "$FF_EDITOR_LOG.name"
  err="$( ( cd "$SB/proj" && PATH="$BIN" HOME="$SB" bash "$FF" 2>&1 >/dev/null ) )"
  rc=$( ( cd "$SB/proj" && PATH="$BIN" HOME="$SB" bash "$FF" >/dev/null 2>&1 ); echo $? )
}

# --- nano wins when it is there ---
install_editor_stub "$BIN" nano
install_editor_stub "$BIN" vi
run_isolated
assert_rc "opening with nano exits 0" 0 "$rc"
assert_eq "nano is preferred"         "nano" "$(editor_name)"

# --- vi is the fallback ---
rm -f "$BIN/nano"
run_isolated
assert_rc "opening with vi exits 0"   0 "$rc"
assert_eq "vi is used when nano is missing" "vi" "$(editor_name)"

# vi implementations disagree about "--": busybox vi treats it as a filename
# and opens the wrong buffer, so ff must not rely on it.
assert_eq       "vi is given exactly one argument"  1 "$(editor_args | wc -l)"
assert_not_contains "vi is not given a bare --"     "$(editor_args)" "--"

# --- neither: say so, and do not pretend it worked ---
rm -f "$BIN/vi"
run_isolated
assert_rc_not   "no editor available does not exit 0" 0 "$rc"
assert_contains "no editor available is explained"    "$err" "nano"

# --- missing search tools are reported too ---
install_editor_stub "$BIN" nano
mv "$BIN/fd" "$SB/fd.hidden"
run_isolated
assert_rc_not   "a missing fd does not exit 0"  0 "$rc"
assert_contains "a missing fd is explained"     "$err" "fd"
mv "$SB/fd.hidden" "$BIN/fd"

# Ubuntu ships fd as fdfind; ff must accept that name.
mv "$BIN/fd" "$BIN/fdfind"
run_isolated
assert_rc "fdfind is accepted in place of fd" 0 "$rc"
mv "$BIN/fdfind" "$BIN/fd"

mv "$BIN/fzf" "$SB/fzf.hidden"
run_isolated
assert_rc_not   "a missing fzf does not exit 0" 0 "$rc"
assert_contains "a missing fzf is explained"    "$err" "fzf"
mv "$SB/fzf.hidden" "$BIN/fzf"

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
