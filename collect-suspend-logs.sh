#!/bin/bash
# Collect high-signal suspend/resume logs.
# This script is read-only, but it may need sudo to see full journal output.

set -euo pipefail

OUT_DIR=${1:-"./suspend-logs-$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$OUT_DIR"

echo "Writing logs to: $OUT_DIR"

echo "== system info ==" | tee "$OUT_DIR/00-system.txt"
{
  echo "date: $(date)"
  echo "kernel: $(uname -a)"
  echo "/sys/power/state: $(cat /sys/power/state 2>/dev/null || true)"
  echo "/sys/power/mem_sleep: $(cat /sys/power/mem_sleep 2>/dev/null || true)"
  echo "cmdline: $(cat /proc/cmdline 2>/dev/null || true)"
} >> "$OUT_DIR/00-system.txt"

# Prefer sudo if available; fall back to unprivileged journalctl.
JCTL=(journalctl)
if command -v sudo >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null; then
    JCTL=(sudo journalctl)
  else
    echo "NOTE: sudo is available but may prompt for a password." | tee -a "$OUT_DIR/00-system.txt"
  fi
fi

echo "== last boot suspend unit ==" | tee "$OUT_DIR/10-systemd-suspend.txt"
"${JCTL[@]}" -b -1 -u systemd-suspend.service --no-pager -n 300 2>/dev/null | tee -a "$OUT_DIR/10-systemd-suspend.txt" || true

echo "== last boot kernel power messages ==" | tee "$OUT_DIR/20-kernel-power.txt"
"${JCTL[@]}" -b -1 -k --no-pager | egrep -i "(PM:|suspend|resume|wakeup|freeze|hibernat|amdgpu|amd_pmc|mt7925|nvme|xhci|acpi|error|warn|fail|timeout)" | tail -n 400 | tee -a "$OUT_DIR/20-kernel-power.txt" || true

echo "== current boot kernel power messages ==" | tee "$OUT_DIR/30-kernel-power-current.txt"
"${JCTL[@]}" -k --no-pager | egrep -i "(PM:|suspend|resume|wakeup|freeze|hibernat|amdgpu|amd_pmc|mt7925|nvme|xhci|acpi|error|warn|fail|timeout)" | tail -n 400 | tee -a "$OUT_DIR/30-kernel-power-current.txt" || true

echo "Done. Attach the directory if you want me to interpret the logs."
