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
# ff records the arguments it was called with and echoes a marker, so the test
# can wait for the widget to have run instead of guessing at a duration. This is
# about key dispatch, not about the finder.
make_stub "$BIN" ff "printf 'ARGS[%s]\\n' \"\$*\" >> '$SB/fired.log'; printf 'FFDONE\\n'"

PATH="$BIN:$PATH" devup_sh "$SB" '_configure_file_finder' >/dev/null 2>&1

# A prompt the driver can recognise, so a key is only sent once the shell is
# actually at the prompt. Guessing that with a sleep is what makes pty tests
# flaky on a loaded machine.
printf "\nPROMPT='DEVUPREADY '\n" >>"$SB/.zshrc"
printf "\nPS1='DEVUPREADY '\n"    >>"$SB/.bashrc"

LAST_PTY_OUTPUT=""

press() { # <shell> <escaped key> -> prints what ff was called with
  rm -f "$SB/fired.log"
  LAST_PTY_OUTPUT="$(
    HOME="$SB" PATH="$BIN:/usr/bin:/bin" \
      python3 "$TESTS_DIR/keydrive.py" "cd '$SB' && exec $1 -i" \
        'EXPECT:DEVUPREADY' "SEND:$2" 'EXPECT:FFDONE' 2>&1
  )"
  # Only the first line matters; a stray keystroke would show up as a second.
  head -n1 "$SB/fired.log" 2>/dev/null
}

# assert_key <desc> <expected> <shell> <key>
assert_key() {
  local desc="$1" want="$2" got
  got="$(press "$3" "$4")"
  if [[ "$got" == "$want" ]]; then
    ok "$desc"
  else
    notok "$desc" "expected [$want], got [$got]; terminal saw: $(
      printf '%s' "$LAST_PTY_OUTPUT" | tr -d '\000' | tr '\r\n' '  ' | tr -s ' ' | tail -c 300)"
  fi
}

# A shell that never reaches a prompt in the pty would fail every case below
# with nothing to explain it, so say what is actually there first.
probe_shell() { # <shell>
  printf '    -- %s probe: bin=%s ver=%s zdotdir=%s rc=%s block=%s\n' \
    "$1" \
    "$(PATH="$BIN:/usr/bin:/bin" command -v "$1" 2>/dev/null || echo NONE)" \
    "$("$1" --version 2>&1 | head -n1 | cut -c1-20)" \
    "${ZDOTDIR:-unset}" \
    "$([[ -f "$SB/.${1}rc" ]] && echo yes || echo MISSING)" \
    "$(grep -c 'devup:file-finder' "$SB/.${1}rc" 2>/dev/null || echo 0)"
  local out
  out="$(HOME="$SB" PATH="$BIN:/usr/bin:/bin" python3 "$TESTS_DIR/keydrive.py" \
          "exec $1 -i" 'EXPECT:DEVUPREADY' 2>&1 | tr -d '\000' | tr '\r\n' '  ' | tr -s ' ')"
  printf '    -- %s saw: [%s]\n' "$1" "$(printf '%s' "$out" | tail -c 200)"
}

for sh in zsh bash; do
  if ! command -v "$sh" >/dev/null 2>&1; then
    printf '    SKIP %s not installed\n' "$sh"; continue
  fi

  _before="$TESTS_FAILED"
  assert_key "$sh: Ctrl-F searches the current directory" "ARGS[]" "$sh" '\x06'
  # If even Ctrl-F did not arrive, the shell never got to a prompt and the two
  # cases below will fail the same way. Say what is actually there instead.
  (( TESTS_FAILED > _before )) && probe_shell "$sh"

  # ESC F — works in any terminal.
  assert_key "$sh: Alt-Shift-F searches globally" "ARGS[--global]" "$sh" '\x1bF'

  # CSI 102;6u — what a terminal implementing the kitty keyboard protocol sends
  # for Ctrl-Shift-F, and what devup's WezTerm config is set up to send.
  assert_key "$sh: the Ctrl-Shift-F sequence searches globally" \
    "ARGS[--global]" "$sh" '\x1b[102;6u'
done

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
