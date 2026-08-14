#!/bin/bash

. /etc/profile 2>/dev/null || true

INSTALLER_VERSION="editable"

# User-editable menu display settings.
# ZOOM supports "fit", "1.6", "2.0", "2.2", "2.3", "2.5", or "3.0". The "fit" mode
# displays the entire 480x480 canvas on the 640x480 panel without cropping.
# Positive offsets apply only to numeric zoom modes.
ZOOM="2.2"
OFFSET_RIGHT_PX=30
OFFSET_UP_PX=120

if [ "$(id -u)" != "0" ]; then
  echo "Run this installer as root"
  exit 1
fi

if [ "$(uname -m)" != "aarch64" ]; then
  echo "This installer supports ARM64 ROCKNIX devices"
  exit 1
fi

for CANDIDATE in /storage/.config/drastic /root/.config/drastic; do
  if [ -e "$CANDIDATE/drastic" ] || [ -e "$CANDIDATE/drastic.bin" ]; then
    DRASTIC_DIR="$CANDIDATE"
    break
  fi
done

if [ -z "$DRASTIC_DIR" ]; then
  echo "DraStic installation was not found"
  exit 1
fi

DRASTIC_LAUNCHER="$DRASTIC_DIR/drastic"
DRASTIC_BINARY="$DRASTIC_DIR/drastic.bin"
MENU_LIBRARY="$DRASTIC_DIR/librgdsmenu.so"
SWAY_CONFIG="/storage/.config/sway/config"
SWAP_SCRIPT="/roms/ports/Swap RGDS Screens.sh"

if [ ! -x "$DRASTIC_BINARY" ]; then
  if file "$DRASTIC_LAUNCHER" | grep -q 'ELF'; then
    mv "$DRASTIC_LAUNCHER" "$DRASTIC_BINARY"
  else
    echo "Native DraStic binary was not found"
    exit 1
  fi
fi

PAYLOAD_LINE=$(awk '/^__MENU_LIBRARY__$/ { print NR + 1; exit }' "$0")
if [ -z "$PAYLOAD_LINE" ]; then
  echo "Embedded menu library is missing"
  exit 1
fi

BASE_LIBRARY="$DRASTIC_DIR/librgdsmenu.base.tmp"

tail -n "+$PAYLOAD_LINE" "$0" | base64 -d > "$BASE_LIBRARY" || {
  rm -f "$BASE_LIBRARY"
  echo "Unable to extract the embedded menu library"
  exit 1
}

if ! file "$BASE_LIBRARY" | grep -q 'ELF 64-bit.*ARM aarch64'; then
  rm -f "$BASE_LIBRARY"
  echo "Embedded menu library failed validation"
  exit 1
fi

python3 - "$BASE_LIBRARY" "$MENU_LIBRARY.tmp" \
  "$ZOOM" "$OFFSET_RIGHT_PX" "$OFFSET_UP_PX" <<'PYTHON_PATCH'
import struct
import sys
from pathlib import Path


source_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
zoom_text = sys.argv[3]
offset_right = int(sys.argv[4])
offset_up = int(sys.argv[5])

if zoom_text not in {"fit", "1.6", "2.0", "2", "2.2", "2.3", "2.5", "3.0", "3"}:
    raise SystemExit('ZOOM must be "fit", "1.6", "2.0", "2.2", "2.3", "2.5", or "3.0"')

fit_mode = zoom_text == "fit"
zoom = None if fit_mode else float(zoom_text)
canvas_width = 480
canvas_height = 480
output_width = 720
output_height = 480
if fit_mode:
    crop_x = 0
    crop_y = 0
    crop_width = canvas_width
    crop_height = canvas_height
else:
    crop_width = round(output_width / zoom)
    crop_height = round(output_height / zoom)
    crop_x = round((canvas_width - crop_width) / 2 - offset_right / zoom)
    crop_y = round((canvas_height - crop_height) / 2 + offset_up / zoom)

if crop_x < 0 or crop_y < 0:
    raise SystemExit("Offsets move the crop outside the menu surface")
if crop_x + crop_width > canvas_width or crop_y + crop_height > canvas_height:
    raise SystemExit("Offsets move the crop outside the menu surface")

data = bytearray(source_path.read_bytes())


def replace_exact(offset, expected, replacement):
    actual = bytes(data[offset : offset + len(expected)])
    if actual != expected:
        raise SystemExit(
            f"Embedded library mismatch at 0x{offset:x}: {actual.hex()}"
        )
    if len(expected) != len(replacement):
        raise SystemExit("Internal patch size mismatch")
    data[offset : offset + len(replacement)] = replacement


# Source crop and fixed 640x480 destination rectangle.
replace_exact(
    0x370,
    struct.pack("<4i", 40, 90, 400, 300),
    struct.pack("<4i", crop_x, crop_y, crop_width, crop_height),
)

# Numeric zoom paths use this vector as their crop-origin adjustment. Fit mode
# instead stores per-axis floating-point scale factors for 480x480 -> 640x480.
if fit_mode:
    replace_exact(
        0x390,
        struct.pack("<4i", -320, -720, 0, 0),
        struct.pack("<4f", 1 / 6, 1 / 8, 4 / 3, 1.0),
    )
else:
    replace_exact(
        0x390,
        struct.pack("<4i", -320, -720, 0, 0),
        struct.pack("<4i", -8 * crop_x, -8 * crop_y, 0, 0),
    )

if fit_mode:
    nop = bytes.fromhex("1f2003d5")
    # Before this point the lanes contain (8*x, 8*y, width, height). Apply
    # (1/6, 1/8, 4/3, 1) to produce the full 640x480 destination rectangle.
    replace_exact(0x6A8, bytes.fromhex("e8cc8c52"), bytes.fromhex("00d8214e"))
    replace_exact(0x6AC, bytes.fromhex("c8ccac72"), bytes.fromhex("00dc216e"))
    replace_exact(0x6B0, bytes.fromhex("0184a14e"), bytes.fromhex("01b8a14e"))
    replace_exact(0x6B4, bytes.fromhex("0054234f"), nop)
    replace_exact(0x6B8, bytes.fromhex("0144186e"), nop)
    replace_exact(0x6BC, bytes.fromhex("000d044e"), nop)
    replace_exact(0x6C0, bytes.fromhex("22c0a04e"), nop)
    replace_exact(0x6C4, bytes.fromhex("20c0a00e"), nop)
    replace_exact(0x6C8, bytes.fromhex("0058824e"), nop)
    replace_exact(0x6CC, bytes.fromhex("01043f4f"), nop)
    replace_exact(0x6D0, bytes.fromhex("0114216f"), nop)
elif zoom == 2.0:
    nop = bytes.fromhex("1f2003d5")
    replace_exact(0x6A8, bytes.fromhex("e8cc8c52"), nop)
    replace_exact(0x6AC, bytes.fromhex("c8ccac72"), nop)
    replace_exact(0x6BC, bytes.fromhex("000d044e"), bytes.fromhex("21043e4f"))
    replace_exact(0x6C0, bytes.fromhex("22c0a04e"), nop)
    replace_exact(0x6C4, bytes.fromhex("20c0a00e"), nop)
    replace_exact(0x6C8, bytes.fromhex("0058824e"), nop)
    replace_exact(0x6CC, bytes.fromhex("01043f4f"), nop)
    replace_exact(0x6D0, bytes.fromhex("0114216f"), nop)
elif zoom == 2.2:
    nop = bytes.fromhex("1f2003d5")
    replace_exact(0x6A8, bytes.fromhex("e8cc8c52"), nop)
    replace_exact(0x6AC, bytes.fromhex("c8ccac72"), nop)
    # The intermediate vector is 8x the source rectangle. A 141/512
    # fixed-point multiplier produces 2.203125x, effectively 2.2x.
    replace_exact(0x6BC, bytes.fromhex("000d044e"), bytes.fromhex("a205044f"))
    replace_exact(0x6C0, bytes.fromhex("22c0a04e"), bytes.fromhex("219ca24e"))
    replace_exact(0x6C4, bytes.fromhex("20c0a00e"), bytes.fromhex("2104374f"))
    replace_exact(0x6C8, bytes.fromhex("0058824e"), nop)
    replace_exact(0x6CC, bytes.fromhex("01043f4f"), nop)
    replace_exact(0x6D0, bytes.fromhex("0114216f"), nop)
elif zoom == 2.3:
    nop = bytes.fromhex("1f2003d5")
    replace_exact(0x6A8, bytes.fromhex("e8cc8c52"), nop)
    replace_exact(0x6AC, bytes.fromhex("c8ccac72"), nop)
    # The intermediate vector is 8x the source rectangle. A 147/512
    # fixed-point multiplier produces 2.296875x, effectively 2.3x.
    replace_exact(0x6BC, bytes.fromhex("000d044e"), bytes.fromhex("6206044f"))
    replace_exact(0x6C0, bytes.fromhex("22c0a04e"), bytes.fromhex("219ca24e"))
    replace_exact(0x6C4, bytes.fromhex("20c0a00e"), bytes.fromhex("2104374f"))
    replace_exact(0x6C8, bytes.fromhex("0058824e"), nop)
    replace_exact(0x6CC, bytes.fromhex("01043f4f"), nop)
    replace_exact(0x6D0, bytes.fromhex("0114216f"), nop)
elif zoom == 2.5:
    nop = bytes.fromhex("1f2003d5")
    replace_exact(0x6A8, bytes.fromhex("e8cc8c52"), nop)
    replace_exact(0x6AC, bytes.fromhex("c8ccac72"), nop)
    # The intermediate vector is 8x the source rectangle. Multiplying by 5
    # and dividing by 16 produces an exact 2.5x destination rectangle.
    replace_exact(0x6BC, bytes.fromhex("000d044e"), bytes.fromhex("a204004f"))
    replace_exact(0x6C0, bytes.fromhex("22c0a04e"), bytes.fromhex("219ca24e"))
    replace_exact(0x6C4, bytes.fromhex("20c0a00e"), bytes.fromhex("21043c4f"))
    replace_exact(0x6C8, bytes.fromhex("0058824e"), nop)
    replace_exact(0x6CC, bytes.fromhex("01043f4f"), nop)
    replace_exact(0x6D0, bytes.fromhex("0114216f"), nop)
elif zoom == 3.0:
    nop = bytes.fromhex("1f2003d5")
    replace_exact(0x6A8, bytes.fromhex("e8cc8c52"), nop)
    replace_exact(0x6AC, bytes.fromhex("c8ccac72"), nop)
    # The intermediate vector is 8x the source rectangle. Multiply it by 3,
    # then divide by 8 to produce an exact 3x destination rectangle.
    replace_exact(0x6BC, bytes.fromhex("000d044e"), bytes.fromhex("6204004f"))
    replace_exact(0x6C0, bytes.fromhex("22c0a04e"), bytes.fromhex("219ca24e"))
    replace_exact(0x6C4, bytes.fromhex("20c0a00e"), bytes.fromhex("21043d4f"))
    replace_exact(0x6C8, bytes.fromhex("0058824e"), nop)
    replace_exact(0x6CC, bytes.fromhex("01043f4f"), nop)
    replace_exact(0x6D0, bytes.fromhex("0114216f"), nop)

output_path.write_bytes(data)
mode_label = "fit 480x480" if fit_mode else f"{zoom:g}x"
print(
    f"Built menu patch: mode={mode_label}, right={offset_right}px, "
    f"up={offset_up}px, crop={crop_x},{crop_y},{crop_width},{crop_height}"
)
PYTHON_PATCH
PATCH_STATUS=$?
rm -f "$BASE_LIBRARY"
if [ "$PATCH_STATUS" != "0" ]; then
  rm -f "$MENU_LIBRARY.tmp"
  echo "Unable to build the configured menu library"
  exit 1
fi

if ! file "$MENU_LIBRARY.tmp" | grep -q 'ELF 64-bit.*ARM aarch64'; then
  rm -f "$MENU_LIBRARY.tmp"
  echo "Configured menu library failed validation"
  exit 1
fi

chmod 755 "$MENU_LIBRARY.tmp"
mv "$MENU_LIBRARY.tmp" "$MENU_LIBRARY"

TOUCH_LIBRARY=""
for CANDIDATE in /usr/lib/libdrastouch.so /usr/lib64/libdrastouch.so; do
  if [ -f "$CANDIDATE" ]; then
    TOUCH_LIBRARY="$CANDIDATE:"
    break
  fi
done

cat > "$DRASTIC_LAUNCHER.tmp" <<EOF
#!/bin/bash

export SDL_VIDEO_WAYLAND_WMCLASS="drastic"
export LD_PRELOAD="${TOUCH_LIBRARY}${MENU_LIBRARY}"
exec "$DRASTIC_BINARY" "\$@"
EOF

chmod 755 "$DRASTIC_LAUNCHER.tmp"
mv "$DRASTIC_LAUNCHER.tmp" "$DRASTIC_LAUNCHER"

if [ -f "$SWAY_CONFIG" ]; then
  TOP_OUTPUT="DSI-2"
  BOTTOM_OUTPUT="DSI-1"
  TOUCH_IDENTIFIER=""

  if command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    OUTPUTS=$(swaymsg -t get_outputs 2>/dev/null | jq -r '.[].name' 2>/dev/null)
    if ! printf '%s\n' "$OUTPUTS" | grep -qx "$TOP_OUTPUT"; then
      TOP_OUTPUT=$(printf '%s\n' "$OUTPUTS" | sed -n '1p')
      BOTTOM_OUTPUT=$(printf '%s\n' "$OUTPUTS" | sed -n '2p')
    fi
    TOUCH_IDENTIFIER=$(swaymsg -t get_inputs 2>/dev/null \
      | jq -r '.[] | select(.type == "touch") | .identifier' 2>/dev/null \
      | head -n 1)
  fi

  RULE="for_window [app_id=\"drastic\"] border none, move absolute position 0 0"
  if [ -n "$BOTTOM_OUTPUT" ]; then
    RULE="$RULE, output $BOTTOM_OUTPUT power on"
  fi
  if [ -n "$TOP_OUTPUT" ]; then
    RULE="$RULE, output $TOP_OUTPUT power on, focus"
  fi
  if [ -n "$TOUCH_IDENTIFIER" ] && [ -n "$TOP_OUTPUT" ]; then
    RULE="$RULE, input \"$TOUCH_IDENTIFIER\" map_to_output $TOP_OUTPUT"
  fi
  if [ -x "$SWAP_SCRIPT" ]; then
    RULE="$RULE, exec /bin/bash \"$SWAP_SCRIPT\" --watch-drastic"
  fi

  awk -v rule="$RULE" '
    BEGIN { replaced = 0 }
    /^for_window \[app_id=".*drastic.*"\]/ {
      if (!replaced) print rule
      replaced = 1
      next
    }
    { print }
    END { if (!replaced) print rule }
  ' "$SWAY_CONFIG" > "$SWAY_CONFIG.tmp"
  mv "$SWAY_CONFIG.tmp" "$SWAY_CONFIG"

  if [ -n "$BOTTOM_OUTPUT" ]; then
    sed -i "/^output $BOTTOM_OUTPUT bg /d" "$SWAY_CONFIG"
    printf 'output %s bg #000000 solid_color\n' "$BOTTOM_OUTPUT" >> "$SWAY_CONFIG"
  fi

  swaymsg reload >/dev/null 2>&1 || true
fi

sync
echo "DraStic ${ZOOM}x menu installed: right=${OFFSET_RIGHT_PX}px, up=${OFFSET_UP_PX}px"
exit 0

__MENU_LIBRARY__
f0VMRgIBAQAAAAAAAAAAAAMAtwABAAAAAAAAAAAAAABAAAAAAAAAAAgJAAAAAAAAAAAAAEAAOAAJ
AEAAEQAQAAYAAAAEAAAAQAAAAAAAAABAAAAAAAAAAEAAAAAAAAAA+AEAAAAAAAD4AQAAAAAAAAgA
AAAAAAAAAQAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADEBAAAAAAAAMQEAAAAAAAAAAAB
AAAAAAABAAAABQAAAMQEAAAAAAAAxAQBAAAAAADEBAEAAAAAAIwCAAAAAAAAjAIAAAAAAAAAAAEA
AAAAAAEAAAAGAAAAUAcAAAAAAABQBwIAAAAAAFAHAgAAAAAAAAEAAAAAAACwCAAAAAAAAAAAAQAA
AAAAAQAAAAYAAABQCAAAAAAAAFAIAwAAAAAAUAgDAAAAAAAAAAAAAAAAACgAAAAAAAAAAAABAAAA
AAACAAAABgAAAFAHAAAAAAAAUAcCAAAAAABQBwIAAAAAAOAAAAAAAAAA4AAAAAAAAAAIAAAAAAAA
AFLldGQEAAAAUAcAAAAAAABQBwIAAAAAAFAHAgAAAAAAAAEAAAAAAACwCAAAAAAAAAEAAAAAAAAA
UOV0ZAQAAADUAwAAAAAAANQDAAAAAAAA1AMAAAAAAAAkAAAAAAAAACQAAAAAAAAABAAAAAAAAABR
5XRkBgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAABQAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAASAAkAxAQB
AAAAAABsAAAAAAAAABoAAAASAAkAMAUBAAAAAACcAAAAAAAAACwAAAASAAkAzAUBAAAAAABQAQAA
AAAAAAEAAAACAAAAAQAAABoAAABEAkAABAAEAAIAAADyGNhYBu8NCqMGcScFAAAABQAAAAMAAAAA
AAAAAgAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAU0RMX0NyZWF0ZVJlbmRlcmVyAGRs
c3ltAFNETF9TZXRXaW5kb3dTaXplAFNETF9SZW5kZXJDb3B5AGxpYnJnZHNtZW51LnNvAAAAAAAA
AEgIAgAAAAAAAgQAAAEAAAAAAAAAAAAAACgAAABaAAAAkAEAACwBAAAAAAAAAAAAAIACAADgAQAA
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
AAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAMwAAAAEAAAACAAAAAAAAANQDAAAAAAAA1AMAAAAAAAAk
AAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAEEAAAABAAAAAgAAAAAAAAD4AwAAAAAAAPgD
AAAAAAAAzAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAABLAAAAAQAAAAYAAAAAAAAAxAQB
AAAAAADEBAAAAAAAAFgCAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAUQAAAAEAAAAGAAAg
AAAAACAHAQAAAAAAIAcAAAAAAAAwAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAFYAAAAG
AAAAAwAAAAAAAABQBwIAAAAAAFAHAAAAAAAA4AAAAAAAAAAEAAAAAAAAAAgAAAAAAAAAEAAAAAAA
AABfAAAAAQAAAAMAAAAAAAAAMAgCAAAAAAAwCAAAAAAAACAAAAAAAAAAAAAAAAAAAAAIAAAAAAAA
AAAAAAAAAAAAaAAAAAgAAAADAAAAAAAAAFAIAgAAAAAAUAgAAAAAAACwBwAAAAAAAAAAAAAAAAAA
AQAAAAAAAAAAAAAAAAAAAHcAAAAIAAAAAwAAAAAAAABQCAMAAAAAAFAIAAAAAAAAKAAAAAAAAAAA
AAAAAAAAAAgAAAAAAAAAAAAAAAAAAAB8AAAAAQAAADAAAAAAAAAAAAAAAAAAAABQCAAAAAAAACgA
AAAAAAAAAAAAAAAAAAABAAAAAAAAAAEAAAAAAAAAhQAAAAMAAAAAAAAAAAAAAAAAAAAAAAAAeAgA
AAAAAACPAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAA==
