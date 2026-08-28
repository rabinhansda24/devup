#!/usr/bin/env bash
# Keeping ~/.local/bin/ff in step with the version devup ships.
#
# The failure this guards against: a user installed ff months ago, devup has
# improved it since, but `test -x ~/.local/bin/ff` still says "installed" so
# the new version never reaches them.
set -uo pipefail
# shellcheck source=tests/helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SB="$(new_sandbox)"
TARGET="$SB/.local/bin/ff"
STALE_MTIME="200001010000"   # a timestamp no test run could produce

install_ff() { devup_sh "$SB" '_install_file_finder' >/dev/null 2>&1; }
config_ff()  { devup_sh "$SB" '_configure_file_finder' >/dev/null 2>&1; }
mtime()      { stat -c %Y "$1" 2>/dev/null; }

# --- the shipped script is identifiable as devup's ---
assert_contains "configs/ff marks itself devup-managed" "$(cat "$FF")" "devup-managed"

# --- a machine without ff ---
assert_rc_not "the check reports missing when ff is absent" 0 "$(pkg_check_rc "$SB")"
install_ff
assert_file_exists "installing creates ~/.local/bin/ff" "$TARGET"
if [[ -x "$TARGET" ]]; then ok "the installed ff is executable"; else notok "the installed ff is executable"; fi
if cmp -s "$FF" "$TARGET"; then ok "the installed ff matches the shipped one"
else notok "the installed ff matches the shipped one"; fi
assert_rc "the check reports installed once ff is current" 0 "$(pkg_check_rc "$SB")"

# --- an already-current ff is left completely alone ---
touch -t "$STALE_MTIME" "$TARGET"
install_ff; config_ff
assert_eq "a current ff is not rewritten by install or config" \
  "$(date -d "2000-01-01 00:00" +%s)" "$(mtime "$TARGET")"

# --- a stale devup-managed ff must be refreshed ---
make_stale() {
  printf '%s\n' '#!/usr/bin/env bash' '# devup-managed: file-finder' '# an old version' 'exit 0' >"$TARGET"
  chmod 0755 "$TARGET"
  touch -t "$STALE_MTIME" "$TARGET"
}

make_stale
assert_rc_not "the check reports missing when ff is stale" 0 "$(pkg_check_rc "$SB")"
install_ff
if cmp -s "$FF" "$TARGET"; then ok "installing refreshes a stale ff"
else notok "installing refreshes a stale ff"; fi

# `devup config file-finder` has to be able to repair it too, since that is the
# documented way to re-apply a single package.
make_stale
config_ff
if cmp -s "$FF" "$TARGET"; then ok "config refreshes a stale ff"
else notok "config refreshes a stale ff"; fi

# --- an ff devup did not write is not thrown away ---
rm -f "$SB"/.local/bin/*.devup-bak.* 2>/dev/null
printf '%s\n' '#!/usr/bin/env bash' '# my own hand-written ff' 'echo mine' >"$TARGET"
chmod 0755 "$TARGET"
install_ff
backup="$(find "$SB/.local/bin" -name 'ff.devup-bak.*' | head -n1)"
if [[ -n "$backup" ]]; then ok "an unmanaged ff is backed up before being replaced"
else notok "an unmanaged ff is backed up before being replaced"; fi
if [[ -n "$backup" ]] && grep -q "hand-written" "$backup"; then
  ok "the backup holds the user's original script"
else
  notok "the backup holds the user's original script"
fi

# --- dry run changes nothing ---
rm -rf "$SB/.local" "$SB/.zshrc" "$SB/.bashrc"
DRY_RUN=1 devup_sh "$SB" 'DRY_RUN=1 _install_file_finder' >/dev/null 2>&1
if [[ ! -e "$TARGET" ]]; then ok "a dry-run install writes no ff"; else notok "a dry-run install writes no ff"; fi
DRY_RUN=1 devup_sh "$SB" 'DRY_RUN=1 _configure_file_finder' >/dev/null 2>&1
if [[ ! -e "$SB/.zshrc" ]]; then ok "a dry-run config writes no rc file"; else notok "a dry-run config writes no rc file"; fi

# --- manual mode still tells the user what to do by hand ---
manual="$(devup_sh "$SB" 'printf "%s" "${PKG_MANUAL[file-finder]}"')"
assert_contains "manual instructions mention configs/ff" "$manual" "configs/ff"

cleanup_sandboxes
exit $(( TESTS_FAILED > 0 ))
