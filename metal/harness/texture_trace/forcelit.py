# forcelit.py <metal cache dir> <backup dir> [mode]: patches every cached fragment shader that does FIFA's manual
# shadow-map compare (sample.x > receiver depth). mode lit: compare always passes; mode view: nothing (dry run).
import sys, re, glob, os, shutil
d, bak = sys.argv[1:3]; mode = sys.argv[3] if len(sys.argv) > 3 else 'lit'
os.makedirs(bak, exist_ok=True)
pat = re.compile(r'= as_type<uint>\(float\(select\(_\d+, fma\(_\d+, float4\(2\.0\), float4\(-1\.0\)\), bool4\(\(push_data\.depth_remap & \d+u\) != 0u\)\)\.x > [^\n]*\)\);')
n = 0
for f in sorted(glob.glob(d + '/*_fragment_*.metal')):
    t = open(f).read()
    m = re.search(r'// msl-bytes (\d+)\n(// ---- MSL\n)', t)
    if not m: continue
    hdr, msl = t[:m.start()], t[m.end():]
    new, k = pat.subn('= 1065353216u;', msl)
    if not k: continue
    n += 1
    print(os.path.basename(f)[:16], k)
    if mode == 'lit':
        if not os.path.exists(bak + '/' + os.path.basename(f)): shutil.copy2(f, bak)
        open(f, 'w').write(hdr + '// msl-bytes %d\n' % len(new.encode()) + m.group(2) + new)
print('patched' if mode == 'lit' else 'would patch', n)
