G = "2.5"
def edit(m):
    out = []
    for c, v in (("x", "_1083"), ("y", "_1084"), ("z", "_1085")):
        a = "    out.frag_color0.%s = ((as_type<uint>(%s) & 2147483647u) > 2139095040u) ? 0.0 : fast::clamp(%s, 0.0, 64512.0);\n" % (c, v, v)
        assert m.count(a) == 1, c
        m = m.replace(a, "    out.frag_color0.%s = ((as_type<uint>(%s) & 2147483647u) > 2139095040u) ? 0.0 : fast::clamp(%s * %s, 0.0, 64512.0);\n" % (c, v, v, G))
    return m
