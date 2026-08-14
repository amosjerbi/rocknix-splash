# DraStic 1.5x Menu Installer

`drastic15x menu.sh` installs an enlarged DraStic pause menu for ARM64 ROCKNIX dual-screen devices.

## What It Changes

- Keeps native DraStic gameplay across both RGDS screens.
- Displays the pause menu on the top screen at `640x480`.
- Enlarges the menu proportionally to `1.5x` without horizontal stretching.
- Keeps the bottom screen black while the pause menu is open.
- Preserves the original DraStic executable as `/storage/.config/drastic/drastic.bin`.
- Installs an embedded ARM64 menu library; no companion files are required.
- Detects the available touchscreen, outputs, and `libdrastouch.so` path.

## Install

1. Copy `drastic15x menu.sh` to `/roms/ports/`.
2. Make it executable: `chmod +x "/roms/ports/drastic15x menu.sh"`.
3. Run it once from the ROCKNIX Ports collection.
4. Exit and relaunch DraStic if a game was already running.

The installer is idempotent and can be run again safely.

## Requirements

- ARM64 ROCKNIX device.
- DraStic installed under `/storage/.config/drastic` or `/root/.config/drastic`.
- Root access, which ROCKNIX Ports scripts normally have.

## Restore Native DraStic

Run over SSH while DraStic is closed:

```sh
rm -f /storage/.config/drastic/drastic
mv /storage/.config/drastic/drastic.bin /storage/.config/drastic/drastic
rm -f /storage/.config/drastic/librgdsmenu.so
chmod +x /storage/.config/drastic/drastic
```

Restart ROCKNIX after restoring if the launcher still shows stale behavior.

## Notes

- This package is intended for ARM64 RGDS-style dual-screen ROCKNIX devices.
- The menu crop is optimized for the main menu and configuration submenus.
- Use `Swap RGDS Screens.sh` separately to change which panel displays EmulationStation.
