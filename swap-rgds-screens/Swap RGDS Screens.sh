#!/bin/bash

. /etc/profile

SWAY_CONFIG="/storage/.config/sway/config"

preserve_native_rgds() {
  sed -i \
    's|^for_window \[app_id=".*drastic.*"\].*|for_window [app_id="drastic"] border none, move absolute position 0 0, output DSI-1 power on, output DSI-2 power on, focus, input "1046:911:Goodix_Capacitive_TouchScreen" map_to_output DSI-2, exec /bin/bash "/roms/ports/Swap RGDS Screens.sh" --watch-drastic|' \
    "$SWAY_CONFIG"
}

disable_bottomscreen_ui() {
  if command -v set_setting >/dev/null 2>&1; then
    set_setting rocknix.bottomscreen.type none
  fi

  lowerdeck_ids=$(pgrep -f '^python3 /usr/share/lowerdeck/main.py ' 2>/dev/null || true)
  [ -z "$lowerdeck_ids" ] || kill $lowerdeck_ids
  rm -f /run/lowerdeck.pid
  swaymsg '[app_id="lowerdeck"] kill' >/dev/null 2>&1 || true
}

current_launcher_output() {
  awk '
    $1 == "workspace" && $2 == "1" && $3 == "output" {
      for (field = 4; field <= NF; field++) {
        if ($field ~ /^DSI-[12]$/) output = $field
      }
    }
    END { print output }
  ' "$SWAY_CONFIG"
}

attach_launcher_inputs() {
  if ! command -v jq >/dev/null 2>&1; then
    return
  fi

  swaymsg -t get_inputs 2>/dev/null \
    | jq -r '.[] | select(.name | test("retrogame_joypad|wlr_virtual_keyboard"; "i")) | .identifier' \
    | while IFS= read -r identifier; do
        [ -z "$identifier" ] || swaymsg "seat seat0 attach \"$identifier\"" >/dev/null
      done

  swaymsg -t get_inputs 2>/dev/null \
    | jq -r '.[] | select(.type == "touch") | .identifier' \
    | sort -u \
    | while IFS= read -r identifier; do
        [ -z "$identifier" ] || swaymsg "input \"$identifier\" map_to_output $TARGET" >/dev/null
      done

  swaymsg "seat seat0 fallback yes" >/dev/null
}

apply_launcher_screen() {
  TARGET="$1"
  OLD_TARGET="$2"

  case "$TARGET:$OLD_TARGET" in
    DSI-1:DSI-2|DSI-2:DSI-1) ;;
    *) return 1 ;;
  esac

  swaymsg "output $TARGET enable" >/dev/null
  swaymsg "output $TARGET power on" >/dev/null
  swaymsg "[app_id=\"emulationstation\"] move container to workspace 1" >/dev/null
  swaymsg "workspace 1" >/dev/null
  swaymsg "move workspace to output $TARGET" >/dev/null
  swaymsg "focus output $TARGET" >/dev/null
  swaymsg "workspace 1" >/dev/null
  attach_launcher_inputs
  swaymsg "[app_id=\"emulationstation\"] focus" >/dev/null
  sleep 1
  swaymsg "output $OLD_TARGET power off" >/dev/null
  sleep 1
  swaymsg "workspace 1" >/dev/null
  swaymsg "[app_id=\"emulationstation\"] focus" >/dev/null
  sleep 1
  swaymsg "[app_id=\"emulationstation\"] focus" >/dev/null
}

if [ "$1" = "--apply" ]; then
  apply_launcher_screen "$2" "$3"
  exit
fi

if [ "$1" = "--watch-drastic" ]; then
  sleep 1
  while pidof drastic drastic.bin >/dev/null 2>&1; do
    sleep 1
  done

  TARGET=$(current_launcher_output)
  if [ "$TARGET" = "DSI-1" ]; then
    OLD_TARGET="DSI-2"
  else
    OLD_TARGET="DSI-1"
  fi
  apply_launcher_screen "$TARGET" "$OLD_TARGET"
  exit
fi

if [ ! -f "$SWAY_CONFIG" ]; then
  exit 1
fi

disable_bottomscreen_ui
preserve_native_rgds

CURRENT_TARGET=$(current_launcher_output)

if [ "$CURRENT_TARGET" = "DSI-1" ]; then
  TARGET="DSI-2"
  OLD_TARGET="DSI-1"
else
  TARGET="DSI-1"
  OLD_TARGET="DSI-2"
fi

sed -i \
  -e "s|^workspace 1 output .*|workspace 1 output $TARGET|" \
  -e 's|^for_window \[app_id="emulationstation"\] move output .*|for_window [app_id="emulationstation"] move container to workspace 1|' \
  -e 's|^for_window \[app_id="emulationstation"\] reload$|for_window [app_id="emulationstation"] focus|' \
  -e "s|^exec_always swaymsg '\[app_id=\"emulationstation\"\]' focus.*|exec_always swaymsg '[app_id=\"emulationstation\"]' focus, output $OLD_TARGET power off|" \
  "$SWAY_CONFIG"

swaymsg reload >/dev/null
sleep 2
apply_launcher_screen "$TARGET" "$OLD_TARGET"

sync
