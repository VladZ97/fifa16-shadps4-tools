import re, sys
for f in sys.argv[1:]:
    rows = []
    for l in open(f, 'rb'):
        if b'Frame stats' not in l: continue
        l = l.decode('latin1')
        m = re.search(r'Frame stats: ([\d.]+) FPS, worst frame ([\d.]+) ms.*?(\d+) write faults/s.*?GPU thread ([\d.]+) us/draw, (\d+) draws/frame, idle ([\d.]+)%.*?host copies ([\d.]+)% \((\d+)/frame\).*?GPU busy ([\d.]+) ms', l)
        if m: rows.append([float(x) for x in m.groups()])
    mt = [r for r in rows if 250 <= r[4] <= 650 and r[0] > 50]
    if not mt: print(f[-24:], 'no match rows'); continue
    av = lambda i: sum(r[i] for r in mt) / len(mt)
    print('%s match rows %d: fps %.1f worst %.1f faults/s %.0f us/draw %.2f draws %.0f idle %.1f hostcopies %.2f%% (%.1f/frame) gpu busy %.2f' % (f[-20:], len(mt), av(0), av(1), av(2), av(3), av(4), av(5), av(6), av(7), av(8)))
