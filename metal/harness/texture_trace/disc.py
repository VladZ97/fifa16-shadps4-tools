# disc.py <seq.txt>...: trace discriminators for the face-texture pipeline.
# compress steps (a7c5bd5f) whose source level is not 4x the destination level; mipkeep / stale-land counts
import re, sys
pat = re.compile(r'bind a7c5bd5f img(\d) id (\d+) (0x[0-9a-f]+) \S+ (\d+)x(\d+) lv(\d+) .* L(\d+)\+')
for fn in sys.argv[1:]:
    src = None; steps = bad = keep = stale = 0; badl = []
    for i, l in enumerate(open(fn, errors='replace'), 1):
        if 'mipkeep' in l: keep += 1
        elif 'stale-land' in l:
            stale += 1; badl.append((i, l.strip()[:150]))
        elif 'bind a7c5bd5f' in l:
            m = pat.search(l)
            if not m: continue
            k, w, lv = int(m.group(1)), int(m.group(4)), int(m.group(7))
            if k == 0: src = (w >> lv, i, l)
            elif k == 1 and src:
                steps += 1
                if src[0] != 4 * (w >> lv):
                    bad += 1; badl.append((src[1], src[2].strip()[:150]))
                src = None
    print(fn, 'compress steps', steps, 'wrong source level', bad, 'mipkeep', keep, 'stale-land', stale)
    for b in badl[:6]: print('   ', b[0], b[1])
