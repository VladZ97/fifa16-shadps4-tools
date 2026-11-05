import re
def edit(m):
    pat = r'float (_\d+) = 0\.693147182464599609375 \* precise::log2\(1\.9999999494757503271102905273438e-05 \+ select\((_\d+), fma\(\2, float4\(2\.0\), float4\(-1\.0\)\), bool4\(\(push_data\.depth_remap & 1u\) != 0u\)\)\.w\);'
    hits = list(re.finditer(pat, m)); assert len(hits) == 2, len(hits)
    a, b = hits
    out = m[:a.start()] + 'float %s = -1.0;' % a.group(1) + m[a.end():b.start()] + 'float %s = 0.693147182464599609375 * precise::log2(1.9999999494757503271102905273438e-05 + 0.0139);' % b.group(1) + m[b.end():]
    return out
