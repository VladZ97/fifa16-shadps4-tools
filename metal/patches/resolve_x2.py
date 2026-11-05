def edit(m):
    n = 0
    for c in ("x", "y", "z"):
        a = "    out.frag_color0.%s = " % c
        assert m.count(a) == 1, (c, m.count(a))
        i = m.index(a); j = m.index(";\n", i)
        expr = m[i + len(a):j]
        m = m[:i] + a + "4.0 * (" + expr + ")" + m[j:]
        n += 1
    assert n == 3
    return m
