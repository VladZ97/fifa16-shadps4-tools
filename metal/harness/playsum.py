#!/usr/bin/env python3
"""Per-phase frame quality of a run: 'play' = 5 s windows after the first cutscene window
(>= 600 draws) with 250-650 draws (the match itself; menus before it are excluded),
'cut' = windows with >= 650 draws after it, 'menu' = everything before."""
import re, sys, collections
def main(run):
    run = run.rstrip('/')
    seen_cut = False
    acc = {k: dict(n=0, game=0, flip=0, disp=0, lat=0.0, latn=0, hist=collections.Counter(), hitch=0, p99=0.0, fstat=0, worst=0.0, gpu=0.0)
           for k in ('menu', 'play', 'cut')}
    pend = dict(sp=None, hist=None, lat=None, fstat=[])
    for raw in open(run + '/emulator.log', 'rb'):
        l = raw.decode('latin-1')
        if l.startswith('Spikes (frames later'):
            m = re.search(r'game (\d+), flip (\d+), present (\d+), display (\d+)', l)
            if m: pend['sp'] = [int(x) for x in m.groups()]
        elif l.startswith('Display intervals'):
            pend['hist'] = [(k, int(v)) for k, v in re.findall(r'([\d.]+\+?):(\d+)', l.split('):', 1)[1])]
        elif l.startswith('Latency'):
            m = re.search(r'frames\): ([\d.]+) ms', l)
            if m: pend['lat'] = float(m.group(1))
        elif l.startswith('[FSTAT]'):
            m = re.search(r'p99=([\d.]+) max=([\d.]+) hitches=(\d+) gpu=([\d.]+)', l)
            if m: pend['fstat'].append(tuple(float(x) for x in m.groups()))
        elif l.startswith('Frame stats'):
            m = re.search(r'(\d+) draws/frame', l)
            if not m: continue
            d = int(m.group(1))
            if d >= 600: seen_cut = True
            key = 'menu' if not seen_cut else ('cut' if d >= 650 else ('play' if d >= 250 else None))
            if key:
                a = acc[key]; a['n'] += 1
                if pend['sp']: a['game'] += pend['sp'][0]; a['flip'] += pend['sp'][1]; a['disp'] += pend['sp'][3]
                if pend['hist']:
                    for k, v in pend['hist']: a['hist'][k] += v
                if pend['lat'] is not None: a['lat'] += pend['lat']; a['latn'] += 1
                for p99, mx, h, g in pend['fstat']:
                    a['hitch'] += int(h); a['p99'] += p99; a['fstat'] += 1; a['worst'] = max(a['worst'], mx); a['gpu'] += g
            pend = dict(sp=None, hist=None, lat=None, fstat=[])
    print('==', run.split('/')[-1])
    for key in ('play', 'cut', 'menu'):
        a = acc[key]
        if not a['n']: continue
        t = sum(a['hist'].values()) or 1
        h = a['hist']; pct = lambda *ks: 100.0 * sum(h[k] for k in ks) / t
        print(f"  {key:4s} {a['n']:3d} windows: late per 5 s: game {a['game']/a['n']:5.1f} flip {a['flip']/a['n']:5.1f} display {a['disp']/a['n']:5.1f} | "
              f"shown 16.7 ms {pct('16.7'):4.1f}%, 8.3-12.5 {pct('8.3','12.5'):4.1f}%, 20.8-29.2 {pct('20.8','25.0','29.2'):4.1f}%, 33+ {pct('33.3','37.5','41.7','45.8+'):3.1f}% | "
              f"latency {a['lat']/max(a['latn'],1):4.1f} ms | p99 {a['p99']/max(a['fstat'],1):4.1f} worst {a['worst']:5.1f} hitches {a['hitch']} gpu {a['gpu']/max(a['fstat'],1):4.1f}")
for r in sys.argv[1:]: main(r)
