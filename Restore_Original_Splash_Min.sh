#!/bin/sh

. /etc/profile 2>/dev/null || true

UNIT="/storage/.config/system.d/custom-splash.service"
RAW="/storage/.config/custom-splash.raw"
FRAMES="/storage/.config/custom-splash-frames"
BOOT_RAW="/storage/.config/custom-splash-boot.raw"
BOOT_FRAMES="/storage/.config/custom-splash-boot-frames"
VIDEO="/storage/.config/custom-splash.mp4"
LAST_RAW="/storage/.config/custom-splash-last.raw"
DURATION_FILE="/storage/.config/custom-splash-duration"
PLAYER="/storage/.config/custom-splash-play.sh"
DUAL_WRAPPER="/storage/.config/dual-screen-start-es.sh"
DUAL_DROPIN="/storage/.config/system.d/essway.service.d/dual-screen-splash.conf"
ES_TARGET="/storage/.config/emulationstation/resources/splash.svg"
ES_BACKUP="${ES_TARGET}.original"
EXTLINUX="/flash/extlinux/extlinux.conf"
OVERLAY="/flash/initramfs.overlay"
SPLICED_MD5="/storage/.config/custom-splash-spliced.md5"
LOG="/storage/roms/ports/splash/install.log"

mkdir -p "$(dirname "$LOG")"

log() {
  echo "$1"
  echo "$1" >> "$LOG"
}

remount_flash_readonly() {
  mount -o remount,ro /flash >> "$LOG" 2>&1 || true
}

echo "=== $(date) ===" >> "$LOG"

systemctl disable --now custom-splash.service >> "$LOG" 2>&1 || true
rm -f "$UNIT" "$RAW" "$BOOT_RAW" "$VIDEO" "$LAST_RAW" "$DURATION_FILE" "$PLAYER"
rm -rf "$FRAMES" "$BOOT_FRAMES"
log "Custom framebuffer splash removed."

if [ -f "$DUAL_DROPIN" ] || [ -f "$DUAL_WRAPPER" ]; then
  rm -f "$DUAL_DROPIN" "$DUAL_WRAPPER"
  rmdir /storage/.config/system.d/essway.service.d 2>/dev/null || true
  log "Dual-screen splash service override removed."
fi

systemctl daemon-reload >> "$LOG" 2>&1 || true

if [ -f "$ES_BACKUP" ]; then
  cp "$ES_BACKUP" "$ES_TARGET"
  log "EmulationStation splash.svg restored from backup."
fi

if [ ! -f "$EXTLINUX" ]; then
  log "ERROR: $EXTLINUX was not found."
  exit 1
fi

if ! mount -o remount,rw /flash >> "$LOG" 2>&1; then
  log "ERROR: could not remount /flash read-write."
  exit 1
fi

BACKUP="/storage/.config/extlinux.conf.backup-restore-minimal-$(date +%Y%m%d-%H%M%S)"
cp "$EXTLINUX" "$BACKUP" || {
  remount_flash_readonly
  log "ERROR: could not back up extlinux.conf."
  exit 1
}

awk '
  function suppressed(argument) {
    return argument == "quiet" \
      || argument == "splash" \
      || argument ~ /^loglevel=/ \
      || argument ~ /^vt.global_cursor_default=/ \
      || argument ~ /^systemd.show_status=/ \
      || argument ~ /^rd.systemd.show_status=/ \
      || argument ~ /^rd.udev.log-priority=/
  }

  /^[[:space:]]*INITRD[[:space:]]+\/initramfs\.overlay[[:space:]]*$/ {
    next
  }

  /^[[:space:]]*APPEND[[:space:]]/ {
    indentation = substr($0, 1, index($0, "APPEND") - 1)
    printf "%sAPPEND", indentation
    has_tty0 = 0
    for (field = 2; field <= NF; field++) {
      if (suppressed($field)) continue
      if ($field == "console=tty0") has_tty0 = 1
      printf " %s", $field
    }
    if (!has_tty0) printf " console=tty0"
    printf " loglevel=3 systemd.show_status=auto rd.systemd.show_status=auto rd.udev.log-priority=3\n"
    next
  }

  { print }
' "$EXTLINUX" > /tmp/extlinux.conf.restore || {
  rm -f /tmp/extlinux.conf.restore
  remount_flash_readonly
  log "ERROR: could not generate minimal-message extlinux configuration."
  exit 1
}

cp /tmp/extlinux.conf.restore "$EXTLINUX" || {
  rm -f /tmp/extlinux.conf.restore
  remount_flash_readonly
  log "ERROR: could not install minimal-message extlinux configuration."
  exit 1
}
rm -f /tmp/extlinux.conf.restore "$OVERLAY"
remount_flash_readonly
log "Early custom overlay removed; original splash restored with errors-only boot messages."
log "Boot configuration backup: $BACKUP"

if [ -f "$SPLICED_MD5" ] && [ -f /storage/KERNEL.backup-original ]; then
  CURRENT_MD5=$(md5sum /flash/KERNEL | cut -d' ' -f1)
  if [ "$CURRENT_MD5" = "$(cat "$SPLICED_MD5")" ]; then
    if mount -o remount,rw /flash >> "$LOG" 2>&1; then
      cp /storage/KERNEL.backup-original /flash/KERNEL
      echo "$(md5sum /flash/KERNEL | cut -d' ' -f1)  target/KERNEL" > /flash/KERNEL.md5
      rm -f "$SPLICED_MD5"
      remount_flash_readonly
      log "Pristine KERNEL restored from backup."
    else
      log "ERROR: could not remount /flash; KERNEL was not restored."
    fi
  fi
fi

rm -f /storage/.config/custom-splash-overlay-ran
sync
log "DONE: original splash restored with minimal reboot messages. Reboot to test."
exit 0
