# usage: mslpatch.py src dst  (reads python 'edit(msl)->msl' from stdin)
import sys,re
src,dst=sys.argv[1:3]; t=open(src).read()
m=re.search(r'// msl-bytes (\d+)\n(// ---- MSL\n)',t); hdr=t[:m.start()]; msl=t[m.end():]
assert len(msl.encode())==int(m.group(1)), (len(msl),m.group(1))
ns={}; exec(sys.stdin.read(),ns); msl=ns['edit'](msl)
open(dst,'w').write(hdr+'// msl-bytes %d\n'%len(msl.encode())+m.group(2)+msl); print('ok',len(msl))
