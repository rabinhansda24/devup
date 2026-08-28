#!/usr/bin/env bash
# What ff offers as candidates: the right files, from the right root, and a
# useful error when the root is not usable.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

if ! command -v fd >/dev/null 2>&1 && ! command -v fdfind >/dev/null 2>&1; then
  printf '    SKIP no fd/fdfind installed\n'
  exit 0
fi

SB="$(new_sandbox)"
BIN="$SB/bin"
make_project "$SB/proj"
install_fzf_stub "$BIN" dump
install_editor_stub "$BIN" nano

export FF_TEST_LIST="$SB/list.txt"
export FF_EDITOR_LOG="$SB/editor.log"

# candidates <cwd> [args...] — the list ff handed to fzf.
candidates() {
  local cwd="$1"; shift
  : >"$FF_TEST_LIST"
  ( cd "$cwd" && PATH="$BIN:$PATH" HOME="$SB" "$FF" "$@" >/dev/null 2>&1 )
  cat "$FF_TEST_LIST"
}

# --- searching the current directory ---
list="$(candidates "$SB/proj")"
assert_contains     "file in the current directory is offered"   "$list" "top.txt"
assert_contains     "nested file is offered"                     "$list" "deep/deeper/nested.txt"
assert_contains     "hidden file is offered"                     "$list" ".hidden.txt"
assert_contains     "filename with spaces is offered"            "$list" "file with spaces.txt"
assert_contains     "unicode filename is offered"                "$list" "ünïcødé-ファイル.txt"
assert_contains     "quotes and brackets in a name are offered"  "$list" "quote'br[ack]et.txt"
assert_not_contains ".git contents are excluded"                 "$list" ".git/config"

# --- 'ff .' behaves like bare ff ---
assert_eq "'ff .' matches bare ff" "$list" "$(candidates "$SB/proj" .)"

# --- the search must not escape the requested root ---
# A symlink to somewhere else is the way a current-directory search silently
# turns into a $HOME (or /) search.
mkdir -p "$SB/outside"
printf 'private\n' >"$SB/outside/SECRET.txt"
ln -s "$SB/outside" "$SB/proj/link-to-outside"
list="$(candidates "$SB/proj")"
assert_not_contains "a symlinked directory is not traversed" "$list" "SECRET.txt"
rm -f "$SB/proj/link-to-outside"

# --- explicit roots ---
list="$(candidates "$SB" "$SB/proj/deep")"
assert_contains     "absolute PATH argument is searched"      "$list" "nested.txt"
assert_not_contains "absolute PATH argument is not exceeded"  "$list" "top.txt"

list="$(candidates "$SB/proj" "deep")"
assert_contains     "relative PATH argument is searched"      "$list" "nested.txt"
assert_not_contains "relative PATH argument is not exceeded"  "$list" "top.txt"

list="$(candidates "$SB/proj" "sub dir")"
assert_contains     "PATH argument containing spaces works"   "$list" "file with spaces.txt"
assert_not_contains "PATH argument with spaces is not exceeded" "$list" "top.txt"

# --- invalid roots must explain themselves ---
err="$( ( cd "$SB/proj" && PATH="$BIN:$PATH" HOME="$SB" "$FF" "$SB/no-such-dir" 2>&1 >/dev/null ) )"
rc=$( ( cd "$SB/proj" && PATH="$BIN:$PATH" HOME="$SB" "$FF" "$SB/no-such-dir" >/dev/null 2>&1 ); echo $? )
assert_rc_not     "a nonexistent PATH does not exit 0"        0 "$rc"
assert_contains   "a nonexistent PATH is reported"            "$err" "no-such-dir"

err="$( ( cd "$SB/proj" && PATH="$BIN:$PATH" HOME="$SB" "$FF" "$SB/proj/top.txt" 2>&1 >/dev/null ) )"
rc=$( ( cd "$SB/proj" && PATH="$BIN:$PATH" HOME="$SB" "$FF" "$SB/proj/top.txt" >/dev/null 2>&1 ); echo $? )
assert_rc_not     "a regular file as PATH does not exit 0"    0 "$rc"
assert_contains   "a regular file as PATH is reported"        "$err" "top.txt"

# --- it must not fall back to searching from somewhere else ---
: >"$FF_TEST_LIST"
( cd "$SB/proj/deep" && PATH="$BIN:$PATH" HOME="$SB" "$FF" >/dev/null 2>&1 )
list="$(cat "$FF_TEST_LIST")"
assert_contains     "search is rooted at the current directory"     "$list" "nested.txt"
assert_not_contains "search does not climb above the current dir"   "$list" "top.txt"

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
