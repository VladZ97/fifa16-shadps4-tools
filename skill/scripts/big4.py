#!/usr/bin/env python3
"""List or extract entries of EA BIG4 archives (FIFA PS4/PC .big files), decoding the
chunkzip (deflate) and chunklzma (LZMA) containers the PS4 build wraps assets in.

  big4.py list    <file.big> [substring]        list entry names (optionally filtered)
  big4.py extract <file.big> <entry name> <out> extract one entry, decoded
  big4.py names   <game folder>                 dump every entry name of every .big to stdout
"""
import struct, sys, os, zlib, lzma

def entries(path):
    with open(path, "rb") as f:
        hdr = f.read(16)
        if hdr[:4] != b"BIG4": raise ValueError("not BIG4")
        count, hsize = struct.unpack(">II", hdr[8:16]); data = f.read(hsize - 16)
    i, out = 0, []
    for _ in range(count):
        off, sz = struct.unpack(">II", data[i:i + 8]); i += 8
        j = data.index(b"\0", i); out.append((data[i:j].decode("latin1"), off, sz)); i = j + 1
    return out

def decode(raw):
    if raw.startswith(b"chunkzip"):   # 48-byte header: usize BE at [12:16], chunk size BE at [16:20];
        # then raw-deflate chunks, each preceded by a variable zero-padded header ending in {csize BE, 1}
        usize, csize = struct.unpack(">II", raw[12:20])
        out = b""; rest = raw[48:]
        while len(out) < usize and rest:
            want = min(csize, usize - len(out)); found = None
            for skip in range(0, 64):
                try:
                    d = zlib.decompressobj(-15); piece = d.decompress(rest[skip:])
                except zlib.error:
                    continue
                if len(piece) == want: found = (piece, d.unused_data); break
            if not found: raise ValueError(f"chunkzip: cannot find chunk after {len(out)} bytes")
            out += found[0]; rest = found[1]
        return out
    if raw.startswith(b"chunlzma"):   # LZMA1 chunks of `csize` bytes each; chunk boundaries are found by trial
        usize, csize = struct.unpack(">II", raw[12:20])
        filt = [{"id": lzma.FILTER_LZMA1, "dict_size": csize, "lc": 3, "lp": 0, "pb": 2}]
        def try_chunk(start, want):
            dec = lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=filt); out = b""; pos = start
            while len(out) < want and pos < len(raw):
                piece = raw[pos:pos + 256]; pos += 256
                out += dec.decompress(piece, max_length=want - len(out))
                while len(out) < want and not dec.needs_input:
                    out += dec.decompress(b"", max_length=want - len(out))
            return (out, pos) if len(out) == want else (None, pos)
        out, pos = b"", 0x35
        while len(out) < usize:
            want = min(csize, usize - len(out)); found = None
            for start in range(pos - 300, pos + 400):
                if start < 0x30 or start >= len(raw): continue
                try:
                    o, end = try_chunk(start, want)
                except lzma.LZMAError:
                    continue
                if o is not None: found = (o, end); break
            if not found: raise ValueError(f"chunklzma: could not locate chunk at ~{pos:#x}")
            out += found[0]; pos = found[1]
        return out
    return raw

def main():
    a = sys.argv[1:]
    if not a: print(__doc__); return
    if a[0] == "list":
        for n, o, s in entries(a[1]):
            if len(a) < 3 or a[2].lower() in n.lower(): print(f"{s:10d} {n}")
    elif a[0] == "extract":
        for n, o, s in entries(a[1]):
            if n.lower() == a[2].lower():
                with open(a[1], "rb") as f: f.seek(o); raw = f.read(s)
                open(a[3], "wb").write(decode(raw)); print("wrote", a[3]); return
        sys.exit("entry not found")
    elif a[0] == "names":
        for big in sorted(os.listdir(a[1])):
            if big.endswith(".big"):
                try:
                    for n, o, s in entries(os.path.join(a[1], big)): print(n)
                except Exception: pass

if __name__ == "__main__": main()
