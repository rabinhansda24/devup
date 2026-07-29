#!/usr/bin/env bash
# 70-maintenance.sh — backups, snapshots, and the disk hygiene that keeps a
# 500GB SSD viable across four language ecosystems.

register_group maint "Backups & Maintenance" \
  "Snapshots, backups, SMART monitoring, and a cache-cleanup helper."

register_pkg \
  --id timeshift \
  --name "timeshift" \
  --desc "System snapshots — roll back a bad apt upgrade" \
  --group maint \
  --check "command -v timeshift" \
  --install "install_apt timeshift" \
  --manual "sudo apt install timeshift" \
  --note "Timeshift needs a one-time setup run: sudo timeshift-gtk" \
  --default yes

register_pkg \
  --id restic \
  --name "restic" \
  --desc "Encrypted, deduplicated backups of \$HOME to an external drive" \
  --group maint \
  --check "command -v restic" \
  --install "install_apt restic" \
  --manual "sudo apt install restic" \
  --note "Init a repo with: restic init --repo /media/\$USER/backup/restic" \
  --default yes

register_pkg \
  --id smartmontools \
  --name "smartmontools" \
  --desc "SMART health checks — important on a second-hand SSD" \
  --group maint \
  --check "command -v smartctl" \
  --install "install_apt smartmontools" \
  --config "_report_smart" \
  --manual "sudo apt install smartmontools && sudo smartctl -a /dev/nvme0n1" \
  --default yes

_report_smart() {
  [[ "${DRY_RUN:-0}" == "1" ]] && return 0
  local dev
  dev="$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1; exit}')"
  [[ -z "$dev" ]] && return 0
  info "Checking SSD wear on ${dev}…"
  local pct
  pct="$($SUDO smartctl -A "$dev" 2>/dev/null \
    | grep -iE 'Percentage Used|Wear_Leveling' | head -n1 || true)"
  if [[ -n "$pct" ]]; then
    log "  ${C_DIM}${pct}${C_RESET}"
    info "Full report: sudo smartctl -a ${dev}"
  fi
}

register_pkg \
  --id devup-clean \
  --name "cleanup helper" \
  --desc "Installs 'devup clean' as a script + optional weekly systemd timer" \
  --group maint \
  --check "test -x \$HOME/.local/bin/devup-clean" \
  --install "_install_cleaner" \
  --manual "Copy configs/devup-clean to ~/.local/bin/" \
  --default yes

_install_cleaner() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "${C_DIM}  [dry-run] install ~/.local/bin/devup-clean${C_RESET}"
    return 0
  fi
  ensure_local_bin
  local src="$DEVUP_ROOT/configs/devup-clean"
  [[ -f "$src" ]] || { warn "configs/devup-clean missing"; return 1; }
  install -m 0755 "$src" "$HOME/.local/bin/devup-clean"
  success "Installed ~/.local/bin/devup-clean (run it monthly, or --dry-run first)"
}
