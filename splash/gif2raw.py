#!/usr/bin/env python3
"""Convert an animated GIF into raw BGRX framebuffer frames.

Pure stdlib so it runs on ROCKNIX's bundled python3. Each frame is
scaled (nearest-neighbor, aspect preserved), centered on black, and
written to OUTDIR/frame_NNNN.raw. Per-frame delays (seconds) go to
OUTDIR/delays.txt, one line per frame.

Usage: gif2raw.py input.gif OUTDIR WIDTH HEIGHT
"""
import os
import shutil
import struct
import sys

MAX_FRAMES = 48  # keep conversion time and storage sane


def fail(msg):
    print("ERROR: %s" % msg)
    sys.exit(1)


def lzw_decode(data, min_code_size, expected):
    clear = 1 << min_code_size
    end = clear + 1
    base = [bytes([i]) for i in range(clear)] + [b"", b""]
    table = list(base)
    code_size = min_code_size + 1
    buf = bits = 0
    pos = 0
    prev = None
    out = bytearray()
    while len(out) < expected:
        while bits < code_size:
            if pos >= len(data):
                return bytes(out)
            buf |= data[pos] << bits
            bits += 8
            pos += 1
        code = buf & ((1 << code_size) - 1)
        buf >>= code_size
        bits -= code_size
        if code == clear:
            table = list(base)
            code_size = min_code_size + 1
            prev = None
            continue
        if code == end:
            break
        if prev is None:
            out += table[code]
            prev = code
            continue
        if code < len(table):
            entry = table[code]
            if len(table) < 4096:
                table.append(table[prev] + entry[:1])
        elif code == len(table):
            entry = table[prev] + table[prev][:1]
            table.append(entry)
        else:
            fail("corrupt GIF (bad LZW code)")
        out += entry
        prev = code
        if len(table) == (1 << code_size) and code_size < 12:
            code_size += 1
    return bytes(out)


def subblocks(data, pos):
    chunks = []
    while data[pos] != 0:
        n = data[pos]
        chunks.append(data[pos + 1:pos + 1 + n])
        pos += 1 + n
    return b"".join(chunks), pos + 1


def deinterlace(idx, w, h):
    rows = []
    for start, step in ((0, 8), (4, 8), (2, 4), (1, 2)):
        rows.extend(range(start, h, step))
    out = bytearray(w * h)
    for src, dst in enumerate(rows):
        out[dst * w:(dst + 1) * w] = idx[src * w:(src + 1) * w]
    return bytes(out)


def parse_gif(path):
    """Yield (rgba_canvas_bytes, delay_seconds) per frame."""
    data = open(path, "rb").read()
    if data[:6] not in (b"GIF87a", b"GIF89a"):
        fail("%s is not a GIF file" % path)
    width, height = struct.unpack("<HH", data[6:10])
    flags = data[10]
    pos = 13
    gct = None
    if flags & 0x80:
        n = 2 << (flags & 7)
        gct = data[pos:pos + 3 * n]
        pos += 3 * n

    canvas = bytearray(width * height * 4)  # RGBA, transparent black
    frames = []
    delay = 0.1
    transparent = None
    disposal = 0

    while pos < len(data):
        block = data[pos]
        if block == 0x3B:  # trailer
            break
        if block == 0x21:  # extension
            label = data[pos + 1]
            pos += 2
            if label == 0xF9:  # graphic control
                packed = data[pos + 1]
                cs = struct.unpack("<H", data[pos + 2:pos + 4])[0]
                delay = max(cs, 2) / 100.0
                transparent = data[pos + 4] if packed & 1 else None
                disposal = (packed >> 2) & 7
            _, pos = subblocks(data, pos + 1 + data[pos]) \
                if label == 0xF9 else subblocks(data, pos)
            continue
        if block != 0x2C:
            fail("unexpected GIF block 0x%02x" % block)

        # image descriptor
        fx, fy, fw, fh = struct.unpack("<HHHH", data[pos + 1:pos + 9])
        lflags = data[pos + 9]
        pos += 10
        ct = gct
        if lflags & 0x80:
            n = 2 << (lflags & 7)
            ct = data[pos:pos + 3 * n]
            pos += 3 * n
        if ct is None:
            fail("GIF frame has no color table")
        min_code = data[pos]
        lzw, pos = subblocks(data, pos + 1)
        idx = lzw_decode(lzw, min_code, fw * fh)
        if len(idx) < fw * fh:
            idx += bytes(fw * fh - len(idx))
        if lflags & 0x40:
            idx = deinterlace(idx, fw, fh)

        snapshot = bytes(canvas) if disposal == 3 else None
        for y in range(fh):
            crow = ((fy + y) * width + fx) * 4
            srow = y * fw
            for x in range(fw):
                ci = idx[srow + x]
                if ci == transparent:
                    continue
                cp = crow + x * 4
                c = ci * 3
                canvas[cp] = ct[c]
                canvas[cp + 1] = ct[c + 1]
                canvas[cp + 2] = ct[c + 2]
                canvas[cp + 3] = 255
        frames.append((bytes(canvas), delay))
        if len(frames) >= MAX_FRAMES:
            print("note: GIF has more frames, keeping first %d" % MAX_FRAMES)
            break

        # dispose for next frame
        if disposal == 2:
            for y in range(fh):
                cp = ((fy + y) * width + fx) * 4
                canvas[cp:cp + fw * 4] = bytes(fw * 4)
        elif disposal == 3 and snapshot is not None:
            canvas = bytearray(snapshot)
    return width, height, frames


def main():
    if len(sys.argv) != 5:
        fail("usage: gif2raw.py input.gif OUTDIR WIDTH HEIGHT")
    src, outdir = sys.argv[1], sys.argv[2]
    fbw, fbh = int(sys.argv[3]), int(sys.argv[4])

    w, h, frames = parse_gif(src)
    if not frames:
        fail("no frames decoded from %s" % src)
    print("decoded %d frames of %dx%d" % (len(frames), w, h))

    scale = min(fbw / w, fbh / h, 1.0)
    dw, dh = max(1, int(w * scale)), max(1, int(h * scale))
    xoff, yoff = (fbw - dw) // 2, (fbh - dh) // 2
    xmap = [int(dx * w / dw) * 4 for dx in range(dw)]
    ymap = [int(dy * h / dh) for dy in range(dh)]

    if os.path.isdir(outdir):
        shutil.rmtree(outdir)
    os.makedirs(outdir)

    delays = []
    for n, (rgba, delay) in enumerate(frames):
        fb = bytearray(fbw * fbh * 4)  # black BGRX canvas
        for dy in range(dh):
            srow = ymap[dy] * w * 4
            drow = ((dy + yoff) * fbw + xoff) * 4
            for dx in range(dw):
                sp = srow + xmap[dx]
                a = rgba[sp + 3]
                if a == 0:
                    continue
                dp = drow + dx * 4
                fb[dp] = rgba[sp + 2] * a // 255      # B
                fb[dp + 1] = rgba[sp + 1] * a // 255  # G
                fb[dp + 2] = rgba[sp] * a // 255      # R
        with open(os.path.join(outdir, "frame_%04d.raw" % (n + 1)), "wb") as f:
            f.write(bytes(fb))
        delays.append(delay)
        if (n + 1) % 10 == 0:
            print("converted %d/%d frames..." % (n + 1, len(frames)))

    with open(os.path.join(outdir, "delays.txt"), "w") as f:
        f.write("".join("%.3f\n" % d for d in delays))
    print("OK: %d frames -> %s (%dx%d)" % (len(frames), outdir, fbw, fbh))


if __name__ == "__main__":
    main()
