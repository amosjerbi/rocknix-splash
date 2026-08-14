RetroArch configuration backup
==============================

Included:
- retroarch.cfg
- retroarch-core-options.cfg
- 32-bit and 64-bit append configs
- top-level per-core .opt settings and .rmp remaps
- config/ per-core options, overrides, and remap directories

Not included:
- saves, save states, screenshots, BIOS/system files, cheats, cores,
  downloads, thumbnails, logs, recordings, or MAME high-score data

Install on a ROCKNIX device
---------------------------

1. Copy this entire retroarch_config directory to the device.
2. Open a terminal in the directory.
3. Run as root:

   chmod +x install.sh
   ./install.sh

The default destination is /storage/.config/retroarch. To install elsewhere:

   ./install.sh /custom/path/to/retroarch

The installer verifies the payload checksum and backs up only settings files
that it replaces. Saves and other unrelated RetroArch data are untouched.
