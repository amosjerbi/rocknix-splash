#!/usr/bin/env python3
"""Convert an 8-bit RGB/RGBA PNG into a raw BGRX framebuffer image.

Pure stdlib (zlib only) so it runs on ROCKNIX's bundled python3.
The source image is scaled (nearest-neighbor, aspect preserved) and
centered on a black canvas matching the framebuffer size.

Usage: png2raw.py input.png output.raw WIDTH HEIGHT
"""
import struct
import sys
import zlib


def fail(msg):
    print("ERROR: %s" % msg)
    sys.exit(1)


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail("%s is not a PNG file" % path)
    pos, idat = 8, b""
    width = height = ctype = None
    while pos < len(data):
        (length, ctag) = struct.unpack(">I4s", data[pos:pos + 8])
        pos += 8
        chunk = data[pos:pos + length]
        pos += length + 4  # skip CRC
        if ctag == b"IHDR":
            width, height, depth, ctype, comp, filt, inter = struct.unpack(
                ">IIBBBBB", chunk)
            if depth != 8 or ctype not in (2, 6) or inter != 0:
                fail("unsupported PNG - need 8-bit RGB or RGBA, "
                     "non-interlaced (re-export the image)")
        elif ctag == b"IDAT":
            idat += chunk
        elif ctag == b"IEND":
            break
    if width is None:
        fail("no IHDR chunk found")
    raw = zlib.decompress(idat)
    ch = 4 if ctype == 6 else 3
    stride = width * ch
    pixels = bytearray()
    prev = bytearray(stride)
    p = 0
    for _ in range(height):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:  # Sub
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 0xFF
        elif f == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:  # Average
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:  # Paeth
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                if pa <= pb and pa <= pc:
                    pred = a
                elif pb <= pc:
                    pred = b
                else:
                    pred = c
                line[i] = (line[i] + pred) & 0xFF
        pixels += line
        prev = line
    return width, height, ch, bytes(pixels)


def main():
    if len(sys.argv) != 5:
        fail("usage: png2raw.py input.png output.raw WIDTH HEIGHT")
    src, dst = sys.argv[1], sys.argv[2]
    fbw, fbh = int(sys.argv[3]), int(sys.argv[4])

    w, h, ch, px = read_png(src)

    # scale to fit, preserve aspect
    scale = min(fbw / w, fbh / h, 1.0)
    dw, dh = max(1, int(w * scale)), max(1, int(h * scale))
    xoff, yoff = (fbw - dw) // 2, (fbh - dh) // 2

    fb = bytearray(fbw * fbh * 4)  # black BGRX canvas
    for dy in range(dh):
        sy = int(dy * h / dh)
        srow = sy * w * ch
        drow = ((dy + yoff) * fbw + xoff) * 4
        for dx in range(dw):
            sp = srow + int(dx * w / dw) * ch
            r, g, b = px[sp], px[sp + 1], px[sp + 2]
            if ch == 4:  # composite alpha over black
                a = px[sp + 3]
                r, g, b = r * a // 255, g * a // 255, b * a // 255
            dp = drow + dx * 4
            fb[dp] = b
            fb[dp + 1] = g
            fb[dp + 2] = r
    open(dst, "wb").write(bytes(fb))
    print("OK: %dx%d PNG -> %dx%d raw (%d bytes)" % (w, h, fbw, fbh, len(fb)))


if __name__ == "__main__":
    main()
