#!/usr/bin/env bash
# The whole pipeline with the real fd and the real fzf, no stubs in between.
#
# fzf's --select-1/--exit-0 let it resolve a query and exit without ever drawing
# the interface, which is what makes an end-to-end run testable here. Only the
# editor is a stub, so the developer's own editor never opens.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

if ! command -v fzf >/dev/null 2>&1; then
  printf '    SKIP fzf not installed\n'; exit 0
fi
if ! command -v fd >/dev/null 2>&1 && ! command -v fdfind >/dev/null 2>&1; then
  printf '    SKIP no fd/fdfind installed\n'; exit 0
fi

SB="$(new_sandbox)"
BIN="$SB/bin"
make_project "$SB/proj"
install_editor_stub "$BIN" nano
export FF_EDITOR_LOG="$SB/editor.log"

find_and_open() { # <query> [PATH] -> sets $rc
  rm -f "$FF_EDITOR_LOG" "$FF_EDITOR_LOG.name"
  local query="$1"; shift
  ( cd "$SB/proj" \
    && PATH="$BIN:$PATH" HOME="$SB" \
       FZF_DEFAULT_OPTS="--query=$query --select-1 --exit-0" \
       "$FF" "$@" </dev/null >/dev/null 2>&1 )
  rc=$?
}

find_and_open "top.txt"
assert_rc       "a real fzf selection exits 0"           0 "$rc"
assert_eq       "the editor gets exactly one argument"   1 "$(editor_args | wc -l)"
assert_eq       "the editor gets an absolute path"       "$SB/proj/top.txt" "$(editor_args)"
assert_eq       "nano is what gets launched"             "nano" "$(editor_name)"

# fzf reads FZF_DEFAULT_OPTS as a word list, so the query itself cannot contain
# spaces here; the file it matches still does, which is what is under test.
find_and_open "spaces.txt"
assert_eq "a filename with spaces survives the pipeline" "$SB/proj/sub dir/file with spaces.txt" "$(editor_args)"

find_and_open "ünïcødé"
assert_eq "a unicode filename survives the pipeline" "$SB/proj/ünïcødé-ファイル.txt" "$(editor_args)"

find_and_open "hidden"
assert_eq "a hidden file can be opened" "$SB/proj/.hidden.txt" "$(editor_args)"

find_and_open "deeper/nested"
assert_eq "a nested file can be opened" "$SB/proj/deep/deeper/nested.txt" "$(editor_args)"

# --- nothing matched: leave without opening anything ---
find_and_open "zzz-no-such-file-zzz"
assert_rc "an unmatched query exits 0" 0 "$rc"
if editor_ran; then notok "an unmatched query opens nothing" "editor ran"; else ok "an unmatched query opens nothing"; fi

# --- .git is not reachable through the finder ---
find_and_open ".git/config"
if editor_ran; then notok "the .git directory stays out of reach" "opened $(editor_args)"
else ok "the .git directory stays out of reach"; fi

# --- an explicit root confines the search ---
find_and_open "nested" "deep"
assert_eq "an explicit root still opens its files" "$SB/proj/deep/deeper/nested.txt" "$(editor_args)"

find_and_open "top.txt" "deep"
if editor_ran; then notok "an explicit root hides everything above it" "opened $(editor_args)"
else ok "an explicit root hides everything above it"; fi

# --- the preview fzf would run is the one ff ships ---
out="$( ( cd "$SB/proj" && PATH="$BIN:$PATH" HOME="$SB" "$FF" --preview top.txt 2>&1 ) )"
assert_contains "the preview of a real file shows its contents" "$out" "top level"

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
