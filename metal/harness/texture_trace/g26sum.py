import sys, re, collections
log = sys.argv[1]
dma = []; clob = []; clob_tot = None; audit = []; apass = None
for l in open(log, errors='replace'):
    if l.startswith('[DMA]'): dma.append(l.strip())
    elif l.startswith('[CLOB] totals'): clob_tot = l.strip()
    elif l.startswith('[CLOB]'): clob.append(l.strip())
    elif l.startswith('[AUDIT] stale'): audit.append(l.strip())
    elif l.startswith('[AUDIT] pass'): apass = l.strip()
print('DMA distinct copies >= 64 KB:', len(dma))
by = collections.Counter()
for l in dma:
    m = re.search(r'copy (\S+) <- (\S+) (\d+) bytes gds (\S+) dst gpu (\d) src gpu (\d) src image (\d)', l)
    if m: by[(m.group(4), m.group(5), m.group(6), m.group(7))] += int(m.group(3))
for k, v in by.most_common(): print('  gds %s dst gpu %s src gpu %s src image %s: %.1f MB' % (*k, v / 1e6))
for l in dma[:int(sys.argv[2]) if len(sys.argv) > 2 else 12]: print('  ' + l[:170])
print('CLOB lines:', len(clob), '| cpu image:', sum('cpu image 1' in l for l in clob))
for l in [l for l in clob if 'cpu image 1' in l][:8] + clob[:4]: print('  ' + l[:200])
print(clob_tot)
print('AUDIT stale:', len(audit))
for l in audit[:10]: print('  ' + l[:260])
print(apass)
