#!/usr/bin/env bash
# The preview pane. A preview that fails must never take the finder down with
# it, so every one of these has to exit 0.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SB="$(new_sandbox)"
BIN="$SB/bin"
isolate_bin "$BIN"
mkdir -p "$SB/proj"
printf 'line one\nline two\n' >"$SB/proj/plain.txt"
printf 'bin\000ary\001\002data\n'  >"$SB/proj/blob.bin"

preview() { # <file> -> sets $rc, prints output
  ( cd "$SB/proj" && PATH="$BIN" HOME="$SB" bash "$FF" --preview "$1" 2>&1 )
}
preview_rc() {
  ( cd "$SB/proj" && PATH="$BIN" HOME="$SB" bash "$FF" --preview "$1" >/dev/null 2>&1 ); echo $?
}

# --- bat is used when present ---
make_stub "$BIN" bat 'printf "BAT-PREVIEW %s\n" "${*: -1}"'
out="$(preview plain.txt)"
assert_contains "bat is used for the preview" "$out" "BAT-PREVIEW"
assert_rc       "the bat preview exits 0" 0 "$(preview_rc plain.txt)"

# --- Ubuntu names it batcat ---
rm -f "$BIN/bat"
make_stub "$BIN" batcat 'printf "BATCAT-PREVIEW %s\n" "${*: -1}"'
out="$(preview plain.txt)"
assert_contains "batcat is used when bat is absent" "$out" "BATCAT-PREVIEW"

# --- neither: still show something useful ---
rm -f "$BIN/batcat"
out="$(preview plain.txt)"
assert_contains "the fallback preview shows the file"  "$out" "line one"
assert_rc       "the fallback preview exits 0" 0 "$(preview_rc plain.txt)"

# --- awkward names ---
printf 'spaces\n' >"$SB/proj/a file with spaces.txt"
out="$(preview "a file with spaces.txt")"
assert_contains "a filename with spaces previews" "$out" "spaces"

# --- things that cannot be previewed must still exit 0 ---
assert_rc "a binary file previews without failing"  0 "$(preview_rc blob.bin)"
assert_rc "a missing file previews without failing" 0 "$(preview_rc no-such-file.txt)"
assert_rc "a directory previews without failing"    0 "$(preview_rc .)"

if [[ "$(id -u)" != "0" ]]; then
  printf 'secret\n' >"$SB/proj/locked.txt"
  chmod 000 "$SB/proj/locked.txt"
  assert_rc "an unreadable file previews without failing" 0 "$(preview_rc locked.txt)"
  chmod 644 "$SB/proj/locked.txt"
else
  printf '    SKIP unreadable-file preview (running as root)\n'
fi

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
