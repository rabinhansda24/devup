#!/usr/bin/env bash
# helpers.sh — assertions and sandbox builders for the tests in this directory.
#
# Tests never touch the developer's real $HOME: every test runs against a
# throwaway sandbox with its own HOME, its own PATH and its own stub binaries.

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "$TESTS_DIR/.." && pwd)"
# shellcheck disable=SC2034  # consumed by the test files that source this
FF="$REPO_ROOT/configs/ff"

TESTS_RUN=0
TESTS_FAILED=0

# ---------- assertions ----------
ok()    { TESTS_RUN=$((TESTS_RUN + 1)); printf '    ok   %s\n' "$1"; }
notok() {
  TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '    FAIL %s\n' "$1"
  # Keep the diagnostic to a couple of lines: some of these values are whole
  # scripts, and a wall of text buries the failures that follow it.
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | head -c 400 | sed 's/^/         /'
  return 0
}

assert_eq() { # <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else notok "$1" "expected [$2], got [$3]"; fi
}

assert_contains() { # <desc> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else notok "$1" "[$3] not found in: $2"; fi
}

assert_not_contains() { # <desc> <haystack> <needle>
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else notok "$1" "[$3] unexpectedly found in: $2"; fi
}

assert_rc() { # <desc> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then ok "$1"; else notok "$1" "expected exit $2, got $3"; fi
}

assert_rc_not() { # <desc> <unwanted-rc> <actual-rc>
  if [[ "$2" != "$3" ]]; then ok "$1"; else notok "$1" "exit status should not be $2"; fi
}

assert_file_exists() { # <desc> <path>
  if [[ -e "$2" ]]; then ok "$1"; else notok "$1" "missing: $2"; fi
}

# ---------- sandbox ----------
# new_sandbox — prints the path of a fresh throwaway directory.
new_sandbox() {
  local d
  d="$(mktemp -d -t devup-fftest.XXXXXXXX)"
  SANDBOXES+=("$d")
  printf '%s\n' "$d"
}

cleanup_sandboxes() {
  local d
  for d in "${SANDBOXES[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}

# make_stub <bindir> <name> <body> — writes an executable stub.
make_stub() {
  local dir="$1" name="$2" body="$3"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\n%s\n' "$body" >"$dir/$name"
  chmod 0755 "$dir/$name"
}

# isolate_bin <bindir> — link in the handful of real tools the stubs themselves
# need, so a test can set PATH to <bindir> alone and still run. Anything ff
# reaches for beyond these has to come from a stub, which is the point: the
# test fails loudly if ff grows an undeclared dependency.
isolate_bin() {
  local dir="$1" t src
  mkdir -p "$dir"
  for t in bash env cat grep sed head; do
    src="$(command -v "$t" 2>/dev/null)" || continue
    [[ -n "$src" ]] && ln -sf "$src" "$dir/$t"
  done
}

# make_project <root> — a small tree covering the awkward filename cases.
make_project() {
  local p="$1"
  mkdir -p "$p/sub dir" "$p/.git" "$p/deep/deeper"
  printf 'top level\n'  >"$p/top.txt"
  printf 'nested\n'     >"$p/deep/deeper/nested.txt"
  printf 'spaces\n'     >"$p/sub dir/file with spaces.txt"
  printf 'hidden\n'     >"$p/.hidden.txt"
  printf 'unicode\n'    >"$p/ünïcødé-ファイル.txt"
  printf "quote'br[ack]et\n" >"$p/quote'br[ack]et.txt"
  printf 'git internals\n' >"$p/.git/config"
}

# ---------- the fzf stubs ----------
# Every stub ignores its arguments and speaks only through stdin/stdout, which
# is all ff relies on. Each one models one real fzf outcome.
install_fzf_stub() { # <bindir> <mode> [arg]
  local dir="$1" mode="$2" arg="${3:-}"
  case "$mode" in
    dump)     make_stub "$dir" fzf 'cat >"$FF_TEST_LIST"; exit 130' ;;
    pick)     make_stub "$dir" fzf "cat >\"\$FF_TEST_LIST\"; sed -n '${arg}p' \"\$FF_TEST_LIST\"; exit 0" ;;
    match)    make_stub "$dir" fzf 'cat >"$FF_TEST_LIST"; grep -m1 -F -e "$FF_TEST_MATCH" "$FF_TEST_LIST"; exit 0' ;;
    cancel)   make_stub "$dir" fzf 'cat >/dev/null; exit 130' ;;
    nomatch)  make_stub "$dir" fzf 'cat >/dev/null; exit 1' ;;
    # Reads one line and exits, leaving the producer to be killed by SIGPIPE.
    early)    make_stub "$dir" fzf 'head -n 1; exit 0' ;;
    broken)   make_stub "$dir" fzf 'exit 2' ;;
    *) printf 'install_fzf_stub: unknown mode %s\n' "$mode" >&2; return 1 ;;
  esac
}

# install_editor_stub <bindir> <name> — records its argv in $FF_EDITOR_LOG.
install_editor_stub() {
  make_stub "$1" "$2" 'printf "%s\n" "$@" >"$FF_EDITOR_LOG"; printf "%s\n" "$0" >"$FF_EDITOR_LOG.name"; exit 0'
}

# editor_args — the argv the editor stub was called with, one per line.
editor_args() { cat "$FF_EDITOR_LOG" 2>/dev/null; }
editor_ran()  { [[ -s "$FF_EDITOR_LOG" ]]; }
editor_name() { basename "$(cat "$FF_EDITOR_LOG.name" 2>/dev/null)" 2>/dev/null; }

# ---------- driving devup itself ----------
# devup_sh <home> <code> — run <code> with devup's libs and the file-finder
# module loaded, against a sandbox HOME. This is how the tests exercise the
# real registration data and the real install/config functions.
devup_sh() {
  local home="$1" code="$2"
  HOME="$home" DEVUP_ROOT="$REPO_ROOT" bash -c '
    set -uo pipefail
    . "$DEVUP_ROOT/lib/core.sh"
    . "$DEVUP_ROOT/lib/registry.sh"
    . "$DEVUP_ROOT/lib/install.sh"
    . "$DEVUP_ROOT/modules/35-file-finder.sh"
    '"$code"
}

# pkg_check_rc <home> — exit status of the file-finder package's --check snippet,
# evaluated exactly the way lib/registry.sh detect_all evaluates it.
pkg_check_rc() {
  local home="$1"
  devup_sh "$home" 'bash -c "${PKG_CHECK[file-finder]}" >/dev/null 2>&1; echo $?' | tail -n1
}
