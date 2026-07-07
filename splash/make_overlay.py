#!/usr/bin/env python3
"""Build an uncompressed initramfs overlay cpio (newc format).

The overlay contains a single file, usr/bin/rocknix-splash, which the
kernel unpacks OVER the built-in initramfs copy. That binary normally
draws the ROCKNIX boot logo; our replacement shell script draws the
custom splash raw from /storage instead (mounted before load_splash
runs in the ROCKNIX init).

Loaded via an INITRD line in /flash/extlinux/extlinux.conf. Plain
(uncompressed) cpio needs no compressor and is decoded natively by
the kernel regardless of its CONFIG_RD_* compression options.

Usage: make_overlay.py output.cpio
"""
import sys

SPLASH_SCRIPT = b"""#!/bin/sh
# custom splash overlay - replaces the ROCKNIX boot logo.
# /storage is already mounted when init calls this (load_splash runs
# after mount_storage). Marker file lets the installer verify the
# overlay was actually loaded by the bootloader.
echo "overlay active" > /storage/.config/custom-splash-overlay-ran 2>/dev/null
for S in /storage/.config/custom-splash-boot.raw \\
         /storage/.config/custom-splash.raw \\
         /storage/.config/custom-splash-frames/frame_0001.raw; do
  if [ -f "${S}" ]; then
    cat "${S}" >/dev/fb0 2>/dev/null
    break
  fi
done
exit 0
"""


def align4(buf):
    return buf + b"\0" * (-len(buf) % 4)


def entry(name, data, mode):
    name_z = name.encode() + b"\0"
    hdr = b"070701" + b"".join(
        b"%08X" % v
        for v in (
            0,           # ino
            mode,        # mode
            0, 0,        # uid, gid
            1,           # nlink
            0,           # mtime
            len(data),   # filesize
            0, 0, 0, 0,  # devmajor/minor, rdevmajor/minor
            len(name_z), # namesize
            0,           # check
        )
    )
    return align4(hdr + name_z) + align4(data)


def main():
    if len(sys.argv) != 2:
        print("usage: make_overlay.py output.cpio")
        sys.exit(1)
    cpio = entry("usr/bin/rocknix-splash", SPLASH_SCRIPT, 0o100755)
    cpio += entry("TRAILER!!!", b"", 0)
    with open(sys.argv[1], "wb") as f:
        f.write(cpio)
    print("OK: overlay cpio written (%d bytes)" % len(cpio))


if __name__ == "__main__":
    main()
