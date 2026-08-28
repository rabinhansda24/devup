#!/usr/bin/env bash
# The global search: --global looks at $HOME instead of the current directory,
# without changing what a current-directory search does.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

if ! command -v fd >/dev/null 2>&1 && ! command -v fdfind >/dev/null 2>&1; then
  printf '    SKIP no fd/fdfind installed\n'
  exit 0
fi

SB="$(new_sandbox)"
BIN="$SB/bin"
install_fzf_stub "$BIN" dump
install_editor_stub "$BIN" nano
export FF_TEST_LIST="$SB/list.txt"
export FF_EDITOR_LOG="$SB/editor.log"

# A home with real files, generated trees, and a project to stand in
mkdir -p "$SB/home/notes" "$SB/home/proj/node_modules/pkg" "$SB/home/proj/src" \
         "$SB/home/.cache/blobs" "$SB/home/.rustup/toolchains" "$SB/home/.local/share/junk"
printf 'note\n'   >"$SB/home/notes/todo.md"
printf 'config\n' >"$SB/home/.hidden-config"
printf 'source\n' >"$SB/home/proj/src/main.rs"
printf 'vendored\n' >"$SB/home/proj/node_modules/pkg/index.js"
printf 'blob\n'   >"$SB/home/.cache/blobs/cached.txt"
printf 'rustc\n'  >"$SB/home/.rustup/toolchains/rustc.txt"
printf 'junk\n'   >"$SB/home/.local/share/junk/j.txt"

candidates() { # <cwd> [args...]
  local cwd="$1"; shift
  : >"$FF_TEST_LIST"
  ( cd "$cwd" && PATH="$BIN:$PATH" HOME="$SB/home" "$FF" "$@" >/dev/null 2>&1 )
  cat "$FF_TEST_LIST"
}

# --- --global reaches all of $HOME, from anywhere ---
list="$(candidates "$SB/home/proj/src" --global)"
assert_contains "--global finds a file elsewhere in \$HOME" "$list" "notes/todo.md"
assert_contains "--global finds hidden files"               "$list" ".hidden-config"
assert_contains "--global still finds the current project"  "$list" "src/main.rs"

# --- and skips the trees that are all noise ---
assert_not_contains "--global skips node_modules"   "$list" "node_modules"
assert_not_contains "--global skips .cache"         "$list" "cached.txt"
assert_not_contains "--global skips .rustup"        "$list" "rustc.txt"
assert_not_contains "--global skips .local/share"   "$list" "junk"

# --- -g is the same thing ---
assert_eq "-g is a synonym for --global" "$list" "$(candidates "$SB/home/proj/src" -g)"

# --- the current-directory search is untouched by any of this ---
# The exclusions belong to the global search alone: inside a project you may
# well want to open something under node_modules.
list="$(candidates "$SB/home/proj")"
assert_contains     "a local search still offers node_modules" "$list" "node_modules/pkg/index.js"
assert_not_contains "a local search stays in the directory"    "$list" "todo.md"

list="$(candidates "$SB/home/proj/src")"
assert_contains     "a local search is still rooted at the cwd" "$list" "main.rs"
assert_not_contains "a local search does not become global"     "$list" "notes/todo.md"

# --- the root is overridable ---
list="$(candidates "$SB/home" --global)"
before="$list"
: >"$FF_TEST_LIST"
( cd "$SB/home" && PATH="$BIN:$PATH" HOME="$SB/home" DEVUP_FF_GLOBAL_ROOT="$SB/home/notes" "$FF" --global >/dev/null 2>&1 )
list="$(cat "$FF_TEST_LIST")"
assert_contains     "DEVUP_FF_GLOBAL_ROOT is searched"     "$list" "todo.md"
assert_not_contains "DEVUP_FF_GLOBAL_ROOT is not exceeded" "$list" ".hidden-config"
if [[ "$before" != "$list" ]]; then ok "the override actually changed the search"
else notok "the override actually changed the search" "the two searches returned the same list"; fi

# --- a root and --global together is a contradiction, not a silent winner ---
err="$( ( cd "$SB/home" && PATH="$BIN:$PATH" HOME="$SB/home" "$FF" --global /tmp 2>&1 >/dev/null ) )"
rc=$( ( cd "$SB/home" && PATH="$BIN:$PATH" HOME="$SB/home" "$FF" --global /tmp >/dev/null 2>&1 ); echo $? )
assert_rc_not   "--global with a PATH does not exit 0" 0 "$rc"
assert_contains "--global with a PATH is explained"    "$err" "takes no PATH"

# --- the picker says which tree it is looking at ---
assert_contains "--help documents the global search" "$( "$FF" --help )" "--global"

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
