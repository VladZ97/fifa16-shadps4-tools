import re,sys,collections
f=sys.argv[1]
ev=collections.OrderedDict()
tgt=set()
for i,l in enumerate(open(f,errors='replace'),1):
    if not l.startswith('[SEQ]'): continue
    m=re.search(r'0x(4[0-9a-f]{8})',l)
    if not m: continue
    a=m.group(1)
    if ' bind 52abaae0 img1' in l: tgt.add(a)
    w=l.split()
    k=w[1]
    if k=='bind': k='B:'+w[2][:4]+w[3]+('w' if ' w1 ' in l else 'r')+re.search(r'L(\d)',l).group(1)
    elif k=='download': k='D'+re.search(r'sync=(\d)',l).group(1)+('L' if re.search(r'landed [1-9]',l) else '')
    elif k=='upload': k='U'+re.search(r'fl (0x[0-9a-f]+) mips (0x[0-9a-f]+)',l).group(1)[2:]+'/'+re.search(r'mips 0x([0-9a-f]+)',l).group(1)
    elif k=='expand': k='X'+w[2][0]+re.search(r'lv(\d)',l).group(1)+('bc' if 'Bc' in l else '')
    elif k=='wb-land': k='WB'+re.search(r'written=(\d)',l).group(1)
    elif k=='delete': k='del'+('P' if 'pending' in l else '')
    elif k=='create': k='C'+('bc' if 'Bc' in l else '')+re.search(r'lv(\d)',l).group(1)
    elif k=='cpu-write': k='CW'
    elif k=='direct-land': k='DL'
    ev.setdefault(a,[]).append(k)
sigs=collections.defaultdict(list)
for a in tgt:
    sigs[' '.join(ev[a])].append(a)
for s,al in sorted(sigs.items(),key=lambda x:-len(x[1])):
    print(len(al),' '.join(al[:6]))
    print('   ',s[:1500])
