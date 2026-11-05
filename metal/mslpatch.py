import sys,re
p,old,new=sys.argv[1:4]
t=open(p).read()
i=t.index('// ---- MSL\n')+len('// ---- MSL\n')
hdr,msl=t[:i],t[i:]
assert old in msl,(p,old)
msl=msl.replace(old,new)
hdr=re.sub(r'// msl-bytes \d+','// msl-bytes %d'%len(msl.encode()),hdr)
open(p,'w').write(hdr+msl)
