# Suspend/Resume (sleep) troubleshooting

Your machine reports only **s2idle** support:

- `/sys/power/mem_sleep: [s2idle]`

That means “modern standby” (not classic S3 deep sleep). On some AMD laptops, s2idle can be sensitive to
GPU/WiFi/ACPI quirks.

## 1) First: make sure our scripts aren’t sabotaging s2idle

`ac-performance-boost.sh` historically applied very aggressive knobs (disable CPU idle, force PCI runtime PM “on”,
disable USB autosuspend). Those can reduce s2idle reliability on some systems.

- New default: `./ac-performance-boost.sh` is **suspend-safe by default**
- Old behavior: `./ac-performance-boost.sh --aggressive`

If you already ran aggressive tuning and suspect it contributed:

```bash
sudo ./reset-power-defaults.sh
```

## 2) Capture the right logs (this is usually the key)

After a failed wake, reboot and run:

```bash
./collect-suspend-logs.sh
```

If sudo prompts for a password, re-run the key commands manually with sudo:

- `sudo journalctl -b -1 -u systemd-suspend.service --no-pager -n 300`
- `sudo journalctl -b -1 -k --no-pager | egrep -i '(PM:|suspend|resume|amdgpu|mt7925|acpi|error|fail|timeout)'`

## 3) Common next steps if s2idle wake is still broken

### A) BIOS option (best when available)
Look for a BIOS/UEFI setting like:
- “Sleep mode: **S3 / Linux**” vs “Modern Standby”

If you can enable S3/deep sleep, Linux often becomes much more reliable.

### B) Kernel parameter commonly used on AMD s2idle
One knob that sometimes helps is:
- `s2idle.prefer_microsoft_guid=1`

This is applied via your bootloader (GRUB/systemd-boot). Only do this once you’ve captured logs.

### C) WiFi driver as a culprit
MediaTek (mt7925e) has been implicated in some suspend/resume failures. A common workaround is unloading/reloading
that module around suspend/resume (systemd sleep hook). If your logs point to WiFi, I can provide an installer script
tailored to your distro layout.

