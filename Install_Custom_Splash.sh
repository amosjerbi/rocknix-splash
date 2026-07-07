#!/bin/sh
# Install Custom Splash (v4 - framebuffer service + initramfs overlay)
#
# ROCKNIX starts EmulationStation with --no-splash, so the ES splash.svg
# is never shown. Instead this installs:
#  - a systemd service that draws your image (or plays your GIF)
#    directly on the framebuffer early in boot
#  - an initramfs overlay (INITRD in extlinux.conf) that replaces the
#    rocknix-splash binary, so the ROCKNIX logo at power-on is replaced
#    by your image too - no kernel modification involved
#
# 1. Put your image in /storage/roms/ports/splash/ as either:
#      splash.gif  - animated GIF (preferred if both exist)
#      splash.png  - still image (8-bit RGB/RGBA, non-interlaced)
#    Any size - it gets scaled and centered on black.
# 2. Run this script from the Ports menu (or via SSH).
# 3. Reboot.
#
# Results are logged to /storage/roms/ports/splash/install.log

SPLASH_DIR="/storage/roms/ports/splash"
PNG="${SPLASH_DIR}/splash.png"
GIF="${SPLASH_DIR}/splash.gif"
# NOTE: converted output lives on /storage (mounted by initramfs,
# available at early boot) - /storage/roms is a later mount and NOT
# yet available when the splash service runs.
RAW="/storage/.config/custom-splash.raw"
FRAMES="/storage/.config/custom-splash-frames"
PLAYER="/storage/.config/custom-splash-play.sh"
UNIT="/storage/.config/system.d/custom-splash.service"
LOG="${SPLASH_DIR}/install.log"

mkdir -p "${SPLASH_DIR}"

log() {
  echo "$1"
  echo "$1" >> "${LOG}"
}

echo "=== $(date) ===" >> "${LOG}"

# framebuffer geometry - use the VISIBLE resolution from fbset, not
# /sys/.../virtual_size: virtual_size is often double-height for
# double buffering (e.g. 640x960 on a 640x480 panel), which would
# center the image in the off-screen half and push it off-center.
FB_GEOM=$(fbset 2>/dev/null | awk '/geometry/ {print $2 " " $3}')
FB_W=${FB_GEOM% *}
FB_H=${FB_GEOM#* }
if [ -z "${FB_W}" ] || [ -z "${FB_H}" ]; then
  FB_SIZE=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)
  FB_W=${FB_SIZE%,*}
  FB_H=${FB_SIZE#*,}
fi
if [ -z "${FB_W}" ] || [ -z "${FB_H}" ]; then
  log "ERROR: could not read framebuffer size"
  exit 1
fi
log "Using framebuffer resolution ${FB_W}x${FB_H}"

if [ -f "${GIF}" ]; then
  [ -f "${SPLASH_DIR}/gif2raw.py" ] || { log "ERROR: gif2raw.py missing"; exit 1; }
  log "Converting ${GIF} for ${FB_W}x${FB_H} framebuffer (this can take a minute)..."
  if ! python3 "${SPLASH_DIR}/gif2raw.py" "${GIF}" "${FRAMES}" "${FB_W}" "${FB_H}" >> "${LOG}" 2>&1; then
    log "ERROR: GIF conversion failed - see ${LOG}"
    exit 1
  fi
  rm -f "${RAW}"
elif [ -f "${PNG}" ]; then
  [ -f "${SPLASH_DIR}/png2raw.py" ] || { log "ERROR: png2raw.py missing"; exit 1; }
  log "Converting ${PNG} for ${FB_W}x${FB_H} framebuffer..."
  if ! python3 "${SPLASH_DIR}/png2raw.py" "${PNG}" "${RAW}" "${FB_W}" "${FB_H}" >> "${LOG}" 2>&1; then
    log "ERROR: PNG conversion failed - see ${LOG}"
    exit 1
  fi
  rm -rf "${FRAMES}"
else
  log "No image found. Put splash.gif or splash.png in ${SPLASH_DIR}"
  log "Then run this script again."
  exit 1
fi

# player: handles both still image and animation; exits as soon as
# EmulationStation is up (sway takes over the display anyway)
cat > "${PLAYER}" << 'EOF'
#!/bin/sh
FRAMES="/storage/.config/custom-splash-frames"
RAW="/storage/.config/custom-splash.raw"
FB="/dev/fb0"

if [ -f "${FRAMES}/delays.txt" ]; then
  END=$(( $(date +%s) + 45 ))
  while [ "$(date +%s)" -lt "${END}" ]; do
    i=0
    while read -r d; do
      i=$((i+1))
      f=$(printf "${FRAMES}/frame_%04d.raw" "${i}")
      [ -f "${f}" ] || break
      cat "${f}" > "${FB}" 2>/dev/null || exit 0
      pgrep -f emulationstation >/dev/null && exit 0
      sleep "${d}"
    done < "${FRAMES}/delays.txt"
  done
elif [ -f "${RAW}" ]; then
  cat "${RAW}" > "${FB}" 2>/dev/null
fi
exit 0
EOF
chmod +x "${PLAYER}"

mkdir -p "$(dirname "${UNIT}")"
cat > "${UNIT}" << 'EOF'
[Unit]
Description=Custom boot splash
After=local-fs.target
Before=essway.service

[Service]
Type=simple
ExecStart=/storage/.config/custom-splash-play.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >> "${LOG}" 2>&1
systemctl enable custom-splash.service >> "${LOG}" 2>&1 || {
  log "ERROR: could not enable custom-splash.service"
  exit 1
}

# --- early boot splash (replaces the ROCKNIX logo) -------------------
# The ROCKNIX logo is drawn by /usr/bin/rocknix-splash inside the
# initramfs embedded in /flash/KERNEL. We override that one file with
# a tiny uncompressed cpio overlay loaded via an INITRD line in
# extlinux.conf - the kernel unpacks it over the built-in initramfs.
# No kernel modification needed; if the bootloader ignores the INITRD
# line the stock logo shows and boot is unaffected.
EXTLINUX="/flash/extlinux/extlinux.conf"
OVERLAY="/flash/initramfs.overlay"
EXTLINUX_BAK="/storage/.config/extlinux.conf.backup-original"
SPLICED_MD5="/storage/.config/custom-splash-spliced.md5"

install_early_splash() {
  if [ ! -f "${EXTLINUX}" ]; then
    log "NOTE: ${EXTLINUX} not found - early boot logo replacement"
    log "      is only supported on extlinux devices, skipping."
    return 0
  fi
  [ -f "${SPLASH_DIR}/make_overlay.py" ] || {
    log "NOTE: make_overlay.py missing, skipping early boot splash."
    return 0
  }

  mount -o remount,rw /flash >> "${LOG}" 2>&1 || {
    log "NOTE: could not remount /flash rw, skipping early boot splash."
    return 0
  }

  # migrate: if this KERNEL was patched in-place by an older method,
  # restore the pristine backup first (overlay replaces that hack)
  if [ -f "${SPLICED_MD5}" ] && [ -f /storage/KERNEL.backup-original ]; then
    CUR_MD5=$(md5sum /flash/KERNEL | cut -d' ' -f1)
    if [ "${CUR_MD5}" = "$(cat "${SPLICED_MD5}")" ]; then
      log "Restoring pristine KERNEL from backup (replacing in-place patch)..."
      cp /storage/KERNEL.backup-original /flash/KERNEL
      echo "$(md5sum /flash/KERNEL | cut -d' ' -f1)  target/KERNEL" > /flash/KERNEL.md5
      rm -f "${SPLICED_MD5}"
    fi
  fi

  if ! python3 "${SPLASH_DIR}/make_overlay.py" "${OVERLAY}" >> "${LOG}" 2>&1; then
    log "NOTE: overlay build failed, early boot logo not replaced."
    mount -o remount,ro /flash >> "${LOG}" 2>&1
    return 0
  fi

  if ! grep -q "INITRD /initramfs.overlay" "${EXTLINUX}"; then
    [ -f "${EXTLINUX_BAK}" ] || cp "${EXTLINUX}" "${EXTLINUX_BAK}"
    awk '{print} /^[ \t]*LINUX /{print "  INITRD /initramfs.overlay"}' \
      "${EXTLINUX}" > /tmp/extlinux.conf.new
    if grep -q "INITRD /initramfs.overlay" /tmp/extlinux.conf.new; then
      cp /tmp/extlinux.conf.new "${EXTLINUX}"
      log "Added INITRD overlay to extlinux.conf (backup: ${EXTLINUX_BAK})"
    else
      log "NOTE: could not add INITRD line (no LINUX entry found?)"
    fi
    rm -f /tmp/extlinux.conf.new
  fi

  mount -o remount,ro /flash >> "${LOG}" 2>&1
  rm -f /storage/.config/custom-splash-overlay-ran
  log "Early boot splash installed - ROCKNIX logo replaced."
}

install_early_splash

sync
log "SUCCESS: custom splash installed. Reboot to see it."
exit 0
