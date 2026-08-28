#!/usr/bin/env bash
# run.sh — runs every tests/test_*.sh and reports a single pass/fail verdict.
#
#   tests/run.sh            # all tests
#   tests/run.sh search     # only tests whose name contains "search"
set -uo pipefail

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="${1:-}"

total=0
failed_files=()

for t in "$TESTS_DIR"/test_*.sh; do
  [[ -e "$t" ]] || continue
  name="$(basename "$t")"
  [[ -n "$filter" && "$name" != *"$filter"* ]] && continue
  printf '%s\n' "$name"
  if bash "$t"; then
    :
  else
    failed_files+=("$name")
  fi
  total=$((total + 1))
done

printf '\n'
if (( ${#failed_files[@]} > 0 )); then
  printf 'FAILED: %s\n' "${failed_files[*]}"
  printf '%d of %d test files failed\n' "${#failed_files[@]}" "$total"
  exit 1
fi
printf 'all %d test files passed\n' "$total"
