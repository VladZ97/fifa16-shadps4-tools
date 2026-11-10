# markflag.py <metal cache dir> <backup dir> [mark|view]: paints every fragment of a body shader magenta when its
# shadow flag (dword 78 of the flag constant buffer) is non-zero, to see which objects carry the flag.
import sys, re, glob, os, shutil
d, bak = sys.argv[1:3]; mode = sys.argv[3] if len(sys.argv) > 3 else 'mark'
os.makedirs(bak, exist_ok=True)
pat = re.compile(r'\n    bool (_\d+) = ssbo_\d+\.data\[78u \+ [^\n]*\] == 0u;')
n = 0
for f in sorted(glob.glob(d + '/*_fragment_*.metal')):
    t = open(f).read()
    m = re.search(r'// msl-bytes (\d+)\n(// ---- MSL\n)', t)
    if not m: continue
    hdr, msl = t[:m.start()], t[m.end():]
    g = pat.search(msl)
    if not g or 'frag_color0.x = 6.0' in msl or msl.count('\n    return out;') != 1 or 'out.frag_color0' not in msl: continue
    new = msl.replace('\n    return out;', '\n    if (!%s) { out.frag_color0.x = 6.0; out.frag_color0.y = 0.0; out.frag_color0.z = 6.0; }\n    return out;' % g.group(1))
    n += 1
    print(os.path.basename(f)[:16])
    if mode == 'mark':
        if not os.path.exists(bak + '/' + os.path.basename(f)): shutil.copy2(f, bak)
        open(f, 'w').write(hdr + '// msl-bytes %d\n' % len(new.encode()) + m.group(2) + new)
print('patched' if mode == 'mark' else 'would patch', n)
