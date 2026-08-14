#!/bin/sh
set -eu

# Installs the bundled RetroArch settings on ROCKNIX or another Linux device.
# An optional first argument overrides the normal RetroArch config directory.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ARCHIVE="$SCRIPT_DIR/retroarch-settings.tar.gz"
TARGET=${1:-/storage/.config/retroarch}
SYSTEM_CONFIG=/storage/.config/system/configs/system.cfg
EXPECTED_SHA256=695b413ff9c238c070bff561bd5d1f8c1686cfdc432a851ddc6e174c29c58cd2

fail() {
    echo "Error: $*" >&2
    exit 1
}

[ -f "$ARCHIVE" ] || fail "Settings archive not found: $ARCHIVE"
command -v tar >/dev/null 2>&1 || fail "tar is required"

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
    [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail "Archive checksum mismatch"
else
    echo "Warning: sha256sum unavailable; skipping checksum verification."
fi

# Refuse archive entries that could escape the selected target directory.
tar tzf "$ARCHIVE" | while IFS= read -r entry; do
    case "$entry" in
        /*|../*|*/../*|*/..)
            fail "Unsafe archive entry: $entry"
            ;;
    esac
done

if [ -e "$TARGET" ] && [ ! -d "$TARGET" ]; then
    fail "Target exists but is not a directory: $TARGET"
fi

mkdir -p "$TARGET" || fail "Cannot create target (run as root): $TARGET"

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${TARGET}.backup-${STAMP}"
BACKED_UP=0

# Back up only files that the payload will overwrite. Saves, states, BIOS files,
# screenshots, thumbnails, and unrelated RetroArch data remain untouched.
tar tzf "$ARCHIVE" | while IFS= read -r entry; do
    case "$entry" in
        */|'') continue ;;
    esac

    if [ -f "$TARGET/$entry" ] || [ -L "$TARGET/$entry" ]; then
        mkdir -p "$BACKUP/$(dirname -- "$entry")"
        cp -p "$TARGET/$entry" "$BACKUP/$entry"
        printf '%s\n' "$entry" >> "$BACKUP/.installed-files"
    fi
done

if [ -d "$BACKUP" ]; then
    BACKED_UP=1
fi

tar xzf "$ARCHIVE" -C "$TARGET"

# ROCKNIX regenerates the active RetroArch menu driver from system.cfg each
# time an emulator launches. Keep that source of truth in sync with the
# bundled RGUI config, otherwise ROCKNIX will silently switch back to Ozone.
if [ -f "$SYSTEM_CONFIG" ]; then
    SYSTEM_BACKUP="${SYSTEM_CONFIG}.backup-${STAMP}"
    cp -p "$SYSTEM_CONFIG" "$SYSTEM_BACKUP"

    if grep -q '^global\.retroarch\.menu_driver=' "$SYSTEM_CONFIG"; then
        sed -i 's/^global\.retroarch\.menu_driver=.*/global.retroarch.menu_driver=rgui/' "$SYSTEM_CONFIG"
    else
        printf '\nglobal.retroarch.menu_driver=rgui\n' >> "$SYSTEM_CONFIG"
    fi
fi

echo "RetroArch settings installed in: $TARGET"
if [ "$BACKED_UP" -eq 1 ]; then
    echo "Replaced files were backed up in: $BACKUP"
else
    echo "No existing settings files needed backup."
fi
if [ -n "${SYSTEM_BACKUP:-}" ]; then
    echo "ROCKNIX menu driver set to RGUI. Previous system settings: $SYSTEM_BACKUP"
fi
echo "Restart RetroArch before using the new settings."
