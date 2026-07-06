# Custom Boot Splash for ROCKNIX

Replaces the boot splash on your device with your own image,
shown from early boot be it PNG or a GIF 🎉

## Quick start

0. Install portmaster.
1. Copy your image to `roms/ports/splash/` as either:
   - `splash.gif` — animated GIF, plays on loop during boot
     (preferred if both files exist; capped at 48 frames)
   - `splash.png` — still image, 8-bit RGB or RGBA, non-interlaced
   - Any size — scaled to fit and centered on a black background
   - Screen is 640x480, so ~480x480 or 640x480 looks best. Smaller
     GIFs convert faster (a 12-frame 480x480 GIF takes ~20s on-device).
2. Run **Install_Custom_Splash** from the Ports menu in EmulationStation
   (or via SSH: `sh /storage/roms/ports/Install_Custom_Splash.sh`)
3. Reboot. Done.

To go back to stock: run **Restore_Original_Splash** from the Ports menu.

If both `splash.gif` and `splash.png` exist, the GIF wins — delete or
rename `splash.gif` and re-run the installer to switch back to the PNG.

Every run writes its result to `roms/ports/splash/install.log` — check
there if something doesn't work.

**Currently installed:** a test spinning-logo GIF (12 frames, 80ms per
frame). Replace `splash.gif` and re-run the installer to change it.

## Files

| File | Purpose |
|------|---------|
| `ports/Install_Custom_Splash.sh` | Converts `splash.gif`/`splash.png` and installs the boot service |
| `ports/Restore_Original_Splash.sh` | Removes the custom splash, back to stock |
| `ports/splash/splash.gif` | Your animated splash (you provide this) |
| `ports/splash/splash.png` | Your still splash image (you provide this) |
| `ports/splash/png2raw.py` | PNG → raw framebuffer converter (pure python, runs on-device) |
| `ports/splash/gif2raw.py` | GIF → raw frame sequence converter (pure python, runs on-device) |
| `ports/splash/install.log` | Log of every install/restore run |
| `/storage/.config/custom-splash.raw` | Converted still image |
| `/storage/.config/custom-splash-frames/` | Converted GIF frames + delays.txt |
| `/storage/.config/custom-splash-play.sh` | Boot-time player (loops GIF, or draws the still once) |
| `/storage/.config/system.d/custom-splash.service` | The systemd unit that runs the player |

## How it works (and why it's done this way)

The boot sequence on this device shows three possible splash stages:

1. **U-Boot** (mainline 2026.01, flashed in the raw area of the SD card
   before the first partition) — the installed build has **no logo
   compiled in**, so nothing is shown at this stage.
2. **Kernel/initramfs** — the initramfs runs `rocknix-splash`, which
   draws the red/gray ROCKNIX logo to the framebuffer. This binary has
   the logo hardcoded as SVG path data and lives *inside* the kernel
   image (`/flash/KERNEL`), so it cannot be changed without building a
   custom ROCKNIX image. This is the logo you briefly see at power-on.
3. **EmulationStation** — ROCKNIX launches ES with `--no-splash`, so
   the ES `splash.svg` resource is never displayed at all. Replacing it
   does nothing (first thing we tried).

This tool works by adding a systemd service that runs early in boot
(after `/storage` is mounted, before EmulationStation) and writes your
image directly to the framebuffer (`/dev/fb0`, 640x480 BGRX), painting
over the ROCKNIX logo. GIFs are pre-converted to raw frames at install
time; at boot a tiny shell player loops them (respecting each frame's
delay) until EmulationStation starts, then exits. The stock logo still
flashes for the first second or two — that part is baked into the
kernel and can only be removed with a custom ROCKNIX build.

The install script converts your image on-device with `png2raw.py` /
`gif2raw.py` (stdlib-only python: decodes, scales, composites alpha
over black, writes raw BGRX). Converted output is stored under
`/storage/.config/` because `/storage/roms` is not yet mounted when
the splash service runs.

## Troubleshooting

- **Still seeing only the ROCKNIX logo?**
  `systemctl status custom-splash.service` — after a successful boot it
  shows `inactive (dead)` with `status=0/SUCCESS` and a `Duration` of a
  few seconds (the player exits once EmulationStation starts). A
  `failed` state or non-zero exit means something is wrong — check
  `install.log` and `journalctl -u custom-splash` for details.
- **"unsupported PNG" error:** re-export the image as a standard 8-bit
  PNG (no 16-bit color, no interlacing).
- **GIF conversion is slow or huge:** each frame becomes a 1.2MB raw
  file; long GIFs are capped at 48 frames. Trim/resize the GIF first
  for faster conversion and less storage.
- **Animation stops early in boot:** intentional — the player exits as
  soon as EmulationStation starts, since it takes over the display.
- **Splash looks stretched/oversized:** the converter preserves aspect
  ratio and never upscales; use an image at least 480px tall for a
  full-height splash.

## rocknix-boot-analysis folder

`roms/ports/rocknix-boot-analysis/` contains artifacts from the boot
investigation:

- `sd_boot_area.img` — **backup of the SD card's first 16MB**
  (bootloader area). If a future U-Boot experiment breaks boot, restore
  from another machine with the SD in a reader:
  `dd if=sd_boot_area.img of=/dev/<sdcard> bs=512`
- `sd_uboot_payload.bin` — the U-Boot binary currently on the SD,
  extracted from its FIT image (no logo compiled in)
- `Generic_uboot.bin` — newer U-Boot build from `/usr/share/bootloader`
  (contains the stock U-Boot submarine logo at file offset 8773024)
- `uboot_logo.bmp` / `.png` — that embedded logo, extracted (160x160
  8-bit BMP — the format a custom U-Boot logo would need)
