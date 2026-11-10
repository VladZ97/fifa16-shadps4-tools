import sys, re, functools
lines = open(sys.argv[1]).read().split('\n')
defs = {}; stores = {}
for l in lines:
    m = re.match(r'\s*(%\w+) = (\w+) (.*)', l)
    if m: defs[m.group(1)] = (m.group(2), [x for x in m.group(3).split() if x.startswith('%')])
    m = re.match(r'\s*OpStore (%\w+) (%\w+)', l)
    if m: stores.setdefault(m.group(1), []).append(m.group(2))
sys.setrecursionlimit(20000)
@functools.lru_cache(None)
def dep(v):
    if v not in defs: return frozenset()
    op, a = defs[v]
    if op in ('OpImageFetch', 'OpImageSampleExplicitLod', 'OpImageSampleImplicitLod'):
        return frozenset(['IMG@' + v])
    if op == 'OpLoad':
        if len(a) > 1 and ('attr' in a[1]): return frozenset([a[1]])
        return dep(a[1]) if len(a) > 1 else frozenset()
    if op == 'OpAccessChain':
        if 'attr' in a[1]: return frozenset([a[1]])
        if 'ssbo' in a[1] or 'push' in a[1]: return frozenset(['const'])
        return frozenset()
    if op == 'OpVariable': return frozenset()
    s = set()
    for x in a[1:]: s |= dep(x)
    return frozenset(s)
for tgt in sys.argv[2:]:
    for ptr, vals in stores.items():
        root = ptr
        if ptr in defs and defs[ptr][0] == 'OpAccessChain': root = defs[ptr][1][1]
        if tgt in root:
            for v in vals:
                print(root, ptr, '<=', sorted(dep(v)))
