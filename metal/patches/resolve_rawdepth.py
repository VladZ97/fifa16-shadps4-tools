import re
def edit(m):
    # output the raw sample-0 depth fetch at the fragment position into frag_color1 (R32)
    a = "    out.frag_color1.x = "
    assert m.count(a) == 1, m.count(a)
    i = m.index(a); j = m.index("\n", i)
    m = m[:i] + "    out.frag_color1.x = float(fs_img0.read(uint2(gl_FragCoord.xy), 0u));" + m[j:]
    return m
