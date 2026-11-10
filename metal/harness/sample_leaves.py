import sys,re,collections
f,a,b=sys.argv[1],int(sys.argv[2]),int(sys.argv[3])
rows=[]
for i,l in enumerate(open(f,errors='replace')):
    if i+1<a or i+1>b: continue
    m=re.match(r'^([ +!:|]*)(\d+) (.*)',l.rstrip())
    if m: rows.append((len(m.group(1)),int(m.group(2)),m.group(3)))
def nm(t):
    if t.startswith('???'):
        mm=re.search(r'\[0x([0-9a-f]+)\]',t); ad=int(mm.group(1),16) if mm else 0
        if 0x400000000<=ad<0x500000000: return 'GAME'
        if 0x700000000000<=ad<0x700010000000: return 'emu+%x'%(ad-0x700000000000)
        return 'sys?'
    return re.sub(r'\s+\(in ([^)]*)\).*','',t)
leaf=collections.Counter(); stack=[]
for i,(d,n,t) in enumerate(rows):
    while stack and stack[-1][0]>=d: stack.pop()
    stack.append((d,nm(t)))
    kids=0; j=i+1
    while j<len(rows) and rows[j][0]>d:
        if rows[j][0]==d+2: kids+=rows[j][1]
        j+=1
    own=n-kids
    if own>0:
        names=[x[1] for x in stack]
        # collapse: last GAME-or-emu frame + everything after
        k=len(names)-1
        while k>0 and names[k] in('sys?',) : k-=1
        key=' > '.join(names[max(k-1,0):][:5])
        if names[-1]=='GAME': key='GAME (running)'
        leaf[key]+=own
tot=sum(leaf.values())
print('total',tot)
for k,v in leaf.most_common(int(sys.argv[4]) if len(sys.argv)>4 else 12): print(f'{v:5d} {100*v/tot:5.1f}%  {k[:150]}')
