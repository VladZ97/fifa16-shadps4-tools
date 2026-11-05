def edit(m):
    a = "    out.frag_color0.x = ((as_type<uint>(_1083) & 2147483647u) > 2139095040u) ? 0.0 : fast::clamp(_1083, 0.0, 64512.0);\n"
    assert m.count(a) == 1
    probe = "    float3 _probe = fs_img3.sample(fs_samp3, float3((_209 < 0.5) ? 0.25 : 0.75)).xyz;\n"
    m = m.replace(a, probe + "    out.frag_color0.x = _probe.x;\n")
    for c, v in (("y", "_1084"), ("z", "_1085")):
        b = "    out.frag_color0.%s = ((as_type<uint>(%s) & 2147483647u) > 2139095040u) ? 0.0 : fast::clamp(%s, 0.0, 64512.0);\n" % (c, v, v)
        assert m.count(b) == 1, c
        m = m.replace(b, "    out.frag_color0.%s = _probe.%s;\n" % (c, c))
    return m
