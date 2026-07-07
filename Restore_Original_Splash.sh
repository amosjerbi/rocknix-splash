#!/bin/sh
# Restore Original Splash
#
# Removes the custom framebuffer boot splash service so the stock
# ROCKNIX logo shows again. Also removes the early-boot initramfs
# overlay (INITRD line + /flash/initramfs.overlay), restores the
# pristine KERNEL if an older in-place patch is still active, and
# restores the EmulationStation splash.svg backup if one exists
# (harmless either way - ES runs with --no-splash on ROCKNIX).
# Results are logged to /storage/roms/ports/splash/install.log

UNIT="/storage/.config/system.d/custom-splash.service"
RAW="/storage/.config/custom-splash.raw"
FRAMES="/storage/.config/custom-splash-frames"
PLAYER="/storage/.config/custom-splash-play.sh"
ES_TARGET="/storage/.config/emulationstation/resources/splash.svg"
ES_BACKUP="${ES_TARGET}.original"
EXTLINUX="/flash/extlinux/extlinux.conf"
OVERLAY="/flash/initramfs.overlay"
SPLICED_MD5="/storage/.config/custom-splash-spliced.md5"
LOG="/storage/roms/ports/splash/install.log"

mkdir -p "$(dirname "${LOG}")"

log() {
  echo "$1"
  echo "$1" >> "${LOG}"
}

echo "=== $(date) ===" >> "${LOG}"

if [ -f "${UNIT}" ]; then
  systemctl disable custom-splash.service >> "${LOG}" 2>&1
  rm -f "${UNIT}" "${RAW}" "${PLAYER}"
  rm -rf "${FRAMES}"
  systemctl daemon-reload >> "${LOG}" 2>&1
  log "Custom splash service removed."
else
  log "No custom splash service installed."
fi

if [ -f "${ES_BACKUP}" ]; then
  cp "${ES_BACKUP}" "${ES_TARGET}"
  log "EmulationStation splash.svg restored from backup."
fi

# --- undo early boot splash (bring the ROCKNIX logo back) ------------
if [ -f "${OVERLAY}" ] || grep -q "INITRD /initramfs.overlay" "${EXTLINUX}" 2>/dev/null; then
  if mount -o remount,rw /flash >> "${LOG}" 2>&1; then
    if grep -q "INITRD /initramfs.overlay" "${EXTLINUX}" 2>/dev/null; then
      grep -v "INITRD /initramfs.overlay" "${EXTLINUX}" > /tmp/extlinux.conf.new
      cp /tmp/extlinux.conf.new "${EXTLINUX}"
      rm -f /tmp/extlinux.conf.new
      log "INITRD overlay line removed from extlinux.conf."
    fi
    rm -f "${OVERLAY}"
    mount -o remount,ro /flash >> "${LOG}" 2>&1
    log "Early boot splash overlay removed."
  else
    log "ERROR: could not remount /flash rw - overlay NOT removed."
  fi
fi

# older in-place KERNEL patch: restore the pristine backup
if [ -f "${SPLICED_MD5}" ] && [ -f /storage/KERNEL.backup-original ]; then
  CUR_MD5=$(md5sum /flash/KERNEL | cut -d' ' -f1)
  if [ "${CUR_MD5}" = "$(cat "${SPLICED_MD5}")" ]; then
    if mount -o remount,rw /flash >> "${LOG}" 2>&1; then
      cp /storage/KERNEL.backup-original /flash/KERNEL
      echo "$(md5sum /flash/KERNEL | cut -d' ' -f1)  target/KERNEL" > /flash/KERNEL.md5
      rm -f "${SPLICED_MD5}"
      mount -o remount,ro /flash >> "${LOG}" 2>&1
      log "Pristine KERNEL restored from backup."
    else
      log "ERROR: could not remount /flash rw - KERNEL NOT restored."
    fi
  fi
fi

rm -f /storage/.config/custom-splash-overlay-ran /storage/.config/custom-splash-boot.raw

sync
log "DONE: stock boot splash restored. Reboot to see it."
exit 0
