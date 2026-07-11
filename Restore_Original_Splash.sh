#!/bin/sh
# Restore the stock ROCKNIX logo with concise boot status on the LCD.

EXTLINUX="/flash/extlinux/extlinux.conf"
OVERLAY="/flash/initramfs.overlay"
UNIT="/storage/.config/system.d/custom-splash.service"
PLAYER="/storage/.config/custom-splash-play.sh"
BACKUP_DIR="/storage/.config"

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: run this script as root."
  exit 1
fi

if [ ! -f "${EXTLINUX}" ]; then
  echo "ERROR: ${EXTLINUX} was not found."
  exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${BACKUP_DIR}/extlinux.conf.backup-logo-with-loading-${STAMP}"
cp "${EXTLINUX}" "${BACKUP}" || exit 1

# Stop the later framebuffer player so it cannot paint over the stock logo.
systemctl disable custom-splash.service >/dev/null 2>&1 || true
systemctl stop custom-splash.service >/dev/null 2>&1 || true
rm -f "${UNIT}" "${PLAYER}"
systemctl daemon-reload >/dev/null 2>&1 || true

mount -o remount,rw /flash || {
  echo "ERROR: could not remount /flash read-write."
  exit 1
}

awk '
  /^[ \t]*INITRD \/initramfs\.overlay[ \t]*$/ { next }
  /^[ \t]*APPEND / {
    prefix = substr($0, 1, index($0, "APPEND ") + 6)
    args = substr($0, index($0, "APPEND ") + 7)
    count = split(args, part, /[ \t]+/)
    out = ""
    have_quiet = 0
    have_tty0 = 0

    for (i = 1; i <= count; i++) {
      arg = part[i]
      if (arg == "") continue
      if (arg == "quiet") have_quiet = 1
      if (arg == "console=tty0") have_tty0 = 1
      if (arg == "loglevel=0" ||
          arg == "vt.global_cursor_default=0" ||
          arg == "systemd.show_status=0" ||
          arg == "rd.systemd.show_status=0" ||
          arg == "rd.udev.log-priority=3") continue
      out = out (out == "" ? "" : " ") arg
    }

    if (!have_quiet) out = out " quiet"
    if (!have_tty0) out = out " console=tty0"
    print prefix out
    next
  }
  { print }
' "${EXTLINUX}" > /tmp/extlinux.conf.logo-loading

if ! grep -q 'console=tty0' /tmp/extlinux.conf.logo-loading; then
  rm -f /tmp/extlinux.conf.logo-loading
  mount -o remount,ro /flash >/dev/null 2>&1 || true
  echo "ERROR: failed to build the restored boot configuration."
  exit 1
fi

cp /tmp/extlinux.conf.logo-loading "${EXTLINUX}"
rm -f /tmp/extlinux.conf.logo-loading "${OVERLAY}"
mount -o remount,ro /flash || true

rm -f /storage/.config/custom-splash-overlay-ran
sync

echo "Stock ROCKNIX logo and LCD loading text restored."
echo "Backup: ${BACKUP}"
echo "Reboot to apply the changes."
