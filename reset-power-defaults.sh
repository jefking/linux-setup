#!/bin/bash
# Reset common power-tuning knobs back to safer defaults.
# Intended as an "undo" for aggressive settings that can destabilize s2idle suspend/resume.

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "ERROR: Run as root (sudo $0)" >&2
  exit 1
fi

echo "== Resetting power-related sysfs knobs =="

# 1) Re-enable CPU idle states
if compgen -G "/sys/devices/system/cpu/cpu*/cpuidle/state*/disable" >/dev/null; then
  echo "- Re-enabling CPU idle states (cpuidle)"
  for f in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
    echo 0 > "$f" 2>/dev/null || true
  done
fi

# 2) Restore PCIe ASPM policy to default
if [ -w /sys/module/pcie_aspm/parameters/policy ]; then
  echo "- Restoring PCIe ASPM policy to 'default'"
  echo default > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true
fi

# 3) Allow PCI runtime PM again
if compgen -G "/sys/bus/pci/devices/*/power/control" >/dev/null; then
  echo "- Restoring PCI runtime PM control to 'auto'"
  for f in /sys/bus/pci/devices/*/power/control; do
    echo auto > "$f" 2>/dev/null || true
  done
fi

# 4) Restore USB autosuspend
if compgen -G "/sys/bus/usb/devices/*/power/autosuspend" >/dev/null; then
  echo "- Restoring USB autosuspend delay to 2s"
  for f in /sys/bus/usb/devices/*/power/autosuspend; do
    echo 2 > "$f" 2>/dev/null || true
  done
fi

if compgen -G "/sys/bus/usb/devices/*/power/control" >/dev/null; then
  echo "- Restoring USB runtime PM control to 'auto'"
  for f in /sys/bus/usb/devices/*/power/control; do
    echo auto > "$f" 2>/dev/null || true
  done
fi

echo "Done. If suspend/resume is still broken, reboot and capture logs (see SUSPEND-RESUME.md)."

