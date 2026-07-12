#!/bin/sh
# Install Custom Splash (v4 - framebuffer service + initramfs overlay)
#
# ROCKNIX starts EmulationStation with --no-splash, so the ES splash.svg
# is never shown. Instead this installs:
#  - a systemd service that draws your image or plays your GIF/MP4
#    directly on the framebuffer early in boot
#  - an initramfs overlay (INITRD in extlinux.conf) that replaces the
#    rocknix-splash binary, so the ROCKNIX logo at power-on is replaced
#    by your image too - no kernel modification involved
#
# 1. Put your images in /storage/roms/ports/splash/:
#      pre-splash.mp4/gif/png - optional early boot image shown first
#                               (animations use their first frame here)
#      splash.mp4/gif/png     - main splash shown after storage mounts
#                               (MP4/GIF stays animated)
#    Any size - images get scaled and centered on black.
# 2. Run this script from the Ports menu (or via SSH).
# 3. Reboot.
#
# Results are logged to /storage/roms/ports/splash/install.log

SPLASH_DIR="/storage/roms/ports/splash"
PNG="${SPLASH_DIR}/splash.png"
GIF="${SPLASH_DIR}/splash.gif"
MP4="${SPLASH_DIR}/splash.mp4"
PRE_PNG="${SPLASH_DIR}/pre-splash.png"
PRE_GIF="${SPLASH_DIR}/pre-splash.gif"
PRE_MP4="${SPLASH_DIR}/pre-splash.mp4"
# NOTE: converted output lives on /storage (mounted by initramfs,
# available at early boot) - /storage/roms is a later mount and NOT
# yet available when the splash service runs.
RAW="/storage/.config/custom-splash.raw"
FRAMES="/storage/.config/custom-splash-frames"
BOOT_RAW="/storage/.config/custom-splash-boot.raw"
BOOT_FRAMES="/storage/.config/custom-splash-boot-frames"
VIDEO="/storage/.config/custom-splash.mp4"
LAST_RAW="/storage/.config/custom-splash-last.raw"
DURATION_FILE="/storage/.config/custom-splash-duration"
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

convert_main_splash() {
  if [ -f "${MP4}" ]; then
    command -v mpv >/dev/null 2>&1 || { log "ERROR: mpv is required for MP4 splash playback"; exit 1; }
    log "Installing ${MP4} for original MP4 playback..."
    cp "${MP4}" "${VIDEO}" || { log "ERROR: could not copy MP4 splash"; exit 1; }
    MP4_DURATION=$(mpv --no-config --no-audio --vo=null --frames=1 \
      --term-playing-msg='${=duration}' "${MP4}" 2>/dev/null | \
      awk '/^[0-9]+([.][0-9]+)?$/ { print; exit }')
    [ -n "${MP4_DURATION}" ] || { log "ERROR: could not read MP4 duration"; exit 1; }
    echo "${MP4_DURATION}" > "${DURATION_FILE}"
    LAST_TMP="/tmp/custom-splash-last-frame"
    rm -rf "${LAST_TMP}"
    mkdir -p "${LAST_TMP}"
    if ! mpv --no-config --no-audio --vo=image --vo-image-format=png \
      --vo-image-outdir="${LAST_TMP}" --start=-0.1 --frames=1 \
      --vf="lavfi=[scale=${FB_W}:${FB_H}:force_original_aspect_ratio=decrease,pad=${FB_W}:${FB_H}:(ow-iw)/2:(oh-ih)/2]" \
      "${MP4}" >> "${LOG}" 2>&1; then
      log "ERROR: could not extract MP4 final frame"
      exit 1
    fi
    LAST_PNG=$(find "${LAST_TMP}" -type f -name '*.png' | head -n 1)
    if [ -z "${LAST_PNG}" ] || ! python3 "${SPLASH_DIR}/png2raw.py" \
      "${LAST_PNG}" "${LAST_RAW}" "${FB_W}" "${FB_H}" >> "${LOG}" 2>&1; then
      log "ERROR: could not convert MP4 final frame"
      exit 1
    fi
    rm -rf "${LAST_TMP}"
    log "MP4 final frame prepared for seamless boot handoff."
    rm -f "${RAW}"
    rm -rf "${FRAMES}"
  elif [ -f "${GIF}" ]; then
    [ -f "${SPLASH_DIR}/gif2raw.py" ] || { log "ERROR: gif2raw.py missing"; exit 1; }
    log "Converting ${GIF} for ${FB_W}x${FB_H} framebuffer (this can take a minute)..."
    if ! python3 "${SPLASH_DIR}/gif2raw.py" "${GIF}" "${FRAMES}" "${FB_W}" "${FB_H}" >> "${LOG}" 2>&1; then
      log "ERROR: GIF conversion failed - see ${LOG}"
      exit 1
    fi
    rm -f "${RAW}"
    rm -f "${VIDEO}"
  elif [ -f "${PNG}" ]; then
    [ -f "${SPLASH_DIR}/png2raw.py" ] || { log "ERROR: png2raw.py missing"; exit 1; }
    log "Converting ${PNG} for ${FB_W}x${FB_H} framebuffer..."
    if ! python3 "${SPLASH_DIR}/png2raw.py" "${PNG}" "${RAW}" "${FB_W}" "${FB_H}" >> "${LOG}" 2>&1; then
      log "ERROR: PNG conversion failed - see ${LOG}"
      exit 1
    fi
    rm -rf "${FRAMES}"
    rm -f "${VIDEO}"
  else
    log "No main splash found. Put splash.mp4, splash.gif, or splash.png in ${SPLASH_DIR}"
    log "Then run this script again."
    exit 1
  fi
}

convert_pre_splash() {
  if [ -f "${PRE_MP4}" ]; then
    command -v mpv >/dev/null 2>&1 || { log "ERROR: mpv is required to read pre-splash.mp4"; exit 1; }
    [ -f "${SPLASH_DIR}/png2raw.py" ] || { log "ERROR: png2raw.py missing"; exit 1; }
    PRE_TMP="/tmp/custom-splash-first-frame"
    rm -rf "${PRE_TMP}"
    mkdir -p "${PRE_TMP}"
    log "Extracting ${PRE_MP4} first frame for early boot splash..."
    if ! mpv --no-config --no-audio --vo=image --vo-image-format=png \
      --vo-image-outdir="${PRE_TMP}" --frames=1 "${PRE_MP4}" >> "${LOG}" 2>&1; then
      log "ERROR: pre-splash MP4 frame extraction failed - see ${LOG}"
      exit 1
    fi
    PRE_FRAME=$(find "${PRE_TMP}" -type f -name '*.png' | head -n 1)
    if [ -z "${PRE_FRAME}" ] || ! python3 "${SPLASH_DIR}/png2raw.py" "${PRE_FRAME}" "${BOOT_RAW}" "${FB_W}" "${FB_H}" >> "${LOG}" 2>&1; then
      log "ERROR: could not convert pre-splash MP4 first frame"
      exit 1
    fi
    rm -rf "${PRE_TMP}" "${BOOT_FRAMES}"
    log "Early boot pre-splash set from first MP4 frame."
  elif [ -f "${PRE_GIF}" ]; then
    [ -f "${SPLASH_DIR}/gif2raw.py" ] || { log "ERROR: gif2raw.py missing"; exit 1; }
    log "Converting ${PRE_GIF} first frame for early boot splash..."
    if ! python3 "${SPLASH_DIR}/gif2raw.py" "${PRE_GIF}" "${BOOT_FRAMES}" "${FB_W}" "${FB_H}" >> "${LOG}" 2>&1; then
      log "ERROR: pre-splash GIF conversion failed - see ${LOG}"
      exit 1
    fi
    if [ -f "${BOOT_FRAMES}/frame_0001.raw" ]; then
      cp "${BOOT_FRAMES}/frame_0001.raw" "${BOOT_RAW}"
      log "Early boot pre-splash set from first GIF frame."
    else
      log "ERROR: pre-splash GIF produced no first frame"
      exit 1
    fi
    rm -rf "${BOOT_FRAMES}"
  elif [ -f "${PRE_PNG}" ]; then
    [ -f "${SPLASH_DIR}/png2raw.py" ] || { log "ERROR: png2raw.py missing"; exit 1; }
    log "Converting ${PRE_PNG} for early boot splash..."
    if ! python3 "${SPLASH_DIR}/png2raw.py" "${PRE_PNG}" "${BOOT_RAW}" "${FB_W}" "${FB_H}" >> "${LOG}" 2>&1; then
      log "ERROR: pre-splash PNG conversion failed - see ${LOG}"
      exit 1
    fi
  else
    rm -f "${BOOT_RAW}"
    rm -rf "${BOOT_FRAMES}"
    log "No pre-splash found; early boot will use the main splash fallback."
  fi
}

convert_main_splash
convert_pre_splash

# player: handles both still image and animation; exits as soon as
# EmulationStation is up (sway takes over the display anyway)
cat > "${PLAYER}" << 'EOF'
#!/bin/sh
FRAMES="/storage/.config/custom-splash-frames"
RAW="/storage/.config/custom-splash.raw"
VIDEO="/storage/.config/custom-splash.mp4"
LAST_RAW="/storage/.config/custom-splash-last.raw"
DURATION_FILE="/storage/.config/custom-splash-duration"
FB="/dev/fb0"

if [ -f "${VIDEO}" ] && command -v mpv >/dev/null 2>&1; then
  # This service is Type=oneshot and ordered before essway, so MPV owns
  # DRM only while the original file plays and releases it before Sway.
  PRELOAD_PID=""
  if [ -f "${LAST_RAW}" ] && [ -f "${DURATION_FILE}" ]; then
    PRELOAD_DELAY=$(awk '{ d=$1-0.15; if (d<0) d=0; printf "%.3f", d }' "${DURATION_FILE}")
    ( sleep "${PRELOAD_DELAY}"; cat "${LAST_RAW}" > "${FB}" 2>/dev/null ) &
    PRELOAD_PID=$!
  fi
  timeout -s KILL 60 mpv --no-config --really-quiet --vo=drm --ao=alsa \
    --fs --keepaspect=yes "${VIDEO}"
  [ -n "${PRELOAD_PID}" ] && wait "${PRELOAD_PID}" 2>/dev/null
  [ -f "${LAST_RAW}" ] && cat "${LAST_RAW}" > "${FB}" 2>/dev/null
elif [ -f "${FRAMES}/delays.txt" ]; then
  END=$(( $(date +%s) + 45 ))
  while [ "$(date +%s)" -lt "${END}" ]; do
    i=0
    while read -r d; do
      i=$((i+1))
      f=$(printf "${FRAMES}/frame_%04d.raw" "${i}")
      [ -f "${f}" ] || break
      cat "${f}" > "${FB}" 2>/dev/null || exit 0
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
After=local-fs.target sound.target pipewire.service pipewire-pulse.service
Before=essway.service

[Service]
Type=oneshot
ExecStart=/storage/.config/custom-splash-play.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >> "${LOG}" 2>&1
systemctl enable custom-splash.service >> "${LOG}" 2>&1 || {
  log "ERROR: could not enable custom-splash.service"
  exit 1
}


# --- hide framebuffer boot console text -----------------------------
# Keep boot messages off the LCD so the custom splash remains clean.
# Serial console stays enabled for recovery/debugging.
BOOT_CONSOLE_ARGS="quiet loglevel=0 vt.global_cursor_default=0 systemd.show_status=0 rd.udev.log-priority=3 rd.systemd.show_status=0"
BOOT_TEXT_BAK="/storage/.config/extlinux.conf.backup-before-hide-text"

install_boot_text_hiding() {
  if [ ! -f "${EXTLINUX}" ]; then
    log "NOTE: ${EXTLINUX} not found - boot text hiding skipped."
    return 0
  fi

  mount -o remount,rw /flash >> "${LOG}" 2>&1 || {
    log "NOTE: could not remount /flash rw, boot text hiding skipped."
    return 0
  }

  [ -f "${BOOT_TEXT_BAK}" ] || cp "${EXTLINUX}" "${BOOT_TEXT_BAK}"

  awk -v extra="${BOOT_CONSOLE_ARGS}" '
    /^[ \t]*APPEND / {
      prefix = substr($0, 1, index($0, "APPEND ") + 6)
      args = substr($0, index($0, "APPEND ") + 7)
      n = split(args, parts, /[ \t]+/)
      out = ""
      for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] == "console=tty0") continue
        if (out != "") out = out " "
        out = out parts[i]
        seen[parts[i]] = 1
      }
      m = split(extra, wanted, /[ \t]+/)
      for (i = 1; i <= m; i++) {
        if (wanted[i] == "" || seen[wanted[i]]) continue
        if (out != "") out = out " "
        out = out wanted[i]
      }
      print prefix out
      next
    }
    { print }
  ' "${EXTLINUX}" > /tmp/extlinux.conf.hide-text

  if grep -q "quiet" /tmp/extlinux.conf.hide-text; then
    cp /tmp/extlinux.conf.hide-text "${EXTLINUX}"
    log "Boot console text hidden (backup: ${BOOT_TEXT_BAK})"
  else
    log "NOTE: boot text hiding failed, extlinux.conf left unchanged."
  fi
  rm -f /tmp/extlinux.conf.hide-text
  mount -o remount,ro /flash >> "${LOG}" 2>&1
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

install_boot_text_hiding
install_early_splash

sync
log "SUCCESS: custom splash installed. Reboot to see it."
exit 0
