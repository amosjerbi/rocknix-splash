# Swap RGDS Screens

`Swap RGDS Screens.sh` toggles the ROCKNIX EmulationStation launcher between the RGDS top and bottom displays.

## Display Mapping

- `DSI-2`: physical top screen.
- `DSI-1`: physical bottom screen.

## What It Changes

- Moves workspace 1 and EmulationStation to the other display.
- Powers on the selected display and powers off the previous display.
- Restores EmulationStation focus after the Ports launcher returns.
- Reattaches the controller, virtual keyboard, and touchscreen.
- Maps touch input to the selected launcher display.
- Preserves native DraStic dual-screen gameplay rules.
- Sets `rocknix.bottomscreen.type=none` to disable the LowerDeck virtual-console panel.
- Closes any active LowerDeck window and removes its stale PID file.

## Use

1. Exit any running game first.
2. Run `Swap RGDS Screens.sh` from the Ports collection.
3. Wait several seconds for EmulationStation to return.
4. Run it again to swap back.

Avoid launching the script repeatedly before the previous swap has finished.

## Automatic DraStic Recovery

When DraStic exits, the script's watcher restores the launcher to the display recorded in the Sway configuration.

## SSH Recovery

If the launcher is visible but does not respond, run:

```sh
export XDG_RUNTIME_DIR=/var/run/0-runtime-dir
export SWAYSOCK=/var/run/0-runtime-dir/sway-ipc.0.sock
swaymsg '[app_id="emulationstation"] focus'
```

To force the launcher onto the top screen:

```sh
/roms/ports/Swap\ RGDS\ Screens.sh --apply DSI-2 DSI-1
```

To force it onto the bottom screen:

```sh
/roms/ports/Swap\ RGDS\ Screens.sh --apply DSI-1 DSI-2
```

## Re-enable LowerDeck

The swap script disables LowerDeck on every normal run. To use LowerDeck again, remove the `disable_bottomscreen_ui` call from the script and run:

```sh
. /etc/profile
set_setting rocknix.bottomscreen.type vc
```
