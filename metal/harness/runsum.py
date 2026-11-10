#!/usr/bin/env python3
"""runsum.py <run dir> [...]: one-run summary of the on-screen cadence, spike classes, latency and
hitch windows from emulator.log (BB_FRAME_STATS=1)."""
import re, sys, collections
def summarize(run):
    hist = collections.Counter(); lat = []; latparts = collections.defaultdict(list)
    cls = collections.Counter(); fstat = []; hc = []; slow = collections.Counter(); busy = []
    pend = None; tot_sp = {'match': [0, 0, 0, 0, 0], 'cut': [0, 0, 0, 0, 0]}; pace = []
    for raw in open(run.rstrip('/') + '/emulator.log', 'rb'):
        line = raw.decode('latin-1')
        if line.startswith('Display intervals'):
            for k, v in re.findall(r'([\d.]+\+?):(\d+)', line.split('):', 1)[1]):
                hist[k] += int(v)
        elif line.startswith('Latency'):
            m = re.search(r'mean of (\d+) frames\): ([\d.]+) ms', line)
            if m and int(m.group(1)) > 100:
                lat.append(float(m.group(2)))
                for name, val in re.findall(r'(host->flip packet|submitted->display) ([\d.]+)', line):
                    latparts[name].append(float(val))
        elif line.startswith('Spike #'):
            g = re.search(r'game ([\d.]+)', line); f = re.search(r'flip ([\d.]+)', line)
            d = re.search(r'display ([\d.]+)', line); dr = re.search(r'(\d+) draws', line)
            h = re.search(r'host copies ([\d.]+)', line)
            if not (g and f and d and dr): continue
            g, f, d, dr = float(g.group(1)), float(f.group(1)), float(d.group(1)), int(dr.group(1))
            if dr < 100 or dr >= 650: continue
            if g >= 70: c = 'game late 70+'
            elif g >= 30: c = 'game late 30-70'
            elif g >= 20: c = 'game late 20-30'
            elif f >= 20: c = 'flip late, game on time'
            else: c = 'display only'
            cls[c] += 1
            if c.startswith('flip late') and h: hc.append(float(h.group(1)))
        elif line.startswith('Spikes (frames later'):
            m = re.search(r'game (\d+), flip (\d+), present (\d+), display (\d+)', line)
            if m: pend = [int(x) for x in m.groups()]
        elif line.startswith('Frame pacing:'):
            m = re.search(r'stddev ([\d.]+) ms, p99 ([\d.]+)', line)
            if m: pace.append((float(m.group(1)), float(m.group(2))))
        elif line.startswith('[FSTAT]'):
            m = re.search(r'fps=([\d.]+) p50=([\d.]+) p99=([\d.]+) max=([\d.]+) hitches=(\d+)', line)
            if m: fstat.append(tuple(float(x) for x in m.groups()))
        elif line.startswith('[SLOWWAIT]') and ' took ' in line:
            slow[line.split(' took ')[0].replace('[SLOWWAIT] ', '')] += 1
        elif line.startswith('Frame stats'):
            m = re.search(r'(\d+) draws/frame.*GPU busy ([\d.]+) ms', line)
            if m and 250 <= int(m.group(1)) < 650: busy.append(float(m.group(2)))
            if m and pend:
                d = int(m.group(1)); key = 'match' if 250 <= d < 650 else ('cut' if d >= 650 else None)
                if key:
                    t = tot_sp[key]; t[0] += pend[0]; t[1] += pend[1]; t[2] += pend[3]; t[3] += 1
                    if pace: t[4] += pace[-1][0]
            pend = None
    tot = sum(hist.values()) or 1
    print('==', run)
    order = ['8.3', '16.7', '25.0', '33.3', '41.7', '45.8+']
    rest = sum(v for k, v in hist.items() if k not in order)
    print('display intervals %: ' + '  '.join(f'{k}:{100*hist[k]/tot:.1f}' for k in order) + f'  other:{100*rest/tot:.1f}  (frames {tot})')
    if lat:
        print(f'latency mean {sum(lat)/len(lat):.1f} ms; ' + '; '.join(f'{k} {sum(v)/len(v):.1f}' for k, v in latparts.items()))
    print('spikes in match (printed): ' + ', '.join(f'{k} {v}' for k, v in sorted(cls.items())))
    if hc:
        hc.sort(); print(f'  flip-late host copies wait: median {hc[len(hc)//2]:.1f} p90 {hc[int(len(hc)*.9)]:.1f}')
    m = [f for f in fstat if f[0] > 40]
    if m:
        print(f'FSTAT windows {len(m)}: mean fps {sum(f[0] for f in m)/len(m):.1f}, mean p99 {sum(f[2] for f in m)/len(m):.1f}, '
              f'hitches {int(sum(f[4] for f in m))}, windows with hitch {sum(1 for f in m if f[4])}, max {max(f[3] for f in m):.0f}')
    for key, t in tot_sp.items():
        if t[3]: print(f'late frames per 5 s window, {key} ({t[3]} windows): game {t[0]/t[3]:.1f}, flip {t[1]/t[3]:.1f}, display {t[2]/t[3]:.1f}; game pacing stddev {t[4]/t[3]:.2f} ms')
    if busy: print(f'GPU busy in match: {sum(busy)/len(busy):.2f} ms/frame over {len(busy)} windows')
    if slow: print('slow waits: ' + ', '.join(f'{k} {v}' for k, v in slow.items()))
for r in sys.argv[1:]: summarize(r)
