#!/usr/bin/env bash
# Do the keys actually reach the widgets?
#
# `bindkey` and `bind -X` only say what devup asked for. These press the keys at
# a real interactive shell in a pty and check which finder ran — the difference
# between a binding that exists and a binding that works.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

if ! command -v python3 >/dev/null 2>&1; then
  printf '    SKIP python3 not available for the pty harness\n'; exit 0
fi
if ! python3 -c 'import pty' 2>/dev/null; then
  printf '    SKIP this python3 has no pty module\n'; exit 0
fi

SB="$(new_sandbox)"
BIN="$SB/bin"
mkdir -p "$BIN"
# ff records the arguments it was called with, and nothing else: this is about
# key dispatch, not about the finder.
make_stub "$BIN" ff "printf 'ARGS[%s]\\n' \"\$*\" >> '$SB/fired.log'"

PATH="$BIN:$PATH" devup_sh "$SB" '_configure_file_finder' >/dev/null 2>&1

press() { # <shell> <escaped key> -> prints what ff was called with
  rm -f "$SB/fired.log"
  HOME="$SB" PATH="$BIN:/usr/bin:/bin" \
    python3 "$TESTS_DIR/keydrive.py" "cd '$SB' && exec $1 -i" \
      'WAIT:2' "SEND:$2" 'WAIT:2' >/dev/null 2>&1
  # Only the first line matters; a stray keystroke would show up as a second.
  head -n1 "$SB/fired.log" 2>/dev/null
}

for sh in zsh bash; do
  if ! command -v "$sh" >/dev/null 2>&1; then
    printf '    SKIP %s not installed\n' "$sh"; continue
  fi

  assert_eq "$sh: Ctrl-F searches the current directory" \
    "ARGS[]" "$(press "$sh" '\x06')"

  # ESC F — works in any terminal.
  assert_eq "$sh: Alt-Shift-F searches globally" \
    "ARGS[--global]" "$(press "$sh" '\x1bF')"

  # CSI 102;6u — what a terminal implementing the kitty keyboard protocol sends
  # for Ctrl-Shift-F, and what devup's WezTerm config is set up to send.
  assert_eq "$sh: the Ctrl-Shift-F sequence searches globally" \
    "ARGS[--global]" "$(press "$sh" '\x1b[102;6u')"
done

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
