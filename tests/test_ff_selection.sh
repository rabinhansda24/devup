#!/usr/bin/env bash
# What ff does with fzf's answer: open it, or return quietly.
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
install_editor_stub "$BIN" nano

export FF_TEST_LIST="$SB/list.txt"
export FF_EDITOR_LOG="$SB/editor.log"

run_ff() { # <fzf-mode> [match-text] -> sets $rc
  install_fzf_stub "$BIN" "$1"
  export FF_TEST_MATCH="${2:-}"
  rm -f "$FF_EDITOR_LOG" "$FF_EDITOR_LOG.name"
  : >"$FF_TEST_LIST"
  ( cd "$SB/proj" && PATH="$BIN:$PATH" HOME="$SB" "$FF" >/dev/null 2>&1 )
  rc=$?
}

# --- Enter: the selection is opened ---
run_ff match "top.txt"
assert_rc       "a selection exits 0"                    0 "$rc"
assert_eq       "the editor is given exactly one argument" 1 "$(editor_args | wc -l)"
assert_contains "the editor is given the selected file"  "$(editor_args)" "top.txt"

# --- awkward filenames survive the round trip ---
run_ff match "file with spaces.txt"
assert_eq       "a path with spaces stays one argument"  1 "$(editor_args | wc -l)"
assert_contains "a path with spaces reaches the editor"  "$(editor_args)" "file with spaces.txt"

run_ff match "ünïcødé"
assert_eq       "a unicode path stays one argument"      1 "$(editor_args | wc -l)"
assert_contains "a unicode path reaches the editor"      "$(editor_args)" "ünïcødé-ファイル.txt"

run_ff match "quote'br[ack]et"
assert_eq       "quotes and brackets stay one argument"  1 "$(editor_args | wc -l)"
assert_contains "quotes and brackets reach the editor"   "$(editor_args)" "quote'br[ack]et.txt"

# The argument handed to the editor must be openable as-is from ff's directory.
sel="$(editor_args | tail -n1)"
if ( cd "$SB/proj" && [[ -f "$sel" ]] ); then
  ok "the path handed to the editor resolves to a real file"
else
  notok "the path handed to the editor resolves to a real file" "[$sel] does not exist"
fi

# --- Esc / Ctrl-C: nothing is opened, nothing is reported ---
run_ff cancel
assert_rc "cancelling exits 0"        0 "$rc"
if editor_ran; then notok "cancelling opens no editor" "editor ran"; else ok "cancelling opens no editor"; fi

run_ff nomatch
assert_rc "an empty result set exits 0" 0 "$rc"
if editor_ran; then notok "an empty result set opens no editor" "editor ran"; else ok "an empty result set opens no editor"; fi

# --- a genuinely broken fzf is not silently swallowed ---
run_ff broken
assert_rc_not "a failing fzf does not look like success" 0 "$rc"

# --- SIGPIPE: fzf exits as soon as it has a selection, so the producer dies ---
# with SIGPIPE. That is normal, and must not stop the editor from opening.
many="$SB/many"
mkdir -p "$many"
for i in $(seq 1 4000); do printf 'x\n' >"$many/file-$i.txt"; done
install_fzf_stub "$BIN" early
rm -f "$FF_EDITOR_LOG"
( cd "$many" && PATH="$BIN:$PATH" HOME="$SB" "$FF" >/dev/null 2>&1 )
rc=$?
assert_rc "a selection survives SIGPIPE upstream" 0 "$rc"
if editor_ran; then ok "the editor opens even when the producer got SIGPIPE"
else notok "the editor opens even when the producer got SIGPIPE" "editor never ran"; fi

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
