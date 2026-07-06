#!/bin/sh
# Restore Original Splash
#
# Removes the custom framebuffer boot splash service so the stock
# ROCKNIX logo shows again. Also restores the EmulationStation
# splash.svg backup if one exists (harmless either way - ES runs
# with --no-splash on ROCKNIX).
# Results are logged to /storage/roms/ports/splash/install.log

UNIT="/storage/.config/system.d/custom-splash.service"
RAW="/storage/.config/custom-splash.raw"
FRAMES="/storage/.config/custom-splash-frames"
PLAYER="/storage/.config/custom-splash-play.sh"
ES_TARGET="/storage/.config/emulationstation/resources/splash.svg"
ES_BACKUP="${ES_TARGET}.original"
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

sync
log "DONE: stock boot splash restored. Reboot to see it."
exit 0
