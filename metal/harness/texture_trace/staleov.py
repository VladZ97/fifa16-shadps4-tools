import sys,re
log=sys.argv[1]
stale=[]; hw=[]
for l in open(log,errors='replace'):
    if l.startswith('[AUDIT] stale image'):
        m=re.search(r'image (0x[0-9a-f]+) (\d+x\d+) (\S+) mips (\d+).*tracked (0x[0-9a-f]+)\.\.(0x[0-9a-f]+)',l)
        stale.append((int(m.group(1),16),int(m.group(6),16),m.group(2),m.group(3)))
    elif l.startswith('[HOSTW]') and 'totals' not in l:
        m=re.search(r'(0x[0-9a-f]+)\+(\d+)',l)
        if m: hw.append((int(m.group(1),16),int(m.group(2)),l.strip()))
for a,e,dim,fmt in stale:
    hits=[h for h in hw if h[0]<e and a<h[0]+h[1]]
    print(hex(a),dim,fmt,'size',e-a,'hostw overlaps',len(hits))
    for h in hits[:2]: print('    ',h[2][:170])
